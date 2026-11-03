import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

const _id = '0123456789abcdef0123456789abcdef';

class _ImportFiles implements RecordingFileApi {
  final calls = <String>[];
  final inspected = <String>[];
  final copying = Completer<void>();
  Completer<void>? copyBarrier;
  Completer<void>? publishBarrier;
  final publishing = Completer<void>();
  RecordingFileCancellation? token;
  bool failCopy = false;
  bool failAfterPublish = false;
  bool failManifest = false;
  int indexBytes = 0;
  String? failSyncPath;

  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) async {
    calls.add(operation);
    if (operation == 'sync_directory') {
      if (failSyncPath == payload['directory_path']) {
        failSyncPath = null;
        throw const FileSystemException('Injected sync failure');
      }
      return {};
    }
    if (operation == 'copy_bundle') {
      token = cancellation;
      final source = payload['source_path']! as String;
      final target = payload['destination_path']! as String;
      if ((payload['maximum_bytes']! as int) < 200) {
        throw StateError('Budget exhausted');
      }
      await Directory(target).create();
      await File('$target/records.bin').writeAsBytes(List.filled(200, 42));
      if (!copying.isCompleted) copying.complete();
      await copyBarrier?.future;
      // Deliberately write after the cancellation signal: the caller must wait.
      await File('$source/fixture.json').copy('$target/fixture.json');
      if (cancellation?.isCancelled == true) {
        throw const RecordingFileCancelled();
      }
      if (failCopy) throw const FileSystemException('Injected incomplete copy');
      return {'inspection': await _inspection(target), 'copied_bytes': 200};
    }
    if (operation == 'publish_bundle') {
      if (!publishing.isCompleted) publishing.complete();
      await publishBarrier?.future;
      final target = payload['destination_path']! as String;
      if (await Directory(target).exists()) throw StateError('Already exists');
      await Directory(payload['staging_path']! as String).rename(target);
      if (failManifest) {
        failSyncPath = '${Directory(target).parent.path}/entries';
      }
      if (failAfterPublish) {
        throw const FileSystemException('Lost publish reply');
      }
      return {};
    }
    final path = payload['bundle_path']! as String;
    if (operation == 'metadata') {
      return {'metadata': (await _inspection(path))['metadata']};
    }
    if (operation == 'inspect') {
      inspected.add(path);
      if (indexBytes > 0) {
        await File('$path/seek.index').writeAsBytes(List.filled(indexBytes, 1));
      }
      return _inspection(path);
    }
    if (operation == 'seek') return {'screen': null};
    throw StateError(operation);
  }

  Future<Map<String, Object?>> _inspection(String path) async => {
    'metadata': jsonDecode(await File('$path/fixture.json').readAsString()),
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

void main() {
  late Directory parent;
  late Directory root;
  late Directory source;
  late _ImportFiles files;
  late SampledRecordingLibrary library;
  SampledRecordingLibrary createLibrary({int maximumBytes = 20000}) =>
      SampledRecordingLibrary(
        files: files,
        directoryResolver: () async => root,
        maximumBytes: maximumBytes,
      );
  Future<List<FileSystemEntity>> staging() =>
      Directory('${root.path}/.imports').list(followLinks: false).toList();

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('sampled-import-test-');
    root = Directory('${parent.path}/library');
    source = await Directory('${parent.path}/external.trailrec').create();
    await File('${source.path}/fixture.json').writeAsString(
      jsonEncode({
        'recording_id': _id,
        'title': 'Imported work',
        'hostname': 'remote',
        'started_at_unix_millis': 1,
      }),
    );
    await File('${source.path}/records.bin').writeAsBytes(List.filled(200, 42));
    await File('${source.path}/old.ndjson').writeAsString('untouched legacy');
    files = _ImportFiles();
    library = createLibrary();
    root = await library.ensureRecordingDirectory();
  });
  tearDown(() async {
    if (files.copyBarrier?.isCompleted == false) files.copyBarrier!.complete();
    if (files.publishBarrier?.isCompleted == false) {
      files.publishBarrier!.complete();
    }
    library.cancelPendingImports();
    await library.drain();
    await parent.delete(recursive: true);
  });

  test(
    'external selection publishes a kept copy, survives restart and preserves its source',
    () async {
      final before = await File('${source.path}/records.bin').readAsBytes();
      final opened = await library.openPickedRecording(source.path);
      expect(opened.entry.path, '${root.path}/$_id.trailrec');
      expect(opened.entry.keep, isTrue);
      expect(opened.entry.state, 'interrupted');
      expect(opened.entry.sessionId, isNull);
      expect(files.inspected, isNot(contains(source.path)));
      expect(await staging(), isEmpty);
      await opened.close();
      final restarted = createLibrary();
      expect((await restarted.recover()).errors, isEmpty);
      await restarted
          .applyRetention(); // Imported date is old, but Keep protects it.
      final reopened = await restarted.openRecording(opened.entry.path);
      await reopened.close();
      await restarted.deleteRecording(opened.entry.path);
      expect(await File('${source.path}/records.bin').readAsBytes(), before);
      expect(
        await File('${source.path}/old.ndjson').readAsString(),
        'untouched legacy',
      );
      expect(await source.list().length, 3);
    },
  );

  test(
    'managed selections reuse the existing copy and duplicate external selections never replace it',
    () async {
      final opened = await library.openPickedRecording(source.path);
      final path = opened.entry.path;
      await opened.close();
      final managed = await library.openPickedRecording(path);
      expect(files.calls.where((op) => op == 'copy_bundle'), hasLength(1));
      await managed.close();
      await expectLater(
        library.openPickedRecording(source.path),
        throwsStateError,
      );
      expect((await library.listRecordings()).single.keep, isTrue);
      expect(await staging(), isEmpty);
      expect(await File('$path/records.bin').length(), 200);
    },
  );

  test(
    'an existing empty destination or unknown manifest is preserved',
    () async {
      final destination = await Directory(
        '${root.path}/$_id.trailrec',
      ).create();
      await expectLater(
        library.openPickedRecording(source.path),
        throwsStateError,
      );
      expect(await destination.list().length, 0);
      await destination.delete();
      final manifest = File('${root.path}/entries/$_id.json');
      await manifest.writeAsString('{"schema_version":99}');
      await expectLater(
        library.openPickedRecording(source.path),
        throwsStateError,
      );
      expect(await manifest.readAsString(), '{"schema_version":99}');
      expect(await staging(), isEmpty);
    },
  );

  test(
    'unknown policy blocks copying and indexes must fit the final budget',
    () async {
      final policy = File('${root.path}/retention.json');
      await policy.writeAsString('{"schema_version":99}');
      await expectLater(
        library.openPickedRecording(source.path),
        throwsFormatException,
      );
      expect(files.calls, isNot(contains('copy_bundle')));
      await policy.delete();
      library = createLibrary(maximumBytes: 800);
      files.indexBytes = 1000;
      await expectLater(
        library.openPickedRecording(source.path),
        throwsStateError,
      );
      expect(files.calls, isNot(contains('publish_bundle')));
      expect(await staging(), isEmpty);
      expect(await library.listRecordings(), isEmpty);
    },
  );

  test(
    'cancellation and drain retain ownership until the copy worker actually settles',
    () async {
      files.copyBarrier = Completer<void>();
      final token = RecordingFileCancellation();
      final pending = library.openPickedRecording(
        source.path,
        cancellation: token,
      );
      final result = expectLater(
        pending,
        throwsA(isA<RecordingFileCancelled>()),
      );
      await files.copying.future;
      expect(await staging(), hasLength(2));
      token.cancel();
      var drained = false;
      final drain = library.drain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      await expectLater(
        createLibrary().recover(),
        throwsA(isA<RecordingLibraryBusy>()),
      );
      expect(await staging(), hasLength(2));
      files.copyBarrier!.complete();
      await result;
      await drain;
      expect(await staging(), isEmpty);
      expect(await library.listRecordings(), isEmpty);
    },
  );

  test(
    'shutdown cancels imports before queued maintenance and refuses new picker jobs',
    () async {
      files.copyBarrier = Completer<void>();
      final result = expectLater(
        library.openPickedRecording(source.path),
        throwsA(isA<RecordingFileCancelled>()),
      );
      await files.copying.future;
      final maintenance = library.applyRetention();
      library.cancelPendingImports();
      expect(files.token!.isCancelled, isTrue);
      await expectLater(
        library.openPickedRecording(source.path),
        throwsA(isA<RecordingFileCancelled>()),
      );
      files.copyBarrier!.complete();
      await result;
      await maintenance;
      await library.drain();
      expect(await staging(), isEmpty);
    },
  );

  test(
    'cancellation after publication begins waits and preserves the committed kept copy',
    () async {
      files.publishBarrier = Completer<void>();
      final token = RecordingFileCancellation();
      final result = expectLater(
        library.openPickedRecording(source.path, cancellation: token),
        throwsA(isA<RecordingFileCancelled>()),
      );
      await files.publishing.future;
      token.cancel();
      files.publishBarrier!.complete();
      await result;
      await library.drain();
      final entries = await library.listRecordings();
      expect(entries.single.keep, isTrue);
      expect(await Directory(entries.single.path).exists(), isTrue);
      expect(await staging(), isEmpty);
    },
  );

  for (final lostManifest in [false, true]) {
    test(
      'publication failure preserves a recoverable copy (manifest=$lostManifest)',
      () async {
        files.failAfterPublish = !lostManifest;
        files.failManifest = lostManifest;
        await expectLater(
          library.openPickedRecording(source.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(await Directory('${root.path}/$_id.trailrec').exists(), isTrue);
        final recovered = createLibrary();
        expect((await recovered.recover()).errors, isEmpty);
        expect((await recovered.listRecordings()).single.keep, isTrue);
        expect(await staging(), isEmpty);
        expect(await File('${source.path}/records.bin').length(), 200);
      },
    );
  }

  test('partial copy failures clean only journal-owned staging', () async {
    files.failCopy = true;
    await expectLater(
      library.openPickedRecording(source.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await staging(), isEmpty);
    expect(await library.listRecordings(), isEmpty);
    expect(await File('${source.path}/records.bin').length(), 200);
  });

  test(
    'restart cleans owned partial imports and preserves unknown journals as protected capacity',
    () async {
      final imports = Directory('${root.path}/.imports');
      final owned = 'a' * 32;
      final unknown = 'b' * 32;
      final corrupt = 'c' * 32;
      for (final id in [owned, unknown, corrupt]) {
        final directory = await Directory(
          '${imports.path}/$id.trailrec',
        ).create();
        await File(
          '${directory.path}/partial',
        ).writeAsBytes(List.filled(600, 3));
      }
      await File(
        '${imports.path}/$owned.json',
      ).writeAsString(jsonEncode({'schema_version': 2, 'import_id': owned}));
      await File(
        '${imports.path}/$unknown.json',
      ).writeAsString(jsonEncode({'schema_version': 3, 'import_id': unknown}));
      await File('${imports.path}/$corrupt.json').writeAsString('not json');
      library = createLibrary(maximumBytes: 1000);
      expect((await library.recover()).errors, isEmpty);
      expect(
        await Directory('${imports.path}/$owned.trailrec').exists(),
        isFalse,
      );
      expect(
        await Directory('${imports.path}/$unknown.trailrec').exists(),
        isTrue,
      );
      expect(
        await Directory('${imports.path}/$corrupt.trailrec').exists(),
        isTrue,
      );
      expect(await library.storageBytes(), greaterThan(1200));
      await expectLater(
        library.openPickedRecording(source.path),
        throwsStateError,
      );
      expect(files.calls, isNot(contains('copy_bundle')));
    },
  );

  test(
    'cleanup rejects symlink staging without touching its external target',
    () async {
      final journal = File('${root.path}/.imports/$_id.json');
      await journal.writeAsString(
        jsonEncode({'schema_version': 2, 'import_id': _id}),
      );
      await Link('${root.path}/.imports/$_id.trailrec').create(source.path);
      expect(
        (await library.recover()).errors.single,
        contains('not a directory'),
      );
      expect(await journal.exists(), isTrue);
      expect(await source.list().length, 3);
    },
  );

  test(
    'the picker cannot import staging or other internal library directories',
    () async {
      await expectLater(
        library.openPickedRecording('${root.path}/.imports'),
        throwsArgumentError,
      );
      expect(files.calls, isNot(contains('copy_bundle')));
    },
  );
}
