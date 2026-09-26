import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

File fixtureFile(String name) => <File>[
  File('native/core/tests/fixtures/recording/$name'),
  File('../../native/core/tests/fixtures/recording/$name'),
].firstWhere((file) => file.existsSync());

Map<String, Object?> fixture() {
  final data =
      (jsonDecode(fixtureFile('sampled_file_v2.json').readAsStringSync())
              as Map)
          .cast<String, Object?>();
  final screen = (data['seek']! as Map)['screen'] as Map;
  screen['frame_bytes'] = base64Decode(screen.remove('frame_base64') as String);
  final asset = data['asset']! as Map;
  asset['rgba_bytes'] = base64Decode(asset.remove('rgba_base64') as String);
  return data;
}

final class FixtureApi implements RecordingFileApi {
  final Map<String, Object?> data = fixture();
  Completer<void>? barrier;
  Completer<void>? inspectBarrier;
  RecordingFileCancellation? lastCancellation;
  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) async {
    lastCancellation = cancellation;
    if (operation == 'inspect') {
      await inspectBarrier?.future;
    } else {
      await barrier?.future;
    }
    return (data[operation]! as Map).cast<String, Object?>();
  }
}

void main() {
  test(
    'Rust fixture decodes structured screen, commands and retained graphics',
    () async {
      final file = await SampledRecordingFile.open(
        '/tmp/sample.trailrec',
        api: FixtureApi(),
      );
      expect(file.info.title, '采样回放 fixture');
      expect(file.info.visualCount, 11);
      expect(file.info.semanticCount, 22);
      expect(file.info.completion, SampledRecordingCompletion.finished);
      final frame = (await file.seek(const Duration(microseconds: 6500000)))!;
      expect(frame.offset, const Duration(seconds: 6));
      expect(frame.frame.rows.first.text, 'frame 6 雪');
      expect(frame.frame.rows.last.text, 'copiable structured screen');
      expect(frame.frame.graphics.single.assetKey, frame.assets.single.key);
      final asset = await file.loadAsset(frame.assets.single);
      expect(asset.rgba, <int>[255, 0, 0, 255, 0, 255, 0, 255]);
      final page = await file.timeline(limit: 3);
      expect(page.events.length, 3);
      expect(page.events.first.command, "printf '%s' 'quoted 雪-0'");
      expect(page.events[1].exitCode, 7);
      expect(page.nextCursor, isPositive);
      await file.close();
    },
  );

  test('cancelled open rejects a late file response', () async {
    final api = FixtureApi()..inspectBarrier = Completer<void>();
    final token = RecordingFileCancellation();
    final opening = SampledRecordingFile.open(
      '/tmp/sample.trailrec',
      api: api,
      cancellation: token,
    );
    final expectation = expectLater(
      opening,
      throwsA(isA<RecordingFileCancelled>()),
    );
    token.cancel();
    api.inspectBarrier!.complete();
    await expectation;
  });

  test(
    'close waits for real read completion and suppresses a late frame',
    () async {
      final api = FixtureApi();
      final file = await SampledRecordingFile.open(
        '/tmp/sample.trailrec',
        api: api,
      );
      api.barrier = Completer<void>();
      final reading = file.seek(Duration.zero);
      final expectation = expectLater(
        reading,
        throwsA(isA<RecordingFileCancelled>()),
      );
      var closed = false;
      final closing = file.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(api.lastCancellation!.isCancelled, isTrue);
      expect(closed, isFalse);
      api.barrier!.complete();
      await expectation;
      await closing;
      expect(file.isClosed, isTrue);
      await expectLater(file.timeline(), throwsStateError);
    },
  );

  test(
    'rejects missing asset bindings and inconsistent summary counts',
    () async {
      final api = FixtureApi();
      final file = await SampledRecordingFile.open(
        '/tmp/sample.trailrec',
        api: api,
      );
      ((api.data['seek']! as Map)['screen'] as Map)['assets'] = <Object?>[];
      await expectLater(file.seek(Duration.zero), throwsFormatException);
      ((api.data['inspect']! as Map)['summary'] as Map)['record_count'] = 1;
      await expectLater(
        SampledRecordingFile.open('/tmp/sample.trailrec', api: api),
        throwsFormatException,
      );
      await file.close();
    },
  );

  test(
    'search rejects nonadvancing pages and close cancels pending search reads',
    () async {
      final api = FixtureApi();
      api.data['search'] = {
        'hits': <Object>[],
        'next_cursor': 0,
        'scanned_bytes': 1,
        'total_bytes': 100,
      };
      final file = await SampledRecordingFile.open(
        '/tmp/sample.trailrec',
        api: api,
      );
      await expectLater(file.search(query: 'text'), throwsFormatException);
      api.barrier = Completer<void>();
      final reading = file.search(query: 'text');
      final expectation = expectLater(
        reading,
        throwsA(isA<RecordingFileCancelled>()),
      );
      var closed = false;
      final closing = file.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      api.barrier!.complete();
      await expectation;
      await closing;
      expect(closed, isTrue);
    },
  );

  final library = <File>[
    File('native/core/target/debug/libianvs_core.dylib'),
    File('../../native/core/target/debug/libianvs_core.dylib'),
    File('native/core/target/debug/libianvs_core.so'),
    File('../../native/core/target/debug/libianvs_core.so'),
  ].where((file) => file.existsSync()).firstOrNull;

  test(
    'actual native workers open, seek, page and cancel without any PTY',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'sampled-file-dart-',
      );
      final source = fixtureFile('sample.trailrec/records.bin').parent;
      final bundle = Directory('${temporary.path}/fixture.trailrec');
      await bundle.create();
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        final relative = entity.path.substring(source.path.length);
        if (entity is Directory) {
          await Directory('${bundle.path}$relative').create(recursive: true);
        }
        if (entity is File) await entity.copy('${bundle.path}$relative');
      }
      final api = NativeRecordingFileApi(libraryPath: library!.absolute.path);
      try {
        expect(
          await api.run('sync_directory', {'directory_path': bundle.path}),
          isEmpty,
        );
        await expectLater(
          api.run('sync_directory', {
            'directory_path': '${bundle.path}/records.bin',
          }),
          throwsFormatException,
        );
        final file = await SampledRecordingFile.open(bundle.path, api: api);
        for (final seconds in <int>[8, 1, 10, 0, 6]) {
          final frame = (await file.seek(Duration(seconds: seconds)))!;
          expect(frame.frame.rows.first.text, 'frame $seconds 雪');
          expect((await file.loadAsset(frame.assets.single)).rgba.length, 8);
        }
        var cursor = 0;
        var events = 0;
        while (true) {
          final page = await file.timeline(cursor: cursor, limit: 3);
          events += page.events.length;
          if (page.nextCursor == null) break;
          cursor = page.nextCursor!;
        }
        expect(events, 22);
        final search = await file.search(
          query: 'quoted 雪-6',
          kind: SampledRecordingSearchKind.command,
        );
        expect(search.hits.single.preview, "printf '%s' 'quoted 雪-6'");
        expect(
          search.hits.single.offset,
          const Duration(microseconds: 6000100),
        );
        expect(search.nextCursor, isNull);
        expect(
          (await file.search(
            query: 'frame 8',
            kind: SampledRecordingSearchKind.screen,
          )).hits.single.offset,
          const Duration(seconds: 8),
        );
        for (var attempt = 0; attempt < 20; attempt++) {
          final token = RecordingFileCancellation();
          final pending = file.seek(Duration.zero, cancellation: token);
          final expectation = expectLater(
            pending,
            throwsA(isA<RecordingFileCancelled>()),
          );
          token.cancel();
          await expectation;
        }
        expect(
          (await file.seek(Duration.zero))!.frame.rows.first.text,
          'frame 0 雪',
        );
        await file.close();
        final token = RecordingFileCancellation();
        final reads = List.generate(
          4,
          (_) => api.run('metadata', <String, Object?>{
            'bundle_path': bundle.path,
            'recording_id': file.info.id,
          }, cancellation: token),
        );
        final expectations = reads
            .map(
              (read) =>
                  expectLater(read, throwsA(isA<RecordingFileCancelled>())),
            )
            .toList();
        api.dispose();
        await Future.wait(expectations);
      } finally {
        api.dispose();
        await temporary.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Build native/core to exercise real FFI workers.'
        : false,
  );
}
