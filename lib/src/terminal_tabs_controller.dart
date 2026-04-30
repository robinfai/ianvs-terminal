import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'clipboard_client.dart';
import 'fig_completion.dart';
import 'local_shell_session_controller.dart';
import 'saved_commands.dart';
import 'session_restore.dart';
import 'shell_integration.dart';
import 'terminal_blocks.dart';
import 'terminal_panes.dart';
import 'terminal_settings.dart';

class TerminalTabController {
  TerminalTabController({
    required this.id,
    required this.fallbackTitle,
    required TerminalPaneLeaf initialPane,
  }) : _rootPane = initialPane,
       _activePaneId = initialPane.id;

  TerminalTabController.restored({
    required this.id,
    required this.fallbackTitle,
    required TerminalPaneNode rootPane,
    required int activePaneId,
  }) : _rootPane = rootPane,
       _activePaneId = rootPane.containsPane(activePaneId)
           ? activePaneId
           : rootPane.leaves.first.id;

  final int id;
  final String fallbackTitle;
  TerminalPaneNode _rootPane;
  int _activePaneId;

  TerminalPaneNode get rootPane => _rootPane;
  List<TerminalPaneLeaf> get panes => _rootPane.leaves;
  int get paneCount => _rootPane.paneCount;
  TerminalPaneLeaf get activePane =>
      panes.firstWhere((pane) => pane.id == _activePaneId);
  LocalShellSessionController get activeShell => activePane.shellController;
  bool get canCloseActivePane => paneCount > 1;

  String get title {
    final windowTitle = activeShell.windowTitle?.trim();
    if (windowTitle != null && windowTitle.isNotEmpty) {
      return windowTitle;
    }
    return fallbackTitle;
  }

  bool selectPane(int paneId) {
    if (!_rootPane.containsPane(paneId) || paneId == _activePaneId) {
      return false;
    }
    _activePaneId = paneId;
    return true;
  }

  void splitActivePane({
    required TerminalPaneSplitDirection direction,
    required TerminalPaneLeaf newPane,
  }) {
    _rootPane = _splitPane(_rootPane, _activePaneId, direction, newPane);
    _activePaneId = newPane.id;
  }

  bool nextPane() {
    return _selectPaneByDelta(1);
  }

  bool previousPane() {
    return _selectPaneByDelta(-1);
  }

  TerminalPaneLeaf? closeActivePane() {
    if (!canCloseActivePane) {
      return null;
    }
    final currentLeaves = panes;
    final activeIndex = currentLeaves.indexWhere(
      (pane) => pane.id == _activePaneId,
    );
    final nextActiveIndex = activeIndex >= currentLeaves.length - 1
        ? activeIndex - 1
        : activeIndex + 1;
    final nextActivePaneId = currentLeaves[nextActiveIndex].id;
    final result = _removePane(_rootPane, _activePaneId);
    if (result == null) {
      return null;
    }
    _rootPane = result.replacement;
    _activePaneId = nextActivePaneId;
    return result.removed;
  }

  bool _selectPaneByDelta(int delta) {
    final currentLeaves = panes;
    if (currentLeaves.length < 2) {
      return false;
    }
    final activeIndex = currentLeaves.indexWhere(
      (pane) => pane.id == _activePaneId,
    );
    if (activeIndex < 0) {
      return false;
    }
    final nextIndex = (activeIndex + delta) % currentLeaves.length;
    _activePaneId =
        currentLeaves[nextIndex < 0
                ? nextIndex + currentLeaves.length
                : nextIndex]
            .id;
    return true;
  }
}

class TerminalTabsController extends ChangeNotifier {
  TerminalTabsController({
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

  final List<TerminalTabController> _tabs = <TerminalTabController>[];
  int _nextTabId = 0;
  int _nextPaneId = 0;
  int _activeIndex = -1;
  bool _restoreSaveSuspended = false;

  List<TerminalTabController> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  TerminalTabController get activeTab => _tabs[_activeIndex];
  TerminalPaneLeaf get activePane => activeTab.activePane;
  LocalShellSessionController get activeShell => activePane.shellController;
  bool get canCloseActiveTab => _tabs.length > 1;
  bool get canCloseActivePane => activeTab.canCloseActivePane;

  void createInitialTab() {
    if (_tabs.isNotEmpty) {
      return;
    }
    final restoreState = sessionRestoreController?.load();
    if (restoreState != null && restoreState.hasTabs) {
      _restoreTabs(restoreState);
      _scheduleRestoreSave();
      notifyListeners();
      return;
    }
    newTab();
  }

  void newTab() {
    _nextTabId += 1;
    final initialPane = _createPane();
    final tab = TerminalTabController(
      id: _nextTabId,
      fallbackTitle: 'Local $_nextTabId',
      initialPane: initialPane,
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    initialPane.shellController.start();
    _notifyAndScheduleRestoreSave();
  }

  void selectTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) {
      return;
    }
    _activeIndex = index;
    _notifyAndScheduleRestoreSave();
  }

  void nextTab() {
    if (_tabs.length < 2) {
      return;
    }
    _activeIndex = (_activeIndex + 1) % _tabs.length;
    _notifyAndScheduleRestoreSave();
  }

  void previousTab() {
    if (_tabs.length < 2) {
      return;
    }
    _activeIndex = _activeIndex <= 0 ? _tabs.length - 1 : _activeIndex - 1;
    _notifyAndScheduleRestoreSave();
  }

  void splitActivePaneRight() {
    _splitActivePane(TerminalPaneSplitDirection.right);
  }

  void splitActivePaneDown() {
    _splitActivePane(TerminalPaneSplitDirection.down);
  }

  void selectPane(int paneId) {
    if (activeTab.selectPane(paneId)) {
      _notifyAndScheduleRestoreSave();
    }
  }

  void nextPane() {
    if (activeTab.nextPane()) {
      _notifyAndScheduleRestoreSave();
    }
  }

  void previousPane() {
    if (activeTab.previousPane()) {
      _notifyAndScheduleRestoreSave();
    }
  }

  void closeActivePane() {
    final removed = activeTab.closeActivePane();
    if (removed == null) {
      return;
    }
    removed.shellController.removeListener(_handleTabChanged);
    removed.shellController.dispose();
    _notifyAndScheduleRestoreSave();
  }

  void updatePaneSplitRatio(TerminalPaneSplit split, double ratio) {
    split.updateRatio(ratio);
    _notifyAndScheduleRestoreSave();
  }

  void closeActiveTab() {
    if (_activeIndex < 0) {
      return;
    }
    closeTab(_activeIndex);
  }

  void closeTab(int index) {
    if (_tabs.length <= 1 || index < 0 || index >= _tabs.length) {
      return;
    }
    final removed = _tabs.removeAt(index);
    for (final pane in removed.panes) {
      pane.shellController.removeListener(_handleTabChanged);
      pane.shellController.dispose();
    }
    if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    } else if (index < _activeIndex) {
      _activeIndex -= 1;
    } else if (index == _activeIndex) {
      _activeIndex = index.clamp(0, _tabs.length - 1).toInt();
    }
    _notifyAndScheduleRestoreSave();
  }

  void _handleTabChanged() {
    _notifyAndScheduleRestoreSave();
  }

  void _splitActivePane(TerminalPaneSplitDirection direction) {
    final newPane = _createPane(
      launchCwd: activeShell.completionController.cwd,
    );
    activeTab.splitActivePane(direction: direction, newPane: newPane);
    newPane.shellController.start();
    _notifyAndScheduleRestoreSave();
  }

  TerminalPaneLeaf _createPane({int? id, String? launchCwd}) {
    final paneId = id ?? _nextPaneId + 1;
    _nextPaneId = _nextPaneId < paneId ? paneId : _nextPaneId;
    final shellController = _createShellController(launchCwd: launchCwd);
    shellController.addListener(_handleTabChanged);
    return TerminalPaneLeaf(id: paneId, shellController: shellController);
  }

  LocalShellSessionController _createShellController({String? launchCwd}) {
    return LocalShellSessionController(
      backendFactory: backendFactory,
      clipboardClient: clipboardClient,
      initialBlocksForSession: initialBlocksForSession,
      savedCommandsController: savedCommandsController,
      completionRepository: completionRepository,
      completionEnvironment: completionEnvironment,
      sessionConfigFactory: () {
        final baseConfig = settingsController.settings.toSessionConfig();
        return applyShellIntegration(
          _sessionConfigWithLaunchCwd(baseConfig, launchCwd),
        );
      },
    );
  }

  void _restoreTabs(TerminalSessionRestoreState restoreState) {
    _restoreSaveSuspended = true;
    try {
      _tabs.clear();
      _nextTabId = 0;
      _nextPaneId = 0;
      for (final restoreTab in restoreState.tabs) {
        _nextTabId += 1;
        final rootPane = _createPaneTreeFromRestore(restoreTab.rootPane);
        final tab = TerminalTabController.restored(
          id: _nextTabId,
          fallbackTitle: restoreTab.fallbackTitle,
          rootPane: rootPane,
          activePaneId: restoreTab.activePaneId,
        );
        _tabs.add(tab);
      }
      _activeIndex = restoreState.activeTabIndex.clamp(0, _tabs.length - 1);
      for (final tab in _tabs) {
        for (final pane in tab.panes) {
          pane.shellController.start();
        }
      }
    } finally {
      _restoreSaveSuspended = false;
    }
  }

  TerminalPaneNode _createPaneTreeFromRestore(
    TerminalSessionRestorePaneNode node,
  ) {
    if (node is TerminalSessionRestorePaneLeaf) {
      return _createPane(id: node.id, launchCwd: node.cwd);
    }
    final split = node as TerminalSessionRestorePaneSplit;
    return TerminalPaneSplit(
      direction: split.direction,
      ratio: split.ratio,
      first: _createPaneTreeFromRestore(split.first),
      second: _createPaneTreeFromRestore(split.second),
    );
  }

  void _notifyAndScheduleRestoreSave() {
    _scheduleRestoreSave();
    notifyListeners();
  }

  void _scheduleRestoreSave() {
    if (_restoreSaveSuspended || _tabs.isEmpty) {
      return;
    }
    sessionRestoreController?.scheduleSave(currentRestoreState());
  }

  TerminalSessionRestoreState currentRestoreState() {
    if (_tabs.isEmpty) {
      return const TerminalSessionRestoreState();
    }
    return TerminalSessionRestoreState(
      activeTabIndex: _activeIndex.clamp(0, _tabs.length - 1),
      tabs: _tabs.map(_restoreTabFor).toList(growable: false),
    );
  }

  TerminalSessionRestoreTab _restoreTabFor(TerminalTabController tab) {
    return TerminalSessionRestoreTab(
      fallbackTitle: tab.fallbackTitle,
      activePaneId: tab.activePane.id,
      rootPane: _restorePaneNodeFor(tab.rootPane),
    );
  }

  TerminalSessionRestorePaneNode _restorePaneNodeFor(TerminalPaneNode node) {
    if (node is TerminalPaneLeaf) {
      return TerminalSessionRestorePaneLeaf(
        id: node.id,
        cwd: _effectiveRestoreCwd(
          node.shellController.completionController.cwd,
        ),
      );
    }
    final split = node as TerminalPaneSplit;
    return TerminalSessionRestorePaneSplit(
      direction: split.direction,
      ratio: split.ratio,
      first: _restorePaneNodeFor(split.first),
      second: _restorePaneNodeFor(split.second),
    );
  }

  String _effectiveRestoreCwd(String? cwd) {
    return _existingDirectoryOrNull(cwd) ??
        _existingDirectoryOrNull(
          settingsController.settings.toSessionConfig().launch.cwd,
        ) ??
        _existingDirectoryOrNull(Platform.environment['HOME']) ??
        Directory.current.path;
  }

  @override
  void dispose() {
    if (_tabs.isNotEmpty) {
      sessionRestoreController?.saveNow(currentRestoreState());
    }
    for (final tab in _tabs) {
      for (final pane in tab.panes) {
        pane.shellController.removeListener(_handleTabChanged);
        pane.shellController.dispose();
      }
    }
    _tabs.clear();
    super.dispose();
  }
}

TerminalPaneNode _splitPane(
  TerminalPaneNode node,
  int targetPaneId,
  TerminalPaneSplitDirection direction,
  TerminalPaneLeaf newPane,
) {
  if (node is TerminalPaneLeaf) {
    if (node.id != targetPaneId) {
      return node;
    }
    return TerminalPaneSplit(
      direction: direction,
      first: node,
      second: newPane,
    );
  }
  final split = node as TerminalPaneSplit;
  if (split.first.containsPane(targetPaneId)) {
    split.first = _splitPane(split.first, targetPaneId, direction, newPane);
  } else if (split.second.containsPane(targetPaneId)) {
    split.second = _splitPane(split.second, targetPaneId, direction, newPane);
  }
  return split;
}

_PaneRemoval? _removePane(TerminalPaneNode node, int paneId) {
  if (node is TerminalPaneLeaf) {
    if (node.id != paneId) {
      return null;
    }
    return _PaneRemoval(removed: node, replacement: node);
  }
  final split = node as TerminalPaneSplit;
  if (split.first.containsPane(paneId)) {
    final removal = _removePane(split.first, paneId);
    if (removal == null) {
      return null;
    }
    final replacement =
        split.first is TerminalPaneLeaf &&
            (split.first as TerminalPaneLeaf).id == paneId
        ? split.second
        : split;
    if (identical(replacement, split)) {
      split.first = removal.replacement;
    }
    return _PaneRemoval(removed: removal.removed, replacement: replacement);
  }
  if (split.second.containsPane(paneId)) {
    final removal = _removePane(split.second, paneId);
    if (removal == null) {
      return null;
    }
    final replacement =
        split.second is TerminalPaneLeaf &&
            (split.second as TerminalPaneLeaf).id == paneId
        ? split.first
        : split;
    if (identical(replacement, split)) {
      split.second = removal.replacement;
    }
    return _PaneRemoval(removed: removal.removed, replacement: replacement);
  }
  return null;
}

class _PaneRemoval {
  const _PaneRemoval({required this.removed, required this.replacement});

  final TerminalPaneLeaf removed;
  final TerminalPaneNode replacement;
}

terminal.TerminalSessionConfig _sessionConfigWithLaunchCwd(
  terminal.TerminalSessionConfig config,
  String? cwd,
) {
  final effectiveCwd = _existingDirectoryOrNull(cwd);
  if (effectiveCwd == null) {
    return config;
  }
  return config.copyWith(launch: config.launch.copyWith(cwd: effectiveCwd));
}

String? _existingDirectoryOrNull(String? cwd) {
  final candidate = cwd?.trim();
  if (candidate == null || candidate.isEmpty) {
    return null;
  }
  try {
    if (Directory(candidate).existsSync()) {
      return candidate;
    }
  } catch (_) {
    return null;
  }
  return null;
}
