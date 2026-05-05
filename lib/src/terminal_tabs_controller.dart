import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'clipboard_client.dart';
import 'fig_completion.dart';
import 'launch_config.dart';
import 'local_shell_session_controller.dart';
import 'platform_paths.dart';
import 'saved_commands.dart';
import 'session_launch.dart';
import 'session_metadata.dart';
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
    final metadataTitle = activeShell.sessionMetadata.preferredTabTitle;
    if (metadataTitle != null) {
      return metadataTitle;
    }
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
    return detachPane(_activePaneId);
  }

  TerminalPaneLeaf? detachPane(int paneId) {
    if (paneCount <= 1 || !_rootPane.containsPane(paneId)) {
      return null;
    }
    final currentLeaves = panes;
    final activeIndex = currentLeaves.indexWhere((pane) => pane.id == paneId);
    if (activeIndex < 0) {
      return null;
    }
    final nextActiveIndex = activeIndex >= currentLeaves.length - 1
        ? activeIndex - 1
        : activeIndex + 1;
    final nextActivePaneId = currentLeaves[nextActiveIndex].id;
    final result = _removePane(_rootPane, paneId);
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
    this.onRestoreStateChanged,
  });

  final PtyBackendFactory backendFactory;
  final ClipboardClient clipboardClient;
  final TerminalSettingsController settingsController;
  final SavedCommandsController savedCommandsController;
  final FigCompletionRepository? completionRepository;
  final Map<String, String> completionEnvironment;
  final TerminalBlockSeedFactory? initialBlocksForSession;
  final TerminalSessionRestoreController? sessionRestoreController;
  final VoidCallback? onRestoreStateChanged;

  final List<TerminalTabController> _tabs = <TerminalTabController>[];
  final Map<LocalShellSessionController, VoidCallback> _paneRestoreListeners =
      <LocalShellSessionController, VoidCallback>{};
  final Map<LocalShellSessionController, String> _paneRestoreCwds =
      <LocalShellSessionController, String>{};
  final Map<LocalShellSessionController, TerminalSessionMetadata>
  _paneRestoreMetadata =
      <LocalShellSessionController, TerminalSessionMetadata>{};
  final Map<LocalShellSessionController, TerminalSessionLaunchProfile>
  _paneRestoreLaunchProfiles =
      <LocalShellSessionController, TerminalSessionLaunchProfile>{};
  final Map<LocalShellSessionController, List<TerminalBlock>>
  _paneRestoreBlocks = <LocalShellSessionController, List<TerminalBlock>>{};
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
  bool get canMoveActivePaneToNewTab => activeTab.canCloseActivePane;

  TerminalLaunchConfiguration currentLaunchConfiguration() {
    return TerminalLaunchConfiguration(
      scope: TerminalLaunchConfigurationScope.app,
      activeWindowIndex: 0,
      windows: <TerminalLaunchConfigurationWindow>[
        currentLaunchConfigurationWindow(),
      ],
    );
  }

  TerminalLaunchConfiguration currentTabLaunchConfiguration({
    int? tabIndex,
    String fallbackWindowTitle = 'Window 1',
  }) {
    final index = tabIndex ?? _activeIndex;
    if (index < 0 || index >= _tabs.length) {
      return const TerminalLaunchConfiguration(
        scope: TerminalLaunchConfigurationScope.tab,
      );
    }
    return TerminalLaunchConfiguration(
      scope: TerminalLaunchConfigurationScope.tab,
      activeWindowIndex: 0,
      windows: <TerminalLaunchConfigurationWindow>[
        TerminalLaunchConfigurationWindow(
          fallbackTitle: fallbackWindowTitle,
          activeTabIndex: 0,
          tabs: <TerminalLaunchConfigurationTab>[
            _launchConfigurationTabFor(_tabs[index]),
          ],
        ),
      ],
    );
  }

  TerminalLaunchConfigurationWindow currentLaunchConfigurationWindow({
    String fallbackTitle = 'Window 1',
  }) {
    return TerminalLaunchConfigurationWindow(
      fallbackTitle: fallbackTitle,
      activeTabIndex: _tabs.isEmpty
          ? 0
          : _activeIndex.clamp(0, _tabs.length - 1),
      tabs: _tabs.map(_launchConfigurationTabFor).toList(growable: false),
    );
  }

  void createInitialTab() {
    if (_tabs.isNotEmpty) {
      return;
    }
    final restoreState = sessionRestoreController?.load();
    final restoreWindow = restoreState?.activeWindow;
    if (restoreWindow != null && restoreWindow.tabs.isNotEmpty) {
      restoreWindowState(restoreWindow);
      _scheduleRestoreSave();
      notifyListeners();
      return;
    }
    newTab();
  }

  void newTab() {
    _newSessionTab(
      fallbackTitle: 'Local ${_nextTabId + 1}',
      sessionMetadata: const TerminalSessionMetadata(),
      launchProfile: const TerminalSessionLaunchProfile.localShell(),
    );
  }

  void newSshTab({
    required String host,
    String account = '',
    String environment = '',
    String project = '',
  }) {
    final metadata = TerminalSessionMetadata(
      kind: TerminalSessionKind.ssh,
      host: host,
      account: account,
      environment: environment,
      project: project,
    );
    _newSessionTab(
      fallbackTitle: metadata.preferredTabTitle ?? 'SSH ${_nextTabId + 1}',
      sessionMetadata: metadata,
      launchProfile: TerminalSessionLaunchProfile.sshCommand(
        host: host,
        account: account,
      ),
    );
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
    _disposePane(removed);
    _notifyAndScheduleRestoreSave();
  }

  bool moveActivePaneToNewTab() {
    if (!canMoveActivePaneToNewTab) {
      return false;
    }
    final movedPane = activeTab.detachPane(activePane.id);
    if (movedPane == null) {
      return false;
    }
    _nextTabId += 1;
    final tab = TerminalTabController(
      id: _nextTabId,
      fallbackTitle: 'Local $_nextTabId',
      initialPane: movedPane,
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _notifyAndScheduleRestoreSave();
    return true;
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
      _disposePane(pane);
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

  void updatePaneStartupCommands(Map<int, String?> commandsByPaneId) {
    if (commandsByPaneId.isEmpty) {
      return;
    }
    for (final tab in _tabs) {
      for (final pane in tab.panes) {
        if (!commandsByPaneId.containsKey(pane.id)) {
          continue;
        }
        pane.shellController.updateStartupCommand(commandsByPaneId[pane.id]);
      }
    }
  }

  void applyLaunchConfiguration(TerminalLaunchConfiguration configuration) {
    final window = configuration.activeWindow;
    if (window == null || window.tabs.isEmpty) {
      return;
    }
    applyLaunchConfigurationWindow(window);
  }

  void applyLaunchConfigurationWindow(
    TerminalLaunchConfigurationWindow window,
  ) {
    _restoreSaveSuspended = true;
    try {
      _disposeAllTabs();
      _nextTabId = 0;
      _nextPaneId = 0;
      for (final launchTab in window.tabs) {
        _nextTabId += 1;
        final rootPane = _createPaneTreeFromLaunchConfiguration(
          launchTab.rootPane,
        );
        final tab = TerminalTabController.restored(
          id: _nextTabId,
          fallbackTitle: launchTab.fallbackTitle,
          rootPane: rootPane,
          activePaneId: launchTab.activePaneId,
        );
        _tabs.add(tab);
      }
      _activeIndex = window.activeTabIndex.clamp(0, _tabs.length - 1);
      for (final tab in _tabs) {
        for (final pane in tab.panes) {
          pane.shellController.start();
        }
      }
    } finally {
      _restoreSaveSuspended = false;
    }
    _notifyAndScheduleRestoreSave();
  }

  void _handleTabChanged() {
    notifyListeners();
  }

  void _newSessionTab({
    required String fallbackTitle,
    required TerminalSessionMetadata sessionMetadata,
    required TerminalSessionLaunchProfile launchProfile,
  }) {
    _nextTabId += 1;
    final initialPane = _createPane(
      sessionMetadata: sessionMetadata,
      launchProfile: launchProfile,
    );
    final tab = TerminalTabController(
      id: _nextTabId,
      fallbackTitle: fallbackTitle,
      initialPane: initialPane,
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    initialPane.shellController.start();
    _notifyAndScheduleRestoreSave();
  }

  void _splitActivePane(TerminalPaneSplitDirection direction) {
    final newPane = _createPane(
      launchCwd: activeShell.completionController.cwd,
      sessionMetadata: activeShell.sessionMetadata,
      launchProfile: activeShell.sessionLaunchProfile,
    );
    activeTab.splitActivePane(direction: direction, newPane: newPane);
    newPane.shellController.start();
    _notifyAndScheduleRestoreSave();
  }

  TerminalPaneLeaf _createPane({
    int? id,
    String? launchCwd,
    String? startupCommand,
    List<TerminalBlock> initialBlocks = const <TerminalBlock>[],
    TerminalSessionMetadata sessionMetadata = const TerminalSessionMetadata(),
    TerminalSessionLaunchProfile launchProfile =
        const TerminalSessionLaunchProfile.localShell(),
  }) {
    final paneId = id ?? _nextPaneId + 1;
    _nextPaneId = _nextPaneId < paneId ? paneId : _nextPaneId;
    final shellController = _createShellController(
      launchCwd: launchCwd,
      startupCommand: startupCommand,
      initialBlocks: initialBlocks,
      sessionMetadata: sessionMetadata,
      launchProfile: launchProfile,
    );
    shellController.addListener(_handleTabChanged);
    _trackPaneRestoreState(shellController);
    return TerminalPaneLeaf(id: paneId, shellController: shellController);
  }

  LocalShellSessionController _createShellController({
    String? launchCwd,
    String? startupCommand,
    List<TerminalBlock> initialBlocks = const <TerminalBlock>[],
    TerminalSessionMetadata sessionMetadata = const TerminalSessionMetadata(),
    TerminalSessionLaunchProfile launchProfile =
        const TerminalSessionLaunchProfile.localShell(),
  }) {
    late final LocalShellSessionController controller;
    controller = LocalShellSessionController(
      backendFactory: backendFactory,
      clipboardClient: clipboardClient,
      initialBlocks: initialBlocks,
      initialBlocksForSession: initialBlocksForSession,
      initialCwd: _effectiveRestoreCwd(launchCwd),
      startupCommand: startupCommand,
      sessionMetadata: sessionMetadata,
      sessionLaunchProfile: launchProfile,
      savedCommandsController: savedCommandsController,
      completionRepository: completionRepository,
      completionEnvironment: completionEnvironment,
      sessionConfigFactory: () {
        final baseConfig = settingsController.settings.toSessionConfig();
        final config = controller.sessionLaunchProfile.applyTo(
          _sessionConfigWithLaunchCwd(
            baseConfig,
            controller.completionController.cwd,
          ),
        );
        return applyShellIntegration(config);
      },
    );
    return controller;
  }

  void restoreWindowState(TerminalSessionRestoreWindow window) {
    _restoreSaveSuspended = true;
    try {
      _disposeAllTabs();
      _nextTabId = 0;
      _nextPaneId = 0;
      for (final restoreTab in window.tabs) {
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
      _activeIndex = window.activeTabIndex.clamp(0, _tabs.length - 1);
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
      return _createPane(
        id: node.id,
        launchCwd: node.cwd,
        initialBlocks: node.blocks,
        sessionMetadata: node.sessionMetadata,
        launchProfile: node.launchProfile,
      );
    }
    final split = node as TerminalSessionRestorePaneSplit;
    return TerminalPaneSplit(
      direction: split.direction,
      ratio: split.ratio,
      first: _createPaneTreeFromRestore(split.first),
      second: _createPaneTreeFromRestore(split.second),
    );
  }

  TerminalPaneNode _createPaneTreeFromLaunchConfiguration(
    TerminalLaunchConfigurationPaneNode node,
  ) {
    if (node is TerminalLaunchConfigurationPaneLeaf) {
      return _createPane(
        id: node.id,
        launchCwd: node.cwd,
        startupCommand: node.startupCommand,
        sessionMetadata: node.sessionMetadata,
        launchProfile: node.launchProfile,
      );
    }
    final split = node as TerminalLaunchConfigurationPaneSplit;
    return TerminalPaneSplit(
      direction: split.direction,
      ratio: split.ratio,
      first: _createPaneTreeFromLaunchConfiguration(split.first),
      second: _createPaneTreeFromLaunchConfiguration(split.second),
    );
  }

  void _notifyAndScheduleRestoreSave() {
    _scheduleRestoreSave();
    notifyListeners();
  }

  void _trackPaneRestoreState(LocalShellSessionController shellController) {
    _paneRestoreCwds[shellController] =
        shellController.completionController.cwd;
    _paneRestoreMetadata[shellController] = shellController.sessionMetadata;
    _paneRestoreLaunchProfiles[shellController] =
        shellController.sessionLaunchProfile;
    _paneRestoreBlocks[shellController] = _restorableBlocks(shellController);
    void listener() {
      final nextCwd = shellController.completionController.cwd;
      final nextMetadata = shellController.sessionMetadata;
      final nextLaunchProfile = shellController.sessionLaunchProfile;
      final nextBlocks = _restorableBlocks(shellController);
      final cwdUnchanged = _paneRestoreCwds[shellController] == nextCwd;
      final metadataUnchanged =
          _paneRestoreMetadata[shellController] == nextMetadata;
      final launchUnchanged =
          _paneRestoreLaunchProfiles[shellController] == nextLaunchProfile;
      final blocksUnchanged = listEquals(
        _paneRestoreBlocks[shellController],
        nextBlocks,
      );
      if (cwdUnchanged &&
          metadataUnchanged &&
          launchUnchanged &&
          blocksUnchanged) {
        return;
      }
      _paneRestoreCwds[shellController] = nextCwd;
      _paneRestoreMetadata[shellController] = nextMetadata;
      _paneRestoreLaunchProfiles[shellController] = nextLaunchProfile;
      _paneRestoreBlocks[shellController] = nextBlocks;
      _scheduleRestoreSave();
    }

    _paneRestoreListeners[shellController] = listener;
    shellController.completionController.addListener(listener);
    shellController.addListener(listener);
  }

  void _untrackPaneRestoreState(LocalShellSessionController shellController) {
    final listener = _paneRestoreListeners.remove(shellController);
    if (listener != null) {
      shellController.completionController.removeListener(listener);
      shellController.removeListener(listener);
    }
    _paneRestoreCwds.remove(shellController);
    _paneRestoreMetadata.remove(shellController);
    _paneRestoreLaunchProfiles.remove(shellController);
    _paneRestoreBlocks.remove(shellController);
  }

  void _disposePane(TerminalPaneLeaf pane) {
    pane.shellController.removeListener(_handleTabChanged);
    _untrackPaneRestoreState(pane.shellController);
    pane.shellController.dispose();
  }

  void _scheduleRestoreSave() {
    if (_restoreSaveSuspended || _tabs.isEmpty) {
      return;
    }
    sessionRestoreController?.scheduleSave(currentRestoreState());
    onRestoreStateChanged?.call();
  }

  TerminalSessionRestoreState currentRestoreState() {
    return TerminalSessionRestoreState(
      activeWindowIndex: 0,
      windows: <TerminalSessionRestoreWindow>[currentRestoreWindow()],
    );
  }

  TerminalSessionRestoreWindow currentRestoreWindow({
    String fallbackTitle = 'Window 1',
  }) {
    return TerminalSessionRestoreWindow(
      fallbackTitle: fallbackTitle,
      activeTabIndex: _tabs.isEmpty
          ? 0
          : _activeIndex.clamp(0, _tabs.length - 1),
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
        blocks: _restorableBlocks(node.shellController),
        sessionMetadata: node.shellController.sessionMetadata,
        launchProfile: node.shellController.sessionLaunchProfile,
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
        _existingDirectoryOrNull(defaultUserHomePath()) ??
        Directory.current.path;
  }

  List<TerminalBlock> _restorableBlocks(
    LocalShellSessionController shellController,
  ) {
    return shellController.blocksController.blocks
        .where((block) => block.status != TerminalBlockStatus.running)
        .toList(growable: false);
  }

  @override
  void dispose() {
    if (_tabs.isNotEmpty) {
      sessionRestoreController?.saveNow(currentRestoreState());
    }
    _disposeAllTabs();
    super.dispose();
  }

  TerminalLaunchConfigurationTab _launchConfigurationTabFor(
    TerminalTabController tab,
  ) {
    return TerminalLaunchConfigurationTab(
      fallbackTitle: tab.fallbackTitle,
      activePaneId: tab.activePane.id,
      rootPane: _launchConfigurationPaneNodeFor(tab.rootPane),
    );
  }

  TerminalLaunchConfigurationPaneNode _launchConfigurationPaneNodeFor(
    TerminalPaneNode node,
  ) {
    if (node is TerminalPaneLeaf) {
      return TerminalLaunchConfigurationPaneLeaf(
        id: node.id,
        cwd: _effectiveRestoreCwd(
          node.shellController.completionController.cwd,
        ),
        startupCommand: node.shellController.startupCommand ?? '',
        sessionMetadata: node.shellController.sessionMetadata,
        launchProfile: node.shellController.sessionLaunchProfile,
      );
    }
    final split = node as TerminalPaneSplit;
    return TerminalLaunchConfigurationPaneSplit(
      direction: split.direction,
      ratio: split.ratio,
      first: _launchConfigurationPaneNodeFor(split.first),
      second: _launchConfigurationPaneNodeFor(split.second),
    );
  }

  void _disposeAllTabs() {
    for (final tab in _tabs) {
      for (final pane in tab.panes) {
        _disposePane(pane);
      }
    }
    _tabs.clear();
    _activeIndex = -1;
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
