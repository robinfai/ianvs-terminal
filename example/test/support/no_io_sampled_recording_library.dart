import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

/// Widget subjects outside recording use no filesystem or native reader.
/// Recording behavior tests must provide a dedicated persistence fixture.
SampledRecordingLibrary noIoSampledRecordingLibrary() =>
    NoIoSampledRecordingLibrary();

class NoIoSampledRecordingLibrary extends SampledRecordingLibrary {
  NoIoSampledRecordingLibrary()
    : super(
        files: _UnexpectedFileAccess(),
        directoryResolver: () async => throw StateError(
          'This test did not provide recording persistence.',
        ),
      );

  @override
  Future<void> applyRetention() async {}

  @override
  Future<SampledRecordingRecovery> recover() async =>
      const SampledRecordingRecovery(0, 0, []);
}

final class _UnexpectedFileAccess implements RecordingFileApi {
  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) => throw StateError('Unexpected recording file operation: $operation');
}
