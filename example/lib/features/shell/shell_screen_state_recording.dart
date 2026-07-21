part of 'shell_screen.dart';

extension _ShellScreenStateRecording on _ShellScreenState {
  Future<void> _toggleActiveSessionRecording(
    SessionController sessionController,
    String? sessionId,
  ) async {
    if (sessionId == null) {
      return;
    }
    final current = ref.read(sessionControllerProvider);
    final shouldStop =
        current.recordingSessionIds.contains(sessionId) ||
        current.recordingPendingSaveSessionIds.contains(sessionId);
    if (shouldStop) {
      final path = await sessionController.stopSessionRecording(sessionId);
      if (path != null) {
        _showShellSnackBar('Recording saved to $path');
      }
      return;
    }
    if (await sessionController.startSessionRecording(sessionId)) {
      _showShellSnackBar('Recording started. Input bytes are redacted.');
    }
  }
}
