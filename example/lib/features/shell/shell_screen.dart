import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import '../../ui/app_ui.dart';
import '../profiles/profile_editor.dart';
import '../profiles/profile_models.dart';
import '../sessions/session_controller.dart';
import '../sessions/session_state.dart';
import '../terminal/clipboard_bridge.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart';
import 'defaults_appearance_dialog.dart';
import 'instant_replay_store.dart';
import 'paste_history_repository.dart';
import 'package:app/features/shell/shell_acceptance.dart';
import 'reference_demo.dart';
import 'window_bridge.dart';

enum _ShellCommandAction {
  newTab,
  splitRight,
  splitDown,
  copy,
  copyMode,
  paste,
  pasteHistory,
  instantReplay,
  search,
  globalSearch,
  autocomplete,
  hotkeyWindow,
  defaults,
  profiles,
}

enum _ShellShortcutAction {
  openLauncher,
  newTab,
  splitRight,
  splitDown,
  autocomplete,
  copyMode,
  pasteHistory,
  instantReplay,
  closeActiveTab,
  openDefaults,
  requestQuitConfirmation,
  activateTab,
}

class _ShellShortcut {
  const _ShellShortcut(this.action, {this.tabIndex});

  final _ShellShortcutAction action;
  final int? tabIndex;
}

final shellAnimationsEnabledProvider = Provider<bool>((ref) => true);

final pasteHistoryRepositoryProvider = Provider<PasteHistoryRepository>((ref) {
  return PasteHistoryRepository();
});

final instantReplayStoreProvider = Provider<InstantReplayStore>((ref) {
  return InstantReplayStore();
});

typedef ShellNotificationSender =
    Future<void> Function({
      required String title,
      String? body,
      String? identifier,
    });

final shellNotificationSenderProvider = Provider<ShellNotificationSender>((
  ref,
) {
  return WindowBridge.showNotification;
});

sealed class _ProfilesSheetResult {
  const _ProfilesSheetResult();
}

final class _OpenProfileResult extends _ProfilesSheetResult {
  const _OpenProfileResult(this.profile);

  final TerminalProfile profile;
}

final class _EditProfileResult extends _ProfilesSheetResult {
  const _EditProfileResult(this.profile);

  final TerminalProfile profile;
}

sealed class _PasteHistorySheetResult {
  const _PasteHistorySheetResult();
}

final class _PasteHistoryPickResult extends _PasteHistorySheetResult {
  const _PasteHistoryPickResult(this.entry);

  final PasteHistoryEntry entry;
}

sealed class _InstantReplaySheetResult {
  const _InstantReplaySheetResult();
}

final class _InstantReplayCopyResult extends _InstantReplaySheetResult {
  const _InstantReplayCopyResult(this.text);

  final String text;
}

class _SearchableSession {
  const _SearchableSession({required this.sessionId, required this.title});

  final String sessionId;
  final String title;
}

class _GlobalSearchResult {
  const _GlobalSearchResult({required this.session, required this.match});

  final _SearchableSession session;
  final TerminalSearchMatch match;
}

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  static const _workspaceCueDuration = Duration(milliseconds: 1400);
  static const _viewportResizeDebounce = Duration(milliseconds: 240);
  static const _terminalViewportPadding = EdgeInsets.fromLTRB(16, 10, 18, 14);
  static const _pasteHistoryLimit = 30;

  final Map<String, SelectionController> _selectionControllers = {};
  final Map<String, FocusNode> _terminalFocusNodes = {};
  final Map<String, Size> _scheduledViewportSizes = {};
  final Map<String, Size> _committedViewportSizes = {};
  final Map<String, DateTime> _lastActivityNotificationAt = {};
  final Map<String, String?> _lastActivityFramePreviews = {};
  final Set<String> _sessionsSeenForActivityNotifications = {};
  StreamSubscription<terminal.TerminalSessionEvent>? _terminalEventSubscription;
  Timer? _workspaceCueTimer;
  Timer? _viewportResizeTimer;
  bool _isCommandMenuOpen = false;
  bool _isDefaultsOpen = false;
  bool _isProfilesOpen = false;
  bool _isSearchOpen = false;
  bool _isAutocompleteOpen = false;
  bool _isCopyModeOpen = false;
  bool _activeTerminalHasFocus = false;
  bool _recentlyClosedLastSession = false;
  bool _showWorkspaceCue = false;
  bool _showReturningCueOnNextFocus = false;
  int _lastObservedTabCount = 0;
  String _searchQuery = '';
  List<TerminalSearchMatch> _searchMatches = const [];
  int _activeSearchIndex = 0;
  String _autocompletePrefix = '';
  List<String> _autocompleteSuggestions = const [];
  int _activeAutocompleteIndex = 0;
  List<PasteHistoryEntry> _pasteHistoryEntries = const [];
  bool _pasteHistoryPersistToDisk = false;
  bool _pasteHistoryLoaded = false;
  int? _copyModeAnchorRow;
  int? _copyModeAnchorCol;
  int? _copyModeExtentRow;
  int? _copyModeExtentCol;

  @override
  void initState() {
    super.initState();
    _terminalEventSubscription = ref
        .read(terminalRuntimeControllerProvider)
        .events
        .listen(_handleTerminalSessionEvent);
    Future.microtask(_loadPasteHistory);
  }

  @override
  void dispose() {
    _terminalEventSubscription?.cancel();
    _workspaceCueTimer?.cancel();
    _viewportResizeTimer?.cancel();
    for (final focusNode in _terminalFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _handleTerminalSessionEvent(terminal.TerminalSessionEvent event) {
    switch (event) {
      case terminal.TerminalSessionFrameEvent(:final sessionId, :final frame):
        ref.read(instantReplayStoreProvider).record(sessionId, frame);
        _notifyInactiveActivity(sessionId, frame);
      case terminal.TerminalSessionExitEvent():
        _notifySessionExit(event.sessionId, event.exitCode);
      case terminal.TerminalSessionBellEvent():
        _notifyBell(event.sessionId);
      case terminal.TerminalSessionShellHookEvent():
        _notifyShellHook(event);
    }
  }

  void _notifyInactiveActivity(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    final preview = _framePreview(frame);
    final hasSeenSession = !_sessionsSeenForActivityNotifications.add(
      sessionId,
    );
    final previousPreview = _lastActivityFramePreviews[sessionId];
    _lastActivityFramePreviews[sessionId] = preview;
    if (hasSeenSession &&
        previousPreview != preview &&
        _notificationSessionIsInactive(sessionId) &&
        preview != null &&
        _activityNotificationAllowed(sessionId)) {
      _sendShellNotification(
        title: 'Activity in ${_sessionTitleForNotification(sessionId)}',
        body: preview,
        identifier: 'flutterm.activity.$sessionId',
      );
    }
  }

  void _notifySessionExit(String sessionId, int? exitCode) {
    _sendShellNotification(
      title: 'Session ended',
      body:
          '${_sessionTitleForNotification(sessionId)} exited${exitCode == null ? '' : ' with code $exitCode'}.',
      identifier:
          'flutterm.exit.$sessionId.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  void _notifyBell(String sessionId) {
    _sendShellNotification(
      title: 'Bell in ${_sessionTitleForNotification(sessionId)}',
      body: 'The terminal requested attention.',
      identifier: 'flutterm.bell.$sessionId',
    );
  }

  void _notifyShellHook(terminal.TerminalSessionShellHookEvent event) {
    if (event.hook != 'command_finished') {
      return;
    }
    final command = event.command;
    final exitCode = event.exitCode;
    _sendShellNotification(
      title: 'Command finished',
      body: [
        if (command != null && command.trim().isNotEmpty) command.trim(),
        if (exitCode != null) 'Exit code $exitCode',
      ].join('\n'),
      identifier:
          'flutterm.command.${event.sessionId}.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  bool _notificationSessionIsInactive(String sessionId) {
    return ref.read(sessionControllerProvider).activeSessionId != sessionId;
  }

  bool _activityNotificationAllowed(String sessionId) {
    final now = DateTime.now();
    final lastNotification = _lastActivityNotificationAt[sessionId];
    if (lastNotification != null &&
        now.difference(lastNotification) < const Duration(seconds: 30)) {
      return false;
    }
    _lastActivityNotificationAt[sessionId] = now;
    return true;
  }

  String? _framePreview(terminal.TerminalFrameDiff frame) {
    for (final row in frame.rows) {
      final text = row.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  String _sessionTitleForNotification(String sessionId) {
    final state = ref.read(sessionControllerProvider);
    for (final tab in state.tabs) {
      final pane = tab.paneFor(sessionId);
      if (pane != null) {
        return pane.title;
      }
    }
    return 'Session $sessionId';
  }

  void _sendShellNotification({
    required String title,
    String? body,
    required String identifier,
  }) {
    unawaited(
      ref.read(shellNotificationSenderProvider)(
        title: title,
        body: body,
        identifier: identifier,
      ),
    );
  }

  String get _visibleOverlay {
    if (_isDefaultsOpen) {
      return 'defaults';
    }
    if (_isProfilesOpen) {
      return 'profiles';
    }
    if (_isCommandMenuOpen) {
      return 'commandMenu';
    }
    return 'none';
  }

  void _publishAcceptanceSnapshot([SessionState? state]) {
    final SessionState snapshotState =
        state ?? ref.read(sessionControllerProvider);
    final activeSessionId = snapshotState.activeSessionId;
    final terminalFrame = activeSessionId == null
        ? null
        : ref
              .read(sessionControllerProvider.notifier)
              .viewportFor(activeSessionId)
              .frame;
    final terminalRows = terminalFrame?.rows ?? const [];
    String? terminalPreview;
    for (final row in terminalRows) {
      final text = row.text.trim();
      if (text.isNotEmpty) {
        terminalPreview = text;
        break;
      }
    }
    shellAcceptanceProbe.update(
      ShellAcceptanceSnapshot(
        commandMenuOpen: _isCommandMenuOpen,
        defaultsOpen: _isDefaultsOpen,
        profilesOpen: _isProfilesOpen,
        visibleOverlay: _visibleOverlay,
        terminalHasVisibleContent: terminalPreview != null,
        terminalPreview: terminalPreview,
        activeTabCount: snapshotState.tabs.length,
        activeSessionId: activeSessionId,
        themeMode: snapshotState.themeMode.name,
        snapshotVersion: shellAcceptanceProbe.current.snapshotVersion,
        terminalFrameSnapshot: terminalFrame == null
            ? null
            : <String, Object?>{
                'viewportRows': terminalFrame.viewportRows,
                'viewportCols': terminalFrame.viewportCols,
                'scrollbackOffset': terminalFrame.scrollbackOffset,
                'scrollbackMaxOffset': terminalFrame.scrollbackMaxOffset,
                'rows': terminalFrame.rows
                    .map(
                      (row) => <String, Object?>{
                        'index': row.index,
                        'text': row.text,
                        'wrapped': row.wrapped,
                      },
                    )
                    .toList(),
              },
      ),
    );
  }

  bool get _usesMetaShortcuts {
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  String _launcherShortcutLabel() {
    return _usesMetaShortcuts ? '⌘⇧P' : 'Ctrl+Shift+P';
  }

  String _newTabShortcutLabel() {
    return _usesMetaShortcuts ? '⌘T' : 'Ctrl+T';
  }

  String _splitRightShortcutLabel() {
    return _usesMetaShortcuts ? '⌘D' : 'Ctrl+D';
  }

  String _splitDownShortcutLabel() {
    return _usesMetaShortcuts ? '⌘⇧D' : 'Ctrl+Shift+D';
  }

  String _hotkeyWindowShortcutLabel() {
    return _usesMetaShortcuts ? '⌥⌘Space' : 'Alt+Ctrl+Space';
  }

  String _autocompleteShortcutLabel() {
    return _usesMetaShortcuts ? '⌘;' : 'Ctrl+;';
  }

  String _sessionCopyShortcutLabel() {
    return _usesMetaShortcuts ? '⌘C' : 'Ctrl+C';
  }

  String _copyModeShortcutLabel() {
    return _usesMetaShortcuts ? '⌘⇧C' : 'Ctrl+Shift+C';
  }

  String _sessionPasteShortcutLabel() {
    return _usesMetaShortcuts ? '⌘V' : 'Ctrl+V';
  }

  String _pasteHistoryShortcutLabel() {
    return _usesMetaShortcuts ? '⌘⇧V' : 'Ctrl+Shift+V';
  }

  String _instantReplayShortcutLabel() {
    return _usesMetaShortcuts ? '⌘⇧R' : 'Ctrl+Shift+R';
  }

  String get _workspaceCueTitle => 'Back in shell';

  _ShellShortcut? _shortcutActionFor(KeyEvent event) {
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final usesMetaShortcuts =
        _usesMetaShortcuts || ref.read(referenceDemoModeProvider);
    final usesAppModifier = usesMetaShortcuts
        ? isMetaPressed && !isControlPressed
        : isControlPressed && !isMetaPressed;

    if (usesAppModifier && !isShiftPressed) {
      final platformAction = switch (event.logicalKey) {
        LogicalKeyboardKey.keyD => _ShellShortcutAction.splitRight,
        LogicalKeyboardKey.semicolon => _ShellShortcutAction.autocomplete,
        LogicalKeyboardKey.keyQ => _ShellShortcutAction.requestQuitConfirmation,
        LogicalKeyboardKey.keyW => _ShellShortcutAction.closeActiveTab,
        LogicalKeyboardKey.comma => _ShellShortcutAction.openDefaults,
        _ => null,
      };
      if (platformAction != null) {
        return _ShellShortcut(platformAction);
      }
      final tabIndex = _tabShortcutIndexFor(event.logicalKey);
      if (tabIndex != null) {
        return _ShellShortcut(
          _ShellShortcutAction.activateTab,
          tabIndex: tabIndex,
        );
      }
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyP) {
      return const _ShellShortcut(_ShellShortcutAction.openLauncher);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyD) {
      return const _ShellShortcut(_ShellShortcutAction.splitDown);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      return const _ShellShortcut(_ShellShortcutAction.copyMode);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      return const _ShellShortcut(_ShellShortcutAction.pasteHistory);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyR) {
      return const _ShellShortcut(_ShellShortcutAction.instantReplay);
    }

    if (usesAppModifier && event.logicalKey == LogicalKeyboardKey.keyT) {
      return const _ShellShortcut(_ShellShortcutAction.newTab);
    }

    return null;
  }

  int? _tabShortcutIndexFor(LogicalKeyboardKey key) {
    return switch (key) {
      LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => 0,
      LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => 1,
      LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => 2,
      LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => 3,
      LogicalKeyboardKey.digit5 || LogicalKeyboardKey.numpad5 => 4,
      LogicalKeyboardKey.digit6 || LogicalKeyboardKey.numpad6 => 5,
      LogicalKeyboardKey.digit7 || LogicalKeyboardKey.numpad7 => 6,
      LogicalKeyboardKey.digit8 || LogicalKeyboardKey.numpad8 => 7,
      LogicalKeyboardKey.digit9 || LogicalKeyboardKey.numpad9 => 8,
      _ => null,
    };
  }

  Size _terminalContentSizeFor(BoxConstraints constraints) {
    return Size(
      (constraints.maxWidth - _terminalViewportPadding.horizontal)
          .clamp(1.0, double.infinity)
          .toDouble(),
      (constraints.maxHeight - _terminalViewportPadding.vertical)
          .clamp(1.0, double.infinity)
          .toDouble(),
    );
  }

  void _commitViewportResize(
    SessionController sessionController,
    String sessionId,
    Size viewportSize,
    double devicePixelRatio,
  ) {
    if (!mounted || !_sessionExists(sessionId)) {
      return;
    }
    sessionController.resizeSession(sessionId, viewportSize, devicePixelRatio);
    _committedViewportSizes[sessionId] = viewportSize;
  }

  bool _sessionExists(String sessionId) {
    return ref
        .read(sessionControllerProvider)
        .tabs
        .any((tab) => tab.containsSession(sessionId));
  }

  void _scheduleViewportResize(
    SessionController sessionController,
    String sessionId,
    Size viewportSize,
    double devicePixelRatio, {
    required bool immediate,
  }) {
    _scheduledViewportSizes[sessionId] = viewportSize;
    _viewportResizeTimer?.cancel();
    _viewportResizeTimer = null;
    if (immediate) {
      _commitViewportResize(
        sessionController,
        sessionId,
        viewportSize,
        devicePixelRatio,
      );
      return;
    }

    _viewportResizeTimer = Timer(_viewportResizeDebounce, () {
      _commitViewportResize(
        sessionController,
        sessionId,
        viewportSize,
        devicePixelRatio,
      );
    });
  }

  String get _emptyStateTitle {
    return _recentlyClosedLastSession
        ? 'Shell workspace is idle'
        : 'Start a shell workspace';
  }

  String get _emptyStateMessage {
    return _recentlyClosedLastSession
        ? 'The last session has closed. Open a new tab to keep working in the shell workspace.'
        : 'Open a new tab to start working in the shell workspace.';
  }

  FocusNode _focusNodeFor(String sessionId) {
    return _terminalFocusNodes.putIfAbsent(sessionId, () {
      final focusNode = FocusNode(debugLabel: 'shell-terminal-$sessionId');
      focusNode.addListener(
        () => _handleTerminalFocusChanged(sessionId, focusNode),
      );
      return focusNode;
    });
  }

  void _handleTerminalFocusChanged(String sessionId, FocusNode focusNode) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId != sessionId) {
      return;
    }

    final hasFocus = focusNode.hasFocus;
    final shouldShowCue = hasFocus && _showReturningCueOnNextFocus;
    if (_activeTerminalHasFocus == hasFocus &&
        _showWorkspaceCue == shouldShowCue) {
      return;
    }

    _workspaceCueTimer?.cancel();
    _workspaceCueTimer = null;
    setState(() {
      _activeTerminalHasFocus = hasFocus;
      if (hasFocus) {
        _showWorkspaceCue = shouldShowCue;
        _showReturningCueOnNextFocus = false;
      } else {
        _showWorkspaceCue = false;
      }
    });

    if (shouldShowCue) {
      _workspaceCueTimer = Timer(_workspaceCueDuration, () {
        if (!mounted || !_showWorkspaceCue) {
          return;
        }
        setState(() {
          _showWorkspaceCue = false;
        });
      });
    }
  }

  void _scheduleReturningCue() {
    _showReturningCueOnNextFocus = true;
    _recentlyClosedLastSession = false;
  }

  void _syncPresentationState(SessionState sessionState) {
    final currentTabCount = sessionState.tabs.length;
    if (currentTabCount == 0 && _lastObservedTabCount > 0) {
      _recentlyClosedLastSession = true;
      _activeTerminalHasFocus = false;
      _showWorkspaceCue = false;
    } else if (currentTabCount > 0 && _lastObservedTabCount == 0) {
      _recentlyClosedLastSession = false;
    }
    if (sessionState.activeSessionId == null) {
      _activeTerminalHasFocus = false;
      _showWorkspaceCue = false;
      _isSearchOpen = false;
      _isAutocompleteOpen = false;
      _isCopyModeOpen = false;
      _searchQuery = '';
      _searchMatches = const [];
      _activeSearchIndex = 0;
      _autocompletePrefix = '';
      _autocompleteSuggestions = const [];
      _activeAutocompleteIndex = 0;
      _copyModeAnchorRow = null;
      _copyModeAnchorCol = null;
      _copyModeExtentRow = null;
      _copyModeExtentCol = null;
      _workspaceCueTimer?.cancel();
      _workspaceCueTimer = null;
    }
    _lastObservedTabCount = currentTabCount;
  }

  void _createSession(
    SessionController sessionController,
    TerminalProfile profile, {
    required bool returningToWorkspace,
  }) {
    if (returningToWorkspace) {
      _scheduleReturningCue();
    }
    sessionController.createSession(profile);
    _focusSession(ref.read(sessionControllerProvider).activeSessionId);
  }

  void _activateSession(SessionController sessionController, String sessionId) {
    _scheduleReturningCue();
    sessionController.activateSession(sessionId);
    _focusSession(sessionId);
  }

  void _splitActiveSession(
    SessionController sessionController,
    TerminalProfile profile,
    TerminalSplitAxis axis,
  ) {
    sessionController.splitActiveSession(profile, axis);
    _focusSession(ref.read(sessionControllerProvider).activeSessionId);
  }

  void _closeSession(
    SessionController sessionController,
    SessionState sessionState,
    String sessionId,
  ) {
    final closesLastSession =
        sessionState.tabs.length == 1 &&
        sessionState.tabs.single.effectivePanes.length == 1;
    if (closesLastSession) {
      _recentlyClosedLastSession = true;
    }
    _scheduledViewportSizes.remove(sessionId);
    _committedViewportSizes.remove(sessionId);
    sessionController.closeSession(sessionId);
    final nextActiveSessionId = ref
        .read(sessionControllerProvider)
        .activeSessionId;
    if (nextActiveSessionId != null) {
      _scheduleReturningCue();
      _focusSession(nextActiveSessionId);
    }
  }

  void _closeTab(
    SessionController sessionController,
    SessionState sessionState,
    String tabSessionId,
  ) {
    final closesLastTab = sessionState.tabs.length == 1;
    final closingTab = sessionState.tabs.firstWhere(
      (tab) => tab.sessionId == tabSessionId,
      orElse: () => sessionState.tabs.first,
    );
    if (closesLastTab) {
      _recentlyClosedLastSession = true;
    }
    for (final pane in closingTab.effectivePanes) {
      _scheduledViewportSizes.remove(pane.sessionId);
      _committedViewportSizes.remove(pane.sessionId);
    }
    sessionController.closeTab(tabSessionId);
    final nextActiveSessionId = ref
        .read(sessionControllerProvider)
        .activeSessionId;
    if (nextActiveSessionId != null) {
      _scheduleReturningCue();
      _focusSession(nextActiveSessionId);
    }
  }

  void _focusSession(String? sessionId) {
    if (sessionId == null) {
      return;
    }
    final focusNode = _focusNodeFor(sessionId);
    if (!focusNode.canRequestFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focusNode.canRequestFocus) {
        return;
      }
      focusNode.requestFocus();
    });
  }

  void _restoreSessionFocus({
    required String? activeSessionIdBeforeOpen,
    required String? activeSessionIdAfterClose,
  }) {
    if (activeSessionIdBeforeOpen == null ||
        activeSessionIdAfterClose != activeSessionIdBeforeOpen) {
      return;
    }
    _scheduleReturningCue();
    _focusSession(activeSessionIdBeforeOpen);
  }

  TerminalProfile? _profileForId(
    List<TerminalProfile> profiles,
    String? profileId,
  ) {
    if (profiles.isEmpty || profileId == null) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == profileId) {
        return profile;
      }
    }
    return null;
  }

  TerminalProfile? _effectiveDefaultProfileFor(
    List<TerminalProfile> profiles,
    String? effectiveDefaultProfileId,
  ) {
    return _profileForId(profiles, effectiveDefaultProfileId) ??
        (profiles.isEmpty ? null : profiles.first);
  }

  TerminalProfile? _profileForPane(
    TerminalPane pane,
    List<TerminalProfile> profiles,
  ) {
    return pane.profileSnapshot ?? _profileForId(profiles, pane.profileId);
  }

  terminal.TerminalViewportColors _terminalColorsForProfile(
    BuildContext context,
    TerminalProfile? profile,
  ) {
    return resolveTerminalColors(
      context,
      profileAppearance: profile?.appearance,
    ).viewport;
  }

  String _defaultSummary(
    List<TerminalProfile> profiles,
    String? configuredDefaultProfileId,
    String? effectiveDefaultProfileId,
  ) {
    final effectiveProfile = _effectiveDefaultProfileFor(
      profiles,
      effectiveDefaultProfileId,
    );
    if (configuredDefaultProfileId == null) {
      return 'Current new-tab profile • ${effectiveProfile?.name ?? 'No profile available'}';
    }
    final configuredProfile = _profileForId(
      profiles,
      configuredDefaultProfileId,
    );
    return 'Configured default • ${configuredProfile?.name ?? effectiveProfile?.name ?? 'No profile available'}';
  }

  Future<void> _copySelection(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) async {
    final text = _selectionTextForSession(
      sessionController,
      sessionId,
      selectionController,
    );
    if (text.isEmpty) {
      return;
    }
    await ClipboardBridge.copy(text);
    await _recordPasteHistory(text, PasteHistoryKind.copy);
  }

  Future<void> _loadPasteHistory() async {
    final document = await ref.read(pasteHistoryRepositoryProvider).load();
    if (!mounted) {
      return;
    }
    final loadedEntries = document?.entries ?? const <PasteHistoryEntry>[];
    setState(() {
      _pasteHistoryLoaded = true;
      _pasteHistoryPersistToDisk = document != null;
      _pasteHistoryEntries = _mergePasteHistoryEntries(
        _pasteHistoryEntries,
        loadedEntries,
      );
    });
  }

  Future<void> _recordPasteHistory(String text, PasteHistoryKind kind) async {
    final normalizedText = text.trimRight();
    if (normalizedText.trim().isEmpty) {
      return;
    }
    final nextEntry = PasteHistoryEntry(
      text: normalizedText,
      kind: kind,
      createdAt: DateTime.now(),
    );
    final nextEntries = <PasteHistoryEntry>[
      nextEntry,
      for (final entry in _pasteHistoryEntries)
        if (entry.text != normalizedText) entry,
    ].take(_pasteHistoryLimit).toList();

    if (mounted) {
      setState(() {
        _pasteHistoryEntries = nextEntries;
        _pasteHistoryLoaded = true;
      });
    } else {
      _pasteHistoryEntries = nextEntries;
    }

    if (_pasteHistoryPersistToDisk) {
      await ref
          .read(pasteHistoryRepositoryProvider)
          .save(PasteHistoryDocument(entries: nextEntries));
    }
  }

  List<PasteHistoryEntry> _mergePasteHistoryEntries(
    List<PasteHistoryEntry> leading,
    List<PasteHistoryEntry> trailing,
  ) {
    final seenTexts = <String>{};
    return <PasteHistoryEntry>[
      for (final entry in [...leading, ...trailing])
        if (entry.text.trim().isNotEmpty && seenTexts.add(entry.text)) entry,
    ].take(_pasteHistoryLimit).toList();
  }

  Future<void> _setPasteHistoryPersistence(bool enabled) async {
    setState(() {
      _pasteHistoryPersistToDisk = enabled;
      _pasteHistoryLoaded = true;
    });
    final repository = ref.read(pasteHistoryRepositoryProvider);
    if (enabled) {
      await repository.save(
        PasteHistoryDocument(entries: _pasteHistoryEntries),
      );
    } else {
      await repository.clearDiskHistory();
    }
  }

  Future<void> _clearPasteHistory() async {
    setState(() {
      _pasteHistoryEntries = const [];
      _pasteHistoryLoaded = true;
    });
    if (_pasteHistoryPersistToDisk) {
      await ref
          .read(pasteHistoryRepositoryProvider)
          .save(const PasteHistoryDocument());
    }
  }

  String _selectionTextForSession(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) {
    final frame = sessionController.viewportFor(sessionId).frame;
    final selection = selectionController.selection;
    if (selection == null) {
      return '';
    }
    if (ref.read(referenceDemoModeProvider)) {
      return selectionController.textForFrame(frame);
    }
    final text = ref
        .read(terminalRuntimeControllerProvider)
        .selectionText(
          sessionId,
          selection,
          block: selectionController.isBlockSelection,
        );
    return text ?? selectionController.textForFrame(frame);
  }

  void _enterCopyMode(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) {
    final frame = sessionController.viewportFor(sessionId).frame;
    if (frame.viewportRows <= 0 || frame.viewportCols <= 0) {
      return;
    }

    final row = (frame.viewportStartRow + frame.cursor.row)
        .clamp(
          frame.viewportStartRow,
          frame.viewportStartRow + frame.viewportRows - 1,
        )
        .toInt();
    final cursorCol = frame.cursor.col.clamp(0, frame.viewportCols).toInt();
    final anchorCol = cursorCol >= frame.viewportCols
        ? (frame.viewportCols - 1).clamp(0, frame.viewportCols).toInt()
        : cursorCol;
    final extentCol = (anchorCol + 1).clamp(0, frame.viewportCols).toInt();

    setState(() {
      _isCopyModeOpen = true;
      _isSearchOpen = false;
      _isAutocompleteOpen = false;
      _copyModeAnchorRow = row;
      _copyModeAnchorCol = anchorCol;
      _copyModeExtentRow = row;
      _copyModeExtentCol = extentCol;
    });
    selectionController.setSelection(
      terminal.TerminalSelection(
        startRow: row,
        startCol: anchorCol,
        endRow: row,
        endCol: extentCol,
      ),
    );
    _focusSession(sessionId);
  }

  KeyEventResult? _handleCopyModeKey(
    KeyEvent event,
    SessionController sessionController,
    String? activeSessionId,
  ) {
    if (!_isCopyModeOpen) {
      return null;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (activeSessionId == null) {
      _closeCopyMode(null);
      return KeyEventResult.handled;
    }
    final selectionController = _selectionControllers[activeSessionId];
    if (selectionController == null) {
      _closeCopyMode(null);
      return KeyEventResult.handled;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _closeCopyMode(selectionController);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        unawaited(
          _copySelection(
            sessionController,
            activeSessionId,
            selectionController,
          ),
        );
        _closeCopyMode(selectionController);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _moveCopyModeSelection(
          sessionController,
          activeSessionId,
          selectionController,
          columnDelta: -1,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _moveCopyModeSelection(
          sessionController,
          activeSessionId,
          selectionController,
          columnDelta: 1,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveCopyModeSelection(
          sessionController,
          activeSessionId,
          selectionController,
          rowDelta: -1,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveCopyModeSelection(
          sessionController,
          activeSessionId,
          selectionController,
          rowDelta: 1,
        );
        return KeyEventResult.handled;
      default:
        return KeyEventResult.handled;
    }
  }

  void _moveCopyModeSelection(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController, {
    int rowDelta = 0,
    int columnDelta = 0,
  }) {
    final anchorRow = _copyModeAnchorRow;
    final anchorCol = _copyModeAnchorCol;
    final extentRow = _copyModeExtentRow;
    final extentCol = _copyModeExtentCol;
    if (anchorRow == null ||
        anchorCol == null ||
        extentRow == null ||
        extentCol == null) {
      return;
    }
    final frame = sessionController.viewportFor(sessionId).frame;
    final minRow = frame.viewportStartRow;
    final maxRow = frame.viewportStartRow + frame.viewportRows - 1;
    final nextRow = (extentRow + rowDelta).clamp(minRow, maxRow).toInt();
    final nextCol = (extentCol + columnDelta)
        .clamp(0, frame.viewportCols)
        .toInt();

    setState(() {
      _copyModeExtentRow = nextRow;
      _copyModeExtentCol = nextCol;
    });
    selectionController.setSelection(
      terminal.TerminalSelection(
        startRow: anchorRow,
        startCol: anchorCol,
        endRow: nextRow,
        endCol: nextCol,
      ),
    );
  }

  void _closeCopyMode(SelectionController? selectionController) {
    setState(() {
      _isCopyModeOpen = false;
      _copyModeAnchorRow = null;
      _copyModeAnchorCol = null;
      _copyModeExtentRow = null;
      _copyModeExtentCol = null;
    });
    selectionController?.clear();
    _focusSession(ref.read(sessionControllerProvider).activeSessionId);
  }

  Future<void> _pasteToSession(String sessionId) async {
    final text = await ClipboardBridge.paste();
    if (text.isEmpty) {
      return;
    }
    await _pasteTextToSession(sessionId, text);
    await _recordPasteHistory(text, PasteHistoryKind.paste);
  }

  Future<void> _pasteTextToSession(String sessionId, String text) async {
    final sessionState = ref.read(sessionControllerProvider);
    final sessionController = ref.read(sessionControllerProvider.notifier);
    TerminalPane? activePane;
    for (final tab in sessionState.tabs) {
      final pane = tab.paneFor(sessionId);
      if (pane != null) {
        activePane = pane;
        break;
      }
    }
    final profile = activePane == null
        ? null
        : _profileForPane(activePane, sessionState.profiles);
    final terminalConfig = profile?.toSessionConfig();
    final frame = sessionController.viewportFor(sessionId).frame;
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(
          sessionId,
          TerminalInputController.clipboardPasteBytesFor(
            emulation:
                terminalConfig?.emulation ??
                terminal.TerminalEmulation.xterm256,
            modes: frame.modes,
            text: text,
          ),
        );
  }

  Future<void> _openPasteHistory(SessionState sessionState) async {
    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    if (activeSessionIdBeforeOpen == null) {
      return;
    }
    if (!_pasteHistoryLoaded) {
      await _loadPasteHistory();
    }
    if (!mounted) {
      return;
    }

    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<_PasteHistorySheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _PasteHistorySheet(
          entries: _pasteHistoryEntries,
          persistToDisk: _pasteHistoryPersistToDisk,
          onPersistChanged: (enabled) =>
              unawaited(_setPasteHistoryPersistence(enabled)),
          onClear: () => unawaited(_clearPasteHistory()),
        );
      },
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case _PasteHistoryPickResult(:final entry):
        final currentActiveSessionId = ref
            .read(sessionControllerProvider)
            .activeSessionId;
        if (currentActiveSessionId == null) {
          return;
        }
        await _pasteTextToSession(currentActiveSessionId, entry.text);
        await _recordPasteHistory(entry.text, PasteHistoryKind.paste);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentActiveSessionId,
        );
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
    }
  }

  void _seedInstantReplayFrame(String sessionId) {
    final sessionController = ref.read(sessionControllerProvider.notifier);
    ref
        .read(instantReplayStoreProvider)
        .record(sessionId, sessionController.viewportFor(sessionId).frame);
  }

  Future<void> _openInstantReplay(SessionState sessionState) async {
    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    if (activeSessionIdBeforeOpen == null) {
      return;
    }
    _seedInstantReplayFrame(activeSessionIdBeforeOpen);
    final store = ref.read(instantReplayStoreProvider);
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<_InstantReplaySheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _InstantReplaySheet(
          frames: store.framesFor(activeSessionIdBeforeOpen),
          onClear: () => store.clear(activeSessionIdBeforeOpen),
        );
      },
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case _InstantReplayCopyResult(:final text):
        if (text.trim().isNotEmpty) {
          await ClipboardBridge.copy(text);
          await _recordPasteHistory(text, PasteHistoryKind.copy);
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
    }
  }

  void _openSearch() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    setState(() {
      _isSearchOpen = true;
      _searchQuery = '';
      _searchMatches = const [];
      _activeSearchIndex = 0;
    });
  }

  void _searchScrollback(String query) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final matches = ref
        .read(terminalRuntimeControllerProvider)
        .searchText(activeSessionId, query);
    setState(() {
      _searchQuery = query;
      _searchMatches = matches;
      _activeSearchIndex = 0;
    });
    if (matches.isNotEmpty) {
      ref
          .read(terminalRuntimeControllerProvider)
          .scrollViewportTo(activeSessionId, matches.first.scrollbackOffset);
    }
  }

  void _moveSearchMatch(int delta) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null || _searchMatches.isEmpty) {
      return;
    }
    final nextIndex = (_activeSearchIndex + delta) % _searchMatches.length;
    final normalizedIndex = nextIndex < 0
        ? nextIndex + _searchMatches.length
        : nextIndex;
    setState(() {
      _activeSearchIndex = normalizedIndex;
    });
    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(
          activeSessionId,
          _searchMatches[normalizedIndex].scrollbackOffset,
        );
  }

  void _closeSearch() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    setState(() {
      _isSearchOpen = false;
      _searchQuery = '';
      _searchMatches = const [];
      _activeSearchIndex = 0;
    });
    if (activeSessionId != null) {
      ref
          .read(terminalRuntimeControllerProvider)
          .scrollViewportTo(activeSessionId, 0);
      _focusSession(activeSessionId);
    }
  }

  Future<void> _openGlobalSearch(SessionState sessionState) async {
    final sessions = _searchableSessions(sessionState);
    if (sessions.isEmpty) {
      return;
    }
    final result = await showModalBottomSheet<_GlobalSearchResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _GlobalSearchSheet(sessions: sessions, onSearch: _searchAllSessions),
    );
    if (!mounted || result == null) {
      _focusSession(ref.read(sessionControllerProvider).activeSessionId);
      return;
    }
    final sessionController = ref.read(sessionControllerProvider.notifier);
    sessionController.activateSession(result.session.sessionId);
    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(
          result.session.sessionId,
          result.match.scrollbackOffset,
        );
    _focusSession(result.session.sessionId);
  }

  List<_SearchableSession> _searchableSessions(SessionState sessionState) {
    return [
      for (final tab in sessionState.tabs)
        for (final pane in tab.effectivePanes)
          _SearchableSession(sessionId: pane.sessionId, title: pane.title),
    ];
  }

  List<_GlobalSearchResult> _searchAllSessions(
    String query,
    List<_SearchableSession> sessions,
  ) {
    if (query.trim().isEmpty) {
      return const <_GlobalSearchResult>[];
    }
    final runtime = ref.read(terminalRuntimeControllerProvider);
    return [
      for (final session in sessions)
        for (final match in runtime.searchText(session.sessionId, query))
          _GlobalSearchResult(session: session, match: match),
    ];
  }

  void _openAutocomplete() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(activeSessionId)
        .frame;
    final prefix = _autocompletePrefixForFrame(frame);
    final suggestions = _autocompleteSuggestionsForFrame(frame, prefix);
    if (suggestions.isEmpty) {
      return;
    }

    setState(() {
      _isAutocompleteOpen = true;
      _isSearchOpen = false;
      _autocompletePrefix = prefix;
      _autocompleteSuggestions = suggestions;
      _activeAutocompleteIndex = 0;
    });
  }

  String _autocompletePrefixForFrame(terminal.TerminalFrameDiff frame) {
    final row = _rowAtCursor(frame);
    if (row == null) {
      return '';
    }
    final beforeCursor = terminal.TerminalTextCells.fromText(
      row.text,
    ).sliceColumns(0, frame.cursor.col);
    return RegExp(r'[A-Za-z0-9_./:-]+$').firstMatch(beforeCursor)?.group(0) ??
        '';
  }

  terminal.TerminalRow? _rowAtCursor(terminal.TerminalFrameDiff frame) {
    for (final row in frame.rows) {
      if (row.index == frame.cursor.row) {
        return row;
      }
    }
    if (frame.cursor.row >= 0 && frame.cursor.row < frame.rows.length) {
      return frame.rows[frame.cursor.row];
    }
    return null;
  }

  List<String> _autocompleteSuggestionsForFrame(
    terminal.TerminalFrameDiff frame,
    String prefix,
  ) {
    final normalizedPrefix = prefix.toLowerCase();
    final seen = <String>{};
    final suggestions = <String>[];
    final wordPattern = RegExp(r'[A-Za-z0-9_./:-]{2,}');

    for (final row in frame.rows.reversed) {
      final matches = wordPattern.allMatches(row.text).toList().reversed;
      for (final match in matches) {
        final word = match.group(0)!;
        final normalizedWord = word.toLowerCase();
        if (word == prefix ||
            (normalizedPrefix.isNotEmpty &&
                !normalizedWord.startsWith(normalizedPrefix)) ||
            word.length <= prefix.length ||
            !seen.add(normalizedWord)) {
          continue;
        }
        suggestions.add(word);
        if (suggestions.length >= 8) {
          return suggestions;
        }
      }
    }

    return suggestions;
  }

  void _moveAutocompleteSelection(int delta) {
    if (_autocompleteSuggestions.isEmpty) {
      return;
    }
    final nextIndex =
        (_activeAutocompleteIndex + delta) % _autocompleteSuggestions.length;
    setState(() {
      _activeAutocompleteIndex = nextIndex < 0
          ? nextIndex + _autocompleteSuggestions.length
          : nextIndex;
    });
  }

  void _closeAutocomplete() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    setState(() {
      _isAutocompleteOpen = false;
      _autocompletePrefix = '';
      _autocompleteSuggestions = const [];
      _activeAutocompleteIndex = 0;
    });
    _focusSession(activeSessionId);
  }

  void _acceptAutocomplete(String suggestion) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final suffix =
        suggestion.toLowerCase().startsWith(_autocompletePrefix.toLowerCase())
        ? suggestion.substring(_autocompletePrefix.length)
        : suggestion;
    if (suffix.isNotEmpty) {
      ref
          .read(terminalRuntimeControllerProvider)
          .sendInput(activeSessionId, Uint8List.fromList(utf8.encode(suffix)));
    }
    _closeAutocomplete();
  }

  Future<void> _openDefaultsAndAppearance(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isDefaultsOpen) {
      return;
    }

    setState(() {
      _isDefaultsOpen = true;
    });
    _publishAcceptanceSnapshot(sessionState);

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final selection = await showDialog<DefaultsAndAppearanceSelection>(
      context: context,
      barrierDismissible: true,
      requestFocus: true,
      animationStyle: animationsEnabled ? null : AnimationStyle.noAnimation,
      builder: (dialogContext) => DefaultsAndAppearanceDialog(
        profiles: sessionState.profiles,
        configuredDefaultProfileId: sessionState.configuredDefaultProfileId,
        effectiveDefaultProfileId: sessionState.defaultProfileId,
        themeMode: sessionState.themeMode,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isDefaultsOpen = false;
    });
    _publishAcceptanceSnapshot();

    if (selection != null) {
      if (selection.openProfiles) {
        await _openProfilesSheet(
          sessionController,
          ref.read(sessionControllerProvider),
        );
        return;
      }
      final stateBeforeSave = ref.read(sessionControllerProvider);
      if (selection.configuredDefaultProfileId !=
          stateBeforeSave.configuredDefaultProfileId) {
        if (selection.configuredDefaultProfileId == null) {
          await sessionController.resetDefaultProfile();
        } else {
          await sessionController.setDefaultProfile(
            selection.configuredDefaultProfileId!,
          );
        }
      }
      if (selection.themeMode != stateBeforeSave.themeMode) {
        await sessionController.setThemeMode(selection.themeMode);
      }
    }

    _restoreSessionFocus(
      activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
      activeSessionIdAfterClose: ref
          .read(sessionControllerProvider)
          .activeSessionId,
    );
  }

  Future<void> _openProfilesSheet(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isProfilesOpen) {
      return;
    }

    setState(() {
      _isProfilesOpen = true;
    });
    _publishAcceptanceSnapshot(sessionState);

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<_ProfilesSheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _ProfilesSheet(
          profiles: sessionState.profiles,
          effectiveDefaultProfileId: sessionState.defaultProfileId,
        );
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isProfilesOpen = false;
    });
    _publishAcceptanceSnapshot();

    switch (result) {
      case _OpenProfileResult(:final profile):
        _createSession(
          sessionController,
          profile,
          returningToWorkspace: activeSessionIdBeforeOpen == null,
        );
        return;
      case _EditProfileResult(:final profile):
        final edited = await showDialog<TerminalProfile>(
          context: context,
          builder: (dialogContext) =>
              ProfileEditorDialog(initialValue: profile),
        );
        if (edited != null) {
          await sessionController.saveProfile(edited);
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
    }
  }

  Future<void> _openCommandMenu(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    final defaultProfile = _effectiveDefaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    if (_isCommandMenuOpen) {
      return;
    }

    setState(() {
      _isCommandMenuOpen = true;
    });
    _publishAcceptanceSnapshot(sessionState);

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final hasActiveSession = activeSessionIdBeforeOpen != null;
    final action = await showGeneralDialog<_ShellCommandAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close command menu',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: animationsEnabled
          ? const Duration(milliseconds: 160)
          : Duration.zero,
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (dialogContext, animation, _, child) {
        if (!animationsEnabled) {
          return SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, right: 14),
                child: _ShellCommandMenu(
                  launcherShortcutLabel: _launcherShortcutLabel(),
                  newTabShortcutLabel: _newTabShortcutLabel(),
                  splitRightShortcutLabel: _splitRightShortcutLabel(),
                  splitDownShortcutLabel: _splitDownShortcutLabel(),
                  hotkeyWindowShortcutLabel: _hotkeyWindowShortcutLabel(),
                  autocompleteShortcutLabel: _autocompleteShortcutLabel(),
                  copyModeShortcutLabel: _copyModeShortcutLabel(),
                  sessionCopyShortcutLabel: _sessionCopyShortcutLabel(),
                  sessionPasteShortcutLabel: _sessionPasteShortcutLabel(),
                  pasteHistoryShortcutLabel: _pasteHistoryShortcutLabel(),
                  instantReplayShortcutLabel: _instantReplayShortcutLabel(),
                  hasDefaultProfile: defaultProfile != null,
                  hasActiveSession: hasActiveSession,
                ),
              ),
            ),
          );
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, right: 14),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.03),
                    end: Offset.zero,
                  ).animate(curved),
                  child: _ShellCommandMenu(
                    launcherShortcutLabel: _launcherShortcutLabel(),
                    newTabShortcutLabel: _newTabShortcutLabel(),
                    splitRightShortcutLabel: _splitRightShortcutLabel(),
                    splitDownShortcutLabel: _splitDownShortcutLabel(),
                    hotkeyWindowShortcutLabel: _hotkeyWindowShortcutLabel(),
                    autocompleteShortcutLabel: _autocompleteShortcutLabel(),
                    copyModeShortcutLabel: _copyModeShortcutLabel(),
                    sessionCopyShortcutLabel: _sessionCopyShortcutLabel(),
                    sessionPasteShortcutLabel: _sessionPasteShortcutLabel(),
                    pasteHistoryShortcutLabel: _pasteHistoryShortcutLabel(),
                    instantReplayShortcutLabel: _instantReplayShortcutLabel(),
                    hasDefaultProfile: defaultProfile != null,
                    hasActiveSession: hasActiveSession,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isCommandMenuOpen = false;
    });
    _publishAcceptanceSnapshot();

    final currentState = ref.read(sessionControllerProvider);
    final currentSessionId = currentState.activeSessionId;
    switch (action) {
      case _ShellCommandAction.newTab:
        if (defaultProfile == null) {
          return;
        }
        _createSession(
          sessionController,
          defaultProfile,
          returningToWorkspace: activeSessionIdBeforeOpen == null,
        );
        return;
      case _ShellCommandAction.splitRight:
        if (defaultProfile == null || currentSessionId == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.horizontal,
        );
        return;
      case _ShellCommandAction.splitDown:
        if (defaultProfile == null || currentSessionId == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.vertical,
        );
        return;
      case _ShellCommandAction.copy:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers[currentSessionId];
        if (selectionController == null) {
          return;
        }
        await _copySelection(
          sessionController,
          currentSessionId,
          selectionController,
        );
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case _ShellCommandAction.copyMode:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers.putIfAbsent(
          currentSessionId,
          SelectionController.new,
        );
        _enterCopyMode(
          sessionController,
          currentSessionId,
          selectionController,
        );
        return;
      case _ShellCommandAction.paste:
        if (currentSessionId == null) {
          return;
        }
        await _pasteToSession(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case _ShellCommandAction.pasteHistory:
        if (currentSessionId == null) {
          return;
        }
        await _openPasteHistory(sessionState);
        return;
      case _ShellCommandAction.instantReplay:
        if (currentSessionId == null) {
          return;
        }
        await _openInstantReplay(sessionState);
        return;
      case _ShellCommandAction.search:
        if (currentSessionId == null) {
          return;
        }
        _openSearch();
        return;
      case _ShellCommandAction.globalSearch:
        if (sessionState.tabs.isEmpty) {
          return;
        }
        await _openGlobalSearch(sessionState);
        return;
      case _ShellCommandAction.autocomplete:
        if (currentSessionId == null) {
          return;
        }
        _openAutocomplete();
        return;
      case _ShellCommandAction.hotkeyWindow:
        await WindowBridge.toggleHotkeyWindow();
        return;
      case _ShellCommandAction.defaults:
        await _openDefaultsAndAppearance(sessionController, sessionState);
        return;
      case _ShellCommandAction.profiles:
        await _openProfilesSheet(sessionController, sessionState);
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
    }
  }

  Widget _buildTerminalWorkspace({
    required BuildContext context,
    required SessionController sessionController,
    required SessionState sessionState,
    required TerminalTab activeTab,
    required String activeSessionId,
    required AppThemeTokens palette,
    required KeyEventResult Function(KeyEvent event) onHostKeyEvent,
  }) {
    final panes = activeTab.effectivePanes;
    final direction = activeTab.splitAxis == TerminalSplitAxis.horizontal
        ? Axis.horizontal
        : Axis.vertical;

    return RepaintBoundary(
      key: const Key('shell-terminal-surface'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.terminalSurface,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: Flex(
          direction: direction,
          children: [
            for (var index = 0; index < panes.length; index++) ...[
              Expanded(
                child: _buildTerminalPane(
                  context: context,
                  sessionController: sessionController,
                  sessionState: sessionState,
                  pane: panes[index],
                  isActive: panes[index].sessionId == activeSessionId,
                  palette: palette,
                  onHostKeyEvent: onHostKeyEvent,
                ),
              ),
              if (index < panes.length - 1)
                SizedBox(
                  width: direction == Axis.horizontal ? 1 : double.infinity,
                  height: direction == Axis.horizontal ? double.infinity : 1,
                  child: ColoredBox(color: palette.border),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalPane({
    required BuildContext context,
    required SessionController sessionController,
    required SessionState sessionState,
    required TerminalPane pane,
    required bool isActive,
    required AppThemeTokens palette,
    required KeyEventResult Function(KeyEvent event) onHostKeyEvent,
  }) {
    final sessionId = pane.sessionId;
    final focusNode = _focusNodeFor(sessionId);
    final selectionController = _selectionControllers.putIfAbsent(
      sessionId,
      SelectionController.new,
    );
    final profile = _profileForPane(pane, sessionState.profiles);
    final terminalConfig = profile?.toSessionConfig();
    final terminalColors = _terminalColorsForProfile(context, profile);
    final inputController = TerminalInputController(
      sessionId: sessionId,
      runtime: ref.read(terminalRuntimeControllerProvider),
      readFrame: () => sessionController.viewportFor(sessionId).frame,
      emulation:
          terminalConfig?.emulation ?? terminal.TerminalEmulation.xterm256,
      readSelection: () => _selectionTextForSession(
        sessionController,
        sessionId,
        selectionController,
      ),
      copySelection: ClipboardBridge.copy,
      readClipboard: ClipboardBridge.paste,
    );

    return LayoutBuilder(
      key: Key('shell-pane-$sessionId'),
      builder: (context, constraints) {
        final viewportSize = _terminalContentSizeFor(constraints);
        final scheduledSize = _scheduledViewportSizes[sessionId];
        if (scheduledSize != viewportSize) {
          _scheduledViewportSizes[sessionId] = viewportSize;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _scheduleViewportResize(
                sessionController,
                sessionId,
                viewportSize,
                MediaQuery.devicePixelRatioOf(context),
                immediate: !_committedViewportSizes.containsKey(sessionId),
              );
            }
          });
        }

        return MouseRegion(
          onEnter: (_) {
            if (!isActive) {
              _activateSession(sessionController, sessionId);
            }
          },
          child: Listener(
            onPointerDown: (event) {
              if (!isActive) {
                _activateSession(sessionController, sessionId);
              }
              final frame = sessionController.viewportFor(sessionId).frame;
              final shouldMiddlePaste =
                  frame.modes.mouseMode == 'off' &&
                  (event.buttons & kMiddleMouseButton) != 0;
              if (shouldMiddlePaste) {
                unawaited(_pasteToSession(sessionId));
              }
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isActive
                      ? palette.accent.withValues(alpha: 0.46)
                      : Colors.transparent,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TerminalViewport(
                      focusNode: focusNode,
                      controller: sessionController.viewportFor(sessionId),
                      selectionController: selectionController,
                      inputController: inputController,
                      contentPadding: _terminalViewportPadding,
                      onMeasuredCellSizeChanged: (_) {
                        if (!mounted) {
                          return;
                        }
                        _scheduleViewportResize(
                          sessionController,
                          sessionId,
                          viewportSize,
                          MediaQuery.devicePixelRatioOf(context),
                          immediate: true,
                        );
                      },
                      colors: terminalColors,
                      font:
                          terminalConfig?.display.font ??
                          const terminal.TerminalFontConfig(),
                      cursor:
                          terminalConfig?.display.cursor ??
                          const terminal.TerminalCursorConfig(),
                      copyOnSelect:
                          terminalConfig?.interaction.copyOnSelect ?? false,
                      optionDragMode:
                          terminalConfig?.interaction.optionDragMode ??
                          terminal.TerminalOptionDragMode.blockSelection,
                      onHostKeyEvent: onHostKeyEvent,
                      onScrollLines: (delta) {
                        ref
                            .read(terminalRuntimeControllerProvider)
                            .scrollViewport(sessionId, delta);
                      },
                      onScrollToOffset: (offset) {
                        ref
                            .read(terminalRuntimeControllerProvider)
                            .scrollViewportTo(sessionId, offset);
                      },
                      onOpenLink: (url) =>
                          unawaited(WindowBridge.openExternalUrl(url)),
                    ),
                  ),
                  if (!isActive)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          key: Key('shell-pane-dim-$sessionId'),
                          color: Colors.black.withValues(alpha: 0.20),
                        ),
                      ),
                    ),
                  if (isActive && _isSearchOpen)
                    Positioned(
                      top: _terminalViewportPadding.top,
                      right: _terminalViewportPadding.right,
                      child: _TerminalSearchBar(
                        query: _searchQuery,
                        matches: _searchMatches.length,
                        activeIndex: _activeSearchIndex,
                        palette: palette,
                        onChanged: _searchScrollback,
                        onPrevious: () => _moveSearchMatch(-1),
                        onNext: () => _moveSearchMatch(1),
                        onClose: _closeSearch,
                      ),
                    ),
                  if (isActive && _isAutocompleteOpen)
                    Positioned(
                      top: _terminalViewportPadding.top,
                      right: _terminalViewportPadding.right,
                      child: _TerminalAutocompleteMenu(
                        prefix: _autocompletePrefix,
                        suggestions: _autocompleteSuggestions,
                        activeIndex: _activeAutocompleteIndex,
                        palette: palette,
                        onPrevious: () => _moveAutocompleteSelection(-1),
                        onNext: () => _moveAutocompleteSelection(1),
                        onAccept: _acceptAutocomplete,
                        onClose: _closeAutocomplete,
                      ),
                    ),
                  if (isActive && _isCopyModeOpen)
                    Positioned(
                      top: _terminalViewportPadding.top,
                      left: _terminalViewportPadding.left,
                      child: IgnorePointer(
                        child: _ShellWorkspaceCue(
                          title: 'Copy mode',
                          palette: palette,
                        ),
                      ),
                    ),
                  if (isActive && _showWorkspaceCue)
                    Positioned(
                      top: _terminalViewportPadding.top,
                      right: _terminalViewportPadding.right,
                      child: IgnorePointer(
                        child: _ShellWorkspaceCue(
                          title: _workspaceCueTitle,
                          palette: palette,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
    final palette = context.appTheme;

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
      final shortcut = _shortcutActionFor(event);
      if (shortcut == null) {
        return KeyEventResult.ignored;
      }

      if (shortcut.action == _ShellShortcutAction.requestQuitConfirmation) {
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

      switch (shortcut.action) {
        case _ShellShortcutAction.openLauncher:
          unawaited(_openCommandMenu(sessionController, sessionState));
          return KeyEventResult.handled;
        case _ShellShortcutAction.newTab:
          if (defaultProfile == null) {
            return KeyEventResult.handled;
          }
          _createSession(
            sessionController,
            defaultProfile,
            returningToWorkspace: activeSessionId == null,
          );
          return KeyEventResult.handled;
        case _ShellShortcutAction.splitRight:
          if (defaultProfile == null || activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.horizontal,
          );
          return KeyEventResult.handled;
        case _ShellShortcutAction.splitDown:
          if (defaultProfile == null || activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.vertical,
          );
          return KeyEventResult.handled;
        case _ShellShortcutAction.autocomplete:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _openAutocomplete();
          return KeyEventResult.handled;
        case _ShellShortcutAction.copyMode:
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
        case _ShellShortcutAction.pasteHistory:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          unawaited(_openPasteHistory(sessionState));
          return KeyEventResult.handled;
        case _ShellShortcutAction.instantReplay:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          unawaited(_openInstantReplay(sessionState));
          return KeyEventResult.handled;
        case _ShellShortcutAction.closeActiveTab:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _closeSession(sessionController, sessionState, activeSessionId);
          return KeyEventResult.handled;
        case _ShellShortcutAction.openDefaults:
          unawaited(
            _openDefaultsAndAppearance(sessionController, sessionState),
          );
          return KeyEventResult.handled;
        case _ShellShortcutAction.requestQuitConfirmation:
          return KeyEventResult.handled;
        case _ShellShortcutAction.activateTab:
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
      }
    }

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) => handleShellShortcut(event),
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: ColoredBox(
          color: palette.canvas,
          child: Padding(
            padding: EdgeInsets.only(
              top: defaultTargetPlatform == TargetPlatform.macOS
                  ? 8
                  : MediaQuery.paddingOf(context).top + 8,
            ),
            child: Column(
              children: [
                _ShellChromeBar(
                  palette: palette,
                  tabs: sessionState.tabs,
                  activeSessionId: activeSessionId,
                  referenceDemoMode: referenceDemoMode,
                  onActivateSession: (sessionId) =>
                      _activateSession(sessionController, sessionId),
                  onCloseSession: (sessionId) =>
                      _closeTab(sessionController, sessionState, sessionId),
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
                    child: activeSessionId == null || activeTab == null
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
                            key: ValueKey(activeTab.sessionId),
                            child: _buildTerminalWorkspace(
                              context: context,
                              sessionController: sessionController,
                              sessionState: sessionState,
                              activeTab: activeTab,
                              activeSessionId: activeSessionId,
                              palette: palette,
                              onHostKeyEvent: handleShellShortcut,
                            ),
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

class _ShellChromeBar extends StatelessWidget {
  const _ShellChromeBar({
    required this.palette,
    required this.tabs,
    required this.activeSessionId,
    required this.referenceDemoMode,
    required this.onActivateSession,
    required this.onCloseSession,
    required this.onShowCommandMenu,
  });

  final AppThemeTokens palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool referenceDemoMode;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onCloseSession;
  final VoidCallback onShowCommandMenu;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-chrome-bar'),
      decoration: BoxDecoration(
        color: palette.chrome,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 72),
            Expanded(
              child: referenceDemoMode
                  ? _ReferenceDemoTabStrip(
                      palette: palette,
                      tabs: tabs,
                      activeSessionId: activeSessionId,
                      onActivateSession: onActivateSession,
                    )
                  : _ShellTabStrip(
                      palette: palette,
                      tabs: tabs,
                      activeSessionId: activeSessionId,
                      onActivateSession: onActivateSession,
                      onCloseSession: onCloseSession,
                    ),
            ),
            if (!referenceDemoMode) ...[
              IconButton(
                key: const Key('shell-chrome-menu'),
                tooltip: 'Open command menu',
                onPressed: onShowCommandMenu,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                iconSize: 16,
                icon: Icon(Icons.tune_rounded, color: palette.textSubtle),
              ),
              const SizedBox(width: 6),
            ] else
              const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}

class _ShellConfigurationWarningsBanner extends StatelessWidget {
  const _ShellConfigurationWarningsBanner({
    required this.palette,
    required this.warnings,
    required this.onReviewProfiles,
    required this.onDismiss,
  });

  final AppThemeTokens palette;
  final List<TerminalProfileLoadWarning> warnings;
  final Future<void> Function() onReviewProfiles;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-configuration-warnings'),
      decoration: BoxDecoration(
        color: palette.overlay,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: palette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Some terminal profile values were ignored and reset to safe defaults.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final warning in warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            terminalProfileLoadWarningMessage(warning),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSubtle),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('shell-configuration-warnings-dismiss'),
                  tooltip: 'Dismiss configuration warnings',
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, color: palette.textSubtle),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                FilledButton.tonal(
                  key: const Key('shell-configuration-warnings-review'),
                  onPressed: () => unawaited(onReviewProfiles()),
                  child: const Text('Review Profiles'),
                ),
                const SizedBox(width: 6),
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceDemoTabStrip extends StatelessWidget {
  const _ReferenceDemoTabStrip({
    required this.palette,
    required this.tabs,
    required this.activeSessionId,
    required this.onActivateSession,
  });

  final AppThemeTokens palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final ValueChanged<String> onActivateSession;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('shell-tab-strip'),
      children: [
        for (var index = 0; index < tabs.length; index++) ...[
          Expanded(
            child: _ReferenceDemoTab(
              palette: palette,
              tab: tabs[index],
              shortcutIndex: index < 9 ? index + 1 : null,
              isActive:
                  activeSessionId != null &&
                  tabs[index].containsSession(activeSessionId!),
              onActivate: () => onActivateSession(tabs[index].activeSessionId),
            ),
          ),
          if (index < tabs.length - 1)
            SizedBox(
              width: 1,
              height: double.infinity,
              child: ColoredBox(color: palette.border),
            ),
        ],
      ],
    );
  }
}

class _ReferenceDemoTab extends StatelessWidget {
  const _ReferenceDemoTab({
    required this.palette,
    required this.tab,
    required this.shortcutIndex,
    required this.isActive,
    required this.onActivate,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
  final bool isActive;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'shell-tab-${tab.sessionId}',
      selected: isActive,
      button: true,
      child: TextButton(
        key: Key('shell-tab-${tab.sessionId}'),
        onPressed: onActivate,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isActive ? palette.textPrimary : palette.textMuted,
          shape: const RoundedRectangleBorder(),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shortcutIndex != null) ...[
                Text(
                  '⌘$shortcutIndex',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isActive ? palette.textMuted : palette.textSubtle,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                tab.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: isActive ? palette.textPrimary : palette.textSubtle,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellTabStrip extends StatelessWidget {
  const _ShellTabStrip({
    required this.palette,
    required this.tabs,
    required this.activeSessionId,
    required this.onActivateSession,
    required this.onCloseSession,
  });

  final AppThemeTokens palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onCloseSession;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('shell-tab-strip'),
      height: double.infinity,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: palette.border,
        ),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive =
              activeSessionId != null && tab.containsSession(activeSessionId!);
          return _ShellTabButton(
            palette: palette,
            tab: tab,
            shortcutIndex: index < 9 ? index + 1 : null,
            isActive: isActive,
            onActivate: () => onActivateSession(tab.activeSessionId),
            onClose: () => onCloseSession(tab.sessionId),
          );
        },
      ),
    );
  }
}

class _ShellTabButton extends StatelessWidget {
  const _ShellTabButton({
    required this.palette,
    required this.tab,
    required this.shortcutIndex,
    required this.isActive,
    required this.onActivate,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'shell-tab-${tab.sessionId}',
      selected: isActive,
      button: true,
      child: TextButton(
        key: Key('shell-tab-${tab.sessionId}'),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
          foregroundColor: isActive ? palette.textPrimary : palette.textMuted,
          shape: const RoundedRectangleBorder(),
        ),
        onPressed: onActivate,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (shortcutIndex != null) ...[
              Text(
                '⌘$shortcutIndex',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isActive ? palette.textMuted : palette.textSubtle,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
            ],
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 140),
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: isActive ? palette.textPrimary : palette.textMuted,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(tab.title, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Close ${tab.title}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Icon(
                  Icons.close_rounded,
                  size: 11,
                  color: isActive
                      ? palette.textMuted
                      : palette.textSubtle.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellEmptyState extends StatelessWidget {
  const _ShellEmptyState({
    super.key,
    required this.palette,
    required this.title,
    required this.message,
    required this.defaultSummary,
    required this.onNewTab,
  });

  final AppThemeTokens palette;
  final String title;
  final String message;
  final String defaultSummary;
  final VoidCallback? onNewTab;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppEmptyState(
            title: title,
            message: message,
            supportingText: defaultSummary,
            action: AppActionButton(
              buttonKey: const Key('shell-empty-new-tab'),
              icon: Icons.add_box_outlined,
              label: 'New Tab',
              onPressed: onNewTab,
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalSearchBar extends StatelessWidget {
  const _TerminalSearchBar({
    required this.query,
    required this.matches,
    required this.activeIndex,
    required this.palette,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final String query;
  final int matches;
  final int activeIndex;
  final AppThemeTokens palette;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  String get _counterText {
    if (matches == 0) {
      return query.isEmpty ? '0 of 0' : 'No matches';
    }
    return '${activeIndex + 1} of $matches';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('terminal-search-bar'),
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.overlay.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          width: 304,
          height: 38,
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('terminal-search-field'),
                  autofocus: true,
                  onChanged: onChanged,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search',
                    hintStyle: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Text(
                _counterText,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: matches == 0 && query.isNotEmpty
                      ? palette.textMuted
                      : palette.textSubtle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                key: const Key('terminal-search-previous'),
                tooltip: 'Previous match',
                onPressed: matches == 0 ? null : onPrevious,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                iconSize: 16,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                key: const Key('terminal-search-next'),
                tooltip: 'Next match',
                onPressed: matches == 0 ? null : onNext,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                iconSize: 16,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              IconButton(
                key: const Key('terminal-search-close'),
                tooltip: 'Close search',
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                iconSize: 16,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlobalSearchSheet extends StatefulWidget {
  const _GlobalSearchSheet({required this.sessions, required this.onSearch});

  final List<_SearchableSession> sessions;
  final List<_GlobalSearchResult> Function(
    String query,
    List<_SearchableSession> sessions,
  )
  onSearch;

  @override
  State<_GlobalSearchSheet> createState() => _GlobalSearchSheetState();
}

class _GlobalSearchSheetState extends State<_GlobalSearchSheet> {
  String _query = '';
  List<_GlobalSearchResult> _results = const [];

  void _handleQueryChanged(String value) {
    setState(() {
      _query = value;
      _results = widget.onSearch(value, widget.sessions);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final resultCount = _results.length;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        key: const Key('terminal-global-search-sheet'),
        color: palette.panel,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(palette.radius.lg),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('terminal-global-search-field'),
                          autofocus: true,
                          onChanged: _handleQueryChanged,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.textPrimary),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.manage_search_rounded),
                            hintText: 'Global search',
                            isDense: true,
                            filled: true,
                            fillColor: palette.overlay,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                palette.radius.sm,
                              ),
                              borderSide: BorderSide(color: palette.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$resultCount matches',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: palette.textSubtle,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: _query.trim().isEmpty
                        ? Center(
                            child: Text(
                              'Type to search ${widget.sessions.length} sessions',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textMuted),
                            ),
                          )
                        : resultCount == 0
                        ? Center(
                            child: Text(
                              'No matches',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textMuted),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: resultCount,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: palette.border),
                            itemBuilder: (context, index) {
                              final result = _results[index];
                              return ListTile(
                                key: Key(
                                  'terminal-global-search-result-${result.session.sessionId}-$index',
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  result.match.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: palette.textPrimary),
                                ),
                                subtitle: Text(
                                  '${result.session.title} • row ${result.match.row + 1}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: palette.textSubtle),
                                ),
                                trailing: const Icon(
                                  Icons.keyboard_return_rounded,
                                  size: 18,
                                ),
                                onTap: () => Navigator.of(context).pop(result),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalAutocompleteMenu extends StatelessWidget {
  const _TerminalAutocompleteMenu({
    required this.prefix,
    required this.suggestions,
    required this.activeIndex,
    required this.palette,
    required this.onPrevious,
    required this.onNext,
    required this.onAccept,
    required this.onClose,
  });

  final String prefix;
  final List<String> suggestions;
  final int activeIndex;
  final AppThemeTokens palette;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<String> onAccept;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('terminal-autocomplete-menu'),
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.overlay.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_fix_high_rounded,
                      size: 15,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        prefix.isEmpty ? 'Completions' : 'Complete "$prefix"',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('terminal-autocomplete-previous'),
                      tooltip: 'Previous completion',
                      onPressed: suggestions.length < 2 ? null : onPrevious,
                      visualDensity: VisualDensity.compact,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      key: const Key('terminal-autocomplete-next'),
                      tooltip: 'Next completion',
                      onPressed: suggestions.length < 2 ? null : onNext,
                      visualDensity: VisualDensity.compact,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    IconButton(
                      key: const Key('terminal-autocomplete-close'),
                      tooltip: 'Close completions',
                      onPressed: onClose,
                      visualDensity: VisualDensity.compact,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(color: palette.border, height: 1),
              for (var index = 0; index < suggestions.length; index++)
                _AutocompleteSuggestionTile(
                  suggestion: suggestions[index],
                  active: index == activeIndex,
                  palette: palette,
                  onTap: () => onAccept(suggestions[index]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutocompleteSuggestionTile extends StatelessWidget {
  const _AutocompleteSuggestionTile({
    required this.suggestion,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  final String suggestion;
  final bool active;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('terminal-autocomplete-suggestion-$suggestion'),
      onTap: onTap,
      child: ColoredBox(
        color: active
            ? palette.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                suggestion,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: active ? palette.textPrimary : palette.textSubtle,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstantReplaySheet extends StatefulWidget {
  const _InstantReplaySheet({required this.frames, required this.onClear});

  final List<InstantReplayFrame> frames;
  final VoidCallback onClear;

  @override
  State<_InstantReplaySheet> createState() => _InstantReplaySheetState();
}

class _InstantReplaySheetState extends State<_InstantReplaySheet> {
  late List<InstantReplayFrame> _frames;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _frames = widget.frames;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final activeFrame = _frames.isEmpty ? null : _frames[_activeIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('instant-replay-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Instant Replay',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close instant replay',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.textMuted),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '${_frames.length} captured frame${_frames.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      key: const Key('instant-replay-clear'),
                      onPressed: _frames.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _frames = const [];
                                _activeIndex = 0;
                              });
                              widget.onClear();
                            },
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_frames.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No terminal frames captured yet.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textSubtle,
                        ),
                      ),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Icon(
                        Icons.history_toggle_off_rounded,
                        size: 16,
                        color: palette.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _frameLabel(activeFrame!),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    key: const Key('instant-replay-slider'),
                    value: _activeIndex.toDouble(),
                    min: 0,
                    max: (_frames.length - 1).toDouble(),
                    divisions: _frames.length <= 1 ? null : _frames.length - 1,
                    label: _activeIndex == 0
                        ? 'Now'
                        : '${_activeIndex + 1} of ${_frames.length}',
                    onChanged: _frames.length <= 1
                        ? null
                        : (value) {
                            setState(() {
                              _activeIndex = value
                                  .round()
                                  .clamp(0, _frames.length - 1)
                                  .toInt();
                            });
                          },
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.terminalSurface,
                        borderRadius: BorderRadius.circular(palette.radius.md),
                        border: Border.all(color: palette.border),
                      ),
                      child: SingleChildScrollView(
                        key: const Key('instant-replay-preview'),
                        padding: const EdgeInsets.all(10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            activeFrame.text,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: palette.textPrimary,
                                  fontFamily: 'monospace',
                                  height: 1.25,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('instant-replay-copy'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_InstantReplayCopyResult(activeFrame.text)),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Text'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _frameLabel(InstantReplayFrame frame) {
    final timestamp = frame.capturedAt;
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final time =
        '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}:${twoDigits(timestamp.second)}';
    return _activeIndex == 0 ? 'Latest frame • $time' : 'Older frame • $time';
  }
}

class _PasteHistorySheet extends StatefulWidget {
  const _PasteHistorySheet({
    required this.entries,
    required this.persistToDisk,
    required this.onPersistChanged,
    required this.onClear,
  });

  final List<PasteHistoryEntry> entries;
  final bool persistToDisk;
  final ValueChanged<bool> onPersistChanged;
  final VoidCallback onClear;

  @override
  State<_PasteHistorySheet> createState() => _PasteHistorySheetState();
}

class _PasteHistorySheetState extends State<_PasteHistorySheet> {
  late List<PasteHistoryEntry> _entries;
  late bool _persistToDisk;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
    _persistToDisk = widget.persistToDisk;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('paste-history-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Paste History',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close paste history',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.textMuted),
                    ),
                  ],
                ),
                SwitchListTile(
                  key: const Key('paste-history-persist'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Save History to Disk',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Keep recent copied and pasted text across launches.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
                  ),
                  value: _persistToDisk,
                  onChanged: (value) {
                    setState(() {
                      _persistToDisk = value;
                    });
                    widget.onPersistChanged(value);
                  },
                ),
                Row(
                  children: [
                    Text(
                      '${_entries.length} recent item${_entries.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      key: const Key('paste-history-clear'),
                      onPressed: _entries.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _entries = const [];
                              });
                              widget.onClear();
                            },
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: _entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Center(
                            child: Text(
                              'No copied or pasted text yet.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) =>
                              Divider(color: palette.border, height: 1),
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            return _PasteHistoryEntryTile(
                              index: index,
                              entry: entry,
                              palette: palette,
                              onTap: () => Navigator.of(
                                context,
                              ).pop(_PasteHistoryPickResult(entry)),
                            );
                          },
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

class _PasteHistoryEntryTile extends StatelessWidget {
  const _PasteHistoryEntryTile({
    required this.index,
    required this.entry,
    required this.palette,
    required this.onTap,
  });

  final int index;
  final PasteHistoryEntry entry;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  String get _kindLabel {
    return switch (entry.kind) {
      PasteHistoryKind.copy => 'Copied',
      PasteHistoryKind.paste => 'Pasted',
    };
  }

  @override
  Widget build(BuildContext context) {
    final preview = entry.text.replaceAll('\n', ' ⏎ ');
    return ListTile(
      key: Key('paste-history-entry-$index'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.kind == PasteHistoryKind.copy
            ? Icons.copy_rounded
            : Icons.content_paste_rounded,
        color: palette.textMuted,
      ),
      title: Text(
        preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        _kindLabel,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      onTap: onTap,
    );
  }
}

class _ShellWorkspaceCue extends StatelessWidget {
  const _ShellWorkspaceCue({required this.title, required this.palette});

  final String title;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-workspace-focus-cue'),
      decoration: BoxDecoration(
        color: palette.overlay.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(palette.radius.lg),
        border: Border.all(color: palette.accent.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_command_key_rounded,
              color: palette.accent,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellCommandMenu extends StatelessWidget {
  const _ShellCommandMenu({
    required this.launcherShortcutLabel,
    required this.newTabShortcutLabel,
    required this.splitRightShortcutLabel,
    required this.splitDownShortcutLabel,
    required this.hotkeyWindowShortcutLabel,
    required this.autocompleteShortcutLabel,
    required this.copyModeShortcutLabel,
    required this.sessionCopyShortcutLabel,
    required this.sessionPasteShortcutLabel,
    required this.pasteHistoryShortcutLabel,
    required this.instantReplayShortcutLabel,
    required this.hasDefaultProfile,
    required this.hasActiveSession,
  });

  final String launcherShortcutLabel;
  final String newTabShortcutLabel;
  final String splitRightShortcutLabel;
  final String splitDownShortcutLabel;
  final String hotkeyWindowShortcutLabel;
  final String autocompleteShortcutLabel;
  final String copyModeShortcutLabel;
  final String sessionCopyShortcutLabel;
  final String sessionPasteShortcutLabel;
  final String pasteHistoryShortcutLabel;
  final String instantReplayShortcutLabel;
  final bool hasDefaultProfile;
  final bool hasActiveSession;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;

    Widget sectionLabel(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.textSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.24,
            ),
          ),
        ),
      );
    }

    return Material(
      key: const Key('shell-command-menu-overlay'),
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 460),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.overlay,
            borderRadius: BorderRadius.circular(palette.radius.lg),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Top actions',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close actions',
                          onPressed: () => Navigator.of(context).pop(),
                          visualDensity: VisualDensity.compact,
                          splashRadius: 16,
                          icon: Icon(
                            Icons.close_rounded,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  sectionLabel('App actions'),
                  _ShellCommandTile(
                    key: const Key('shell-new-tab'),
                    icon: Icons.add_box_outlined,
                    title: 'New tab',
                    subtitle: 'App action • Open the default shell profile.',
                    shortcutLabel: newTabShortcutLabel,
                    enabled: hasDefaultProfile,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.newTab),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-command-defaults'),
                    icon: Icons.tune_rounded,
                    title: 'Defaults & appearance',
                    subtitle:
                        'App action • Pick the default profile and theme.',
                    enabled: true,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.defaults),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-command-profiles'),
                    icon: Icons.folder_open_rounded,
                    title: 'Profiles…',
                    subtitle: 'App action • Open or edit shell profiles.',
                    enabled: true,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.profiles),
                  ),
                  sectionLabel('Session actions'),
                  if (!hasActiveSession)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Requires an active shell session.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSubtle),
                        ),
                      ),
                    ),
                  _ShellCommandTile(
                    icon: Icons.copy_rounded,
                    title: 'Copy selection',
                    subtitle: 'Session action • Copy the current selection.',
                    shortcutLabel: sessionCopyShortcutLabel,
                    enabled: hasActiveSession,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.copy),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-copy-mode'),
                    icon: Icons.select_all_rounded,
                    title: 'Copy mode',
                    subtitle:
                        'Session action • Select terminal text from the keyboard.',
                    shortcutLabel: copyModeShortcutLabel,
                    enabled: hasActiveSession,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.copyMode),
                  ),
                  _ShellCommandTile(
                    icon: Icons.content_paste_rounded,
                    title: 'Paste clipboard',
                    subtitle:
                        'Session action • Paste clipboard into the shell.',
                    shortcutLabel: sessionPasteShortcutLabel,
                    enabled: hasActiveSession,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.paste),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-paste-history'),
                    icon: Icons.history_rounded,
                    title: 'Paste history',
                    subtitle:
                        'Session action • Revisit recently copied or pasted text.',
                    shortcutLabel: pasteHistoryShortcutLabel,
                    enabled: hasActiveSession,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_ShellCommandAction.pasteHistory),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-instant-replay'),
                    icon: Icons.replay_rounded,
                    title: 'Instant replay',
                    subtitle:
                        'Session action • Recover text from recent terminal frames.',
                    shortcutLabel: instantReplayShortcutLabel,
                    enabled: hasActiveSession,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_ShellCommandAction.instantReplay),
                  ),
                  _ShellCommandTile(
                    icon: Icons.search_rounded,
                    title: 'Search scrollback',
                    subtitle: 'Session action • Find text in local output.',
                    enabled: hasActiveSession,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.search),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-global-search'),
                    icon: Icons.manage_search_rounded,
                    title: 'Global search',
                    subtitle: 'Workspace action • Search all tabs at once.',
                    enabled: hasActiveSession,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_ShellCommandAction.globalSearch),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-autocomplete'),
                    icon: Icons.auto_fix_high_rounded,
                    title: 'Autocomplete',
                    subtitle:
                        'Session action • Complete a word from visible output.',
                    shortcutLabel: autocompleteShortcutLabel,
                    enabled: hasActiveSession,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_ShellCommandAction.autocomplete),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-split-right'),
                    icon: Icons.vertical_split_rounded,
                    title: 'Split right',
                    subtitle:
                        'Pane action • Open the default profile beside this pane.',
                    shortcutLabel: splitRightShortcutLabel,
                    enabled: hasDefaultProfile && hasActiveSession,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_ShellCommandAction.splitRight),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-split-down'),
                    icon: Icons.horizontal_split_rounded,
                    title: 'Split down',
                    subtitle:
                        'Pane action • Open the default profile below this pane.',
                    shortcutLabel: splitDownShortcutLabel,
                    enabled: hasDefaultProfile && hasActiveSession,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_ShellCommandAction.splitDown),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-hotkey-window'),
                    icon: Icons.keyboard_rounded,
                    title: 'Hotkey window',
                    subtitle: 'App action • Hide or summon the shell window.',
                    shortcutLabel: hotkeyWindowShortcutLabel,
                    enabled: true,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_ShellCommandAction.hotkeyWindow),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.keyboard_command_key_rounded,
                          size: 16,
                          color: palette.textSubtle,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Open command menu with $launcherShortcutLabel',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: palette.textSubtle),
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
      ),
    );
  }
}

class _ShellCommandTile extends StatelessWidget {
  const _ShellCommandTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.shortcutLabel,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String? shortcutLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(palette.radius.lg),
      ),
      leading: Icon(
        icon,
        color: enabled ? palette.textPrimary : palette.textSubtle,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: enabled ? palette.textPrimary : palette.textSubtle,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      trailing: shortcutLabel == null
          ? null
          : Text(
              shortcutLabel!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: enabled ? palette.textMuted : palette.textSubtle,
                fontWeight: FontWeight.w700,
              ),
            ),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}

class _ProfilesSheet extends StatefulWidget {
  const _ProfilesSheet({
    required this.profiles,
    required this.effectiveDefaultProfileId,
  });

  final List<TerminalProfile> profiles;
  final String? effectiveDefaultProfileId;

  @override
  State<_ProfilesSheet> createState() => _ProfilesSheetState();
}

class _ProfilesSheetState extends State<_ProfilesSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TerminalProfile> get _filteredProfiles {
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return widget.profiles;
    }
    return [
      for (final profile in widget.profiles)
        if (_profileMatchesQuery(profile, normalizedQuery)) profile,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final filteredProfiles = _filteredProfiles;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('profiles-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Profiles',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close profiles',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.textMuted),
                    ),
                  ],
                ),
                Text(
                  'Open a tab with any saved profile or edit its terminal settings.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('profiles-search-field'),
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Search profiles or tags',
                  ),
                  onChanged: (value) {
                    setState(() {
                      _query = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: filteredProfiles.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Text(
                            'No matching profiles',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: palette.textSubtle),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filteredProfiles.length,
                          separatorBuilder: (_, _) =>
                              Divider(color: palette.border, height: 1),
                          itemBuilder: (context, index) {
                            final profile = filteredProfiles[index];
                            final isDefault =
                                profile.id == widget.effectiveDefaultProfileId;
                            final summary = _profileSummary(
                              profile,
                              isDefault: isDefault,
                            );
                            return ListTile(
                              key: Key('profile-entry-${profile.id}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                profile.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: palette.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              subtitle: _ProfileEntrySubtitle(
                                summary: summary,
                                tags: profile.tags,
                              ),
                              trailing: IconButton(
                                tooltip: 'Edit ${profile.name}',
                                onPressed: () => Navigator.of(
                                  context,
                                ).pop(_EditProfileResult(profile)),
                                icon: Icon(
                                  Icons.edit_outlined,
                                  color: palette.textMuted,
                                ),
                              ),
                              onTap: () => Navigator.of(
                                context,
                              ).pop(_OpenProfileResult(profile)),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _profileSummary(TerminalProfile profile, {required bool isDefault}) {
    final base =
        '${profile.shell} • ${terminalEmulationLabel(profile.terminalEmulation)} • ${profile.scrollbackLines} lines';
    return isDefault ? '$base • Default profile' : base;
  }

  bool _profileMatchesQuery(TerminalProfile profile, String query) {
    if (profile.name.toLowerCase().contains(query) ||
        profile.shell.toLowerCase().contains(query)) {
      return true;
    }
    return profile.tags.any((tag) => tag.toLowerCase().contains(query));
  }
}

class _ProfileEntrySubtitle extends StatelessWidget {
  const _ProfileEntrySubtitle({required this.summary, required this.tags});

  final String summary;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final summaryStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: palette.textSubtle);
    if (tags.isEmpty) {
      return Text(summary, style: summaryStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(summary, style: summaryStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in tags)
              DecoratedBox(
                key: Key('profile-tag-$tag'),
                decoration: BoxDecoration(
                  color: palette.panel,
                  border: Border.all(color: palette.border),
                  borderRadius: BorderRadius.circular(palette.radius.sm),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    tag,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
