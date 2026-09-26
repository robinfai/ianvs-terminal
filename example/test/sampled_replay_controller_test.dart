import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/recording/sampled_replay_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class _Read {
  _Read(this.position, this.cancellation);
  final int position;
  final RecordingFileCancellation? cancellation;
  final Completer<void> barrier = Completer<void>();
}

class _Files implements RecordingFileApi {
  final reads = <_Read>[];
  bool hold = false;
  bool fail = false;
  final Map<String, dynamic> data =
      jsonDecode(
            <File>[
              File('native/core/tests/fixtures/recording/sampled_file_v2.json'),
              File(
                '../native/core/tests/fixtures/recording/sampled_file_v2.json',
              ),
            ].firstWhere((file) => file.existsSync()).readAsStringSync(),
          )
          as Map<String, dynamic>;
  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) async {
    final result = (jsonDecode(jsonEncode(data[operation])) as Map)
        .cast<String, Object?>();
    if (operation == 'seek') {
      final read = _Read(payload['offset_micros']! as int, cancellation);
      reads.add(read);
      if (hold) await read.barrier.future;
      if (fail) throw const FormatException('unreadable screen');
      final screen = result['screen']! as Map;
      screen['frame_bytes'] = base64Decode(
        screen.remove('frame_base64') as String,
      );
      screen['offset_micros'] = read.position;
    }
    return result;
  }
}

void main() {
  test(
    'seek storms keep one in-flight read and only publish the newest destination',
    () async {
      final api = _Files()..hold = true;
      final file = await SampledRecordingFile.open(
        '/tmp/file.trailrec',
        api: api,
      );
      final replay = SampledReplayController(file);
      var frames = 0;
      replay.viewport.addListener(() => frames++);
      final first = replay.seek(const Duration(seconds: 1));
      final futures = [
        for (var i = 2; i <= 9; i++) replay.seek(Duration(seconds: i)),
      ];
      expect(api.reads.length, 1);
      expect(api.reads.first.cancellation!.isCancelled, isTrue);
      api.reads.first.barrier.complete();
      await Future<void>.delayed(Duration.zero);
      expect(api.reads.length, 2);
      expect(api.reads.last.position, 9000000);
      api.reads.last.barrier.complete();
      await Future.wait([first, ...futures]);
      expect(replay.position, const Duration(seconds: 9));
      expect(frames, 1);
      expect(replay.error, isNull);
      replay.dispose();
      await file.close();
    },
  );

  test(
    'failed seek retains prior screen and exposes a retryable error',
    () async {
      final api = _Files();
      final file = await SampledRecordingFile.open(
        '/tmp/file.trailrec',
        api: api,
      );
      final replay = SampledReplayController(file);
      await replay.initialize();
      final initial = replay.viewport.frame;
      api.fail = true;
      await replay.seek(const Duration(seconds: 3));
      expect(identical(replay.viewport.frame, initial), isTrue);
      expect(replay.error, contains('unreadable screen'));
      api.fail = false;
      await replay.seek(const Duration(seconds: 4));
      expect(replay.position, const Duration(seconds: 4));
      expect(replay.error, isNull);
      replay.dispose();
      await file.close();
    },
  );

  test(
    'dispose suppresses late completion and close waits for its worker',
    () async {
      final api = _Files()..hold = true;
      final file = await SampledRecordingFile.open(
        '/tmp/file.trailrec',
        api: api,
      );
      final replay = SampledReplayController(file);
      final seek = replay.seek(Duration.zero);
      replay.dispose();
      final close = file.close();
      expect(api.reads.single.cancellation!.isCancelled, isTrue);
      api.reads.single.barrier.complete();
      await Future.wait([seek, close]);
    },
  );

  test(
    'pause during restart at the end never starts a delayed playback timer',
    () async {
      final api = _Files();
      final file = await SampledRecordingFile.open(
        '/tmp/file.trailrec',
        api: api,
      );
      final replay = SampledReplayController(file);
      await replay.seek(replay.duration);
      api.hold = true;
      replay.play();
      expect(api.reads.last.position, 0);
      replay.pause();
      api.reads.last.barrier.complete();
      await Future<void>.delayed(Duration.zero);
      expect(replay.playing, isFalse);
      expect(replay.position, Duration.zero);
      replay.dispose();
      await file.close();
    },
  );
}
