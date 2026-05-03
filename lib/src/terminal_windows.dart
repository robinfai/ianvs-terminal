import 'package:flutter/foundation.dart';

import 'clipboard_client.dart';
import 'fig_completion.dart';
import 'launch_config.dart';
import 'local_shell_session_controller.dart';
import 'saved_commands.dart';
import 'session_restore.dart';
import 'terminal_blocks.dart';
import 'terminal_panes.dart';
import 'terminal_settings.dart';
import 'terminal_tabs_controller.dart';

class TerminalWindowController {
  TerminalWindowController({
    required this.id,
    required this.fallbackTitle,
    required this.tabsController,
  });

  final int id;
  final String fallbackTitle;
  final TerminalTabsController tabsController;

  String get title => fallbackTitle;
}

class TerminalWindowsController extends ChangeNotifier {
  TerminalWindowsController({
    required this.backendFactory,
    required this.clipboardClient,
    required this.settingsController,
    required this.savedCommandsController,
    this.completionRepository,
    this.completionEnvironment = const <String, String>{},
    this.initialBlocksForSession,
    this.sessionRestoreController,
  });

  final PtyBackendFactory backendFactory;
  final ClipboardClient clipboardClient;
  final TerminalSettingsController settingsController;
  final SavedCommandsController savedCommandsController;
  final FigCompletionRepository? completionRepository;
  final Map<String, String> completionEnvironment;
  final TerminalBlockSeedFactory? initialBlocksForSession;
  final TerminalSessionRestoreController? sessionRestoreController;

  final List<TerminalWindowController> _windows = <TerminalWindowController>[];
  final Map<TerminalTabsController, VoidCallback> _windowListeners =
      <TerminalTabsController, VoidCallback>{};
  int _nextWindowId = 0;
  int _activeWindowIndex = -1;
  bool _restoreSaveSuspended = false;

  List<TerminalWindowController> get windows => List.unmodifiable(_windows);
  bool get hasWindows => _windows.isNotEmpty;
  int get activeWindowIndex => _activeWindowIndex;
  TerminalWindowController get activeWindow => _windows[_activeWindowIndex];
  TerminalTabsController get activeTabsController =>
      activeWindow.tabsController;
  List<TerminalTabController> get tabs => activeTabsController.tabs;
  int get activeIndex => activeTabsController.activeIndex;
  TerminalTabController get activeTab => activeTabsController.activeTab;
  TerminalPaneLeaf get activePane => activeTabsController.activePane;
  LocalShellSessionController get activeShell =>
      activeTabsController.activeShell;
  bool get canCloseActiveWindow => _windows.length > 1;
  bool get canCloseActiveTab => activeTabsController.canCloseActiveTab;
  bool get canCloseActivePane => activeTabsController.canCloseActivePane;

  void createInitialWindow() {
    if (_windows.isNotEmpty) {
      return;
    }
    final restoreState = sessionRestoreController?.load();
    if (restoreState != null && restoreState.hasWindows) {
      _restoreWindows(restoreState);
      _scheduleRestoreSave();
      notifyListeners();
      return;
    }
    newWindow();
  }

  void newWindow() {
    _restoreSaveSuspended = true;
    try {
      final window = _createWindow(
        fallbackTitle: 'Window ${_nextWindowId + 1}',
      );
      window.tabsController.createInitialTab();
      _windows.add(window);
      _activeWindowIndex = _windows.length - 1;
    } finally {
      _restoreSaveSuspended = false;
    }
    _notifyAndScheduleRestoreSave();
  }

  void closeActiveWindow() {
    if (_activeWindowIndex < 0) {
      return;
    }
    closeWindow(_activeWindowIndex);
  }

  void closeWindow(int index) {
    if (_windows.length <= 1 || index < 0 || index >= _windows.length) {
      return;
    }
    final removed = _windows.removeAt(index);
    _untrackWindow(removed);
    removed.tabsController.dispose();
    if (_activeWindowIndex >= _windows.length) {
      _activeWindowIndex = _windows.length - 1;
    } else if (index < _activeWindowIndex) {
      _activeWindowIndex -= 1;
    } else if (index == _activeWindowIndex) {
      _activeWindowIndex = index.clamp(0, _windows.length - 1).toInt();
    }
    _notifyAndScheduleRestoreSave();
  }

  void selectWindow(int index) {
    if (index < 0 || index >= _windows.length || index == _activeWindowIndex) {
      return;
    }
    _activeWindowIndex = index;
    _notifyAndScheduleRestoreSave();
  }

  void nextWindow() {
    if (_windows.length < 2) {
      return;
    }
    _activeWindowIndex = (_activeWindowIndex + 1) % _windows.length;
    _notifyAndScheduleRestoreSave();
  }

  void previousWindow() {
    if (_windows.length < 2) {
      return;
    }
    _activeWindowIndex = _activeWindowIndex <= 0
        ? _windows.length - 1
        : _activeWindowIndex - 1;
    _notifyAndScheduleRestoreSave();
  }

  void newTab() => activeTabsController.newTab();

  void newSshTab({
    required String host,
    String account = '',
    String environment = '',
    String project = '',
  }) {
    activeTabsController.newSshTab(
      host: host,
      account: account,
      environment: environment,
      project: project,
    );
  }

  void selectTab(int index) => activeTabsController.selectTab(index);
  void nextTab() => activeTabsController.nextTab();
  void previousTab() => activeTabsController.previousTab();
  void splitActivePaneRight() => activeTabsController.splitActivePaneRight();
  void splitActivePaneDown() => activeTabsController.splitActivePaneDown();
  void selectPane(int paneId) => activeTabsController.selectPane(paneId);
  void nextPane() => activeTabsController.nextPane();
  void previousPane() => activeTabsController.previousPane();
  void closeActivePane() => activeTabsController.closeActivePane();
  void updatePaneSplitRatio(TerminalPaneSplit split, double ratio) =>
      activeTabsController.updatePaneSplitRatio(split, ratio);
  void closeActiveTab() => activeTabsController.closeActiveTab();
  void closeTab(int index) => activeTabsController.closeTab(index);

  void updatePaneStartupCommands(Map<int, String?> commandsByPaneId) {
    activeTabsController.updatePaneStartupCommands(commandsByPaneId);
  }

  TerminalLaunchConfiguration currentLaunchConfiguration() {
    if (_windows.isEmpty) {
      return const TerminalLaunchConfiguration();
    }
    return TerminalLaunchConfiguration(
      activeWindowIndex: _activeWindowIndex.clamp(0, _windows.length - 1),
      windows: _windows
          .map(
            (window) => window.tabsController.currentLaunchConfigurationWindow(
              fallbackTitle: window.title,
            ),
          )
          .toList(growable: false),
    );
  }

  void applyLaunchConfiguration(TerminalLaunchConfiguration configuration) {
    if (!configuration.hasWindows) {
      return;
    }
    _restoreSaveSuspended = true;
    try {
      _disposeAllWindows();
      _nextWindowId = 0;
      for (final launchWindow in configuration.windows) {
        final window = _createWindow(fallbackTitle: launchWindow.fallbackTitle);
        window.tabsController.applyLaunchConfigurationWindow(launchWindow);
        _windows.add(window);
      }
      _activeWindowIndex = configuration.activeWindowIndex.clamp(
        0,
        _windows.length - 1,
      );
    } finally {
      _restoreSaveSuspended = false;
    }
    _notifyAndScheduleRestoreSave();
  }

  TerminalSessionRestoreState currentRestoreState() {
    if (_windows.isEmpty) {
      return const TerminalSessionRestoreState();
    }
    return TerminalSessionRestoreState(
      activeWindowIndex: _activeWindowIndex.clamp(0, _windows.length - 1),
      windows: _windows
          .map(
            (window) => window.tabsController.currentRestoreWindow(
              fallbackTitle: window.title,
            ),
          )
          .toList(growable: false),
    );
  }

  TerminalWindowController _createWindow({required String fallbackTitle}) {
    _nextWindowId += 1;
    final tabsController = TerminalTabsController(
      backendFactory: backendFactory,
      clipboardClient: clipboardClient,
      settingsController: settingsController,
      savedCommandsController: savedCommandsController,
      completionRepository: completionRepository,
      completionEnvironment: completionEnvironment,
      initialBlocksForSession: initialBlocksForSession,
      onRestoreStateChanged: _scheduleRestoreSave,
    );
    final window = TerminalWindowController(
      id: _nextWindowId,
      fallbackTitle: fallbackTitle,
      tabsController: tabsController,
    );
    _trackWindow(window);
    return window;
  }

  void _restoreWindows(TerminalSessionRestoreState restoreState) {
    _restoreSaveSuspended = true;
    try {
      _disposeAllWindows();
      _nextWindowId = 0;
      for (final restoreWindow in restoreState.windows) {
        final window = _createWindow(
          fallbackTitle: restoreWindow.fallbackTitle,
        );
        window.tabsController.restoreWindowState(restoreWindow);
        _windows.add(window);
      }
      _activeWindowIndex = restoreState.activeWindowIndex.clamp(
        0,
        _windows.length - 1,
      );
    } finally {
      _restoreSaveSuspended = false;
    }
  }

  void _trackWindow(TerminalWindowController window) {
    void listener() {
      if (_restoreSaveSuspended) {
        return;
      }
      notifyListeners();
    }

    _windowListeners[window.tabsController] = listener;
    window.tabsController.addListener(listener);
  }

  void _untrackWindow(TerminalWindowController window) {
    final listener = _windowListeners.remove(window.tabsController);
    if (listener != null) {
      window.tabsController.removeListener(listener);
    }
  }

  void _disposeAllWindows() {
    for (final window in _windows) {
      _untrackWindow(window);
      window.tabsController.dispose();
    }
    _windows.clear();
    _activeWindowIndex = -1;
  }

  void _notifyAndScheduleRestoreSave() {
    _scheduleRestoreSave();
    notifyListeners();
  }

  void _scheduleRestoreSave() {
    if (_restoreSaveSuspended || _windows.isEmpty) {
      return;
    }
    sessionRestoreController?.scheduleSave(currentRestoreState());
  }

  @override
  void dispose() {
    if (_windows.isNotEmpty) {
      sessionRestoreController?.saveNow(currentRestoreState());
    }
    _disposeAllWindows();
    super.dispose();
  }
}
