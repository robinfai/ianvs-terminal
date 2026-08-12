import 'package:app/features/recording/local_session_recording_repository.dart';

/// Creates a recording repository for widget compositions that do not exercise
/// recording persistence.
///
/// Recovery is intentionally empty and every unoverridden filesystem entry
/// point fails before I/O. Tests that cover recording behavior must provide
/// their purpose-built repository instead.
LocalSessionRecordingRepository noIoLocalSessionRecordingRepository() {
  return _NoIoLocalSessionRecordingRepository();
}

final class _NoIoLocalSessionRecordingRepository
    extends LocalSessionRecordingRepository
    with NoIoLocalSessionRecordingRecovery {
  _NoIoLocalSessionRecordingRepository()
    : super(
        directoryResolver: () async => throw StateError(
          'This widget test did not provide recording persistence.',
        ),
      );
}

/// Shared recovery seam for widget tests whose subject is not startup recovery.
mixin NoIoLocalSessionRecordingRecovery on LocalSessionRecordingRepository {
  @override
  Future<LocalSessionRecordingRecoveryResult> recoverNativeRecordings() async {
    return const LocalSessionRecordingRecoveryResult(
      recoveredPaths: <String>[],
      pendingJobIds: <String>[],
      orphanPaths: <String>[],
      failures: <LocalSessionRecordingRecoveryFailure>[],
    );
  }
}
