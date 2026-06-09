import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../platform/clipboard_bridge.dart';
import '../../ui/app_ui.dart';
import '../config/local_terminal_config_bootstrap.dart';
import '../config/local_terminal_config_models.dart';
import '../config/local_terminal_config_preferences_adapter.dart';
import '../preferences/app_preferences_models.dart';
import '../policies/local_terminal_paste_decision.dart';
import '../policies/local_terminal_policy_models.dart';
import '../profiles/dynamic_profiles_sheet.dart';
import '../profiles/profile_editor.dart';
import '../profiles/profile_models.dart';
import '../profiles/profiles_sheet.dart';
import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_command_block_controller.dart';
import '../productivity/shell_productivity_models.dart';
import '../productivity/shell_productivity_reducer.dart';
import '../sessions/session_controller.dart';
import '../sessions/session_state.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal.dart' as terminal;
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart';
import '../visual/local_terminal_diagnostics_exporter.dart';
import '../visual/local_terminal_scrollback_exporter.dart';
import '../visual/local_terminal_visual_models.dart';
import 'advanced_paste_transformer.dart';
import 'defaults_appearance_dialog.dart';
import 'instant_replay_store.dart';
import 'paste_history_repository.dart';
import 'password_manager_store.dart';
import 'reference_demo.dart';
import 'local_terminal_shell_ui_wiring_exports.dart';
import 'shell_acceptance.dart';
import 'shell_action_registry.dart';
import 'shell_action_runtime_bindings.dart';
import 'shell_command_block_view_models.dart';
import 'shell_shortcut_bridge.dart';
import 'window_bridge.dart';

part 'shell_screen_state_events.dart';
part 'shell_screen_state_coprocesses.dart';
part 'shell_screen_state_shortcuts_status.dart';
part 'shell_screen_state_sessions.dart';
part 'shell_screen_state_clipboard.dart';
part 'shell_screen_state_integrations.dart';
part 'shell_screen_state_instant_replay.dart';
part 'shell_screen_state_search_completion.dart';
part 'shell_screen_state_profile_actions.dart';
part 'shell_screen_state_command_actions.dart';
part 'shell_screen_state_terminal_workspace.dart';
part 'shell_screen_models.dart';
part 'shell_screen_toolbelt.dart';
part 'shell_screen_status_bar.dart';
part 'shell_screen_chrome.dart';
part 'shell_screen_search.dart';
part 'shell_screen_shell_integration.dart';
part 'shell_screen_completion.dart';
part 'shell_screen_instant_replay.dart';
part 'shell_screen_sheets.dart';
part 'shell_screen_command_menu.dart';
part 'shell_screen_shared_buttons.dart';
part 'shell_screen_command_blocks.dart';
part 'shell_screen_history_peek.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  static const _workspaceCueDuration = Duration(milliseconds: 1400);
  static const _viewportResizeDebounce = Duration(milliseconds: 240);
  static const _terminalOverlayPadding = EdgeInsets.fromLTRB(12, 10, 14, 12);
  static const _pasteHistoryLimit = 30;
  static const _capturedOutputLimit = 80;
  static const _minimumHorizontalPaneCols = 24;
  static const _minimumVerticalPaneRows = 8;
  static const _paneGrowRatioStep = 0.08;
  static const _minimumSiblingPaneRatio = 0.24;
  static const _paneDividerDragThickness = 8.0;

  final Map<String, SelectionController> _selectionControllers = {};
  final Map<String, FocusNode> _terminalFocusNodes = {};
  final Map<String, TextEditingController> _commandInputControllers = {};
  final Map<String, FocusNode> _commandInputFocusNodes = {};
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'shell-search');
  final Map<String, Size> _scheduledViewportSizes = {};
  final Map<String, Size> _committedViewportSizes = {};
  final Map<String, Size> _measuredTerminalCellSizes = {};
  final Map<String, double> _terminalViewportDevicePixelRatios = {};
  final Set<String> _readOnlySessionIds = {};
  final Map<String, DateTime> _lastActivityNotificationAt = {};
  final Map<String, String?> _lastActivityFramePreviews = {};
  final Map<String, String?> _lastNewOutputFramePreviews = {};
  final Map<String, Set<String>> _triggerMatchesBySession = {};
  final Map<String, int> _terminalFrameSequenceBySession = {};
  final Map<String, String> _searchRefreshFrameSignatures = {};
  final TextEditingController _autoComposerController = TextEditingController();
  final FocusNode _autoComposerFocusNode = FocusNode();
  final Set<String> _sessionsSeenForActivityNotifications = {};
  final Set<String> _sessionsSeenForNewOutputBadges = {};
  final Set<String> _sessionsWithNewOutput = {};
  StreamSubscription<terminal.TerminalSessionEvent>? _terminalEventSubscription;
  late final LocalTerminalShellUiWiringSnapshot _completionDiagnosticsSnapshot;
  Timer? _workspaceCueTimer;
  Timer? _viewportResizeTimer;
  bool _isCommandMenuOpen = false;
  bool _isDefaultsOpen = false;
  bool _isProfilesOpen = false;
  bool _isSearchOpen = false;
  bool _isAutocompleteOpen = false;
  bool _isAutoComposerOpen = false;
  bool _isCopyModeOpen = false;
  bool _isToolbeltOpen = false;
  bool _activeTerminalHasFocus = false;
  bool _recentlyClosedLastSession = false;
  bool _showWorkspaceCue = false;
  bool _showReturningCueOnNextFocus = false;
  String _workspaceCueTitle = 'Back in shell';
  bool _commandFinishedNotificationsEnabled = true;
  bool _bellNotificationsEnabled = true;
  bool _activityNotificationsEnabled = true;
  LocalTerminalConfigBootstrapSource _notificationConfigSource =
      LocalTerminalConfigBootstrapSource.defaults;
  LocalTerminalConfigDocument _notificationLocalConfig =
      const LocalTerminalConfigDocument();
  LocalTerminalKeybindingsConfig _keybindingsConfig =
      const LocalTerminalKeybindingsConfig();
  LocalTerminalClipboardConfig _clipboardConfig =
      const LocalTerminalClipboardConfig();
  LocalTerminalBracketedPastePolicy _bracketedPastePolicy =
      LocalTerminalBracketedPastePolicy.auto;
  LocalTerminalPastePolicy _pastePolicy = const LocalTerminalPastePolicy();
  LocalTerminalPasteHistoryPolicy _pasteHistoryPolicy =
      const LocalTerminalPasteHistoryPolicy();
  CommandBlocksHistoryFeatureFlags _commandBlocksHistoryFeatureFlags =
      CommandBlocksHistoryFeatureFlags.disabled;
  final Map<String, ShellCommandBlockSnapshot> _commandBlockSnapshotsBySession =
      {};
  bool _isHistoryPeekOpen = false;
  bool _notificationsBlockedBySystem = false;
  final Set<String> _notificationFailureCodesShown = <String>{};
  int _lastObservedTabCount = 0;
  String? _zoomedPaneSessionId;
  String? _lastRenderableSessionId;
  String _searchQuery = '';
  String? _searchErrorText;
  List<terminal.TerminalSearchMatch> _searchMatches = const [];
  int _activeSearchIndex = 0;
  int _searchFocusRequestSerial = 0;
  terminal.TerminalSearchMode _searchMode =
      terminal.TerminalSearchMode.smartCaseSubstring;
  String _autocompletePrefix = '';
  List<String> _autocompleteSuggestions = const [];
  int _activeAutocompleteIndex = 0;
  List<String> _autoComposerSuggestions = const [];
  int _activeAutoComposerIndex = 0;
  List<PasteHistoryEntry> _pasteHistoryEntries = const [];
  _InstantReplayWorkspaceSession? _instantReplayWorkspaceSession;
  List<_TerminalAnnotation> _annotations = const [];
  List<_CapturedOutputEntry> _capturedOutputEntries = const [];
  Map<String, _ShellCoprocess> _coprocesses = const {};
  bool _pasteHistoryPersistToDisk = false;
  bool _pasteHistoryLoaded = false;
  int _nextAnnotationId = 0;
  int _nextCapturedOutputId = 0;
  final Map<String, Set<String>> _coprocessInputKeysBySession =
      <String, Set<String>>{};
  int? _copyModeAnchorRow;
  int? _copyModeAnchorCol;
  int? _copyModeExtentRow;
  int? _copyModeExtentCol;

  @override
  void initState() {
    super.initState();
    WindowBridge.setNativeMenuHandlers(
      onPaste: _handleNativePasteMenu,
      onFind: _handleNativeFindMenu,
    );
    _completionDiagnosticsSnapshot =
        const LocalTerminalPendingCompletionSnapshotFactory(
          p0BoundaryManifest: LocalTerminalP0BoundaryClosureManifest(
            localTerminalPlanDocumented: true,
            roadmapLocalWorkspaceAligned: true,
            remoteScopeExcluded: true,
            perMilestoneExecutionPlansCreated: true,
            competitorCoverageMapped: true,
            productionWiringChecklistCreated: true,
          ),
        ).build(capturedAt: DateTime.now());
    _terminalEventSubscription = ref
        .read(terminalRuntimeControllerProvider)
        .events
        .listen(_handleTerminalSessionEvent);
    Future.microtask(_loadPasteHistory);
    Future.microtask(_loadNotificationPreferences);
  }

  @override
  void dispose() {
    WindowBridge.setNativeMenuHandlers();
    _terminalEventSubscription?.cancel();
    _workspaceCueTimer?.cancel();
    _viewportResizeTimer?.cancel();
    for (final focusNode in _terminalFocusNodes.values) {
      focusNode.dispose();
    }
    for (final controller in _commandInputControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _commandInputFocusNodes.values) {
      focusNode.dispose();
    }
    _searchFocusNode.dispose();
    _autoComposerController.dispose();
    _autoComposerFocusNode.dispose();
    super.dispose();
  }

  void _mutateState(VoidCallback fn) {
    setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(sessionControllerProvider);
    _syncPresentationState(sessionState);
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final activeSessionId = sessionState.activeSessionId;
    final defaultProfile = _effectiveDefaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    final defaultSummary = _defaultSummary(
      sessionState.profiles,
      sessionState.configuredDefaultProfileId,
      sessionState.defaultProfileId,
    );
    final referenceDemoMode = ref.watch(referenceDemoModeProvider);
    _publishAcceptanceSnapshot(sessionState);
    final animationsEnabled = ref.watch(shellAnimationsEnabledProvider);
    TerminalTab? activeTab;
    if (activeSessionId != null) {
      for (final tab in sessionState.tabs) {
        if (tab.containsSession(activeSessionId)) {
          activeTab = tab;
          break;
        }
      }
    }
    final displayedSessionId = _displayedSessionIdFor(
      sessionController,
      sessionState,
      activeSessionId,
    );
    final displayedTab = _tabForSession(sessionState, displayedSessionId);
    final palette = context.appTheme;
    final activePane = activeSessionId == null
        ? null
        : activeTab?.paneFor(activeSessionId);
    final activeShellIntegration =
        activePane?.shellIntegration ?? TerminalShellIntegrationSnapshot.empty;
    final statusPane = displayedSessionId == null
        ? activePane
        : displayedTab?.paneFor(displayedSessionId) ?? activePane;
    final statusDirectory = statusPane?.shellIntegration.currentDirectory;
    final statusProfile = statusPane == null
        ? null
        : _profileForPane(statusPane, sessionState.profiles);
    final statusViewportLabel = _viewportStatusLabelFor(displayedSessionId);
    final statusViewportController = displayedSessionId == null
        ? null
        : sessionController.viewportFor(displayedSessionId);
    final commandInputSessionId = displayedSessionId ?? activeSessionId;
    final shellChromeBackground = statusProfile == null
        ? activeTab == null
              ? _terminalColorsForProfile(
                  context,
                  defaultProfile,
                ).canvasBackground
              : _tabTerminalBackgroundColor(context, sessionState, activeTab)
        : _terminalColorsForProfile(context, statusProfile).canvasBackground;
    final instantReplaySession = _instantReplayWorkspaceSession;
    final instantReplayPane = instantReplaySession == null
        ? null
        : _paneForSession(sessionState, instantReplaySession.sourceSessionId);
    final instantReplayProfile = instantReplayPane == null
        ? null
        : _profileForPane(instantReplayPane, sessionState.profiles);
    final instantReplayConfig = instantReplayProfile?.toSessionConfig();
    final instantReplayColors = _terminalColorsForProfile(
      context,
      instantReplayProfile ?? statusProfile ?? defaultProfile,
    );

    KeyEventResult handleShellShortcut(KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final copyModeResult = _handleCopyModeKey(
        event,
        sessionController,
        activeSessionId,
      );
      if (copyModeResult != null) {
        return copyModeResult;
      }
      if (_isAutoComposerOpen) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _closeAutoComposer();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      final shortcut = _shortcutActionFor(event);
      if (shortcut == null) {
        return KeyEventResult.ignored;
      }

      if (shortcut.action == TerminalActionId.requestQuitConfirmation) {
        if (event is KeyRepeatEvent) {
          return KeyEventResult.handled;
        }
        unawaited(WindowBridge.requestQuitConfirmation());
        return KeyEventResult.handled;
      }

      if (_isCommandMenuOpen || _isDefaultsOpen || _isProfilesOpen) {
        return KeyEventResult.handled;
      }

      if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      }

      final shortcutProductionAdapter = _buildScopedProductionActionAdapter(
        requiredActionNames: const {
          'newTab',
          'closeTab',
          'splitRight',
          'splitDown',
          'closePane',
          'focusNextPane',
          'focusPreviousPane',
          'searchScrollback',
          'previousPrompt',
          'nextPrompt',
          'autocomplete',
          'copyMode',
          'paste',
          'pasteHistory',
          'instantReplay',
          'toggleCommandPalette',
          'toggleHotkeyWindow',
          'openDefaults',
        },
        callbacks: ShellActionProductionCallbacks(
          newTab: (_) {
            if (defaultProfile == null) {
              return const ShellActionBindingResult.skipped(
                'No default profile is available.',
              );
            }
            _createSession(
              sessionController,
              defaultProfile,
              returningToWorkspace: activeSessionId == null,
            );
            return const ShellActionBindingResult.completed();
          },
          closeTab: (_) {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Close tab requires an active session.',
              );
            }
            _closeSession(sessionController, sessionState, activeSessionId);
            return const ShellActionBindingResult.completed();
          },
          closePane: (_) {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Close pane requires an active session.',
              );
            }
            _closeSession(sessionController, sessionState, activeSessionId);
            return const ShellActionBindingResult.completed();
          },
          splitRight: (_) {
            if (defaultProfile == null || activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Split right requires a default profile and active session.',
              );
            }
            final conflictReason = _splitAxisConflictReason(
              sessionState,
              activeSessionId,
              TerminalSplitAxis.horizontal,
            );
            if (conflictReason != null) {
              return ShellActionBindingResult.skipped(conflictReason);
            }
            _splitActiveSession(
              sessionController,
              defaultProfile,
              TerminalSplitAxis.horizontal,
            );
            return const ShellActionBindingResult.completed();
          },
          splitDown: (_) {
            if (defaultProfile == null || activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Split down requires a default profile and active session.',
              );
            }
            final conflictReason = _splitAxisConflictReason(
              sessionState,
              activeSessionId,
              TerminalSplitAxis.vertical,
            );
            if (conflictReason != null) {
              return ShellActionBindingResult.skipped(conflictReason);
            }
            _splitActiveSession(
              sessionController,
              defaultProfile,
              TerminalSplitAxis.vertical,
            );
            return const ShellActionBindingResult.completed();
          },
          focusNextPane: (_) {
            if (activeSessionId == null || activeTab == null) {
              return const ShellActionBindingResult.skipped(
                'Focus next pane requires an active session.',
              );
            }
            final blockedReason = _zoomedPaneManagementUnavailableReason(
              activeTab,
            );
            if (blockedReason != null) {
              return ShellActionBindingResult.skipped(blockedReason);
            }
            if (!_focusRelativePane(
              sessionController,
              activeTab,
              activeSessionId,
              delta: 1,
            )) {
              return const ShellActionBindingResult.skipped(
                'No next pane is available.',
              );
            }
            return const ShellActionBindingResult.completed();
          },
          focusPreviousPane: (_) {
            if (activeSessionId == null || activeTab == null) {
              return const ShellActionBindingResult.skipped(
                'Focus previous pane requires an active session.',
              );
            }
            final blockedReason = _zoomedPaneManagementUnavailableReason(
              activeTab,
            );
            if (blockedReason != null) {
              return ShellActionBindingResult.skipped(blockedReason);
            }
            if (!_focusRelativePane(
              sessionController,
              activeTab,
              activeSessionId,
              delta: -1,
            )) {
              return const ShellActionBindingResult.skipped(
                'No previous pane is available.',
              );
            }
            return const ShellActionBindingResult.completed();
          },
          searchScrollback: (_) {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Search requires an active session.',
              );
            }
            _openSearch();
            return const ShellActionBindingResult.completed();
          },
          previousPrompt: (_) {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Previous prompt requires an active session.',
              );
            }
            _navigateShellPrompt(activeSessionId, direction: -1);
            return const ShellActionBindingResult.completed();
          },
          nextPrompt: (_) {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Next prompt requires an active session.',
              );
            }
            _navigateShellPrompt(activeSessionId, direction: 1);
            return const ShellActionBindingResult.completed();
          },
          autocomplete: (_) {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Autocomplete requires an active session.',
              );
            }
            _openAutocomplete();
            return const ShellActionBindingResult.completed();
          },
          copyMode: (_) {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Copy mode requires an active session.',
              );
            }
            final selectionController = _selectionControllers.putIfAbsent(
              activeSessionId,
              SelectionController.new,
            );
            _enterCopyMode(
              sessionController,
              activeSessionId,
              selectionController,
            );
            return const ShellActionBindingResult.completed();
          },
          paste: (_) async {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Paste requires an active session.',
              );
            }
            await _pasteToSession(activeSessionId);
            return const ShellActionBindingResult.completed();
          },
          pasteHistory: (_) async {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Paste history requires an active session.',
              );
            }
            await _openPasteHistory(sessionState);
            return const ShellActionBindingResult.completed();
          },
          instantReplay: (_) async {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Instant replay requires an active session.',
              );
            }
            await _openInstantReplay(sessionState);
            return const ShellActionBindingResult.completed();
          },
          toggleCommandPalette: (_) {
            unawaited(_openCommandMenu(sessionController, sessionState));
            return const ShellActionBindingResult.completed();
          },
          toggleHotkeyWindow: (_) async {
            final toggled = await _toggleHotkeyWindowWithFeedback();
            return toggled
                ? const ShellActionBindingResult.completed()
                : const ShellActionBindingResult.skipped(
                    'Hotkey window is unavailable.',
                  );
          },
          openDefaults: (_) async {
            await _openDefaultsAndAppearance(sessionController, sessionState);
            return const ShellActionBindingResult.completed();
          },
        ),
      );
      if (_dispatchProductionShortcutIfBound(
        adapter: shortcutProductionAdapter,
        action: shortcut.action,
      )) {
        return KeyEventResult.handled;
      }

      switch (shortcut.action) {
        case TerminalActionId.openLauncher:
          unawaited(_openCommandMenu(sessionController, sessionState));
          return KeyEventResult.handled;
        case TerminalActionId.openCommandMenu:
          unawaited(_openCommandMenu(sessionController, sessionState));
          return KeyEventResult.handled;
        case TerminalActionId.toolbelt:
          return KeyEventResult.handled;
        case TerminalActionId.newTab:
          if (defaultProfile == null) {
            return KeyEventResult.handled;
          }
          _createSession(
            sessionController,
            defaultProfile,
            returningToWorkspace: activeSessionId == null,
          );
          return KeyEventResult.handled;
        case TerminalActionId.splitRight:
          if (defaultProfile == null || activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.horizontal,
          );
          return KeyEventResult.handled;
        case TerminalActionId.splitDown:
          if (defaultProfile == null || activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.vertical,
          );
          return KeyEventResult.handled;
        case TerminalActionId.autocomplete:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _openAutocomplete();
          return KeyEventResult.handled;
        case TerminalActionId.copyMode:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          final selectionController = _selectionControllers.putIfAbsent(
            activeSessionId,
            SelectionController.new,
          );
          _enterCopyMode(
            sessionController,
            activeSessionId,
            selectionController,
          );
          return KeyEventResult.handled;
        case TerminalActionId.pasteHistory:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          unawaited(_openPasteHistory(sessionState));
          return KeyEventResult.handled;
        case TerminalActionId.instantReplay:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          unawaited(_openInstantReplay(sessionState));
          return KeyEventResult.handled;
        case TerminalActionId.previousPrompt:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _navigateShellPrompt(activeSessionId, direction: -1);
          return KeyEventResult.handled;
        case TerminalActionId.nextPrompt:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _navigateShellPrompt(activeSessionId, direction: 1);
          return KeyEventResult.handled;
        case TerminalActionId.closeActiveTab:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _closeSession(sessionController, sessionState, activeSessionId);
          return KeyEventResult.handled;
        case TerminalActionId.openDefaults:
          unawaited(
            _openDefaultsAndAppearance(sessionController, sessionState),
          );
          return KeyEventResult.handled;
        case TerminalActionId.requestQuitConfirmation:
          return KeyEventResult.handled;
        case TerminalActionId.copy:
          return KeyEventResult.ignored;
        case TerminalActionId.paste:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          unawaited(_pasteToSession(activeSessionId));
          return KeyEventResult.handled;
        case TerminalActionId.activateTab:
          final tabIndex = shortcut.tabIndex;
          if (tabIndex == null || tabIndex >= sessionState.tabs.length) {
            return KeyEventResult.handled;
          }
          final tab = sessionState.tabs[tabIndex];
          final tabActiveSessionId = tab.activeSessionId;
          if (tab.containsSession(activeSessionId ?? '')) {
            _focusSession(tabActiveSessionId);
            return KeyEventResult.handled;
          }
          _activateSession(sessionController, tabActiveSessionId);
          return KeyEventResult.handled;
        default:
          return KeyEventResult.handled;
      }
    }

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) => handleShellShortcut(event),
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: ColoredBox(
          color: palette.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ShellChromeBar(
                palette: palette,
                terminalBackgroundColor: shellChromeBackground,
                tabs: sessionState.tabs,
                activeSessionId: activeSessionId,
                tabHasNewOutput: _tabHasNewOutput,
                tabBackgroundColor: (tab) =>
                    _tabTerminalBackgroundColor(context, sessionState, tab),
                referenceDemoMode: referenceDemoMode,
                onNewTab: defaultProfile == null
                    ? null
                    : () {
                        _createSession(
                          sessionController,
                          defaultProfile,
                          returningToWorkspace: activeSessionId == null,
                        );
                      },
                onActivateSession: (sessionId) =>
                    _activateSession(sessionController, sessionId),
                onCloseSession: (sessionId) =>
                    _closeTab(sessionController, sessionState, sessionId),
                onReorderTab:
                    ({required int oldIndex, required int newIndex}) =>
                        sessionController.reorderTab(
                          oldIndex: oldIndex,
                          newIndex: newIndex,
                        ),
                onShowTabContextMenu: (tab, position) => _openTabContextMenu(
                  sessionController,
                  ref.read(sessionControllerProvider),
                  tab,
                  position,
                ),
                onShowCommandMenu: () =>
                    _openCommandMenu(sessionController, sessionState),
              ),
              if (sessionState.configurationWarnings.isNotEmpty)
                _ShellConfigurationWarningsBanner(
                  palette: palette,
                  warnings: sessionState.configurationWarnings,
                  onReviewProfiles: () => _openProfilesSheet(
                    sessionController,
                    ref.read(sessionControllerProvider),
                  ),
                  onDismiss: sessionController.dismissConfigurationWarnings,
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: animationsEnabled
                      ? const Duration(milliseconds: 160)
                      : Duration.zero,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: instantReplaySession != null
                      ? _InstantReplayWorkspace(
                          key: const Key('instant-replay-workspace'),
                          workspace: instantReplaySession,
                          palette: palette,
                          runtime: ref.read(terminalRuntimeControllerProvider),
                          terminalColors: instantReplayColors,
                          font:
                              instantReplayConfig?.display.font ??
                              const terminal.TerminalFontConfig(),
                          cursor:
                              instantReplayConfig?.display.cursor ??
                              const terminal.TerminalCursorConfig(),
                          onCopyVisible: _copyInstantReplayVisibleText,
                          onClear: _clearInstantReplayHistory,
                          onExit: _closeInstantReplayWorkspace,
                        )
                      : !sessionState.isReady ||
                            (activeSessionId != null &&
                                displayedSessionId == null)
                      ? _ShellStartupSurface(
                          key: const Key('shell-startup-state'),
                          palette: palette,
                        )
                      : activeSessionId == null || activeTab == null
                      ? _ShellEmptyState(
                          key: const Key('shell-empty-state'),
                          palette: palette,
                          title: _emptyStateTitle,
                          message: _emptyStateMessage,
                          defaultSummary: defaultSummary,
                          onNewTab: defaultProfile == null
                              ? null
                              : () {
                                  _createSession(
                                    sessionController,
                                    defaultProfile,
                                    returningToWorkspace: true,
                                  );
                                },
                        )
                      : KeyedSubtree(
                          key: ValueKey((displayedTab ?? activeTab).sessionId),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildTerminalWorkspace(
                                  context: context,
                                  sessionController: sessionController,
                                  sessionState: sessionState,
                                  activeTab: displayedTab ?? activeTab,
                                  activeSessionId:
                                      displayedSessionId ?? activeSessionId,
                                  palette: palette,
                                  onHostKeyEvent: handleShellShortcut,
                                ),
                              ),
                              if (_historyPeekVisibleForSession(
                                activeSessionId,
                              ))
                                Builder(
                                  builder: (context) {
                                    final width =
                                        shellHistoryPeekSidePaneWidthForAvailableWidth(
                                          MediaQuery.sizeOf(context).width,
                                        );
                                    if (width <= 0) {
                                      return const SizedBox.shrink();
                                    }
                                    return SizedBox(
                                      width: width,
                                      child: ShellHistoryPeekSheet(
                                        maxWidth: width,
                                        blocks: _historyPeekBlocksForSession(
                                          activeSessionId,
                                        ),
                                        onClose: _closeHistoryPeek,
                                      ),
                                    );
                                  },
                                ),
                              if (_isToolbeltOpen)
                                _ShellToolbelt(
                                  capturedOutputCount:
                                      _capturedOutputForSession(
                                        activeSessionId,
                                      ).length,
                                  pasteHistoryCount:
                                      _pasteHistoryEntries.length,
                                  commandHistoryCount: activeShellIntegration
                                      .recentCommands
                                      .length,
                                  recentDirectoryCount: activeShellIntegration
                                      .recentDirectories
                                      .length,
                                  promptMarkCount:
                                      _effectivePromptMarksForSession(
                                        activeSessionId,
                                        sessionState: sessionState,
                                      ).length,
                                  tmuxControlModeActive: _tmuxControlModeActive(
                                    activeSessionId,
                                  ),
                                  coprocessActive: _coprocesses.containsKey(
                                    activeSessionId,
                                  ),
                                  annotationCount: _annotationsForSession(
                                    activeSessionId,
                                  ).length,
                                  completionDiagnosticsSnapshot:
                                      _completionDiagnosticsSnapshot,
                                  palette: palette,
                                  onClose: () {
                                    _closeToolbelt();
                                  },
                                  onOpenCapturedOutput: () =>
                                      _openToolbeltChild(
                                        () => _openCapturedOutput(
                                          activeSessionId,
                                        ),
                                      ),
                                  onOpenPasteHistory: () => _openToolbeltChild(
                                    () => _openPasteHistory(sessionState),
                                  ),
                                  onOpenShellIntegrationUtilities: () =>
                                      _openToolbeltChild(
                                        () => _openShellIntegrationUtilities(
                                          sessionState,
                                          activeSessionId,
                                        ),
                                      ),
                                  onOpenTmuxIntegration: () =>
                                      _openToolbeltChild(
                                        () => _openTmuxIntegration(
                                          activeSessionId,
                                        ),
                                      ),
                                  onOpenCoprocess: () => _openToolbeltChild(
                                    () => _openCoprocess(activeSessionId),
                                  ),
                                  onOpenAnnotations: () {
                                    final selectionController =
                                        _selectionControllers.putIfAbsent(
                                          activeSessionId,
                                          SelectionController.new,
                                        );
                                    _openToolbeltChild(
                                      () => _openAnnotations(
                                        sessionController,
                                        activeSessionId,
                                        selectionController,
                                      ),
                                    );
                                  },
                                  onOpenInstantReplay: () => _openToolbeltChild(
                                    () => _openInstantReplay(sessionState),
                                  ),
                                  onOpenPasswordManager: () =>
                                      _openToolbeltChild(
                                        () => _openPasswordManager(
                                          sessionController,
                                          activeSessionId,
                                        ),
                                      ),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
              if (commandInputSessionId != null &&
                  _commandInputVisibleForSession(commandInputSessionId))
                ShellCommandInputBar(
                  key: ValueKey('shell-command-input-$commandInputSessionId'),
                  controller: _commandInputControllerFor(commandInputSessionId),
                  focusNode: _commandInputFocusNodeFor(commandInputSessionId),
                  enabled: !_isSessionReadOnly(commandInputSessionId),
                  cwd: statusDirectory?.trim().isNotEmpty == true
                      ? statusDirectory!.trim()
                      : statusProfile?.cwd,
                  onSubmitted: (command) =>
                      _submitCommandInput(commandInputSessionId, command),
                ),
              if (statusPane != null)
                if (statusViewportController == null ||
                    displayedSessionId == null)
                  _ShellStatusBar(
                    key: const Key('shell-status-bar'),
                    palette: palette,
                    terminalBackgroundColor: shellChromeBackground,
                    directory: statusDirectory?.trim().isNotEmpty == true
                        ? statusDirectory!.trim()
                        : statusProfile?.cwd,
                    viewportLabel: statusViewportLabel,
                    modeItems: const <_ShellStatusModeItem>[],
                    encodingLabel: 'UTF-8',
                  )
                else
                  ListenableBuilder(
                    listenable: statusViewportController,
                    builder: (context, _) {
                      return _ShellStatusBar(
                        key: const Key('shell-status-bar'),
                        palette: palette,
                        terminalBackgroundColor: shellChromeBackground,
                        directory: statusDirectory?.trim().isNotEmpty == true
                            ? statusDirectory!.trim()
                            : statusProfile?.cwd,
                        viewportLabel: statusViewportLabel,
                        modeItems: _statusModeItemsFor(
                          displayedSessionId,
                          statusViewportController.frame.modes,
                        ),
                        encodingLabel: 'UTF-8',
                      );
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
