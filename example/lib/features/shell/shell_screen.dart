import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../platform/clipboard_bridge.dart';
import '../../ui/app_ui.dart';
import '../config/local_terminal_config_models.dart';
import '../config/local_terminal_keybinding_resolver.dart';
import '../preferences/app_preferences_models.dart';
import '../policies/local_terminal_paste_decision.dart';
import '../policies/local_terminal_policy_models.dart';
import '../profiles/dynamic_profiles_sheet.dart';
import '../profiles/profile_editor.dart';
import '../profiles/profile_models.dart';
import '../profiles/profiles_sheet.dart';
import '../sessions/session_controller.dart';
import '../sessions/session_state.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal.dart' as terminal;
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart';
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
import 'window_bridge.dart';

class _ShellShortcut {
  const _ShellShortcut(this.action, {this.tabIndex});

  final TerminalActionId action;
  final int? tabIndex;
}

final shellAnimationsEnabledProvider = Provider<bool>((ref) => true);

final pasteHistoryRepositoryProvider = Provider<PasteHistoryRepository>((ref) {
  return PasteHistoryRepository();
});

final instantReplayStoreProvider = Provider<InstantReplayStore>((ref) {
  return InstantReplayStore();
});

final passwordManagerStoreProvider = Provider<PasswordManagerStore>((ref) {
  return PasswordManagerStore();
});

final RegExp _passwordPromptPattern = RegExp(
  r'(?:password|passphrase)(?:\s+for\s+[^:]+)?\s*:\s*$',
  caseSensitive: false,
);

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

sealed class _PasteHistorySheetResult {
  const _PasteHistorySheetResult();
}

final class _PasteHistoryPickResult extends _PasteHistorySheetResult {
  const _PasteHistoryPickResult(this.entry);

  final PasteHistoryEntry entry;
}

sealed class _AdvancedPasteSheetResult {
  const _AdvancedPasteSheetResult();
}

final class _AdvancedPasteSendResult extends _AdvancedPasteSheetResult {
  const _AdvancedPasteSendResult(this.text);

  final String text;
}

sealed class _PasswordManagerSheetResult {
  const _PasswordManagerSheetResult();
}

final class _PasswordManagerSendResult extends _PasswordManagerSheetResult {
  const _PasswordManagerSendResult(this.entry);

  final PasswordManagerEntry entry;
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

class _TerminalAnnotation {
  const _TerminalAnnotation({
    required this.id,
    required this.sessionId,
    required this.selectedText,
    required this.note,
  });

  final String id;
  final String sessionId;
  final String selectedText;
  final String note;
}

class _CapturedOutputEntry {
  const _CapturedOutputEntry({
    required this.id,
    required this.sessionId,
    required this.pattern,
    required this.text,
    required this.rowIndex,
  });

  final String id;
  final String sessionId;
  final String pattern;
  final String text;
  final int rowIndex;
}

class _LogicalTerminalRow {
  const _LogicalTerminalRow({
    required this.startRow,
    required this.endRow,
    required this.text,
  });

  final terminal.TerminalRow startRow;
  final terminal.TerminalRow endRow;
  final String text;
}

class _CoprocessStartRequest {
  const _CoprocessStartRequest({
    required this.command,
    required this.pattern,
    required this.response,
  });

  final String command;
  final String pattern;
  final String response;
}

class _ShellCoprocess {
  const _ShellCoprocess({
    required this.command,
    required this.pattern,
    required this.response,
    this.inputLineCount = 0,
    this.lastInput,
  });

  final String command;
  final String pattern;
  final String response;
  final int inputLineCount;
  final String? lastInput;

  _ShellCoprocess copyWith({int? inputLineCount, String? lastInput}) {
    return _ShellCoprocess(
      command: command,
      pattern: pattern,
      response: response,
      inputLineCount: inputLineCount ?? this.inputLineCount,
      lastInput: lastInput ?? this.lastInput,
    );
  }
}

class _SessionBadgeContent {
  const _SessionBadgeContent({
    required this.title,
    required this.detail,
    this.status,
  });

  final String title;
  final String detail;
  final String? status;
}

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

  final Map<String, SelectionController> _selectionControllers = {};
  final Map<String, FocusNode> _terminalFocusNodes = {};
  final Map<String, Size> _scheduledViewportSizes = {};
  final Map<String, Size> _committedViewportSizes = {};
  final Map<String, Size> _measuredTerminalCellSizes = {};
  final Map<String, int> _paneFlexBySession = {};
  final Set<String> _readOnlySessionIds = {};
  final Map<String, DateTime> _lastActivityNotificationAt = {};
  final Map<String, String?> _lastActivityFramePreviews = {};
  final Map<String, Set<String>> _triggerMatchesBySession = {};
  final Map<String, int> _terminalFrameSequenceBySession = {};
  final TextEditingController _autoComposerController = TextEditingController();
  final FocusNode _autoComposerFocusNode = FocusNode();
  final Set<String> _sessionsSeenForActivityNotifications = {};
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
  bool _commandFinishedNotificationsEnabled = true;
  bool _bellNotificationsEnabled = true;
  bool _activityNotificationsEnabled = true;
  int _lastObservedTabCount = 0;
  String? _zoomedPaneSessionId;
  String? _lastRenderableSessionId;
  String _searchQuery = '';
  String? _searchErrorText;
  List<TerminalSearchMatch> _searchMatches = const [];
  int _activeSearchIndex = 0;
  bool _searchUseRegex = false;
  String _autocompletePrefix = '';
  List<String> _autocompleteSuggestions = const [];
  int _activeAutocompleteIndex = 0;
  List<String> _autoComposerSuggestions = const [];
  int _activeAutoComposerIndex = 0;
  List<PasteHistoryEntry> _pasteHistoryEntries = const [];
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
    _terminalEventSubscription?.cancel();
    _workspaceCueTimer?.cancel();
    _viewportResizeTimer?.cancel();
    for (final focusNode in _terminalFocusNodes.values) {
      focusNode.dispose();
    }
    _autoComposerController.dispose();
    _autoComposerFocusNode.dispose();
    super.dispose();
  }

  void _handleTerminalSessionEvent(terminal.TerminalSessionEvent event) {
    switch (event) {
      case terminal.TerminalSessionFrameEvent(:final sessionId, :final frame):
        final frameSequence =
            (_terminalFrameSequenceBySession[sessionId] ?? 0) + 1;
        _terminalFrameSequenceBySession[sessionId] = frameSequence;
        ref.read(instantReplayStoreProvider).record(sessionId, frame);
        _feedCoprocess(sessionId, frame, frameSequence: frameSequence);
        _runProfileTriggers(sessionId, frame, frameSequence: frameSequence);
        _notifyInactiveActivity(sessionId, frame);
        _scheduleRenderableSessionSwap(sessionId);
      case terminal.TerminalSessionExitEvent():
        _terminalFrameSequenceBySession.remove(event.sessionId);
        _triggerMatchesBySession.remove(event.sessionId);
        _stopCoprocess(event.sessionId);
        _clearCapturedOutput(event.sessionId);
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
    if (!_activityNotificationsEnabled) {
      return;
    }
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
    if (!_bellNotificationsEnabled) {
      return;
    }
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
    if (!_commandFinishedNotificationsEnabled) {
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

  Future<void> _loadNotificationPreferences() async {
    final preferences = await ref.read(appPreferencesRepositoryProvider).load();
    if (!mounted || preferences == null) {
      return;
    }
    setState(() {
      _commandFinishedNotificationsEnabled =
          preferences.notifications.commandFinished;
      _bellNotificationsEnabled = preferences.notifications.bell;
      _activityNotificationsEnabled = preferences.notifications.activity;
    });
  }

  Future<void> _saveNotificationPreferences() async {
    final repository = ref.read(appPreferencesRepositoryProvider);
    final preferences =
        await repository.load() ?? const TerminalAppPreferencesDocument();
    await repository.save(
      preferences.copyWith(
        notifications: TerminalAppNotifications(
          commandFinished: _commandFinishedNotificationsEnabled,
          bell: _bellNotificationsEnabled,
          activity: _activityNotificationsEnabled,
        ),
      ),
    );
  }

  Future<bool> _toggleHotkeyWindowWithFeedback() async {
    final status = await WindowBridge.hotkeyStatus();
    if (status != null && !status.registered) {
      _showHotkeyWindowFailure(status);
      return false;
    }
    try {
      await WindowBridge.toggleHotkeyWindow();
      return true;
    } on PlatformException catch (error) {
      _showHotkeyWindowFailure(status, error: error);
      return false;
    }
  }

  void _showHotkeyWindowFailure(
    HotkeyWindowStatus? status, {
    PlatformException? error,
  }) {
    if (!mounted) {
      return;
    }
    final details = <String>[
      'Hotkey window unavailable',
      if (status != null) 'shortcut: ${status.shortcut}',
      if (status?.errorCode != null) 'error: ${status!.errorCode}',
      if (error?.message != null && error!.message!.trim().isNotEmpty)
        error.message!.trim(),
    ].join(' - ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(details)));
  }

  void _feedCoprocess(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    required int frameSequence,
  }) {
    final currentCoprocess = _coprocesses[sessionId];
    if (currentCoprocess == null) {
      return;
    }
    var nextCoprocess = currentCoprocess;
    final seenKeys = _coprocessInputKeysBySession.putIfAbsent(
      sessionId,
      () => <String>{},
    );
    String? pendingResponse;
    for (final logicalRow in _logicalRows(frame.rows)) {
      final input = logicalRow.text.trimRight();
      if (input.trim().isEmpty) {
        continue;
      }
      final inputKey = [
        _frameDedupeScope(frame, frameSequence),
        logicalRow.endRow.index,
        input,
      ].join('\u0000');
      if (!seenKeys.add(inputKey)) {
        continue;
      }
      nextCoprocess = nextCoprocess.copyWith(
        inputLineCount: nextCoprocess.inputLineCount + 1,
        lastInput: input,
      );
      if (pendingResponse == null &&
          _coprocessPatternMatches(nextCoprocess.pattern, input)) {
        pendingResponse = nextCoprocess.response;
      }
    }
    if (nextCoprocess != currentCoprocess && mounted) {
      setState(() {
        _coprocesses = <String, _ShellCoprocess>{
          ..._coprocesses,
          sessionId: nextCoprocess,
        };
      });
    }
    if (pendingResponse != null) {
      _sendPlainTextToSession(sessionId, pendingResponse);
    }
  }

  bool _coprocessPatternMatches(String pattern, String input) {
    final trimmedPattern = pattern.trim();
    if (trimmedPattern.isEmpty) {
      return false;
    }
    try {
      return RegExp(trimmedPattern, caseSensitive: false).hasMatch(input);
    } on FormatException {
      return input.toLowerCase().contains(trimmedPattern.toLowerCase());
    }
  }

  void _startCoprocess(String sessionId, _CoprocessStartRequest request) {
    _coprocessInputKeysBySession[sessionId] = <String>{};
    setState(() {
      _coprocesses = <String, _ShellCoprocess>{
        ..._coprocesses,
        sessionId: _ShellCoprocess(
          command: request.command,
          pattern: request.pattern,
          response: request.response,
        ),
      };
    });
  }

  void _stopCoprocess(String sessionId) {
    if (!_coprocesses.containsKey(sessionId)) {
      _coprocessInputKeysBySession.remove(sessionId);
      return;
    }
    _coprocessInputKeysBySession.remove(sessionId);
    setState(() {
      _coprocesses = <String, _ShellCoprocess>{
        for (final entry in _coprocesses.entries)
          if (entry.key != sessionId) entry.key: entry.value,
      };
    });
  }

  void _runProfileTriggers(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    required int frameSequence,
  }) {
    final profile = _profileForSession(sessionId);
    if (profile == null || profile.triggers.isEmpty) {
      return;
    }
    final seenMatches = _triggerMatchesBySession.putIfAbsent(
      sessionId,
      () => <String>{},
    );
    for (final logicalRow in _logicalRows(frame.rows)) {
      final text = logicalRow.text;
      if (text.isEmpty) {
        continue;
      }
      for (final trigger in profile.triggers) {
        final regex = _regexForTrigger(trigger);
        if (regex == null) {
          continue;
        }
        if (!regex.hasMatch(text)) {
          continue;
        }
        final matchKey = _triggerMatchKey(
          trigger,
          logicalRow,
          frameScope: _frameDedupeScope(frame, frameSequence),
        );
        if (!seenMatches.add(matchKey)) {
          continue;
        }
        _recordCapturedOutput(sessionId, trigger, logicalRow);
        _runProfileTrigger(sessionId, trigger, text);
      }
    }
  }

  void _recordCapturedOutput(
    String sessionId,
    TerminalProfileTrigger trigger,
    _LogicalTerminalRow logicalRow,
  ) {
    final text = logicalRow.text.trimRight();
    if (text.trim().isEmpty) {
      return;
    }
    final entry = _CapturedOutputEntry(
      id: 'capture-${_nextCapturedOutputId++}',
      sessionId: sessionId,
      pattern: trigger.pattern,
      text: text,
      rowIndex: logicalRow.endRow.index,
    );
    setState(() {
      _capturedOutputEntries = <_CapturedOutputEntry>[
        entry,
        ..._capturedOutputEntries,
      ].take(_capturedOutputLimit).toList(growable: false);
    });
  }

  TerminalProfile? _profileForSession(String sessionId) {
    final state = ref.read(sessionControllerProvider);
    for (final tab in state.tabs) {
      final pane = tab.paneFor(sessionId);
      if (pane == null) {
        continue;
      }
      final snapshot = pane.profileSnapshot;
      if (snapshot != null) {
        return snapshot;
      }
      for (final profile in state.profiles) {
        if (profile.id == pane.profileId) {
          return profile;
        }
      }
      return null;
    }
    return null;
  }

  RegExp? _regexForTrigger(TerminalProfileTrigger trigger) {
    try {
      return RegExp(trigger.pattern, caseSensitive: trigger.caseSensitive);
    } on FormatException {
      return null;
    }
  }

  String _triggerMatchKey(
    TerminalProfileTrigger trigger,
    _LogicalTerminalRow logicalRow, {
    required String frameScope,
  }) {
    return [
      frameScope,
      trigger.pattern,
      trigger.action.name,
      trigger.value ?? '',
      trigger.caseSensitive,
      logicalRow.endRow.index,
      logicalRow.text,
    ].join('\u0000');
  }

  String _frameDedupeScope(
    terminal.TerminalFrameDiff frame,
    int frameSequence,
  ) {
    return frame.frameKind == terminal.TerminalFrameKind.delta
        ? 'delta:$frameSequence'
        : 'snapshot';
  }

  void _runProfileTrigger(
    String sessionId,
    TerminalProfileTrigger trigger,
    String rowText,
  ) {
    switch (trigger.action) {
      case TerminalProfileTriggerAction.notify:
        _sendShellNotification(
          title:
              'Trigger matched in ${_sessionTitleForNotification(sessionId)}',
          body: rowText.trim(),
          identifier:
              'flutterm.trigger.$sessionId.${trigger.pattern.hashCode}.${DateTime.now().microsecondsSinceEpoch}',
        );
      case TerminalProfileTriggerAction.sendText:
        final value = trigger.value;
        if (value == null || value.isEmpty) {
          return;
        }
        if (_isSessionReadOnly(sessionId)) {
          return;
        }
        ref
            .read(terminalRuntimeControllerProvider)
            .sendInput(sessionId, Uint8List.fromList(utf8.encode(value)));
    }
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
    for (final logicalRow in _logicalRows(frame.rows)) {
      final text = logicalRow.text.trim();
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
    if (_isToolbeltOpen) {
      return 'toolbelt';
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
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final usesMetaShortcuts =
        _usesMetaShortcuts || ref.read(referenceDemoModeProvider);
    final usesAppModifier = usesMetaShortcuts
        ? isMetaPressed && !isControlPressed
        : isControlPressed && !isMetaPressed;

    final resolvedBindings = LocalTerminalKeyBindingResolver.resolve(
      config: const LocalTerminalKeybindingsConfig(),
    );
    for (final binding in resolvedBindings) {
      final action = ShellActionRegistry.actions[binding.actionId];
      final defaultBinding = action?.defaultKeyBinding;
      if (defaultBinding == null) {
        continue;
      }
      if (binding.source != LocalTerminalKeyBindingSource.defaultBinding) {
        continue;
      }
      if (_shortcutEventMatchesDefaultBinding(
        event: event,
        binding: defaultBinding,
        usesMetaShortcuts: usesMetaShortcuts,
        isMetaPressed: isMetaPressed,
        isControlPressed: isControlPressed,
        isShiftPressed: isShiftPressed,
        isAltPressed: isAltPressed,
      )) {
        return _ShellShortcut(binding.actionId);
      }
    }

    if (usesAppModifier && !isShiftPressed && !isAltPressed) {
      final tabIndex = _tabShortcutIndexFor(event.logicalKey);
      if (tabIndex != null) {
        return _ShellShortcut(TerminalActionId.activateTab, tabIndex: tabIndex);
      }
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyP) {
      return const _ShellShortcut(TerminalActionId.openLauncher);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyD) {
      return const _ShellShortcut(TerminalActionId.splitDown);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      return const _ShellShortcut(TerminalActionId.copyMode);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      return const _ShellShortcut(TerminalActionId.pasteHistory);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyR) {
      return const _ShellShortcut(TerminalActionId.instantReplay);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return const _ShellShortcut(TerminalActionId.previousPrompt);
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return const _ShellShortcut(TerminalActionId.nextPrompt);
    }

    if (usesAppModifier && event.logicalKey == LogicalKeyboardKey.keyT) {
      return const _ShellShortcut(TerminalActionId.newTab);
    }

    return null;
  }

  bool _shortcutEventMatchesDefaultBinding({
    required KeyEvent event,
    required TerminalKeyBinding binding,
    required bool usesMetaShortcuts,
    required bool isMetaPressed,
    required bool isControlPressed,
    required bool isShiftPressed,
    required bool isAltPressed,
  }) {
    if (event.logicalKey != binding.key) {
      return false;
    }

    final appModifierMatches = binding.meta
        ? usesMetaShortcuts
              ? isMetaPressed && !isControlPressed
              : isControlPressed && !isMetaPressed
        : !isMetaPressed && !isControlPressed;

    return appModifierMatches &&
        isShiftPressed == binding.shift &&
        isAltPressed == binding.alt;
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

  EdgeInsets _terminalViewportPaddingFor(SessionState sessionState) {
    return EdgeInsets.all(sessionState.terminalViewportPadding);
  }

  Size _terminalContentSizeFor(
    BoxConstraints constraints,
    EdgeInsets terminalViewportPadding,
  ) {
    return Size(
      (constraints.maxWidth - terminalViewportPadding.horizontal)
          .clamp(1.0, double.infinity)
          .toDouble(),
      (constraints.maxHeight - terminalViewportPadding.vertical)
          .clamp(1.0, double.infinity)
          .toDouble(),
    );
  }

  String? _viewportStatusLabelFor(String? sessionId) {
    if (sessionId == null) {
      return null;
    }
    final viewportSize =
        _scheduledViewportSizes[sessionId] ??
        _committedViewportSizes[sessionId];
    final cellSize =
        _measuredTerminalCellSizes[sessionId] ??
        terminal.terminalFallbackCellSize;
    if (viewportSize == null || cellSize.width <= 0 || cellSize.height <= 0) {
      return null;
    }
    final cols = (viewportSize.width / cellSize.width).floor();
    final rows = (viewportSize.height / cellSize.height).floor();
    if (cols <= 0 || rows <= 0) {
      return null;
    }
    return '$cols×$rows';
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
      _isAutoComposerOpen = false;
      _isCopyModeOpen = false;
      _isToolbeltOpen = false;
      _searchQuery = '';
      _searchErrorText = null;
      _searchMatches = const [];
      _activeSearchIndex = 0;
      _autocompletePrefix = '';
      _autocompleteSuggestions = const [];
      _activeAutocompleteIndex = 0;
      _autoComposerController.clear();
      _autoComposerSuggestions = const [];
      _activeAutoComposerIndex = 0;
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

  TerminalTab? _tabForSession(SessionState sessionState, String? sessionId) {
    if (sessionId == null) {
      return null;
    }
    for (final tab in sessionState.tabs) {
      if (tab.containsSession(sessionId)) {
        return tab;
      }
    }
    return null;
  }

  bool _sessionHasRenderableContent(
    SessionController sessionController,
    String sessionId,
  ) {
    final viewport = sessionController.viewportFor(sessionId);
    if (viewport.frameVersion <= 0) {
      return false;
    }
    final frame = viewport.frame;
    if (frame.inlineImages.isNotEmpty) {
      return true;
    }
    for (final row in frame.rows) {
      if (row.text.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  String? _displayedSessionIdFor(
    SessionController sessionController,
    SessionState sessionState,
    String? activeSessionId,
  ) {
    if (activeSessionId == null) {
      _lastRenderableSessionId = null;
      return null;
    }
    final activeTab = _tabForSession(sessionState, activeSessionId);
    final retainedSessionId = _lastRenderableSessionId;
    final retainedTab = _tabForSession(sessionState, retainedSessionId);
    if (activeTab != null &&
        retainedTab != null &&
        activeTab.sessionId == retainedTab.sessionId) {
      _lastRenderableSessionId = activeSessionId;
      return activeSessionId;
    }
    if (_sessionHasRenderableContent(sessionController, activeSessionId)) {
      _lastRenderableSessionId = activeSessionId;
      return activeSessionId;
    }
    if (retainedSessionId != null &&
        retainedTab != null &&
        _sessionHasRenderableContent(sessionController, retainedSessionId)) {
      return retainedSessionId;
    }
    return null;
  }

  void _scheduleRenderableSessionSwap(String sessionId) {
    if (!mounted) {
      return;
    }
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == sessionId && _lastRenderableSessionId != sessionId) {
      setState(() {});
    }
  }

  bool _focusRelativePane(
    SessionController sessionController,
    TerminalTab activeTab,
    String activeSessionId, {
    required int delta,
  }) {
    final zoomedPaneSessionId = _zoomedPaneSessionId;
    final zoomedPane = zoomedPaneSessionId == null
        ? null
        : activeTab.paneFor(zoomedPaneSessionId);
    final panes = zoomedPane == null ? activeTab.effectivePanes : [zoomedPane];
    if (panes.length < 2) {
      return false;
    }
    final activeIndex = panes.indexWhere(
      (pane) => pane.sessionId == activeSessionId,
    );
    if (activeIndex < 0) {
      return false;
    }
    final nextIndex = (activeIndex + delta) % panes.length;
    final normalizedIndex = nextIndex < 0
        ? nextIndex + panes.length
        : nextIndex;
    _activateSession(sessionController, panes[normalizedIndex].sessionId);
    return true;
  }

  bool _growActivePane(TerminalTab activeTab, String activeSessionId) {
    final panes = activeTab.effectivePanes;
    if (panes.length < 2 || !activeTab.containsSession(activeSessionId)) {
      return false;
    }
    setState(() {
      for (final pane in panes) {
        _paneFlexBySession.putIfAbsent(pane.sessionId, () => 1);
      }
      _paneFlexBySession[activeSessionId] =
          (_paneFlexBySession[activeSessionId] ?? 1) + 1;
    });
    return true;
  }

  bool _isSessionReadOnly(String sessionId) {
    return _readOnlySessionIds.contains(sessionId);
  }

  String _visibleFrameText(String sessionId) {
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    final lines = <String>[
      for (final row in _logicalRows(frame.rows)) row.text.trimRight(),
    ];
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
  }

  Future<File?> _exportVisibleFrame(String sessionId) async {
    final historicalContent = ref
        .read(terminalRuntimeControllerProvider)
        .exportScrollbackText(sessionId);
    final hasHistoricalContent =
        historicalContent != null && historicalContent.trim().isNotEmpty;
    final content = hasHistoricalContent
        ? historicalContent
        : _visibleFrameText(sessionId);
    if (content.trim().isEmpty) {
      return null;
    }
    final supportDirectory = await getApplicationSupportDirectory();
    final exportDirectory = Directory(
      '${supportDirectory.path}/scrollback_exports',
    );
    final basename =
        'visible-scrollback-${DateTime.now().millisecondsSinceEpoch}';
    return LocalTerminalScrollbackExporter.write(
      directory: exportDirectory,
      basename: basename,
      export: LocalTerminalScrollbackExport(
        format: LocalTerminalExportFormat.plainText,
        content: content,
        metadata: <String, Object?>{
          'sessionId': sessionId,
          'scope': hasHistoricalContent
              ? 'historical-scrollback'
              : 'visible-frame',
          'capturedAt': DateTime.now().toIso8601String(),
        },
      ),
      policy: const LocalTerminalScrollbackExportPolicy(),
    );
  }

  void _toggleReadOnlySession(String sessionId) {
    setState(() {
      if (!_readOnlySessionIds.add(sessionId)) {
        _readOnlySessionIds.remove(sessionId);
      }
    });
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

  _SessionBadgeContent? _sessionBadgeForPane(
    TerminalPane pane,
    TerminalProfile? profile,
  ) {
    final integration = pane.shellIntegration;
    final hasShellData =
        integration.username != null ||
        integration.hostname != null ||
        integration.currentDirectory != null ||
        integration.lastCommand != null ||
        integration.shell != null;
    if (!hasShellData) {
      return null;
    }

    final identity = _sessionIdentityLabel(integration);
    final directory = integration.currentDirectory == null
        ? null
        : _compactSessionPath(integration.currentDirectory!);
    final title = identity ?? profile?.name ?? pane.title;
    final detail =
        directory ?? integration.shell ?? profile?.name ?? pane.title;
    final status = _sessionStatusLabel(integration);
    return _SessionBadgeContent(title: title, detail: detail, status: status);
  }

  String? _sessionIdentityLabel(TerminalShellIntegrationSnapshot integration) {
    final username = integration.username;
    final hostname = integration.hostname;
    if (username != null && hostname != null) {
      return '$username@$hostname';
    }
    return username ?? hostname;
  }

  String? _sessionStatusLabel(TerminalShellIntegrationSnapshot integration) {
    final command = integration.lastCommand;
    if (command == null) {
      return integration.shell;
    }
    final exitCode = integration.lastExitCode;
    if (exitCode == null) {
      return _compactSessionCommand(command);
    }
    final status = exitCode == 0 ? 'ok' : 'exit $exitCode';
    return '${_compactSessionCommand(command)} $status';
  }

  String _compactSessionCommand(String command) {
    const maxLength = 34;
    final normalized = command.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }

  String _compactSessionPath(String path) {
    const maxLength = 34;
    final normalized = path.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    final tail = segments.length <= 2
        ? normalized.substring(normalized.length - (maxLength - 3))
        : segments.skip(segments.length - 2).join('/');
    final compact = '.../$tail';
    return compact.length <= maxLength
        ? compact
        : compact.substring(compact.length - maxLength);
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

  List<_TerminalAnnotation> _annotationsForSession(String sessionId) {
    return [
      for (final annotation in _annotations)
        if (annotation.sessionId == sessionId) annotation,
    ];
  }

  Future<void> _openAnnotations(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) async {
    final selectedText = _selectionTextForSession(
      sessionController,
      sessionId,
      selectionController,
    ).trimRight();
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _AnnotationsSheet(
          entries: _annotationsForSession(sessionId),
          selectedText: selectedText,
          onAdd: (note) => _addAnnotation(
            sessionId: sessionId,
            selectedText: selectedText,
            note: note,
          ),
          onRemove: _removeAnnotation,
        );
      },
    );
  }

  _TerminalAnnotation _addAnnotation({
    required String sessionId,
    required String selectedText,
    required String note,
  }) {
    final annotation = _TerminalAnnotation(
      id: 'annotation-${_nextAnnotationId++}',
      sessionId: sessionId,
      selectedText: selectedText.trimRight(),
      note: note.trim(),
    );
    setState(() {
      _annotations = [annotation, ..._annotations];
    });
    return annotation;
  }

  void _removeAnnotation(String annotationId) {
    setState(() {
      _annotations = [
        for (final annotation in _annotations)
          if (annotation.id != annotationId) annotation,
      ];
    });
  }

  List<_CapturedOutputEntry> _capturedOutputForSession(String sessionId) {
    return [
      for (final entry in _capturedOutputEntries)
        if (entry.sessionId == sessionId) entry,
    ];
  }

  Future<void> _openCapturedOutput(String sessionId) async {
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _CapturedOutputSheet(
          entries: _capturedOutputForSession(sessionId),
          onClear: () => _clearCapturedOutput(sessionId),
          onCopy: (text) => unawaited(ClipboardBridge.copy(text)),
        );
      },
    );
  }

  void _clearCapturedOutput(String sessionId) {
    if (!mounted) {
      _capturedOutputEntries = [
        for (final entry in _capturedOutputEntries)
          if (entry.sessionId != sessionId) entry,
      ];
      return;
    }
    setState(() {
      _capturedOutputEntries = [
        for (final entry in _capturedOutputEntries)
          if (entry.sessionId != sessionId) entry,
      ];
    });
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
    final decision = LocalTerminalPasteDecisionResolver.resolve(
      text: text,
      readOnly: _isSessionReadOnly(sessionId),
      pastePolicy: const LocalTerminalPastePolicy(),
      historyPolicy: const LocalTerminalPasteHistoryPolicy(),
    );
    switch (decision.kind) {
      case LocalTerminalPasteDecisionKind.blockedReadOnly:
        _focusSession(sessionId);
        return;
      case LocalTerminalPasteDecisionKind.requireConfirmation:
        final confirmed = await _confirmPaste(decision);
        if (!confirmed) {
          _focusSession(sessionId);
          return;
        }
      case LocalTerminalPasteDecisionKind.sendImmediately:
        break;
    }
    await _pasteTextToSession(sessionId, decision.text);
    if (decision.captureHistory) {
      await _recordPasteHistory(decision.text, PasteHistoryKind.paste);
    }
  }

  Future<bool> _confirmPaste(LocalTerminalPasteDecision decision) async {
    final lineCount = _lineCountForPasteConfirmation(decision.text);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const Key('paste-confirmation-dialog'),
          title: const Text('Confirm paste'),
          content: Text(
            'Paste ${decision.text.length} characters across $lineCount lines?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Paste'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  int _lineCountForPasteConfirmation(String text) {
    if (text.isEmpty) {
      return 0;
    }
    return RegExp(r'\r\n|\r|\n').allMatches(text).length + 1;
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
    if (_isSessionReadOnly(sessionId)) {
      return;
    }
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

  bool _sendPlainTextToSession(String sessionId, String text) {
    if (text.isEmpty) {
      return false;
    }
    if (_isSessionReadOnly(sessionId)) {
      return false;
    }
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(sessionId, Uint8List.fromList(utf8.encode(text)));
    _focusSession(sessionId);
    return true;
  }

  String _shellQuotedPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return "''";
    }
    if (RegExp(r'^[A-Za-z0-9_./:@%+=,-]+$').hasMatch(trimmed)) {
      return trimmed;
    }
    return "'${trimmed.replaceAll("'", r"'\''")}'";
  }

  Future<void> _openShellIntegrationUtilities(
    SessionState sessionState,
    String sessionId,
  ) async {
    final pane = _paneForSession(sessionState, sessionId);
    if (pane == null) {
      return;
    }
    final integration = pane.shellIntegration;
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _ShellIntegrationUtilitiesSheet(
          integration: integration,
          onInsertCommand: (command) {
            _sendPlainTextToSession(sessionId, command);
          },
          onChangeDirectory: (directory) {
            _sendPlainTextToSession(
              sessionId,
              'cd ${_shellQuotedPath(directory)}',
            );
          },
          onJumpToMark: (mark) {
            ref
                .read(terminalRuntimeControllerProvider)
                .scrollViewportTo(sessionId, mark.scrollbackOffset);
            _focusSession(sessionId);
          },
        );
      },
    );
  }

  bool _tmuxControlModeActive(String sessionId) {
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    return _frameLooksLikeTmuxControlMode(frame);
  }

  bool _frameLooksLikeTmuxControlMode(terminal.TerminalFrameDiff frame) {
    var sawModeBanner = false;
    var sawCommandMenu = false;
    for (final row in frame.rows) {
      final text = row.text.trim();
      if (text.contains('tmux mode started') ||
          text.startsWith('%window-add') ||
          text.startsWith('%session-changed')) {
        sawModeBanner = true;
      }
      if (text.contains('Detach cleanly') ||
          text.contains('Force-quit tmux mode') ||
          text == 'Command Menu') {
        sawCommandMenu = true;
      }
    }
    return sawModeBanner && sawCommandMenu;
  }

  Future<void> _openTmuxIntegration(String sessionId) async {
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _TmuxIntegrationSheet(
          controlModeDetected: _tmuxControlModeActive(sessionId),
          onSendCommand: (command) {
            _sendPlainTextToSession(sessionId, command);
          },
        );
      },
    );
  }

  Future<void> _openCoprocess(String sessionId) async {
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _CoprocessSheet(
          activeCoprocess: _coprocesses[sessionId],
          onStart: (request) => _startCoprocess(sessionId, request),
          onStop: () => _stopCoprocess(sessionId),
        );
      },
    );
  }

  Future<void> _openAdvancedPaste(String sessionId) async {
    final clipboardText = await ClipboardBridge.paste();
    if (!mounted) {
      return;
    }

    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<_AdvancedPasteSheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _AdvancedPasteSheet(initialText: clipboardText);
      },
    );

    if (!mounted || !_sessionExists(sessionId)) {
      return;
    }

    switch (result) {
      case _AdvancedPasteSendResult(:final text):
        if (text.isEmpty) {
          return;
        }
        await _pasteTextToSession(sessionId, text);
        await _recordPasteHistory(text, PasteHistoryKind.paste);
        return;
      case null:
        return;
    }
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

  Future<void> _openPasswordManager(
    SessionController sessionController,
    String sessionId,
  ) async {
    final store = ref.read(passwordManagerStoreProvider);
    final frame = sessionController.viewportFor(sessionId).frame;
    final promptDetected = _frameHasPasswordPrompt(frame);
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<_PasswordManagerSheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _PasswordManagerSheet(
          entries: store.entries,
          promptDetected: promptDetected,
          onAdd: store.add,
          onRemove: store.remove,
        );
      },
    );

    if (!mounted) {
      return;
    }
    switch (result) {
      case _PasswordManagerSendResult(:final entry):
        final latestFrame = sessionController.viewportFor(sessionId).frame;
        if (!_frameHasPasswordPrompt(latestFrame)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Password send blocked: no password prompt is active.',
              ),
            ),
          );
          return;
        }
        _sendPasswordToSession(sessionId, entry);
        return;
      case null:
        return;
    }
  }

  void _sendPasswordToSession(String sessionId, PasswordManagerEntry entry) {
    if (_isSessionReadOnly(sessionId)) {
      return;
    }
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(
          sessionId,
          Uint8List.fromList(utf8.encode('${entry.password}\n')),
        );
  }

  bool _frameHasPasswordPrompt(terminal.TerminalFrameDiff frame) {
    for (final logicalRow in _logicalRows(frame.rows).reversed) {
      final text = logicalRow.text.trimRight();
      if (text.isEmpty) {
        continue;
      }
      if (_passwordPromptPattern.hasMatch(text)) {
        return true;
      }
      return false;
    }
    return false;
  }

  List<_LogicalTerminalRow> _logicalRows(List<terminal.TerminalRow> rows) {
    final logicalRows = <_LogicalTerminalRow>[];
    var start = 0;
    while (start < rows.length) {
      final buffer = StringBuffer(rows[start].text);
      var end = start;
      while (end < rows.length - 1 && rows[end].wrapped) {
        end += 1;
        buffer.write(rows[end].text);
      }
      logicalRows.add(
        _LogicalTerminalRow(
          startRow: rows[start],
          endRow: rows[end],
          text: buffer.toString(),
        ),
      );
      start = end + 1;
    }
    return logicalRows;
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
      _searchUseRegex = false;
    });
  }

  void _searchScrollback(String query) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    String? errorText;
    final matches = _searchUseRegex
        ? _regexSearchVisibleFrame(
            activeSessionId,
            query,
            onError: () {
              errorText = 'Invalid regular expression';
            },
          )
        : ref
              .read(terminalRuntimeControllerProvider)
              .searchText(activeSessionId, query);
    setState(() {
      _searchQuery = query;
      _searchErrorText = errorText;
      _searchMatches = matches;
      _activeSearchIndex = 0;
    });
    if (matches.isNotEmpty) {
      ref
          .read(terminalRuntimeControllerProvider)
          .scrollViewportTo(activeSessionId, matches.first.scrollbackOffset);
    }
  }

  List<TerminalSearchMatch> _regexSearchVisibleFrame(
    String sessionId,
    String query, {
    VoidCallback? onError,
  }) {
    if (query.isEmpty) {
      return const <TerminalSearchMatch>[];
    }
    final RegExp expression;
    try {
      expression = RegExp(query);
    } on FormatException {
      onError?.call();
      return const <TerminalSearchMatch>[];
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    final matches = <TerminalSearchMatch>[];
    for (final row in frame.rows) {
      final absoluteRow = frame.viewportStartRow + row.index;
      if (absoluteRow < frame.viewportStartRow ||
          absoluteRow >= frame.viewportStartRow + frame.viewportRows) {
        continue;
      }
      for (final match in expression.allMatches(row.text)) {
        final text = match.group(0) ?? '';
        final startCol = terminal.TerminalTextCells.fromText(
          row.text.substring(0, match.start),
        ).cellCount;
        final endCol = terminal.TerminalTextCells.fromText(
          row.text.substring(0, match.end),
        ).cellCount;
        matches.add(
          TerminalSearchMatch(
            row: absoluteRow,
            startCol: startCol,
            endCol: endCol,
            text: text,
            scrollbackOffset: (frame.scrollbackMaxOffset - absoluteRow).clamp(
              0,
              frame.scrollbackMaxOffset,
            ),
          ),
        );
      }
    }
    return matches;
  }

  void _setSearchRegexEnabled(bool value) {
    if (_searchUseRegex == value) {
      return;
    }
    setState(() {
      _searchUseRegex = value;
      _searchErrorText = null;
      _searchMatches = const [];
      _activeSearchIndex = 0;
    });
    if (_searchQuery.isNotEmpty) {
      _searchScrollback(_searchQuery);
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
      _searchUseRegex = false;
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
    final sessionState = ref.read(sessionControllerProvider);
    final activeSessionId = sessionState.activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(activeSessionId)
        .frame;
    final prefix = _autocompletePrefixForFrame(frame);
    final suggestions = _mergeAutocompleteSuggestions([
      _shellCommandAutocompleteSuggestions(
        sessionState,
        activeSessionId,
        prefix,
      ),
      _autocompleteSuggestionsForFrame(frame, prefix),
    ]);
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

  List<String> _shellCommandAutocompleteSuggestions(
    SessionState sessionState,
    String sessionId,
    String prefix,
  ) {
    final pane = _paneForSession(sessionState, sessionId);
    if (pane == null) {
      return const <String>[];
    }
    final normalizedPrefix = prefix.toLowerCase();
    final seen = <String>{};
    final suggestions = <String>[];
    final wordPattern = RegExp(r'[A-Za-z0-9_./:-]{2,}');
    for (final command in pane.shellIntegration.recentCommands) {
      final normalizedCommand = command.toLowerCase();
      if (command != prefix &&
          command.length > prefix.length &&
          (normalizedPrefix.isEmpty ||
              normalizedCommand.startsWith(normalizedPrefix)) &&
          seen.add(normalizedCommand)) {
        suggestions.add(command);
        if (suggestions.length >= 8) {
          return suggestions;
        }
      }
      for (final match in wordPattern.allMatches(command)) {
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

  List<String> _mergeAutocompleteSuggestions(List<List<String>> groups) {
    final seen = <String>{};
    final merged = <String>[];
    for (final group in groups) {
      for (final suggestion in group) {
        if (!seen.add(suggestion.toLowerCase())) {
          continue;
        }
        merged.add(suggestion);
        if (merged.length >= 8) {
          return merged;
        }
      }
    }
    return merged;
  }

  TerminalPane? _paneForSession(SessionState sessionState, String sessionId) {
    for (final tab in sessionState.tabs) {
      final pane = tab.paneFor(sessionId);
      if (pane != null) {
        return pane;
      }
    }
    return null;
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

  bool _selectLastCommandOutput(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) {
    final pane = _paneForSession(
      ref.read(sessionControllerProvider),
      sessionId,
    );
    final promptMarks = pane?.shellIntegration.promptMarks;
    if (promptMarks == null || promptMarks.length < 2) {
      return false;
    }
    final startMark = promptMarks[promptMarks.length - 2];
    final endMark = promptMarks.last;
    final startRow = startMark.scrollbackOffset + 1;
    final endRow = endMark.scrollbackOffset - 1;
    if (endRow < startRow) {
      return false;
    }
    final frame = sessionController.viewportFor(sessionId).frame;
    selectionController.setSelection(
      terminal.TerminalSelection(
        startRow: startRow,
        startCol: 0,
        endRow: endRow,
        endCol: _rowEndColumn(frame, endRow),
      ),
    );
    _focusSession(sessionId);
    return true;
  }

  int _rowEndColumn(terminal.TerminalFrameDiff frame, int rowIndex) {
    for (final row in frame.rows) {
      if (row.index == rowIndex) {
        return terminal.TerminalTextCells.fromText(row.text).cellCount;
      }
    }
    return frame.viewportCols;
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
      _sendPlainTextToSession(activeSessionId, suffix);
    }
    _closeAutocomplete();
  }

  void _openAutoComposer() {
    final sessionState = ref.read(sessionControllerProvider);
    final activeSessionId = sessionState.activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    _autoComposerController.clear();
    final suggestions = _autoComposerSuggestionsForText('', sessionState);
    setState(() {
      _isAutoComposerOpen = true;
      _isSearchOpen = false;
      _isAutocompleteOpen = false;
      _isCopyModeOpen = false;
      _autoComposerSuggestions = suggestions;
      _activeAutoComposerIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isAutoComposerOpen) {
        return;
      }
      _autoComposerFocusNode.requestFocus();
    });
  }

  void _closeAutoComposer() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    setState(() {
      _isAutoComposerOpen = false;
      _autoComposerSuggestions = const [];
      _activeAutoComposerIndex = 0;
    });
    _focusSession(activeSessionId);
  }

  void _updateAutoComposerSuggestions(String text) {
    final suggestions = _autoComposerSuggestionsForText(text);
    setState(() {
      _autoComposerSuggestions = suggestions;
      _activeAutoComposerIndex = 0;
    });
  }

  List<String> _autoComposerSuggestionsForText(
    String text, [
    SessionState? sessionState,
  ]) {
    final SessionState state =
        sessionState ?? ref.read(sessionControllerProvider);
    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      return const <String>[];
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(activeSessionId)
        .frame;
    final prefix = _autoComposerPrefixForText(text);
    return _mergeAutocompleteSuggestions([
      _shellCommandAutocompleteSuggestions(state, activeSessionId, prefix),
      _autocompleteSuggestionsForFrame(frame, prefix),
    ]);
  }

  String _autoComposerPrefixForText(String text) {
    return RegExp(r'[A-Za-z0-9_./:-]+$').firstMatch(text)?.group(0) ?? '';
  }

  void _moveAutoComposerSuggestion(int delta) {
    if (_autoComposerSuggestions.isEmpty) {
      return;
    }
    final nextIndex =
        (_activeAutoComposerIndex + delta) % _autoComposerSuggestions.length;
    setState(() {
      _activeAutoComposerIndex = nextIndex < 0
          ? nextIndex + _autoComposerSuggestions.length
          : nextIndex;
    });
  }

  void _acceptAutoComposerSuggestion(String suggestion) {
    final currentText = _autoComposerController.text;
    final prefix = _autoComposerPrefixForText(currentText);
    final nextText = prefix.isEmpty
        ? suggestion
        : '${currentText.substring(0, currentText.length - prefix.length)}'
              '$suggestion';
    _autoComposerController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    _updateAutoComposerSuggestions(nextText);
    _autoComposerFocusNode.requestFocus();
  }

  void _sendAutoComposerCommand() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final command = _autoComposerController.text.trimRight();
    if (command.isEmpty) {
      return;
    }
    if (!_sendPlainTextToSession(activeSessionId, '$command\n')) {
      return;
    }
    _autoComposerController.clear();
    _closeAutoComposer();
  }

  void _navigateShellPrompt(String sessionId, {required int direction}) {
    final sessionState = ref.read(sessionControllerProvider);
    final pane = _paneForSession(sessionState, sessionId);
    final promptMarks = pane?.shellIntegration.promptMarks;
    if (promptMarks == null || promptMarks.isEmpty) {
      return;
    }

    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    final target = _shellPromptNavigationTarget(
      promptMarks,
      frame.scrollbackOffset,
      direction: direction,
    );
    if (target == null) {
      return;
    }

    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(sessionId, target.scrollbackOffset);
    _focusSession(sessionId);
  }

  TerminalShellPromptMark? _shellPromptNavigationTarget(
    List<TerminalShellPromptMark> marks,
    int currentOffset, {
    required int direction,
  }) {
    if (direction < 0) {
      for (final mark in marks) {
        if (mark.scrollbackOffset > currentOffset) {
          return mark;
        }
      }
      return marks.last;
    }

    for (final mark in marks.reversed) {
      if (mark.scrollbackOffset < currentOffset) {
        return mark;
      }
    }
    return marks.first;
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
      barrierColor: Colors.black.withValues(alpha: 0.34),
      barrierDismissible: true,
      requestFocus: true,
      animationStyle: animationsEnabled ? null : AnimationStyle.noAnimation,
      builder: (dialogContext) => DefaultsAndAppearanceDialog(
        profiles: sessionState.profiles,
        configuredDefaultProfileId: sessionState.configuredDefaultProfileId,
        effectiveDefaultProfileId: sessionState.defaultProfileId,
        themeMode: sessionState.themeMode,
        terminalViewportPadding: sessionState.terminalViewportPadding,
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
      if (selection.terminalViewportPadding !=
          stateBeforeSave.terminalViewportPadding) {
        await sessionController.setTerminalViewportPadding(
          selection.terminalViewportPadding,
        );
      }
      final updatedProfile = selection.updatedProfile;
      if (updatedProfile != null) {
        await sessionController.saveProfile(updatedProfile);
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
    final result = await showModalBottomSheet<ProfilesSheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return ProfilesSheet(
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
      case OpenProfileResult(:final profile):
        _createSession(
          sessionController,
          profile,
          returningToWorkspace: activeSessionIdBeforeOpen == null,
        );
        return;
      case EditProfileResult(:final profile):
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
      case CreateProfileResult():
        final edited = await showDialog<TerminalProfile>(
          context: context,
          builder: (dialogContext) => ProfileEditorDialog(
            initialValue: _newProfileTemplate(sessionState.profiles),
          ),
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

  TerminalProfile _newProfileTemplate(List<TerminalProfile> existingProfiles) {
    final existingIds = {for (final profile in existingProfiles) profile.id};
    var suffix = 1;
    var id = 'profile-$suffix';
    while (existingIds.contains(id)) {
      suffix += 1;
      id = 'profile-$suffix';
    }
    return defaultTerminalProfile().copyWith(id: id, name: 'New Profile');
  }

  Future<void> _openDynamicProfiles(SessionController sessionController) async {
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<DynamicProfilesImportResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) => const DynamicProfilesSheet(),
    );
    if (!mounted || result == null) {
      return;
    }
    for (final profile in result.profiles) {
      await sessionController.saveProfile(profile);
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported ${result.profiles.length} dynamic profile${result.profiles.length == 1 ? '' : 's'}'
          '${result.warningCount == 0 ? '' : ' with ${result.warningCount} warning${result.warningCount == 1 ? '' : 's'}'}',
        ),
      ),
    );
  }

  ShellActionProductionRuntimeAdapter _buildScopedProductionActionAdapter({
    required Set<String> requiredActionNames,
    required ShellActionProductionCallbacks callbacks,
  }) {
    return ShellActionProductionRuntimeAdapter.fromCallbacks(
      actionSet: ShellActionProductionActionSet(
        requiredActionNames: requiredActionNames,
      ),
      callbacks: callbacks,
    );
  }

  Future<bool> _executeProductionActionIfBound({
    required ShellActionProductionRuntimeAdapter adapter,
    required TerminalActionId action,
  }) async {
    if (!adapter.isReady) {
      return false;
    }
    if (!adapter.executor.wiringState.bindings.contains(action)) {
      return false;
    }
    final result = await adapter.executor.execute(action);
    return result.completed;
  }

  bool _dispatchProductionShortcutIfBound({
    required ShellActionProductionRuntimeAdapter adapter,
    required TerminalActionId action,
  }) {
    if (!adapter.isReady) {
      return false;
    }
    if (!adapter.executor.wiringState.bindings.contains(action)) {
      return false;
    }
    unawaited(adapter.executor.execute(action));
    return true;
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
    final activePaneBeforeOpen = activeSessionIdBeforeOpen == null
        ? null
        : _paneForSession(sessionState, activeSessionIdBeforeOpen);
    final isActiveSessionReadOnly =
        activeSessionIdBeforeOpen != null &&
        _isSessionReadOnly(activeSessionIdBeforeOpen);
    final canSelectCommandOutput =
        (activePaneBeforeOpen?.shellIntegration.promptMarks.length ?? 0) >= 2;
    final activePaneZoomed =
        activeSessionIdBeforeOpen != null &&
        _zoomedPaneSessionId == activeSessionIdBeforeOpen;
    final action = await showGeneralDialog<TerminalActionId>(
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
                  hotkeyWindowShortcutLabel: _hotkeyWindowShortcutLabel(),
                  autocompleteShortcutLabel: _autocompleteShortcutLabel(),
                  copyModeShortcutLabel: _copyModeShortcutLabel(),
                  sessionCopyShortcutLabel: _sessionCopyShortcutLabel(),
                  sessionPasteShortcutLabel: _sessionPasteShortcutLabel(),
                  pasteHistoryShortcutLabel: _pasteHistoryShortcutLabel(),
                  instantReplayShortcutLabel: _instantReplayShortcutLabel(),
                  hasDefaultProfile: defaultProfile != null,
                  hasActiveSession: hasActiveSession,
                  activePaneZoomed: activePaneZoomed,
                  canReopenClosedTab: sessionController.canReopenClosedTab,
                  isActiveSessionReadOnly: isActiveSessionReadOnly,
                  commandFinishedNotificationsEnabled:
                      _commandFinishedNotificationsEnabled,
                  bellNotificationsEnabled: _bellNotificationsEnabled,
                  activityMonitorEnabled: _activityNotificationsEnabled,
                  canSelectCommandOutput: canSelectCommandOutput,
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
                    hotkeyWindowShortcutLabel: _hotkeyWindowShortcutLabel(),
                    autocompleteShortcutLabel: _autocompleteShortcutLabel(),
                    copyModeShortcutLabel: _copyModeShortcutLabel(),
                    sessionCopyShortcutLabel: _sessionCopyShortcutLabel(),
                    sessionPasteShortcutLabel: _sessionPasteShortcutLabel(),
                    pasteHistoryShortcutLabel: _pasteHistoryShortcutLabel(),
                    instantReplayShortcutLabel: _instantReplayShortcutLabel(),
                    hasDefaultProfile: defaultProfile != null,
                    hasActiveSession: hasActiveSession,
                    activePaneZoomed: activePaneZoomed,
                    canReopenClosedTab: sessionController.canReopenClosedTab,
                    isActiveSessionReadOnly: isActiveSessionReadOnly,
                    commandFinishedNotificationsEnabled:
                        _commandFinishedNotificationsEnabled,
                    bellNotificationsEnabled: _bellNotificationsEnabled,
                    activityMonitorEnabled: _activityNotificationsEnabled,
                    canSelectCommandOutput: canSelectCommandOutput,
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
    final productionMenuAdapter = _buildScopedProductionActionAdapter(
      requiredActionNames: const {
        'newTab',
        'closeTab',
        'reopenClosedTab',
        'duplicateCurrentCwd',
        'toolbelt',
        'splitRight',
        'splitDown',
        'closePane',
        'focusNextPane',
        'focusPreviousPane',
        'resizePane',
        'swapPane',
        'zoomPane',
        'copy',
        'copyCommandOutput',
        'copyMode',
        'paste',
        'advancedPaste',
        'pasteHistory',
        'instantReplay',
        'toggleReadOnly',
        'clearScrollback',
        'globalSearch',
        'autocomplete',
        'autoComposer',
        'searchScrollback',
        'previousPrompt',
        'nextPrompt',
        'selectCommandOutput',
        'shellIntegrationUtilities',
        'openRecentDirectory',
        'tmuxIntegration',
        'coprocess',
        'annotations',
        'capturedOutput',
        'passwordManager',
        'toggleHotkeyWindow',
        'openDefaults',
        'defaults',
        'profiles',
        'dynamicProfiles',
        'openThemePicker',
        'applyLayoutTemplate',
        'exportScrollback',
        'toggleCommandFinishedNotify',
        'toggleBellNotify',
        'toggleActivityMonitor',
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
            returningToWorkspace: activeSessionIdBeforeOpen == null,
          );
          return const ShellActionBindingResult.completed();
        },
        closeTab: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Close tab requires an active session.',
            );
          }
          _closeSession(sessionController, currentState, currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        duplicateCurrentCwd: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Duplicate current directory requires a default profile and active session.',
            );
          }
          final currentPane = _paneForSession(currentState, currentSessionId);
          final currentDirectory =
              currentPane?.shellIntegration.currentDirectory;
          if (currentDirectory == null || currentDirectory.isEmpty) {
            return const ShellActionBindingResult.skipped(
              'No current directory is available to duplicate.',
            );
          }
          _createSession(
            sessionController,
            defaultProfile,
            returningToWorkspace: activeSessionIdBeforeOpen == null,
          );
          final duplicateSessionId = ref
              .read(sessionControllerProvider)
              .activeSessionId;
          if (duplicateSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'No duplicated session was created.',
            );
          }
          _sendPlainTextToSession(
            duplicateSessionId,
            'cd ${_shellQuotedPath(currentDirectory)}',
          );
          return const ShellActionBindingResult.completed();
        },
        reopenClosedTab: (_) {
          if (!sessionController.canReopenClosedTab) {
            return const ShellActionBindingResult.skipped(
              'No recently closed tab is available.',
            );
          }
          sessionController.reopenClosedTab();
          _focusSession(ref.read(sessionControllerProvider).activeSessionId);
          return const ShellActionBindingResult.completed();
        },
        closePane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Close pane requires an active session.',
            );
          }
          _closeSession(sessionController, currentState, currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        toolbelt: (_) {
          setState(() {
            _isToolbeltOpen = true;
          });
          return const ShellActionBindingResult.completed();
        },
        splitRight: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Split right requires a default profile and active session.',
            );
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.horizontal,
          );
          return const ShellActionBindingResult.completed();
        },
        splitDown: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Split down requires a default profile and active session.',
            );
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.vertical,
          );
          return const ShellActionBindingResult.completed();
        },
        focusNextPane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Focus next pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null ||
              !_focusRelativePane(
                sessionController,
                currentTab,
                currentSessionId,
                delta: 1,
              )) {
            return const ShellActionBindingResult.skipped(
              'No next pane is available.',
            );
          }
          return const ShellActionBindingResult.completed();
        },
        focusPreviousPane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Focus previous pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null ||
              !_focusRelativePane(
                sessionController,
                currentTab,
                currentSessionId,
                delta: -1,
              )) {
            return const ShellActionBindingResult.skipped(
              'No previous pane is available.',
            );
          }
          return const ShellActionBindingResult.completed();
        },
        resizePaneRight: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Resize pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null ||
              !_growActivePane(currentTab, currentSessionId)) {
            return const ShellActionBindingResult.skipped(
              'Resize pane requires at least two panes.',
            );
          }
          _focusSession(currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        swapPane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Swap pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if ((currentTab?.effectivePanes.length ?? 0) < 2) {
            return const ShellActionBindingResult.skipped(
              'Swap pane requires at least two panes.',
            );
          }
          sessionController.swapActivePaneWithSibling();
          _focusSession(currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        zoomPane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Zoom pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if ((currentTab?.effectivePanes.length ?? 0) < 2) {
            return const ShellActionBindingResult.skipped(
              'Zoom pane requires at least two panes.',
            );
          }
          setState(() {
            _zoomedPaneSessionId = _zoomedPaneSessionId == currentSessionId
                ? null
                : currentSessionId;
          });
          _focusSession(currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        copy: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Copy requires an active session.',
            );
          }
          final selectionController = _selectionControllers[currentSessionId];
          if (selectionController == null) {
            return const ShellActionBindingResult.skipped(
              'Copy requires an active selection controller.',
            );
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
          return const ShellActionBindingResult.completed();
        },
        copyCommandOutput: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Copy command output requires an active session.',
            );
          }
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          final selected = _selectLastCommandOutput(
            sessionController,
            currentSessionId,
            selectionController,
          );
          if (!selected) {
            _restoreSessionFocus(
              activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
              activeSessionIdAfterClose: currentSessionId,
            );
            return const ShellActionBindingResult.skipped(
              'No command output is available to copy.',
            );
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
          return const ShellActionBindingResult.completed();
        },
        copyMode: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Copy mode requires an active session.',
            );
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
          return const ShellActionBindingResult.completed();
        },
        paste: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Paste requires an active session.',
            );
          }
          await _pasteToSession(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        advancedPaste: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Advanced paste requires an active session.',
            );
          }
          await _openAdvancedPaste(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        pasteHistory: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Paste history requires an active session.',
            );
          }
          await _openPasteHistory(sessionState);
          return const ShellActionBindingResult.completed();
        },
        instantReplay: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Instant replay requires an active session.',
            );
          }
          await _openInstantReplay(sessionState);
          return const ShellActionBindingResult.completed();
        },
        toggleReadOnly: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Read-only mode requires an active session.',
            );
          }
          _toggleReadOnlySession(currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        clearScrollback: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Clear scrollback requires an active session.',
            );
          }
          final cleared = ref
              .read(terminalRuntimeControllerProvider)
              .clearScrollback(currentSessionId);
          if (!cleared && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Clear scrollback requires native runtime support.',
                ),
              ),
            );
          }
          return ShellActionBindingResult.completed(
            cleared
                ? 'Cleared scrollback.'
                : 'Clear scrollback is not supported by this runtime.',
          );
        },
        globalSearch: (_) async {
          if (sessionState.tabs.isEmpty) {
            return const ShellActionBindingResult.skipped(
              'Global search requires at least one tab.',
            );
          }
          await _openGlobalSearch(sessionState);
          return const ShellActionBindingResult.completed();
        },
        autocomplete: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Autocomplete requires an active session.',
            );
          }
          _openAutocomplete();
          return const ShellActionBindingResult.completed();
        },
        autoComposer: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Auto composer requires an active session.',
            );
          }
          _openAutoComposer();
          return const ShellActionBindingResult.completed();
        },
        searchScrollback: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Search requires an active session.',
            );
          }
          _openSearch();
          return const ShellActionBindingResult.completed();
        },
        previousPrompt: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Previous prompt requires an active session.',
            );
          }
          _navigateShellPrompt(currentSessionId, direction: -1);
          return const ShellActionBindingResult.completed();
        },
        nextPrompt: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Next prompt requires an active session.',
            );
          }
          _navigateShellPrompt(currentSessionId, direction: 1);
          return const ShellActionBindingResult.completed();
        },
        selectCommandOutput: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Select command output requires an active session.',
            );
          }
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          final selected = _selectLastCommandOutput(
            sessionController,
            currentSessionId,
            selectionController,
          );
          if (!selected) {
            _restoreSessionFocus(
              activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
              activeSessionIdAfterClose: currentSessionId,
            );
          }
          return const ShellActionBindingResult.completed();
        },
        shellIntegrationUtilities: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Shell integration utilities require an active session.',
            );
          }
          await _openShellIntegrationUtilities(currentState, currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        openRecentDirectory: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Open recent directory requires an active session.',
            );
          }
          final currentPane = _paneForSession(currentState, currentSessionId);
          final recentDirectories =
              currentPane?.shellIntegration.recentDirectories ?? const [];
          if (recentDirectories.isEmpty) {
            return const ShellActionBindingResult.skipped(
              'No recent directory is available.',
            );
          }
          _sendPlainTextToSession(
            currentSessionId,
            'cd ${_shellQuotedPath(recentDirectories.first)}',
          );
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        tmuxIntegration: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'tmux integration requires an active session.',
            );
          }
          await _openTmuxIntegration(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        coprocess: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Coprocess requires an active session.',
            );
          }
          await _openCoprocess(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        annotations: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Annotations require an active session.',
            );
          }
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          await _openAnnotations(
            sessionController,
            currentSessionId,
            selectionController,
          );
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        capturedOutput: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Captured output requires an active session.',
            );
          }
          await _openCapturedOutput(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        passwordManager: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Password manager requires an active session.',
            );
          }
          await _openPasswordManager(sessionController, currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
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
        defaults: (_) async {
          await _openDefaultsAndAppearance(sessionController, sessionState);
          return const ShellActionBindingResult.completed();
        },
        profiles: (_) async {
          await _openProfilesSheet(sessionController, sessionState);
          return const ShellActionBindingResult.completed();
        },
        dynamicProfiles: (_) async {
          await _openDynamicProfiles(sessionController);
          return const ShellActionBindingResult.completed();
        },
        openThemePicker: (_) async {
          await _openDefaultsAndAppearance(sessionController, sessionState);
          return const ShellActionBindingResult.completed();
        },
        applyLayoutTemplate: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Apply layout template requires a default profile and active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null) {
            return const ShellActionBindingResult.skipped(
              'No active tab is available for layout templates.',
            );
          }
          if (currentTab.effectivePanes.length > 1) {
            return const ShellActionBindingResult.skipped(
              'Two-pane layout template is already satisfied.',
            );
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.horizontal,
          );
          return const ShellActionBindingResult.completed();
        },
        exportScrollback: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Export scrollback requires an active session.',
            );
          }
          final file = await _exportVisibleFrame(currentSessionId);
          if (file == null) {
            return const ShellActionBindingResult.skipped(
              'No visible terminal content is available to export.',
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Exported terminal scrollback to ${file.path}'),
              ),
            );
          }
          return const ShellActionBindingResult.completed(
            'Exported terminal scrollback.',
          );
        },
        toggleCommandFinishedNotify: (_) {
          setState(() {
            _commandFinishedNotificationsEnabled =
                !_commandFinishedNotificationsEnabled;
          });
          unawaited(_saveNotificationPreferences());
          return const ShellActionBindingResult.completed();
        },
        toggleBellNotify: (_) {
          setState(() {
            _bellNotificationsEnabled = !_bellNotificationsEnabled;
          });
          unawaited(_saveNotificationPreferences());
          return const ShellActionBindingResult.completed();
        },
        toggleActivityMonitor: (_) {
          setState(() {
            _activityNotificationsEnabled = !_activityNotificationsEnabled;
          });
          unawaited(_saveNotificationPreferences());
          return const ShellActionBindingResult.completed();
        },
      ),
    );
    if (action != null &&
        await _executeProductionActionIfBound(
          adapter: productionMenuAdapter,
          action: action,
        )) {
      return;
    }
    switch (action) {
      case TerminalActionId.newTab:
        if (defaultProfile == null) {
          return;
        }
        _createSession(
          sessionController,
          defaultProfile,
          returningToWorkspace: activeSessionIdBeforeOpen == null,
        );
        return;
      case TerminalActionId.toolbelt:
        setState(() {
          _isToolbeltOpen = true;
        });
        return;
      case TerminalActionId.splitRight:
        if (defaultProfile == null || currentSessionId == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.horizontal,
        );
        return;
      case TerminalActionId.splitDown:
        if (defaultProfile == null || currentSessionId == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.vertical,
        );
        return;
      case TerminalActionId.copy:
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
      case TerminalActionId.copyMode:
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
      case TerminalActionId.paste:
        if (currentSessionId == null) {
          return;
        }
        await _pasteToSession(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.advancedPaste:
        if (currentSessionId == null) {
          return;
        }
        await _openAdvancedPaste(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.pasteHistory:
        if (currentSessionId == null) {
          return;
        }
        await _openPasteHistory(sessionState);
        return;
      case TerminalActionId.shellIntegrationUtilities:
        if (currentSessionId == null) {
          return;
        }
        await _openShellIntegrationUtilities(currentState, currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.selectCommandOutput:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers.putIfAbsent(
          currentSessionId,
          SelectionController.new,
        );
        if (_selectLastCommandOutput(
          sessionController,
          currentSessionId,
          selectionController,
        )) {
          return;
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.tmuxIntegration:
        if (currentSessionId == null) {
          return;
        }
        await _openTmuxIntegration(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.coprocess:
        if (currentSessionId == null) {
          return;
        }
        await _openCoprocess(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.annotations:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers.putIfAbsent(
          currentSessionId,
          SelectionController.new,
        );
        await _openAnnotations(
          sessionController,
          currentSessionId,
          selectionController,
        );
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.capturedOutput:
        if (currentSessionId == null) {
          return;
        }
        await _openCapturedOutput(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.passwordManager:
        if (currentSessionId == null) {
          return;
        }
        await _openPasswordManager(sessionController, currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.instantReplay:
        if (currentSessionId == null) {
          return;
        }
        await _openInstantReplay(sessionState);
        return;
      case TerminalActionId.search:
        if (currentSessionId == null) {
          return;
        }
        _openSearch();
        return;
      case TerminalActionId.globalSearch:
        if (sessionState.tabs.isEmpty) {
          return;
        }
        await _openGlobalSearch(sessionState);
        return;
      case TerminalActionId.autocomplete:
        if (currentSessionId == null) {
          return;
        }
        _openAutocomplete();
        return;
      case TerminalActionId.autoComposer:
        if (currentSessionId == null) {
          return;
        }
        _openAutoComposer();
        return;
      case TerminalActionId.hotkeyWindow:
        await _toggleHotkeyWindowWithFeedback();
        return;
      case TerminalActionId.defaults:
        await _openDefaultsAndAppearance(sessionController, sessionState);
        return;
      case TerminalActionId.profiles:
        await _openProfilesSheet(sessionController, sessionState);
        return;
      case TerminalActionId.dynamicProfiles:
        await _openDynamicProfiles(sessionController);
        return;
      case TerminalActionId.openDefaults:
        await _openDefaultsAndAppearance(sessionController, sessionState);
        return;
      case TerminalActionId.activateTab:
        return;
      case TerminalActionId.openLauncher:
      case TerminalActionId.openCommandMenu:
      case TerminalActionId.closeActiveTab:
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      default:
        return;
    }
  }

  Future<void> _openTabContextMenu(
    SessionController sessionController,
    SessionState sessionState,
    TerminalTab tab,
    Offset position,
  ) async {
    final defaultProfile = _effectiveDefaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    final targetSessionId = tab.activeSessionId;
    final hasMultiplePanes = tab.effectivePanes.length > 1;
    final targetPane = tab.paneFor(targetSessionId);
    final hasCurrentDirectory =
        (targetPane?.shellIntegration.currentDirectory ?? '').isNotEmpty;
    final isTargetPaneZoomed =
        _zoomedPaneSessionId == targetSessionId && targetPane != null;
    final overlay = Overlay.of(context).context.findRenderObject();
    final overlaySize = overlay is RenderBox
        ? overlay.size
        : MediaQuery.sizeOf(context);

    PopupMenuItem<TerminalActionId> item({
      required TerminalActionId action,
      required IconData icon,
      required String title,
      required bool enabled,
    }) {
      return PopupMenuItem<TerminalActionId>(
        value: action,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
      );
    }

    final action = await showMenu<TerminalActionId>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlaySize,
      ),
      items: [
        item(
          action: TerminalActionId.duplicateCurrentCwd,
          icon: Icons.create_new_folder_rounded,
          title: 'Duplicate current directory',
          enabled: defaultProfile != null && hasCurrentDirectory,
        ),
        item(
          action: TerminalActionId.splitRight,
          icon: Icons.vertical_split_rounded,
          title: 'Split right',
          enabled: defaultProfile != null,
        ),
        item(
          action: TerminalActionId.splitDown,
          icon: Icons.horizontal_split_rounded,
          title: 'Split down',
          enabled: defaultProfile != null,
        ),
        item(
          action: TerminalActionId.applyLayoutTemplate,
          icon: Icons.dashboard_customize_rounded,
          title: 'Apply two-pane layout',
          enabled: defaultProfile != null && !hasMultiplePanes,
        ),
        const PopupMenuDivider(),
        item(
          action: TerminalActionId.focusNextPane,
          icon: Icons.keyboard_tab_rounded,
          title: 'Focus next pane',
          enabled: hasMultiplePanes,
        ),
        item(
          action: TerminalActionId.focusPreviousPane,
          icon: Icons.keyboard_tab_rounded,
          title: 'Focus previous pane',
          enabled: hasMultiplePanes,
        ),
        item(
          action: TerminalActionId.resizePane,
          icon: Icons.open_with_rounded,
          title: 'Grow active pane',
          enabled: hasMultiplePanes,
        ),
        item(
          action: TerminalActionId.swapPane,
          icon: Icons.swap_horiz_rounded,
          title: 'Swap active pane',
          enabled: hasMultiplePanes,
        ),
        item(
          action: TerminalActionId.zoomPane,
          icon: Icons.zoom_out_map_rounded,
          title: '${isTargetPaneZoomed ? 'Unzoom' : 'Zoom'} active pane',
          enabled: hasMultiplePanes,
        ),
        const PopupMenuDivider(),
        item(
          action: TerminalActionId.closePane,
          icon: Icons.close_fullscreen_rounded,
          title: 'Close active pane',
          enabled: true,
        ),
        item(
          action: TerminalActionId.closeActiveTab,
          icon: Icons.close_rounded,
          title: 'Close tab',
          enabled: true,
        ),
      ],
    );

    if (!mounted || action == null) {
      return;
    }
    await _runTabContextAction(
      sessionController,
      action,
      targetTabSessionId: tab.sessionId,
    );
  }

  Future<void> _runTabContextAction(
    SessionController sessionController,
    TerminalActionId action, {
    required String targetTabSessionId,
  }) async {
    final defaultProfile = _effectiveDefaultProfileFor(
      ref.read(sessionControllerProvider).profiles,
      ref.read(sessionControllerProvider).defaultProfileId,
    );
    final initialState = ref.read(sessionControllerProvider);
    TerminalTab? targetTab;
    for (final candidate in initialState.tabs) {
      if (candidate.sessionId == targetTabSessionId) {
        targetTab = candidate;
        break;
      }
    }
    if (targetTab == null) {
      return;
    }
    final targetSessionId = targetTab.activeSessionId;

    if (action == TerminalActionId.closeActiveTab) {
      _closeTab(sessionController, initialState, targetTab.sessionId);
      return;
    }

    sessionController.activateSession(targetSessionId);
    _focusSession(targetSessionId);
    final currentState = ref.read(sessionControllerProvider);
    final currentSessionId = currentState.activeSessionId;
    if (currentSessionId == null) {
      return;
    }

    switch (action) {
      case TerminalActionId.duplicateCurrentCwd:
        if (defaultProfile == null) {
          return;
        }
        final currentPane = _paneForSession(currentState, currentSessionId);
        final currentDirectory = currentPane?.shellIntegration.currentDirectory;
        if (currentDirectory == null || currentDirectory.isEmpty) {
          return;
        }
        _createSession(
          sessionController,
          defaultProfile,
          returningToWorkspace: false,
        );
        final duplicateSessionId = ref
            .read(sessionControllerProvider)
            .activeSessionId;
        if (duplicateSessionId != null) {
          _sendPlainTextToSession(
            duplicateSessionId,
            'cd ${_shellQuotedPath(currentDirectory)}',
          );
        }
        return;
      case TerminalActionId.splitRight:
        if (defaultProfile == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.horizontal,
        );
        return;
      case TerminalActionId.splitDown:
        if (defaultProfile == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.vertical,
        );
        return;
      case TerminalActionId.applyLayoutTemplate:
        if (defaultProfile == null) {
          return;
        }
        final currentTab = _tabForSession(currentState, currentSessionId);
        if (currentTab == null || currentTab.effectivePanes.length > 1) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.horizontal,
        );
        return;
      case TerminalActionId.focusNextPane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        if (currentTab != null) {
          _focusRelativePane(
            sessionController,
            currentTab,
            currentSessionId,
            delta: 1,
          );
        }
        return;
      case TerminalActionId.focusPreviousPane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        if (currentTab != null) {
          _focusRelativePane(
            sessionController,
            currentTab,
            currentSessionId,
            delta: -1,
          );
        }
        return;
      case TerminalActionId.resizePane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        if (currentTab != null &&
            _growActivePane(currentTab, currentSessionId)) {
          _focusSession(currentSessionId);
        }
        return;
      case TerminalActionId.swapPane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        if ((currentTab?.effectivePanes.length ?? 0) < 2) {
          return;
        }
        sessionController.swapActivePaneWithSibling();
        _focusSession(currentSessionId);
        return;
      case TerminalActionId.zoomPane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        if ((currentTab?.effectivePanes.length ?? 0) < 2) {
          return;
        }
        setState(() {
          _zoomedPaneSessionId = _zoomedPaneSessionId == currentSessionId
              ? null
              : currentSessionId;
        });
        _focusSession(currentSessionId);
        return;
      case TerminalActionId.closePane:
        _closeSession(sessionController, currentState, currentSessionId);
        return;
      default:
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
    final zoomedPaneSessionId = _zoomedPaneSessionId;
    final zoomedPane = zoomedPaneSessionId == null
        ? null
        : activeTab.paneFor(zoomedPaneSessionId);
    final panes = zoomedPane == null ? activeTab.effectivePanes : [zoomedPane];
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
                flex: _paneFlexBySession[panes[index].sessionId] ?? 1,
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
      readOnly: () => _isSessionReadOnly(sessionId),
    );
    final annotations = _annotationsForSession(sessionId);
    final activeCoprocess = _coprocesses[sessionId];
    final terminalViewportPadding = _terminalViewportPaddingFor(sessionState);

    return LayoutBuilder(
      key: Key('shell-pane-$sessionId'),
      builder: (context, constraints) {
        final viewportSize = _terminalContentSizeFor(
          constraints,
          terminalViewportPadding,
        );
        final scheduledSize = _scheduledViewportSizes[sessionId];
        if (scheduledSize != viewportSize) {
          _scheduledViewportSizes[sessionId] = viewportSize;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
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
        final viewportController = sessionController.viewportFor(sessionId);

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
                      ? palette.focusRing.withValues(alpha: 0.78)
                      : Colors.transparent,
                  width: isActive ? 1.5 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TerminalViewport(
                      focusNode: focusNode,
                      controller: viewportController,
                      selectionController: selectionController,
                      inputController: inputController,
                      contentPadding: terminalViewportPadding,
                      onMeasuredCellSizeChanged: (cellSize) {
                        if (!mounted) {
                          return;
                        }
                        if (_measuredTerminalCellSizes[sessionId] != cellSize) {
                          setState(() {
                            _measuredTerminalCellSizes[sessionId] = cellSize;
                          });
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
                  if (isActive && _isSearchOpen && _searchMatches.isNotEmpty)
                    Positioned.fill(
                      child: _TerminalSearchHighlights(
                        matches: _searchMatches,
                        activeIndex: _activeSearchIndex,
                        frame: viewportController.frame,
                        cellSize:
                            viewportController.measuredCellSize ??
                            terminal.terminalFallbackCellSize,
                        contentPadding: terminalViewportPadding,
                        palette: palette,
                      ),
                    ),
                  if (!isActive)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          key: Key('shell-pane-dim-$sessionId'),
                          color: palette.inactiveScrim,
                        ),
                      ),
                    ),
                  if (isActive && _isSearchOpen)
                    Positioned(
                      top: _terminalOverlayPadding.top,
                      right: _terminalOverlayPadding.right,
                      child: _TerminalSearchBar(
                        query: _searchQuery,
                        matches: _searchMatches.length,
                        activeIndex: _activeSearchIndex,
                        regexEnabled: _searchUseRegex,
                        errorText: _searchErrorText,
                        palette: palette,
                        onChanged: _searchScrollback,
                        onRegexChanged: _setSearchRegexEnabled,
                        onPrevious: () => _moveSearchMatch(-1),
                        onNext: () => _moveSearchMatch(1),
                        onClose: _closeSearch,
                      ),
                    ),
                  if (isActive && _isAutocompleteOpen)
                    Positioned(
                      top: _terminalOverlayPadding.top,
                      right: _terminalOverlayPadding.right,
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
                  if (isActive && _isAutoComposerOpen)
                    Positioned(
                      left: _terminalOverlayPadding.left,
                      right: _terminalOverlayPadding.right,
                      bottom: _terminalOverlayPadding.bottom,
                      child: _TerminalAutoComposer(
                        controller: _autoComposerController,
                        focusNode: _autoComposerFocusNode,
                        suggestions: _autoComposerSuggestions,
                        activeIndex: _activeAutoComposerIndex,
                        palette: palette,
                        onChanged: _updateAutoComposerSuggestions,
                        onPrevious: () => _moveAutoComposerSuggestion(-1),
                        onNext: () => _moveAutoComposerSuggestion(1),
                        onAcceptSuggestion: _acceptAutoComposerSuggestion,
                        onSend: _sendAutoComposerCommand,
                        onClose: _closeAutoComposer,
                      ),
                    ),
                  if (isActive &&
                      activeCoprocess != null &&
                      !_isSearchOpen &&
                      !_isAutocompleteOpen &&
                      !_isAutoComposerOpen)
                    Positioned(
                      top: _terminalOverlayPadding.top,
                      right: _terminalOverlayPadding.right,
                      child: _CoprocessIndicator(
                        key: Key('terminal-coprocess-indicator-$sessionId'),
                        command: activeCoprocess.command,
                        palette: palette,
                      ),
                    ),
                  if (isActive && _isCopyModeOpen)
                    Positioned(
                      top: _terminalOverlayPadding.top,
                      left: _terminalOverlayPadding.left,
                      child: IgnorePointer(
                        child: _ShellWorkspaceCue(
                          title: 'Copy mode',
                          palette: palette,
                        ),
                      ),
                    ),
                  if (isActive &&
                      annotations.isNotEmpty &&
                      !_isAutoComposerOpen)
                    Positioned(
                      left: _terminalOverlayPadding.left,
                      bottom: _terminalOverlayPadding.bottom,
                      child: _TerminalAnnotationBadge(
                        key: Key('terminal-annotation-badge-$sessionId'),
                        count: annotations.length,
                        palette: palette,
                        onTap: () => unawaited(
                          _openAnnotations(
                            sessionController,
                            sessionId,
                            selectionController,
                          ),
                        ),
                      ),
                    ),
                  if (isActive && _showWorkspaceCue)
                    Positioned(
                      top: _terminalOverlayPadding.top,
                      right: _terminalOverlayPadding.right,
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
    final statusProfile = statusPane == null
        ? null
        : _profileForPane(statusPane, sessionState.profiles);
    final statusContent = statusPane == null
        ? null
        : _sessionBadgeForPane(statusPane, statusProfile);
    final statusViewportLabel = _viewportStatusLabelFor(displayedSessionId);

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
          return KeyEventResult.ignored;
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
                tabs: sessionState.tabs,
                activeSessionId: activeSessionId,
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
                  child:
                      !sessionState.isReady ||
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
                                      activeShellIntegration.promptMarks.length,
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
                                    setState(() {
                                      _isToolbeltOpen = false;
                                    });
                                  },
                                  onOpenCapturedOutput: () => unawaited(
                                    _openCapturedOutput(activeSessionId),
                                  ),
                                  onOpenPasteHistory: () => unawaited(
                                    _openPasteHistory(sessionState),
                                  ),
                                  onOpenShellIntegrationUtilities: () =>
                                      unawaited(
                                        _openShellIntegrationUtilities(
                                          sessionState,
                                          activeSessionId,
                                        ),
                                      ),
                                  onOpenTmuxIntegration: () => unawaited(
                                    _openTmuxIntegration(activeSessionId),
                                  ),
                                  onOpenCoprocess: () => unawaited(
                                    _openCoprocess(activeSessionId),
                                  ),
                                  onOpenAnnotations: () {
                                    final selectionController =
                                        _selectionControllers.putIfAbsent(
                                          activeSessionId,
                                          SelectionController.new,
                                        );
                                    unawaited(
                                      _openAnnotations(
                                        sessionController,
                                        activeSessionId,
                                        selectionController,
                                      ),
                                    );
                                  },
                                  onOpenInstantReplay: () => unawaited(
                                    _openInstantReplay(sessionState),
                                  ),
                                  onOpenPasswordManager: () => unawaited(
                                    _openPasswordManager(
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
              if (statusPane != null)
                _ShellStatusBar(
                  key: const Key('shell-status-bar'),
                  palette: palette,
                  sessionName:
                      statusContent?.title ?? statusProfile?.name ?? 'Shell',
                  directory: statusContent?.detail ?? statusProfile?.cwd,
                  shell:
                      statusPane.shellIntegration.shell ?? statusProfile?.shell,
                  connectionLabel: statusPane.isExited
                      ? (statusPane.exitCode == null
                            ? 'Exited'
                            : 'Exit ${statusPane.exitCode}')
                      : 'Connected',
                  connected: !statusPane.isExited,
                  viewportLabel: statusViewportLabel,
                  encodingLabel: 'UTF-8',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellToolbelt extends StatelessWidget {
  const _ShellToolbelt({
    required this.capturedOutputCount,
    required this.pasteHistoryCount,
    required this.commandHistoryCount,
    required this.recentDirectoryCount,
    required this.promptMarkCount,
    required this.tmuxControlModeActive,
    required this.coprocessActive,
    required this.annotationCount,
    required this.completionDiagnosticsSnapshot,
    required this.palette,
    required this.onClose,
    required this.onOpenCapturedOutput,
    required this.onOpenPasteHistory,
    required this.onOpenShellIntegrationUtilities,
    required this.onOpenTmuxIntegration,
    required this.onOpenCoprocess,
    required this.onOpenAnnotations,
    required this.onOpenInstantReplay,
    required this.onOpenPasswordManager,
  });

  final int capturedOutputCount;
  final int pasteHistoryCount;
  final int commandHistoryCount;
  final int recentDirectoryCount;
  final int promptMarkCount;
  final bool tmuxControlModeActive;
  final bool coprocessActive;
  final int annotationCount;
  final LocalTerminalShellUiWiringSnapshot completionDiagnosticsSnapshot;
  final AppThemeTokens palette;
  final VoidCallback onClose;
  final VoidCallback onOpenCapturedOutput;
  final VoidCallback onOpenPasteHistory;
  final VoidCallback onOpenShellIntegrationUtilities;
  final VoidCallback onOpenTmuxIntegration;
  final VoidCallback onOpenCoprocess;
  final VoidCallback onOpenAnnotations;
  final VoidCallback onOpenInstantReplay;
  final VoidCallback onOpenPasswordManager;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('shell-toolbelt-panel'),
      width: 304,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.chromeElevated,
          border: Border(left: BorderSide(color: palette.borderStrong)),
          boxShadow: palette.elevation.floating,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                palette.spacing.lg,
                palette.spacing.lg,
                palette.spacing.lg,
                palette.spacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Toolbelt',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      _buildSheetCloseButton(
                        tooltip: 'Close toolbelt',
                        onPressed: onClose,
                        buttonKey: const Key('toolbelt-close'),
                      ),
                    ],
                  ),
                  SizedBox(height: palette.spacing.sm),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-captured-output'),
                            icon: Icons.outbox_rounded,
                            title: 'Captured output',
                            countLabel:
                                '$capturedOutputCount captured line${capturedOutputCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenCapturedOutput,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-paste-history'),
                            icon: Icons.history_rounded,
                            title: 'Paste history',
                            countLabel:
                                '$pasteHistoryCount recent item${pasteHistoryCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenPasteHistory,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-command-history'),
                            icon: Icons.list_alt_rounded,
                            title: 'Command history',
                            countLabel:
                                '$commandHistoryCount command${commandHistoryCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenShellIntegrationUtilities,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-recent-directories'),
                            icon: Icons.folder_rounded,
                            title: 'Recent directories',
                            countLabel:
                                '$recentDirectoryCount director${recentDirectoryCount == 1 ? 'y' : 'ies'}',
                            palette: palette,
                            onTap: onOpenShellIntegrationUtilities,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-prompt-marks'),
                            icon: Icons.assistant_direction_rounded,
                            title: 'Prompt marks',
                            countLabel:
                                '$promptMarkCount mark${promptMarkCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenShellIntegrationUtilities,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-tmux-integration'),
                            icon: Icons.account_tree_rounded,
                            title: 'tmux integration',
                            countLabel: tmuxControlModeActive
                                ? 'Control mode active'
                                : 'Start or attach',
                            palette: palette,
                            onTap: onOpenTmuxIntegration,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-coprocess'),
                            icon: Icons.hub_rounded,
                            title: 'Coprocess',
                            countLabel: coprocessActive
                                ? 'Automation active'
                                : 'Run automation',
                            palette: palette,
                            onTap: onOpenCoprocess,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-annotations'),
                            icon: Icons.sticky_note_2_rounded,
                            title: 'Annotations',
                            countLabel:
                                '$annotationCount note${annotationCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenAnnotations,
                          ),
                          Divider(color: palette.border, height: 18),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-instant-replay'),
                            icon: Icons.replay_rounded,
                            title: 'Instant replay',
                            countLabel: 'Recent frames',
                            palette: palette,
                            onTap: onOpenInstantReplay,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-password-manager'),
                            icon: Icons.password_rounded,
                            title: 'Password manager',
                            countLabel: 'Prompt-gated sends',
                            palette: palette,
                            onTap: onOpenPasswordManager,
                          ),
                          Divider(color: palette.border, height: 18),
                          LocalTerminalCompletionDiagnosticsPanel(
                            key: const Key('toolbelt-completion-diagnostics'),
                            snapshot: completionDiagnosticsSnapshot,
                            maxItemsPerSection: 4,
                          ),
                        ],
                      ),
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

class _ToolbeltActionRow extends StatelessWidget {
  const _ToolbeltActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.countLabel,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String countLabel;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      minLeadingWidth: 24,
      contentPadding: EdgeInsets.symmetric(
        horizontal: palette.spacing.sm,
        vertical: palette.spacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(palette.radius.md),
      ),
      hoverColor: _shellTileHoverColor(palette),
      focusColor: _shellTileFocusColor(palette),
      leading: Icon(icon, color: palette.accent, size: 20),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        countLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      onTap: onTap,
    );
  }
}

class _ShellStatusBar extends StatelessWidget {
  const _ShellStatusBar({
    super.key,
    required this.palette,
    required this.sessionName,
    required this.directory,
    required this.shell,
    required this.connectionLabel,
    required this.connected,
    required this.viewportLabel,
    required this.encodingLabel,
  });

  final AppThemeTokens palette;
  final String sessionName;
  final String? directory;
  final String? shell;
  final String connectionLabel;
  final bool connected;
  final String? viewportLabel;
  final String encodingLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chromeElevated.withValues(alpha: 0.86),
        border: Border(top: BorderSide(color: palette.border)),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(palette.radius.lg),
          bottomRight: Radius.circular(palette.radius.lg),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: palette.spacing.lg),
            child: Row(
              children: [
                _ShellStatusItem(
                  key: const Key('shell-status-session'),
                  palette: palette,
                  icon: Icons.terminal_rounded,
                  label: sessionName,
                  emphasized: true,
                ),
                if (directory != null && directory!.trim().isNotEmpty) ...[
                  _ShellStatusDivider(palette: palette),
                  _ShellStatusItem(
                    key: const Key('shell-status-directory'),
                    palette: palette,
                    label: _statusPathLabel(directory!),
                    minWidth: 176,
                    maxWidth: 260,
                  ),
                ],
                if (shell != null && shell!.trim().isNotEmpty) ...[
                  _ShellStatusDivider(palette: palette),
                  _ShellStatusItem(
                    key: const Key('shell-status-shell'),
                    palette: palette,
                    label: _statusShellLabel(shell!),
                    monospace: true,
                  ),
                ],
                _ShellStatusDivider(palette: palette),
                _ShellStatusItem(
                  key: const Key('shell-status-connection'),
                  palette: palette,
                  label: connectionLabel,
                  dotColor: connected ? palette.success : palette.warning,
                ),
                if (viewportLabel != null) ...[
                  _ShellStatusDivider(palette: palette),
                  _ShellStatusItem(
                    key: const Key('shell-status-viewport'),
                    palette: palette,
                    label: viewportLabel!,
                    monospace: true,
                  ),
                ],
                _ShellStatusDivider(palette: palette),
                _ShellStatusItem(
                  key: const Key('shell-status-encoding'),
                  palette: palette,
                  label: encodingLabel,
                  monospace: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusPathLabel(String path) {
    final normalized = path.trim();
    if (normalized.length <= 34) {
      return normalized;
    }
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '.../${parts[parts.length - 2]}/${parts.last}';
    }
    return '...${normalized.substring(normalized.length - 31)}';
  }

  String _statusShellLabel(String shell) {
    final normalized = shell.trim();
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash == -1 || lastSlash == normalized.length - 1) {
      return normalized;
    }
    return normalized.substring(lastSlash + 1);
  }
}

class _ShellStatusDivider extends StatelessWidget {
  const _ShellStatusDivider({required this.palette});

  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: EdgeInsets.symmetric(horizontal: palette.spacing.lg),
      color: palette.border.withValues(alpha: 0.62),
    );
  }
}

class _ShellStatusItem extends StatelessWidget {
  const _ShellStatusItem({
    super.key,
    required this.palette,
    required this.label,
    this.icon,
    this.dotColor,
    this.emphasized = false,
    this.monospace = false,
    this.minWidth,
    this.maxWidth,
  });

  final AppThemeTokens palette;
  final String label;
  final IconData? icon;
  final Color? dotColor;
  final bool emphasized;
  final bool monospace;
  final double? minWidth;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: emphasized ? palette.textPrimary : palette.textMuted,
      fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
      fontFamily: monospace ? 'monospace' : null,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth ?? 0,
        maxWidth: maxWidth ?? 180,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.selected.withValues(alpha: emphasized ? 0.34 : 0.22),
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: palette.border.withValues(alpha: 0.46)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: palette.accent),
                const SizedBox(width: 6),
              ],
              if (dotColor != null) ...[
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ],
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
    required this.onNewTab,
    required this.onActivateSession,
    required this.onCloseSession,
    required this.onShowTabContextMenu,
    required this.onShowCommandMenu,
  });

  final AppThemeTokens palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool referenceDemoMode;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onCloseSession;
  final void Function(TerminalTab tab, Offset position) onShowTabContextMenu;
  final VoidCallback onShowCommandMenu;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-chrome-bar'),
      decoration: BoxDecoration(
        color: palette.chromeElevated.withValues(alpha: 0.78),
        border: Border.all(color: palette.border.withValues(alpha: 0.72)),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(palette.radius.lg),
          topRight: Radius.circular(palette.radius.lg),
        ),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            SizedBox(
              width: defaultTargetPlatform == TargetPlatform.macOS
                  ? 132
                  : palette.spacing.md,
            ),
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
                      onNewTab: onNewTab,
                      onActivateSession: onActivateSession,
                      onCloseSession: onCloseSession,
                      onShowTabContextMenu: onShowTabContextMenu,
                    ),
            ),
            if (!referenceDemoMode) ...[
              _buildChromeIconButton(
                key: const Key('shell-chrome-menu'),
                tooltip: 'Open command menu',
                onPressed: onShowCommandMenu,
                iconSize: 16,
                icon: Icon(Icons.tune_rounded, color: palette.textSubtle),
              ),
              SizedBox(width: palette.spacing.xs),
              const SizedBox(width: 8),
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
        color: palette.warningContainer,
        border: Border(bottom: BorderSide(color: palette.warning)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: palette.warning),
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
                _buildCompactActionButton(
                  key: const Key('shell-configuration-warnings-dismiss'),
                  tooltip: 'Dismiss configuration warnings',
                  onPressed: onDismiss,
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
    required this.onNewTab,
    required this.onActivateSession,
    required this.onCloseSession,
    required this.onShowTabContextMenu,
  });

  final AppThemeTokens palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onCloseSession;
  final void Function(TerminalTab tab, Offset position) onShowTabContextMenu;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('shell-tab-strip'),
      height: double.infinity,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 3),
        itemCount: tabs.length + 1,
        separatorBuilder: (_, _) => Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 12),
          color: palette.border.withValues(alpha: 0.28),
        ),
        itemBuilder: (context, index) {
          if (index == tabs.length) {
            return _ShellNewTabButton(palette: palette, onPressed: onNewTab);
          }
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
            onShowContextMenu: (position) =>
                onShowTabContextMenu(tab, position),
          );
        },
      ),
    );
  }
}

class _ShellNewTabButton extends StatelessWidget {
  const _ShellNewTabButton({required this.palette, required this.onPressed});

  final AppThemeTokens palette;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _buildChromeIconButton(
        key: const Key('shell-chrome-new-tab'),
        tooltip: 'New tab',
        onPressed: onPressed,
        iconSize: 18,
        icon: Icon(Icons.add_rounded, color: palette.textSubtle),
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
    required this.onShowContextMenu,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onClose;
  final ValueChanged<Offset> onShowContextMenu;

  @override
  Widget build(BuildContext context) {
    final tabTextStyle = Theme.of(context).textTheme.titleSmall!.copyWith(
      color: isActive
          ? palette.textPrimary
          : palette.textMuted.withValues(alpha: 0.82),
      fontWeight: FontWeight.w500,
    );

    return Semantics(
      label: 'shell-tab-${tab.sessionId}',
      selected: isActive,
      button: true,
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) {
            onShowContextMenu(event.position);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 92, maxWidth: 220),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(
                  color: isActive
                      ? palette.borderStrong.withValues(alpha: 0.6)
                      : Colors.transparent,
                ),
              ),
            ),
            child: TextButton(
              key: Key('shell-tab-${tab.sessionId}'),
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: palette.spacing.md),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(
                  horizontal: -1,
                  vertical: -2,
                ),
                foregroundColor: WidgetStatePropertyAll(
                  isActive ? palette.textPrimary : palette.textMuted,
                ),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (isActive) {
                    return palette.selected.withValues(alpha: 0.46);
                  }
                  if (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)) {
                    return palette.selected.withValues(alpha: 0.18);
                  }
                  return Colors.transparent;
                }),
                side: const WidgetStatePropertyAll(BorderSide.none),
                shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
              ),
              onPressed: onActivate,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (shortcutIndex != null) ...[
                    Text(
                      '⌘$shortcutIndex',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isActive
                            ? palette.textMuted
                            : palette.textSubtle,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 140),
                      style: tabTextStyle,
                      child: Text(tab.title, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Tooltip(
                    message: 'Close ${tab.title}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onClose,
                      child: Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: isActive
                            ? palette.textMuted.withValues(alpha: 0.78)
                            : palette.textSubtle.withValues(alpha: 0.34),
                      ),
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

class _ShellStartupSurface extends StatelessWidget {
  const _ShellStartupSurface({super.key, required this.palette});

  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        border: Border(top: BorderSide(color: palette.terminalFrame)),
      ),
      child: const SizedBox.expand(),
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
        border: Border(top: BorderSide(color: palette.terminalFrame)),
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

class _TerminalSearchHighlights extends StatelessWidget {
  const _TerminalSearchHighlights({
    required this.matches,
    required this.activeIndex,
    required this.frame,
    required this.cellSize,
    required this.contentPadding,
    required this.palette,
  });

  final List<terminal.TerminalSearchMatch> matches;
  final int activeIndex;
  final terminal.TerminalFrameDiff frame;
  final Size cellSize;
  final EdgeInsets contentPadding;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    if (cellSize.width <= 0 || cellSize.height <= 0) {
      return const SizedBox.shrink();
    }
    final highlights = <Widget>[];
    for (var index = 0; index < matches.length; index += 1) {
      final match = matches[index];
      final relativeRow = match.row - frame.viewportStartRow;
      if (relativeRow < 0 || relativeRow >= frame.viewportRows) {
        continue;
      }
      final startCol = match.startCol.clamp(0, frame.viewportCols).toInt();
      if (startCol >= frame.viewportCols) {
        continue;
      }
      final endCol = match.endCol
          .clamp(startCol + 1, frame.viewportCols)
          .toInt();
      final maxWidth = (frame.viewportCols - startCol) * cellSize.width;
      if (maxWidth <= 0) {
        continue;
      }
      final highlightWidth = (endCol - startCol) * cellSize.width;
      final isActive = index == activeIndex;
      highlights.add(
        Positioned(
          key: Key('terminal-search-highlight-$index'),
          left: contentPadding.left + startCol * cellSize.width,
          top: contentPadding.top + relativeRow * cellSize.height,
          width: highlightWidth > maxWidth ? maxWidth : highlightWidth,
          height: cellSize.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: (isActive ? palette.accent : palette.warning).withValues(
                alpha: isActive ? 0.34 : 0.22,
              ),
              border: isActive
                  ? Border.all(
                      color: palette.accent.withValues(alpha: 0.82),
                      width: 1,
                    )
                  : null,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );
    }

    if (highlights.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      key: const Key('terminal-search-highlights'),
      child: SizedBox.expand(child: Stack(children: highlights)),
    );
  }
}

class _TerminalSearchBar extends StatefulWidget {
  const _TerminalSearchBar({
    required this.query,
    required this.matches,
    required this.activeIndex,
    required this.regexEnabled,
    required this.errorText,
    required this.palette,
    required this.onChanged,
    required this.onRegexChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final String query;
  final int matches;
  final int activeIndex;
  final bool regexEnabled;
  final String? errorText;
  final AppThemeTokens palette;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onRegexChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  State<_TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<_TerminalSearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(_TerminalSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _counterText {
    final errorText = widget.errorText;
    if (errorText != null) {
      return errorText;
    }
    if (widget.matches == 0) {
      return widget.query.isEmpty ? '0 of 0' : 'No matches';
    }
    return '${widget.activeIndex + 1} of ${widget.matches}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
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
                  controller: _controller,
                  autofocus: true,
                  onChanged: widget.onChanged,
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
              SizedBox(
                width: 76,
                child: Text(
                  _counterText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: widget.errorText != null
                        ? Theme.of(context).colorScheme.error
                        : widget.matches == 0 && widget.query.isNotEmpty
                        ? palette.textMuted
                        : palette.textSubtle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildCompactActionButton(
                key: const Key('terminal-search-regex'),
                tooltip: 'Regular expression',
                isSelected: widget.regexEnabled,
                onPressed: () => widget.onRegexChanged(!widget.regexEnabled),
                splashRadius: 16,
                iconSize: 16,
                selectedIcon: const Icon(Icons.code_rounded),
                icon: Icon(
                  Icons.code_rounded,
                  color: widget.regexEnabled ? palette.accent : null,
                ),
              ),
              _buildCompactActionButton(
                key: const Key('terminal-search-previous'),
                tooltip: 'Previous match',
                onPressed: widget.matches == 0 ? null : widget.onPrevious,
                splashRadius: 16,
                iconSize: 16,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              _buildCompactActionButton(
                key: const Key('terminal-search-next'),
                tooltip: 'Next match',
                onPressed: widget.matches == 0 ? null : widget.onNext,
                splashRadius: 16,
                iconSize: 16,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              _buildCompactActionButton(
                key: const Key('terminal-search-close'),
                tooltip: 'Close search',
                onPressed: widget.onClose,
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
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final result = _results[index];
                              return _ShellEntryTile(
                                key: Key(
                                  'terminal-global-search-result-${result.session.sessionId}-$index',
                                ),
                                dense: true,
                                title: result.match.text,
                                subtitle:
                                    '${result.session.title} • row ${result.match.row + 1}',
                                subtitleMaxLines: 1,
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

class _CoprocessSheet extends StatefulWidget {
  const _CoprocessSheet({
    required this.activeCoprocess,
    required this.onStart,
    required this.onStop,
  });

  final _ShellCoprocess? activeCoprocess;
  final ValueChanged<_CoprocessStartRequest> onStart;
  final VoidCallback onStop;

  @override
  State<_CoprocessSheet> createState() => _CoprocessSheetState();
}

class _CoprocessSheetState extends State<_CoprocessSheet> {
  late final TextEditingController _commandController;
  late final TextEditingController _patternController;
  late final TextEditingController _responseController;

  bool get _canStart =>
      _patternController.text.trim().isNotEmpty &&
      _responseController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _commandController = TextEditingController(text: 'presence bot');
    _patternController = TextEditingController(text: 'Are you there?');
    _responseController = TextEditingController(text: 'Yes\n');
  }

  @override
  void dispose() {
    _commandController.dispose();
    _patternController.dispose();
    _responseController.dispose();
    super.dispose();
  }

  void _start() {
    if (!_canStart) {
      return;
    }
    final command = _commandController.text.trim();
    widget.onStart(
      _CoprocessStartRequest(
        command: command.isEmpty ? 'Coprocess' : command,
        pattern: _patternController.text.trim(),
        response: _responseController.text,
      ),
    );
    Navigator.of(context).pop();
  }

  void _stop() {
    widget.onStop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final active = widget.activeCoprocess;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('coprocess-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Coprocess',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      _buildSheetCloseButton(
                        tooltip: 'Close coprocess',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (active == null)
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ShellIntegrationSectionHeader(
                              icon: Icons.hub_rounded,
                              title: 'Run Coprocess',
                              countLabel: 'one per session',
                              palette: palette,
                            ),
                            _CoprocessTextField(
                              fieldKey: const Key('coprocess-command-field'),
                              controller: _commandController,
                              label: 'Command label',
                              icon: Icons.label_rounded,
                              palette: palette,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            _CoprocessTextField(
                              fieldKey: const Key('coprocess-pattern-field'),
                              controller: _patternController,
                              label: 'Input pattern',
                              icon: Icons.search_rounded,
                              palette: palette,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            _CoprocessTextField(
                              fieldKey: const Key('coprocess-response-field'),
                              controller: _responseController,
                              label: 'Coprocess output',
                              icon: Icons.keyboard_return_rounded,
                              palette: palette,
                              maxLines: 3,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                key: const Key('coprocess-start'),
                                onPressed: _canStart ? _start : null,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Run'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    _ActiveCoprocessPanel(
                      coprocess: active,
                      palette: palette,
                      onStop: _stop,
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

class _CoprocessTextField extends StatelessWidget {
  const _CoprocessTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.icon,
    required this.palette,
    required this.onChanged,
    this.maxLines = 1,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final AppThemeTokens palette;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        labelText: label,
      ),
    );
  }
}

class _ActiveCoprocessPanel extends StatelessWidget {
  const _ActiveCoprocessPanel({
    required this.coprocess,
    required this.palette,
    required this.onStop,
  });

  final _ShellCoprocess coprocess;
  final AppThemeTokens palette;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('coprocess-active-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ShellIntegrationSectionHeader(
          icon: Icons.hub_rounded,
          title: coprocess.command,
          countLabel: '${coprocess.inputLineCount} lines',
          palette: palette,
        ),
        Text(
          'Pattern ${coprocess.pattern}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
        ),
        if (coprocess.lastInput != null) ...[
          const SizedBox(height: 6),
          Text(
            coprocess.lastInput!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
              fontFamily: 'monospace',
            ),
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const Key('coprocess-stop'),
            onPressed: onStop,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Stop'),
          ),
        ),
      ],
    );
  }
}

class _TmuxIntegrationSheet extends StatefulWidget {
  const _TmuxIntegrationSheet({
    required this.controlModeDetected,
    required this.onSendCommand,
  });

  final bool controlModeDetected;
  final ValueChanged<String> onSendCommand;

  @override
  State<_TmuxIntegrationSheet> createState() => _TmuxIntegrationSheetState();
}

class _TmuxIntegrationSheetState extends State<_TmuxIntegrationSheet> {
  late final TextEditingController _commandController;

  @override
  void initState() {
    super.initState();
    _commandController = TextEditingController();
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  void _send(String command) {
    Navigator.of(context).pop();
    widget.onSendCommand(command);
  }

  void _sendCustomCommand() {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      return;
    }
    _send('$command\n');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final controlModeDetected = widget.controlModeDetected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('tmux-integration-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'tmux Integration',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      _buildSheetCloseButton(
                        tooltip: 'Close tmux integration',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  _TmuxStatusChip(
                    controlModeDetected: controlModeDetected,
                    palette: palette,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ShellIntegrationSectionHeader(
                            icon: Icons.terminal_rounded,
                            title: 'Control Mode',
                            countLabel: 'tmux -CC',
                            palette: palette,
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-start-control-mode'),
                            icon: Icons.play_arrow_rounded,
                            title: 'Start tmux -CC',
                            subtitle: 'Create a new tmux control-mode session.',
                            palette: palette,
                            onTap: () => _send('tmux -CC\n'),
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-attach-control-mode'),
                            icon: Icons.login_rounded,
                            title: 'Attach tmux -CC',
                            subtitle: 'Attach to an existing tmux session.',
                            palette: palette,
                            onTap: () => _send('tmux -CC attach\n'),
                          ),
                          const SizedBox(height: 8),
                          _ShellIntegrationSectionHeader(
                            icon: Icons.account_tree_rounded,
                            title: 'tmux Actions',
                            countLabel: controlModeDetected
                                ? 'available'
                                : 'waiting',
                            palette: palette,
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-new-window'),
                            icon: Icons.add_box_outlined,
                            title: 'New window',
                            subtitle: 'Send new-window to tmux control mode.',
                            palette: palette,
                            enabled: controlModeDetected,
                            onTap: () => _send('new-window\n'),
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-split-right'),
                            icon: Icons.vertical_split_rounded,
                            title: 'Split pane right',
                            subtitle: 'Send split-window -h.',
                            palette: palette,
                            enabled: controlModeDetected,
                            onTap: () => _send('split-window -h\n'),
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-split-down'),
                            icon: Icons.horizontal_split_rounded,
                            title: 'Split pane down',
                            subtitle: 'Send split-window -v.',
                            palette: palette,
                            enabled: controlModeDetected,
                            onTap: () => _send('split-window -v\n'),
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-detach-client'),
                            icon: Icons.logout_rounded,
                            title: 'Detach client',
                            subtitle: 'Detach while leaving tmux running.',
                            palette: palette,
                            enabled: controlModeDetected,
                            onTap: () => _send('detach-client\n'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('tmux-command-field'),
                            controller: _commandController,
                            enabled: controlModeDetected,
                            onSubmitted: (_) => _sendCustomCommand(),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: palette.textPrimary),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.code_rounded),
                              suffixIcon: IconButton(
                                key: const Key('tmux-send-command'),
                                tooltip: 'Send tmux command',
                                onPressed: controlModeDetected
                                    ? _sendCustomCommand
                                    : null,
                                icon: const Icon(Icons.keyboard_return_rounded),
                              ),
                              hintText: 'tmux command',
                            ),
                          ),
                        ],
                      ),
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

class _TmuxStatusChip extends StatelessWidget {
  const _TmuxStatusChip({
    required this.controlModeDetected,
    required this.palette,
  });

  final bool controlModeDetected;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: controlModeDetected
            ? palette.accent.withValues(alpha: 0.12)
            : palette.chrome,
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(
          color: controlModeDetected ? palette.accent : palette.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              controlModeDetected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: controlModeDetected ? palette.accent : palette.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              controlModeDetected
                  ? 'Control mode detected'
                  : 'No tmux control mode detected',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: controlModeDetected
                    ? palette.textPrimary
                    : palette.textSubtle,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TmuxActionTile extends StatelessWidget {
  const _TmuxActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final AppThemeTokens palette;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final titleColor = enabled ? palette.textPrimary : palette.textSubtle;
    final iconColor = enabled ? palette.textMuted : palette.textSubtle;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(icon, color: iconColor, size: 20),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: titleColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}

class _ShellIntegrationUtilitiesSheet extends StatelessWidget {
  const _ShellIntegrationUtilitiesSheet({
    required this.integration,
    required this.onInsertCommand,
    required this.onChangeDirectory,
    required this.onJumpToMark,
  });

  final TerminalShellIntegrationSnapshot integration;
  final ValueChanged<String> onInsertCommand;
  final ValueChanged<String> onChangeDirectory;
  final ValueChanged<TerminalShellPromptMark> onJumpToMark;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final commandCount = integration.recentCommands.length;
    final directoryCount = integration.recentDirectories.length;
    final markCount = integration.promptMarks.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('shell-integration-utilities-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
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
                          'Shell Integration',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      AppActionButton(
                        tooltip: 'Close shell integration',
                        tone: AppActionTone.ghost,
                        size: AppActionSize.dense,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icons.close_rounded,
                      ),
                    ],
                  ),
                  _ShellIntegrationSummary(
                    integration: integration,
                    palette: palette,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        _ShellIntegrationSectionHeader(
                          icon: Icons.list_alt_rounded,
                          title: 'Command History',
                          countLabel:
                              '$commandCount command${commandCount == 1 ? '' : 's'}',
                          palette: palette,
                        ),
                        if (integration.recentCommands.isEmpty)
                          _ShellIntegrationEmptyRow(
                            message:
                                'Run a command after opening this tab to fill command history.',
                            palette: palette,
                          )
                        else
                          for (
                            var index = 0;
                            index < integration.recentCommands.length &&
                                index < 8;
                            index++
                          )
                            _ShellIntegrationActionTile(
                              key: Key('shell-command-history-entry-$index'),
                              icon: Icons.keyboard_return_rounded,
                              title: integration.recentCommands[index],
                              subtitle: 'Insert previous command',
                              palette: palette,
                              onTap: () {
                                Navigator.of(context).pop();
                                onInsertCommand(
                                  integration.recentCommands[index],
                                );
                              },
                            ),
                        const SizedBox(height: 8),
                        _ShellIntegrationSectionHeader(
                          icon: Icons.folder_rounded,
                          title: 'Recent Directories',
                          countLabel:
                              '$directoryCount director${directoryCount == 1 ? 'y' : 'ies'}',
                          palette: palette,
                        ),
                        if (integration.recentDirectories.isEmpty)
                          _ShellIntegrationEmptyRow(
                            message:
                                'Change directories after opening this tab to fill this list.',
                            palette: palette,
                          )
                        else
                          for (
                            var index = 0;
                            index < integration.recentDirectories.length &&
                                index < 8;
                            index++
                          )
                            _ShellIntegrationActionTile(
                              key: Key('shell-recent-directory-$index'),
                              icon: Icons.subdirectory_arrow_right_rounded,
                              title: integration.recentDirectories[index],
                              subtitle: 'Insert cd command',
                              palette: palette,
                              onTap: () {
                                Navigator.of(context).pop();
                                onChangeDirectory(
                                  integration.recentDirectories[index],
                                );
                              },
                            ),
                        const SizedBox(height: 8),
                        _ShellIntegrationSectionHeader(
                          icon: Icons.assistant_direction_rounded,
                          title: 'Prompt Marks',
                          countLabel:
                              '$markCount mark${markCount == 1 ? '' : 's'}',
                          palette: palette,
                        ),
                        if (integration.promptMarks.isEmpty)
                          _ShellIntegrationEmptyRow(
                            message:
                                'Prompt marks appear after the shell draws new prompts.',
                            palette: palette,
                          )
                        else
                          for (
                            var index = 0;
                            index < integration.promptMarks.length && index < 8;
                            index++
                          )
                            _ShellPromptMarkTile(
                              key: Key('shell-prompt-mark-$index'),
                              mark: integration.promptMarks.reversed.elementAt(
                                index,
                              ),
                              palette: palette,
                              onTap: () {
                                Navigator.of(context).pop();
                                onJumpToMark(
                                  integration.promptMarks.reversed.elementAt(
                                    index,
                                  ),
                                );
                              },
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

class _ShellIntegrationSummary extends StatelessWidget {
  const _ShellIntegrationSummary({
    required this.integration,
    required this.palette,
  });

  final TerminalShellIntegrationSnapshot integration;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final identity = _identityLabel;
    final directory = integration.currentDirectory;
    final command = integration.lastCommand;
    final exitCode = integration.lastExitCode;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ShellIntegrationChip(
          icon: Icons.account_tree_rounded,
          label: identity ?? 'Local shell',
          palette: palette,
        ),
        if (directory != null)
          _ShellIntegrationChip(
            icon: Icons.folder_open_rounded,
            label: _compactText(directory, 42),
            palette: palette,
          ),
        if (command != null)
          _ShellIntegrationChip(
            icon: Icons.terminal_rounded,
            label: exitCode == null
                ? _compactText(command, 42)
                : '${_compactText(command, 32)} ${exitCode == 0 ? 'ok' : 'exit $exitCode'}',
            palette: palette,
          ),
      ],
    );
  }

  String? get _identityLabel {
    final username = integration.username;
    final hostname = integration.hostname;
    if (username != null && hostname != null) {
      return '$username@$hostname';
    }
    return username ?? hostname ?? integration.shell;
  }
}

class _ShellIntegrationChip extends StatelessWidget {
  const _ShellIntegrationChip({
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chrome,
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: palette.textMuted),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: palette.textSubtle,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellIntegrationSectionHeader extends StatelessWidget {
  const _ShellIntegrationSectionHeader({
    required this.icon,
    required this.title,
    required this.countLabel,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final String countLabel;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            countLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.textSubtle,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellIntegrationEmptyRow extends StatelessWidget {
  const _ShellIntegrationEmptyRow({
    required this.message,
    required this.palette,
  });

  final String message;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
      ),
    );
  }
}

class _ShellIntegrationActionTile extends StatelessWidget {
  const _ShellIntegrationActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ShellEntryTile(
      dense: true,
      leading: Icon(icon, color: palette.textMuted, size: 20),
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: 1,
      onTap: onTap,
    );
  }
}

class _ShellPromptMarkTile extends StatelessWidget {
  const _ShellPromptMarkTile({
    super.key,
    required this.mark,
    required this.palette,
    required this.onTap,
  });

  final TerminalShellPromptMark mark;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final command = mark.command;
    final cwd = mark.cwd;
    final compactCwd = cwd == null ? null : _compactText(cwd, 42);
    final subtitle = [?command, ?compactCwd].join(' • ');

    return _ShellEntryTile(
      dense: true,
      leading: Icon(
        Icons.assistant_direction_rounded,
        color: palette.textMuted,
        size: 20,
      ),
      title: 'Offset ${mark.scrollbackOffset}',
      subtitle: subtitle.isEmpty ? 'Shell prompt mark' : subtitle,
      subtitleMaxLines: 1,
      onTap: onTap,
    );
  }
}

String _compactText(String text, int maxLength) {
  final trimmed = text.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxLength - 3)}...';
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
                    _buildCompactActionButton(
                      key: const Key('terminal-autocomplete-previous'),
                      tooltip: 'Previous completion',
                      onPressed: suggestions.length < 2 ? null : onPrevious,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    _buildCompactActionButton(
                      key: const Key('terminal-autocomplete-next'),
                      tooltip: 'Next completion',
                      onPressed: suggestions.length < 2 ? null : onNext,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    _buildCompactActionButton(
                      key: const Key('terminal-autocomplete-close'),
                      tooltip: 'Close completions',
                      onPressed: onClose,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
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

class _TerminalAutoComposer extends StatelessWidget {
  const _TerminalAutoComposer({
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.activeIndex,
    required this.palette,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onAcceptSuggestion,
    required this.onSend,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final int activeIndex;
  final AppThemeTokens palette;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<String> onAcceptSuggestion;
  final VoidCallback onSend;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trimRight().isNotEmpty;
    return Material(
      key: const Key('terminal-auto-composer'),
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.overlay.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(palette.radius.lg),
              border: Border.all(color: palette.accent.withValues(alpha: 0.34)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.edit_note_rounded,
                        size: 18,
                        color: palette.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('terminal-auto-composer-field'),
                          controller: controller,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                          decoration: const InputDecoration(
                            hintText: 'Compose command',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: onChanged,
                          onSubmitted: (_) {
                            if (controller.text.trimRight().isNotEmpty) {
                              onSend();
                            }
                          },
                        ),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-previous'),
                        tooltip: 'Previous completion',
                        onPressed: suggestions.length < 2 ? null : onPrevious,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-next'),
                        tooltip: 'Next completion',
                        onPressed: suggestions.length < 2 ? null : onNext,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-send'),
                        tooltip: 'Send command',
                        onPressed: canSend ? onSend : null,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.send_rounded),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-close'),
                        tooltip: 'Close composer',
                        onPressed: onClose,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 4),
                    for (
                      var index = 0;
                      index < suggestions.length && index < 5;
                      index++
                    )
                      _AutoComposerSuggestionTile(
                        suggestion: suggestions[index],
                        active: index == activeIndex,
                        palette: palette,
                        onTap: () => onAcceptSuggestion(suggestions[index]),
                      ),
                  ],
                ],
              ),
            ),
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

class _AutoComposerSuggestionTile extends StatelessWidget {
  const _AutoComposerSuggestionTile({
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
      key: Key('terminal-auto-composer-suggestion-$suggestion'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(palette.radius.sm),
      child: ColoredBox(
        color: active
            ? palette.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  active
                      ? Icons.keyboard_return_rounded
                      : Icons.subdirectory_arrow_right_rounded,
                  size: 15,
                  color: active ? palette.accent : palette.textSubtle,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    suggestion,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: active ? palette.textPrimary : palette.textSubtle,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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
                    _buildSheetCloseButton(
                      tooltip: 'Close instant replay',
                      onPressed: () => Navigator.of(context).pop(),
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

class _AdvancedPasteSheet extends StatefulWidget {
  const _AdvancedPasteSheet({required this.initialText});

  final String initialText;

  @override
  State<_AdvancedPasteSheet> createState() => _AdvancedPasteSheetState();
}

class _AdvancedPasteSheetState extends State<_AdvancedPasteSheet> {
  late final TextEditingController _textController;
  bool _escapeSpecialCharacters = false;
  bool _base64Encode = false;
  bool _appendNewline = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _textController.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    setState(() {});
  }

  String get _transformedText {
    return transformAdvancedPasteText(
      _textController.text,
      escapeSpecialCharacters: _escapeSpecialCharacters,
      base64Encode: _base64Encode,
      appendNewline: _appendNewline,
    );
  }

  int get _transformedByteCount {
    return utf8.encode(_transformedText).length;
  }

  void _send() {
    final text = _transformedText;
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(_AdvancedPasteSendResult(text));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final transformedText = _transformedText;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        key: const Key('advanced-paste-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
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
                          'Advanced Paste',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      AppActionButton(
                        tooltip: 'Close advanced paste',
                        tone: AppActionTone.ghost,
                        size: AppActionSize.dense,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icons.close_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('advanced-paste-text-field'),
                    controller: _textController,
                    minLines: 4,
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      labelText: 'Text',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ShellSwitchTile(
                    tileKey: const Key('advanced-paste-escape'),
                    title: 'Escape special characters',
                    value: _escapeSpecialCharacters,
                    onChanged: (value) {
                      setState(() {
                        _escapeSpecialCharacters = value;
                      });
                    },
                  ),
                  _ShellSwitchTile(
                    tileKey: const Key('advanced-paste-base64'),
                    title: 'Base64 encode',
                    value: _base64Encode,
                    onChanged: (value) {
                      setState(() {
                        _base64Encode = value;
                      });
                    },
                  ),
                  _ShellSwitchTile(
                    tileKey: const Key('advanced-paste-newline'),
                    title: 'Append newline',
                    value: _appendNewline,
                    onChanged: (value) {
                      setState(() {
                        _appendNewline = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$_transformedByteCount byte${_transformedByteCount == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: palette.textSubtle,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('advanced-paste-send'),
                        onPressed: transformedText.isEmpty ? null : _send,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Paste'),
                      ),
                    ],
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

class _CapturedOutputSheet extends StatefulWidget {
  const _CapturedOutputSheet({
    required this.entries,
    required this.onClear,
    required this.onCopy,
  });

  final List<_CapturedOutputEntry> entries;
  final VoidCallback onClear;
  final ValueChanged<String> onCopy;

  @override
  State<_CapturedOutputSheet> createState() => _CapturedOutputSheetState();
}

class _CapturedOutputSheetState extends State<_CapturedOutputSheet> {
  late List<_CapturedOutputEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('captured-output-sheet'),
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
                        'Captured Output',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppActionButton(
                      tooltip: 'Close captured output',
                      tone: AppActionTone.ghost,
                      size: AppActionSize.dense,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '${_entries.length} captured line${_entries.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      key: const Key('captured-output-clear'),
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
                              'No trigger output captured yet.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            return _CapturedOutputEntryTile(
                              index: index,
                              entry: entry,
                              palette: palette,
                              onCopy: () => widget.onCopy(entry.text),
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

class _CapturedOutputEntryTile extends StatelessWidget {
  const _CapturedOutputEntryTile({
    required this.index,
    required this.entry,
    required this.palette,
    required this.onCopy,
  });

  final int index;
  final _CapturedOutputEntry entry;
  final AppThemeTokens palette;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _ShellEntryTile(
      key: Key('captured-output-entry-$index'),
      leading: Icon(Icons.outbox_rounded, color: palette.textMuted),
      title: entry.text,
      titleMaxLines: 2,
      subtitle: 'Pattern ${entry.pattern} • Row ${entry.rowIndex}',
      subtitleMaxLines: 1,
      trailing: _buildEntryActionButton(
        key: Key('captured-output-copy-$index'),
        tooltip: 'Copy captured output',
        onPressed: onCopy,
        icon: Icons.copy_rounded,
      ),
    );
  }
}

class _AnnotationsSheet extends StatefulWidget {
  const _AnnotationsSheet({
    required this.entries,
    required this.selectedText,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_TerminalAnnotation> entries;
  final String selectedText;
  final _TerminalAnnotation Function(String note) onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_AnnotationsSheet> createState() => _AnnotationsSheetState();
}

class _AnnotationsSheetState extends State<_AnnotationsSheet> {
  late List<_TerminalAnnotation> _entries;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
    _noteController = TextEditingController();
    _noteController.addListener(_handleNoteChanged);
  }

  @override
  void dispose() {
    _noteController.removeListener(_handleNoteChanged);
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSave {
    return widget.selectedText.trim().isNotEmpty &&
        _noteController.text.trim().isNotEmpty;
  }

  void _handleNoteChanged() {
    setState(() {});
  }

  void _save() {
    if (!_canSave) {
      return;
    }
    final annotation = widget.onAdd(_noteController.text);
    setState(() {
      _entries = [annotation, ..._entries];
      _noteController.clear();
    });
  }

  void _remove(_TerminalAnnotation annotation) {
    widget.onRemove(annotation.id);
    setState(() {
      _entries = [
        for (final current in _entries)
          if (current.id != annotation.id) current,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final hasSelection = widget.selectedText.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        key: const Key('annotations-sheet'),
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
                        'Annotations',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppActionButton(
                      buttonKey: const Key('annotations-close'),
                      tooltip: 'Close annotations',
                      tone: AppActionTone.ghost,
                      size: AppActionSize.dense,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (hasSelection)
                  DecoratedBox(
                    key: const Key('annotation-selection-preview'),
                    decoration: BoxDecoration(
                      color: palette.terminalSurface,
                      borderRadius: BorderRadius.circular(palette.radius.md),
                      border: Border.all(color: palette.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.selectedText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontFamily: 'monospace',
                                height: 1.25,
                              ),
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    'Select terminal text to add an annotation.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
                  ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('annotation-note-field'),
                  controller: _noteController,
                  enabled: hasSelection,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    alignLabelWithHint: true,
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const Key('annotation-save'),
                    onPressed: _canSave ? _save : null,
                    icon: const Icon(Icons.add_comment_rounded, size: 18),
                    label: const Text('Add Annotation'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${_entries.length} annotation${_entries.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: _entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'No annotations in this session.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final annotation = _entries[index];
                            return _AnnotationEntryTile(
                              index: index,
                              annotation: annotation,
                              palette: palette,
                              onRemove: () => _remove(annotation),
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

class _AnnotationEntryTile extends StatelessWidget {
  const _AnnotationEntryTile({
    required this.index,
    required this.annotation,
    required this.palette,
    required this.onRemove,
  });

  final int index;
  final _TerminalAnnotation annotation;
  final AppThemeTokens palette;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _ShellEntryTile(
      key: Key('annotation-entry-$index'),
      leading: Icon(Icons.sticky_note_2_rounded, color: palette.textMuted),
      title: annotation.note,
      titleMaxLines: 2,
      subtitle: annotation.selectedText.replaceAll('\n', ' ⏎ '),
      subtitleMaxLines: 2,
      trailing: _buildEntryActionButton(
        key: Key('annotation-remove-$index'),
        tooltip: 'Remove annotation',
        onPressed: onRemove,
        icon: Icons.delete_outline_rounded,
      ),
    );
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
                    AppActionButton(
                      tooltip: 'Close paste history',
                      tone: AppActionTone.ghost,
                      size: AppActionSize.dense,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
                _ShellSwitchTile(
                  tileKey: const Key('paste-history-persist'),
                  title: 'Save History to Disk',
                  subtitle: 'Keep recent copied and pasted text across launches.',
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
                              const Divider(height: 1),
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
    return _ShellEntryTile(
      key: Key('paste-history-entry-$index'),
      leading: Icon(
        entry.kind == PasteHistoryKind.copy
            ? Icons.copy_rounded
            : Icons.content_paste_rounded,
        color: palette.textMuted,
      ),
      title: preview,
      titleMaxLines: 2,
      subtitle: _kindLabel,
      onTap: onTap,
    );
  }
}

class _ShellEntryTile extends StatelessWidget {
  const _ShellEntryTile({
    super.key,
    this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
  });

  final Widget? leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;
  final int titleMaxLines;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(
        title,
        maxLines: titleMaxLines,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: subtitleMaxLines,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _ShellSwitchTile extends StatelessWidget {
  const _ShellSwitchTile({
    required this.tileKey,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final Key tileKey;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return SwitchListTile(
      key: tileKey,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _PasswordManagerSheet extends StatefulWidget {
  const _PasswordManagerSheet({
    required this.entries,
    required this.promptDetected,
    required this.onAdd,
    required this.onRemove,
  });

  final List<PasswordManagerEntry> entries;
  final bool promptDetected;
  final PasswordManagerEntry Function({
    required String label,
    required String password,
  })
  onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_PasswordManagerSheet> createState() => _PasswordManagerSheetState();
}

class _PasswordManagerSheetState extends State<_PasswordManagerSheet> {
  late List<PasswordManagerEntry> _entries;
  late final TextEditingController _labelController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
    _labelController = TextEditingController();
    _passwordController = TextEditingController();
    _passwordController.addListener(_handlePasswordChanged);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_handlePasswordChanged);
    _labelController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handlePasswordChanged() {
    setState(() {});
  }

  void _addEntry() {
    final password = _passwordController.text;
    if (password.isEmpty) {
      return;
    }
    final entry = widget.onAdd(
      label: _labelController.text,
      password: password,
    );
    setState(() {
      _entries = [entry, ..._entries];
      _labelController.clear();
      _passwordController.clear();
    });
  }

  void _removeEntry(PasswordManagerEntry entry) {
    widget.onRemove(entry.id);
    setState(() {
      _entries = [
        for (final current in _entries)
          if (current.id != entry.id) current,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        key: const Key('password-manager-sheet'),
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
                        'Password Manager',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppActionButton(
                      tooltip: 'Close password manager',
                      tone: AppActionTone.ghost,
                      size: AppActionSize.dense,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
                Text(
                  widget.promptDetected
                      ? 'Password prompt detected in the active session.'
                      : 'Open a password prompt before sending a password.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('password-manager-label-field'),
                  controller: _labelController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    hintText: 'Server or account',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('password-manager-password-field'),
                  controller: _passwordController,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => _addEntry(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const Key('password-manager-add'),
                    onPressed: _addEntry,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: _entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'No saved passwords in this session.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            return _PasswordManagerEntryTile(
                              index: index,
                              entry: entry,
                              promptDetected: widget.promptDetected,
                              palette: palette,
                              onSend: () => Navigator.of(
                                context,
                              ).pop(_PasswordManagerSendResult(entry)),
                              onRemove: () => _removeEntry(entry),
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

class _PasswordManagerEntryTile extends StatelessWidget {
  const _PasswordManagerEntryTile({
    required this.index,
    required this.entry,
    required this.promptDetected,
    required this.palette,
    required this.onSend,
    required this.onRemove,
  });

  final int index;
  final PasswordManagerEntry entry;
  final bool promptDetected;
  final AppThemeTokens palette;
  final VoidCallback onSend;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _ShellEntryTile(
      key: Key('password-manager-entry-$index'),
      leading: Icon(Icons.key_rounded, color: palette.textMuted),
      title: entry.label,
      subtitle: promptDetected ? 'Ready to send' : 'Waiting for password prompt',
      trailing: Wrap(
        spacing: 4,
        children: [
          _buildEntryActionButton(
            key: Key('password-manager-remove-$index'),
            tooltip: 'Remove password',
            onPressed: onRemove,
            icon: Icons.delete_outline_rounded,
          ),
          FilledButton(
            key: Key('password-manager-send-$index'),
            onPressed: promptDetected ? onSend : null,
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

class _CoprocessIndicator extends StatelessWidget {
  const _CoprocessIndicator({
    super.key,
    required this.command,
    required this.palette,
  });

  final String command;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Coprocess: $command',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: palette.accent.withValues(alpha: 0.72)),
          boxShadow: palette.elevation.floating,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub_rounded, size: 15, color: palette.accent),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.textPrimary,
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

class _TerminalAnnotationBadge extends StatelessWidget {
  const _TerminalAnnotationBadge({
    super.key,
    required this.count,
    required this.palette,
    required this.onTap,
  });

  final int count;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(palette.radius.md),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.overlay.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(color: palette.borderStrong),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sticky_note_2_rounded,
                  size: 16,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  '$count annotation${count == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
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
        border: Border.all(color: palette.focusRing.withValues(alpha: 0.62)),
        boxShadow: palette.elevation.floating,
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
    required this.hotkeyWindowShortcutLabel,
    required this.autocompleteShortcutLabel,
    required this.copyModeShortcutLabel,
    required this.sessionCopyShortcutLabel,
    required this.sessionPasteShortcutLabel,
    required this.pasteHistoryShortcutLabel,
    required this.instantReplayShortcutLabel,
    required this.hasDefaultProfile,
    required this.hasActiveSession,
    required this.activePaneZoomed,
    required this.canReopenClosedTab,
    required this.isActiveSessionReadOnly,
    required this.commandFinishedNotificationsEnabled,
    required this.bellNotificationsEnabled,
    required this.activityMonitorEnabled,
    required this.canSelectCommandOutput,
  });

  final String launcherShortcutLabel;
  final String newTabShortcutLabel;
  final String hotkeyWindowShortcutLabel;
  final String autocompleteShortcutLabel;
  final String copyModeShortcutLabel;
  final String sessionCopyShortcutLabel;
  final String sessionPasteShortcutLabel;
  final String pasteHistoryShortcutLabel;
  final String instantReplayShortcutLabel;
  final bool hasDefaultProfile;
  final bool hasActiveSession;
  final bool activePaneZoomed;
  final bool canReopenClosedTab;
  final bool isActiveSessionReadOnly;
  final bool commandFinishedNotificationsEnabled;
  final bool bellNotificationsEnabled;
  final bool activityMonitorEnabled;
  final bool canSelectCommandOutput;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final maxMenuHeight = (MediaQuery.sizeOf(context).height - 24)
        .clamp(360.0, 560.0)
        .toDouble();

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
        constraints: BoxConstraints(maxWidth: 340, maxHeight: maxMenuHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.overlay,
            borderRadius: BorderRadius.circular(palette.radius.xl),
            border: Border.all(color: palette.borderStrong),
            boxShadow: palette.elevation.dialog,
          ),
          child: Material(
            type: MaterialType.transparency,
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
                          _buildSheetCloseButton(
                            tooltip: 'Close actions',
                            onPressed: () => Navigator.of(context).pop(),
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
                          Navigator.of(context).pop(TerminalActionId.newTab),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-command-defaults'),
                      icon: Icons.tune_rounded,
                      title: 'Defaults & appearance',
                      subtitle:
                          'App action • Pick the default profile and theme.',
                      enabled: true,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.defaults),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-reopen-closed-tab'),
                      icon: Icons.restore_rounded,
                      title: 'Reopen closed tab',
                      subtitle:
                          'App action • Recreate the most recently closed tab.',
                      enabled: canReopenClosedTab,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.reopenClosedTab),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-toolbelt'),
                      icon: Icons.view_sidebar_rounded,
                      title: 'Toolbelt',
                      subtitle:
                          'App action • Keep terminal tools in a sidebar.',
                      enabled: hasActiveSession,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.toolbelt),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-split-right'),
                      icon: Icons.vertical_split_rounded,
                      title: 'Split right',
                      subtitle: 'Session action • Add a pane to the right.',
                      enabled: hasDefaultProfile && hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.splitRight),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-split-down'),
                      icon: Icons.horizontal_split_rounded,
                      title: 'Split down',
                      subtitle: 'Session action • Add a pane below.',
                      enabled: hasDefaultProfile && hasActiveSession,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.splitDown),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-zoom-pane'),
                      icon: Icons.zoom_out_map_rounded,
                      title: activePaneZoomed
                          ? 'Unzoom active pane'
                          : 'Zoom active pane',
                      subtitle: 'Session action • Focus one pane temporarily.',
                      enabled: hasActiveSession,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.zoomPane),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-theme-picker'),
                      icon: Icons.palette_rounded,
                      title: 'Theme picker',
                      subtitle: 'App action • Open appearance controls.',
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.openThemePicker),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-export-scrollback'),
                      icon: Icons.ios_share_rounded,
                      title: 'Export scrollback',
                      subtitle:
                          'App action • Save historical scrollback when available.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.exportScrollback),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-toggle-command-finished-notify'),
                      icon: Icons.notifications_active_rounded,
                      title:
                          '${commandFinishedNotificationsEnabled ? 'Disable' : 'Enable'} command-finished notifications',
                      subtitle:
                          'App action • Toggle shell hook completion alerts.',
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.toggleCommandFinishedNotify),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-toggle-bell-notify'),
                      icon: Icons.notifications_rounded,
                      title:
                          '${bellNotificationsEnabled ? 'Disable' : 'Enable'} bell notifications',
                      subtitle: 'App action • Toggle terminal bell alerts.',
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.toggleBellNotify),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-toggle-activity-monitor'),
                      icon: Icons.notification_important_rounded,
                      title:
                          '${activityMonitorEnabled ? 'Disable' : 'Enable'} activity monitor',
                      subtitle:
                          'App action • Toggle inactive-session activity alerts.',
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.toggleActivityMonitor),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-command-profiles'),
                      icon: Icons.folder_open_rounded,
                      title: 'Profiles…',
                      subtitle: 'App action • Open or edit shell profiles.',
                      enabled: true,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.profiles),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-dynamic-profiles'),
                      icon: Icons.data_object_rounded,
                      title: 'Dynamic profiles',
                      subtitle:
                          'App action • Import iTerm-style JSON profiles.',
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.dynamicProfiles),
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
                          Navigator.of(context).pop(TerminalActionId.copy),
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
                          Navigator.of(context).pop(TerminalActionId.copyMode),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-toggle-read-only'),
                      icon: Icons.lock_outline_rounded,
                      title:
                          '${isActiveSessionReadOnly ? 'Disable' : 'Enable'} read-only mode',
                      subtitle:
                          'Session action • Block terminal input for this pane.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.toggleReadOnly),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-clear-scrollback'),
                      icon: Icons.clear_all_rounded,
                      title: 'Clear scrollback',
                      subtitle:
                          'Session action • Clear local scrollback when supported.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.clearScrollback),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-annotations'),
                      icon: Icons.sticky_note_2_rounded,
                      title: 'Annotations',
                      subtitle:
                          'Session action • Attach notes to selected output.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.annotations),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-captured-output'),
                      icon: Icons.outbox_rounded,
                      title: 'Captured output',
                      subtitle:
                          'Session action • Review lines matched by triggers.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.capturedOutput),
                    ),
                    _ShellCommandTile(
                      icon: Icons.content_paste_rounded,
                      title: 'Paste clipboard',
                      subtitle:
                          'Session action • Paste clipboard into the shell.',
                      shortcutLabel: sessionPasteShortcutLabel,
                      enabled: hasActiveSession,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.paste),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-advanced-paste'),
                      icon: Icons.assignment_rounded,
                      title: 'Advanced paste',
                      subtitle:
                          'Session action • Edit and transform text before pasting.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.advancedPaste),
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
                      ).pop(TerminalActionId.pasteHistory),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-integration-utilities'),
                      icon: Icons.integration_instructions_rounded,
                      title: 'Shell integration',
                      subtitle:
                          'Session action • Command history, directories, and marks.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.shellIntegrationUtilities),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-select-command-output'),
                      icon: Icons.fact_check_rounded,
                      title: 'Select command output',
                      subtitle:
                          'Session action • Select output between prompt marks.',
                      enabled: hasActiveSession && canSelectCommandOutput,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.selectCommandOutput),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-tmux-integration'),
                      icon: Icons.account_tree_rounded,
                      title: 'tmux integration',
                      subtitle:
                          'Session action • Start or drive tmux control mode.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.tmuxIntegration),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-coprocess'),
                      icon: Icons.hub_rounded,
                      title: 'Coprocess',
                      subtitle:
                          'Session action • Automate replies from terminal output.',
                      enabled: hasActiveSession,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.coprocess),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-password-manager'),
                      icon: Icons.password_rounded,
                      title: 'Password manager',
                      subtitle:
                          'Session action • Send saved passwords at prompts.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.passwordManager),
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
                      ).pop(TerminalActionId.instantReplay),
                    ),
                    _ShellCommandTile(
                      icon: Icons.search_rounded,
                      title: 'Search scrollback',
                      subtitle: 'Session action • Find text in local output.',
                      enabled: hasActiveSession,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.search),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-global-search'),
                      icon: Icons.manage_search_rounded,
                      title: 'Global search',
                      subtitle: 'Workspace action • Search all tabs at once.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.globalSearch),
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
                      ).pop(TerminalActionId.autocomplete),
                    ),
                    _ShellCommandTile(
                      key: const Key('shell-auto-composer'),
                      icon: Icons.edit_note_rounded,
                      title: 'Auto Composer',
                      subtitle:
                          'Session action • Native command editor with completions.',
                      enabled: hasActiveSession,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.autoComposer),
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
                      ).pop(TerminalActionId.hotkeyWindow),
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
      hoverColor: _shellTileHoverColor(palette),
      focusColor: _shellTileFocusColor(palette),
      leading: Icon(icon, color: enabled ? palette.accent : palette.textSubtle),
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

Color _shellTileHoverColor(AppThemeTokens palette) {
  return palette.selected.withValues(alpha: 0.44);
}

Color _shellTileFocusColor(AppThemeTokens palette) {
  return palette.selected.withValues(alpha: 0.56);
}

Widget _buildSheetCloseButton({
  required String tooltip,
  required VoidCallback onPressed,
  Key? buttonKey,
}) {
  return AppActionButton(
    buttonKey: buttonKey,
    tooltip: tooltip,
    tone: AppActionTone.ghost,
    size: AppActionSize.dense,
    onPressed: onPressed,
    icon: Icons.close_rounded,
  );
}

Widget _buildCompactActionButton({
  required Key key,
  required String tooltip,
  required Widget icon,
  required VoidCallback? onPressed,
  double? splashRadius,
  double? iconSize,
  bool isSelected = false,
  Widget? selectedIcon,
}) {
  return IconButton(
    key: key,
    tooltip: tooltip,
    isSelected: isSelected,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    splashRadius: splashRadius,
    iconSize: iconSize,
    selectedIcon: selectedIcon,
    icon: icon,
  );
}

Widget _buildEntryActionButton({
  required Key key,
  required String tooltip,
  required IconData icon,
  required VoidCallback? onPressed,
}) {
  return Builder(
    builder: (context) {
      return IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: context.appTheme.textMuted),
      );
    },
  );
}

Widget _buildChromeIconButton({
  required Key key,
  required String tooltip,
  required Widget icon,
  required VoidCallback? onPressed,
  required double iconSize,
}) {
  return IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    splashRadius: 16,
    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
    iconSize: iconSize,
    icon: icon,
  );
}
