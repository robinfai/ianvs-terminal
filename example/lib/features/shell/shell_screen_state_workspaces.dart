part of 'shell_screen.dart';

extension _ShellScreenStateWorkspaces on _ShellScreenState {
  Future<void> _loadRecentWorkspaces() async {
    try {
      final recent = await ref
          .read(sessionControllerProvider.notifier)
          .recentWorkspaces();
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _recentWorkspaces = recent;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showShellSnackBar(
        'Recent Workspaces could not be loaded: '
        '${_boundedWorkspaceUiDetail(error)}',
      );
    }
  }

  Future<void> _openProjectWorkspaceFromPicker() async {
    if (_workspaceSwitchBusy) {
      return;
    }
    String? projectPath;
    try {
      projectPath = await WindowBridge.chooseProjectDirectory();
    } on Object catch (error) {
      _showShellSnackBar(
        'Project picker failed: ${_boundedWorkspaceUiDetail(error)}',
      );
      return;
    }
    if (!mounted || projectPath == null) {
      return;
    }
    await _performWorkspaceSwitch(
      () => ref
          .read(sessionControllerProvider.notifier)
          .openProjectWorkspace(projectPath!),
    );
  }

  Future<void> _openRecentWorkspace(String workspaceId) {
    return _performWorkspaceSwitch(
      () => ref
          .read(sessionControllerProvider.notifier)
          .openRecentWorkspace(workspaceId),
    );
  }

  Future<void> _performWorkspaceSwitch(
    Future<bool> Function() switchWorkspace,
  ) async {
    if (_workspaceSwitchBusy || !mounted) {
      return;
    }
    _mutateState(() {
      _workspaceSwitchBusy = true;
    });
    var switched = false;
    try {
      switched = await switchWorkspace();
    } finally {
      if (mounted) {
        _mutateState(() {
          _workspaceSwitchBusy = false;
        });
      }
    }
    if (!mounted) {
      return;
    }
    await _loadRecentWorkspaces();
    if (!mounted || !switched) {
      return;
    }
    final controller = ref.read(sessionControllerProvider.notifier);
    _scheduleWorkspaceCue('Opened ${controller.activeWorkspaceIdentity.name}');
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId != null) {
      _focusSession(activeSessionId);
    }
  }
}

String _boundedWorkspaceUiDetail(Object error) {
  final normalized = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 180) {
    return normalized;
  }
  return '${normalized.substring(0, 177)}…';
}
