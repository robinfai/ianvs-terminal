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
                        onModernInputRequested: _focusModernInput,
                      ),
                      if (_commandPaletteController.isOpen)
                        _CommandPalettePanel(
                          controller: _commandPaletteController,
                          textController: _paletteTextControllerForMode(),
                          focusNode: _paletteFocusNodeForMode(),
                          mode: _paletteOpenFilter,
                          chooseEnabled: activeShell.canAcceptInput,
                          lightTheme:
                              _settingsController.settings.themePreset ==
                              TerminalThemePreset.light,
                          onClose: _closeCommandHistory,
                          onChoose: _chooseCommandHistoryEntry,
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
    return _PaneChrome(
      paneId: pane.id,
      active: isActivePane,
      onSelected: () {
        _tabsController.selectPane(pane.id);
      },
      child: _bodyForShellState(pane, isActivePane: isActivePane),
    );
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
      shellController: shellController,
      inputController: inputController,
      focusNode: _terminalFocusNodeForPane(pane.id),
      modernInputFocusNode: _modernInputFocusNode,
      commandHistoryFocusNode: _commandHistoryFocusNode,
      commandHistoryTextController: _commandHistoryTextController,
      sessionLabel: _sessionLabel(sessionId),
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
              suggestedNamedLaunchConfigPath(
                name: 'Ianvs Terminal App',
                currentPath: Directory.current.path,
              ),
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
    required this.onModernInputRequested,
  });

  final TerminalWindowsController tabsController;
  final VoidCallback onNewSshSessionRequested;
  final VoidCallback onSearch;
  final VoidCallback onWorkspaceSearchRequested;
  final VoidCallback onSettings;
  final VoidCallback onSessionContextRequested;
  final VoidCallback onLaunchConfigRequested;
  final VoidCallback onModernInputRequested;

  @override
  Widget build(BuildContext context) {
    final activeShell = tabsController.activeShell;
    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF171A21),
        border: Border(bottom: BorderSide(color: Color(0xFF252B36))),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              const Text(
                'Ianvs Terminal',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              _SessionBadge(label: activeShell.sessionMetadata.kind.label),
              const SizedBox(width: 6),
              _StatusBadge(
                status: activeShell.status,
                exitCode: activeShell.exitCode,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: _WindowStrip(tabsController: tabsController),
              ),
              const SizedBox(width: 8),
              Expanded(child: _TabStrip(tabsController: tabsController)),
              _HeaderActionButton(
                key: const Key('terminal-new-window-button'),
                tooltip: 'New window',
                onPressed: tabsController.newWindow,
                icon: Icons.open_in_new,
              ),
              _HeaderActionButton(
                key: const Key('terminal-close-window-button'),
                tooltip: 'Close window',
                onPressed: tabsController.canCloseActiveWindow
                    ? tabsController.closeActiveWindow
                    : null,
                icon: Icons.web_asset_off_outlined,
              ),
              _HeaderActionButton(
                key: const Key('terminal-new-tab-button'),
                tooltip: 'New tab',
                onPressed: tabsController.newTab,
                icon: Icons.add,
              ),
              _HeaderActionButton(
                key: const Key('terminal-new-ssh-session-button'),
                tooltip: 'New SSH session',
                onPressed: onNewSshSessionRequested,
                icon: Icons.lan_outlined,
              ),
              _HeaderActionButton(
                key: const Key('terminal-settings-button'),
                tooltip: 'Settings',
                onPressed: onSettings,
                icon: Icons.tune,
              ),
              _HeaderActionButton(
                key: const Key('terminal-launch-config-button'),
                tooltip: 'Launch config',
                onPressed: onLaunchConfigRequested,
                icon: Icons.rocket_launch_outlined,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _HeaderActionButton(
                key: const Key('terminal-search-button'),
                tooltip: 'Search',
                onPressed: onSearch,
                icon: Icons.search,
              ),
              _HeaderActionButton(
                key: const Key('terminal-workspace-search-button'),
                tooltip: 'Workspace search',
                onPressed: onWorkspaceSearchRequested,
                icon: Icons.travel_explore,
              ),
              _HeaderActionButton(
                key: const Key('terminal-split-right-button'),
                tooltip: 'Split right',
                onPressed: tabsController.splitActivePaneRight,
                icon: Icons.vertical_split,
              ),
              _HeaderActionButton(
                key: const Key('terminal-split-down-button'),
                tooltip: 'Split down',
                onPressed: tabsController.splitActivePaneDown,
                icon: Icons.horizontal_split,
              ),
              _HeaderActionButton(
                key: const Key('terminal-close-pane-button'),
                tooltip: 'Close pane',
                onPressed: tabsController.canCloseActivePane
                    ? tabsController.closeActivePane
                    : null,
                icon: Icons.close_fullscreen,
              ),
              _HeaderActionButton(
                key: const Key('terminal-session-context-button'),
                tooltip: 'Session context',
                onPressed: onSessionContextRequested,
                icon: Icons.security,
              ),
              _HeaderActionButton(
                key: const Key('terminal-copy-button'),
                tooltip: 'Copy',
                onPressed: activeShell.canCopy
                    ? activeShell.copySelection
                    : null,
                icon: Icons.copy,
              ),
              _HeaderActionButton(
                key: const Key('terminal-paste-button'),
                tooltip: 'Paste',
                onPressed: activeShell.canPaste
                    ? activeShell.pasteClipboard
                    : null,
                icon: Icons.content_paste,
              ),
              _HeaderActionButton(
                key: const Key('terminal-restart-button'),
                tooltip: 'Restart',
                onPressed: activeShell.canRestart ? activeShell.restart : null,
                icon: Icons.restart_alt,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BlockToolbar(
                  controller: activeShell.blocksController,
                  reinputEnabled: activeShell.canAcceptInput,
                  onReinput: onModernInputRequested,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
  const _InlineBlockRail({required this.controller, required this.lightTheme});

  final TerminalBlocksController controller;
  final bool lightTheme;

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
    return Container(
      key: const Key('terminal-inline-block-rail'),
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
            lightTheme: lightTheme,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
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
      ),
    );
  }
}

class _InlineActiveBlockCard extends StatelessWidget {
  const _InlineActiveBlockCard({
    required this.controller,
    required this.block,
    required this.lightTheme,
  });

  final TerminalBlocksController controller;
  final TerminalBlock block;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    final (badgeBackground, badgeBorder, badgeIndicator) =
        _inlineBlockStatusColors(block.status, lightTheme);
    final cardBackground = lightTheme
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF111827);
    final textColor = lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final outputPreview = _firstOutputLine(block.outputText);
    return Container(
      key: const Key('terminal-inline-active-block-card'),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeBorder),
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
                      '${controller.displayIndex} of ${controller.blocks.length}',
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  _singleLinePreview(block.commandText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
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
        ],
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

class _WindowStrip extends StatelessWidget {
  const _WindowStrip({required this.tabsController});

  final TerminalWindowsController tabsController;

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
  });

  final int windowId;
  final String title;
  final bool active;
  final VoidCallback onSelect;

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
      child: InkWell(
        key: Key('terminal-window-$windowId'),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? const Color(0xFFE5E7EB) : const Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.tabsController});

  final TerminalWindowsController tabsController;

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
                title: tabsController.tabs[index].title,
                active: index == tabsController.activeIndex,
                onSelect: () => tabsController.selectTab(index),
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

class _TerminalTabButton extends StatelessWidget {
  const _TerminalTabButton({
    required this.title,
    required this.active,
    required this.onSelect,
    this.onClose,
  });

  final String title;
  final bool active;
  final VoidCallback onSelect;
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
    required this.onSelected,
    required this.child,
  });

  final int paneId;
  final bool active;
  final VoidCallback onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: Key('terminal-pane-$paneId'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onSelected(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? const Color(0xFF4D8DFF) : const Color(0xFF111827),
            width: active ? 2 : 1,
          ),
        ),
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
    final background = widget.lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF111827);
    final borderColor = widget.lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF252B36);
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
    return Container(
      key: const Key('terminal-command-palette-panel'),
      height: 280,
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: Key(
              sessionMode
                  ? 'terminal-workspace-search-panel'
                  : 'terminal-command-history-panel',
            ),
            height: 0,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 320,
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
                Expanded(
                  child: Text(
                    'Use saved:, history:, session:, ssh:',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mutedColor, fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous palette result',
                  onPressed: matches.isEmpty
                      ? null
                      : widget.controller.goToPrevious,
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                ),
                IconButton(
                  tooltip: 'Next palette result',
                  onPressed: matches.isEmpty
                      ? null
                      : widget.controller.goToNext,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                ),
                IconButton(
                  tooltip: sessionMode
                      ? 'Close workspace search'
                      : 'Close command history',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Text(
                      sessionMode
                          ? 'No sessions match'
                          : 'No commands or sessions match',
                      style: TextStyle(color: mutedColor, fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final entry = matches[index];
                      return _CommandPaletteEntryRow(
                        key: Key(
                          entry.isSessionEntry
                              ? 'terminal-workspace-search-row-${entry.id}'
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
                        onTap: entry.isSessionEntry || widget.chooseEnabled
                            ? () {
                                widget.controller.selectEntryAt(index);
                                unawaited(_choose());
                              }
                            : null,
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
      final entry = widget.controller.activeEntry;
      if (entry != null && (entry.isSessionEntry || widget.chooseEnabled)) {
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
                : _buildCommandRow(textColor, mutedColor),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionRow(Color textColor, Color mutedColor) {
    return Row(
      children: [
        SizedBox(
          width: 82,
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
        const SizedBox(width: 8),
        const _CommandSourceBadge(source: CommandPaletteEntrySource.session),
        const SizedBox(width: 6),
        if (entry.isActivePane)
          const _WorkspaceActiveBadge(label: 'Active pane')
        else if (entry.isActiveTab)
          const _WorkspaceActiveBadge(label: 'Active tab'),
        if (entry.isActivePane || entry.isActiveTab) const SizedBox(width: 6),
        _CompactWorkspaceStatusBadge(
          status: entry.status,
          exitCode: entry.exitCode,
        ),
        if (entry.isSshSession) ...[
          const SizedBox(width: 6),
          const _SessionModeBadge(label: 'SSH'),
        ],
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
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
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            _singleLinePreview(entry.cwd),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: mutedColor, fontSize: 11),
          ),
        ),
        if (entry.lastCommand.isNotEmpty) ...[
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              _singleLinePreview(entry.lastCommand),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: mutedColor, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCommandRow(Color textColor, Color mutedColor) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            entry.source == CommandPaletteEntrySource.saved
                ? 'Save'
                : entry.windowLabel,
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
            entry.source == CommandPaletteEntrySource.saved
                ? _singleLinePreview(entry.savedEntry.cwdHint)
                : entry.outputPreview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: mutedColor, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: entry.source == CommandPaletteEntrySource.saved
              ? 'Remove saved command'
              : 'Save history command',
          onPressed: entry.source == CommandPaletteEntrySource.saved
              ? onRemove
              : onSave,
          icon: Icon(
            entry.source == CommandPaletteEntrySource.saved
                ? Icons.bookmark_remove
                : Icons.bookmark_add,
            size: 16,
          ),
        ),
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
    required this.shellController,
    required this.inputController,
    required this.focusNode,
    required this.modernInputFocusNode,
    required this.commandHistoryFocusNode,
    required this.commandHistoryTextController,
    required this.sessionLabel,
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

  final LocalShellSessionController shellController;
  final terminal.TerminalInputController inputController;
  final FocusNode focusNode;
  final FocusNode modernInputFocusNode;
  final FocusNode commandHistoryFocusNode;
  final TextEditingController commandHistoryTextController;
  final String sessionLabel;
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

  @override
  Widget build(BuildContext context) {
    final rawInputActive =
        shellController.modernInputController.state.effectiveMode ==
        ModernInputEffectiveMode.raw;
    focusNode.canRequestFocus = inputEnabled && rawInputActive && isActivePane;
    final colors = settings.themePreset.viewportColors;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.canvasBackground),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              animation: shellController.blocksController,
              builder: (context, _) {
                final lightTheme =
                    settings.themePreset == TerminalThemePreset.light;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
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
                                return terminal.TerminalViewport(
                                  focusNode: focusNode,
                                  controller:
                                      shellController.viewportController,
                                  selectionController:
                                      shellController.selectionController,
                                  inputController: inputController,
                                  contentPadding: const EdgeInsets.all(14),
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
                                    shellController.scrollViewport(delta);
                                  },
                                  onScrollToOffset: (offset) {
                                    shellController.scrollViewportTo(offset);
                                  },
                                );
                              },
                            ),
                          ),
                          if (isActivePane &&
                              shellController.blocksController.hasBlocks)
                            Positioned(
                              top: 12,
                              left: 18,
                              right: 18,
                              child: _InlineBlockRail(
                                controller: shellController.blocksController,
                                lightTheme: lightTheme,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isActivePane &&
                        shellController.blocksController.hasBlocks)
                      _BlockHistoryPanel(
                        controller: shellController.blocksController,
                        reinputEnabled: shellController.canAcceptInput,
                        lightTheme: lightTheme,
                        onReinput: onModernInputRequested,
                      ),
                  ],
                );
              },
            ),
          ),
          if (isActivePane && shellController.commandHistoryController.isOpen)
            _CommandHistoryPanel(
              controller: shellController.commandHistoryController,
              textController: commandHistoryTextController,
              focusNode: commandHistoryFocusNode,
              chooseEnabled: inputEnabled,
              lightTheme: settings.themePreset == TerminalThemePreset.light,
              onClose: onCommandHistoryClosed,
              onChoose: onCommandHistorySelected,
              onModernInputRequested: onModernInputRequested,
            ),
          if (isActivePane && shellController.completionController.isOpen)
            _CompletionPanel(
              controller: shellController.completionController,
              lightTheme: settings.themePreset == TerminalThemePreset.light,
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
              onModernInputRequested: onModernInputRequested,
              onRawInputRequested: onRawInputRequested,
              onCommandHistoryRequested: onCommandHistoryRequested,
              onSaveCommandRequested: onSaveCommandRequested,
            ),
        ],
      ),
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
    return Container(
      key: const Key('terminal-modern-input-bar'),
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
          : Row(
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: Color(0xFF4D8DFF),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _HeaderActionButton(
                  key: const Key('terminal-modern-submit-button'),
                  tooltip: 'Submit command',
                  onPressed: widget.enabled && widget.controller.canSubmit
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
    final background = lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);
    final borderColor = lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF273244);
    final foreground = lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final muted = lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    return Container(
      key: const Key('terminal-completion-panel'),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          final active = index == controller.activeIndex;
          return Container(
            key: Key('terminal-completion-row-${suggestion.name}'),
            color: active ? const Color(0x334D8DFF) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                SizedBox(
                  width: 80,
                  child: Text(
                    _completionSourceLabel(suggestion.source),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    suggestion.description,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
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
    final background = widget.lightTheme
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF111827);
    final borderColor = widget.lightTheme
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF252B36);
    final textColor = widget.lightTheme
        ? const Color(0xFF0F172A)
        : const Color(0xFFE5E7EB);
    final mutedColor = widget.lightTheme
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    return Container(
      key: const Key('terminal-command-history-panel'),
      height: 250,
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
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
                  onPressed: matches.isEmpty
                      ? null
                      : widget.controller.goToNext,
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
          Divider(height: 1, color: borderColor),
          Expanded(
            child: matches.isEmpty
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
                        key: Key(
                          'terminal-command-history-row-${entry.blockId}',
                        ),
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
      _ => false,
    };
    final session = switch (source) {
      CommandPaletteEntrySource.session => true,
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
    return suggestedNamedLaunchConfigPath(
      name: _nameController.text,
      currentPath: Directory.current.path,
    );
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
  String? _shellError;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _fontFamilyController = TextEditingController(text: settings.fontFamily);
    _shellController = TextEditingController(text: settings.defaultShell);
  }

  @override
  void dispose() {
    _fontFamilyController.dispose();
    _shellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('terminal-settings-panel'),
      backgroundColor: const Color(0xFF151922),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final settings = widget.controller.settings;
              return Column(
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
                            labelText: 'Default shell',
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
                ],
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
    });
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
