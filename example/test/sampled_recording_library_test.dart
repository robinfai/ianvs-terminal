import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

final class _Files implements RecordingFileApi {
  final List<String> calls = [];
  Completer<void>? reading;
  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) async {
    calls.add(operation);
    if (operation == 'seek') {
      await reading?.future;
      return {'screen': null};
    }
    final metadata =
        (jsonDecode(
                  await File(
                    '${payload['bundle_path']}/fixture.json',
                  ).readAsString(),
                )
                as Map)
            .cast<String, Object?>();
    if (operation == 'metadata') return {'metadata': metadata};
    if (operation != 'inspect') throw StateError(operation);
    return {
      'metadata': metadata,
      'summary': {
        'record_count': 2,
        'visual_count': 1,
        'semantic_count': 1,
        'duration_micros': 1000000,
      },
      'source_bytes': 200,
      'verified_bytes': 200,
      'completion': 'interrupted',
      'error': null,
    };
  }
}

final class _Backend implements PtySessionRequestV1Backend {
  String phase = 'capturing';
  bool settled = false;
  bool loseStart = false;
  bool loseRelease = false;
  final List<String> calls = [];
  @override
  String? requestSessionV1Json(String sessionId, String json) {
    final request = jsonDecode(json) as Map;
    final operation = request['operation'] as String;
    final input = request['payload'] as Map;
    calls.add(operation);
    if ((loseStart && operation.endsWith('_start')) ||
        (loseRelease && operation.endsWith('_release'))) {
      return null;
    }
    const counts = {
      'record_count': 0,
      'visual_count': 0,
      'semantic_count': 0,
      'duration_micros': 0,
    };
    return jsonEncode({
      'schema_version': 1,
      'contract': 'ianvs-session-response-v1',
      'request_id': request['request_id'],
      'session_id': sessionId,
      'operation': operation,
      'ok': true,
      'timestamp_micros': 1,
      'payload': {
        'ok': true,
        'schema_version': 2,
        'capture_id': input['capture_id'],
        'bundle_path': input['bundle_path'],
        'session_id': sessionId,
        'phase': phase,
        'settled': settled,
        'stop_requested': operation.endsWith('_stop'),
        'written': counts,
        'committed': counts,
        'error': phase == 'failed' ? 'disk full' : null,
        if (operation.endsWith('_release')) 'released': true,
      },
    });
  }
}

Future<void> _seed(
  Directory root,
  String id, {
  bool keep = false,
  String state = 'finished',
  int ageDays = 1,
}) async {
  final path = '${root.path}/$id.trailrec';
  await Directory(path).create(recursive: true);
  final date = DateTime.now().toUtc().subtract(Duration(days: ageDays));
  await File('$path/fixture.json').writeAsString(
    jsonEncode({
      'recording_id': id,
      'title': 'fixture $id',
      'hostname': 'host',
      'started_at_unix_millis': date.millisecondsSinceEpoch,
    }),
  );
  await File('$path/payload').writeAsBytes(List.filled(100, 42));
  final entry = SampledRecordingEntry(
    id: id,
    path: path,
    displayName: 'fixture $id',
    createdAtUtc: date,
    duration: const Duration(seconds: 1),
    state: state,
    sessionId: null,
    keep: keep,
  );
  await File(
    '${root.path}/entries/$id.json',
  ).writeAsString(jsonEncode(entry.toJson()));
}

void main() {
  late Directory root;
  late _Files files;
  late SampledRecordingLibrary library;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sampled-library-test-');
    files = _Files();
    library = SampledRecordingLibrary(
      files: files,
      directoryResolver: () async => root,
      maximumAge: const Duration(days: 7),
    );
    root = await library.ensureRecordingDirectory();
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'reservation persists before dispatch and cannot be recovered by a competing owner',
    () async {
      final claim = await library.reserve(
        sessionId: '1',
        sessionEpoch: 9,
        title: 'work',
      );
      final stored =
          jsonDecode(
                await File(
                  '${root.path}/entries/${claim.entry.id}.json',
                ).readAsString(),
              )
              as Map;
      expect(stored['state'], 'reserved');
      final other = SampledRecordingLibrary(
        files: files,
        directoryResolver: () async => root,
      );
      expect((await other.recover()).busy, 1);
      await expectLater(
        other.deleteRecording(claim.entry.path),
        throwsA(isA<RecordingLibraryBusy>()),
      );
      await library.abandonUndispatched(claim);
      expect(await library.listRecordings(), isEmpty);
    },
  );

  test(
    'lost start and failed but unsettled writers retain their file claim',
    () async {
      final claim = await library.reserve(
        sessionId: '1',
        sessionEpoch: 1,
        title: 'work',
      );
      final backend = _Backend()..loseStart = true;
      final client = SampledRecordingCaptureClient(backend: backend);
      await expectLater(
        library.start(claim, client),
        throwsA(isA<SampledCaptureRequestException>()),
      );
      expect(claim.dispatched, isTrue);
      await expectLater(library.abandonUndispatched(claim), throwsStateError);
      expect((await library.recover()).busy, 1);
      backend
        ..loseStart = false
        ..phase = 'failed';
      await library.update(claim, client.status(claim.handle));
      expect(claim.entry.isActive, isTrue);
      await expectLater(
        library.deleteRecording(claim.entry.path),
        throwsA(isA<RecordingLibraryBusy>()),
      );
      backend.settled = true;
      await library.finish(claim, client);
      expect(library.activeClaims, isEmpty);
      expect((await library.listRecordings()).single.state, 'interrupted');
    },
  );

  test(
    'concurrent finish shares stop and a lost cleanup response still releases a settled file',
    () async {
      final claim = await library.reserve(
        sessionId: '1',
        sessionEpoch: 1,
        title: 'work',
      );
      final backend = _Backend();
      final client = SampledRecordingCaptureClient(backend: backend);
      await library.start(claim, client);
      backend
        ..phase = 'finished'
        ..settled = true
        ..loseRelease = true;
      await Future.wait([
        library.finish(claim, client),
        library.finish(claim, client),
      ]);
      expect(backend.calls.where((c) => c.endsWith('_stop')).length, 1);
      expect(library.activeClaims, isEmpty);
      await library.deleteRecording(claim.entry.path);
      expect(await library.listRecordings(), isEmpty);
    },
  );

  test(
    'one corrupt or future manifest does not hide or rewrite other recoverable records',
    () async {
      final bad = 'a' * 32;
      final good = 'b' * 32;
      await _seed(root, bad);
      final manifest = File('${root.path}/entries/$bad.json');
      final raw = jsonDecode(await manifest.readAsString()) as Map;
      raw['schema_version'] = 2.0;
      final original = jsonEncode(raw);
      await manifest.writeAsString(original);
      await _seed(root, good, state: 'capturing');
      final result = await library.recover();
      expect(result.recovered, 1);
      expect(result.errors.length, 1);
      expect(await manifest.readAsString(), original);
      final entries = await library.listRecordings();
      expect(entries.length, 2);
      expect(entries.firstWhere((e) => e.id == bad).isReadable, isFalse);
      expect(entries.firstWhere((e) => e.id == good).state, 'interrupted');
      await library.applyRetention();
      expect(await manifest.readAsString(), original);
    },
  );

  test(
    'retention removes old ordinary files while preserving Keep, active and legacy data',
    () async {
      final old = 'a' * 32;
      final keep = 'b' * 32;
      final active = 'c' * 32;
      await _seed(root, old, ageDays: 30);
      await _seed(root, keep, ageDays: 30, keep: true);
      await _seed(root, active, ageDays: 30, state: 'capturing');
      final legacy = File('${root.path}/legacy.ndjson');
      await legacy.writeAsString('preserve legacy');
      await library.applyRetention();
      expect(await Directory('${root.path}/$old.trailrec').exists(), isFalse);
      expect(await Directory('${root.path}/$keep.trailrec').exists(), isTrue);
      expect(await Directory('${root.path}/$active.trailrec').exists(), isTrue);
      expect(await legacy.readAsString(), 'preserve legacy');
      expect(files.calls, ['metadata']);
      final bounded = SampledRecordingLibrary(
        files: files,
        directoryResolver: () async => root,
        maximumBytes: 1,
      );
      await expectLater(
        bounded.reserve(sessionId: '2', sessionEpoch: 1, title: 'blocked'),
        throwsStateError,
      );
    },
  );

  test('read lease survives close until native reads complete', () async {
    final id = 'a' * 32;
    await _seed(root, id);
    final path = '${root.path}/$id.trailrec';
    final opened = await library.openRecording(path);
    files.reading = Completer<void>();
    final read = opened.recording.seek(Duration.zero);
    final expectation = expectLater(
      read,
      throwsA(isA<RecordingFileCancelled>()),
    );
    final closing = opened.close();
    await expectLater(
      library.deleteRecording(path),
      throwsA(isA<RecordingLibraryBusy>()),
    );
    files.reading!.complete();
    await expectation;
    await closing;
    await library.deleteRecording(path);
    expect(await Directory(path).exists(), isFalse);
  });

  test(
    'orphan new bundles recover as protected while foreign paths are rejected',
    () async {
      final id = 'a' * 32;
      await _seed(root, id);
      await File('${root.path}/entries/$id.json').delete();
      expect((await library.recover()).recovered, 1);
      expect((await library.listRecordings()).single.keep, isTrue);
      await expectLater(
        library.deleteRecording('${root.path}/../$id.trailrec'),
        throwsArgumentError,
      );
      await expectLater(
        library.openRecording('${root.path}/legacy.ndjson'),
        throwsArgumentError,
      );
    },
  );
}
