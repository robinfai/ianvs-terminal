import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

/// Uses the Rust-generated contract bytes, with deterministic in-process reads
/// for widget tests. Actual worker/native round trips have separate coverage.
class SampledTestFiles implements RecordingFileApi {
  SampledTestFiles({Map<String, dynamic>? fixture})
    : fixture =
          fixture ??
          jsonDecode(
                [
                  File(
                    'native/core/tests/fixtures/recording/sampled_file_v2.json',
                  ),
                  File(
                    '../native/core/tests/fixtures/recording/sampled_file_v2.json',
                  ),
                ].firstWhere((file) => file.existsSync()).readAsStringSync(),
              )
              as Map<String, dynamic>;
  final Map<String, dynamic> fixture;
  final List<String> operations = [];
  final List<int> seeks = [];
  final List<Map<String, Object?>> searchRequests = [];
  Completer<void>? inspectBarrier;
  bool failInspect = false;
  RecordingFileCancellation? inspectCancellation;

  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) async {
    operations.add(operation);
    if (operation == 'sync_directory') return {};
    if (operation == 'search') searchRequests.add(Map.of(payload));
    if (operation == 'inspect') {
      inspectCancellation = cancellation;
      await inspectBarrier?.future;
      if (failInspect) throw const FormatException('Unreadable recording');
    }
    final result =
        (jsonDecode(
                  jsonEncode(
                    fixture[operation == 'metadata' ? 'inspect' : operation],
                  ),
                )
                as Map)
            .cast<String, Object?>();
    final metadata = result['metadata'];
    if (metadata is Map) {
      metadata['recording_id'] = (payload['bundle_path']! as String)
          .split('/')
          .last
          .split('.')
          .first;
      metadata['title'] = 'Saved work';
    }
    if (operation == 'metadata') return {'metadata': metadata};
    if (operation == 'seek') {
      seeks.add(payload['offset_micros']! as int);
      final screen = result['screen']! as Map;
      screen['frame_bytes'] = base64Decode(
        screen.remove('frame_base64') as String,
      );
      screen['offset_micros'] = payload['offset_micros'];
    }
    if (operation == 'asset') {
      result['rgba_bytes'] = base64Decode(
        result.remove('rgba_base64')! as String,
      );
    }
    return result;
  }
}

Future<SampledRecordingEntry> seedSampledRecording(
  SampledRecordingLibrary library, {
  String id = '0123456789abcdef0123456789abcdef',
}) async {
  final root = await library.ensureRecordingDirectory();
  final entry = SampledRecordingEntry(
    id: id,
    path: '${root.path}/$id.trailrec',
    displayName: 'Saved work',
    createdAtUtc: DateTime.now().toUtc(),
    duration: const Duration(seconds: 10),
    state: 'finished',
    sessionId: null,
    keep: false,
  );
  await Directory(entry.path).create();
  await File(
    '${root.path}/entries/$id.json',
  ).writeAsString(jsonEncode(entry.toJson()), flush: true);
  return entry;
}
