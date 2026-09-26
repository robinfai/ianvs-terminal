import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

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
  test(
    'copy validates native identity and storage accounting before admission',
    () async {
      final api = FixtureApi();
      Map<String, Object?> result(int bytes) => {
        'inspection': api.data['inspect'],
        'copied_bytes': bytes,
      };
      for (final bytes in [0, 8100, 1048577]) {
        api.data['copy_bundle'] = result(bytes);
        await expectLater(
          SampledRecordingFile.copyBundle(
            '/tmp/source.trailrec',
            '/tmp/staging.trailrec',
            api: api,
            maximumBytes: 1048576,
          ),
          throwsFormatException,
        );
      }
      api.data['copy_bundle'] = {...result(8125), 'unexpected': true};
      await expectLater(
        SampledRecordingFile.copyBundle(
          '/tmp/source.trailrec',
          '/tmp/staging.trailrec',
          api: api,
          maximumBytes: 1048576,
        ),
        throwsFormatException,
      );
      api.data['copy_bundle'] = result(8125);
      final copied = await SampledRecordingFile.copyBundle(
        '/tmp/source.trailrec',
        '/tmp/staging.trailrec',
        api: api,
        maximumBytes: 1048576,
      );
      expect(copied.info.path, '/tmp/staging.trailrec');
      expect(copied.copiedBytes, 8125);
      final metadata = (api.data['inspect']! as Map)['metadata'] as Map;
      metadata['recording_id'] = '../foreign';
      await expectLater(
        SampledRecordingFile.copyBundle(
          '/tmp/source.trailrec',
          '/tmp/staging.trailrec',
          api: api,
          maximumBytes: 1048576,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'cancelled copying settles only after the underlying operation returns',
    () async {
      final api = FixtureApi()..barrier = Completer<void>();
      api.data['copy_bundle'] = {
        'inspection': api.data['inspect'],
        'copied_bytes': 8125,
      };
      final token = RecordingFileCancellation();
      var settled = false;
      final copying = SampledRecordingFile.copyBundle(
        '/tmp/source.trailrec',
        '/tmp/staging.trailrec',
        api: api,
        maximumBytes: 1048576,
        cancellation: token,
      ).whenComplete(() => settled = true);
      final expectation = expectLater(
        copying,
        throwsA(isA<RecordingFileCancelled>()),
      );
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      api.barrier!.complete();
      await expectation;
      expect(settled, isTrue);
    },
  );

  test('publication requires an exact completed acknowledgement', () async {
    final api = FixtureApi();
    api.data['publish_bundle'] = {'enqueued': true};
    await expectLater(
      SampledRecordingFile.publishBundle(
        '/tmp/staging.trailrec',
        '/tmp/copy.trailrec',
        recordingId: 'a' * 32,
        api: api,
      ),
      throwsFormatException,
    );
    api.data['publish_bundle'] = <String, Object?>{};
    await SampledRecordingFile.publishBundle(
      '/tmp/staging.trailrec',
      '/tmp/copy.trailrec',
      recordingId: 'a' * 32,
      api: api,
    );
  });

  test(
    'native workers copy, publish and replay an external bundle without changing its files',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'sampled-copy-dart-',
      );
      final external = Directory('${temporary.path}/external.trailrec');
      await external.create();
      final fixture = fixtureFile('sample.trailrec/records.bin').parent;
      await for (final entity in fixture.list(
        recursive: true,
        followLinks: false,
      )) {
        final relative = entity.path.substring(fixture.path.length);
        if (entity is Directory) {
          await Directory('${external.path}$relative').create(recursive: true);
        }
        if (entity is File) {
          await entity.copy('${external.path}$relative');
        }
      }
      final marker = File('${external.path}/search.index');
      await marker.writeAsString('preserve the external cache');
      final before = await File('${external.path}/records.bin').readAsBytes();
      final names = await external
          .list(recursive: true)
          .map((entry) => entry.path)
          .toSet();
      final api = NativeRecordingFileApi(libraryPath: library!.absolute.path);
      final staging = Directory('${temporary.path}/staging.trailrec');
      try {
        await expectLater(
          SampledRecordingFile.copyBundle(
            external.path,
            staging.path,
            api: api,
            maximumBytes: 1,
          ),
          throwsFormatException,
        );
        expect(await staging.exists(), isFalse);
        final copied = await SampledRecordingFile.copyBundle(
          external.path,
          staging.path,
          api: api,
          maximumBytes: 1048576,
        );
        expect(copied.info.visualCount, 11);
        expect(copied.copiedBytes, before.length + 24);
        final destination = '${temporary.path}/${copied.info.id}.trailrec';
        await SampledRecordingFile.publishBundle(
          staging.path,
          destination,
          recordingId: copied.info.id,
          api: api,
        );
        expect(await staging.exists(), isFalse);
        final replay = await SampledRecordingFile.open(destination, api: api);
        try {
          final frame = (await replay.seek(const Duration(seconds: 6)))!;
          expect(frame.frame.rows.first.text, 'frame 6 雪');
          expect((await replay.loadAsset(frame.assets.single)).rgba.length, 8);
          expect(
            (await replay.search(
              query: 'quoted 雪-6',
              kind: SampledRecordingSearchKind.command,
            )).hits.single.offset,
            const Duration(microseconds: 6000100),
          );
        } finally {
          await replay.close();
        }
        await SampledRecordingFile.copyBundle(
          external.path,
          staging.path,
          api: api,
          maximumBytes: 1048576,
        );
        await expectLater(
          SampledRecordingFile.publishBundle(
            staging.path,
            destination,
            recordingId: copied.info.id,
            api: api,
          ),
          throwsFormatException,
        );
        expect(await staging.exists(), isTrue);
        expect(
          await File('${external.path}/records.bin').readAsBytes(),
          before,
        );
        expect(await marker.readAsString(), 'preserve the external cache');
        expect(
          await external
              .list(recursive: true)
              .map((entry) => entry.path)
              .toSet(),
          names,
        );
      } finally {
        api.dispose();
        await temporary.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Build native/core to exercise real import workers.'
        : false,
  );
}
