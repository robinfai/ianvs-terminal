part of 'shell_screen.dart';

extension _ShellScreenStateFolders on _ShellScreenState {
  Future<void> _openTerminalAtFolderFromPicker() async {
    String? folderPath;
    try {
      folderPath = await WindowBridge.chooseTerminalFolder();
    } on Object catch (error) {
      _showShellSnackBar(
        'Folder picker failed: ${_boundedFolderUiDetail(error)}',
      );
      return;
    }
    if (!mounted || folderPath == null) {
      return;
    }
    final opened = await ref
        .read(sessionControllerProvider.notifier)
        .openTerminalAtFolder(folderPath);
    if (!mounted || !opened) {
      return;
    }
    _scheduleWorkspaceCue('Opened terminal at folder');
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId != null) {
      _focusSession(activeSessionId);
    }
  }
}

String _boundedFolderUiDetail(Object error) {
  final normalized = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 180) {
    return normalized;
  }
  return '${normalized.substring(0, 177)}…';
}
