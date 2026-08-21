part of 'shell_screen.dart';

extension _ShellScreenStateRecording on _ShellScreenState {
  Future<void> _toggleActiveSessionRecording(
    SessionController sessionController,
    String? sessionId,
  ) async {
    final l10n = context.l10n;
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
        _showRecordingSavedSnackBar(path);
      }
      return;
    }
    if (await sessionController.startSessionRecording(sessionId)) {
      _showShellSnackBar(l10n.recordingReplayStarted);
    }
  }

  void _showRecordingSavedSnackBar(String path) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final fileName = File(path).uri.pathSegments.last;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.recordingSavedNamed(fileName),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('recording-saved-replay'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.inversePrimary,
                  ),
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    unawaited(_openRecordingAtPath(path));
                  },
                  child: Text(context.l10n.replay),
                ),
                TextButton(
                  key: const Key('recording-saved-reveal'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.inversePrimary,
                  ),
                  onPressed: () => unawaited(_revealShellPath(path)),
                  child: Text(context.l10n.reveal),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
