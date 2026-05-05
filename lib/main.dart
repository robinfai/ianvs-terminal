import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'src/clipboard_client.dart';
import 'src/command_history.dart';
import 'src/command_palette.dart';
import 'src/fig_completion.dart';
import 'src/launch_config.dart';
import 'src/local_shell_session_controller.dart';
import 'src/modern_input_controller.dart';
import 'src/modern_input_editing.dart';
import 'src/saved_commands.dart';
import 'src/session_launch.dart';
import 'src/session_metadata.dart';
import 'src/session_restore.dart';
import 'src/terminal_blocks.dart';
import 'src/terminal_panes.dart';
import 'src/terminal_settings.dart';
import 'src/terminal_windows.dart';
import 'src/workspace_search.dart';

void main() {
  runApp(IanvsTerminalApp(sessionRestoreStore: TerminalSessionRestoreStore()));
}

int debugTerminalFocusNodeCount(Element element) {
  final shellState =
      element is StatefulElement && element.state is _IanvsTerminalShellState
      ? element.state as _IanvsTerminalShellState
      : element.findAncestorStateOfType<_IanvsTerminalShellState>();
  return shellState?._terminalFocusNodes.length ?? 0;
}

class IanvsTerminalApp extends StatelessWidget {
  const IanvsTerminalApp({
    super.key,
    this.backendFactory,
    this.clipboardClient,
    this.settingsStore,
    this.savedCommandsStore,
    this.sessionRestoreStore,
    this.launchConfigStore,
    this.sessionRestoreDebounceDuration = const Duration(milliseconds: 250),
    this.completionRepository,
    this.completionEnvironment,
    this.initialBlocksForSession,
  });

  final PtyBackendFactory? backendFactory;
  final ClipboardClient? clipboardClient;
  final TerminalSettingsStore? settingsStore;
  final SavedCommandsStore? savedCommandsStore;
  final TerminalSessionRestoreStore? sessionRestoreStore;
  final TerminalLaunchConfigurationStore? launchConfigStore;
  final Duration sessionRestoreDebounceDuration;
  final FigCompletionRepository? completionRepository;
  final Map<String, String>? completionEnvironment;
  final TerminalBlockSeedFactory? initialBlocksForSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ianvs Terminal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4D8DFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF111318),
        useMaterial3: true,
      ),
      home: IanvsTerminalShell(
        backendFactory: backendFactory ?? NativePtyBackend.load,
        clipboardClient: clipboardClient ?? const FlutterClipboardClient(),
        settingsStore: settingsStore,
        savedCommandsStore: savedCommandsStore,
        sessionRestoreStore: sessionRestoreStore,
        launchConfigStore: launchConfigStore,
        sessionRestoreDebounceDuration: sessionRestoreDebounceDuration,
        completionRepository: completionRepository,
        completionEnvironment: completionEnvironment,
        initialBlocksForSession: initialBlocksForSession,
      ),
    );
  }
}

class IanvsTerminalShell extends StatefulWidget {
  const IanvsTerminalShell({
    super.key,
    required this.backendFactory,
    required this.clipboardClient,
    this.settingsStore,
    this.savedCommandsStore,
    this.sessionRestoreStore,
    this.launchConfigStore,
    this.sessionRestoreDebounceDuration = const Duration(milliseconds: 250),
    this.completionRepository,
    this.completionEnvironment,
    this.initialBlocksForSession,
  });

  final PtyBackendFactory backendFactory;
  final ClipboardClient clipboardClient;
  final TerminalSettingsStore? settingsStore;
  final SavedCommandsStore? savedCommandsStore;
  final TerminalSessionRestoreStore? sessionRestoreStore;
  final TerminalLaunchConfigurationStore? launchConfigStore;
  final Duration sessionRestoreDebounceDuration;
  final FigCompletionRepository? completionRepository;
  final Map<String, String>? completionEnvironment;
  final TerminalBlockSeedFactory? initialBlocksForSession;

  @override
  State<IanvsTerminalShell> createState() => _IanvsTerminalShellState();
}

class _IanvsTerminalShellState extends State<IanvsTerminalShell> {
  final FocusNode _findFocusNode = FocusNode(debugLabel: 'ianvs-find');
  final FocusNode _commandHistoryFocusNode = FocusNode(
    debugLabel: 'ianvs-command-history',
  );
  final FocusNode _workspaceSearchFocusNode = FocusNode(
    debugLabel: 'ianvs-workspace-search',
  );
  final FocusNode _modernInputFocusNode = FocusNode(
    debugLabel: 'ianvs-modern-input',
  );
  final TextEditingController _findTextController = TextEditingController();
  final TextEditingController _commandHistoryTextController =
      TextEditingController();
  final TextEditingController _workspaceSearchTextController =
      TextEditingController();
  late final TerminalSettingsController _settingsController;
  late final SavedCommandsController _savedCommandsController;
  late final TerminalLaunchConfigurationStore _launchConfigStore;
  TerminalSessionRestoreController? _sessionRestoreController;
  late final TerminalWindowsController _tabsController;
  late final CommandPaletteController _commandPaletteController;
  final Map<int, FocusNode> _terminalFocusNodes = <int, FocusNode>{};
  int? _lastActiveTabId;
  int? _lastActivePaneId;
  ModernInputEffectiveMode? _lastInputMode;
  bool? _lastCanAcceptInput;
  String? _lastLaunchConfigPath;
  CommandPaletteFilter _paletteOpenFilter = CommandPaletteFilter.commands;

  @override
  void initState() {
    super.initState();
    _settingsController = TerminalSettingsController(
      store: widget.settingsStore ?? TerminalSettingsStore(),
    );
    _launchConfigStore =
        widget.launchConfigStore ?? const TerminalLaunchConfigurationStore();
    _savedCommandsController = SavedCommandsController(
      store: widget.savedCommandsStore ?? SavedCommandsStore(),
    );
    final sessionRestoreStore = widget.sessionRestoreStore;
    if (sessionRestoreStore != null) {
      _sessionRestoreController = TerminalSessionRestoreController(
        store: sessionRestoreStore,
        debounceDuration: widget.sessionRestoreDebounceDuration,
      );
    }
    _tabsController = TerminalWindowsController(
      backendFactory: widget.backendFactory,
      clipboardClient: widget.clipboardClient,
      settingsController: _settingsController,
      savedCommandsController: _savedCommandsController,
      completionRepository:
          widget.completionRepository ?? FigCompletionRepository.assets(),
      completionEnvironment:
          widget.completionEnvironment ?? Platform.environment,
      initialBlocksForSession: widget.initialBlocksForSession,
      sessionRestoreController: _sessionRestoreController,
    )..addListener(_syncActiveTabState);
    _commandPaletteController = CommandPaletteController(
      windowsController: _tabsController,
      savedCommandsController: _savedCommandsController,
      launchConfigStore: _launchConfigStore,
    );
    _tabsController.createInitialWindow();
  }

  @override
  void dispose() {
    _tabsController.removeListener(_syncActiveTabState);
    _commandPaletteController.dispose();
    _tabsController.dispose();
    _sessionRestoreController?.dispose();
    _savedCommandsController.dispose();
    _settingsController.dispose();
    _workspaceSearchTextController.dispose();
    _commandHistoryTextController.dispose();
    _findTextController.dispose();
    _modernInputFocusNode.dispose();
    _workspaceSearchFocusNode.dispose();
    _commandHistoryFocusNode.dispose();
    _findFocusNode.dispose();
    for (final focusNode in _terminalFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _syncActiveTabState() {
    _pruneTerminalFocusNodes();
    if (_tabsController.tabs.isEmpty) {
      return;
    }
    final activeTab = _tabsController.activeTab;
    final activePane = _tabsController.activePane;
    final activeShell = activePane.shellController;
    final canAcceptInput = activeShell.canAcceptInput;
    final terminalFocusNode = _terminalFocusNodeForPane(activePane.id);
    terminalFocusNode.canRequestFocus = canAcceptInput;
    for (final entry in _terminalFocusNodes.entries) {
      if (entry.key != activePane.id) {
        entry.value.canRequestFocus = false;
      }
    }
    if (!canAcceptInput && terminalFocusNode.hasFocus) {
      terminalFocusNode.unfocus();
    }
    final activeTargetChanged =
        _lastActiveTabId != activeTab.id || _lastActivePaneId != activePane.id;
    final inputMode = activeShell.modernInputController.state.effectiveMode;
    final inputModeChanged = _lastInputMode != inputMode;
    final inputAvailabilityChanged = _lastCanAcceptInput != canAcceptInput;
    if (activeTargetChanged) {
      _lastActiveTabId = activeTab.id;
      _lastActivePaneId = activePane.id;
      _findTextController.text = activeShell.findState.query;
      _commandHistoryTextController.text = _commandPaletteController.query;
      _workspaceSearchTextController.text = _commandPaletteController.query;
    }
    _lastInputMode = inputMode;
    _lastCanAcceptInput = canAcceptInput;
    if (activeTargetChanged || inputModeChanged || inputAvailabilityChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusActiveShellInput();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _tabsController,
        _settingsController,
        _commandPaletteController,
      ]),
      builder: (context, _) {
        final activeShell = _tabsController.activeShell;
        return Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                const _NewWindowIntent(),
            const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
                const _NewTabIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyW,
              meta: true,
              shift: true,
            ): const _CloseWindowIntent(),
            const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
                const _CloseTabIntent(),
            const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
                const _SplitPaneRightIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyD,
              meta: true,
              shift: true,
            ): const _SplitPaneDownIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyW,
              meta: true,
              alt: true,
            ): const _ClosePaneIntent(),
            const SingleActivator(
              LogicalKeyboardKey.bracketRight,
              meta: true,
              alt: true,
            ): const _NextPaneIntent(),
            const SingleActivator(
              LogicalKeyboardKey.bracketLeft,
              meta: true,
              alt: true,
            ): const _PreviousPaneIntent(),
            const SingleActivator(
              LogicalKeyboardKey.bracketRight,
              meta: true,
              shift: true,
            ): const _NextTabIntent(),
            const SingleActivator(
              LogicalKeyboardKey.bracketLeft,
              meta: true,
              shift: true,
            ): const _PreviousTabIntent(),
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                const _OpenFindIntent(),
            const SingleActivator(LogicalKeyboardKey.comma, meta: true):
                const _OpenSettingsIntent(),
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                const _OpenModernInputIntent(),
            const SingleActivator(LogicalKeyboardKey.keyR, meta: true):
                const _OpenCommandHistoryIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyO,
              meta: true,
              shift: true,
            ): const _OpenWorkspaceSearchIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyI,
              meta: true,
              shift: true,
            ): const _ToggleRawInputIntent(),
            if (_commandPaletteController.isOpen)
              const SingleActivator(LogicalKeyboardKey.escape):
                  const _CloseCommandHistoryIntent(),
            if (_commandPaletteController.isOpen)
              const SingleActivator(LogicalKeyboardKey.arrowDown):
                  const _NextCommandHistoryIntent(),
            if (_commandPaletteController.isOpen)
              const SingleActivator(LogicalKeyboardKey.arrowUp):
                  const _PreviousCommandHistoryIntent(),
            if (_commandPaletteController.isOpen)
              const SingleActivator(LogicalKeyboardKey.enter):
                  const _ChooseCommandHistoryIntent(),
            if (activeShell.findState.isOpen)
              const SingleActivator(LogicalKeyboardKey.escape):
                  const _CloseFindIntent(),
            if (activeShell.findState.isOpen)
              const SingleActivator(LogicalKeyboardKey.enter):
                  const _NextFindIntent(),
            if (activeShell.findState.isOpen)
              const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                  const _PreviousFindIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _NewWindowIntent: CallbackAction<_NewWindowIntent>(
                onInvoke: (_) {
                  _tabsController.newWindow();
                  return null;
                },
              ),
              _NewTabIntent: CallbackAction<_NewTabIntent>(
                onInvoke: (_) {
                  _tabsController.newTab();
                  return null;
                },
              ),
              _CloseWindowIntent: CallbackAction<_CloseWindowIntent>(
                onInvoke: (_) {
                  _tabsController.closeActiveWindow();
                  return null;
                },
              ),
              _CloseTabIntent: CallbackAction<_CloseTabIntent>(
                onInvoke: (_) {
                  _tabsController.closeActiveTab();
                  return null;
                },
              ),
              _SplitPaneRightIntent: CallbackAction<_SplitPaneRightIntent>(
                onInvoke: (_) {
                  _tabsController.splitActivePaneRight();
                  return null;
                },
              ),
              _SplitPaneDownIntent: CallbackAction<_SplitPaneDownIntent>(
                onInvoke: (_) {
                  _tabsController.splitActivePaneDown();
                  return null;
                },
              ),
              _ClosePaneIntent: CallbackAction<_ClosePaneIntent>(
                onInvoke: (_) {
                  _tabsController.closeActivePane();
                  return null;
                },
              ),
              _NextPaneIntent: CallbackAction<_NextPaneIntent>(
                onInvoke: (_) {
                  _tabsController.nextPane();
                  return null;
                },
              ),
              _PreviousPaneIntent: CallbackAction<_PreviousPaneIntent>(
                onInvoke: (_) {
                  _tabsController.previousPane();
                  return null;
                },
              ),
              _NextTabIntent: CallbackAction<_NextTabIntent>(
                onInvoke: (_) {
                  _tabsController.nextTab();
                  return null;
                },
              ),
              _PreviousTabIntent: CallbackAction<_PreviousTabIntent>(
                onInvoke: (_) {
                  _tabsController.previousTab();
                  return null;
                },
              ),
              _OpenFindIntent: CallbackAction<_OpenFindIntent>(
                onInvoke: (_) => _openFind(),
              ),
              _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
                onInvoke: (_) {
                  _openSettings();
                  return null;
                },
              ),
              _OpenModernInputIntent: CallbackAction<_OpenModernInputIntent>(
                onInvoke: (_) {
                  _openModernInput();
                  return null;
                },
              ),
              _OpenCommandHistoryIntent:
                  CallbackAction<_OpenCommandHistoryIntent>(
                    onInvoke: (_) => _openCommandHistory(),
                  ),
              _OpenWorkspaceSearchIntent:
                  CallbackAction<_OpenWorkspaceSearchIntent>(
                    onInvoke: (_) => _openWorkspaceSearch(),
                  ),
              _ToggleRawInputIntent: CallbackAction<_ToggleRawInputIntent>(
                onInvoke: (_) {
                  _toggleRawInput();
                  return null;
                },
              ),
              _CloseFindIntent: CallbackAction<_CloseFindIntent>(
                onInvoke: (_) => _closeFind(),
              ),
              _CloseCommandHistoryIntent:
                  CallbackAction<_CloseCommandHistoryIntent>(
                    onInvoke: (_) => _closeCommandHistory(),
                  ),
              _CloseWorkspaceSearchIntent:
                  CallbackAction<_CloseWorkspaceSearchIntent>(
                    onInvoke: (_) => _closeWorkspaceSearch(),
                  ),
              _NextCommandHistoryIntent:
                  CallbackAction<_NextCommandHistoryIntent>(
                    onInvoke: (_) {
                      _commandPaletteController.goToNext();
                      return null;
                    },
                  ),
              _PreviousCommandHistoryIntent:
                  CallbackAction<_PreviousCommandHistoryIntent>(
                    onInvoke: (_) {
                      _commandPaletteController.goToPrevious();
                      return null;
                    },
                  ),
              _ChooseCommandHistoryIntent:
                  CallbackAction<_ChooseCommandHistoryIntent>(
                    onInvoke: (_) {
                      unawaited(_chooseCommandHistoryEntry());
                      return null;
                    },
                  ),
              _NextFindIntent: CallbackAction<_NextFindIntent>(
                onInvoke: (_) {
                  _tabsController.activeShell.goToNextMatch();
                  return null;
                },
              ),
              _PreviousFindIntent: CallbackAction<_PreviousFindIntent>(
                onInvoke: (_) {
                  _tabsController.activeShell.goToPreviousMatch();
                  return null;
                },
              ),
            },
            child: PlatformMenuBar(
              menus: _platformMenus(activeShell),
              child: Scaffold(
                body: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        tabsController: _tabsController,
                        onNewSshSessionRequested: _openNewSshSession,
                        onSearch: _openFind,
                        onWorkspaceSearchRequested: _openWorkspaceSearch,
                        onSettings: _openSettings,
                        onSessionContextRequested: _openSessionContext,
                        onLaunchConfigRequested: _openLaunchConfig,
                        onSavedLaunchConfigsRequested: _openSavedLaunchConfigs,
                        onSaveAppLaunchConfigRequested:
                            _saveAppLaunchConfigFromWindow,
                        onSaveTabLaunchConfigRequested: _saveTabLaunchConfig,
                        onModernInputRequested: _focusModernInput,
                      ),
                      if (activeShell.findState.isOpen)
                        _FindBar(
                          controller: activeShell,
                          textController: _findTextController,
                          focusNode: _findFocusNode,
                          onClose: _closeFind,
                        ),
                      Expanded(child: _bodyForActiveTab()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<PlatformMenuItem> _platformMenus(
    LocalShellSessionController activeShell,
  ) {
    return <PlatformMenuItem>[
      PlatformMenu(
        label: 'Terminal',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Settings',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: _openSettings,
          ),
          PlatformMenuItem(
            label: 'Command Palette',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyR,
              meta: true,
            ),
            onSelected: _openCommandHistory,
          ),
          PlatformMenuItem(
            label: 'Workspace Search',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyO,
              meta: true,
              shift: true,
            ),
            onSelected: _openWorkspaceSearch,
          ),
          PlatformMenuItem(
            label: 'Launch Config',
            onSelected: _openLaunchConfig,
          ),
          PlatformMenuItem(
            label: 'Saved Launch Configs',
            onSelected: _openSavedLaunchConfigs,
          ),
          PlatformMenuItem(
            label: 'New SSH Session',
            onSelected: _openNewSshSession,
          ),
          PlatformMenuItem(
            label: 'Session Context',
            onSelected: _openSessionContext,
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformMenuItem(
                label: 'New Window',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                ),
                onSelected: _tabsController.newWindow,
              ),
              PlatformMenuItem(
                label: 'Close Window',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  meta: true,
                  shift: true,
                ),
                onSelected: _tabsController.canCloseActiveWindow
                    ? _tabsController.closeActiveWindow
                    : null,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformMenuItem(
                label: 'New Tab',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyT,
                  meta: true,
                ),
                onSelected: _tabsController.newTab,
              ),
              PlatformMenuItem(
                label: 'Close Tab',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  meta: true,
                ),
                onSelected: _tabsController.canCloseActiveTab
                    ? _tabsController.closeActiveTab
                    : null,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformMenuItem(
                label: 'Split Right',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyD,
                  meta: true,
                ),
                onSelected: _tabsController.splitActivePaneRight,
              ),
              PlatformMenuItem(
                label: 'Split Down',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyD,
                  meta: true,
                  shift: true,
                ),
                onSelected: _tabsController.splitActivePaneDown,
              ),
              PlatformMenuItem(
                label: 'Close Pane',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  meta: true,
                  alt: true,
                ),
                onSelected: _tabsController.canCloseActivePane
                    ? _tabsController.closeActivePane
                    : null,
              ),
              PlatformMenuItem(
                label: 'Next Pane',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.bracketRight,
                  meta: true,
                  alt: true,
                ),
                onSelected: _tabsController.nextPane,
              ),
              PlatformMenuItem(
                label: 'Previous Pane',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.bracketLeft,
                  meta: true,
                  alt: true,
                ),
                onSelected: _tabsController.previousPane,
              ),
            ],
          ),
          PlatformMenuItem(
            label: 'Restart',
            onSelected: activeShell.canRestart ? activeShell.restart : null,
          ),
        ],
      ),
      PlatformMenu(
        label: 'Edit',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Copy',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyC,
              meta: true,
            ),
            onSelected: activeShell.canCopy
                ? () => unawaited(activeShell.copySelection())
                : null,
          ),
          PlatformMenuItem(
            label: 'Paste',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyV,
              meta: true,
            ),
            onSelected: activeShell.canPaste
                ? () => unawaited(activeShell.pasteClipboard())
                : null,
          ),
          PlatformMenuItem(
            label: 'Find',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyF,
              meta: true,
            ),
            onSelected: _openFind,
          ),
        ],
      ),
    ];
  }

  Widget _bodyForActiveTab() {
    return _PaneTreeView(
      node: _tabsController.activeTab.rootPane,
      activePaneId: _tabsController.activePane.id,
      leafBuilder: _bodyForPane,
      onSplitRatioChanged: _tabsController.updatePaneSplitRatio,
    );
  }

  Widget _bodyForPane(TerminalPaneLeaf pane) {
    final isActivePane = pane.id == _tabsController.activePane.id;
    final shellController = pane.shellController;
    return _PaneChrome(
      paneId: pane.id,
      active: isActivePane,
      showHeader: _tabsController.activeTab.paneCount > 1,
      sessionLabel: 'Pane ${pane.id}',
      contextChips: _paneContextChips(shellController),
      canClose: _tabsController.activeTab.canCloseActivePane,
      canMoveToNewTab: _tabsController.canMoveActivePaneToNewTab,
      canCopy: shellController.canCopy,
      canPaste: shellController.canPaste,
      canRestart: shellController.canRestart,
      onSelected: () {
        _tabsController.selectPane(pane.id);
      },
      onSplitRight: () {
        _tabsController.selectPane(pane.id);
        _tabsController.splitActivePaneRight();
      },
      onSplitDown: () {
        _tabsController.selectPane(pane.id);
        _tabsController.splitActivePaneDown();
      },
      onClose: () {
        _tabsController.selectPane(pane.id);
        _tabsController.closeActivePane();
      },
      onMoveToNewTab: () {
        _tabsController.selectPane(pane.id);
        _tabsController.moveActivePaneToNewTab();
      },
      onSessionContext: () {
        _tabsController.selectPane(pane.id);
        unawaited(_openSessionContext());
      },
      onCopy: () {
        _tabsController.selectPane(pane.id);
        unawaited(shellController.copySelection());
      },
      onPaste: () {
        _tabsController.selectPane(pane.id);
        unawaited(shellController.pasteClipboard());
      },
      onRestart: () {
        _tabsController.selectPane(pane.id);
        shellController.restart();
      },
      child: _bodyForShellState(pane, isActivePane: isActivePane),
    );
  }

  List<_PaneContextChipData> _paneContextChips(
    LocalShellSessionController shellController,
  ) {
    final metadata = shellController.sessionMetadata;
    final targetLabel = metadata.compactContextLabel ?? metadata.kind.label;
    final cwd = shellController.completionController.cwd;
    final cwdLabel = _singleLinePreview(cwd);
    final lastCommand = _lastCompletedCommandPreview(
      shellController.blocksController.blocks,
    );
    return <_PaneContextChipData>[
      _PaneContextChipData(
        keySuffix: 'target',
        label: targetLabel,
        icon: Icons.radio_button_checked,
      ),
      _PaneContextChipData(
        keySuffix: 'cwd',
        label: cwdLabel.isEmpty ? 'cwd pending' : cwdLabel,
        icon: Icons.folder_outlined,
      ),
      _PaneContextChipData(
        keySuffix: 'status',
        label:
            'Status ${_shellStatusLabel(shellController.status, shellController.exitCode)}',
        icon: Icons.circle,
      ),
      if (lastCommand.isNotEmpty)
        _PaneContextChipData(
          keySuffix: 'last-command',
          label: lastCommand,
          icon: Icons.history,
        ),
    ];
  }

  Widget _bodyForShellState(
    TerminalPaneLeaf pane, {
    required bool isActivePane,
  }) {
    final shellController = pane.shellController;
    final startupError = shellController.startupError;
    if (shellController.status == LocalShellStatus.failed &&
        startupError != null) {
      return _StartupError(
        error: startupError,
        onRetry: shellController.restart,
      );
    }

    final inputController = shellController.inputController;
    final sessionId = shellController.sessionId;
    if (inputController == null || sessionId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _TerminalSurface(
      key: ValueKey(shellController),
      paneId: pane.id,
      shellController: shellController,
      inputController: inputController,
      focusNode: _terminalFocusNodeForPane(pane.id),
      modernInputFocusNode: _modernInputFocusNode,
      commandHistoryFocusNode: _commandHistoryFocusNode,
      commandHistoryTextController: _commandHistoryTextController,
      commandPaletteController: _commandPaletteController,
      commandPaletteTextController: _paletteTextControllerForMode(),
      commandPaletteFocusNode: _paletteFocusNodeForMode(),
      commandPaletteMode: _paletteOpenFilter,
      sessionLabel: _sessionLabel(sessionId),
      showSessionContextHeader: _tabsController.activeTab.paneCount > 1,
      inputEnabled: shellController.canAcceptInput,
      isActivePane: isActivePane,
      settings: _settingsController.settings,
      onModernInputRequested: _focusModernInput,
      onRawInputRequested: _focusTerminalInput,
      onCommandHistoryRequested: _openCommandHistory,
      onCommandHistoryClosed: _closeCommandHistory,
      onCommandHistorySelected: _chooseCommandHistoryEntry,
      onSaveCommandRequested: _saveActiveDraft,
      onViewportLaidOut: (viewportSize, measuredCellSize) {
        _resizeSession(shellController, viewportSize, measuredCellSize);
      },
    );
  }

  void _resizeSession(
    LocalShellSessionController shellController,
    Size viewportSize,
    Size? measuredCellSize,
  ) {
    shellController.resizeSession(
      viewportSize,
      View.of(context).devicePixelRatio,
      measuredCellSize: measuredCellSize,
    );
  }

  Object? _openFind() {
    final activeShell = _tabsController.activeShell;
    if (_commandPaletteController.isOpen) {
      _commandPaletteController.close();
      _commandHistoryFocusNode.unfocus();
      _workspaceSearchFocusNode.unfocus();
    }
    activeShell.openFind();
    _findTextController.text = activeShell.findState.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _findFocusNode.requestFocus();
      }
    });
    return null;
  }

  Object? _closeFind() {
    final activeShell = _tabsController.activeShell;
    activeShell.closeFind();
    _findFocusNode.unfocus();
    _focusActiveShellInput();
    return null;
  }

  Object? _openCommandHistory() {
    final activeShell = _tabsController.activeShell;
    if (activeShell.modernInputController.state.effectiveMode ==
        ModernInputEffectiveMode.raw) {
      return null;
    }
    if (activeShell.findState.isOpen) {
      activeShell.closeFind();
      _findFocusNode.unfocus();
    }
    activeShell.completionController.close();
    return _openCommandPalette(filter: CommandPaletteFilter.commands);
  }

  Object? _closeCommandHistory() {
    _commandPaletteController.close();
    _commandHistoryFocusNode.unfocus();
    _workspaceSearchFocusNode.unfocus();
    _focusActiveShellInput();
    return null;
  }

  Object? _openWorkspaceSearch() {
    final activeShell = _tabsController.activeShell;
    if (activeShell.findState.isOpen) {
      activeShell.closeFind();
      _findFocusNode.unfocus();
    }
    activeShell.completionController.close();
    return _openCommandPalette(filter: CommandPaletteFilter.session);
  }

  Object? _openCommandPalette({required CommandPaletteFilter filter}) {
    _paletteOpenFilter = filter;
    _commandPaletteController.open(filter: filter);
    _paletteTextControllerForMode().text = _commandPaletteController.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _paletteFocusNodeForMode().requestFocus();
      }
    });
    return null;
  }

  Object? _closeWorkspaceSearch() {
    return _closeCommandHistory();
  }

  Future<void> _chooseCommandHistoryEntry() async {
    final entry = _commandPaletteController.activeEntry;
    if (entry == null) {
      return;
    }
    if (entry.isLaunchConfigEntry) {
      final config = entry.launchConfig;
      if (config == null) {
        return;
      }
      _tabsController.applyLaunchConfiguration(config.configuration);
      _lastLaunchConfigPath = config.path;
      _commandPaletteController.close();
      if (!mounted) {
        return;
      }
      _commandHistoryFocusNode.unfocus();
      _workspaceSearchFocusNode.unfocus();
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Applied launch config from ${config.path}')),
        );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusActiveShellInput();
        }
      });
      return;
    }
    if (entry.isSessionEntry) {
      _tabsController.selectWindow(entry.windowIndex);
      _tabsController.selectTab(entry.tabIndex);
      _tabsController.selectPane(entry.paneId);
      _commandPaletteController.close();
      if (!mounted) {
        return;
      }
      _commandHistoryFocusNode.unfocus();
      _workspaceSearchFocusNode.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusActiveShellInput();
        }
      });
      return;
    }
    final activeShell = _tabsController.activeShell;
    if (!activeShell.canAcceptInput) {
      return;
    }
    activeShell.modernInputController.useModernInput();
    activeShell.modernInputController.updateDraft(entry.commandText);
    _commandPaletteController.close();
    if (!mounted) {
      return;
    }
    _commandHistoryFocusNode.unfocus();
    _workspaceSearchFocusNode.unfocus();
    _focusModernInput();
  }

  void _saveActiveDraft() {
    final activeShell = _tabsController.activeShell;
    _savedCommandsController.addCommand(
      activeShell.modernInputController.state.draft,
    );
  }

  Future<void> _openSettings() async {
    if (_commandPaletteController.isOpen) {
      _commandPaletteController.close();
      _workspaceSearchFocusNode.unfocus();
      _commandHistoryFocusNode.unfocus();
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return _SettingsPanel(controller: _settingsController);
      },
    );
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusActiveShellInput();
      }
    });
  }

  Future<void> _openSessionContext() async {
    if (_commandPaletteController.isOpen) {
      _commandPaletteController.close();
      _workspaceSearchFocusNode.unfocus();
      _commandHistoryFocusNode.unfocus();
    }
    final activeShell = _tabsController.activeShell;
    final update = await showDialog<_SessionContextUpdate>(
      context: context,
      builder: (context) {
        return _SessionContextPanel(
          initialMetadata: activeShell.sessionMetadata,
          initialLaunchProfile: activeShell.sessionLaunchProfile,
          auditEntryCount: activeShell.buildAuditSnapshot().entries.length,
        );
      },
    );
    if (update != null) {
      activeShell.updateSessionMetadata(update.metadata);
      activeShell.updateSessionLaunchProfile(update.launchProfile);
    }
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusActiveShellInput();
      }
    });
  }

  Future<void> _openNewSshSession() async {
    if (_commandPaletteController.isOpen) {
      _commandPaletteController.close();
      _workspaceSearchFocusNode.unfocus();
      _commandHistoryFocusNode.unfocus();
    }
    final request = await showDialog<_NewSshSessionRequest>(
      context: context,
      builder: (context) => const _NewSshSessionPanel(),
    );
    if (request != null) {
      _tabsController.newSshTab(
        host: request.host,
        account: request.account,
        environment: request.environment,
        project: request.project,
      );
    }
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusActiveShellInput();
      }
    });
  }

  Future<void> _openLaunchConfig() async {
    if (_commandPaletteController.isOpen) {
      _commandPaletteController.close();
      _workspaceSearchFocusNode.unfocus();
      _commandHistoryFocusNode.unfocus();
    }
    final result = await showDialog<_LaunchConfigDialogResult>(
      context: context,
      builder: (context) {
        return _LaunchConfigPanel(
          tabsController: _tabsController,
          store: _launchConfigStore,
          initialPath:
              _lastLaunchConfigPath ??
              _launchConfigStore.suggestedNamedPath('Ianvs Terminal App'),
        );
      },
    );
    if (result != null) {
      _lastLaunchConfigPath = result.path;
    }
    if (!mounted) {
      return;
    }
    if (result?.action == _LaunchConfigDialogAction.applied) {
      final message = 'Applied app config from ${result!.path}';
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusActiveShellInput();
      }
    });
  }

  Future<void> _openSavedLaunchConfigs() async {
    if (_commandPaletteController.isOpen) {
      _commandPaletteController.close();
      _workspaceSearchFocusNode.unfocus();
      _commandHistoryFocusNode.unfocus();
    }
    final result = await showDialog<_SavedLaunchConfigDialogResult>(
      context: context,
      builder: (context) {
        return _SavedLaunchConfigsPanel(
          tabsController: _tabsController,
          store: _launchConfigStore,
        );
      },
    );
    if (result != null) {
      _lastLaunchConfigPath = result.path;
    }
    if (!mounted) {
      return;
    }
    if (result != null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.message)));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusActiveShellInput();
      }
    });
  }

  void _saveAppLaunchConfigFromWindow(int windowIndex) {
    if (windowIndex < 0 || windowIndex >= _tabsController.windows.length) {
      return;
    }
    final window = _tabsController.windows[windowIndex];
    final configuration = _tabsController.currentLaunchConfiguration(
      activeWindowIndex: windowIndex,
    );
    _saveContextLaunchConfig(
      name: '${window.title} App',
      configuration: configuration,
      message: 'Saved app config',
    );
  }

  void _saveTabLaunchConfig(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _tabsController.tabs.length) {
      return;
    }
    final tab = _tabsController.tabs[tabIndex];
    final configuration = _tabsController.currentTabLaunchConfiguration(
      windowIndex: _tabsController.activeWindowIndex,
      tabIndex: tabIndex,
    );
    _saveContextLaunchConfig(
      name: '${tab.title} Tab',
      configuration: configuration,
      message: 'Saved tab config',
    );
  }

  void _saveContextLaunchConfig({
    required String name,
    required TerminalLaunchConfiguration configuration,
    required String message,
  }) {
    if (!configuration.hasTabs) {
      return;
    }
    final path = _launchConfigStore.suggestedNamedPath(name);
    _launchConfigStore.save(File(path), configuration);
    _lastLaunchConfigPath = path;
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$message to $path')));
  }

  void _openModernInput() {
    final activeShell = _tabsController.activeShell;
    activeShell.commandHistoryController.close();
    activeShell.completionController.close();
    if (_commandPaletteController.isOpen) {
      _commandPaletteController.close();
      _workspaceSearchFocusNode.unfocus();
      _commandHistoryFocusNode.unfocus();
    }
    activeShell.modernInputController.useModernInput();
    _commandHistoryFocusNode.unfocus();
    _findFocusNode.unfocus();
    _focusModernInput();
  }

  void _toggleRawInput() {
    final activeShell = _tabsController.activeShell;
    activeShell.commandHistoryController.close();
    activeShell.completionController.close();
    if (_commandPaletteController.isOpen) {
      _commandPaletteController.close();
      _workspaceSearchFocusNode.unfocus();
      _commandHistoryFocusNode.unfocus();
    }
    activeShell.modernInputController.toggleManualRaw();
    _focusActiveShellInput();
  }

  void _focusActiveShellInput() {
    final activeShell = _tabsController.activeShell;
    if (_commandPaletteController.isOpen) {
      _paletteFocusNodeForMode().requestFocus();
      return;
    }
    if (activeShell.findState.isOpen) {
      _findFocusNode.requestFocus();
      return;
    }
    if (!activeShell.canAcceptInput) {
      return;
    }
    if (activeShell.modernInputController.state.effectiveMode ==
        ModernInputEffectiveMode.raw) {
      _focusTerminalInput();
    } else {
      _focusModernInput();
    }
  }

  FocusNode _paletteFocusNodeForMode() {
    return _paletteOpenFilter == CommandPaletteFilter.session
        ? _workspaceSearchFocusNode
        : _commandHistoryFocusNode;
  }

  TextEditingController _paletteTextControllerForMode() {
    return _paletteOpenFilter == CommandPaletteFilter.session
        ? _workspaceSearchTextController
        : _commandHistoryTextController;
  }

  void _focusModernInput() {
    if (_tabsController.activeShell.canAcceptInput) {
      _modernInputFocusNode.requestFocus();
    }
  }

  void _focusTerminalInput() {
    if (_tabsController.activeShell.canAcceptInput) {
      _terminalFocusNodeForPane(_tabsController.activePane.id).requestFocus();
    }
  }

  FocusNode _terminalFocusNodeForPane(int paneId) {
    return _terminalFocusNodes.putIfAbsent(
      paneId,
      () => FocusNode(
        debugLabel: paneId == 1
            ? 'ianvs-terminal'
            : 'ianvs-terminal-pane-$paneId',
      ),
    );
  }

  void _pruneTerminalFocusNodes() {
    final livePaneIds = _tabsController.tabs
        .expand((tab) => tab.panes.map((pane) => pane.id))
        .toSet();
    final retiredPaneIds = _terminalFocusNodes.keys
        .where((paneId) => !livePaneIds.contains(paneId))
        .toList(growable: false);
    for (final paneId in retiredPaneIds) {
      final focusNode = _terminalFocusNodes.remove(paneId);
      if (focusNode == null) {
        continue;
      }
      if (focusNode.hasFocus) {
        focusNode.unfocus();
      }
      focusNode.dispose();
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.tabsController,
    required this.onNewSshSessionRequested,
    required this.onSearch,
    required this.onWorkspaceSearchRequested,
    required this.onSettings,
    required this.onSessionContextRequested,
    required this.onLaunchConfigRequested,
    required this.onSavedLaunchConfigsRequested,
    required this.onSaveAppLaunchConfigRequested,
    required this.onSaveTabLaunchConfigRequested,
    required this.onModernInputRequested,
  });

  final TerminalWindowsController tabsController;
  final VoidCallback onNewSshSessionRequested;
  final VoidCallback onSearch;
  final VoidCallback onWorkspaceSearchRequested;
  final VoidCallback onSettings;
  final VoidCallback onSessionContextRequested;
  final VoidCallback onLaunchConfigRequested;
  final VoidCallback onSavedLaunchConfigsRequested;
  final ValueChanged<int> onSaveAppLaunchConfigRequested;
  final ValueChanged<int> onSaveTabLaunchConfigRequested;
  final VoidCallback onModernInputRequested;

  @override
  Widget build(BuildContext context) {
    final activeShell = tabsController.activeShell;
    final activeTitle = tabsController.activeTab.title;
    return Container(
      key: const Key('terminal-header'),
      height: 68,
      decoration: const BoxDecoration(
        color: Color(0xFF252929),
        border: Border(bottom: BorderSide(color: Color(0xFF3A3E3F))),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 276,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF2C3031),
                border: Border(right: BorderSide(color: Color(0xFF3A3E3F))),
              ),
              child: Row(
                children: const [
                  SizedBox(width: 24),
                  _MacTrafficLight(color: Color(0xFFFF5F57)),
                  SizedBox(width: 17),
                  _MacTrafficLight(color: Color(0xFFFFBD2E)),
                  SizedBox(width: 17),
                  _MacTrafficLight(color: Color(0xFF28C840)),
                  Spacer(),
                  _HeaderChromeIcon(icon: Icons.view_sidebar_outlined),
                  SizedBox(width: 24),
                  _HeaderChromeIcon(icon: Icons.grid_view_outlined),
                  SizedBox(width: 24),
                ],
              ),
            ),
          ),
          Positioned(
            left: 276,
            top: 0,
            bottom: 0,
            width: 384,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF2B3031),
                border: Border(right: BorderSide(color: Color(0xFF3A3E3F))),
              ),
              child: Center(
                child: Text(
                  _shortHeaderTitle(activeTitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD5DBDE),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 660,
            top: 0,
            bottom: 0,
            width: 104,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _HeaderAddMenu(
                  tabsController: tabsController,
                  onNewSshSessionRequested: onNewSshSessionRequested,
                  onLaunchConfigRequested: onLaunchConfigRequested,
                  onSavedLaunchConfigsRequested: onSavedLaunchConfigsRequested,
                  onSaveAppLaunchConfigRequested:
                      onSaveAppLaunchConfigRequested,
                  onSaveTabLaunchConfigRequested:
                      onSaveTabLaunchConfigRequested,
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 17,
                  color: Color(0xFFC7CDD1),
                ),
              ],
            ),
          ),
          Positioned(
            right: 130,
            top: 0,
            bottom: 0,
            child: _HeaderStatusCluster(activeShell: activeShell),
          ),
          Positioned(
            right: 80,
            top: 0,
            bottom: 0,
            child: Center(
              child: _HeaderOverflowMenu(
                tabsController: tabsController,
                activeShell: activeShell,
                onSearch: onSearch,
                onWorkspaceSearchRequested: onWorkspaceSearchRequested,
                onSettings: onSettings,
                onSessionContextRequested: onSessionContextRequested,
              ),
            ),
          ),
          const Positioned(
            right: 24,
            top: 0,
            bottom: 0,
            child: _HeaderProfileBadge(),
          ),
        ],
      ),
    );
  }
}

class _MacTrafficLight extends StatelessWidget {
  const _MacTrafficLight({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 22),
    );
  }
}

class _HeaderChromeIcon extends StatelessWidget {
  const _HeaderChromeIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 28, color: const Color(0xFFB8BEC2));
  }
}

class _HeaderStatusCluster extends StatelessWidget {
  const _HeaderStatusCluster({required this.activeShell});

  final LocalShellSessionController activeShell;

  @override
  Widget build(BuildContext context) {
    final blocks = activeShell.blocksController.blocks;
    final changedFiles = blocks.isEmpty ? 1 : blocks.length;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.file_download_outlined, size: 24),
          const SizedBox(width: 10),
          Text(
            '+$changedFiles',
            style: const TextStyle(
              color: Color(0xFF5ED39A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            '-1',
            style: TextStyle(
              color: Color(0xFFE66F67),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderProfileBadge extends StatelessWidget {
  const _HeaderProfileBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
        ),
        child: const SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.apps, size: 24, color: Color(0xFF7C6CE0)),
        ),
      ),
    );
  }
}

String _shortHeaderTitle(String title) {
  final normalized = title.trim();
  if (normalized.isEmpty) {
    return 'Ianvs Terminal';
  }
  if (normalized.length <= 26) {
    return normalized;
  }
  return '..${normalized.substring(normalized.length - 24)}';
}

class _HeaderOverflowMenu extends StatelessWidget {
  const _HeaderOverflowMenu({
    required this.tabsController,
    required this.activeShell,
    required this.onSearch,
    required this.onWorkspaceSearchRequested,
    required this.onSettings,
    required this.onSessionContextRequested,
  });

  static const String search = 'search';
  static const String workspaceSearch = 'workspace-search';
  static const String settings = 'settings';
  static const String closeWindow = 'close-window';
  static const String splitRight = 'split-right';
  static const String splitDown = 'split-down';
  static const String closePane = 'close-pane';
  static const String sessionContext = 'session-context';
  static const String copy = 'copy';
  static const String paste = 'paste';
  static const String restart = 'restart';

  final TerminalWindowsController tabsController;
  final LocalShellSessionController activeShell;
  final VoidCallback onSearch;
  final VoidCallback onWorkspaceSearchRequested;
  final VoidCallback onSettings;
  final VoidCallback onSessionContextRequested;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('terminal-header-overflow-menu-button'),
      padding: EdgeInsets.zero,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          key: Key('terminal-search-button'),
          value: search,
          child: _HeaderMenuItemLabel(icon: Icons.search, label: 'Search'),
        ),
        const PopupMenuItem<String>(
          key: Key('terminal-workspace-search-button'),
          value: workspaceSearch,
          child: _HeaderMenuItemLabel(
            icon: Icons.travel_explore,
            label: 'Workspace search',
          ),
        ),
        const PopupMenuItem<String>(
          key: Key('terminal-settings-button'),
          value: settings,
          child: _HeaderMenuItemLabel(icon: Icons.tune, label: 'Settings'),
        ),
        PopupMenuItem<String>(
          key: const Key('terminal-close-window-button'),
          value: closeWindow,
          enabled: tabsController.canCloseActiveWindow,
          child: const _HeaderMenuItemLabel(
            icon: Icons.web_asset_off_outlined,
            label: 'Close window',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          key: Key('terminal-split-right-button'),
          value: splitRight,
          child: _HeaderMenuItemLabel(
            icon: Icons.vertical_split,
            label: 'Split right',
          ),
        ),
        const PopupMenuItem<String>(
          key: Key('terminal-split-down-button'),
          value: splitDown,
          child: _HeaderMenuItemLabel(
            icon: Icons.horizontal_split,
            label: 'Split down',
          ),
        ),
        PopupMenuItem<String>(
          key: const Key('terminal-close-pane-button'),
          value: closePane,
          enabled: tabsController.canCloseActivePane,
          child: const _HeaderMenuItemLabel(
            icon: Icons.close_fullscreen,
            label: 'Close pane',
          ),
        ),
        const PopupMenuItem<String>(
          key: Key('terminal-session-context-button'),
          value: sessionContext,
          child: _HeaderMenuItemLabel(
            icon: Icons.security,
            label: 'Session context',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          key: const Key('terminal-copy-button'),
          value: copy,
          enabled: activeShell.canCopy,
          child: const _HeaderMenuItemLabel(icon: Icons.copy, label: 'Copy'),
        ),
        PopupMenuItem<String>(
          key: const Key('terminal-paste-button'),
          value: paste,
          enabled: activeShell.canPaste,
          child: const _HeaderMenuItemLabel(
            icon: Icons.content_paste,
            label: 'Paste',
          ),
        ),
        PopupMenuItem<String>(
          key: const Key('terminal-restart-button'),
          value: restart,
          enabled: activeShell.canRestart,
          child: const _HeaderMenuItemLabel(
            icon: Icons.restart_alt,
            label: 'Restart',
          ),
        ),
      ],
      onSelected: _handleSelected,
      child: const _HeaderMenuButtonChrome(
        tooltip: 'More terminal actions',
        icon: Icons.more_horiz,
      ),
    );
  }

  void _handleSelected(String action) {
    switch (action) {
      case search:
        onSearch();
        break;
      case workspaceSearch:
        onWorkspaceSearchRequested();
        break;
      case settings:
        onSettings();
        break;
      case closeWindow:
        tabsController.closeActiveWindow();
        break;
      case splitRight:
        tabsController.splitActivePaneRight();
        break;
      case splitDown:
        tabsController.splitActivePaneDown();
        break;
      case closePane:
        tabsController.closeActivePane();
        break;
      case sessionContext:
        onSessionContextRequested();
        break;
      case copy:
        unawaited(activeShell.copySelection());
        break;
      case paste:
        unawaited(activeShell.pasteClipboard());
        break;
      case restart:
        activeShell.restart();
        break;
    }
  }
}

class _HeaderMenuButtonChrome extends StatelessWidget {
  const _HeaderMenuButtonChrome({required this.tooltip, required this.icon});

  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 22,
        child: Center(child: Icon(icon, size: 16)),
      ),
    );
  }
}

class _HeaderMenuItemLabel extends StatelessWidget {
  const _HeaderMenuItemLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), const SizedBox(width: 10), Text(label)],
    );
  }
}

class _HeaderAddMenu extends StatelessWidget {
  const _HeaderAddMenu({
    required this.tabsController,
    required this.onNewSshSessionRequested,
    required this.onLaunchConfigRequested,
    required this.onSavedLaunchConfigsRequested,
    required this.onSaveAppLaunchConfigRequested,
    required this.onSaveTabLaunchConfigRequested,
  });

  static const String newTab = 'new-tab';
  static const String newWindow = 'new-window';
  static const String newSsh = 'new-ssh';
  static const String savedConfigs = 'saved-configs';
  static const String saveTabConfig = 'save-tab-config';
  static const String saveAppConfig = 'save-app-config';
  static const String launchConfig = 'launch-config';

  final TerminalWindowsController tabsController;
  final VoidCallback onNewSshSessionRequested;
  final VoidCallback onLaunchConfigRequested;
  final VoidCallback onSavedLaunchConfigsRequested;
  final ValueChanged<int> onSaveAppLaunchConfigRequested;
  final ValueChanged<int> onSaveTabLaunchConfigRequested;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('terminal-add-menu-button'),
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 540, maxWidth: 600),
      itemBuilder: (context) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-new-tab'),
          value: newTab,
          height: 40,
          child: _HeaderMenuItemLabel(
            icon: Icons.tab,
            label: 'New terminal tab',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-new-window'),
          value: newWindow,
          height: 40,
          child: _HeaderMenuItemLabel(
            icon: Icons.web_asset,
            label: 'New terminal window',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-new-ssh'),
          value: newSsh,
          height: 40,
          child: _HeaderMenuItemLabel(
            icon: Icons.dns,
            label: 'New SSH session',
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-saved-configs'),
          value: savedConfigs,
          height: 40,
          child: _HeaderMenuItemLabel(
            icon: Icons.folder_open,
            label: 'Saved launch configs',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-launch-config'),
          value: launchConfig,
          height: 40,
          child: _HeaderMenuItemLabel(
            icon: Icons.rocket_launch,
            label: 'Launch configuration',
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-save-tab-config'),
          value: saveTabConfig,
          height: 40,
          child: _HeaderMenuItemLabel(
            icon: Icons.save_as,
            label: 'Save current tab as config',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-save-app-config'),
          value: saveAppConfig,
          height: 40,
          child: _HeaderMenuItemLabel(
            icon: Icons.save,
            label: 'Save app as config',
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-default-shell'),
          enabled: false,
          height: 40,
          child: _HeaderMenuItemLabel(
            icon: Icons.terminal,
            label: 'Zsh (/bin/zsh)',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-bash-shell'),
          enabled: false,
          height: 40,
          child: _HeaderMenuItemLabel(icon: Icons.terminal, label: 'Bash'),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-add-menu-fish-shell'),
          enabled: false,
          height: 40,
          child: _HeaderMenuItemLabel(icon: Icons.terminal, label: 'Fish'),
        ),
      ],
      onSelected: _handleSelected,
      child: const _HeaderMenuButtonChrome(tooltip: 'Add', icon: Icons.add),
    );
  }

  void _handleSelected(String action) {
    switch (action) {
      case newTab:
        tabsController.newTab();
        break;
      case newWindow:
        tabsController.newWindow();
        break;
      case newSsh:
        onNewSshSessionRequested();
        break;
      case savedConfigs:
        onSavedLaunchConfigsRequested();
        break;
      case saveTabConfig:
        onSaveTabLaunchConfigRequested(tabsController.activeIndex);
        break;
      case saveAppConfig:
        onSaveAppLaunchConfigRequested(tabsController.activeWindowIndex);
        break;
      case launchConfig:
        onLaunchConfigRequested();
        break;
    }
  }
}

// ignore: unused_element
class _BlockToolbar extends StatelessWidget {
  const _BlockToolbar({
    required this.controller,
    required this.reinputEnabled,
    required this.onReinput,
  });

  final TerminalBlocksController controller;
  final bool reinputEnabled;
  final VoidCallback onReinput;

  @override
  Widget build(BuildContext context) {
    final block = controller.activeBlock;
    final commandPreview = block?.commandText.trim() ?? '';
    final statusLabel = block?.status.label ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF252B36)),
      ),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                'Block ${controller.displayIndex}/${controller.blocks.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 58,
              child: Text(
                statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                commandPreview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 11),
              ),
            ),
            _HeaderActionButton(
              key: const Key('terminal-block-previous-button'),
              tooltip: 'Previous block',
              onPressed: controller.hasBlocks
                  ? controller.goToPreviousBlock
                  : null,
              icon: Icons.keyboard_arrow_up,
            ),
            _HeaderActionButton(
              key: const Key('terminal-block-next-button'),
              tooltip: 'Next block',
              onPressed: controller.hasBlocks ? controller.goToNextBlock : null,
              icon: Icons.keyboard_arrow_down,
            ),
            _HeaderActionButton(
              key: const Key('terminal-block-copy-command-button'),
              tooltip: 'Copy block command',
              onPressed: controller.canCopyActiveCommand
                  ? () => unawaited(controller.copyActiveCommand())
                  : null,
              icon: Icons.terminal,
            ),
            _HeaderActionButton(
              key: const Key('terminal-block-copy-output-button'),
              tooltip: 'Copy block output',
              onPressed: controller.canCopyActiveOutput
                  ? () => unawaited(controller.copyActiveOutput())
                  : null,
              icon: Icons.notes,
            ),
            _HeaderActionButton(
              key: const Key('terminal-block-copy-all-button'),
              tooltip: 'Copy block command and output',
              onPressed: controller.canCopyActiveCommandAndOutput
                  ? () => unawaited(controller.copyActiveCommandAndOutput())
                  : null,
              icon: Icons.content_copy,
            ),
            _HeaderActionButton(
              key: const Key('terminal-block-reinput-button'),
              tooltip: 'Reinput block command',
              onPressed: controller.canReinputActiveCommand && reinputEnabled
                  ? () {
                      unawaited(controller.reinputActiveCommand());
                      onReinput();
                    }
                  : null,
              icon: Icons.keyboard_return,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineBlockRail extends StatelessWidget {
  const _InlineBlockRail({
    required this.controller,
    required this.reinputEnabled,
    required this.lightTheme,
    this.expandedActiveBlock = false,
    this.minHeight,
    required this.onReinput,
  });

  final TerminalBlocksController controller;
  final bool reinputEnabled;
  final bool lightTheme;
  final bool expandedActiveBlock;
  final double? minHeight;
  final VoidCallback onReinput;

  @override
  Widget build(BuildContext context) {
    final activeBlock = controller.activeBlock;
    if (activeBlock == null) {
      return const SizedBox.shrink();
    }
    final background = lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF273244);
    return KeyedSubtree(
      key: const Key('terminal-inline-block-row'),
      child: Container(
        key: const Key('terminal-inline-block-rail'),
        constraints: minHeight == null
            ? const BoxConstraints()
            : BoxConstraints(minHeight: minHeight!),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InlineActiveBlockCard(
              controller: controller,
              block: activeBlock,
              reinputEnabled: reinputEnabled,
              lightTheme: lightTheme,
              expandedBody: expandedActiveBlock,
              onReinput: onReinput,
            ),
            if (!expandedActiveBlock) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                key: const Key('terminal-inline-block-context-strip'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (
                      var index = 0;
                      index < controller.blocks.length;
                      index += 1
                    ) ...[
                      if (index > 0)
                        _InlineBlockDivider(
                          key: Key('terminal-inline-block-divider-$index'),
                          lightTheme: lightTheme,
                        ),
                      _InlineBlockChip(
                        key: Key(
                          'terminal-inline-block-chip-${controller.blocks[index].id}',
                        ),
                        index: index,
                        block: controller.blocks[index],
                        active: index == controller.activeIndex,
                        lightTheme: lightTheme,
                        onTap: () => controller.selectBlockAt(index),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ViewportBlockStatusRail extends StatelessWidget {
  const _ViewportBlockStatusRail({
    required this.controller,
    required this.lightTheme,
  });

  final TerminalBlocksController controller;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    final background = lightTheme
        ? const Color(0xEEF8FAFC)
        : const Color(0xEE0B1120);
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF273244);
    return DecoratedBox(
      key: const Key('terminal-block-status-rail'),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(6),
        itemCount: controller.blocks.length,
        separatorBuilder: (context, index) => _ViewportBlockDivider(
          key: Key('terminal-block-status-divider-${index + 1}'),
          lightTheme: lightTheme,
        ),
        itemBuilder: (context, index) {
          final block = controller.blocks[index];
          return _ViewportBlockStatusMarker(
            key: Key('terminal-block-status-marker-${block.id}'),
            block: block,
            index: index,
            active: index == controller.activeIndex,
            lightTheme: lightTheme,
            onTap: () => controller.selectBlockAt(index),
          );
        },
      ),
    );
  }
}

class _ViewportBlockStatusMarker extends StatelessWidget {
  const _ViewportBlockStatusMarker({
    super.key,
    required this.block,
    required this.index,
    required this.active,
    required this.lightTheme,
    required this.onTap,
  });

  final TerminalBlock block;
  final int index;
  final bool active;
  final bool lightTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (statusBackground, statusBorder, statusIndicator) =
        _inlineBlockStatusColors(block.status, lightTheme);
    final textColor = lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    return Tooltip(
      message: _singleLinePreview(block.commandText),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active ? statusBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? statusBorder : const Color(0x00000000),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 6, 5, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 34,
                  decoration: BoxDecoration(
                    color: statusIndicator,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1} ${block.status.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusIndicator,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _singleLinePreview(block.commandText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? textColor : mutedColor,
                          fontSize: 10,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewportBlockDivider extends StatelessWidget {
  const _ViewportBlockDivider({super.key, required this.lightTheme});

  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 1,
        height: 12,
        color: lightTheme ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
      ),
    );
  }
}

class _InlineBlockActionsMenu extends StatelessWidget {
  const _InlineBlockActionsMenu({
    required this.controller,
    required this.reinputEnabled,
    required this.onReinput,
  });

  static const String copyCommand = 'copy-command';
  static const String copyOutput = 'copy-output';
  static const String copyAll = 'copy-all';
  static const String reinput = 'reinput';
  static const String bookmark = 'bookmark';

  final TerminalBlocksController controller;
  final bool reinputEnabled;
  final VoidCallback onReinput;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('terminal-inline-block-actions-button'),
      padding: EdgeInsets.zero,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          key: const Key('terminal-inline-block-copy-command-action'),
          value: copyCommand,
          enabled: controller.canCopyActiveCommand,
          child: const _HeaderMenuItemLabel(
            icon: Icons.terminal,
            label: 'Copy command',
          ),
        ),
        PopupMenuItem<String>(
          key: const Key('terminal-inline-block-copy-output-action'),
          value: copyOutput,
          enabled: controller.canCopyActiveOutput,
          child: const _HeaderMenuItemLabel(
            icon: Icons.notes,
            label: 'Copy output',
          ),
        ),
        PopupMenuItem<String>(
          key: const Key('terminal-inline-block-copy-all-action'),
          value: copyAll,
          enabled: controller.canCopyActiveCommandAndOutput,
          child: const _HeaderMenuItemLabel(
            icon: Icons.content_copy,
            label: 'Copy all',
          ),
        ),
        PopupMenuItem<String>(
          key: const Key('terminal-inline-block-reinput-action'),
          value: reinput,
          enabled: controller.canReinputActiveCommand && reinputEnabled,
          child: const _HeaderMenuItemLabel(
            icon: Icons.keyboard_return,
            label: 'Reinput',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          key: Key('terminal-inline-block-bookmark-action'),
          value: bookmark,
          enabled: false,
          child: _HeaderMenuItemLabel(
            icon: Icons.bookmark_border,
            label: 'Bookmark',
          ),
        ),
      ],
      onSelected: _handleSelected,
      child: const _HeaderMenuButtonChrome(
        tooltip: 'Block actions',
        icon: Icons.more_horiz,
      ),
    );
  }

  void _handleSelected(String action) {
    switch (action) {
      case copyCommand:
        unawaited(controller.copyActiveCommand());
        break;
      case copyOutput:
        unawaited(controller.copyActiveOutput());
        break;
      case copyAll:
        unawaited(controller.copyActiveCommandAndOutput());
        break;
      case reinput:
        unawaited(controller.reinputActiveCommand());
        onReinput();
        break;
      case bookmark:
        break;
    }
  }
}

class _InlineActiveBlockCard extends StatefulWidget {
  const _InlineActiveBlockCard({
    required this.controller,
    required this.block,
    required this.reinputEnabled,
    required this.lightTheme,
    required this.expandedBody,
    required this.onReinput,
  });

  final TerminalBlocksController controller;
  final TerminalBlock block;
  final bool reinputEnabled;
  final bool lightTheme;
  final bool expandedBody;
  final VoidCallback onReinput;

  @override
  State<_InlineActiveBlockCard> createState() => _InlineActiveBlockCardState();
}

class _InlineActiveBlockCardState extends State<_InlineActiveBlockCard> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() {
      _hovered = hovered;
    });
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() {
      _pressed = pressed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (badgeBackground, badgeBorder, badgeIndicator) =
        _inlineBlockStatusColors(widget.block.status, widget.lightTheme);
    final restingBackground = widget.lightTheme
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF111827);
    final hoverBackground = widget.lightTheme
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF172033);
    final pressedBackground = widget.lightTheme
        ? const Color(0xFFEFF6FF)
        : const Color(0xFF1B2942);
    final cardBackground = _pressed
        ? pressedBackground
        : _hovered
        ? hoverBackground
        : restingBackground;
    final cardBorder = _hovered || _pressed ? badgeIndicator : badgeBorder;
    final textColor = widget.lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = widget.lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final outputPreview = _firstOutputLine(widget.block.outputText);
    final outputText = widget.block.outputText.trimRight();
    final commandPreview = widget.expandedBody
        ? widget.block.commandText.trimRight()
        : _singleLinePreview(widget.block.commandText);
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) {
        _setHovered(false);
        _setPressed(false);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const Key('terminal-sticky-block-command-header'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () =>
            widget.controller.selectBlockAt(widget.controller.activeIndex),
        child: AnimatedContainer(
          key: const Key('terminal-inline-active-block-card'),
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          constraints: widget.expandedBody
              ? const BoxConstraints(minHeight: 300)
              : const BoxConstraints(),
          decoration: BoxDecoration(
            color: cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cardBorder),
          ),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: badgeIndicator,
                  shape: BoxShape.circle,
                  border: Border.all(color: badgeBorder),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: badgeBackground,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: badgeBorder),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            child: Text(
                              'Active block',
                              style: TextStyle(
                                color: badgeIndicator,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${widget.controller.displayIndex} of ${widget.controller.blocks.length}',
                          style: TextStyle(
                            color: mutedColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _HeaderActionButton(
                          key: const Key('terminal-block-overview-button'),
                          tooltip: widget.controller.historyPanelOpen
                              ? 'Hide block overview'
                              : 'Show block overview',
                          onPressed: widget.controller.hasBlocks
                              ? widget.controller.toggleHistoryPanel
                              : null,
                          icon: widget.controller.historyPanelOpen
                              ? Icons.view_sidebar
                              : Icons.view_sidebar_outlined,
                        ),
                        const SizedBox(width: 6),
                        _InlineBlockActionsMenu(
                          controller: widget.controller,
                          reinputEnabled: widget.reinputEnabled,
                          onReinput: widget.onReinput,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ConstrainedBox(
                      key: const Key(
                        'terminal-inline-active-block-command-output-body',
                      ),
                      constraints: widget.expandedBody
                          ? const BoxConstraints(minHeight: 230)
                          : const BoxConstraints(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            commandPreview,
                            key: const Key(
                              'terminal-inline-active-block-command-body',
                            ),
                            maxLines: widget.expandedBody ? 3 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              height: widget.expandedBody ? 1.32 : null,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.expandedBody && outputText.isNotEmpty) ...[
                            _ExpandedInlineBlockOutput(
                              outputText: outputText,
                              mutedColor: mutedColor,
                              textColor: textColor,
                            ),
                          ] else if (outputPreview.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              outputPreview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: mutedColor, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedInlineBlockOutput extends StatelessWidget {
  const _ExpandedInlineBlockOutput({
    required this.outputText,
    required this.mutedColor,
    required this.textColor,
  });

  final String outputText;
  final Color mutedColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('terminal-inline-active-block-output-body'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: mutedColor.withValues(alpha: 0.24)),
        ),
      ),
      child: Text(
        outputText,
        maxLines: 7,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor.withValues(alpha: 0.78),
          fontSize: 11,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InlineBlockChip extends StatelessWidget {
  const _InlineBlockChip({
    super.key,
    required this.index,
    required this.block,
    required this.active,
    required this.lightTheme,
    required this.onTap,
  });

  final int index;
  final TerminalBlock block;
  final bool active;
  final bool lightTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (badgeBackground, badgeBorder, badgeIndicator) =
        _inlineBlockStatusColors(block.status, lightTheme);
    final background = active
        ? (lightTheme ? const Color(0xFFEFF6FF) : const Color(0xFF172033))
        : Colors.transparent;
    final borderColor = active ? badgeBorder : const Color(0x00000000);
    final textColor = lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 118, maxWidth: 172),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: badgeIndicator,
                  shape: BoxShape.circle,
                  border: Border.all(color: badgeBorder),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '#${index + 1}',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _singleLinePreview(block.commandText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (active) ...[
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: badgeBackground,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      'Active',
                      style: TextStyle(
                        color: badgeIndicator,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineBlockDivider extends StatelessWidget {
  const _InlineBlockDivider({super.key, required this.lightTheme});

  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 18,
        child: Divider(
          color: lightTheme ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
          thickness: 1,
          height: 1,
        ),
      ),
    );
  }
}

(Color background, Color border, Color indicator) _inlineBlockStatusColors(
  TerminalBlockStatus status,
  bool lightTheme,
) {
  return switch (status) {
    TerminalBlockStatus.running => (
      lightTheme ? const Color(0xFFDCFCE7) : const Color(0xFF052E1A),
      const Color(0xFF166534),
      lightTheme ? const Color(0xFF166534) : const Color(0xFFBBF7D0),
    ),
    TerminalBlockStatus.succeeded => (
      lightTheme ? const Color(0xFFE0F2FE) : const Color(0xFF0F2A3A),
      const Color(0xFF0369A1),
      lightTheme ? const Color(0xFF0369A1) : const Color(0xFFBAE6FD),
    ),
    TerminalBlockStatus.failed => (
      lightTheme ? const Color(0xFFFEE2E2) : const Color(0xFF2A1215),
      const Color(0xFF991B1B),
      lightTheme ? const Color(0xFF991B1B) : const Color(0xFFFECACA),
    ),
    TerminalBlockStatus.interrupted => (
      lightTheme ? const Color(0xFFFEF3C7) : const Color(0xFF2A1F13),
      const Color(0xFF92400E),
      lightTheme ? const Color(0xFF92400E) : const Color(0xFFFDE68A),
    ),
    TerminalBlockStatus.unknown => (
      lightTheme ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
      const Color(0xFF475569),
      lightTheme ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
    ),
  };
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(22),
        minimumSize: const Size.square(22),
        maximumSize: const Size.square(22),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: icon == Icons.restart_alt ? 16 : 14),
    );
  }
}

// ignore: unused_element
class _WindowStrip extends StatelessWidget {
  const _WindowStrip({
    required this.tabsController,
    required this.onSaveAppConfig,
  });

  final TerminalWindowsController tabsController;
  final ValueChanged<int> onSaveAppConfig;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < tabsController.windows.length; index += 1)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _TerminalWindowButton(
                windowId: tabsController.windows[index].id,
                title: tabsController.windows[index].title,
                active: index == tabsController.activeWindowIndex,
                onSelect: () => tabsController.selectWindow(index),
                onSaveAppConfig: () => onSaveAppConfig(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _TerminalWindowButton extends StatelessWidget {
  const _TerminalWindowButton({
    required this.windowId,
    required this.title,
    required this.active,
    required this.onSelect,
    required this.onSaveAppConfig,
  });

  final int windowId;
  final String title;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onSaveAppConfig;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0xFF202632) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: active ? const Color(0xFF4D8DFF) : const Color(0xFF252B36),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: Key('terminal-window-$windowId'),
            onTap: onSelect,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active
                      ? const Color(0xFFE5E7EB)
                      : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
          _StripContextActionButton(
            buttonKey: Key('terminal-window-save-app-config-$windowId'),
            tooltip: 'Save app as config',
            width: 26,
            height: 26,
            icon: Icons.bookmark_add_outlined,
            onPressed: onSaveAppConfig,
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabsController,
    required this.onSaveTabConfig,
  });

  final TerminalWindowsController tabsController;
  final ValueChanged<int> onSaveTabConfig;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < tabsController.tabs.length; index += 1)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _TerminalTabButton(
                tabId: tabsController.tabs[index].id,
                title: tabsController.tabs[index].title,
                active: index == tabsController.activeIndex,
                onSelect: () => tabsController.selectTab(index),
                onSaveTabConfig: () => onSaveTabConfig(index),
                onClose: tabsController.canCloseActiveTab
                    ? () => tabsController.closeTab(index)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _StripContextActionButton extends StatelessWidget {
  const _StripContextActionButton({
    required this.buttonKey,
    required this.tooltip,
    required this.width,
    required this.height,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final double width;
  final double height;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: width,
          height: height,
          child: Icon(icon, size: 14),
        ),
      ),
    );
  }
}

class _TerminalTabButton extends StatelessWidget {
  const _TerminalTabButton({
    required this.tabId,
    required this.title,
    required this.active,
    required this.onSelect,
    required this.onSaveTabConfig,
    this.onClose,
  });

  final int tabId;
  final String title;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onSaveTabConfig;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0xFF202632) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: active ? const Color(0xFF3B4658) : const Color(0xFF252B36),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 34,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: Key('terminal-tab-$title'),
              onTap: onSelect,
              child: SizedBox(
                height: 34,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active
                              ? const Color(0xFFE5E7EB)
                              : const Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 28,
              height: 30,
              child: _StripContextActionButton(
                buttonKey: Key('terminal-tab-save-config-$tabId'),
                tooltip: 'Save tab as config',
                width: 28,
                height: 30,
                icon: Icons.bookmark_add_outlined,
                onPressed: onSaveTabConfig,
              ),
            ),
            SizedBox(
              width: 28,
              height: 30,
              child: IconButton(
                key: Key('terminal-close-tab-$title'),
                tooltip: 'Close $title',
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 30,
                ),
                padding: EdgeInsets.zero,
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaneTreeView extends StatelessWidget {
  const _PaneTreeView({
    required this.node,
    required this.activePaneId,
    required this.leafBuilder,
    required this.onSplitRatioChanged,
  });

  final TerminalPaneNode node;
  final int activePaneId;
  final Widget Function(TerminalPaneLeaf pane) leafBuilder;
  final void Function(TerminalPaneSplit split, double ratio)
  onSplitRatioChanged;

  @override
  Widget build(BuildContext context) {
    final paneNode = node;
    if (paneNode is TerminalPaneLeaf) {
      return leafBuilder(paneNode);
    }
    final split = paneNode as TerminalPaneSplit;
    return LayoutBuilder(
      builder: (context, constraints) {
        final firstFlex = (split.ratio * 1000).round().clamp(1, 999);
        final secondFlex = 1000 - firstFlex;
        final children = <Widget>[
          Expanded(
            flex: firstFlex,
            child: _PaneTreeView(
              node: split.first,
              activePaneId: activePaneId,
              leafBuilder: leafBuilder,
              onSplitRatioChanged: onSplitRatioChanged,
            ),
          ),
          _PaneDivider(
            direction: split.direction,
            onDragDelta: (delta) {
              final extent = split.direction == TerminalPaneSplitDirection.right
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              if (extent <= 0) {
                return;
              }
              onSplitRatioChanged(split, split.ratio + delta / extent);
            },
          ),
          Expanded(
            flex: secondFlex,
            child: _PaneTreeView(
              node: split.second,
              activePaneId: activePaneId,
              leafBuilder: leafBuilder,
              onSplitRatioChanged: onSplitRatioChanged,
            ),
          ),
        ];
        return split.direction == TerminalPaneSplitDirection.right
            ? Row(children: children)
            : Column(children: children);
      },
    );
  }
}

class _PaneDivider extends StatelessWidget {
  const _PaneDivider({required this.direction, required this.onDragDelta});

  final TerminalPaneSplitDirection direction;
  final ValueChanged<double> onDragDelta;

  @override
  Widget build(BuildContext context) {
    final vertical = direction == TerminalPaneSplitDirection.right;
    return MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        key: const Key('terminal-pane-divider'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          onDragDelta(vertical ? details.delta.dx : details.delta.dy);
        },
        child: SizedBox(
          width: vertical ? 6 : double.infinity,
          height: vertical ? double.infinity : 6,
          child: ColoredBox(
            color: const Color(0xFF252B36),
            child: Center(
              child: SizedBox(
                width: vertical ? 1 : 28,
                height: vertical ? 28 : 1,
                child: const ColoredBox(color: Color(0xFF3A4250)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneChrome extends StatelessWidget {
  const _PaneChrome({
    required this.paneId,
    required this.active,
    required this.showHeader,
    required this.sessionLabel,
    required this.contextChips,
    required this.canClose,
    required this.canMoveToNewTab,
    required this.canCopy,
    required this.canPaste,
    required this.canRestart,
    required this.onSelected,
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onClose,
    required this.onMoveToNewTab,
    required this.onSessionContext,
    required this.onCopy,
    required this.onPaste,
    required this.onRestart,
    required this.child,
  });

  final int paneId;
  final bool active;
  final bool showHeader;
  final String sessionLabel;
  final List<_PaneContextChipData> contextChips;
  final bool canClose;
  final bool canMoveToNewTab;
  final bool canCopy;
  final bool canPaste;
  final bool canRestart;
  final VoidCallback onSelected;
  final VoidCallback onSplitRight;
  final VoidCallback onSplitDown;
  final VoidCallback onClose;
  final VoidCallback onMoveToNewTab;
  final VoidCallback onSessionContext;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onRestart;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: Key('terminal-pane-$paneId'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onSelected(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: showHeader
              ? Border.all(
                  color: active
                      ? const Color(0xFF4D8DFF)
                      : const Color(0xFF111827),
                  width: active ? 2 : 1,
                )
              : null,
        ),
        child: Column(
          children: [
            if (showHeader)
              _PaneLocalHeader(
                paneId: paneId,
                active: active,
                sessionLabel: sessionLabel,
                contextChips: contextChips,
                canClose: canClose,
                canMoveToNewTab: canMoveToNewTab,
                canCopy: canCopy,
                canPaste: canPaste,
                canRestart: canRestart,
                onFocus: onSelected,
                onSplitRight: onSplitRight,
                onSplitDown: onSplitDown,
                onClose: onClose,
                onMoveToNewTab: onMoveToNewTab,
                onSessionContext: onSessionContext,
                onCopy: onCopy,
                onPaste: onPaste,
                onRestart: onRestart,
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  if (active)
                    IgnorePointer(
                      child: SizedBox(key: Key('terminal-pane-active-$paneId')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaneLocalHeader extends StatelessWidget {
  const _PaneLocalHeader({
    required this.paneId,
    required this.active,
    required this.sessionLabel,
    required this.contextChips,
    required this.canClose,
    required this.canMoveToNewTab,
    required this.canCopy,
    required this.canPaste,
    required this.canRestart,
    required this.onFocus,
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onClose,
    required this.onMoveToNewTab,
    required this.onSessionContext,
    required this.onCopy,
    required this.onPaste,
    required this.onRestart,
  });

  final int paneId;
  final bool active;
  final String sessionLabel;
  final List<_PaneContextChipData> contextChips;
  final bool canClose;
  final bool canMoveToNewTab;
  final bool canCopy;
  final bool canPaste;
  final bool canRestart;
  final VoidCallback onFocus;
  final VoidCallback onSplitRight;
  final VoidCallback onSplitDown;
  final VoidCallback onClose;
  final VoidCallback onMoveToNewTab;
  final VoidCallback onSessionContext;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final foreground = active
        ? const Color(0xFFE5E7EB)
        : const Color(0xFF94A3B8);
    return Container(
      key: Key('terminal-pane-header-$paneId'),
      height: 30,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF172033) : const Color(0xFF111827),
        border: const Border(bottom: BorderSide(color: Color(0xFF252B36))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 380;
          return Row(
            children: [
              SizedBox(
                key: active ? Key('terminal-pane-active-marker-$paneId') : null,
                width: 4,
                height: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF4D8DFF)
                        : Colors.transparent,
                  ),
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Tooltip(
                  message: 'Pane drag handle',
                  child: SizedBox(
                    key: Key('terminal-pane-drag-handle-$paneId'),
                    width: 18,
                    height: double.infinity,
                    child: const Icon(
                      Icons.drag_indicator,
                      size: 13,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                sessionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (compact)
                const Spacer()
              else ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      key: Key('terminal-pane-context-chips-$paneId'),
                      children: [
                        for (
                          var index = 0;
                          index < contextChips.length;
                          index += 1
                        ) ...[
                          if (index > 0) const SizedBox(width: 6),
                          _PaneContextChip(
                            paneId: paneId,
                            data: contextChips[index],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              _PaneHeaderButton(
                key: Key('terminal-pane-split-right-$paneId'),
                tooltip: 'Split pane right',
                icon: Icons.vertical_split,
                onPressed: onSplitRight,
              ),
              _PaneHeaderButton(
                key: Key('terminal-pane-split-down-$paneId'),
                tooltip: 'Split pane down',
                icon: Icons.horizontal_split,
                onPressed: onSplitDown,
              ),
              _PaneHeaderButton(
                key: Key('terminal-pane-close-$paneId'),
                tooltip: 'Close this pane',
                icon: Icons.close,
                onPressed: canClose ? onClose : null,
              ),
              _PaneHeaderMenu(
                paneId: paneId,
                canClose: canClose,
                canMoveToNewTab: canMoveToNewTab,
                canCopy: canCopy,
                canPaste: canPaste,
                canRestart: canRestart,
                onFocus: onFocus,
                onSplitRight: onSplitRight,
                onSplitDown: onSplitDown,
                onMoveToNewTab: onMoveToNewTab,
                onSessionContext: onSessionContext,
                onCopy: onCopy,
                onPaste: onPaste,
                onRestart: onRestart,
                onClose: onClose,
              ),
              const SizedBox(width: 4),
            ],
          );
        },
      ),
    );
  }
}

class _PaneContextChipData {
  const _PaneContextChipData({
    required this.keySuffix,
    required this.label,
    required this.icon,
  });

  final String keySuffix;
  final String label;
  final IconData icon;
}

class _PaneContextChip extends StatelessWidget {
  const _PaneContextChip({required this.paneId, required this.data});

  final int paneId;
  final _PaneContextChipData data;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      key: Key('terminal-pane-context-chip-$paneId-${data.keySuffix}'),
      constraints: const BoxConstraints(maxWidth: 148),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(data.icon, size: 9, color: const Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaneHeaderMenu extends StatelessWidget {
  const _PaneHeaderMenu({
    required this.paneId,
    required this.canClose,
    required this.canMoveToNewTab,
    required this.canCopy,
    required this.canPaste,
    required this.canRestart,
    required this.onFocus,
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onMoveToNewTab,
    required this.onSessionContext,
    required this.onCopy,
    required this.onPaste,
    required this.onRestart,
    required this.onClose,
  });

  static const String focus = 'focus';
  static const String splitRight = 'split-right';
  static const String splitDown = 'split-down';
  static const String moveToNewTab = 'move-to-new-tab';
  static const String sessionContext = 'session-context';
  static const String copy = 'copy';
  static const String paste = 'paste';
  static const String restart = 'restart';
  static const String close = 'close';

  final int paneId;
  final bool canClose;
  final bool canMoveToNewTab;
  final bool canCopy;
  final bool canPaste;
  final bool canRestart;
  final VoidCallback onFocus;
  final VoidCallback onSplitRight;
  final VoidCallback onSplitDown;
  final VoidCallback onMoveToNewTab;
  final VoidCallback onSessionContext;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onRestart;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: Key('terminal-pane-menu-$paneId'),
      padding: EdgeInsets.zero,
      tooltip: 'Pane actions',
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          key: Key('terminal-pane-menu-focus-$paneId'),
          value: focus,
          child: const _HeaderMenuItemLabel(
            icon: Icons.center_focus_strong,
            label: 'Focus pane',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-pane-menu-split-right-$paneId'),
          value: splitRight,
          child: const _HeaderMenuItemLabel(
            icon: Icons.vertical_split,
            label: 'Split right',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-pane-menu-split-down-$paneId'),
          value: splitDown,
          child: const _HeaderMenuItemLabel(
            icon: Icons.horizontal_split,
            label: 'Split down',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-pane-menu-move-to-new-tab-$paneId'),
          value: moveToNewTab,
          enabled: canMoveToNewTab,
          child: const _HeaderMenuItemLabel(
            icon: Icons.open_in_new,
            label: 'Move to new tab',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-pane-menu-session-context-$paneId'),
          value: sessionContext,
          child: const _HeaderMenuItemLabel(
            icon: Icons.security,
            label: 'Session context',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          key: Key('terminal-pane-menu-copy-$paneId'),
          value: copy,
          enabled: canCopy,
          child: const _HeaderMenuItemLabel(icon: Icons.copy, label: 'Copy'),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-pane-menu-paste-$paneId'),
          value: paste,
          enabled: canPaste,
          child: const _HeaderMenuItemLabel(
            icon: Icons.content_paste,
            label: 'Paste',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-pane-menu-restart-$paneId'),
          value: restart,
          enabled: canRestart,
          child: const _HeaderMenuItemLabel(
            icon: Icons.restart_alt,
            label: 'Restart',
          ),
        ),
        PopupMenuItem<String>(
          key: Key('terminal-pane-menu-close-$paneId'),
          value: close,
          enabled: canClose,
          child: const _HeaderMenuItemLabel(
            icon: Icons.close,
            label: 'Close pane',
          ),
        ),
      ],
      onSelected: _handleSelected,
      child: const SizedBox(
        width: 22,
        height: 24,
        child: Center(
          child: Icon(Icons.more_horiz, size: 13, color: Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  void _handleSelected(String action) {
    switch (action) {
      case focus:
        onFocus();
        break;
      case splitRight:
        onSplitRight();
        break;
      case splitDown:
        onSplitDown();
        break;
      case moveToNewTab:
        onMoveToNewTab();
        break;
      case sessionContext:
        onSessionContext();
        break;
      case copy:
        onCopy();
        break;
      case paste:
        onPaste();
        break;
      case restart:
        onRestart();
        break;
      case close:
        onClose();
        break;
    }
  }
}

class _PaneHeaderButton extends StatelessWidget {
  const _PaneHeaderButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 22, height: 24),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(icon, size: 13),
      style: IconButton.styleFrom(
        fixedSize: const Size(22, 24),
        minimumSize: const Size(22, 24),
        maximumSize: const Size(22, 24),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: const Color(0xFFCBD5E1),
        disabledForegroundColor: const Color(0xFF475569),
      ),
    );
  }
}

class _FindBar extends StatelessWidget {
  const _FindBar({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.onClose,
  });

  final LocalShellSessionController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final state = controller.findState;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Color(0xFF252B36))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              key: const Key('terminal-find-field'),
              focusNode: focusNode,
              controller: textController,
              onChanged: controller.updateFindQuery,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Find',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            child: Text(
              '${state.displayIndex}/${state.matches.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Previous match',
            onPressed: state.matches.isEmpty
                ? null
                : controller.goToPreviousMatch,
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
          ),
          IconButton(
            tooltip: 'Next match',
            onPressed: state.matches.isEmpty ? null : controller.goToNextMatch,
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Close search',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _InlineMenuShell extends StatelessWidget {
  const _InlineMenuShell({
    required this.shellKey,
    required this.lightTheme,
    required this.maxHeight,
    required this.header,
    required this.body,
    this.aliasKeys = const <Key>[],
    this.alignment = Alignment.bottomLeft,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 8),
    this.maxWidth = 720,
  });

  final Key shellKey;
  final List<Key> aliasKeys;
  final bool lightTheme;
  final double maxHeight;
  final Widget header;
  final Widget body;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final background = lightTheme
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF0F172A);
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF273244);
    return Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Material(
            key: shellKey,
            color: background,
            elevation: 10,
            shadowColor: const Color(0x2E000000),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final aliasKey in aliasKeys)
                  SizedBox(key: aliasKey, height: 0),
                header,
                Divider(height: 1, color: borderColor),
                Flexible(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandPalettePanel extends StatefulWidget {
  const _CommandPalettePanel({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.mode,
    required this.chooseEnabled,
    required this.lightTheme,
    required this.onClose,
    required this.onChoose,
    required this.onModernInputRequested,
  });

  final CommandPaletteController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final CommandPaletteFilter mode;
  final bool chooseEnabled;
  final bool lightTheme;
  final VoidCallback onClose;
  final Future<void> Function() onChoose;
  final VoidCallback onModernInputRequested;

  @override
  State<_CommandPalettePanel> createState() => _CommandPalettePanelState();
}

class _CommandPalettePanelState extends State<_CommandPalettePanel> {
  @override
  Widget build(BuildContext context) {
    final matches = widget.controller.matches;
    final textColor = widget.lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = widget.lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final sessionMode = widget.mode == CommandPaletteFilter.session;
    final hintText = sessionMode
        ? 'Search sessions, prompts, and targets'
        : 'Search commands and sessions';
    return _InlineMenuShell(
      shellKey: const Key('terminal-inline-menu-shell-command-palette'),
      aliasKeys: <Key>[
        const Key('terminal-command-palette-panel'),
        Key(
          sessionMode
              ? 'terminal-workspace-search-panel'
              : 'terminal-command-history-panel',
        ),
      ],
      lightTheme: widget.lightTheme,
      maxHeight: 500,
      maxWidth: 600,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Focus(
                    onKeyEvent: _handleKey,
                    child: TextField(
                      key: Key(
                        sessionMode
                            ? 'terminal-workspace-search-field'
                            : 'terminal-command-history-field',
                      ),
                      focusNode: widget.focusNode,
                      controller: widget.textController,
                      onChanged: widget.controller.updateQuery,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: textColor, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: hintText,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${widget.controller.displayIndex}/${matches.length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedColor, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                _PaletteFilterChip(
                  filter: widget.controller.effectiveFilter,
                  lightTheme: widget.lightTheme,
                ),
                const SizedBox(width: 8),
                _HeaderActionButton(
                  tooltip: 'Previous palette result',
                  onPressed: matches.isEmpty
                      ? null
                      : widget.controller.goToPrevious,
                  icon: Icons.keyboard_arrow_up,
                ),
                _HeaderActionButton(
                  tooltip: 'Next palette result',
                  onPressed: matches.isEmpty
                      ? null
                      : widget.controller.goToNext,
                  icon: Icons.keyboard_arrow_down,
                ),
                _HeaderActionButton(
                  tooltip: sessionMode
                      ? 'Close workspace search'
                      : 'Close command history',
                  onPressed: widget.onClose,
                  icon: Icons.close,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PaletteSourceRail(
              controller: widget.controller,
              lightTheme: widget.lightTheme,
              onSelected: _selectFilter,
            ),
          ],
        ),
      ),
      body: matches.isEmpty
          ? Center(
              child: Text(
                sessionMode
                    ? 'No sessions match'
                    : 'No commands or sessions match',
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
            )
          : ListView.separated(
              key: const Key('terminal-command-palette-results-list'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: matches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final entry = matches[index];
                return _CommandPaletteEntryRow(
                  key: Key(
                    entry.isSessionEntry
                        ? 'terminal-workspace-search-row-${entry.id}'
                        : entry.isLaunchConfigEntry
                        ? 'terminal-launch-config-palette-row-${entry.id}'
                        : 'terminal-command-history-row-${entry.id}',
                  ),
                  entry: entry,
                  active: index == widget.controller.activeIndex,
                  chooseEnabled: widget.chooseEnabled,
                  lightTheme: widget.lightTheme,
                  onSave: () {
                    widget.controller.saveEntry(entry);
                  },
                  onRemove: () {
                    widget.controller.removeEntry(entry);
                  },
                  onTap:
                      entry.isSessionEntry ||
                          entry.isLaunchConfigEntry ||
                          widget.chooseEnabled
                      ? () {
                          widget.controller.selectEntryAt(index);
                          unawaited(_choose());
                        }
                      : null,
                );
              },
            ),
    );
  }

  void _selectFilter(CommandPaletteFilter filter) {
    widget.controller.updateFilter(filter);
    if (widget.textController.text != widget.controller.query) {
      widget.textController.value = TextEditingValue(
        text: widget.controller.query,
        selection: TextSelection.collapsed(
          offset: widget.controller.query.length,
        ),
      );
    }
    widget.focusNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.controller.goToNext();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.controller.goToPrevious();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final entry = widget.controller.activeEntry;
      if (entry != null &&
          (entry.isSessionEntry ||
              entry.isLaunchConfigEntry ||
              widget.chooseEnabled)) {
        unawaited(_choose());
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _choose() async {
    final entry = widget.controller.activeEntry;
    await widget.onChoose();
    if (!mounted) {
      return;
    }
    if (entry?.isCommandEntry ?? false) {
      widget.onModernInputRequested();
    }
  }
}

class _PaletteFilterChip extends StatelessWidget {
  const _PaletteFilterChip({required this.filter, required this.lightTheme});

  final CommandPaletteFilter filter;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: Key('terminal-command-palette-filter-${filter.label}'),
      decoration: BoxDecoration(
        color: lightTheme ? const Color(0xFFEFF6FF) : const Color(0xFF172033),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: lightTheme ? const Color(0xFFBFDBFE) : const Color(0xFF334155),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          filter.label,
          style: TextStyle(
            color: lightTheme
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFBFDBFE),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PaletteSourceRail extends StatelessWidget {
  const _PaletteSourceRail({
    required this.controller,
    required this.lightTheme,
    required this.onSelected,
  });

  static const List<CommandPaletteFilter> _filters = <CommandPaletteFilter>[
    CommandPaletteFilter.all,
    CommandPaletteFilter.workflow,
    CommandPaletteFilter.history,
    CommandPaletteFilter.session,
    CommandPaletteFilter.ssh,
    CommandPaletteFilter.launchConfig,
  ];

  final CommandPaletteController controller;
  final bool lightTheme;
  final ValueChanged<CommandPaletteFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('terminal-command-palette-source-rail'),
      height: 226,
      child: Align(
        alignment: Alignment.topLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final filter in _filters)
              _PaletteSourceChip(
                filter: filter,
                count: controller.countForFilter(filter),
                selected: controller.effectiveFilter == filter,
                lightTheme: lightTheme,
                onTap: () => onSelected(filter),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaletteSourceChip extends StatelessWidget {
  const _PaletteSourceChip({
    required this.filter,
    required this.count,
    required this.selected,
    required this.lightTheme,
    required this.onTap,
  });

  final CommandPaletteFilter filter;
  final int count;
  final bool selected;
  final bool lightTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 || filter == CommandPaletteFilter.all;
    final borderColor = selected
        ? const Color(0xFF4D8DFF)
        : lightTheme
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF334155);
    final background = selected
        ? lightTheme
              ? const Color(0xFFEFF6FF)
              : const Color(0xFF172033)
        : lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);
    final foreground = enabled
        ? lightTheme
              ? const Color(0xFF0F172A)
              : const Color(0xFFE5E7EB)
        : const Color(0xFF64748B);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('terminal-command-palette-source-filter-${filter.label}'),
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '${_paletteSourceRailLabel(filter)} $count',
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _paletteSourceRailLabel(CommandPaletteFilter filter) {
  return switch (filter) {
    CommandPaletteFilter.all => 'All',
    CommandPaletteFilter.commands => 'Commands',
    CommandPaletteFilter.workflow => 'Workflows',
    CommandPaletteFilter.saved => 'Saved',
    CommandPaletteFilter.history => 'History',
    CommandPaletteFilter.session => 'Sessions',
    CommandPaletteFilter.ssh => 'SSH',
    CommandPaletteFilter.launchConfig => 'Launch',
  };
}

class _CommandPaletteEntryRow extends StatelessWidget {
  const _CommandPaletteEntryRow({
    super.key,
    required this.entry,
    required this.active,
    required this.chooseEnabled,
    required this.lightTheme,
    required this.onSave,
    required this.onRemove,
    required this.onTap,
  });

  final CommandPaletteEntry entry;
  final bool active;
  final bool chooseEnabled;
  final bool lightTheme;
  final VoidCallback onSave;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final activeBackground = lightTheme
        ? const Color(0xFFEFF6FF)
        : const Color(0xFF172033);
    final hoverBackground = lightTheme
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF111827);
    final textColor = lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: active ? activeBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: hoverBackground,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: active ? const Color(0xFF4D8DFF) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(9, 8, 10, 8),
            child: entry.isSessionEntry
                ? _buildSessionRow(textColor, mutedColor)
                : entry.isLaunchConfigEntry
                ? _buildLaunchConfigRow(textColor, mutedColor)
                : _buildCommandRow(textColor, mutedColor),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionRow(Color textColor, Color mutedColor) {
    final detail = entry.sessionDetailLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                entry.paneLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const _CommandSourceBadge(
              source: CommandPaletteEntrySource.session,
            ),
            const SizedBox(width: 6),
            if (entry.isActivePane)
              const _WorkspaceActiveBadge(label: 'Active')
            else if (entry.isActiveTab)
              const _WorkspaceActiveBadge(label: 'Tab'),
            if (entry.isActivePane || entry.isActiveTab)
              const SizedBox(width: 6),
            _CompactWorkspaceStatusBadge(
              status: entry.status,
              exitCode: entry.exitCode,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _singleLinePreview(entry.tabTitle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (entry.isSshSession) ...[
              const SizedBox(width: 6),
              const _SessionModeBadge(label: 'SSH'),
            ],
          ],
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            detail,
            key: Key('terminal-command-palette-detail-${entry.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
        ],
      ],
    );
  }

  Widget _buildCommandRow(Color textColor, Color mutedColor) {
    final detail = entry.commandDetailLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                entry.isSavedCommandEntry ? 'Save' : entry.windowLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _CommandSourceBadge(source: entry.source),
            if (entry.blockStatus != null) ...[
              const SizedBox(width: 6),
              _BlockPanelStatus(status: entry.blockStatus!),
            ],
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Text(
                _singleLinePreview(entry.commandText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                entry.isSavedCommandEntry
                    ? _singleLinePreview(entry.savedEntry.cwdHint)
                    : entry.outputPreview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mutedColor, fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: entry.isSavedCommandEntry
                  ? 'Remove saved command'
                  : 'Save history command',
              onPressed: entry.isSavedCommandEntry ? onRemove : onSave,
              icon: Icon(
                entry.isSavedCommandEntry
                    ? Icons.bookmark_remove
                    : Icons.bookmark_add,
                size: 16,
              ),
            ),
          ],
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            detail,
            key: Key('terminal-command-palette-detail-${entry.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
        ],
      ],
    );
  }

  Widget _buildLaunchConfigRow(Color textColor, Color mutedColor) {
    final detail = entry.launchConfigDetailLabel;
    final config = entry.launchConfig;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                config?.scopeLabel ?? 'Config',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const _CommandSourceBadge(
              source: CommandPaletteEntrySource.launchConfig,
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Text(
                _singleLinePreview(entry.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                config == null
                    ? ''
                    : '${config.windowCount}w ${config.tabCount}t ${config.paneCount}p',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mutedColor, fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.keyboard_return, size: 16, color: mutedColor),
          ],
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            detail,
            key: Key('terminal-command-palette-detail-${entry.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
        ],
      ],
    );
  }
}

class _SessionModeBadge extends StatelessWidget {
  const _SessionModeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F2A3A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF0369A1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFBAE6FD),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSearchPanel extends StatefulWidget {
  const _WorkspaceSearchPanel({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.onClose,
    required this.onChoose,
  });

  final WorkspaceSearchController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onClose;
  final VoidCallback onChoose;

  @override
  State<_WorkspaceSearchPanel> createState() => _WorkspaceSearchPanelState();
}

class _WorkspaceSearchPanelState extends State<_WorkspaceSearchPanel> {
  @override
  Widget build(BuildContext context) {
    final matches = widget.controller.matches;
    return Container(
      key: const Key('terminal-workspace-search-panel'),
      height: 250,
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Color(0xFF252B36))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 300,
                  child: Focus(
                    onKeyEvent: _handleKey,
                    child: TextField(
                      key: const Key('terminal-workspace-search-field'),
                      focusNode: widget.focusNode,
                      controller: widget.textController,
                      onChanged: widget.controller.updateQuery,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search tabs and panes',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${widget.controller.displayIndex}/${matches.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Enter to jump',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Previous workspace result',
                  onPressed: matches.isEmpty
                      ? null
                      : widget.controller.goToPrevious,
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                ),
                IconButton(
                  tooltip: 'Next workspace result',
                  onPressed: matches.isEmpty
                      ? null
                      : widget.controller.goToNext,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                ),
                IconButton(
                  tooltip: 'Close workspace search',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF252B36)),
          Expanded(
            child: matches.isEmpty
                ? const Center(
                    child: Text(
                      'No open tabs or panes match',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final result = matches[index];
                      return _WorkspaceSearchRow(
                        key: Key('terminal-workspace-search-row-${result.id}'),
                        result: result,
                        active: index == widget.controller.activeIndex,
                        onTap: () {
                          widget.controller.selectResultAt(index);
                          widget.onChoose();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.controller.goToNext();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.controller.goToPrevious();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onChoose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class _WorkspaceSearchRow extends StatelessWidget {
  const _WorkspaceSearchRow({
    super.key,
    required this.result,
    required this.active,
    required this.onTap,
  });

  final WorkspaceSearchResult result;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeBackground = const Color(0xFF172033);
    final hoverBackground = const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: active ? activeBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: hoverBackground,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: active ? const Color(0xFF4D8DFF) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(9, 8, 10, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 82,
                  child: Text(
                    result.paneLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (result.isActivePane)
                  const _WorkspaceActiveBadge(label: 'Active pane')
                else if (result.isActiveTab)
                  const _WorkspaceActiveBadge(label: 'Active tab'),
                if (result.isActivePane || result.isActiveTab)
                  const SizedBox(width: 6),
                _CompactWorkspaceStatusBadge(
                  status: result.status,
                  exitCode: result.exitCode,
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Text(
                    _singleLinePreview(result.tabTitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(
                    _singleLinePreview(result.cwd),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceActiveBadge extends StatelessWidget {
  const _WorkspaceActiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F2A3A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF0369A1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFBAE6FD),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CompactWorkspaceStatusBadge extends StatelessWidget {
  const _CompactWorkspaceStatusBadge({
    required this.status,
    required this.exitCode,
  });

  final LocalShellStatus status;
  final int? exitCode;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (status) {
      LocalShellStatus.starting => (
        const Color(0xFF1E293B),
        const Color(0xFFCBD5E1),
        const Color(0xFF334155),
      ),
      LocalShellStatus.running => (
        const Color(0xFF052E1A),
        const Color(0xFFBBF7D0),
        const Color(0xFF166534),
      ),
      LocalShellStatus.exited => (
        const Color(0xFF2A1F13),
        const Color(0xFFFDE68A),
        const Color(0xFF92400E),
      ),
      LocalShellStatus.failed => (
        const Color(0xFF2A1215),
        const Color(0xFFFECACA),
        const Color(0xFF991B1B),
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          workspaceSearchStatusLabel(status, exitCode).toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SessionBadge extends StatelessWidget {
  const _SessionBadge({
    required this.label,
    this.backgroundColor = const Color(0xFF202632),
    this.borderColor = const Color(0xFF303848),
    this.foregroundColor = const Color(0xFFE2E8F0),
  });

  final String label;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: foregroundColor),
        ),
      ),
    );
  }
}

class _PaneSessionContextHeader extends StatelessWidget {
  const _PaneSessionContextHeader({
    required this.sessionLabel,
    required this.metadata,
    required this.launchProfile,
  });

  final String sessionLabel;
  final TerminalSessionMetadata metadata;
  final TerminalSessionLaunchProfile launchProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          key: const Key('terminal-session-context-strip'),
          spacing: 6,
          runSpacing: 6,
          children: [
            _SessionBadge(
              label: sessionLabel,
              backgroundColor: const Color(0xFF111827),
              borderColor: const Color(0xFF374151),
              foregroundColor: const Color(0xFFCBD5E1),
            ),
            _SessionBadge(
              label: metadata.kind.label,
              backgroundColor: metadata.isSsh
                  ? const Color(0xFF1E293B)
                  : const Color(0xFF202632),
              borderColor: metadata.isSsh
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFF303848),
              foregroundColor: metadata.isSsh
                  ? const Color(0xFFBFDBFE)
                  : const Color(0xFFE2E8F0),
            ),
            if (_transportBadgeLabel(
                  metadata: metadata,
                  launchProfile: launchProfile,
                )
                case final transportLabel?)
              _SessionBadge(
                label: transportLabel,
                backgroundColor: launchProfile.isSshCommand
                    ? const Color(0xFF0F2A3A)
                    : const Color(0xFF2A1F13),
                borderColor: launchProfile.isSshCommand
                    ? const Color(0xFF0369A1)
                    : const Color(0xFF92400E),
                foregroundColor: launchProfile.isSshCommand
                    ? const Color(0xFFBAE6FD)
                    : const Color(0xFFFDE68A),
              ),
            for (final label in metadata.targetBadges)
              _SessionBadge(
                label: label,
                backgroundColor: const Color(0xFF172033),
                borderColor: const Color(0xFF334155),
                foregroundColor: const Color(0xFFCBD5E1),
              ),
          ],
        ),
        if (metadata.safetyContext.badges.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            key: const Key('terminal-session-safety-strip'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in metadata.safetyContext.badges)
                _SessionBadge(
                  label: label,
                  backgroundColor: const Color(0xFF0F2A3A),
                  borderColor: const Color(0xFF0369A1),
                  foregroundColor: const Color(0xFFBAE6FD),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ignore: unused_element
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.exitCode});

  final LocalShellStatus status;
  final int? exitCode;

  @override
  Widget build(BuildContext context) {
    final (label, color, borderColor) = switch (status) {
      LocalShellStatus.starting => (
        'Starting',
        const Color(0xFF1E293B),
        const Color(0xFF334155),
      ),
      LocalShellStatus.running => (
        'Running',
        const Color(0xFF052E1A),
        const Color(0xFF166534),
      ),
      LocalShellStatus.exited => (
        exitCode == null ? 'Exited' : 'Exited $exitCode',
        const Color(0xFF2A1F13),
        const Color(0xFF92400E),
      ),
      LocalShellStatus.failed => (
        'Failed',
        const Color(0xFF2A1215),
        const Color(0xFF991B1B),
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

class _TerminalSurface extends StatelessWidget {
  const _TerminalSurface({
    super.key,
    required this.paneId,
    required this.shellController,
    required this.inputController,
    required this.focusNode,
    required this.modernInputFocusNode,
    required this.commandHistoryFocusNode,
    required this.commandHistoryTextController,
    required this.commandPaletteController,
    required this.commandPaletteTextController,
    required this.commandPaletteFocusNode,
    required this.commandPaletteMode,
    required this.sessionLabel,
    required this.showSessionContextHeader,
    required this.inputEnabled,
    required this.isActivePane,
    required this.settings,
    required this.onModernInputRequested,
    required this.onRawInputRequested,
    required this.onCommandHistoryRequested,
    required this.onCommandHistoryClosed,
    required this.onCommandHistorySelected,
    required this.onSaveCommandRequested,
    required this.onViewportLaidOut,
  });

  final int paneId;
  final LocalShellSessionController shellController;
  final terminal.TerminalInputController inputController;
  final FocusNode focusNode;
  final FocusNode modernInputFocusNode;
  final FocusNode commandHistoryFocusNode;
  final TextEditingController commandHistoryTextController;
  final CommandPaletteController commandPaletteController;
  final TextEditingController commandPaletteTextController;
  final FocusNode commandPaletteFocusNode;
  final CommandPaletteFilter commandPaletteMode;
  final String sessionLabel;
  final bool showSessionContextHeader;
  final bool inputEnabled;
  final bool isActivePane;
  final TerminalSettings settings;
  final VoidCallback onModernInputRequested;
  final VoidCallback onRawInputRequested;
  final VoidCallback onCommandHistoryRequested;
  final VoidCallback onCommandHistoryClosed;
  final Future<void> Function() onCommandHistorySelected;
  final VoidCallback onSaveCommandRequested;
  final void Function(Size viewportSize, Size? measuredCellSize)
  onViewportLaidOut;

  static const EdgeInsets _viewportPadding = EdgeInsets.fromLTRB(
    32,
    14,
    32,
    14,
  );
  static const double _inlineBlockRailLeftPadding = 132;
  static const double _inlineBlockRailDefaultReservedHeight = 132;
  static const double _inlineBlockRailExpandedReservedHeight = 320;

  static double _inlineBlockRailReservedHeightFor(bool blockFirst) {
    return blockFirst
        ? _inlineBlockRailExpandedReservedHeight
        : _inlineBlockRailDefaultReservedHeight;
  }

  static double _inlineBlockRailTopForHeight(
    double viewportHeight, {
    required bool blockFirst,
  }) {
    if (blockFirst) {
      final top = viewportHeight - _inlineBlockRailExpandedReservedHeight;
      return top < 136 ? 136 : top;
    }
    final scaledTop = viewportHeight * (blockFirst ? 0.417 : 0.51);
    final bottomGuard = blockFirst ? 1.0 : 20.0;
    final maxTop =
        viewportHeight -
        _inlineBlockRailReservedHeightFor(blockFirst) -
        bottomGuard;
    final boundedTop = scaledTop > (blockFirst ? 264 : 340)
        ? (blockFirst ? 264.0 : 340.0)
        : scaledTop;
    final minTop = viewportHeight >= 360 ? (blockFirst ? 136.0 : 112.0) : 12.0;
    final effectiveMaxTop = maxTop < minTop ? minTop : maxTop;
    if (boundedTop < minTop) {
      return minTop;
    }
    if (boundedTop > effectiveMaxTop) {
      return effectiveMaxTop;
    }
    return boundedTop;
  }

  static EdgeInsets _viewportPaddingForInlineBlockRail(
    double viewportHeight, {
    required bool blockFirst,
  }) {
    return EdgeInsets.fromLTRB(
      _inlineBlockRailLeftPadding,
      _inlineBlockRailTopForHeight(viewportHeight, blockFirst: blockFirst) +
          _inlineBlockRailReservedHeightFor(blockFirst),
      14,
      14,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawInputActive =
        shellController.modernInputController.state.effectiveMode ==
        ModernInputEffectiveMode.raw;
    focusNode.canRequestFocus = inputEnabled && rawInputActive && isActivePane;
    final colors = settings.themePreset.viewportColors;
    return KeyedSubtree(
      key: Key('terminal-pane-surface-$paneId'),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.canvasBackground),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSessionContextHeader)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                    child: _PaneSessionContextHeader(
                      sessionLabel: sessionLabel,
                      metadata: shellController.sessionMetadata,
                      launchProfile: shellController.sessionLaunchProfile,
                    ),
                  ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: Listenable.merge(<Listenable>[
                      shellController.blocksController,
                      shellController.modernInputController,
                    ]),
                    builder: (context, _) {
                      final lightTheme =
                          settings.themePreset == TerminalThemePreset.light;
                      final inputState =
                          shellController.modernInputController.state;
                      final draftPreview = _singleLinePreview(inputState.draft);
                      final showInlineBlockRail =
                          isActivePane &&
                          shellController.blocksController.hasBlocks;
                      final completionBlockFirst =
                          showInlineBlockRail &&
                          inputState.effectiveMode ==
                              ModernInputEffectiveMode.modern &&
                          draftPreview.isNotEmpty;
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final showBlockHistoryPanel =
                              showInlineBlockRail &&
                              shellController
                                  .blocksController
                                  .historyPanelOpen &&
                              constraints.maxWidth >= 720 &&
                              constraints.maxHeight >= 180;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (context.mounted) {
                                                  onViewportLaidOut(
                                                    Size(
                                                      constraints.maxWidth,
                                                      constraints.maxHeight,
                                                    ),
                                                    null,
                                                  );
                                                }
                                              });
                                          final blockRailContentPadding =
                                              _viewportPaddingForInlineBlockRail(
                                                constraints.maxHeight,
                                                blockFirst:
                                                    completionBlockFirst,
                                              );
                                          return Opacity(
                                            key: completionBlockFirst
                                                ? const Key(
                                                    'terminal-default-viewport-muted-for-completion',
                                                  )
                                                : const Key(
                                                    'terminal-default-viewport-visible',
                                                  ),
                                            opacity: completionBlockFirst
                                                ? 0
                                                : 1,
                                            child: terminal.TerminalViewport(
                                              focusNode: focusNode,
                                              controller: shellController
                                                  .viewportController,
                                              selectionController:
                                                  shellController
                                                      .selectionController,
                                              inputController: inputController,
                                              contentPadding:
                                                  showInlineBlockRail
                                                  ? blockRailContentPadding
                                                  : _viewportPadding,
                                              colors: colors,
                                              font: settings.fontConfig,
                                              onMeasuredCellSizeChanged:
                                                  (measuredCellSize) {
                                                    onViewportLaidOut(
                                                      Size(
                                                        constraints.maxWidth,
                                                        constraints.maxHeight,
                                                      ),
                                                      measuredCellSize,
                                                    );
                                                  },
                                              onScrollLines: (delta) {
                                                shellController.scrollViewport(
                                                  delta,
                                                );
                                              },
                                              onScrollToOffset: (offset) {
                                                shellController
                                                    .scrollViewportTo(offset);
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    if (showInlineBlockRail)
                                      Positioned(
                                        top: _inlineBlockRailTopForHeight(
                                          constraints.maxHeight,
                                          blockFirst: completionBlockFirst,
                                        ),
                                        left: completionBlockFirst ? 0 : 18,
                                        right: completionBlockFirst ? 0 : 18,
                                        child: _InlineBlockRail(
                                          controller:
                                              shellController.blocksController,
                                          reinputEnabled:
                                              shellController.canAcceptInput,
                                          lightTheme: lightTheme,
                                          expandedActiveBlock:
                                              completionBlockFirst,
                                          minHeight: completionBlockFirst
                                              ? _inlineBlockRailReservedHeightFor(
                                                  true,
                                                )
                                              : null,
                                          onReinput: onModernInputRequested,
                                        ),
                                      ),
                                    if (showInlineBlockRail)
                                      Positioned(
                                        key: const Key(
                                          'terminal-block-status-rail-slot',
                                        ),
                                        top:
                                            _inlineBlockRailTopForHeight(
                                              constraints.maxHeight,
                                              blockFirst: completionBlockFirst,
                                            ) +
                                            _inlineBlockRailReservedHeightFor(
                                              completionBlockFirst,
                                            ),
                                        left: 12,
                                        bottom: 14,
                                        width: 108,
                                        child: _ViewportBlockStatusRail(
                                          controller:
                                              shellController.blocksController,
                                          lightTheme: lightTheme,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (showBlockHistoryPanel)
                                _BlockHistoryPanel(
                                  controller: shellController.blocksController,
                                  reinputEnabled:
                                      shellController.canAcceptInput,
                                  lightTheme: lightTheme,
                                  onReinput: onModernInputRequested,
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                if (isActivePane &&
                    shellController.commandHistoryController.isOpen)
                  _CommandHistoryPanel(
                    controller: shellController.commandHistoryController,
                    textController: commandHistoryTextController,
                    focusNode: commandHistoryFocusNode,
                    chooseEnabled: inputEnabled,
                    lightTheme:
                        settings.themePreset == TerminalThemePreset.light,
                    onClose: onCommandHistoryClosed,
                    onChoose: onCommandHistorySelected,
                    onModernInputRequested: onModernInputRequested,
                  ),
                if (isActivePane && shellController.completionController.isOpen)
                  _CompletionPanel(
                    controller: shellController.completionController,
                    lightTheme:
                        settings.themePreset == TerminalThemePreset.light,
                  ),
                if (isActivePane)
                  _InputAdjacentContextStrip(
                    shellController: shellController,
                    lightTheme:
                        settings.themePreset == TerminalThemePreset.light,
                    compactCommandDetection:
                        shellController.blocksController.hasBlocks,
                  )
                else
                  _InactiveInputContextStrip(
                    paneId: paneId,
                    shellController: shellController,
                    lightTheme:
                        settings.themePreset == TerminalThemePreset.light,
                    compact: shellController.blocksController.hasBlocks,
                  ),
                if (isActivePane)
                  _ModernInputBar(
                    controller: shellController.modernInputController,
                    completionController: shellController.completionController,
                    commandHistoryController:
                        shellController.commandHistoryController,
                    focusNode: modernInputFocusNode,
                    enabled: inputEnabled,
                    settings: settings,
                    compactWhenCommandDraft:
                        shellController.blocksController.hasBlocks,
                    onModernInputRequested: onModernInputRequested,
                    onRawInputRequested: onRawInputRequested,
                    onCommandHistoryRequested: onCommandHistoryRequested,
                    onSaveCommandRequested: onSaveCommandRequested,
                  )
                else
                  _InactiveModernInputBarPreview(
                    paneId: paneId,
                    settings: settings,
                  ),
              ],
            ),
            if (isActivePane && commandPaletteController.isOpen)
              Positioned(
                top: 170,
                left: 0,
                right: 0,
                child: _CommandPalettePanel(
                  controller: commandPaletteController,
                  textController: commandPaletteTextController,
                  focusNode: commandPaletteFocusNode,
                  mode: commandPaletteMode,
                  chooseEnabled: inputEnabled,
                  lightTheme: settings.themePreset == TerminalThemePreset.light,
                  onClose: onCommandHistoryClosed,
                  onChoose: onCommandHistorySelected,
                  onModernInputRequested: onModernInputRequested,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InputAdjacentContextStrip extends StatelessWidget {
  const _InputAdjacentContextStrip({
    required this.shellController,
    required this.lightTheme,
    required this.compactCommandDetection,
  });

  final LocalShellSessionController shellController;
  final bool lightTheme;
  final bool compactCommandDetection;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shellController.modernInputController,
      builder: (context, _) {
        final inputState = shellController.modernInputController.state;
        final draftPreview = _singleLinePreview(inputState.draft);
        if (compactCommandDetection &&
            inputState.effectiveMode == ModernInputEffectiveMode.modern &&
            draftPreview.isNotEmpty) {
          return _InputCommandDetectionStrip(
            draftPreview: draftPreview,
            lightTheme: lightTheme,
            compact: compactCommandDetection,
          );
        }
        return _InputContextStrip(
          shellController: shellController,
          lightTheme: lightTheme,
          compact: compactCommandDetection,
        );
      },
    );
  }
}

class _InputCommandDetectionStrip extends StatelessWidget {
  const _InputCommandDetectionStrip({
    required this.draftPreview,
    required this.lightTheme,
    required this.compact,
  });

  final String draftPreview;
  final bool lightTheme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF252B36);
    final background = lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0B1220);
    final foreground = lightTheme
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);
    final muted = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final accent = lightTheme
        ? const Color(0xFF2563EB)
        : const Color(0xFF60A5FA);
    return Container(
      key: const Key('terminal-input-command-detection-strip'),
      constraints: BoxConstraints(minHeight: compact ? 47 : 48),
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      padding: EdgeInsets.fromLTRB(14, compact ? 6 : 8, 14, compact ? 6 : 8),
      child: Row(
        children: [
          Icon(Icons.terminal, size: compact ? 14 : 16, color: accent),
          SizedBox(width: compact ? 8 : 9),
          Text(
            'Autodetected shell command',
            key: const Key('terminal-input-command-detection-label'),
            style: TextStyle(
              color: foreground,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              draftPreview,
              key: const Key('terminal-input-command-detection-preview'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputContextStrip extends StatelessWidget {
  const _InputContextStrip({
    required this.shellController,
    required this.lightTheme,
    required this.compact,
  });

  final LocalShellSessionController shellController;
  final bool lightTheme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metadata = shellController.sessionMetadata;
    final targetLabel = metadata.compactContextLabel ?? metadata.kind.label;
    final cwd = _singleLinePreview(shellController.completionController.cwd);
    final status = _shellStatusLabel(
      shellController.status,
      shellController.exitCode,
    );
    final lastCommand = _lastCompletedCommandPreview(
      shellController.blocksController.blocks,
    );
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF252B36);
    final background = lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0B1220);
    return Container(
      key: const Key('terminal-input-context-strip'),
      height: compact ? 34 : 74,
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 7, 12, 0)
          : const EdgeInsets.fromLTRB(32, 20, 32, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _InputContextChip(
              chipKey: const Key('terminal-input-context-chip-target'),
              label: targetLabel,
              icon: Icons.radio_button_checked,
              lightTheme: lightTheme,
            ),
            const SizedBox(width: 6),
            _InputContextChip(
              chipKey: const Key('terminal-input-context-chip-cwd'),
              label: cwd.isEmpty ? 'cwd pending' : cwd,
              icon: Icons.folder_outlined,
              lightTheme: lightTheme,
            ),
            const SizedBox(width: 6),
            _InputContextChip(
              chipKey: const Key('terminal-input-context-chip-status'),
              label: 'Status $status',
              icon: Icons.circle,
              lightTheme: lightTheme,
            ),
            if (lastCommand.isNotEmpty) ...[
              const SizedBox(width: 6),
              _InputContextChip(
                chipKey: const Key('terminal-input-context-chip-last-command'),
                label: lastCommand,
                icon: Icons.history,
                lightTheme: lightTheme,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InactiveInputContextStrip extends StatelessWidget {
  const _InactiveInputContextStrip({
    required this.paneId,
    required this.shellController,
    required this.lightTheme,
    required this.compact,
  });

  final int paneId;
  final LocalShellSessionController shellController;
  final bool lightTheme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metadata = shellController.sessionMetadata;
    final targetLabel = metadata.compactContextLabel ?? metadata.kind.label;
    final cwd = _singleLinePreview(shellController.completionController.cwd);
    final status = _shellStatusLabel(
      shellController.status,
      shellController.exitCode,
    );
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF252B36);
    final background = lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0B1220);
    return Container(
      key: Key('terminal-inactive-input-context-strip-$paneId'),
      height: compact ? 34 : 74,
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 7, 12, 0)
          : const EdgeInsets.fromLTRB(32, 20, 32, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _InputContextChip(
              chipKey: Key(
                'terminal-inactive-input-context-chip-target-$paneId',
              ),
              label: targetLabel,
              icon: Icons.radio_button_checked,
              lightTheme: lightTheme,
            ),
            const SizedBox(width: 6),
            _InputContextChip(
              chipKey: Key('terminal-inactive-input-context-chip-cwd-$paneId'),
              label: cwd.isEmpty ? 'cwd pending' : cwd,
              icon: Icons.folder_outlined,
              lightTheme: lightTheme,
            ),
            const SizedBox(width: 6),
            _InputContextChip(
              chipKey: Key(
                'terminal-inactive-input-context-chip-status-$paneId',
              ),
              label: 'Status $status',
              icon: Icons.circle,
              lightTheme: lightTheme,
            ),
          ],
        ),
      ),
    );
  }
}

class _InputContextChip extends StatelessWidget {
  const _InputContextChip({
    required this.chipKey,
    required this.label,
    required this.icon,
    required this.lightTheme,
  });

  final Key chipKey;
  final String label;
  final IconData icon;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    final foreground = lightTheme
        ? const Color(0xFF334155)
        : const Color(0xFFCBD5E1);
    final muted = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final background = lightTheme
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF111827);
    final border = lightTheme
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF334155);
    return ConstrainedBox(
      key: chipKey,
      constraints: const BoxConstraints(maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InactiveModernInputBarPreview extends StatelessWidget {
  const _InactiveModernInputBarPreview({
    required this.paneId,
    required this.settings,
  });

  final int paneId;
  final TerminalSettings settings;

  @override
  Widget build(BuildContext context) {
    final lightTheme = settings.themePreset == TerminalThemePreset.light;
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF252B36);
    final background = lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF111827);
    final editorBackground = lightTheme
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF0B1220);
    final mutedColor = lightTheme
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    return Container(
      key: Key('terminal-inactive-modern-input-bar-$paneId'),
      height: 133,
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: DecoratedBox(
        key: Key('terminal-inactive-modern-input-editor-$paneId'),
        decoration: BoxDecoration(
          color: editorBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Type a command',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mutedColor,
                    fontFamily: settings.fontConfig.family,
                    fontSize: settings.fontConfig.size,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                key: Key('terminal-inactive-modern-input-toolbar-$paneId'),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: borderColor),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DisabledInputPreviewIcon(icon: Icons.send),
                      _DisabledInputPreviewIcon(icon: Icons.history),
                      _DisabledInputPreviewIcon(icon: Icons.bookmark_add),
                      _DisabledInputPreviewIcon(icon: Icons.keyboard),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisabledInputPreviewIcon extends StatelessWidget {
  const _DisabledInputPreviewIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Icon(icon, size: 16, color: const Color(0xFF475569)),
    );
  }
}

class _ModernInputBar extends StatefulWidget {
  const _ModernInputBar({
    required this.controller,
    required this.completionController,
    required this.commandHistoryController,
    required this.focusNode,
    required this.enabled,
    required this.settings,
    required this.compactWhenCommandDraft,
    required this.onModernInputRequested,
    required this.onRawInputRequested,
    required this.onCommandHistoryRequested,
    required this.onSaveCommandRequested,
  });

  final ModernInputController controller;
  final FigCompletionController completionController;
  final CommandHistoryController commandHistoryController;
  final FocusNode focusNode;
  final bool enabled;
  final TerminalSettings settings;
  final bool compactWhenCommandDraft;
  final VoidCallback onModernInputRequested;
  final VoidCallback onRawInputRequested;
  final VoidCallback onCommandHistoryRequested;
  final VoidCallback onSaveCommandRequested;

  @override
  State<_ModernInputBar> createState() => _ModernInputBarState();
}

class _ModernInputBarState extends State<_ModernInputBar> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController.fromValue(
      widget.controller.editingValue,
    );
    _textController.addListener(_syncToController);
    widget.controller.addListener(_syncFromController);
  }

  @override
  void didUpdateWidget(covariant _ModernInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _syncFromController();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _textController.removeListener(_syncToController);
    _textController.dispose();
    super.dispose();
  }

  void _syncFromController() {
    final value = widget.controller.editingValue;
    if (_textController.value == value) {
      return;
    }
    _textController.value = value;
  }

  void _syncToController() {
    widget.controller.updateEditingValue(_textController.value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final colors = widget.settings.themePreset.viewportColors;
    final lightTheme = widget.settings.themePreset == TerminalThemePreset.light;
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF252B36);
    final background = lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF111827);
    final textColor = lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final compact =
        widget.compactWhenCommandDraft &&
        state.effectiveMode == ModernInputEffectiveMode.modern &&
        _singleLinePreview(_textController.text).isNotEmpty;
    if (state.effectiveMode == ModernInputEffectiveMode.modern && !compact) {
      return Container(
        key: const Key('terminal-modern-input-bar'),
        height: 133,
        decoration: BoxDecoration(
          color: colors.canvasBackground,
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: Stack(
          children: [
            Positioned(
              key: const Key('terminal-modern-input-editor'),
              left: 32,
              right: 260,
              top: 22,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 38,
                    child: Focus(
                      onKeyEvent: _handleInputKey,
                      child: TextField(
                        key: const Key('terminal-modern-input-field'),
                        focusNode: widget.focusNode,
                        controller: _textController,
                        enabled: widget.enabled,
                        minLines: 1,
                        maxLines: 1,
                        style: TextStyle(
                          color: textColor,
                          fontFamily: widget.settings.fontConfig.family,
                          fontSize: 22,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                        cursorColor: colors.cursor,
                        onChanged: _handleTextChanged,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.enabled ? '' : 'Shell unavailable',
                          hintStyle: TextStyle(color: mutedColor),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '⌘↩ new /agent conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mutedColor.withValues(alpha: 0.72),
                      fontFamily: widget.settings.fontConfig.family,
                      fontSize: 18,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 24,
              top: 22,
              child: Opacity(
                opacity: 0,
                child: DecoratedBox(
                  key: const Key('terminal-modern-input-toolbar'),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HeaderActionButton(
                          key: const Key('terminal-modern-submit-button'),
                          tooltip: 'Submit command',
                          onPressed:
                              widget.enabled && widget.controller.canSubmit
                              ? () => unawaited(widget.controller.submit())
                              : null,
                          icon: Icons.send,
                        ),
                        _HeaderActionButton(
                          key: const Key('terminal-command-history-button'),
                          tooltip: 'Command history',
                          onPressed: widget.onCommandHistoryRequested,
                          icon: Icons.history,
                        ),
                        _HeaderActionButton(
                          key: const Key('terminal-save-command-button'),
                          tooltip: 'Save current command',
                          onPressed: widget.onSaveCommandRequested,
                          icon: Icons.bookmark_add_outlined,
                        ),
                        _HeaderActionButton(
                          key: const Key('terminal-raw-input-button'),
                          tooltip: 'Use raw terminal input',
                          onPressed: widget.onRawInputRequested,
                          icon: Icons.keyboard,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      key: const Key('terminal-modern-input-bar'),
      alignment: compact ? Alignment.topCenter : null,
      constraints: BoxConstraints(minHeight: compact ? 130 : 112),
      decoration: BoxDecoration(
        color: compact ? colors.canvasBackground : background,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      padding: EdgeInsets.fromLTRB(12, compact ? 6 : 8, 12, compact ? 8 : 10),
      child: state.effectiveMode == ModernInputEffectiveMode.raw
          ? _RawInputBanner(
              autoRaw: state.autoRawHint && !state.manualRaw,
              draft: state.draft,
              enabled: widget.enabled,
              textColor: textColor,
              mutedColor: mutedColor,
              onModernInputRequested: () {
                widget.controller.useModernInput();
                widget.onModernInputRequested();
              },
            )
          : DecoratedBox(
              key: const Key('terminal-modern-input-editor'),
              decoration: BoxDecoration(
                color: lightTheme
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF0B1220),
                borderRadius: BorderRadius.circular(compact ? 6 : 8),
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  compact ? 5 : 7,
                  8,
                  compact ? 5 : 7,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Focus(
                        onKeyEvent: _handleInputKey,
                        child: TextField(
                          key: const Key('terminal-modern-input-field'),
                          focusNode: widget.focusNode,
                          controller: _textController,
                          enabled: widget.enabled,
                          minLines: 1,
                          maxLines: 4,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: widget.settings.fontConfig.family,
                            fontSize: widget.settings.fontConfig.size,
                            height: 1.35,
                          ),
                          cursorColor: colors.cursor,
                          onChanged: _handleTextChanged,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: widget.enabled
                                ? 'Type a command'
                                : 'Shell is not accepting input',
                            hintStyle: TextStyle(color: mutedColor),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Opacity(
                      opacity: compact ? 0.72 : 1,
                      child: DecoratedBox(
                        key: const Key('terminal-modern-input-toolbar'),
                        decoration: BoxDecoration(
                          color: lightTheme
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: borderColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 3,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _HeaderActionButton(
                                key: const Key('terminal-modern-submit-button'),
                                tooltip: 'Submit command',
                                onPressed:
                                    widget.enabled &&
                                        widget.controller.canSubmit
                                    ? () =>
                                          unawaited(widget.controller.submit())
                                    : null,
                                icon: Icons.send,
                              ),
                              _HeaderActionButton(
                                key: const Key(
                                  'terminal-command-history-button',
                                ),
                                tooltip: 'Command history',
                                onPressed: widget.onCommandHistoryRequested,
                                icon: Icons.history,
                              ),
                              _HeaderActionButton(
                                key: const Key('terminal-save-command-button'),
                                tooltip: 'Save command',
                                onPressed: widget.controller.canSubmit
                                    ? widget.onSaveCommandRequested
                                    : null,
                                icon: Icons.bookmark_add,
                              ),
                              _HeaderActionButton(
                                key: const Key('terminal-raw-toggle-button'),
                                tooltip: 'Use raw terminal input',
                                onPressed: widget.enabled
                                    ? () {
                                        widget.completionController.close();
                                        widget.controller.toggleManualRaw();
                                        widget.onRawInputRequested();
                                      }
                                    : null,
                                icon: Icons.keyboard,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  KeyEventResult _handleInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (widget.completionController.isOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.completionController.close();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.completionController.next();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.completionController.previous();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        final edited = widget.completionController.acceptActive(
          _textController.value,
        );
        if (edited != null) {
          _applyModernInputEdit(edited);
        }
        return KeyEventResult.handled;
      }
    }
    if (_isControlShortcut(event, LogicalKeyboardKey.keyR)) {
      widget.completionController.close();
      widget.onCommandHistoryRequested();
      return KeyEventResult.handled;
    }
    if (_isControlShortcut(event, LogicalKeyboardKey.keyU)) {
      _applyModernInputEdit(applyModernInputClearLine(_textController.value));
      return KeyEventResult.handled;
    }
    if (_isMetaShortcut(event, LogicalKeyboardKey.keyA)) {
      _applyModernInputEdit(
        applyModernInputSelectBuffer(_textController.value),
      );
      return KeyEventResult.handled;
    }
    if (_isAltShortcut(event, LogicalKeyboardKey.backspace)) {
      _applyModernInputEdit(
        applyModernInputDeletePreviousWord(_textController.value),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.enableManualRaw();
      widget.onRawInputRequested();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (!widget.enabled || _hasPressedModifier()) {
        return KeyEventResult.ignored;
      }
      unawaited(_completeOrAccept());
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      if (!widget.enabled || _hasPressedModifier()) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        final edited = applyModernInputPairBackspace(_textController.value);
        if (edited == null) {
          return KeyEventResult.ignored;
        }
        _applyModernInputEdit(edited);
        return KeyEventResult.handled;
      }
      final pairInput = _modernInputPairTextFor(event);
      if (pairInput == null) {
        return KeyEventResult.ignored;
      }
      final edited = applyModernInputPairInsertion(
        _textController.value,
        pairInput,
      );
      if (edited == null) {
        return KeyEventResult.ignored;
      }
      _applyModernInputEdit(edited);
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      widget.controller.updateEditingValue(_textController.value);
      widget.controller.insertNewline();
      return KeyEventResult.handled;
    }
    if (widget.enabled) {
      unawaited(widget.controller.submit());
    }
    return KeyEventResult.handled;
  }

  void _applyModernInputEdit(TextEditingValue value) {
    _textController.value = value;
    widget.controller.updateEditingValue(value);
  }

  void _handleTextChanged(String value) {
    widget.completionController.close();
  }

  Future<void> _completeOrAccept() async {
    final edited = await widget.completionController.completeOrAccept(
      _textController.value,
    );
    if (!mounted || edited == null) {
      return;
    }
    _applyModernInputEdit(edited);
  }

  bool _hasPressedModifier() {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed;
  }

  bool _isControlShortcut(KeyDownEvent event, LogicalKeyboardKey key) {
    final keyboard = HardwareKeyboard.instance;
    return event.logicalKey == key &&
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed;
  }

  bool _isMetaShortcut(KeyDownEvent event, LogicalKeyboardKey key) {
    final keyboard = HardwareKeyboard.instance;
    return event.logicalKey == key &&
        keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed;
  }

  bool _isAltShortcut(KeyDownEvent event, LogicalKeyboardKey key) {
    final keyboard = HardwareKeyboard.instance;
    return event.logicalKey == key &&
        keyboard.isAltPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed;
  }

  String? _modernInputPairTextFor(KeyDownEvent event) {
    final character = event.character;
    if (character != null && character.length == 1) {
      switch (character) {
        case '(':
        case ')':
        case '[':
        case ']':
        case '{':
        case '}':
        case "'":
        case '"':
        case '`':
          return character;
      }
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.parenthesisLeft:
        return '(';
      case LogicalKeyboardKey.parenthesisRight:
        return ')';
      case LogicalKeyboardKey.bracketLeft:
        return '[';
      case LogicalKeyboardKey.bracketRight:
        return ']';
      case LogicalKeyboardKey.braceLeft:
        return '{';
      case LogicalKeyboardKey.braceRight:
        return '}';
      case LogicalKeyboardKey.quoteSingle:
        return "'";
      case LogicalKeyboardKey.quote:
        return '"';
      case LogicalKeyboardKey.backquote:
        return '`';
    }
    return null;
  }
}

class _CompletionPanel extends StatelessWidget {
  const _CompletionPanel({required this.controller, required this.lightTheme});

  final FigCompletionController controller;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    final suggestions = controller.suggestions.take(8).toList(growable: false);
    final foreground = lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final muted = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    return _InlineMenuShell(
      shellKey: const Key('terminal-inline-menu-shell-completion'),
      aliasKeys: const <Key>[Key('terminal-completion-panel')],
      lightTheme: lightTheme,
      maxHeight: 220,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 7),
        child: Row(
          children: [
            Text(
              'Completions',
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${controller.activeIndex + 1}/${suggestions.length}',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tab or Enter accepts the selected item',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          final active = index == controller.activeIndex;
          return Semantics(
            key: Key('terminal-completion-row-${suggestion.name}'),
            selected: active,
            child: Container(
              decoration: BoxDecoration(
                color: active ? const Color(0x334D8DFF) : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color: active
                        ? const Color(0xFF4D8DFF)
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(11, 6, 14, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      suggestion.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CompletionSourceBadge(source: suggestion.source),
                  const SizedBox(width: 8),
                  if (active) ...[
                    _CompletionActiveBadge(name: suggestion.name),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      suggestion.description,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CompletionActiveBadge extends StatelessWidget {
  const _CompletionActiveBadge({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: Key('terminal-completion-active-badge-$name'),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2A3A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF0369A1)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          'Selected',
          style: TextStyle(
            color: Color(0xFFBAE6FD),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String _completionSourceLabel(FigCompletionSuggestionSource source) {
  return switch (source) {
    FigCompletionSuggestionSource.spec => 'Spec',
    FigCompletionSuggestionSource.template => 'Template',
    FigCompletionSuggestionSource.generator => 'Generator',
  };
}

class _CompletionSourceBadge extends StatelessWidget {
  const _CompletionSourceBadge({required this.source});

  final FigCompletionSuggestionSource source;

  @override
  Widget build(BuildContext context) {
    final label = _completionSourceLabel(source);
    return DecoratedBox(
      key: Key('terminal-completion-source-badge-$label'),
      decoration: BoxDecoration(
        color: const Color(0xFF172554),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF1D4ED8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFBFDBFE),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CommandHistoryPanel extends StatefulWidget {
  const _CommandHistoryPanel({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.chooseEnabled,
    required this.lightTheme,
    required this.onClose,
    required this.onChoose,
    required this.onModernInputRequested,
  });

  final CommandHistoryController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final bool chooseEnabled;
  final bool lightTheme;
  final VoidCallback onClose;
  final Future<void> Function() onChoose;
  final VoidCallback onModernInputRequested;

  @override
  State<_CommandHistoryPanel> createState() => _CommandHistoryPanelState();
}

class _CommandHistoryPanelState extends State<_CommandHistoryPanel> {
  @override
  Widget build(BuildContext context) {
    final matches = widget.controller.matches;
    final textColor = widget.lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = widget.lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    return _InlineMenuShell(
      shellKey: const Key('terminal-inline-menu-shell-history'),
      aliasKeys: const <Key>[Key('terminal-command-history-panel')],
      lightTheme: widget.lightTheme,
      maxHeight: 250,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
        child: Row(
          children: [
            SizedBox(
              width: 280,
              child: Focus(
                onKeyEvent: _handleKey,
                child: TextField(
                  key: const Key('terminal-command-history-field'),
                  focusNode: widget.focusNode,
                  controller: widget.textController,
                  onChanged: widget.controller.updateQuery,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: textColor, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search command history',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 52,
              child: Text(
                '${widget.controller.displayIndex}/${matches.length}',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.chooseEnabled ? 'Enter to reinput' : 'Exited',
              style: TextStyle(color: mutedColor, fontSize: 12),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Previous command',
              onPressed: matches.isEmpty
                  ? null
                  : widget.controller.goToPrevious,
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            ),
            IconButton(
              tooltip: 'Next command',
              onPressed: matches.isEmpty ? null : widget.controller.goToNext,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            ),
            IconButton(
              tooltip: 'Close command history',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
      body: matches.isEmpty
          ? Center(
              child: Text(
                'No commands',
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: matches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final entry = matches[index];
                return _CommandHistoryRow(
                  key: Key('terminal-command-history-row-${entry.blockId}'),
                  index: index,
                  entry: entry,
                  active: index == widget.controller.activeIndex,
                  textColor: textColor,
                  mutedColor: mutedColor,
                  lightTheme: widget.lightTheme,
                  onSave: () {
                    widget.controller.saveEntry(entry);
                  },
                  onRemove: () {
                    widget.controller.removeEntry(entry);
                  },
                  onTap: widget.chooseEnabled
                      ? () {
                          widget.controller.selectEntryAt(index);
                          unawaited(_choose());
                        }
                      : null,
                );
              },
            ),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.controller.goToNext();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.controller.goToPrevious();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (widget.chooseEnabled) {
        unawaited(_choose());
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _choose() async {
    await widget.onChoose();
    if (!mounted) {
      return;
    }
    widget.onModernInputRequested();
  }
}

class _CommandHistoryRow extends StatelessWidget {
  const _CommandHistoryRow({
    super.key,
    required this.index,
    required this.entry,
    required this.active,
    required this.textColor,
    required this.mutedColor,
    required this.lightTheme,
    required this.onSave,
    required this.onRemove,
    required this.onTap,
  });

  final int index;
  final CommandHistoryEntry entry;
  final bool active;
  final Color textColor;
  final Color mutedColor;
  final bool lightTheme;
  final VoidCallback onSave;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final activeBackground = lightTheme
        ? const Color(0xFFEFF6FF)
        : const Color(0xFF172033);
    final hoverBackground = lightTheme
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: active ? activeBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: hoverBackground,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: active ? const Color(0xFF4D8DFF) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(9, 8, 10, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '#${index + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _CommandSourceBadge(source: entry.source),
                if (entry.source == CommandHistoryEntrySource.history) ...[
                  const SizedBox(width: 6),
                  _BlockPanelStatus(status: entry.status),
                ],
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    _singleLinePreview(entry.commandText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(
                    entry.outputPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mutedColor, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: Key(
                    entry.source == CommandHistoryEntrySource.saved
                        ? 'terminal-command-history-remove-${entry.id}'
                        : 'terminal-command-history-save-${entry.id}',
                  ),
                  tooltip: entry.source == CommandHistoryEntrySource.saved
                      ? 'Remove saved command'
                      : 'Save history command',
                  onPressed: entry.source == CommandHistoryEntrySource.saved
                      ? onRemove
                      : onSave,
                  icon: Icon(
                    entry.source == CommandHistoryEntrySource.saved
                        ? Icons.bookmark_remove
                        : Icons.bookmark_add,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandSourceBadge extends StatelessWidget {
  const _CommandSourceBadge({required this.source});

  final Object source;

  @override
  Widget build(BuildContext context) {
    final saved = switch (source) {
      CommandHistoryEntrySource.saved => true,
      CommandPaletteEntrySource.saved => true,
      CommandPaletteEntrySource.workflow => true,
      _ => false,
    };
    final session = switch (source) {
      CommandPaletteEntrySource.session => true,
      _ => false,
    };
    final launch = switch (source) {
      CommandPaletteEntrySource.launchConfig => true,
      _ => false,
    };
    final label = switch (source) {
      CommandHistoryEntrySource source => source.label,
      CommandPaletteEntrySource source => source.label,
      _ => '',
    };
    final (background, foreground, border) = saved
        ? (
            const Color(0xFF1E1B4B),
            const Color(0xFFC4B5FD),
            const Color(0xFF5B21B6),
          )
        : launch
        ? (
            const Color(0xFF052E1A),
            const Color(0xFFBBF7D0),
            const Color(0xFF166534),
          )
        : session
        ? (
            const Color(0xFF0F2A3A),
            const Color(0xFFBAE6FD),
            const Color(0xFF0369A1),
          )
        : (
            const Color(0xFF172554),
            const Color(0xFFBFDBFE),
            const Color(0xFF1D4ED8),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RawInputBanner extends StatelessWidget {
  const _RawInputBanner({
    required this.autoRaw,
    required this.draft,
    required this.enabled,
    required this.textColor,
    required this.mutedColor,
    required this.onModernInputRequested,
  });

  final bool autoRaw;
  final String draft;
  final bool enabled;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback onModernInputRequested;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Icon(Icons.keyboard, size: 18, color: mutedColor),
          const SizedBox(width: 8),
          Text(
            autoRaw ? 'Auto raw input active' : 'Raw input active',
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (draft.isNotEmpty) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _singleLinePreview(draft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
            ),
          ] else
            const Spacer(),
          TextButton.icon(
            key: const Key('terminal-modern-mode-button'),
            onPressed: enabled && !autoRaw ? onModernInputRequested : null,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Modern'),
          ),
        ],
      ),
    );
  }
}

class _BlockHistoryPanel extends StatelessWidget {
  const _BlockHistoryPanel({
    required this.controller,
    required this.reinputEnabled,
    required this.lightTheme,
    required this.onReinput,
  });

  final TerminalBlocksController controller;
  final bool reinputEnabled;
  final bool lightTheme;
  final VoidCallback onReinput;

  @override
  Widget build(BuildContext context) {
    final blocks = controller.blocks;
    final panelBackground = lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF1F2937);
    final textColor = lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    return Container(
      key: const Key('terminal-block-panel'),
      width: 300,
      decoration: BoxDecoration(
        color: panelBackground,
        border: Border(left: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Blocks ${controller.displayIndex}/${blocks.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _HeaderActionButton(
                  key: const Key('terminal-block-panel-copy-command-button'),
                  tooltip: 'Copy block command',
                  onPressed: controller.canCopyActiveCommand
                      ? () => unawaited(controller.copyActiveCommand())
                      : null,
                  icon: Icons.terminal,
                ),
                _HeaderActionButton(
                  key: const Key('terminal-block-panel-copy-output-button'),
                  tooltip: 'Copy block output',
                  onPressed: controller.canCopyActiveOutput
                      ? () => unawaited(controller.copyActiveOutput())
                      : null,
                  icon: Icons.notes,
                ),
                _HeaderActionButton(
                  key: const Key('terminal-block-panel-copy-all-button'),
                  tooltip: 'Copy block command and output',
                  onPressed: controller.canCopyActiveCommandAndOutput
                      ? () => unawaited(controller.copyActiveCommandAndOutput())
                      : null,
                  icon: Icons.content_copy,
                ),
                _HeaderActionButton(
                  key: const Key('terminal-block-panel-reinput-button'),
                  tooltip: 'Reinput block command',
                  onPressed:
                      controller.canReinputActiveCommand && reinputEnabled
                      ? () {
                          unawaited(controller.reinputActiveCommand());
                          onReinput();
                        }
                      : null,
                  icon: Icons.keyboard_return,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: blocks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final block = blocks[index];
                return _BlockHistoryRow(
                  key: Key('terminal-block-row-${block.id}'),
                  index: index,
                  block: block,
                  active: index == controller.activeIndex,
                  textColor: textColor,
                  mutedColor: mutedColor,
                  lightTheme: lightTheme,
                  onTap: () => controller.selectBlockAt(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockHistoryRow extends StatelessWidget {
  const _BlockHistoryRow({
    super.key,
    required this.index,
    required this.block,
    required this.active,
    required this.textColor,
    required this.mutedColor,
    required this.lightTheme,
    required this.onTap,
  });

  final int index;
  final TerminalBlock block;
  final bool active;
  final Color textColor;
  final Color mutedColor;
  final bool lightTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeBackground = lightTheme
        ? const Color(0xFFEFF6FF)
        : const Color(0xFF172033);
    final hoverBackground = lightTheme
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF111827);
    final commandPreview = _singleLinePreview(block.commandText);
    final outputPreview = _firstOutputLine(block.outputText);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: active ? activeBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: hoverBackground,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: active ? const Color(0xFF4D8DFF) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(9, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '#${index + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _BlockPanelStatus(status: block.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  commandPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (outputPreview.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    outputPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mutedColor, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockPanelStatus extends StatelessWidget {
  const _BlockPanelStatus({required this.status});

  final TerminalBlockStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (status) {
      TerminalBlockStatus.running => (
        const Color(0xFF052E1A),
        const Color(0xFFBBF7D0),
        const Color(0xFF166534),
      ),
      TerminalBlockStatus.succeeded => (
        const Color(0xFF0F2A3A),
        const Color(0xFFBAE6FD),
        const Color(0xFF0369A1),
      ),
      TerminalBlockStatus.failed => (
        const Color(0xFF2A1215),
        const Color(0xFFFECACA),
        const Color(0xFF991B1B),
      ),
      TerminalBlockStatus.interrupted => (
        const Color(0xFF2A1F13),
        const Color(0xFFFDE68A),
        const Color(0xFF92400E),
      ),
      TerminalBlockStatus.unknown => (
        const Color(0xFF1E293B),
        const Color(0xFFCBD5E1),
        const Color(0xFF475569),
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          status.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String _singleLinePreview(String text) {
  final preview = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (preview.length <= 120) {
    return preview;
  }
  return '${preview.substring(0, 119)}...';
}

String _firstOutputLine(String text) {
  final trimmed = text.trimRight();
  if (trimmed.isEmpty) {
    return '';
  }
  return _singleLinePreview(trimmed.split('\n').first);
}

String _lastCompletedCommandPreview(List<TerminalBlock> blocks) {
  for (var index = blocks.length - 1; index >= 0; index -= 1) {
    final block = blocks[index];
    if (block.status == TerminalBlockStatus.running) {
      continue;
    }
    final command = _singleLinePreview(block.commandText);
    if (command.isNotEmpty) {
      return command;
    }
  }
  return '';
}

String _shellStatusLabel(LocalShellStatus status, int? exitCode) {
  return switch (status) {
    LocalShellStatus.starting => 'Starting',
    LocalShellStatus.running => 'Running',
    LocalShellStatus.exited => exitCode == null ? 'Exited' : 'Exited $exitCode',
    LocalShellStatus.failed => 'Failed',
  };
}

String _launchConfigScopeTitle(TerminalLaunchConfigurationScope scope) {
  return switch (scope) {
    TerminalLaunchConfigurationScope.app => 'App config',
    TerminalLaunchConfigurationScope.tab => 'Tab config',
  };
}

String _launchConfigScopeDescription(TerminalLaunchConfigurationScope scope) {
  return switch (scope) {
    TerminalLaunchConfigurationScope.app =>
      'Captures windows, tabs, panes, metadata, startup commands, and session launch profiles.',
    TerminalLaunchConfigurationScope.tab =>
      "Captures one tab's pane tree, cwd, startup commands, shell, title, and optional params.",
  };
}

class _SavedLaunchConfigsPanel extends StatefulWidget {
  const _SavedLaunchConfigsPanel({
    required this.tabsController,
    required this.store,
  });

  final TerminalWindowsController tabsController;
  final TerminalLaunchConfigurationStore store;

  @override
  State<_SavedLaunchConfigsPanel> createState() =>
      _SavedLaunchConfigsPanelState();
}

class _SavedLaunchConfigsPanelState extends State<_SavedLaunchConfigsPanel> {
  late List<TerminalSavedLaunchConfiguration> _configs;
  int _selectedIndex = 0;
  String? _defaultPath;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _reloadConfigs();
  }

  TerminalSavedLaunchConfiguration? get _selectedConfig {
    if (_configs.isEmpty) {
      return null;
    }
    return _configs[_selectedIndex.clamp(0, _configs.length - 1)];
  }

  void _reloadConfigs() {
    _configs = widget.store.listSaved();
    if (_configs.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= _configs.length) {
      _selectedIndex = _configs.length - 1;
    }
  }

  void _selectConfig(int index) {
    setState(() {
      _selectedIndex = index;
      _statusText = null;
    });
  }

  void _applySelected() {
    final config = _selectedConfig;
    if (config == null) {
      return;
    }
    widget.tabsController.applyLaunchConfiguration(config.configuration);
    Navigator.of(context).pop(
      _SavedLaunchConfigDialogResult(
        path: config.path,
        message: 'Applied saved config from ${config.path}',
      ),
    );
  }

  Future<void> _copyPathForEdit() async {
    final config = _selectedConfig;
    if (config == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: config.path));
    setState(() {
      _statusText = 'Copied path for editing.';
    });
  }

  void _removeSelected() {
    final config = _selectedConfig;
    if (config == null) {
      return;
    }
    widget.store.remove(config.file);
    setState(() {
      _statusText = 'Removed ${config.name}.';
      _reloadConfigs();
    });
  }

  void _makeDefault() {
    final config = _selectedConfig;
    if (config == null) {
      return;
    }
    setState(() {
      _defaultPath = config.path;
      _statusText = '${config.name} is marked as the default for this window.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedConfig;
    return Dialog(
      key: const Key('terminal-saved-launch-configs-panel'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        key: const Key('terminal-saved-launch-configs-dialog'),
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saved configs',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Apply, inspect, edit, or remove saved Ianvs app and tab snapshots.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close saved launch configs',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _configs.isEmpty
                    ? const Center(
                        child: Text(
                          'No saved configs',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 280,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFF111827),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFF233047),
                                ),
                              ),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: _configs.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 2),
                                itemBuilder: (context, index) {
                                  final config = _configs[index];
                                  final active = index == _selectedIndex;
                                  final isDefault = _defaultPath == config.path;
                                  return _SavedLaunchConfigRow(
                                    key: Key(
                                      'terminal-saved-launch-config-row-$index',
                                    ),
                                    config: config,
                                    active: active,
                                    isDefault: isDefault,
                                    onTap: () => _selectConfig(index),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _SavedLaunchConfigSidecar(
                              config: selected!,
                              isDefault: _defaultPath == selected.path,
                              statusText: _statusText,
                              onApply: _applySelected,
                              onEdit: _copyPathForEdit,
                              onRemove: _removeSelected,
                              onMakeDefault: _makeDefault,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedLaunchConfigRow extends StatelessWidget {
  const _SavedLaunchConfigRow({
    super.key,
    required this.config,
    required this.active,
    required this.isDefault,
    required this.onTap,
  });

  final TerminalSavedLaunchConfiguration config;
  final bool active;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scopeTitle = _launchConfigScopeTitle(config.configuration.scope);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: active ? const Color(0xFF172033) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: active ? const Color(0xFF4D8DFF) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        config.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isDefault)
                      const _LaunchConfigMiniBadge(label: 'Default'),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '$scopeTitle · ${config.windowCount} windows · ${config.tabCount} tabs · ${config.paneCount} panes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedLaunchConfigSidecar extends StatelessWidget {
  const _SavedLaunchConfigSidecar({
    required this.config,
    required this.isDefault,
    required this.statusText,
    required this.onApply,
    required this.onEdit,
    required this.onRemove,
    required this.onMakeDefault,
  });

  final TerminalSavedLaunchConfiguration config;
  final bool isDefault;
  final String? statusText;
  final VoidCallback onApply;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onMakeDefault;

  @override
  Widget build(BuildContext context) {
    final scopeTitle = _launchConfigScopeTitle(config.configuration.scope);
    final scopeDescription = _launchConfigScopeDescription(
      config.configuration.scope,
    );
    return DecoratedBox(
      key: const Key('terminal-saved-launch-config-sidecar'),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF233047)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      config.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _LaunchConfigMiniBadge(label: scopeTitle),
                  if (isDefault) ...[
                    const SizedBox(width: 6),
                    const _LaunchConfigMiniBadge(label: 'Default'),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                scopeDescription,
                key: const Key('terminal-saved-launch-config-scope-copy'),
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                config.path,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _LaunchConfigStatCard(
                    label: 'Scope',
                    value: config.scopeLabel,
                  ),
                  _LaunchConfigStatCard(
                    label: 'Windows',
                    value: '${config.windowCount}',
                  ),
                  _LaunchConfigStatCard(
                    label: 'Tabs',
                    value: '${config.tabCount}',
                  ),
                  _LaunchConfigStatCard(
                    label: 'Panes',
                    value: '${config.paneCount}',
                  ),
                  _LaunchConfigStatCard(
                    label: 'Active',
                    value: config.activeWindowLabel,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (config.modifiedAt != null)
                Text(
                  'Updated ${config.modifiedAt}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 18),
              if (statusText != null) ...[
                Text(
                  statusText!,
                  style: const TextStyle(
                    color: Color(0xFF93C5FD),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('terminal-saved-launch-config-edit-button'),
                    onPressed: onEdit,
                    child: const Text('Edit file'),
                  ),
                  OutlinedButton(
                    key: const Key(
                      'terminal-saved-launch-config-default-button',
                    ),
                    onPressed: onMakeDefault,
                    child: const Text('Make default'),
                  ),
                  OutlinedButton(
                    key: const Key(
                      'terminal-saved-launch-config-remove-button',
                    ),
                    onPressed: onRemove,
                    child: const Text('Remove'),
                  ),
                  FilledButton(
                    key: const Key('terminal-saved-launch-config-apply-button'),
                    onPressed: onApply,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchConfigMiniBadge extends StatelessWidget {
  const _LaunchConfigMiniBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFBFDBFE),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _LaunchConfigScopeExplainer extends StatelessWidget {
  const _LaunchConfigScopeExplainer();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('terminal-launch-config-scope-explainer'),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LaunchConfigScopeCopy(
              title: 'App config',
              body:
                  'Windows, tabs, panes, metadata, startup commands, and session launch profiles.',
            ),
            SizedBox(height: 8),
            _LaunchConfigScopeCopy(
              title: 'Tab config',
              body:
                  "One tab's pane tree, cwd, startup commands, shell, title, and optional params.",
            ),
          ],
        ),
      ),
    );
  }
}

class _LaunchConfigScopeCopy extends StatelessWidget {
  const _LaunchConfigScopeCopy({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 74,
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFFBFDBFE),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            body,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _SavedLaunchConfigDialogResult {
  const _SavedLaunchConfigDialogResult({
    required this.path,
    required this.message,
  });

  final String path;
  final String message;
}

class _LaunchConfigPanel extends StatefulWidget {
  const _LaunchConfigPanel({
    required this.tabsController,
    required this.store,
    required this.initialPath,
  });

  final TerminalWindowsController tabsController;
  final TerminalLaunchConfigurationStore store;
  final String initialPath;

  @override
  State<_LaunchConfigPanel> createState() => _LaunchConfigPanelState();
}

class _LaunchConfigPanelState extends State<_LaunchConfigPanel> {
  late final TextEditingController _nameController;
  late final TextEditingController _pathController;
  late final List<_LaunchConfigPaneField> _paneFields;
  late final Map<String, TextEditingController> _startupControllers;
  bool _advancedPathExpanded = false;
  bool _pathCustomized = false;
  bool _syncingPathFromName = false;
  _LaunchConfigPanelPhase _phase = _LaunchConfigPanelPhase.compose;
  String? _savedPath;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: launchConfigDisplayNameFromPath(widget.initialPath),
    )..addListener(_syncSuggestedPathFromName);
    _pathController = TextEditingController(text: widget.initialPath);
    _paneFields = _buildPaneFields();
    _startupControllers = <String, TextEditingController>{
      for (final field in _paneFields)
        field.fieldId: TextEditingController(text: field.startupCommand),
    };
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_syncSuggestedPathFromName)
      ..dispose();
    _pathController.dispose();
    for (final controller in _startupControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<_LaunchConfigPaneField> _buildPaneFields() {
    final fields = <_LaunchConfigPaneField>[];
    for (
      var windowIndex = 0;
      windowIndex < widget.tabsController.windows.length;
      windowIndex += 1
    ) {
      final window = widget.tabsController.windows[windowIndex];
      for (
        var tabIndex = 0;
        tabIndex < window.tabsController.tabs.length;
        tabIndex += 1
      ) {
        final tab = window.tabsController.tabs[tabIndex];
        for (final pane in tab.panes) {
          final metadata = pane.shellController.sessionMetadata;
          fields.add(
            _LaunchConfigPaneField(
              fieldId: widget.tabsController.windows.length == 1
                  ? 'pane-${pane.id}'
                  : 'window-${windowIndex + 1}-pane-${pane.id}',
              windowLabel: 'Window ${windowIndex + 1}',
              tabLabel: 'Tab ${tabIndex + 1} · ${tab.title}',
              paneId: pane.id,
              cwd: pane.shellController.completionController.cwd,
              startupCommand: pane.shellController.startupCommand ?? '',
              contextLabel: metadata.compactContextLabel ?? metadata.kind.label,
              shellController: pane.shellController,
            ),
          );
        }
      }
    }
    return fields;
  }

  int get _windowCount => widget.tabsController.windows.length;

  int get _tabCount => widget.tabsController.windows.fold<int>(
    0,
    (count, window) => count + window.tabsController.tabs.length,
  );

  int get _paneCount => _paneFields.length;
  bool get _canSave => _nameController.text.trim().isNotEmpty;

  String get _currentPath => _pathController.text.trim();

  String _suggestedPathForCurrentName() {
    return widget.store.suggestedNamedPath(_nameController.text);
  }

  void _syncSuggestedPathFromName() {
    if (_pathCustomized || _syncingPathFromName) {
      return;
    }
    final suggestedPath = _suggestedPathForCurrentName();
    if (_pathController.text == suggestedPath) {
      return;
    }
    _syncingPathFromName = true;
    _pathController.value = TextEditingValue(
      text: suggestedPath,
      selection: TextSelection.collapsed(offset: suggestedPath.length),
    );
    _syncingPathFromName = false;
  }

  void _updatePathCustomization(String value) {
    if (_syncingPathFromName) {
      return;
    }
    final customized = value.trim() != _suggestedPathForCurrentName();
    if (_pathCustomized == customized) {
      return;
    }
    setState(() {
      _pathCustomized = customized;
    });
  }

  void _resetPathToSuggested() {
    final suggestedPath = _suggestedPathForCurrentName();
    _syncingPathFromName = true;
    _pathController.value = TextEditingValue(
      text: suggestedPath,
      selection: TextSelection.collapsed(offset: suggestedPath.length),
    );
    _syncingPathFromName = false;
    setState(() {
      _pathCustomized = false;
    });
  }

  Widget _buildAppSnapshotColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Current app snapshot',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ianvs exports every window, tab, pane, cwd, startup command, and session launch profile.',
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (
                  var windowIndex = 0;
                  windowIndex < widget.tabsController.windows.length;
                  windowIndex += 1
                )
                  _LaunchConfigWindowCard(
                    windowLabel: 'Window ${windowIndex + 1}',
                    active:
                        windowIndex == widget.tabsController.activeWindowIndex,
                    tabSummaries: widget
                        .tabsController
                        .windows[windowIndex]
                        .tabsController
                        .tabs
                        .asMap()
                        .entries
                        .map(
                          (entry) => _LaunchConfigTabSummary(
                            label:
                                'Tab ${entry.key + 1} · ${entry.value.title}',
                            paneCount: entry.value.panes.length,
                          ),
                        )
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartupCommandsColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Startup commands',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Commands run once after each pane launches or restarts.',
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final field in _paneFields) ...[
                  Text(
                    '${field.windowLabel} · ${field.tabLabel} · Pane ${field.paneId}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${field.contextLabel} · ${field.cwd}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: Key(
                      'terminal-launch-config-startup-field-${field.fieldId}',
                    ),
                    controller: _startupControllers[field.fieldId],
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Startup command',
                      hintText: 'Optional command to run after launch',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveSettingsCard() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF233047)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Save current app snapshot',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start with a name, then expand the path only if you need a custom location.',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 12),
            const _LaunchConfigScopeExplainer(),
            const SizedBox(height: 14),
            TextField(
              key: const Key('terminal-launch-config-name-field'),
              controller: _nameController,
              onChanged: (_) {
                setState(() {
                  _errorText = null;
                });
              },
              decoration: const InputDecoration(
                labelText: 'App snapshot name',
                hintText: 'payments-prod',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Ianvs will save to',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: SelectableText(
                  _currentPath,
                  key: const Key('terminal-launch-config-path-preview'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE5E7EB),
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('terminal-launch-config-advanced-toggle'),
                onPressed: () {
                  setState(() {
                    _advancedPathExpanded = !_advancedPathExpanded;
                  });
                },
                icon: Icon(
                  _advancedPathExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(
                  _advancedPathExpanded
                      ? 'Hide advanced path'
                      : 'Customize path',
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 160),
              crossFadeState: _advancedPathExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('terminal-launch-config-path-field'),
                    controller: _pathController,
                    onChanged: (value) {
                      setState(() {
                        _errorText = null;
                      });
                      _updatePathCustomization(value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Advanced config path',
                      hintText:
                          '/Users/name/Library/Application Support/Ianvs/ianvs-terminal/launch_configs/app.json',
                      border: OutlineInputBorder(),
                      helperText:
                          'Only change this when you need a custom export location.',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key(
                        'terminal-launch-config-reset-path-button',
                      ),
                      onPressed: _pathCustomized ? _resetPathToSuggested : null,
                      child: const Text('Reset to suggested path'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    final path = _savedPath ?? _currentPath;
    final fileName = path.split(RegExp(r'[\\/]')).last;
    return SingleChildScrollView(
      key: const Key('terminal-launch-config-success-state'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF233047)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF34D399), size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Saved current app',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                fileName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ianvs wrote a reusable app snapshot with every window, tab, pane, startup command, and session context. Apply it now or close this panel when you are done checking the path.',
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Saved file',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        path,
                        key: const Key('terminal-launch-config-success-path'),
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _LaunchConfigStatCard(
                    label: 'Windows',
                    value: '$_windowCount',
                  ),
                  _LaunchConfigStatCard(label: 'Tabs', value: '$_tabCount'),
                  _LaunchConfigStatCard(label: 'Panes', value: '$_paneCount'),
                ],
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorText!,
                  style: const TextStyle(color: Color(0xFFFCA5A5)),
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('terminal-launch-config-copy-path-button'),
                    onPressed: _copySavedPath,
                    child: const Text('Copy path'),
                  ),
                  FilledButton.tonal(
                    key: const Key(
                      'terminal-launch-config-success-apply-button',
                    ),
                    onPressed: _applySavedLayout,
                    child: const Text('Apply saved app'),
                  ),
                  FilledButton(
                    key: const Key('terminal-launch-config-done-button'),
                    onPressed: _closeAfterSave,
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyStartupCommands() {
    for (final field in _paneFields) {
      field.shellController.updateStartupCommand(
        _startupControllers[field.fieldId]?.text,
      );
    }
  }

  bool _applyLaunchConfigAtPath(String path) {
    if (path.isEmpty) {
      setState(() {
        _errorText = 'Launch config path is required.';
      });
      return false;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() {
        _errorText = 'Launch config file was not found.';
      });
      return false;
    }
    final configuration = widget.store.load(file);
    if (!configuration.hasTabs) {
      setState(() {
        _errorText = 'Launch config file is invalid or has no tabs.';
      });
      return false;
    }
    widget.tabsController.applyLaunchConfiguration(configuration);
    return true;
  }

  Future<void> _saveCurrentLayout() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorText = 'App snapshot name is required.';
      });
      return;
    }
    final path = _currentPath.isEmpty
        ? _suggestedPathForCurrentName()
        : _currentPath;
    _applyStartupCommands();
    widget.store.save(
      File(path),
      widget.tabsController.currentLaunchConfiguration(),
    );
    setState(() {
      _savedPath = path;
      _phase = _LaunchConfigPanelPhase.success;
      _errorText = null;
    });
  }

  Future<void> _applyLaunchConfig() async {
    final path = _currentPath.isEmpty
        ? _suggestedPathForCurrentName()
        : _currentPath;
    if (_applyLaunchConfigAtPath(path) && mounted) {
      Navigator.of(context).pop(
        _LaunchConfigDialogResult(
          action: _LaunchConfigDialogAction.applied,
          path: path,
        ),
      );
    }
  }

  Future<void> _applySavedLayout() async {
    final path = _savedPath ?? _currentPath;
    if (_applyLaunchConfigAtPath(path) && mounted) {
      Navigator.of(context).pop(
        _LaunchConfigDialogResult(
          action: _LaunchConfigDialogAction.applied,
          path: path,
        ),
      );
    }
  }

  Future<void> _copySavedPath() async {
    final path = _savedPath ?? _currentPath;
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied config path')));
  }

  void _closeAfterSave() {
    final path = _savedPath ?? _currentPath;
    Navigator.of(context).pop(
      _LaunchConfigDialogResult(
        action: _LaunchConfigDialogAction.saved,
        path: path,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _phase == _LaunchConfigPanelPhase.success
        ? 'App snapshot saved'
        : 'Save or reapply the current app state';
    final subtitle = _phase == _LaunchConfigPanelPhase.success
        ? 'Use the saved file path below to verify, copy, or immediately reapply this app export.'
        : 'Use one file to capture windows, tabs, panes, startup commands, and session context across the whole app.';
    return Dialog(
      key: const Key('terminal-launch-config-panel'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        key: const Key('terminal-launch-config-dialog'),
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Export Ianvs App',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: Color(0xFF93C5FD),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 18),
              if (_phase == _LaunchConfigPanelPhase.compose) ...[
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSaveSettingsCard(),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _LaunchConfigStatCard(
                              label: 'Windows',
                              value: '$_windowCount',
                            ),
                            _LaunchConfigStatCard(
                              label: 'Tabs',
                              value: '$_tabCount',
                            ),
                            _LaunchConfigStatCard(
                              label: 'Panes',
                              value: '$_paneCount',
                            ),
                            _LaunchConfigStatCard(
                              label: 'Active window',
                              value:
                                  'Window ${widget.tabsController.activeWindowIndex + 1}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 360,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final wide = constraints.maxWidth >= 720;
                              final snapshot = DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111827),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF233047),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _buildAppSnapshotColumn(),
                                ),
                              );
                              final commands = DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111827),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF233047),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _buildStartupCommandsColumn(),
                                ),
                              );
                              if (!wide) {
                                return Column(
                                  children: [
                                    Expanded(child: snapshot),
                                    const SizedBox(height: 12),
                                    Expanded(child: commands),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: snapshot),
                                  const SizedBox(width: 16),
                                  Expanded(child: commands),
                                ],
                              );
                            },
                          ),
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorText!,
                            style: const TextStyle(color: Color(0xFFFCA5A5)),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              key: const Key(
                                'terminal-launch-config-apply-button',
                              ),
                              onPressed: _applyLaunchConfig,
                              child: const Text('Apply app config'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              key: const Key(
                                'terminal-launch-config-save-button',
                              ),
                              onPressed: _canSave ? _saveCurrentLayout : null,
                              child: const Text('Save current app'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                Expanded(child: _buildSuccessState()),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LaunchConfigPanelPhase { compose, success }

enum _LaunchConfigDialogAction { saved, applied }

class _LaunchConfigDialogResult {
  const _LaunchConfigDialogResult({required this.action, required this.path});

  final _LaunchConfigDialogAction action;
  final String path;
}

class _LaunchConfigPaneField {
  const _LaunchConfigPaneField({
    required this.fieldId,
    required this.windowLabel,
    required this.tabLabel,
    required this.paneId,
    required this.cwd,
    required this.startupCommand,
    required this.contextLabel,
    required this.shellController,
  });

  final String fieldId;
  final String windowLabel;
  final String tabLabel;
  final int paneId;
  final String cwd;
  final String startupCommand;
  final String contextLabel;
  final LocalShellSessionController shellController;
}

class _LaunchConfigStatCard extends StatelessWidget {
  const _LaunchConfigStatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF233047)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _LaunchConfigTabSummary {
  const _LaunchConfigTabSummary({required this.label, required this.paneCount});

  final String label;
  final int paneCount;
}

class _LaunchConfigWindowCard extends StatelessWidget {
  const _LaunchConfigWindowCard({
    required this.windowLabel,
    required this.active,
    required this.tabSummaries,
  });

  final String windowLabel;
  final bool active;
  final List<_LaunchConfigTabSummary> tabSummaries;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF172554) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? const Color(0xFF4D8DFF) : const Color(0xFF233047),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                windowLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (active)
                const Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF93C5FD),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final summary in tabSummaries) ...[
            Text(
              summary.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${summary.paneCount} pane${summary.paneCount == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
            if (!identical(summary, tabSummaries.last))
              const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SessionContextUpdate {
  const _SessionContextUpdate({
    required this.metadata,
    required this.launchProfile,
  });

  final TerminalSessionMetadata metadata;
  final TerminalSessionLaunchProfile launchProfile;
}

class _NewSshSessionRequest {
  const _NewSshSessionRequest({
    required this.host,
    required this.account,
    required this.environment,
    required this.project,
  });

  final String host;
  final String account;
  final String environment;
  final String project;
}

class _SessionContextPanel extends StatefulWidget {
  const _SessionContextPanel({
    required this.initialMetadata,
    required this.initialLaunchProfile,
    required this.auditEntryCount,
  });

  final TerminalSessionMetadata initialMetadata;
  final TerminalSessionLaunchProfile initialLaunchProfile;
  final int auditEntryCount;

  @override
  State<_SessionContextPanel> createState() => _SessionContextPanelState();
}

class _SessionContextPanelState extends State<_SessionContextPanel> {
  late TerminalSessionKind _kind;
  late final TextEditingController _hostController;
  late final TextEditingController _accountController;
  late final TextEditingController _environmentController;
  late final TextEditingController _projectController;
  late final TextEditingController _identityController;
  late final TextEditingController _sourceController;
  late final TextEditingController _validUntilController;
  String? _errorText;

  bool get _transportLockedToSshCommand =>
      widget.initialLaunchProfile.isSshCommand;

  @override
  void initState() {
    super.initState();
    final metadata = widget.initialMetadata;
    _kind = metadata.kind;
    _hostController = TextEditingController(text: metadata.host);
    _accountController = TextEditingController(text: metadata.account);
    _environmentController = TextEditingController(text: metadata.environment);
    _projectController = TextEditingController(text: metadata.project);
    _identityController = TextEditingController(
      text: metadata.safetyContext.identity,
    );
    _sourceController = TextEditingController(
      text: metadata.safetyContext.authorizationSource,
    );
    _validUntilController = TextEditingController(
      text: metadata.safetyContext.validUntil,
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _accountController.dispose();
    _environmentController.dispose();
    _projectController.dispose();
    _identityController.dispose();
    _sourceController.dispose();
    _validUntilController.dispose();
    super.dispose();
  }

  TerminalSessionMetadata _buildMetadata() {
    return TerminalSessionMetadata(
      kind: _transportLockedToSshCommand ? TerminalSessionKind.ssh : _kind,
      host: _hostController.text,
      account: _accountController.text,
      environment: _environmentController.text,
      project: _projectController.text,
      safetyContext: TerminalSafetyContext(
        identity: _identityController.text,
        authorizationSource: _sourceController.text,
        validUntil: _validUntilController.text,
      ),
    );
  }

  TerminalSessionLaunchProfile _buildLaunchProfile() {
    if (_transportLockedToSshCommand) {
      return TerminalSessionLaunchProfile.sshCommand(
        host: _hostController.text.trim(),
        account: _accountController.text.trim(),
      );
    }
    return const TerminalSessionLaunchProfile.localShell();
  }

  @override
  Widget build(BuildContext context) {
    final auditLabel = widget.auditEntryCount == 1
        ? '1 completed block'
        : '${widget.auditEntryCount} completed blocks';
    final currentTransportLabel = _transportLockedToSshCommand
        ? 'SSH command via local PTY'
        : (_kind == TerminalSessionKind.ssh
              ? 'Metadata only on top of a local shell'
              : 'Local shell');
    return AlertDialog(
      key: const Key('terminal-session-context-panel'),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Session Context',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            key: const Key('terminal-session-context-close-button'),
            tooltip: 'Close session context',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Current transport: $currentTransportLabel.',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFBFDBFE),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _transportLockedToSshCommand
                    ? 'This pane already launches a local `ssh` command. Host and account changes here will affect restart, restore, and launch config recreation.'
                    : 'This panel edits display metadata and safety context for the active pane. Use `New SSH Session` when you need a real local `ssh` command session.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Session Type',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('terminal-session-kind-local'),
                    label: const Text('Local'),
                    selected: _kind == TerminalSessionKind.local,
                    onSelected: _transportLockedToSshCommand
                        ? null
                        : (_) {
                            setState(() {
                              _kind = TerminalSessionKind.local;
                            });
                          },
                  ),
                  ChoiceChip(
                    key: const Key('terminal-session-kind-ssh'),
                    label: const Text('SSH'),
                    selected: _kind == TerminalSessionKind.ssh,
                    onSelected: (_) {
                      setState(() {
                        _kind = TerminalSessionKind.ssh;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('terminal-session-host-field'),
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: 'prod.example.internal',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('terminal-session-account-field'),
                controller: _accountController,
                decoration: const InputDecoration(
                  labelText: 'Account',
                  hintText: 'ops-user',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('terminal-session-environment-field'),
                controller: _environmentController,
                decoration: const InputDecoration(
                  labelText: 'Environment',
                  hintText: 'prod-us-east-1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('terminal-session-project-field'),
                controller: _projectController,
                decoration: const InputDecoration(
                  labelText: 'Project',
                  hintText: 'payments-api',
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Safety Context',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('terminal-session-identity-field'),
                controller: _identityController,
                decoration: const InputDecoration(
                  labelText: 'Identity',
                  hintText: 'robin.oncall',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('terminal-session-auth-source-field'),
                controller: _sourceController,
                decoration: const InputDecoration(
                  labelText: 'Authorization source',
                  hintText: 'Ianvs Access / Okta',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('terminal-session-valid-until-field'),
                controller: _validUntilController,
                decoration: const InputDecoration(
                  labelText: 'Valid until',
                  hintText: '2026-05-03T18:00:00Z',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Audit snapshot ready: $auditLabel.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: const TextStyle(color: Color(0xFFFCA5A5)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('terminal-session-context-apply-button'),
          onPressed: () {
            final metadata = _buildMetadata();
            if (metadata.kind == TerminalSessionKind.ssh) {
              final hostError = sshHostValidationError(metadata.host);
              if (hostError != null) {
                setState(() {
                  _errorText = hostError;
                });
                return;
              }
            }
            Navigator.of(context).pop(
              _SessionContextUpdate(
                metadata: metadata,
                launchProfile: _buildLaunchProfile(),
              ),
            );
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _NewSshSessionPanel extends StatefulWidget {
  const _NewSshSessionPanel();

  @override
  State<_NewSshSessionPanel> createState() => _NewSshSessionPanelState();
}

class _NewSshSessionPanelState extends State<_NewSshSessionPanel> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _environmentController = TextEditingController();
  final TextEditingController _projectController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _hostController.dispose();
    _accountController.dispose();
    _environmentController.dispose();
    _projectController.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _hostController.text.trim();
    final hostError = sshHostValidationError(host);
    if (hostError != null) {
      setState(() {
        _errorText = hostError;
      });
      return;
    }
    Navigator.of(context).pop(
      _NewSshSessionRequest(
        host: host,
        account: _accountController.text.trim(),
        environment: _environmentController.text.trim(),
        project: _projectController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('terminal-new-ssh-session-panel'),
      title: const Text(
        'New SSH Session',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Launch a new tab that runs the local `ssh` command through the existing PTY runtime. This is not an Ianvs gateway or zero-trust client.',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('terminal-new-ssh-host-field'),
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: 'prod.example.internal',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('terminal-new-ssh-account-field'),
                controller: _accountController,
                decoration: const InputDecoration(
                  labelText: 'Account',
                  hintText: 'ops-user',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('terminal-new-ssh-environment-field'),
                controller: _environmentController,
                decoration: const InputDecoration(
                  labelText: 'Environment',
                  hintText: 'prod-use1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('terminal-new-ssh-project-field'),
                controller: _projectController,
                decoration: const InputDecoration(
                  labelText: 'Project',
                  hintText: 'payments-api',
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: const TextStyle(color: Color(0xFFFCA5A5)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('terminal-new-ssh-open-button'),
          onPressed: _submit,
          child: const Text('Open SSH tab'),
        ),
      ],
    );
  }
}

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({required this.controller});

  final TerminalSettingsController controller;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  late final TextEditingController _fontFamilyController;
  late final TextEditingController _shellController;
  late final TextEditingController _startupShellController;
  String? _shellError;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _fontFamilyController = TextEditingController(text: settings.fontFamily);
    _shellController = TextEditingController(text: settings.defaultShell);
    _startupShellController = TextEditingController(
      text: settings.defaultShell,
    );
  }

  @override
  void dispose() {
    _fontFamilyController.dispose();
    _shellController.dispose();
    _startupShellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('terminal-settings-panel'),
      backgroundColor: const Color(0xFF151922),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final settings = widget.controller.settings;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('settings-close-button'),
                          tooltip: 'Close settings',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('settings-font-family-field'),
                      controller: _fontFamilyController,
                      onChanged: widget.controller.updateFontFamily,
                      decoration: const InputDecoration(
                        labelText: 'Font family',
                        hintText: 'Use flutterm default',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Text('Font size')),
                        IconButton(
                          key: const Key('settings-font-size-decrease'),
                          tooltip: 'Decrease font size',
                          onPressed: () {
                            widget.controller.updateFontSize(
                              settings.fontSize - 1,
                            );
                          },
                          icon: const Icon(Icons.remove, size: 18),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            settings.fontSize.toStringAsFixed(0),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          key: const Key('settings-font-size-increase'),
                          tooltip: 'Increase font size',
                          onPressed: () {
                            widget.controller.updateFontSize(
                              settings.fontSize + 1,
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in TerminalThemePreset.values)
                          ChoiceChip(
                            key: Key('settings-theme-${preset.name}'),
                            label: Text(preset.label),
                            selected: settings.themePreset == preset,
                            onSelected: (_) {
                              widget.controller.updateThemePreset(preset);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('settings-shell-field'),
                            controller: _shellController,
                            onChanged: (_) {
                              if (_shellError != null) {
                                setState(() => _shellError = null);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'New session shell',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              errorText: _shellError,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          key: const Key('settings-shell-apply'),
                          onPressed: _applyShell,
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSessionDefaults(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _applyShell() {
    final saved = widget.controller.updateDefaultShell(_shellController.text);
    setState(() {
      _shellError = saved ? null : 'Shell path is required';
      if (saved) {
        _startupShellController.text = _shellController.text.trim();
      }
    });
  }

  Widget _buildSessionDefaults() {
    return DecoratedBox(
      key: const Key('settings-session-defaults-section'),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF273244)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Session defaults',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Reserved controls for new sessions, startup commands, and cwd inheritance. These defaults keep macOS local shells first while leaving room for split, tab, and window-specific launch policy.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('settings-startup-shell-field'),
              controller: _startupShellController,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Startup shell',
                helperText: 'Reserved for startup command execution policy.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: const [
                _ReservedCwdPolicyField(
                  fieldKey: Key('settings-cwd-policy-split'),
                  label: 'Split cwd policy',
                  value: 'Inherit active pane cwd',
                ),
                _ReservedCwdPolicyField(
                  fieldKey: Key('settings-cwd-policy-tab'),
                  label: 'Tab cwd policy',
                  value: 'Inherit active tab cwd',
                ),
                _ReservedCwdPolicyField(
                  fieldKey: Key('settings-cwd-policy-window'),
                  label: 'Window cwd policy',
                  value: 'Use home directory',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReservedCwdPolicyField extends StatelessWidget {
  const _ReservedCwdPolicyField({
    required this.fieldKey,
    required this.label,
    required this.value,
  });

  final Key fieldKey;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: TextFormField(
        key: fieldKey,
        initialValue: value,
        enabled: false,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1517),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF7F1D1D)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unable to start local shell\n$error',
                  style: const TextStyle(color: Color(0xFFFECACA), height: 1.4),
                ),
                const SizedBox(height: 14),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _sessionLabel(String sessionId) {
  if (sessionId.startsWith('session-')) {
    return sessionId;
  }
  return 'session-$sessionId';
}

String? _transportBadgeLabel({
  required TerminalSessionMetadata metadata,
  required TerminalSessionLaunchProfile launchProfile,
}) {
  if (launchProfile.isSshCommand) {
    return 'SSH command';
  }
  if (metadata.isSsh) {
    return 'Metadata only';
  }
  return null;
}

class _OpenFindIntent extends Intent {
  const _OpenFindIntent();
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

class _OpenModernInputIntent extends Intent {
  const _OpenModernInputIntent();
}

class _OpenCommandHistoryIntent extends Intent {
  const _OpenCommandHistoryIntent();
}

class _OpenWorkspaceSearchIntent extends Intent {
  const _OpenWorkspaceSearchIntent();
}

class _ToggleRawInputIntent extends Intent {
  const _ToggleRawInputIntent();
}

class _NewWindowIntent extends Intent {
  const _NewWindowIntent();
}

class _NewTabIntent extends Intent {
  const _NewTabIntent();
}

class _CloseWindowIntent extends Intent {
  const _CloseWindowIntent();
}

class _CloseTabIntent extends Intent {
  const _CloseTabIntent();
}

class _SplitPaneRightIntent extends Intent {
  const _SplitPaneRightIntent();
}

class _SplitPaneDownIntent extends Intent {
  const _SplitPaneDownIntent();
}

class _ClosePaneIntent extends Intent {
  const _ClosePaneIntent();
}

class _NextPaneIntent extends Intent {
  const _NextPaneIntent();
}

class _PreviousPaneIntent extends Intent {
  const _PreviousPaneIntent();
}

class _NextTabIntent extends Intent {
  const _NextTabIntent();
}

class _PreviousTabIntent extends Intent {
  const _PreviousTabIntent();
}

class _CloseFindIntent extends Intent {
  const _CloseFindIntent();
}

class _CloseCommandHistoryIntent extends Intent {
  const _CloseCommandHistoryIntent();
}

class _CloseWorkspaceSearchIntent extends Intent {
  const _CloseWorkspaceSearchIntent();
}

class _NextCommandHistoryIntent extends Intent {
  const _NextCommandHistoryIntent();
}

class _PreviousCommandHistoryIntent extends Intent {
  const _PreviousCommandHistoryIntent();
}

class _ChooseCommandHistoryIntent extends Intent {
  const _ChooseCommandHistoryIntent();
}

class _NextFindIntent extends Intent {
  const _NextFindIntent();
}

class _PreviousFindIntent extends Intent {
  const _PreviousFindIntent();
}
