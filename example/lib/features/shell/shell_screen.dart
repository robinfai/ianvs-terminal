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
import 'shell_shortcut_bridge.dart';
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
  final terminal.TerminalSearchMatch match;
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
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'shell-search');
  final Map<String, Size> _scheduledViewportSizes = {};
  final Map<String, Size> _committedViewportSizes = {};
  final Map<String, Size> _measuredTerminalCellSizes = {};
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
    _searchFocusNode.dispose();
    _autoComposerController.dispose();
    _autoComposerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleNativePasteMenu() async {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    await _pasteToSession(activeSessionId);
  }

  Future<void> _handleNativeFindMenu(NativeFindAction action) async {
    if (!mounted) {
      return;
    }
    switch (action) {
      case NativeFindAction.next:
        if (!_isSearchOpen) {
          _openSearch();
          return;
        }
        _moveSearchMatch(1);
        return;
      case NativeFindAction.previous:
        if (!_isSearchOpen) {
          _openSearch();
          return;
        }
        _moveSearchMatch(-1);
        return;
      case NativeFindAction.show:
      case NativeFindAction.replace:
      case NativeFindAction.useSelection:
      case NativeFindAction.jumpToSelection:
        _openSearch();
        return;
    }
  }

  void _handleTerminalSessionEvent(terminal.TerminalSessionEvent event) {
    switch (event) {
      case terminal.TerminalSessionFrameEvent(:final sessionId, :final frame):
        final frameSequence =
            (_terminalFrameSequenceBySession[sessionId] ?? 0) + 1;
        _terminalFrameSequenceBySession[sessionId] = frameSequence;
        ref.read(instantReplayStoreProvider).record(sessionId, frame);
        _markNewOutputBadge(sessionId, frame);
        _feedCoprocess(sessionId, frame, frameSequence: frameSequence);
        _runProfileTriggers(sessionId, frame, frameSequence: frameSequence);
        _notifyInactiveActivity(sessionId, frame);
        _refreshSearchMatchesAfterFrame(sessionId, frame);
        _scheduleRenderableSessionSwap(sessionId);
      case terminal.TerminalSessionExitEvent():
        _terminalFrameSequenceBySession.remove(event.sessionId);
        _lastNewOutputFramePreviews.remove(event.sessionId);
        _searchRefreshFrameSignatures.remove(event.sessionId);
        _sessionsSeenForNewOutputBadges.remove(event.sessionId);
        _sessionsWithNewOutput.remove(event.sessionId);
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
        identifier: 'ianvs-terminal.activity.$sessionId',
      );
    }
  }

  void _markNewOutputBadge(String sessionId, terminal.TerminalFrameDiff frame) {
    final preview = _framePreview(frame);
    final hasSeenSession = !_sessionsSeenForNewOutputBadges.add(sessionId);
    final previousPreview = _lastNewOutputFramePreviews[sessionId];
    _lastNewOutputFramePreviews[sessionId] = preview;
    if (!hasSeenSession ||
        previousPreview == preview ||
        preview == null ||
        !_sessionTabIsInactive(sessionId)) {
      return;
    }
    if (_sessionsWithNewOutput.contains(sessionId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _sessionsWithNewOutput.add(sessionId);
    });
  }

  void _notifySessionExit(String sessionId, int? exitCode) {
    _sendShellNotification(
      title: 'Session ended',
      body:
          '${_sessionTitleForNotification(sessionId)} exited${exitCode == null ? '' : ' with code $exitCode'}.',
      identifier:
          'ianvs-terminal.exit.$sessionId.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  void _notifyBell(String sessionId) {
    if (!_bellNotificationsEnabled) {
      return;
    }
    _sendShellNotification(
      title: 'Bell in ${_sessionTitleForNotification(sessionId)}',
      body: 'The terminal requested attention.',
      identifier: 'ianvs-terminal.bell.$sessionId',
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
          'ianvs-terminal.command.${event.sessionId}.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  Future<void> _loadNotificationPreferences() async {
    final configBootstrap = await _loadNotificationConfig();
    final preferences = LocalTerminalConfigPreferencesAdapter.toAppPreferences(
      configBootstrap.config,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationConfigSource = configBootstrap.source;
      _notificationLocalConfig = configBootstrap.config;
      _keybindingsConfig = configBootstrap.config.keybindings;
      _clipboardConfig = configBootstrap.config.clipboard;
      _bracketedPastePolicy = configBootstrap.config.paste.bracketedPaste;
      _pastePolicy = _pastePolicyFromConfig(configBootstrap.config.paste);
      _pasteHistoryPolicy = _pasteHistoryPolicyFromConfig(
        configBootstrap.config.paste,
      );
      _pasteHistoryEntries = _pasteHistoryEntries
          .take(_effectivePasteHistoryLimit)
          .toList();
      _commandFinishedNotificationsEnabled =
          preferences.notifications.commandFinished;
      _bellNotificationsEnabled = preferences.notifications.bell;
      _activityNotificationsEnabled = preferences.notifications.activity;
    });
  }

  Future<LocalTerminalConfigBootstrapResult> _loadNotificationConfig() async {
    try {
      return await ref.read(localTerminalConfigLoaderProvider).load();
    } on Object {
      final legacyPreferences = await ref
          .read(appPreferencesRepositoryProvider)
          .load();
      return LocalTerminalConfigBootstrap.resolve(
        localConfig: null,
        legacyAppPreferences: legacyPreferences,
      );
    }
  }

  Future<void> _saveNotificationPreferences() async {
    final notifications = TerminalAppNotifications(
      commandFinished: _commandFinishedNotificationsEnabled,
      bell: _bellNotificationsEnabled,
      activity: _activityNotificationsEnabled,
    );
    final localConfig = await _loadLocalNotificationConfigForSave();
    if (localConfig != null) {
      final nextConfig = localConfig.copyWith(
        notifications: LocalTerminalNotificationsConfig(
          enabled:
              notifications.commandFinished ||
              notifications.bell ||
              notifications.activity,
          commandFinished: notifications.commandFinished,
          bell: notifications.bell,
          activity: notifications.activity,
        ),
      );
      _notificationConfigSource =
          LocalTerminalConfigBootstrapSource.localConfig;
      _notificationLocalConfig = nextConfig;
      await ref.read(localTerminalConfigRepositoryProvider).save(nextConfig);
      return;
    }

    final repository = ref.read(appPreferencesRepositoryProvider);
    final preferences =
        await repository.load() ?? const TerminalAppPreferencesDocument();
    await repository.save(preferences.copyWith(notifications: notifications));
  }

  Future<LocalTerminalConfigDocument?>
  _loadLocalNotificationConfigForSave() async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    if (_notificationConfigSource ==
        LocalTerminalConfigBootstrapSource.localConfig) {
      return await repository.load() ?? _notificationLocalConfig;
    }
    return repository.load();
  }

  LocalTerminalPastePolicy _pastePolicyFromConfig(
    LocalTerminalPasteConfig config,
  ) {
    return LocalTerminalPastePolicy(
      confirmLargePaste: config.confirmLargePaste,
      confirmMultilinePaste: config.confirmMultilinePaste,
      historySize: config.historySize,
    );
  }

  LocalTerminalPasteHistoryPolicy _pasteHistoryPolicyFromConfig(
    LocalTerminalPasteConfig config,
  ) {
    return LocalTerminalPasteHistoryPolicy(
      enabled: config.historySize > 0,
      maxEntries: config.historySize,
    );
  }

  terminal.TerminalFrameModes _pasteModesFor(
    terminal.TerminalFrameModes frameModes,
  ) {
    return switch (_bracketedPastePolicy) {
      LocalTerminalBracketedPastePolicy.auto => frameModes,
      LocalTerminalBracketedPastePolicy.force =>
        const terminal.TerminalFrameModes(bracketedPaste: true),
      LocalTerminalBracketedPastePolicy.plain =>
        terminal.TerminalFrameModes.empty,
    };
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
              'ianvs-terminal.trigger.$sessionId.${trigger.pattern.hashCode}.${DateTime.now().microsecondsSinceEpoch}',
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

  bool _sessionTabIsInactive(String sessionId) {
    final sessionState = ref.read(sessionControllerProvider);
    final activeSessionId = sessionState.activeSessionId;
    if (activeSessionId == null) {
      return true;
    }
    for (final tab in sessionState.tabs) {
      if (tab.containsSession(sessionId)) {
        return !tab.containsSession(activeSessionId);
      }
    }
    return true;
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
      _dispatchShellNotification(
        title: title,
        body: body,
        identifier: identifier,
      ),
    );
  }

  void _closeToolbelt() {
    if (!_isToolbeltOpen) {
      return;
    }
    setState(() {
      _isToolbeltOpen = false;
    });
  }

  void _openToolbeltChild(Future<void> Function() open) {
    _closeToolbelt();
    unawaited(open());
  }

  Future<void> _dispatchShellNotification({
    required String title,
    String? body,
    required String identifier,
  }) async {
    try {
      await ref.read(shellNotificationSenderProvider)(
        title: title,
        body: body,
        identifier: identifier,
      );
      if (mounted && _notificationsBlockedBySystem) {
        setState(() {
          _notificationsBlockedBySystem = false;
        });
      }
    } on PlatformException catch (error) {
      if (mounted &&
          error.code == 'notification_authorization_failed' &&
          !_notificationsBlockedBySystem) {
        setState(() {
          _notificationsBlockedBySystem = true;
        });
      }
      if (!mounted || !_notificationFailureCodesShown.add(error.code)) {
        return;
      }
      final message = switch (error.code) {
        'notification_authorization_failed' =>
          'macOS notifications are blocked for Ianvs Terminal. Enable them in System Settings > Notifications.',
        'notification_delivery_failed' =>
          'Ianvs Terminal could not deliver a macOS notification right now.',
        _ => null,
      };
      if (message == null) {
        return;
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
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
    return _usesMetaShortcuts ? '⌘⇧H' : 'Ctrl+Shift+H';
  }

  String _instantReplayShortcutLabel() {
    return _usesMetaShortcuts ? '⌥⌘B' : 'Alt+Ctrl+B';
  }

  String _searchShortcutLabel() {
    return _usesMetaShortcuts ? '⌘F' : 'Ctrl+F';
  }

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

    for (final scope in const <TerminalKeyBindingScope>[
      TerminalKeyBindingScope.terminalFocused,
      TerminalKeyBindingScope.focusedApp,
      TerminalKeyBindingScope.global,
    ]) {
      final actionId = ShellShortcutBridge.resolve(
        key: event.logicalKey,
        usesMetaShortcuts: usesMetaShortcuts,
        isMetaPressed: isMetaPressed,
        isControlPressed: isControlPressed,
        isShiftPressed: isShiftPressed,
        isAltPressed: isAltPressed,
        scope: scope,
        config: _keybindingsConfig,
      );
      if (actionId != null) {
        return _ShellShortcut(actionId);
      }
    }

    if (usesAppModifier && !isShiftPressed && !isAltPressed) {
      final tabIndex = _tabShortcutIndexFor(event.logicalKey);
      if (tabIndex != null) {
        return _ShellShortcut(TerminalActionId.activateTab, tabIndex: tabIndex);
      }
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

  List<_ShellStatusModeItem> _statusModeItemsFor(
    String sessionId,
    terminal.TerminalFrameModes modes,
  ) {
    final items = <_ShellStatusModeItem>[];
    if (modes.alternateScreen) {
      items.add(
        const _ShellStatusModeItem(
          key: Key('shell-status-mode-alt'),
          label: 'ALT',
          tooltip: 'Alternate screen buffer is active.',
          semanticsLabel: 'Terminal mode: alternate screen buffer active',
        ),
      );
    }
    if (modes.mouseMode != 'off') {
      final mouseMode = _mouseModeStatusLabel(modes.mouseMode);
      final mouseEncoding = _mouseEncodingStatusLabel(modes.mouseEncoding);
      items.add(
        _ShellStatusModeItem(
          key: const Key('shell-status-mode-mouse'),
          label: 'MOUSE',
          tooltip: 'Mouse reporting is active: $mouseMode, $mouseEncoding.',
          semanticsLabel: 'Terminal mode: mouse reporting active',
        ),
      );
    }
    if (modes.bracketedPaste) {
      items.add(
        const _ShellStatusModeItem(
          key: Key('shell-status-mode-paste'),
          label: 'PASTE',
          tooltip: 'Bracketed paste mode is active.',
          semanticsLabel: 'Terminal mode: bracketed paste active',
        ),
      );
    }
    if (_isSessionReadOnly(sessionId)) {
      items.add(
        const _ShellStatusModeItem(
          key: Key('shell-status-mode-read-only'),
          label: 'READ ONLY',
          tooltip:
              'Read-only mode is enabled for this pane. Input and paste sends are blocked.',
          semanticsLabel: 'Terminal pane is read-only',
        ),
      );
    }
    return items;
  }

  String _mouseModeStatusLabel(String mode) {
    return switch (mode) {
      'normal' => 'normal tracking',
      'button_event' => 'button-event tracking',
      'any_event' => 'any-event tracking',
      _ => mode.replaceAll('_', ' '),
    };
  }

  String _mouseEncodingStatusLabel(String encoding) {
    return switch (encoding) {
      'sgr' => 'SGR encoding',
      'utf8' => 'UTF-8 encoding',
      'urxvt' => 'URXVT encoding',
      'default' => 'default encoding',
      _ => '${encoding.replaceAll('_', ' ')} encoding',
    };
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
    _refreshSearchMatchesAfterResize(sessionId);
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

  void _scheduleWorkspaceCue(String title) {
    _showReturningCueOnNextFocus = true;
    _workspaceCueTitle = title;
    _recentlyClosedLastSession = false;
  }

  void _scheduleReturningCue() {
    _scheduleWorkspaceCue('Back in shell');
  }

  void _showScheduledWorkspaceCueNow() {
    if (!_showReturningCueOnNextFocus) {
      return;
    }
    _workspaceCueTimer?.cancel();
    _workspaceCueTimer = null;
    setState(() {
      _showWorkspaceCue = true;
      _showReturningCueOnNextFocus = false;
    });
    _workspaceCueTimer = Timer(_workspaceCueDuration, () {
      if (!mounted || !_showWorkspaceCue) {
        return;
      }
      setState(() {
        _showWorkspaceCue = false;
      });
    });
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
    _clearNewOutputForTab(
      _tabForSession(ref.read(sessionControllerProvider), sessionId),
    );
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

  bool _tabHasNewOutput(TerminalTab tab) {
    return tab.effectivePanes.any(
      (pane) => _sessionsWithNewOutput.contains(pane.sessionId),
    );
  }

  Color _tabTerminalBackgroundColor(
    BuildContext context,
    SessionState sessionState,
    TerminalTab tab,
  ) {
    final profile = _profileForPane(tab.activePane, sessionState.profiles);
    return _terminalColorsForProfile(context, profile).canvasBackground;
  }

  void _clearNewOutputForTab(TerminalTab? tab) {
    if (tab == null) {
      return;
    }
    var changed = false;
    for (final pane in tab.effectivePanes) {
      changed = _sessionsWithNewOutput.remove(pane.sessionId) || changed;
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  void _clearNewOutputForSessions(Iterable<String> sessionIds) {
    for (final sessionId in sessionIds) {
      _sessionsWithNewOutput.remove(sessionId);
      _sessionsSeenForNewOutputBadges.remove(sessionId);
      _lastNewOutputFramePreviews.remove(sessionId);
    }
  }

  String? _splitAxisConflictReason(
    SessionState sessionState,
    String? sessionId,
    TerminalSplitAxis requestedAxis,
  ) {
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
    _scheduleWorkspaceCue('Pane ${normalizedIndex + 1} of ${panes.length}');
    _activateSession(sessionController, panes[normalizedIndex].sessionId);
    return true;
  }

  bool _growActivePane(TerminalTab activeTab, String activeSessionId) {
    if (_growActivePaneUnavailableReason(activeTab, activeSessionId) != null) {
      return false;
    }
    ref.read(sessionControllerProvider.notifier).growPane(activeSessionId);
    return true;
  }

  String? _growActivePaneUnavailableReason(
    TerminalTab activeTab,
    String activeSessionId,
  ) {
    final panes = activeTab.effectivePanes;
    if (panes.length < 2 || !activeTab.containsSession(activeSessionId)) {
      return 'Add another pane to use this action.';
    }

    if (_paneGrowthWouldShrinkSiblingTooFar(
      activeTab.effectivePaneLayout,
      activeSessionId,
    )) {
      return activeTab.splitAxis == TerminalSplitAxis.horizontal
          ? 'Another pane would become narrower than $_minimumHorizontalPaneCols columns.'
          : 'Another pane would become shorter than $_minimumVerticalPaneRows rows.';
    }

    final sessionController = ref.read(sessionControllerProvider.notifier);
    for (final pane in panes) {
      if (pane.sessionId == activeSessionId) {
        continue;
      }
      final frame = sessionController.viewportFor(pane.sessionId).frame;
      final primarySize = activeTab.splitAxis == TerminalSplitAxis.horizontal
          ? frame.viewportCols
          : frame.viewportRows;
      final minimumPrimarySize =
          activeTab.splitAxis == TerminalSplitAxis.horizontal
          ? _minimumHorizontalPaneCols
          : _minimumVerticalPaneRows;
      if (primarySize <= minimumPrimarySize) {
        return activeTab.splitAxis == TerminalSplitAxis.horizontal
            ? 'Another pane would become narrower than $_minimumHorizontalPaneCols columns.'
            : 'Another pane would become shorter than $_minimumVerticalPaneRows rows.';
      }
    }
    return null;
  }

  bool _paneGrowthWouldShrinkSiblingTooFar(
    TerminalPaneLayoutNode node,
    String activeSessionId,
  ) {
    if (node.isLeaf) {
      return false;
    }
    final first = node.first!;
    final second = node.second!;
    if (first.containsSession(activeSessionId)) {
      if (!first.isLeaf) {
        return _paneGrowthWouldShrinkSiblingTooFar(first, activeSessionId);
      }
      return 1 - (node.ratio + _paneGrowRatioStep) < _minimumSiblingPaneRatio;
    }
    if (second.containsSession(activeSessionId)) {
      if (!second.isLeaf) {
        return _paneGrowthWouldShrinkSiblingTooFar(second, activeSessionId);
      }
      return node.ratio - _paneGrowRatioStep < _minimumSiblingPaneRatio;
    }
    return false;
  }

  String? _zoomedPaneManagementUnavailableReason(TerminalTab tab) {
    final zoomedPaneSessionId = _zoomedPaneSessionId;
    if (zoomedPaneSessionId == null ||
        !tab.containsSession(zoomedPaneSessionId)) {
      return null;
    }
    return 'Unzoom the active pane to manage other panes.';
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

  Future<Directory?> _exportDiagnosticsBundle(SessionState state) async {
    final runtime = ref.read(terminalRuntimeControllerProvider);
    final seenSessionIds = <String>{};
    final exports = <terminal.TerminalDiagnosticsExport>[];
    for (final tab in state.tabs) {
      for (final pane in tab.effectivePanes) {
        final sessionId = pane.sessionId;
        if (!seenSessionIds.add(sessionId) || !runtime.hasSession(sessionId)) {
          continue;
        }
        final export = runtime.exportSessionDiagnostics(sessionId);
        if (export != null) {
          exports.add(export);
        }
      }
    }
    if (exports.isEmpty) {
      return null;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final exportDirectory = Directory(
      '${supportDirectory.path}/diagnostic_exports',
    );
    final basename = 'diagnostics-${DateTime.now().millisecondsSinceEpoch}';
    return LocalTerminalDiagnosticsExporter.write(
      directory: exportDirectory,
      basename: basename,
      exports: exports,
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
    final currentState = ref.read(sessionControllerProvider);
    final activeSessionId = currentState.activeSessionId;
    final conflictReason = _splitAxisConflictReason(
      currentState,
      activeSessionId,
      axis,
    );
    if (conflictReason != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(conflictReason)));
      return;
    }
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
    _clearNewOutputForSessions([sessionId]);
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
    _clearNewOutputForSessions(
      closingTab.effectivePanes.map((pane) => pane.sessionId),
    );
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
    final focusNode = _focusNodeFor(activeSessionIdBeforeOpen);
    if (focusNode.hasFocus) {
      _showScheduledWorkspaceCueNow();
      return;
    }
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
    ].take(_effectivePasteHistoryLimit).toList();

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

  int get _effectivePasteHistoryLimit {
    if (_pasteHistoryPolicy.maxEntries <= 0) {
      return 0;
    }
    return math.min(_pasteHistoryLimit, _pasteHistoryPolicy.maxEntries);
  }

  List<PasteHistoryEntry> _mergePasteHistoryEntries(
    List<PasteHistoryEntry> leading,
    List<PasteHistoryEntry> trailing,
  ) {
    final seenTexts = <String>{};
    return <PasteHistoryEntry>[
      for (final entry in [...leading, ...trailing])
        if (entry.text.trim().isNotEmpty && seenTexts.add(entry.text)) entry,
    ].take(_effectivePasteHistoryLimit).toList();
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
      pastePolicy: _pastePolicy,
      historyPolicy: _pasteHistoryPolicy,
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
    final preview = _pasteConfirmationPreview(decision.text);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const Key('paste-confirmation-dialog'),
          title: const Text('Confirm paste'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste ${decision.text.length} characters across $lineCount lines?',
              ),
              const SizedBox(height: 12),
              Text(
                'Preview',
                style: Theme.of(
                  dialogContext,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(dialogContext).colorScheme.outlineVariant,
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      preview,
                      key: const Key('paste-confirmation-preview'),
                      style: Theme.of(
                        dialogContext,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
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

  String _pasteConfirmationPreview(String text) {
    const maxLines = 6;
    const maxCharacters = 240;
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final previewLines = lines.take(maxLines).toList();
    var preview = previewLines.join('\n');
    var truncated = lines.length > maxLines;
    if (preview.length > maxCharacters) {
      preview = preview.substring(0, maxCharacters).trimRight();
      truncated = true;
    }
    return truncated ? '$preview\n...' : preview;
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
            modes: _pasteModesFor(frame.modes),
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
    final integration = _integrationWithEffectivePromptMarks(
      sessionId,
      pane.shellIntegration,
    );
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
        final decision = LocalTerminalPasteDecisionResolver.resolve(
          text: entry.text,
          readOnly: _isSessionReadOnly(currentActiveSessionId),
          pastePolicy: _pastePolicy,
          historyPolicy: _pasteHistoryPolicy,
        );
        switch (decision.kind) {
          case LocalTerminalPasteDecisionKind.blockedReadOnly:
            _restoreSessionFocus(
              activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
              activeSessionIdAfterClose: currentActiveSessionId,
            );
            return;
          case LocalTerminalPasteDecisionKind.requireConfirmation:
            final confirmed = await _confirmPaste(decision);
            if (!confirmed) {
              _restoreSessionFocus(
                activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
                activeSessionIdAfterClose: currentActiveSessionId,
              );
              return;
            }
          case LocalTerminalPasteDecisionKind.sendImmediately:
            break;
        }
        await _pasteTextToSession(currentActiveSessionId, decision.text);
        if (decision.captureHistory) {
          await _recordPasteHistory(decision.text, PasteHistoryKind.paste);
        }
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
      _searchFocusRequestSerial += 1;
    });
    if (_searchQuery.isNotEmpty) {
      _searchScrollback(_searchQuery);
    }
    _requestSearchFocus();
  }

  void _requestSearchFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isSearchOpen) {
        return;
      }
      _searchFocusNode.requestFocus();
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (!mounted || !_isSearchOpen) {
          return;
        }
        _searchFocusNode.requestFocus();
      }),
    );
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _searchErrorText = null;
      _searchMatches = const [];
      _activeSearchIndex = 0;
      _searchFocusRequestSerial += 1;
    });
    _requestSearchFocus();
  }

  void _searchScrollback(String query) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final result = ref
        .read(terminalRuntimeControllerProvider)
        .searchTextResult(activeSessionId, query, mode: _searchMode);
    final activeIndex = _defaultSearchActiveIndex(result.matches);
    setState(() {
      _searchQuery = query;
      _searchErrorText = result.errorText;
      _searchMatches = result.matches;
      _activeSearchIndex = activeIndex;
    });
    if (result.matches.isNotEmpty) {
      ref
          .read(terminalRuntimeControllerProvider)
          .scrollViewportTo(
            activeSessionId,
            result.matches[activeIndex].scrollbackOffset,
          );
    }
    _rememberSearchRefreshFrameSignature(activeSessionId);
  }

  int _defaultSearchActiveIndex(List<terminal.TerminalSearchMatch> matches) {
    return matches.isEmpty ? 0 : matches.length - 1;
  }

  void _refreshSearchMatchesAfterResize(String sessionId) {
    _refreshSearchMatchesForSession(sessionId);
  }

  void _refreshSearchMatchesAfterFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (!_searchRefreshAllowedForSession(sessionId)) {
      return;
    }
    final signature = _searchRefreshFrameSignature(frame);
    if (_searchRefreshFrameSignatures[sessionId] == signature) {
      return;
    }
    _searchRefreshFrameSignatures[sessionId] = signature;
    _refreshSearchMatchesForSession(sessionId, frame: frame);
  }

  bool _searchRefreshAllowedForSession(String sessionId) {
    if (!_isSearchOpen || _searchQuery.isEmpty) {
      return false;
    }
    if (ref.read(sessionControllerProvider).activeSessionId != sessionId) {
      return false;
    }
    return true;
  }

  void _refreshSearchMatchesForSession(
    String sessionId, {
    terminal.TerminalFrameDiff? frame,
  }) {
    if (!_searchRefreshAllowedForSession(sessionId)) {
      return;
    }
    final previousActiveIndex = _activeSearchIndex;
    final previousActiveMatch =
        previousActiveIndex >= 0 && previousActiveIndex < _searchMatches.length
        ? _searchMatches[previousActiveIndex]
        : null;
    final result = ref
        .read(terminalRuntimeControllerProvider)
        .searchTextResult(sessionId, _searchQuery, mode: _searchMode);
    if (!mounted) {
      return;
    }
    setState(() {
      _searchErrorText = result.errorText;
      _searchMatches = result.matches;
      _activeSearchIndex = _refreshedSearchActiveIndex(
        result.matches,
        previousActiveMatch: previousActiveMatch,
        previousActiveIndex: previousActiveIndex,
      );
    });
    if (frame == null) {
      _rememberSearchRefreshFrameSignature(sessionId);
    }
  }

  void _rememberSearchRefreshFrameSignature(String sessionId) {
    final frame = ref
        .read(terminalRuntimeControllerProvider)
        .viewportFor(sessionId)
        .frame;
    _searchRefreshFrameSignatures[sessionId] = _searchRefreshFrameSignature(
      frame,
    );
  }

  String _searchRefreshFrameSignature(terminal.TerminalFrameDiff frame) {
    final buffer = StringBuffer()
      ..write(frame.viewportStartRow)
      ..write('|')
      ..write(frame.viewportRows)
      ..write('|')
      ..write(frame.viewportCols)
      ..write('|')
      ..write(frame.scrollbackOffset)
      ..write('|')
      ..write(frame.scrollbackMaxOffset)
      ..write('|')
      ..write(frame.rows.length);
    for (final row in frame.rows) {
      buffer
        ..write('|')
        ..write(row.index)
        ..write(':')
        ..write(row.wrapped ? 1 : 0)
        ..write(':')
        ..write(row.text);
    }
    return buffer.toString();
  }

  int _refreshedSearchActiveIndex(
    List<terminal.TerminalSearchMatch> matches, {
    required terminal.TerminalSearchMatch? previousActiveMatch,
    required int previousActiveIndex,
  }) {
    if (matches.isEmpty) {
      return 0;
    }
    if (previousActiveMatch == null) {
      return 0;
    }
    final exactIndex = _closestSearchMatchIndex(
      matches,
      previousActiveIndex,
      (match) =>
          match.row == previousActiveMatch.row &&
          match.startCol == previousActiveMatch.startCol &&
          match.endCol == previousActiveMatch.endCol &&
          match.scrollbackOffset == previousActiveMatch.scrollbackOffset &&
          match.text == previousActiveMatch.text,
    );
    if (exactIndex != -1) {
      return exactIndex;
    }
    final stableContentIndex = _closestSearchMatchIndex(
      matches,
      previousActiveIndex,
      (match) =>
          match.scrollbackOffset == previousActiveMatch.scrollbackOffset &&
          match.text == previousActiveMatch.text,
    );
    if (stableContentIndex != -1) {
      return stableContentIndex;
    }
    return previousActiveIndex.clamp(0, matches.length - 1).toInt();
  }

  int _closestSearchMatchIndex(
    List<terminal.TerminalSearchMatch> matches,
    int preferredIndex,
    bool Function(terminal.TerminalSearchMatch match) matchesIdentity,
  ) {
    var bestIndex = -1;
    var bestDistance = 1 << 30;
    for (var index = 0; index < matches.length; index += 1) {
      if (!matchesIdentity(matches[index])) {
        continue;
      }
      final distance = (index - preferredIndex).abs();
      if (distance < bestDistance) {
        bestIndex = index;
        bestDistance = distance;
      }
    }
    return bestIndex;
  }

  void _setSearchMode(terminal.TerminalSearchMode value) {
    if (_searchMode == value) {
      return;
    }
    setState(() {
      _searchMode = value;
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
    });
    if (activeSessionId != null) {
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
    final promptMarks = _effectivePromptMarksForSession(
      sessionId,
      sessionState: ref.read(sessionControllerProvider),
    );
    if (promptMarks.length < 2) {
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
    final promptMarks = _effectivePromptMarksForSession(sessionId);
    if (promptMarks.isEmpty) {
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

  List<TerminalShellPromptMark> _effectivePromptMarksForSession(
    String sessionId, {
    SessionState? sessionState,
  }) {
    final SessionState currentState =
        sessionState ?? ref.read(sessionControllerProvider);
    final pane = _paneForSession(currentState, sessionId);
    if (pane == null) {
      return const <TerminalShellPromptMark>[];
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    return _effectivePromptMarksForFrame(pane.shellIntegration, frame);
  }

  TerminalShellIntegrationSnapshot _integrationWithEffectivePromptMarks(
    String sessionId,
    TerminalShellIntegrationSnapshot integration,
  ) {
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    return integration.copyWith(
      promptMarks: _effectivePromptMarksForFrame(integration, frame),
    );
  }

  List<TerminalShellPromptMark> _effectivePromptMarksForFrame(
    TerminalShellIntegrationSnapshot integration,
    terminal.TerminalFrameDiff frame,
  ) {
    final fallback = _fallbackPromptMarkForFrame(integration, frame);
    if (fallback == null) {
      return integration.promptMarks;
    }
    if (integration.promptMarks.any(
      (mark) => mark.scrollbackOffset == fallback.scrollbackOffset,
    )) {
      return integration.promptMarks;
    }
    final merged = [...integration.promptMarks, fallback];
    merged.sort((a, b) => a.scrollbackOffset.compareTo(b.scrollbackOffset));
    return merged;
  }

  TerminalShellPromptMark? _fallbackPromptMarkForFrame(
    TerminalShellIntegrationSnapshot integration,
    terminal.TerminalFrameDiff frame,
  ) {
    final hasShellIntegrationContext =
        integration.currentDirectory?.trim().isNotEmpty == true ||
        integration.lastCommand?.trim().isNotEmpty == true ||
        integration.recentCommands.isNotEmpty ||
        integration.recentDirectories.isNotEmpty;
    if (!hasShellIntegrationContext || frame.rows.isEmpty) {
      return null;
    }

    terminal.TerminalRow? anchorRow;
    final rowAtCursor = _rowAtCursor(frame);
    if (rowAtCursor != null && rowAtCursor.text.trimRight().isNotEmpty) {
      anchorRow = rowAtCursor;
    }
    if (anchorRow == null) {
      for (final logicalRow in _logicalRows(frame.rows).reversed) {
        if (logicalRow.text.trimRight().isEmpty) {
          continue;
        }
        anchorRow = logicalRow.endRow;
        break;
      }
    }
    if (anchorRow == null) {
      return null;
    }

    return TerminalShellPromptMark(
      scrollbackOffset: (frame.scrollbackMaxOffset - anchorRow.index).clamp(
        0,
        frame.scrollbackMaxOffset,
      ),
      command: integration.lastCommand,
      cwd: integration.currentDirectory,
    );
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
    final defaultsRoute = RawDialogRoute<DefaultsAndAppearanceSelection>(
      barrierColor: Colors.black.withValues(alpha: 0.34),
      barrierDismissible: true,
      barrierLabel: 'Close defaults',
      requestFocus: true,
      transitionDuration: animationsEnabled
          ? const Duration(milliseconds: 160)
          : Duration.zero,
      pageBuilder: (dialogContext, _, _) => SafeArea(
        child: Align(
          alignment: Alignment.center,
          child: DefaultsAndAppearanceDialog(
            profiles: sessionState.profiles,
            configuredDefaultProfileId: sessionState.configuredDefaultProfileId,
            effectiveDefaultProfileId: sessionState.defaultProfileId,
            themeMode: sessionState.themeMode,
            terminalViewportPadding: sessionState.terminalViewportPadding,
          ),
        ),
      ),
      transitionBuilder: (dialogContext, animation, _, child) {
        if (!animationsEnabled) {
          return child;
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
    final selection = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<DefaultsAndAppearanceSelection>(defaultsRoute);
    await defaultsRoute.completed;

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
            title: 'New profile',
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
    final isActiveSessionReadOnly =
        activeSessionIdBeforeOpen != null &&
        _isSessionReadOnly(activeSessionIdBeforeOpen);
    final canSelectCommandOutput = activeSessionIdBeforeOpen != null
        ? _effectivePromptMarksForSession(
                activeSessionIdBeforeOpen,
                sessionState: sessionState,
              ).length >=
              2
        : false;
    final activePaneZoomed =
        activeSessionIdBeforeOpen != null &&
        _zoomedPaneSessionId == activeSessionIdBeforeOpen;
    final splitRightUnavailableReason = _splitAxisConflictReason(
      sessionState,
      activeSessionIdBeforeOpen,
      TerminalSplitAxis.horizontal,
    );
    final splitDownUnavailableReason = _splitAxisConflictReason(
      sessionState,
      activeSessionIdBeforeOpen,
      TerminalSplitAxis.vertical,
    );
    final hotkeyWindowStatusFuture = WindowBridge.hotkeyStatus();
    Widget commandMenu(HotkeyWindowStatus? hotkeyWindowStatus) {
      return _ShellCommandMenu(
        launcherShortcutLabel: _launcherShortcutLabel(),
        newTabShortcutLabel: _newTabShortcutLabel(),
        hotkeyWindowShortcutLabel: _hotkeyWindowShortcutLabel(),
        autocompleteShortcutLabel: _autocompleteShortcutLabel(),
        copyModeShortcutLabel: _copyModeShortcutLabel(),
        sessionCopyShortcutLabel: _sessionCopyShortcutLabel(),
        sessionPasteShortcutLabel: _sessionPasteShortcutLabel(),
        pasteHistoryShortcutLabel: _pasteHistoryShortcutLabel(),
        instantReplayShortcutLabel: _instantReplayShortcutLabel(),
        searchShortcutLabel: _searchShortcutLabel(),
        hasDefaultProfile: defaultProfile != null,
        hasActiveSession: hasActiveSession,
        activePaneZoomed: activePaneZoomed,
        canReopenClosedTab: sessionController.canReopenClosedTab,
        splitRightUnavailableReason: splitRightUnavailableReason,
        splitDownUnavailableReason: splitDownUnavailableReason,
        hotkeyWindowStatus: hotkeyWindowStatus,
        isActiveSessionReadOnly: isActiveSessionReadOnly,
        notificationsBlockedBySystem: _notificationsBlockedBySystem,
        commandFinishedNotificationsEnabled:
            _commandFinishedNotificationsEnabled,
        bellNotificationsEnabled: _bellNotificationsEnabled,
        activityMonitorEnabled: _activityNotificationsEnabled,
        canSelectCommandOutput: canSelectCommandOutput,
      );
    }

    final commandMenuRoute = RawDialogRoute<TerminalActionId>(
      barrierDismissible: true,
      barrierLabel: 'Close command menu',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: animationsEnabled
          ? const Duration(milliseconds: 160)
          : Duration.zero,
      pageBuilder: (_, _, _) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, right: 14),
              child: _ShellCommandMenuHotkeyStatus(
                statusFuture: hotkeyWindowStatusFuture,
                builder: commandMenu,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        if (!animationsEnabled) {
          return child;
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
    final action = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<TerminalActionId>(commandMenuRoute);
    await commandMenuRoute.completed;

    if (!mounted) {
      return;
    }

    setState(() {
      _isCommandMenuOpen = false;
    });
    _publishAcceptanceSnapshot();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }

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
        'exportDiagnostics',
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
          final conflictReason = _splitAxisConflictReason(
            currentState,
            currentSessionId,
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
          if (defaultProfile == null || currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Split down requires a default profile and active session.',
            );
          }
          final conflictReason = _splitAxisConflictReason(
            currentState,
            currentSessionId,
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
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Focus next pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          final paneManagementBlockedReason = currentTab == null
              ? null
              : _zoomedPaneManagementUnavailableReason(currentTab);
          if (paneManagementBlockedReason != null) {
            return ShellActionBindingResult.skipped(
              paneManagementBlockedReason,
            );
          }
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
          final blockedReason = currentTab == null
              ? null
              : _zoomedPaneManagementUnavailableReason(currentTab);
          if (blockedReason != null) {
            return ShellActionBindingResult.skipped(blockedReason);
          }
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
          final blockedReason = currentTab == null
              ? null
              : _zoomedPaneManagementUnavailableReason(currentTab);
          if (blockedReason != null) {
            return ShellActionBindingResult.skipped(blockedReason);
          }
          if (currentTab == null) {
            return const ShellActionBindingResult.skipped(
              'Resize pane requires at least two panes.',
            );
          }
          final growthBlockedReason = _growActivePaneUnavailableReason(
            currentTab,
            currentSessionId,
          );
          if (growthBlockedReason != null ||
              !_growActivePane(currentTab, currentSessionId)) {
            return ShellActionBindingResult.skipped(
              growthBlockedReason ?? 'Resize pane requires at least two panes.',
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
          final blockedReason = currentTab == null
              ? null
              : _zoomedPaneManagementUnavailableReason(currentTab);
          if (blockedReason != null) {
            return ShellActionBindingResult.skipped(blockedReason);
          }
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
          final willEnableReadOnly = !_isSessionReadOnly(currentSessionId);
          _toggleReadOnlySession(currentSessionId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  willEnableReadOnly
                      ? 'Read-only mode enabled. Input is blocked for this pane.'
                      : 'Read-only mode disabled. Input is active for this pane.',
                ),
              ),
            );
          }
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
                content: Text('Scrollback exported to ${file.path}'),
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: 'Copy path',
                  onPressed: () {
                    unawaited(
                      Clipboard.setData(ClipboardData(text: file.path)),
                    );
                  },
                ),
              ),
            );
          }
          return const ShellActionBindingResult.completed(
            'Exported terminal scrollback.',
          );
        },
        exportDiagnostics: (_) async {
          if (currentSessionId == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Export diagnostics requires an active session.',
                  ),
                ),
              );
            }
            return const ShellActionBindingResult.skipped(
              'Export diagnostics requires an active session.',
            );
          }
          final directory = await _exportDiagnosticsBundle(currentState);
          if (directory == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Diagnostics export is unavailable for the active sessions.',
                  ),
                ),
              );
            }
            return const ShellActionBindingResult.skipped(
              'Diagnostics export is unavailable for the active sessions.',
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Diagnostics exported to ${directory.path}'),
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: 'Copy path',
                  onPressed: () {
                    unawaited(
                      Clipboard.setData(ClipboardData(text: directory.path)),
                    );
                  },
                ),
              ),
            );
          }
          return const ShellActionBindingResult.completed(
            'Exported terminal diagnostics.',
          );
        },
        toggleCommandFinishedNotify: (_) {
          setState(() {
            _commandFinishedNotificationsEnabled =
                !_commandFinishedNotificationsEnabled;
          });
          unawaited(_saveNotificationPreferences());
          final messenger = ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Command-finished notifications ${_commandFinishedNotificationsEnabled ? 'enabled' : 'disabled'} and saved.',
              ),
            ),
          );
          return const ShellActionBindingResult.completed();
        },
        toggleBellNotify: (_) {
          setState(() {
            _bellNotificationsEnabled = !_bellNotificationsEnabled;
          });
          unawaited(_saveNotificationPreferences());
          final messenger = ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Bell notifications ${_bellNotificationsEnabled ? 'enabled' : 'disabled'} and saved.',
              ),
            ),
          );
          return const ShellActionBindingResult.completed();
        },
        toggleActivityMonitor: (_) {
          setState(() {
            _activityNotificationsEnabled = !_activityNotificationsEnabled;
          });
          unawaited(_saveNotificationPreferences());
          final messenger = ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Activity monitor ${_activityNotificationsEnabled ? 'enabled' : 'disabled'} and saved.',
              ),
            ),
          );
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
    final splitRightBlockedReason = _splitAxisConflictReason(
      sessionState,
      targetSessionId,
      TerminalSplitAxis.horizontal,
    );
    final splitDownBlockedReason = _splitAxisConflictReason(
      sessionState,
      targetSessionId,
      TerminalSplitAxis.vertical,
    );
    final targetPane = tab.paneFor(targetSessionId);
    final hasCurrentDirectory =
        (targetPane?.shellIntegration.currentDirectory ?? '').isNotEmpty;
    final isTargetPaneZoomed =
        _zoomedPaneSessionId == targetSessionId && targetPane != null;
    final paneManagementBlockedReason = _zoomedPaneManagementUnavailableReason(
      tab,
    );
    final growPaneBlockedReason = targetPane == null
        ? 'Add another pane to use this action.'
        : paneManagementBlockedReason ??
              _growActivePaneUnavailableReason(tab, targetSessionId);
    final overlay = Overlay.of(context).context.findRenderObject();
    final overlaySize = overlay is RenderBox
        ? overlay.size
        : MediaQuery.sizeOf(context);

    PopupMenuItem<TerminalActionId> item({
      required TerminalActionId action,
      required IconData icon,
      required String title,
      required bool enabled,
      String? disabledReason,
    }) {
      final reason = enabled ? null : disabledReason;
      return PopupMenuItem<TerminalActionId>(
        value: action,
        enabled: enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(title)),
              ],
            ),
            if (reason != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  'Unavailable: $reason',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
                ),
              ),
            ],
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
          enabled: defaultProfile != null && splitRightBlockedReason == null,
          disabledReason: splitRightBlockedReason,
        ),
        item(
          action: TerminalActionId.splitDown,
          icon: Icons.horizontal_split_rounded,
          title: 'Split down',
          enabled: defaultProfile != null && splitDownBlockedReason == null,
          disabledReason: splitDownBlockedReason,
        ),
        item(
          action: TerminalActionId.applyLayoutTemplate,
          icon: Icons.dashboard_customize_rounded,
          title: 'Apply two-pane layout',
          enabled: defaultProfile != null && !hasMultiplePanes,
          disabledReason: hasMultiplePanes
              ? 'This tab already has multiple panes.'
              : null,
        ),
        const PopupMenuDivider(),
        item(
          action: TerminalActionId.focusNextPane,
          icon: Icons.keyboard_tab_rounded,
          title: 'Focus next pane',
          enabled: hasMultiplePanes && paneManagementBlockedReason == null,
          disabledReason: hasMultiplePanes
              ? paneManagementBlockedReason
              : 'Add another pane to use this action.',
        ),
        item(
          action: TerminalActionId.focusPreviousPane,
          icon: Icons.keyboard_tab_rounded,
          title: 'Focus previous pane',
          enabled: hasMultiplePanes && paneManagementBlockedReason == null,
          disabledReason: hasMultiplePanes
              ? paneManagementBlockedReason
              : 'Add another pane to use this action.',
        ),
        item(
          action: TerminalActionId.resizePane,
          icon: Icons.open_with_rounded,
          title: 'Grow active pane',
          enabled: hasMultiplePanes && growPaneBlockedReason == null,
          disabledReason: growPaneBlockedReason,
        ),
        item(
          action: TerminalActionId.swapPane,
          icon: Icons.swap_horiz_rounded,
          title: 'Swap active pane',
          enabled: hasMultiplePanes && paneManagementBlockedReason == null,
          disabledReason: hasMultiplePanes
              ? paneManagementBlockedReason
              : 'Add another pane to use this action.',
        ),
        item(
          action: TerminalActionId.zoomPane,
          icon: Icons.zoom_out_map_rounded,
          title: '${isTargetPaneZoomed ? 'Unzoom' : 'Zoom'} active pane',
          enabled: hasMultiplePanes,
          disabledReason: hasMultiplePanes
              ? null
              : 'Add another pane to use this action.',
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
        final blockedReason = currentTab == null
            ? null
            : _zoomedPaneManagementUnavailableReason(currentTab);
        if (blockedReason != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(blockedReason)));
          return;
        }
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
        final blockedReason = currentTab == null
            ? null
            : _zoomedPaneManagementUnavailableReason(currentTab);
        if (blockedReason != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(blockedReason)));
          return;
        }
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
        if (currentTab == null) {
          return;
        }
        final blockedReason = _growActivePaneUnavailableReason(
          currentTab,
          currentSessionId,
        );
        if (_growActivePane(currentTab, currentSessionId)) {
          _focusSession(currentSessionId);
        } else if (blockedReason != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(blockedReason)));
        }
        return;
      case TerminalActionId.swapPane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        final blockedReason = currentTab == null
            ? null
            : _zoomedPaneManagementUnavailableReason(currentTab);
        if (blockedReason != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(blockedReason)));
          return;
        }
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
    final paneLayout = zoomedPane == null
        ? activeTab.effectivePaneLayout
        : TerminalPaneLayoutNode.leaf(zoomedPane);
    final terminalBackground = _tabTerminalBackgroundColor(
      context,
      sessionState,
      activeTab,
    );

    return RepaintBoundary(
      key: const Key('shell-terminal-surface'),
      child: DecoratedBox(
        decoration: BoxDecoration(color: terminalBackground),
        child: _buildTerminalPaneLayoutNode(
          context: context,
          sessionController: sessionController,
          sessionState: sessionState,
          node: paneLayout,
          activeSessionId: activeSessionId,
          palette: palette,
          terminalBackground: terminalBackground,
          onHostKeyEvent: onHostKeyEvent,
        ),
      ),
    );
  }

  Widget _buildTerminalPaneLayoutNode({
    required BuildContext context,
    required SessionController sessionController,
    required SessionState sessionState,
    required TerminalPaneLayoutNode node,
    required String activeSessionId,
    required AppThemeTokens palette,
    required Color terminalBackground,
    required KeyEventResult Function(KeyEvent event) onHostKeyEvent,
  }) {
    if (node.isLeaf) {
      final pane = node.pane!;
      return _buildTerminalPane(
        context: context,
        sessionController: sessionController,
        sessionState: sessionState,
        pane: pane,
        isActive: pane.sessionId == activeSessionId,
        palette: palette,
        onHostKeyEvent: onHostKeyEvent,
      );
    }

    final direction = node.splitAxis == TerminalSplitAxis.horizontal
        ? Axis.horizontal
        : Axis.vertical;
    final first = node.first!;
    final second = node.second!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availablePrimarySize =
            (direction == Axis.horizontal
                ? constraints.maxWidth
                : constraints.maxHeight) -
            _paneDividerDragThickness;
        return Flex(
          direction: direction,
          children: [
            Expanded(
              flex: math.max(1, (node.ratio * 1000).round()),
              child: _buildTerminalPaneLayoutNode(
                context: context,
                sessionController: sessionController,
                sessionState: sessionState,
                node: first,
                activeSessionId: activeSessionId,
                palette: palette,
                terminalBackground: terminalBackground,
                onHostKeyEvent: onHostKeyEvent,
              ),
            ),
            _PaneDividerHandle(
              key: Key(
                'shell-pane-divider-${first.firstLeafId}-${second.firstLeafId}',
              ),
              direction: direction,
              thickness: _paneDividerDragThickness,
              terminalBackground: terminalBackground,
              palette: palette,
              onDragUpdate: (primaryDelta) {
                if (availablePrimarySize <= 0 ||
                    !availablePrimarySize.isFinite) {
                  return;
                }
                final nextRatio =
                    node.ratio + (primaryDelta / availablePrimarySize);
                sessionController.resizeActivePaneSplit(node.id, nextRatio);
              },
            ),
            Expanded(
              flex: math.max(1, ((1 - node.ratio) * 1000).round()),
              child: _buildTerminalPaneLayoutNode(
                context: context,
                sessionController: sessionController,
                sessionState: sessionState,
                node: second,
                activeSessionId: activeSessionId,
                palette: palette,
                terminalBackground: terminalBackground,
                onHostKeyEvent: onHostKeyEvent,
              ),
            ),
          ],
        );
      },
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

        return Listener(
          onPointerDown: (event) {
            if (!isActive && (event.buttons & kPrimaryMouseButton) != 0) {
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
                        _clipboardConfig.copyOnSelect ||
                        (terminalConfig?.interaction.copyOnSelect ?? false),
                    optionDragMode:
                        terminalConfig?.interaction.optionDragMode ??
                        terminal.TerminalOptionDragMode.blockSelection,
                    searchMatches: isActive && _isSearchOpen
                        ? _searchMatches
                        : const <terminal.TerminalSearchMatch>[],
                    activeSearchMatchIndex: isActive && _isSearchOpen
                        ? _activeSearchIndex
                        : -1,
                    searchHighlightStyle: terminal.TerminalSearchHighlightStyle(
                      activeFill: palette.accent.withValues(alpha: 0.34),
                      inactiveFill: palette.warning.withValues(alpha: 0.22),
                      activeBorder: palette.accent.withValues(alpha: 0.82),
                      radius: 3,
                    ),
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
                        color: palette.inactiveScrim,
                      ),
                    ),
                  ),
                if (isActive && _isSearchOpen)
                  Positioned(
                    top: _terminalOverlayPadding.top,
                    left: _terminalOverlayPadding.left,
                    right: _terminalOverlayPadding.right,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: _TerminalSearchBar(
                        query: _searchQuery,
                        matches: _searchMatches.length,
                        activeIndex: _activeSearchIndex,
                        searchMode: _searchMode,
                        errorText: _searchErrorText,
                        palette: palette,
                        focusNode: _searchFocusNode,
                        focusRequestSerial: _searchFocusRequestSerial,
                        onChanged: _searchScrollback,
                        onClear: _clearSearch,
                        onModeChanged: _setSearchMode,
                        onPrevious: () => _moveSearchMatch(1),
                        onNext: () => _moveSearchMatch(-1),
                        onClose: _closeSearch,
                      ),
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
                if (isActive && annotations.isNotEmpty && !_isAutoComposerOpen)
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
    final statusDirectory = statusPane?.shellIntegration.currentDirectory;
    final statusProfile = statusPane == null
        ? null
        : _profileForPane(statusPane, sessionState.profiles);
    final statusViewportLabel = _viewportStatusLabelFor(displayedSessionId);
    final statusViewportController = displayedSessionId == null
        ? null
        : sessionController.viewportFor(displayedSessionId);
    final shellChromeBackground = statusProfile == null
        ? activeTab == null
              ? _terminalColorsForProfile(
                  context,
                  defaultProfile,
                ).canvasBackground
              : _tabTerminalBackgroundColor(context, sessionState, activeTab)
        : _terminalColorsForProfile(context, statusProfile).canvasBackground;

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
    required this.terminalBackgroundColor,
    required this.directory,
    required this.viewportLabel,
    required this.modeItems,
    required this.encodingLabel,
  });

  final AppThemeTokens palette;
  final Color terminalBackgroundColor;
  final String? directory;
  final String? viewportLabel;
  final List<_ShellStatusModeItem> modeItems;
  final String encodingLabel;

  @override
  Widget build(BuildContext context) {
    final tone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: terminalBackgroundColor,
    );
    final statusItems = <Widget>[
      _ShellStatusItem(
        key: const Key('shell-status-encoding'),
        palette: palette,
        tone: tone,
        label: encodingLabel,
        monospace: true,
      ),
      if (viewportLabel != null)
        _ShellStatusItem(
          key: const Key('shell-status-viewport'),
          palette: palette,
          tone: tone,
          label: viewportLabel!,
          monospace: true,
        ),
      for (final modeItem in modeItems)
        _ShellStatusItem(
          key: modeItem.key,
          palette: palette,
          tone: tone,
          label: modeItem.label,
          tooltip: modeItem.tooltip,
          semanticsLabel: modeItem.semanticsLabel,
          monospace: true,
          highlighted: true,
          maxWidth: 118,
        ),
      if (directory != null && directory!.trim().isNotEmpty)
        _ShellStatusDirectoryItem(
          key: const Key('shell-status-directory'),
          palette: palette,
          tone: tone,
          label: _statusPathLabel(directory!),
          fullPath: directory!.trim(),
          minWidth: 176,
          maxWidth: 260,
        ),
    ];

    return DecoratedBox(
      key: const Key('shell-status-bar-surface'),
      decoration: BoxDecoration(
        color: terminalBackgroundColor,
        border: Border(
          top: BorderSide(color: tone.border.withValues(alpha: 0.46)),
        ),
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
          reverse: true,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: palette.spacing.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var index = 0; index < statusItems.length; index++) ...[
                  if (index > 0)
                    _ShellStatusDivider(palette: palette, tone: tone),
                  statusItems[index],
                ],
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
}

class _ShellStatusModeItem {
  const _ShellStatusModeItem({
    required this.key,
    required this.label,
    required this.tooltip,
    required this.semanticsLabel,
  });

  final Key key;
  final String label;
  final String tooltip;
  final String semanticsLabel;
}

class _ShellStatusDirectoryItem extends StatefulWidget {
  const _ShellStatusDirectoryItem({
    super.key,
    required this.palette,
    required this.tone,
    required this.label,
    required this.fullPath,
    this.minWidth,
    this.maxWidth,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final String label;
  final String fullPath;
  final double? minWidth;
  final double? maxWidth;

  @override
  State<_ShellStatusDirectoryItem> createState() =>
      _ShellStatusDirectoryItemState();
}

class _ShellStatusDirectoryItemState extends State<_ShellStatusDirectoryItem> {
  bool _hovered = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final menuBackground = Color.alphaBlend(
      widget.tone.hoverBackground.withValues(alpha: 0.42),
      widget.tone.activeBackground,
    );
    final menuBorder = widget.tone.border.withValues(alpha: 0.58);
    final menuTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: widget.tone.primaryText,
      fontWeight: FontWeight.w600,
    );
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.palette.radius.md),
      side: BorderSide(color: menuBorder),
    );
    final themedMenu = Theme.of(context).copyWith(
      hoverColor: widget.tone.hoverBackground.withValues(alpha: 0.72),
      highlightColor: widget.tone.hoverBackground.withValues(alpha: 0.72),
      focusColor: widget.tone.hoverBackground.withValues(alpha: 0.72),
      splashColor: Colors.transparent,
      popupMenuTheme: PopupMenuThemeData(
        color: menuBackground,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: menuShape,
        textStyle: menuTextStyle,
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Theme(
        data: themedMenu,
        child: PopupMenuButton<String>(
          tooltip: widget.fullPath,
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under,
          offset: Offset(0, widget.palette.spacing.xs),
          color: menuBackground,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: menuShape,
          onOpened: () => setState(() => _menuOpen = true),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'copyPath',
              height: 34,
              child: Text('Copy full path', style: menuTextStyle),
            ),
          ],
          onCanceled: () => setState(() => _menuOpen = false),
          onSelected: (value) {
            setState(() => _menuOpen = false);
            if (value == 'copyPath') {
              unawaited(ClipboardBridge.copy(widget.fullPath));
            }
          },
          child: _ShellStatusItem(
            palette: widget.palette,
            tone: widget.tone,
            label: widget.label,
            minWidth: widget.minWidth,
            maxWidth: widget.maxWidth,
            highlighted: _hovered || _menuOpen,
          ),
        ),
      ),
    );
  }
}

class _ShellStatusDivider extends StatelessWidget {
  const _ShellStatusDivider({required this.palette, required this.tone});

  final AppThemeTokens palette;
  final _ShellTabTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: EdgeInsets.symmetric(horizontal: palette.spacing.lg),
      color: tone.border.withValues(alpha: 0.34),
    );
  }
}

class _ShellStatusItem extends StatelessWidget {
  const _ShellStatusItem({
    super.key,
    required this.palette,
    required this.tone,
    required this.label,
    this.monospace = false,
    this.minWidth,
    this.maxWidth,
    this.highlighted = false,
    this.tooltip,
    this.semanticsLabel,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final String label;
  final bool monospace;
  final double? minWidth;
  final double? maxWidth;
  final bool highlighted;
  final String? tooltip;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final itemBackground = highlighted
        ? tone.hoverBackground
        : Color.alphaBlend(
            tone.hoverBackground.withValues(alpha: 0.34),
            tone.activeBackground,
          );
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: tone.mutedText,
      fontWeight: FontWeight.w600,
      fontFamily: monospace ? 'monospace' : null,
    );
    Widget item = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth ?? 0,
        maxWidth: maxWidth ?? 180,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: itemBackground,
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: tone.border.withValues(alpha: 0.38)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
    if (semanticsLabel != null) {
      item = Semantics(container: true, label: semanticsLabel, child: item);
    }
    if (tooltip != null) {
      item = Tooltip(message: tooltip!, child: item);
    }
    return item;
  }
}

class _ShellChromeBar extends StatelessWidget {
  const _ShellChromeBar({
    required this.palette,
    required this.terminalBackgroundColor,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabBackgroundColor,
    required this.referenceDemoMode,
    required this.onNewTab,
    required this.onActivateSession,
    required this.onCloseSession,
    required this.onReorderTab,
    required this.onShowTabContextMenu,
    required this.onShowCommandMenu,
  });

  final AppThemeTokens palette;
  final Color terminalBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final bool referenceDemoMode;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onCloseSession;
  final void Function({required int oldIndex, required int newIndex})
  onReorderTab;
  final void Function(TerminalTab tab, Offset position) onShowTabContextMenu;
  final VoidCallback onShowCommandMenu;

  @override
  Widget build(BuildContext context) {
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: terminalBackgroundColor,
    );
    return DecoratedBox(
      key: const Key('shell-chrome-bar'),
      decoration: BoxDecoration(
        color: terminalBackgroundColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(palette.radius.lg),
          topRight: Radius.circular(palette.radius.lg),
        ),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            _WindowDragHandle(
              key: const Key('shell-window-drag-leading'),
              child: SizedBox(
                width: defaultTargetPlatform == TargetPlatform.macOS
                    ? 132
                    : palette.spacing.md,
                height: double.infinity,
              ),
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
                      chromeBackgroundColor: terminalBackgroundColor,
                      tabs: tabs,
                      activeSessionId: activeSessionId,
                      tabHasNewOutput: tabHasNewOutput,
                      tabBackgroundColor: tabBackgroundColor,
                      onNewTab: onNewTab,
                      onActivateSession: onActivateSession,
                      onCloseSession: onCloseSession,
                      onReorderTab: onReorderTab,
                      onShowTabContextMenu: onShowTabContextMenu,
                    ),
            ),
            if (!referenceDemoMode) ...[
              _buildChromeIconButton(
                key: const Key('shell-chrome-menu'),
                tooltip: 'Open command menu',
                onPressed: onShowCommandMenu,
                iconSize: 16,
                hoverBackgroundColor: chromeTone.hoverBackground,
                icon: Icon(Icons.tune_rounded, color: chromeTone.subtleText),
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

class _WindowDragHandle extends StatelessWidget {
  const _WindowDragHandle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return child;
    }
    return _MacWindowDragHandle(child: child);
  }
}

class _MacWindowDragHandle extends StatefulWidget {
  const _MacWindowDragHandle({required this.child});

  final Widget child;

  @override
  State<_MacWindowDragHandle> createState() => _MacWindowDragHandleState();
}

class _MacWindowDragHandleState extends State<_MacWindowDragHandle> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) {
          setState(() {
            _dragging = true;
          });
          unawaited(WindowBridge.beginWindowDrag());
        },
        onPanEnd: (_) {
          setState(() {
            _dragging = false;
          });
        },
        onPanCancel: () {
          setState(() {
            _dragging = false;
          });
        },
        child: Tooltip(message: 'Drag window', child: widget.child),
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
      identifier: _shellTabSemanticsIdentifier(tab),
      label: _shellTabSemanticsLabel(tab, shortcutIndex),
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

class _ShellTabStrip extends StatefulWidget {
  const _ShellTabStrip({
    required this.palette,
    required this.chromeBackgroundColor,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabBackgroundColor,
    required this.onNewTab,
    required this.onActivateSession,
    required this.onCloseSession,
    required this.onReorderTab,
    required this.onShowTabContextMenu,
  });

  final AppThemeTokens palette;
  final Color chromeBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onCloseSession;
  final void Function({required int oldIndex, required int newIndex})
  onReorderTab;
  final void Function(TerminalTab tab, Offset position) onShowTabContextMenu;

  @override
  State<_ShellTabStrip> createState() => _ShellTabStripState();
}

class _ShellTabStripState extends State<_ShellTabStrip> {
  static const double _minReadableTabWidth = 112;
  static const double _newTabButtonWidth = 30;
  static const double _overflowButtonWidth = 120;

  String? _draggingSessionId;

  bool get _usesDelayedDragStart {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: widget.chromeBackgroundColor,
    );
    return SizedBox(
      key: const Key('shell-tab-strip'),
      height: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 0.0;
          final tabsAreaWidth = math.max(0.0, totalWidth - _newTabButtonWidth);
          final visibleTabCount = _visibleTabCountFor(tabsAreaWidth);
          final hasOverflow = visibleTabCount < widget.tabs.length;
          final hiddenTabs = hasOverflow
              ? widget.tabs.skip(visibleTabCount).toList(growable: false)
              : const <TerminalTab>[];
          final overflowWidth = hasOverflow ? _overflowButtonWidth : 0.0;
          final visibleTabsWidth = math.max(0.0, tabsAreaWidth - overflowWidth);
          final tabWidth = visibleTabCount == 0
              ? 0.0
              : visibleTabsWidth / visibleTabCount;

          return Row(
            children: [
              SizedBox(
                width: visibleTabsWidth,
                child: visibleTabCount == 0
                    ? const SizedBox.expand()
                    : ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        proxyDecorator: (child, index, animation) =>
                            _ShellTabDragProxy(
                              palette: widget.palette,
                              animation: animation,
                              child: child,
                            ),
                        onReorderStart: (index) {
                          if (index >= visibleTabCount) {
                            return;
                          }
                          unawaited(HapticFeedback.selectionClick());
                          setState(() {
                            _draggingSessionId = widget.tabs[index].sessionId;
                          });
                        },
                        onReorderEnd: (_) {
                          if (_draggingSessionId == null) {
                            return;
                          }
                          setState(() {
                            _draggingSessionId = null;
                          });
                        },
                        onReorderItem: (oldIndex, newIndex) =>
                            widget.onReorderTab(
                              oldIndex: oldIndex,
                              newIndex: newIndex,
                            ),
                        itemCount: visibleTabCount,
                        itemBuilder: (context, index) {
                          final tab = widget.tabs[index];
                          final isActive =
                              widget.activeSessionId != null &&
                              tab.containsSession(widget.activeSessionId!);
                          final isDragging =
                              _draggingSessionId == tab.sessionId;
                          return _ShellReorderableTabItem(
                            key: ValueKey('shell-tab-reorder-${tab.sessionId}'),
                            width: tabWidth,
                            child: _ShellTabButton(
                              palette: widget.palette,
                              tab: tab,
                              shortcutIndex: index < 9 ? index + 1 : null,
                              isActive: isActive,
                              hasNewOutput: widget.tabHasNewOutput(tab),
                              terminalBackgroundColor: widget
                                  .tabBackgroundColor(tab),
                              dragRegionBuilder: (child) =>
                                  _ShellTabDragStartRegion(
                                    key: Key('shell-tab-drag-${tab.sessionId}'),
                                    index: index,
                                    useDelayedStart: _usesDelayedDragStart,
                                    isDragging: isDragging,
                                    child: child,
                                  ),
                              onActivate: () =>
                                  widget.onActivateSession(tab.activeSessionId),
                              onClose: () =>
                                  widget.onCloseSession(tab.sessionId),
                              onShowContextMenu: (position) =>
                                  widget.onShowTabContextMenu(tab, position),
                            ),
                          );
                        },
                      ),
              ),
              if (hasOverflow)
                _ShellTabOverflowMenu(
                  palette: widget.palette,
                  chromeBackgroundColor: widget.chromeBackgroundColor,
                  tabs: hiddenTabs,
                  activeSessionId: widget.activeSessionId,
                  tabHasNewOutput: widget.tabHasNewOutput,
                  tabBackgroundColor: widget.tabBackgroundColor,
                  onActivateSession: widget.onActivateSession,
                ),
              _ShellNewTabButton(
                palette: widget.palette,
                tone: chromeTone,
                onPressed: widget.onNewTab,
              ),
            ],
          );
        },
      ),
    );
  }

  int _visibleTabCountFor(double tabsAreaWidth) {
    final tabCount = widget.tabs.length;
    if (tabCount == 0 || tabsAreaWidth <= 0) {
      return 0;
    }
    final capacityWithoutOverflow = math.max(
      1,
      tabsAreaWidth ~/ _minReadableTabWidth,
    );
    if (tabCount <= capacityWithoutOverflow) {
      return tabCount;
    }
    final capacityWithOverflow = math.max(
      1,
      (tabsAreaWidth - _overflowButtonWidth) ~/ _minReadableTabWidth,
    );
    return math.min(tabCount - 1, capacityWithOverflow);
  }
}

class _ShellReorderableTabItem extends StatelessWidget {
  const _ShellReorderableTabItem({
    super.key,
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: child);
  }
}

class _ShellTabDragProxy extends StatelessWidget {
  const _ShellTabDragProxy({
    required this.palette,
    required this.animation,
    required this.child,
  });

  final AppThemeTokens palette;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final lift = Curves.easeOutCubic.transform(animation.value);
        return Transform.scale(
          scale: 1 + lift * 0.018,
          child: Material(
            color: palette.chromeElevated.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(palette.radius.md),
            elevation: 6 * lift,
            shadowColor: palette.elevation.floating.first.color,
            child: child!,
          ),
        );
      },
    );
  }
}

class _ShellTabDragStartRegion extends StatelessWidget {
  const _ShellTabDragStartRegion({
    super.key,
    required this.index,
    required this.useDelayedStart,
    required this.isDragging,
    required this.child,
  });

  final int index;
  final bool useDelayedStart;
  final bool isDragging;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dragStartListener = useDelayedStart
        ? ReorderableDelayedDragStartListener(index: index, child: child)
        : ReorderableDragStartListener(index: index, child: child);
    return MouseRegion(
      cursor: isDragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      child: dragStartListener,
    );
  }
}

class _ShellNewTabButton extends StatelessWidget {
  const _ShellNewTabButton({
    required this.palette,
    required this.tone,
    required this.onPressed,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _ShellTabStripState._newTabButtonWidth,
      child: Center(
        child: _buildChromeIconButton(
          key: const Key('shell-chrome-new-tab'),
          tooltip: 'New tab',
          onPressed: onPressed,
          iconSize: 18,
          hoverBackgroundColor: tone.hoverBackground,
          icon: Icon(Icons.add_rounded, color: tone.subtleText),
        ),
      ),
    );
  }
}

class _ShellTabTone {
  const _ShellTabTone({
    required this.activeBackground,
    required this.hoverBackground,
    required this.border,
    required this.primaryText,
    required this.mutedText,
    required this.subtleText,
    required this.menuSelectionBackground,
    required this.menuSelectionText,
  });

  final Color activeBackground;
  final Color hoverBackground;
  final Color border;
  final Color primaryText;
  final Color mutedText;
  final Color subtleText;
  final Color menuSelectionBackground;
  final Color menuSelectionText;

  factory _ShellTabTone.fromTerminalBackground({
    required Color terminalBackground,
  }) {
    final luminance = terminalBackground.computeLuminance();
    final isDark = luminance < 0.5;
    final contrastColor = isDark ? Colors.white : Colors.black;
    final hoverBackground = _neutralHighlightFor(terminalBackground);
    final border = Color.lerp(
      terminalBackground,
      contrastColor,
      isDark ? 0.34 : 0.26,
    )!;
    final menuSelectionBackground = _neutralHighlightFor(
      terminalBackground,
      emphasis: true,
    );
    final primaryText = _readableTextOn(terminalBackground);
    final inactiveText = _readableTextOn(terminalBackground);

    return _ShellTabTone(
      activeBackground: terminalBackground,
      hoverBackground: hoverBackground,
      border: border,
      primaryText: primaryText,
      mutedText: inactiveText.withValues(alpha: 0.82),
      subtleText: inactiveText.withValues(alpha: 0.58),
      menuSelectionBackground: menuSelectionBackground,
      menuSelectionText: _readableTextOn(menuSelectionBackground),
    );
  }

  static Color _readableTextOn(Color background) {
    return background.computeLuminance() < 0.5 ? Colors.white : Colors.black;
  }

  static Color _neutralHighlightFor(Color background, {bool emphasis = false}) {
    final hsl = HSLColor.fromColor(background);
    final isDark = background.computeLuminance() < 0.5;
    final delta = emphasis ? 0.24 : 0.16;
    final lightness = isDark
        ? math.min(1.0, hsl.lightness + delta)
        : math.max(0.0, hsl.lightness - delta);
    return hsl.withSaturation(0).withLightness(lightness).toColor();
  }
}

class _ShellTabOverflowMenu extends StatefulWidget {
  const _ShellTabOverflowMenu({
    required this.palette,
    required this.chromeBackgroundColor,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabBackgroundColor,
    required this.onActivateSession,
  });

  final AppThemeTokens palette;
  final Color chromeBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final ValueChanged<String> onActivateSession;

  @override
  State<_ShellTabOverflowMenu> createState() => _ShellTabOverflowMenuState();
}

class _ShellTabOverflowMenuState extends State<_ShellTabOverflowMenu> {
  static const double _menuWidth = 176;
  static const double _menuMaxHeight = 360;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _hovered = false;

  @override
  void didUpdateWidget(_ShellTabOverflowMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_overlayEntry != null) {
      if (widget.tabs.isEmpty) {
        _closeMenu();
      } else {
        _overlayEntry!.markNeedsBuild();
      }
    }
  }

  @override
  void dispose() {
    _removeMenuEntry();
    super.dispose();
  }

  void _toggleMenu() {
    if (_overlayEntry == null) {
      _openMenu();
    } else {
      _closeMenu();
    }
  }

  void _openMenu() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(
              _ShellTabStripState._overflowButtonWidth - _menuWidth,
              38,
            ),
            child: _ShellTabOverflowPanel(
              palette: widget.palette,
              width: _menuWidth,
              maxHeight: _menuMaxHeight,
              tabs: widget.tabs,
              activeSessionId: widget.activeSessionId,
              tabHasNewOutput: widget.tabHasNewOutput,
              tabBackgroundColor: widget.tabBackgroundColor,
              onSelected: (sessionId) {
                _closeMenu();
                widget.onActivateSession(sessionId);
              },
            ),
          ),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
    setState(() {});
  }

  void _closeMenu() {
    _removeMenuEntry();
    if (mounted) {
      setState(() {});
    }
  }

  void _removeMenuEntry() {
    final entry = _overlayEntry;
    if (entry == null) {
      return;
    }
    _overlayEntry = null;
    entry.remove();
  }

  @override
  Widget build(BuildContext context) {
    final activeHiddenTab = widget.activeSessionId == null
        ? null
        : widget.tabs.cast<TerminalTab?>().firstWhere(
            (tab) => tab!.containsSession(widget.activeSessionId!),
            orElse: () => null,
          );
    final isActive = activeHiddenTab != null;
    final isOpen = _overlayEntry != null;
    final hasHiddenNewOutput = widget.tabs.any(widget.tabHasNewOutput);
    final label = activeHiddenTab?.title ?? '${widget.tabs.length} more';
    final activeTone = activeHiddenTab == null
        ? null
        : _ShellTabTone.fromTerminalBackground(
            terminalBackground: widget.tabBackgroundColor(activeHiddenTab),
          );
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: widget.chromeBackgroundColor,
    );
    final background = isActive
        ? activeTone!.activeBackground
        : _hovered || isOpen
        ? chromeTone.hoverBackground
        : Colors.transparent;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: 'Show hidden tabs',
        child: SizedBox(
          width: _ShellTabStripState._overflowButtonWidth,
          height: double.infinity,
          child: Semantics(
            label: 'shell-tab-overflow',
            button: true,
            selected: isActive,
            expanded: isOpen,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                key: const Key('shell-tab-overflow-button'),
                behavior: HitTestBehavior.opaque,
                onTap: _toggleMenu,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    border: Border(
                      left: BorderSide(
                        color:
                            activeTone?.border.withValues(alpha: 0.72) ??
                            chromeTone.border.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.palette.spacing.md,
                    ),
                    child: Row(
                      children: [
                        if (hasHiddenNewOutput) ...[
                          _ShellTabNewOutputDot(
                            key: const Key('shell-tab-overflow-new-output'),
                            palette: widget.palette,
                          ),
                          const SizedBox(width: 7),
                        ],
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: isActive
                                      ? activeTone!.primaryText
                                      : chromeTone.mutedText,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 120),
                          turns: isOpen ? 0.5 : 0,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: isActive
                                ? activeTone!.subtleText
                                : chromeTone.subtleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabOverflowPanel extends StatelessWidget {
  const _ShellTabOverflowPanel({
    required this.palette,
    required this.width,
    required this.maxHeight,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabBackgroundColor,
    required this.onSelected,
  });

  final AppThemeTokens palette;
  final double width;
  final double maxHeight;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final menuRadius = BorderRadius.circular(palette.radius.sm);

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: Directionality(
        textDirection: Directionality.of(context),
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: DecoratedBox(
              key: const Key('shell-tab-overflow-panel'),
              decoration: BoxDecoration(
                color: palette.panelElevated.withValues(alpha: 0.98),
                border: Border.all(
                  color: palette.borderStrong.withValues(alpha: 0.54),
                ),
                borderRadius: menuRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: menuRadius,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final tab in tabs)
                        _ShellTabOverflowRow(
                          key: Key('shell-tab-overflow-item-${tab.sessionId}'),
                          palette: palette,
                          tab: tab,
                          isActive:
                              activeSessionId != null &&
                              tab.containsSession(activeSessionId!),
                          hasNewOutput: tabHasNewOutput(tab),
                          terminalBackgroundColor: tabBackgroundColor(tab),
                          onSelected: () => onSelected(tab.activeSessionId),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabOverflowRow extends StatefulWidget {
  const _ShellTabOverflowRow({
    super.key,
    required this.palette,
    required this.tab,
    required this.isActive,
    required this.hasNewOutput,
    required this.terminalBackgroundColor,
    required this.onSelected,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final bool isActive;
  final bool hasNewOutput;
  final Color terminalBackgroundColor;
  final VoidCallback onSelected;

  @override
  State<_ShellTabOverflowRow> createState() => _ShellTabOverflowRowState();
}

class _ShellTabOverflowRowState extends State<_ShellTabOverflowRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: widget.terminalBackgroundColor,
    );
    final background = widget.isActive
        ? tone.menuSelectionBackground
        : _hovered
        ? tone.hoverBackground
        : Colors.transparent;
    final textColor = widget.isActive
        ? tone.menuSelectionText
        : widget.palette.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: widget.isActive
                          ? tone.menuSelectionText
                          : Colors.transparent,
                    ),
                    if (!widget.isActive && widget.hasNewOutput)
                      _ShellTabNewOutputDot(
                        key: Key(
                          'shell-tab-new-output-${widget.tab.sessionId}',
                        ),
                        palette: widget.palette,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.tab.title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontSize: 13,
                    height: 1,
                    fontWeight: widget.isActive
                        ? FontWeight.w700
                        : FontWeight.w500,
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

class _ShellTabNewOutputDot extends StatelessWidget {
  const _ShellTabNewOutputDot({super.key, required this.palette});

  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New output',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.focus,
          shape: BoxShape.circle,
          border: Border.all(
            color: palette.textPrimary.withValues(alpha: 0.36),
          ),
        ),
        child: const SizedBox.square(dimension: 8),
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
    required this.hasNewOutput,
    required this.terminalBackgroundColor,
    required this.dragRegionBuilder,
    required this.onActivate,
    required this.onClose,
    required this.onShowContextMenu,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
  final bool isActive;
  final bool hasNewOutput;
  final Color terminalBackgroundColor;
  final Widget Function(Widget child) dragRegionBuilder;
  final VoidCallback onActivate;
  final VoidCallback onClose;
  final ValueChanged<Offset> onShowContextMenu;

  @override
  Widget build(BuildContext context) {
    final tone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: terminalBackgroundColor,
    );
    final tabTextStyle = Theme.of(context).textTheme.titleSmall!.copyWith(
      color: isActive ? tone.primaryText : tone.mutedText,
      fontWeight: FontWeight.w500,
    );
    final tabBorder = isActive
        ? Border(
            top: BorderSide(color: tone.border.withValues(alpha: 0.58)),
            left: BorderSide(color: tone.border.withValues(alpha: 0.72)),
            right: BorderSide(color: tone.border.withValues(alpha: 0.72)),
          )
        : Border(
            left: BorderSide(color: tone.border.withValues(alpha: 0.34)),
            right: BorderSide(color: tone.border.withValues(alpha: 0.34)),
            bottom: BorderSide(color: tone.border.withValues(alpha: 0.34)),
          );

    return Semantics(
      identifier: _shellTabSemanticsIdentifier(tab),
      label: _shellTabSemanticsLabel(tab, shortcutIndex),
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
        child: SizedBox.expand(
          child: DecoratedBox(
            key: Key('shell-tab-border-${tab.sessionId}'),
            decoration: BoxDecoration(border: tabBorder),
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
                  isActive ? tone.primaryText : tone.mutedText,
                ),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (isActive) {
                    return tone.activeBackground;
                  }
                  if (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)) {
                    return tone.hoverBackground;
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
                  Flexible(
                    child: dragRegionBuilder(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (shortcutIndex != null) ...[
                            Text(
                              '⌘$shortcutIndex',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: isActive
                                        ? tone.subtleText
                                        : tone.subtleText,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (hasNewOutput && !isActive) ...[
                            _ShellTabNewOutputDot(
                              key: Key('shell-tab-new-output-${tab.sessionId}'),
                              palette: palette,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 140),
                              style: tabTextStyle,
                              child: Text(
                                tab.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
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
                            ? tone.subtleText.withValues(alpha: 0.78)
                            : tone.subtleText.withValues(alpha: 0.48),
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

String _shellTabSemanticsIdentifier(TerminalTab tab) {
  return 'shell-tab-${tab.sessionId}';
}

String _shellTabSemanticsLabel(TerminalTab tab, int? shortcutIndex) {
  final shortcut = shortcutIndex == null ? '' : ', Command $shortcutIndex';
  return '${tab.title} tab$shortcut';
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

class _TerminalSearchBar extends StatefulWidget {
  const _TerminalSearchBar({
    required this.query,
    required this.matches,
    required this.activeIndex,
    required this.searchMode,
    required this.errorText,
    required this.palette,
    required this.focusNode,
    required this.focusRequestSerial,
    required this.onChanged,
    required this.onClear,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final String query;
  final int matches;
  final int activeIndex;
  final terminal.TerminalSearchMode searchMode;
  final String? errorText;
  final AppThemeTokens palette;
  final FocusNode focusNode;
  final int focusRequestSerial;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<terminal.TerminalSearchMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  State<_TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<_TerminalSearchBar> {
  static const _searchBarMaxWidth = 544.0;
  static const _searchBarIdleWidth = 544.0;
  static const _searchBarCompactBreakpoint = 430.0;
  static const _searchBarControlHeight = 40.0;
  static const _searchFieldEditHeight = 24.0;
  static const _searchBarHorizontalInset = 8.0;
  static const _searchBarVerticalInset = 8.0;

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusAndSelectQuery();
    });
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
    if (oldWidget.focusRequestSerial != widget.focusRequestSerial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _focusAndSelectQuery();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _counterText {
    if (widget.errorText != null) {
      return 'Regex error';
    }
    if (widget.query.isEmpty) {
      return '';
    }
    if (widget.matches == 0) {
      return 'No matches';
    }
    return '${widget.activeIndex + 1}/${widget.matches}';
  }

  void _focusAndSelectQuery() {
    widget.focusNode.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  String _searchModeLabel(terminal.TerminalSearchMode mode) {
    return switch (mode) {
      terminal.TerminalSearchMode.smartCaseSubstring => 'Smart Case Substring',
      terminal.TerminalSearchMode.caseSensitiveSubstring =>
        'Case-Sensitive Substring',
      terminal.TerminalSearchMode.caseInsensitiveSubstring =>
        'Case-Insensitive Substring',
      terminal.TerminalSearchMode.caseSensitiveRegex => 'Case-Sensitive Regex',
      terminal.TerminalSearchMode.caseInsensitiveRegex =>
        'Case-Insensitive Regex',
    };
  }

  Widget _searchModeMark(terminal.TerminalSearchMode mode) {
    final palette = widget.palette;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: palette.textPrimary,
      fontWeight: FontWeight.w800,
      height: 1,
    );
    return switch (mode) {
      terminal.TerminalSearchMode.smartCaseSubstring => Icon(
        Icons.manage_search_rounded,
        size: 17,
        color: palette.textPrimary,
      ),
      terminal.TerminalSearchMode.caseSensitiveSubstring => Text(
        'Aa',
        style: style,
      ),
      terminal.TerminalSearchMode.caseInsensitiveSubstring => Text(
        'aa',
        style: style,
      ),
      terminal.TerminalSearchMode.caseSensitiveRegex => Text(
        '.*',
        style: style,
      ),
      terminal.TerminalSearchMode.caseInsensitiveRegex => Text(
        '.*i',
        style: style,
      ),
    };
  }

  Widget _buildSearchModeButton(
    BuildContext context,
    MenuController controller,
  ) {
    final palette = widget.palette;
    return Tooltip(
      message: 'Search filter: ${_searchModeLabel(widget.searchMode)}',
      child: Semantics(
        button: true,
        label: 'Search filter',
        child: InkWell(
          key: const Key('terminal-search-mode'),
          borderRadius: BorderRadius.circular(palette.radius.sm),
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(palette.radius.sm),
            ),
            child: SizedBox(
              width: 40,
              height: _searchBarControlHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    child: Center(child: _searchModeMark(widget.searchMode)),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: palette.textSubtle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSearchModeMenuChildren(BuildContext context) {
    final palette = widget.palette;
    final textTheme = Theme.of(context).textTheme;
    final modes = terminal.TerminalSearchMode.values;

    Widget item(terminal.TerminalSearchMode mode) {
      final selected = mode == widget.searchMode;
      return MenuItemButton(
        key: Key('terminal-search-mode-${mode.wireName}'),
        onPressed: () {
          widget.onModeChanged(mode);
        },
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(336, 34)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          backgroundColor: WidgetStateProperty.all(
            selected ? palette.selected : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.all(palette.textPrimary),
          overlayColor: WidgetStateProperty.all(
            palette.accent.withValues(alpha: 0.12),
          ),
        ),
        leadingIcon: selected
            ? Icon(Icons.check_rounded, size: 18, color: palette.textPrimary)
            : const SizedBox(width: 18, height: 18),
        child: Text(
          _searchModeLabel(mode),
          style: textTheme.bodyMedium?.copyWith(
            color: palette.textPrimary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      );
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          'Filter',
          style: textTheme.titleSmall?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Divider(color: palette.border),
      item(modes[0]),
      Divider(color: palette.border),
      item(modes[1]),
      item(modes[2]),
      Divider(color: palette.border),
      item(modes[3]),
      item(modes[4]),
    ];
  }

  Widget _buildSearchModeMenu(BuildContext context) {
    final palette = widget.palette;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(palette.overlay),
        elevation: WidgetStateProperty.all(8.0),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(palette.radius.md),
            side: BorderSide(color: palette.borderStrong),
          ),
        ),
      ),
      menuChildren: _buildSearchModeMenuChildren(context),
      builder: (context, controller, child) {
        return _buildSearchModeButton(context, controller);
      },
    );
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (isShiftPressed) {
        widget.onPrevious();
      } else {
        widget.onNext();
      }
      return KeyEventResult.handled;
    }
    if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
      _focusAndSelectQuery();
      return KeyEventResult.handled;
    }
    if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyA) {
      _focusAndSelectQuery();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildInlineSearchClearButton() {
    return _buildCompactActionButton(
      key: const Key('terminal-search-clear'),
      tooltip: 'Clear search text',
      onPressed: widget.onClear,
      splashRadius: 14,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 22, height: 22),
      icon: Icon(Icons.cancel_rounded, color: widget.palette.textSubtle),
    );
  }

  Widget _buildInlineSearchStatus(BuildContext context) {
    if (_counterText.isEmpty) {
      return const SizedBox.shrink();
    }
    final foreground = _statusForeground(context);
    return Semantics(
      liveRegion: true,
      label: 'Search result: $_counterText',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 78),
        child: Padding(
          key: const Key('terminal-search-status'),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            _counterText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground.withValues(alpha: 0.92),
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final palette = widget.palette;
    final textTheme = Theme.of(context).textTheme;
    final baseTextStyle = textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final inputTextStyle = baseTextStyle.copyWith(
      color: palette.textPrimary,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );
    final hintTextStyle = baseTextStyle.copyWith(
      color: palette.textSubtle,
      fontWeight: FontWeight.w500,
      height: 1.1,
    );
    return AnimatedBuilder(
      animation: widget.focusNode,
      builder: (context, _) {
        final focused = widget.focusNode.hasFocus;
        return SizedBox(
          key: const Key('terminal-search-input'),
          height: _searchBarControlHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.chrome.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(palette.radius.sm),
              border: Border.all(
                color: focused ? palette.focusRing : palette.border,
                width: focused ? 1.4 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 2, right: 8),
              child: Row(
                children: [
                  _buildSearchModeMenu(context),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _handleSearchKeyEvent,
                      child: Semantics(
                        label: 'Search terminal output',
                        textField: true,
                        child: SizedBox(
                          height: _searchBarControlHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              height: _searchFieldEditHeight,
                              child: TextField(
                                key: const Key('terminal-search-field'),
                                focusNode: widget.focusNode,
                                controller: _controller,
                                autofocus: true,
                                textInputAction: TextInputAction.search,
                                textAlignVertical: TextAlignVertical.center,
                                minLines: 1,
                                maxLines: 1,
                                cursorColor: palette.focusRing,
                                strutStyle: StrutStyle.fromTextStyle(
                                  inputTextStyle,
                                  forceStrutHeight: true,
                                ),
                                onChanged: widget.onChanged,
                                onSubmitted: (_) => widget.onNext(),
                                style: inputTextStyle,
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: 'Search',
                                  hintStyle: hintTextStyle,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_counterText.isNotEmpty)
                    _buildInlineSearchStatus(context),
                  if (widget.query.isNotEmpty) const SizedBox(width: 2),
                  if (widget.query.isNotEmpty) _buildInlineSearchClearButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _statusForeground(BuildContext context) {
    if (widget.errorText != null) {
      return Theme.of(context).colorScheme.onErrorContainer;
    }
    if (widget.matches == 0 && widget.query.isNotEmpty) {
      return widget.palette.warning;
    }
    return widget.palette.textPrimary;
  }

  List<Widget> _buildSearchNavigationButtons(BoxConstraints constraints) {
    return [
      _buildCompactActionButton(
        key: const Key('terminal-search-previous'),
        tooltip: 'Previous match',
        onPressed: widget.matches == 0 ? null : widget.onPrevious,
        splashRadius: 18,
        iconSize: 24,
        padding: EdgeInsets.zero,
        constraints: constraints,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      _buildCompactActionButton(
        key: const Key('terminal-search-next'),
        tooltip: 'Next match',
        onPressed: widget.matches == 0 ? null : widget.onNext,
        splashRadius: 18,
        iconSize: 24,
        padding: EdgeInsets.zero,
        constraints: constraints,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ];
  }

  Widget _buildSearchCloseButton(BoxConstraints constraints) {
    return _buildCompactActionButton(
      key: const Key('terminal-search-close'),
      tooltip: 'Close search',
      onPressed: widget.onClose,
      splashRadius: 16,
      iconSize: 22,
      padding: EdgeInsets.zero,
      constraints: constraints,
      icon: const Icon(Icons.close_rounded),
    );
  }

  Widget _buildRegularSearchRow(
    BuildContext context,
    BoxConstraints actionButtonConstraints,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSearchField(context)),
        const SizedBox(width: 12),
        ..._buildSearchNavigationButtons(actionButtonConstraints),
        const SizedBox(width: 4),
        _buildSearchCloseButton(actionButtonConstraints),
      ],
    );
  }

  Widget _buildCompactSearchRows(
    BuildContext context,
    BoxConstraints actionButtonConstraints,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSearchField(context)),
        const SizedBox(width: 8),
        _buildSearchCloseButton(actionButtonConstraints),
      ],
    );
  }

  Widget _buildSearchPanel(BuildContext context, {required bool compact}) {
    final palette = widget.palette;
    const actionButtonConstraints = BoxConstraints.tightFor(
      width: 34,
      height: 40,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.overlay.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(palette.radius.lg),
        border: Border.all(
          color: widget.errorText == null
              ? palette.borderStrong.withValues(alpha: 0.72)
              : Theme.of(context).colorScheme.error.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _searchBarHorizontalInset,
          vertical: _searchBarVerticalInset,
        ),
        child: compact
            ? _buildCompactSearchRows(context, actionButtonConstraints)
            : _buildRegularSearchRow(context, actionButtonConstraints),
      ),
    );
  }

  double get _preferredBarWidth {
    if (widget.query.isEmpty && widget.errorText == null) {
      return _searchBarIdleWidth;
    }
    return _searchBarMaxWidth;
  }

  @override
  Widget build(BuildContext context) {
    final preferredWidth = _preferredBarWidth;
    return Material(
      key: const Key('terminal-search-bar'),
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : preferredWidth;
          final width = math.min(preferredWidth, availableWidth);
          final compact = width < _searchBarCompactBreakpoint;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: width,
                child: _buildSearchPanel(context, compact: compact),
              ),
              if (widget.errorText != null)
                _TerminalSearchErrorPopover(
                  errorText: widget.errorText!,
                  palette: widget.palette,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TerminalSearchErrorPopover extends StatelessWidget {
  const _TerminalSearchErrorPopover({
    required this.errorText,
    required this.palette,
  });

  final String errorText;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 276),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(
              color: colorScheme.error.withValues(alpha: 0.55),
            ),
            boxShadow: palette.elevation.floating,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    errorText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
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

  String get _scopeText {
    final count = widget.sessions.length;
    final noun = count == 1 ? 'session' : 'sessions';
    return 'Searching across $count $noun';
  }

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
                      const SizedBox(width: 8),
                      _buildSheetCloseButton(
                        buttonKey: const Key('terminal-global-search-close'),
                        tooltip: 'Close global search',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: _query.trim().isEmpty
                        ? Center(
                            child: Text(
                              _scopeText,
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
      decoration: InputDecoration(prefixIcon: Icon(icon), labelText: label),
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
    return Semantics(
      key: Key('terminal-autocomplete-suggestion-$suggestion'),
      label: suggestion,
      button: true,
      selected: active,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
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
    return Semantics(
      key: Key('terminal-auto-composer-suggestion-$suggestion'),
      label: suggestion,
      button: true,
      selected: active,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
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
                          color: active
                              ? palette.textPrimary
                              : palette.textSubtle,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
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
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: 'Instant Replay',
      child: Padding(
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
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
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
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: palette.textSubtle,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        key: const Key('instant-replay-clear'),
                        style: TextButton.styleFrom(
                          foregroundColor: palette.textSubtle,
                          disabledForegroundColor: palette.textMuted.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        onPressed: _frames.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  _frames = const [];
                                  _activeIndex = 0;
                                });
                                widget.onClear();
                              },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                        ),
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
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.textSubtle),
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
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
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
                      divisions: _frames.length <= 1
                          ? null
                          : _frames.length - 1,
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
                          borderRadius: BorderRadius.circular(
                            palette.radius.md,
                          ),
                          border: Border.all(color: palette.border),
                        ),
                        child: SingleChildScrollView(
                          key: const Key('instant-replay-preview'),
                          padding: const EdgeInsets.all(10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
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
                  MergeSemantics(
                    child: Semantics(
                      label: 'Paste text',
                      textField: true,
                      child: TextField(
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
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSubtle,
                        disabledForegroundColor: palette.textMuted.withValues(
                          alpha: 0.5,
                        ),
                      ),
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
                              'No trigger output captured yet. Add profile triggers or coprocess patterns to collect matching terminal lines here.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
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
                              'No annotations in this session. Select terminal output first, then open Annotations to attach a note.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
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
                  subtitle:
                      'Keep recent copied and pasted text across launches.',
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
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSubtle,
                        disabledForegroundColor: palette.textMuted.withValues(
                          alpha: 0.5,
                        ),
                      ),
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
                          separatorBuilder: (_, _) => const Divider(height: 1),
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
  late final FocusNode _passwordFocusNode;

  bool get _canAddEntry => _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
    _labelController = TextEditingController();
    _passwordController = TextEditingController();
    _passwordFocusNode = FocusNode(debugLabel: 'password-manager-password');
    _passwordController.addListener(_handlePasswordChanged);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_handlePasswordChanged);
    _labelController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _handlePasswordChanged() {
    setState(() {});
  }

  void _addEntry() {
    final password = _passwordController.text;
    if (!_canAddEntry) {
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
                const SizedBox(height: 4),
                Text(
                  'Passwords are kept for this app session and can only be sent when the active terminal appears to be asking for one.',
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
                Semantics(
                  label: 'Password',
                  value: _passwordController.text.isEmpty
                      ? ''
                      : 'Password entered',
                  textField: true,
                  obscured: true,
                  excludeSemantics: true,
                  onTap: () => _passwordFocusNode.requestFocus(),
                  onSetText: (text) {
                    _passwordController.value = TextEditingValue(
                      text: text,
                      selection: TextSelection.collapsed(offset: text.length),
                    );
                  },
                  child: TextField(
                    key: const Key('password-manager-password-field'),
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _addEntry(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const Key('password-manager-add'),
                    onPressed: _canAddEntry ? _addEntry : null,
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
                              'No saved passwords in this session. Add one above, then open a password prompt before sending.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
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
      subtitle: promptDetected
          ? 'Ready to send'
          : 'Waiting for password prompt',
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

class _ShellCommandMenuHotkeyStatus extends StatefulWidget {
  const _ShellCommandMenuHotkeyStatus({
    required this.statusFuture,
    required this.builder,
  });

  final Future<HotkeyWindowStatus?> statusFuture;
  final Widget Function(HotkeyWindowStatus? status) builder;

  @override
  State<_ShellCommandMenuHotkeyStatus> createState() =>
      _ShellCommandMenuHotkeyStatusState();
}

class _ShellCommandMenuHotkeyStatusState
    extends State<_ShellCommandMenuHotkeyStatus> {
  HotkeyWindowStatus? _status;

  @override
  void initState() {
    super.initState();
    widget.statusFuture.then((status) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_status);
  }
}

class _ShellCommandMenu extends StatefulWidget {
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
    required this.searchShortcutLabel,
    required this.hasDefaultProfile,
    required this.hasActiveSession,
    required this.activePaneZoomed,
    required this.canReopenClosedTab,
    required this.splitRightUnavailableReason,
    required this.splitDownUnavailableReason,
    required this.hotkeyWindowStatus,
    required this.isActiveSessionReadOnly,
    required this.notificationsBlockedBySystem,
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
  final String searchShortcutLabel;
  final bool hasDefaultProfile;
  final bool hasActiveSession;
  final bool activePaneZoomed;
  final bool canReopenClosedTab;
  final String? splitRightUnavailableReason;
  final String? splitDownUnavailableReason;
  final HotkeyWindowStatus? hotkeyWindowStatus;
  final bool isActiveSessionReadOnly;
  final bool notificationsBlockedBySystem;
  final bool commandFinishedNotificationsEnabled;
  final bool bellNotificationsEnabled;
  final bool activityMonitorEnabled;
  final bool canSelectCommandOutput;

  @override
  State<_ShellCommandMenu> createState() => _ShellCommandMenuState();
}

class _ShellCommandMenuState extends State<_ShellCommandMenu> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final maxMenuHeight = (MediaQuery.sizeOf(context).height - 24)
        .clamp(360.0, 560.0)
        .toDouble();
    final launcherShortcutLabel = widget.launcherShortcutLabel;
    final newTabShortcutLabel = widget.newTabShortcutLabel;
    final hotkeyWindowShortcutLabel = widget.hotkeyWindowShortcutLabel;
    final autocompleteShortcutLabel = widget.autocompleteShortcutLabel;
    final copyModeShortcutLabel = widget.copyModeShortcutLabel;
    final sessionCopyShortcutLabel = widget.sessionCopyShortcutLabel;
    final sessionPasteShortcutLabel = widget.sessionPasteShortcutLabel;
    final pasteHistoryShortcutLabel = widget.pasteHistoryShortcutLabel;
    final instantReplayShortcutLabel = widget.instantReplayShortcutLabel;
    final searchShortcutLabel = widget.searchShortcutLabel;
    final hasDefaultProfile = widget.hasDefaultProfile;
    final hasActiveSession = widget.hasActiveSession;
    final activePaneZoomed = widget.activePaneZoomed;
    final canReopenClosedTab = widget.canReopenClosedTab;
    final splitRightUnavailableReason = widget.splitRightUnavailableReason;
    final splitDownUnavailableReason = widget.splitDownUnavailableReason;
    final hotkeyWindowStatus = widget.hotkeyWindowStatus;
    final isActiveSessionReadOnly = widget.isActiveSessionReadOnly;
    final notificationsBlockedBySystem = widget.notificationsBlockedBySystem;
    final commandFinishedNotificationsEnabled =
        widget.commandFinishedNotificationsEnabled;
    final bellNotificationsEnabled = widget.bellNotificationsEnabled;
    final activityMonitorEnabled = widget.activityMonitorEnabled;
    final canSelectCommandOutput = widget.canSelectCommandOutput;

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

    const activeSessionRequired = 'Open a terminal tab first.';
    const defaultProfileRequired = 'No default profile is configured.';
    const closedTabRequired = 'No recently closed tab is available.';
    const readOnlySendRequired = 'Disable read-only mode to send text.';

    String? hotkeyWindowUnavailableReason() {
      final status = hotkeyWindowStatus;
      if (status == null || status.registered) {
        return null;
      }
      final details = <String>[
        'Hotkey window is unavailable.',
        'Shortcut: ${status.shortcut}.',
        if (status.errorCode != null) 'Error: ${status.errorCode}.',
      ];
      return details.join(' ');
    }

    String selectCommandOutputUnavailableReason() {
      if (!hasActiveSession) {
        return activeSessionRequired;
      }
      return 'No prompt-marked command output is available yet.';
    }

    Widget commandTile({
      Key? key,
      required TerminalActionId actionId,
      required IconData icon,
      required String title,
      required String subtitle,
      required bool enabled,
      String? disabledReason,
      int subtitleMaxLines = 1,
      String? shortcutLabel,
      VoidCallback? onTap,
    }) {
      if (!_commandMenuActionMatchesQuery(
        actionId,
        _query,
        title: title,
        subtitle: subtitle,
      )) {
        return const SizedBox.shrink();
      }

      return _ShellCommandTile(
        key: key,
        icon: icon,
        title: title,
        subtitle: subtitle,
        shortcutLabel: shortcutLabel,
        enabled: enabled,
        disabledReason: disabledReason,
        subtitleMaxLines: subtitleMaxLines,
        onTap: onTap,
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                      child: MergeSemantics(
                        child: Semantics(
                          label: 'Search actions',
                          textField: true,
                          child: TextField(
                            key: const Key('shell-command-search-field'),
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: palette.textPrimary),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search_rounded),
                              labelText: 'Search actions',
                              hintText: 'Type an action and press Enter',
                              helperText:
                                  'Examples: profile, paste history, read-only',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  palette.radius.lg,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _query = value;
                              });
                            },
                            onSubmitted: (query) {
                              final action = _commandMenuActionForQuery(query);
                              if (action == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'No action matches "$query".',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(context).pop(action);
                            },
                          ),
                        ),
                      ),
                    ),
                    commandTile(
                      key: const Key('shell-search-scrollback-top'),
                      actionId: TerminalActionId.search,
                      icon: Icons.search_rounded,
                      title: 'Search terminal output',
                      subtitle:
                          'Top action • Open in-terminal search for the active pane.',
                      shortcutLabel: searchShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.search),
                    ),
                    sectionLabel('App actions'),
                    commandTile(
                      key: const Key('shell-new-tab'),
                      actionId: TerminalActionId.newTab,
                      icon: Icons.add_box_outlined,
                      title: 'New tab',
                      subtitle: 'App action • Open the default shell profile.',
                      shortcutLabel: newTabShortcutLabel,
                      enabled: hasDefaultProfile,
                      disabledReason: defaultProfileRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.newTab),
                    ),
                    commandTile(
                      key: const Key('shell-command-defaults'),
                      actionId: TerminalActionId.defaults,
                      icon: Icons.tune_rounded,
                      title: 'Defaults & appearance',
                      subtitle:
                          'App action • Pick the default profile and theme.',
                      enabled: true,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.defaults),
                    ),
                    commandTile(
                      key: const Key('shell-reopen-closed-tab'),
                      actionId: TerminalActionId.reopenClosedTab,
                      icon: Icons.restore_rounded,
                      title: 'Reopen closed tab',
                      subtitle:
                          'App action • Recreate the most recently closed tab.',
                      enabled: canReopenClosedTab,
                      disabledReason: closedTabRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.reopenClosedTab),
                    ),
                    commandTile(
                      key: const Key('shell-toolbelt'),
                      actionId: TerminalActionId.toolbelt,
                      icon: Icons.view_sidebar_rounded,
                      title: 'Toolbelt',
                      subtitle:
                          'App action • Keep terminal tools in a sidebar.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.toolbelt),
                    ),
                    commandTile(
                      key: const Key('shell-split-right'),
                      actionId: TerminalActionId.splitRight,
                      icon: Icons.vertical_split_rounded,
                      title: 'Split right',
                      subtitle: 'Session action • Add a pane to the right.',
                      enabled:
                          hasDefaultProfile &&
                          hasActiveSession &&
                          splitRightUnavailableReason == null,
                      disabledReason: !hasDefaultProfile
                          ? defaultProfileRequired
                          : !hasActiveSession
                          ? activeSessionRequired
                          : splitRightUnavailableReason,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.splitRight),
                    ),
                    commandTile(
                      key: const Key('shell-split-down'),
                      actionId: TerminalActionId.splitDown,
                      icon: Icons.horizontal_split_rounded,
                      title: 'Split down',
                      subtitle: 'Session action • Add a pane below.',
                      enabled:
                          hasDefaultProfile &&
                          hasActiveSession &&
                          splitDownUnavailableReason == null,
                      disabledReason: !hasDefaultProfile
                          ? defaultProfileRequired
                          : !hasActiveSession
                          ? activeSessionRequired
                          : splitDownUnavailableReason,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.splitDown),
                    ),
                    commandTile(
                      key: const Key('shell-zoom-pane'),
                      actionId: TerminalActionId.zoomPane,
                      icon: Icons.zoom_out_map_rounded,
                      title: activePaneZoomed
                          ? 'Unzoom active pane'
                          : 'Zoom active pane',
                      subtitle: 'Session action • Focus one pane temporarily.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.zoomPane),
                    ),
                    commandTile(
                      key: const Key('shell-theme-picker'),
                      actionId: TerminalActionId.openThemePicker,
                      icon: Icons.palette_rounded,
                      title: 'Terminal color presets',
                      subtitle:
                          'App action • Open Defaults & appearance to choose terminal colors.',
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.openThemePicker),
                    ),
                    commandTile(
                      key: const Key('shell-toggle-command-finished-notify'),
                      actionId: TerminalActionId.toggleCommandFinishedNotify,
                      icon: Icons.notifications_active_rounded,
                      title:
                          '${commandFinishedNotificationsEnabled ? 'Disable' : 'Enable'} command-finished notifications',
                      subtitle: notificationsBlockedBySystem
                          ? 'App action • Toggle shell hook completion alerts. macOS notifications are currently blocked in System Settings.'
                          : 'App action • Toggle shell hook completion alerts.',
                      subtitleMaxLines: notificationsBlockedBySystem ? 2 : 1,
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.toggleCommandFinishedNotify),
                    ),
                    commandTile(
                      key: const Key('shell-toggle-bell-notify'),
                      actionId: TerminalActionId.toggleBellNotify,
                      icon: Icons.notifications_rounded,
                      title:
                          '${bellNotificationsEnabled ? 'Disable' : 'Enable'} bell notifications',
                      subtitle: notificationsBlockedBySystem
                          ? 'App action • Toggle terminal bell alerts. macOS notifications are currently blocked in System Settings.'
                          : 'App action • Toggle terminal bell alerts.',
                      subtitleMaxLines: notificationsBlockedBySystem ? 2 : 1,
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.toggleBellNotify),
                    ),
                    commandTile(
                      key: const Key('shell-toggle-activity-monitor'),
                      actionId: TerminalActionId.toggleActivityMonitor,
                      icon: Icons.notification_important_rounded,
                      title:
                          '${activityMonitorEnabled ? 'Disable' : 'Enable'} activity monitor',
                      subtitle: notificationsBlockedBySystem
                          ? 'App action • Toggle inactive-session activity alerts. macOS notifications are currently blocked in System Settings.'
                          : 'App action • Toggle inactive-session activity alerts.',
                      subtitleMaxLines: notificationsBlockedBySystem ? 2 : 1,
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.toggleActivityMonitor),
                    ),
                    commandTile(
                      key: const Key('shell-command-profiles'),
                      actionId: TerminalActionId.profiles,
                      icon: Icons.folder_open_rounded,
                      title: 'Profiles…',
                      subtitle: 'App action • Open or edit shell profiles.',
                      enabled: true,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.profiles),
                    ),
                    commandTile(
                      key: const Key('shell-dynamic-profiles'),
                      actionId: TerminalActionId.dynamicProfiles,
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
                    commandTile(
                      actionId: TerminalActionId.copy,
                      icon: Icons.copy_rounded,
                      title: 'Copy selection',
                      subtitle: 'Session action • Copy the current selection.',
                      shortcutLabel: sessionCopyShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.copy),
                    ),
                    commandTile(
                      key: const Key('shell-copy-mode'),
                      actionId: TerminalActionId.copyMode,
                      icon: Icons.select_all_rounded,
                      title: 'Copy mode',
                      subtitle:
                          'Session action • Select terminal text from the keyboard.',
                      shortcutLabel: copyModeShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.copyMode),
                    ),
                    commandTile(
                      key: const Key('shell-toggle-read-only'),
                      actionId: TerminalActionId.toggleReadOnly,
                      icon: Icons.lock_outline_rounded,
                      title:
                          '${isActiveSessionReadOnly ? 'Disable' : 'Enable'} read-only mode',
                      subtitle:
                          'Session action • Block terminal input for this pane.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.toggleReadOnly),
                    ),
                    commandTile(
                      key: const Key('shell-clear-scrollback'),
                      actionId: TerminalActionId.clearScrollback,
                      icon: Icons.clear_all_rounded,
                      title: 'Clear scrollback',
                      subtitle:
                          'Session action • Clear local scrollback when supported.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.clearScrollback),
                    ),
                    commandTile(
                      key: const Key('shell-export-scrollback'),
                      actionId: TerminalActionId.exportScrollback,
                      icon: Icons.ios_share_rounded,
                      title: 'Export scrollback',
                      subtitle:
                          'Session action • Save a terminal text snapshot to Application Support.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.exportScrollback),
                    ),
                    commandTile(
                      key: const Key('shell-export-diagnostics'),
                      actionId: TerminalActionId.exportDiagnostics,
                      icon: Icons.bug_report_rounded,
                      title: 'Export diagnostics',
                      subtitle:
                          'Session action • Save a local resource evidence bundle.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.exportDiagnostics),
                    ),
                    commandTile(
                      key: const Key('shell-annotations'),
                      actionId: TerminalActionId.annotations,
                      icon: Icons.sticky_note_2_rounded,
                      title: 'Annotations',
                      subtitle:
                          'Session action • Attach notes to selected output.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.annotations),
                    ),
                    commandTile(
                      key: const Key('shell-captured-output'),
                      actionId: TerminalActionId.capturedOutput,
                      icon: Icons.outbox_rounded,
                      title: 'Captured output',
                      subtitle:
                          'Session action • Review lines matched by triggers.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.capturedOutput),
                    ),
                    commandTile(
                      key: const Key('shell-paste-clipboard'),
                      actionId: TerminalActionId.paste,
                      icon: Icons.content_paste_rounded,
                      title: 'Paste clipboard',
                      subtitle:
                          'Session action • Paste clipboard into the shell.',
                      shortcutLabel: sessionPasteShortcutLabel,
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.paste),
                    ),
                    commandTile(
                      key: const Key('shell-advanced-paste'),
                      actionId: TerminalActionId.advancedPaste,
                      icon: Icons.assignment_rounded,
                      title: 'Advanced paste',
                      subtitle:
                          'Session action • Edit and transform text before pasting.',
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.advancedPaste),
                    ),
                    commandTile(
                      key: const Key('shell-paste-history'),
                      actionId: TerminalActionId.pasteHistory,
                      icon: Icons.history_rounded,
                      title: 'Paste history',
                      subtitle:
                          'Session action • Revisit recently copied or pasted text.',
                      shortcutLabel: pasteHistoryShortcutLabel,
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.pasteHistory),
                    ),
                    commandTile(
                      key: const Key('shell-integration-utilities'),
                      actionId: TerminalActionId.shellIntegrationUtilities,
                      icon: Icons.integration_instructions_rounded,
                      title: 'Shell integration',
                      subtitle:
                          'Session action • Command history, directories, and marks.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.shellIntegrationUtilities),
                    ),
                    commandTile(
                      key: const Key('shell-select-command-output'),
                      actionId: TerminalActionId.selectCommandOutput,
                      icon: Icons.fact_check_rounded,
                      title: 'Select command output',
                      subtitle:
                          'Session action • Select output between prompt marks.',
                      enabled: hasActiveSession && canSelectCommandOutput,
                      disabledReason: selectCommandOutputUnavailableReason(),
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.selectCommandOutput),
                    ),
                    commandTile(
                      key: const Key('shell-tmux-integration'),
                      actionId: TerminalActionId.tmuxIntegration,
                      icon: Icons.account_tree_rounded,
                      title: 'tmux integration',
                      subtitle:
                          'Session action • Start or drive tmux control mode.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.tmuxIntegration),
                    ),
                    commandTile(
                      key: const Key('shell-coprocess'),
                      actionId: TerminalActionId.coprocess,
                      icon: Icons.hub_rounded,
                      title: 'Coprocess',
                      subtitle:
                          'Session action • Automate replies from terminal output.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.coprocess),
                    ),
                    commandTile(
                      key: const Key('shell-password-manager'),
                      actionId: TerminalActionId.passwordManager,
                      icon: Icons.password_rounded,
                      title: 'Password manager',
                      subtitle:
                          'Session action • Send saved passwords at prompts.',
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.passwordManager),
                    ),
                    commandTile(
                      key: const Key('shell-instant-replay'),
                      actionId: TerminalActionId.instantReplay,
                      icon: Icons.replay_rounded,
                      title: 'Instant replay',
                      subtitle:
                          'Session action • Recover text from recent terminal frames.',
                      shortcutLabel: instantReplayShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.instantReplay),
                    ),
                    commandTile(
                      actionId: TerminalActionId.search,
                      icon: Icons.search_rounded,
                      title: 'Search scrollback',
                      subtitle: 'Session action • Find text in local output.',
                      shortcutLabel: searchShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.search),
                    ),
                    commandTile(
                      key: const Key('shell-global-search'),
                      actionId: TerminalActionId.globalSearch,
                      icon: Icons.manage_search_rounded,
                      title: 'Global search',
                      subtitle: 'Workspace action • Search all tabs at once.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.globalSearch),
                    ),
                    commandTile(
                      key: const Key('shell-autocomplete'),
                      actionId: TerminalActionId.autocomplete,
                      icon: Icons.auto_fix_high_rounded,
                      title: 'Autocomplete',
                      subtitle:
                          'Session action • Complete a word from visible output.',
                      shortcutLabel: autocompleteShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.autocomplete),
                    ),
                    commandTile(
                      key: const Key('shell-auto-composer'),
                      actionId: TerminalActionId.autoComposer,
                      icon: Icons.edit_note_rounded,
                      title: 'Auto Composer',
                      subtitle:
                          'Session action • Native command editor with completions.',
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.autoComposer),
                    ),
                    commandTile(
                      key: const Key('shell-hotkey-window'),
                      actionId: TerminalActionId.hotkeyWindow,
                      icon: Icons.keyboard_rounded,
                      title: 'Hotkey window',
                      subtitle:
                          'App action • Hide this window. Reopen with $hotkeyWindowShortcutLabel.',
                      shortcutLabel: hotkeyWindowShortcutLabel,
                      enabled: hotkeyWindowUnavailableReason() == null,
                      disabledReason: hotkeyWindowUnavailableReason(),
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

const _commandMenuActionSearchEntries = <MapEntry<String, TerminalActionId>>[
  MapEntry('new tab open default shell profile', TerminalActionId.newTab),
  MapEntry(
    'defaults appearance default profile theme',
    TerminalActionId.defaults,
  ),
  MapEntry('reopen closed tab restore tab', TerminalActionId.reopenClosedTab),
  MapEntry('toolbelt sidebar terminal tools', TerminalActionId.toolbelt),
  MapEntry('split right vertical pane', TerminalActionId.splitRight),
  MapEntry('split down horizontal pane', TerminalActionId.splitDown),
  MapEntry('zoom active pane unzoom focus', TerminalActionId.zoomPane),
  MapEntry(
    'theme picker terminal color presets appearance defaults',
    TerminalActionId.openThemePicker,
  ),
  MapEntry('export scrollback save output', TerminalActionId.exportScrollback),
  MapEntry(
    'export diagnostics resource cpu memory evidence bundle',
    TerminalActionId.exportDiagnostics,
  ),
  MapEntry(
    'command finished notifications shell hook completion alerts',
    TerminalActionId.toggleCommandFinishedNotify,
  ),
  MapEntry(
    'bell notifications terminal bell alerts',
    TerminalActionId.toggleBellNotify,
  ),
  MapEntry(
    'activity monitor inactive session alerts',
    TerminalActionId.toggleActivityMonitor,
  ),
  MapEntry('profiles edit shell profiles', TerminalActionId.profiles),
  MapEntry(
    'dynamic profiles import json iterm profile',
    TerminalActionId.dynamicProfiles,
  ),
  MapEntry('copy selection', TerminalActionId.copy),
  MapEntry(
    'copy mode select terminal text keyboard',
    TerminalActionId.copyMode,
  ),
  MapEntry(
    'read only readonly lock block input',
    TerminalActionId.toggleReadOnly,
  ),
  MapEntry('clear scrollback clear output', TerminalActionId.clearScrollback),
  MapEntry('annotations notes selected output', TerminalActionId.annotations),
  MapEntry('captured output trigger lines', TerminalActionId.capturedOutput),
  MapEntry('paste clipboard', TerminalActionId.paste),
  MapEntry(
    'advanced paste transform edit paste',
    TerminalActionId.advancedPaste,
  ),
  MapEntry('paste history recent copied pasted', TerminalActionId.pasteHistory),
  MapEntry(
    'shell integration command history directories prompt marks',
    TerminalActionId.shellIntegrationUtilities,
  ),
  MapEntry(
    'select command output prompt marks',
    TerminalActionId.selectCommandOutput,
  ),
  MapEntry('tmux integration control mode', TerminalActionId.tmuxIntegration),
  MapEntry('coprocess automate replies output', TerminalActionId.coprocess),
  MapEntry(
    'password manager saved passwords prompts',
    TerminalActionId.passwordManager,
  ),
  MapEntry(
    'instant replay recent terminal frames',
    TerminalActionId.instantReplay,
  ),
  MapEntry('search scrollback find local output', TerminalActionId.search),
  MapEntry('global search workspace all tabs', TerminalActionId.globalSearch),
  MapEntry(
    'autocomplete complete word visible output',
    TerminalActionId.autocomplete,
  ),
  MapEntry(
    'auto composer command editor completions',
    TerminalActionId.autoComposer,
  ),
  MapEntry('hotkey window summon hide shell', TerminalActionId.hotkeyWindow),
];

TerminalActionId? _commandMenuActionForQuery(String query) {
  final normalized = _normalizeCommandMenuQuery(query);
  if (normalized.isEmpty) {
    return null;
  }
  for (final entry in _commandMenuActionSearchEntries) {
    if (_commandMenuQueryMatches(entry.key, normalized)) {
      return entry.value;
    }
  }
  return null;
}

bool _commandMenuActionMatchesQuery(
  TerminalActionId actionId,
  String query, {
  required String title,
  required String subtitle,
}) {
  final normalized = _normalizeCommandMenuQuery(query);
  if (normalized.isEmpty) {
    return true;
  }

  final fallback = _normalizeCommandMenuQuery(
    '$title $subtitle ${actionId.name}',
  );
  if (_commandMenuQueryMatches(fallback, normalized)) {
    return true;
  }

  return _commandMenuActionSearchEntries
      .where((entry) => entry.value == actionId)
      .map((entry) => entry.key)
      .any((entry) => _commandMenuQueryMatches(entry, normalized));
}

bool _commandMenuQueryMatches(String candidate, String query) {
  final normalizedCandidate = _normalizeCommandMenuQuery(candidate);
  final normalizedQuery = _normalizeCommandMenuQuery(query);
  if (normalizedQuery.isEmpty) {
    return true;
  }
  if (normalizedCandidate.isEmpty) {
    return false;
  }
  if (normalizedCandidate.contains(normalizedQuery) ||
      normalizedQuery.contains(normalizedCandidate)) {
    return true;
  }

  final candidateTokens = normalizedCandidate.split(' ');
  return normalizedQuery
      .split(' ')
      .every(
        (queryToken) => candidateTokens.any(
          (candidateToken) =>
              candidateToken.contains(queryToken) ||
              queryToken.contains(candidateToken),
        ),
      );
}

String _normalizeCommandMenuQuery(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

class _PaneDividerHandle extends StatefulWidget {
  const _PaneDividerHandle({
    super.key,
    required this.direction,
    required this.thickness,
    required this.terminalBackground,
    required this.palette,
    required this.onDragUpdate,
  });

  final Axis direction;
  final double thickness;
  final Color terminalBackground;
  final AppThemeTokens palette;
  final ValueChanged<double> onDragUpdate;

  @override
  State<_PaneDividerHandle> createState() => _PaneDividerHandleState();
}

class _PaneDividerHandleState extends State<_PaneDividerHandle> {
  bool _hovered = false;
  bool _dragging = false;

  bool get _active => _hovered || _dragging;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() {
      _hovered = value;
    });
  }

  void _setDragging(bool value) {
    if (_dragging == value) {
      return;
    }
    setState(() {
      _dragging = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.direction == Axis.horizontal;
    final background = _active
        ? widget.palette.accent.withValues(alpha: _dragging ? 0.16 : 0.09)
        : widget.terminalBackground;
    final lineColor = _active
        ? widget.palette.accent.withValues(alpha: _dragging ? 0.86 : 0.68)
        : widget.palette.borderStrong.withValues(alpha: 0.72);
    final lineThickness = _active ? 2.0 : 1.0;

    return SizedBox(
      width: horizontal ? widget.thickness : double.infinity,
      height: horizontal ? double.infinity : widget.thickness,
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: horizontal ? (_) => _setDragging(true) : null,
          onHorizontalDragEnd: horizontal ? (_) => _setDragging(false) : null,
          onHorizontalDragCancel: horizontal ? () => _setDragging(false) : null,
          onHorizontalDragUpdate: horizontal
              ? (details) => widget.onDragUpdate(details.delta.dx)
              : null,
          onVerticalDragStart: horizontal ? null : (_) => _setDragging(true),
          onVerticalDragEnd: horizontal ? null : (_) => _setDragging(false),
          onVerticalDragCancel: horizontal ? null : () => _setDragging(false),
          onVerticalDragUpdate: horizontal
              ? null
              : (details) => widget.onDragUpdate(details.delta.dy),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOutCubic,
            color: background,
            child: Align(
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOutCubic,
                width: horizontal ? lineThickness : double.infinity,
                height: horizontal ? double.infinity : lineThickness,
                decoration: BoxDecoration(
                  color: lineColor,
                  borderRadius: BorderRadius.circular(2),
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
    this.disabledReason,
    this.subtitleMaxLines = 1,
    this.shortcutLabel,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String? disabledReason;
  final int subtitleMaxLines;
  final String? shortcutLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final effectiveSubtitle = enabled
        ? subtitle
        : 'Unavailable: ${disabledReason ?? 'Unavailable in the current context.'}';
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
        effectiveSubtitle,
        maxLines: enabled ? subtitleMaxLines : 2,
        overflow: TextOverflow.ellipsis,
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
  EdgeInsetsGeometry? padding,
  BoxConstraints? constraints,
}) {
  return Semantics(
    label: tooltip,
    button: true,
    enabled: onPressed != null,
    excludeSemantics: true,
    onTap: onPressed,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      isSelected: isSelected,
      onPressed: onPressed,
      visualDensity: constraints == null
          ? VisualDensity.compact
          : VisualDensity.standard,
      splashRadius: splashRadius,
      iconSize: iconSize,
      padding: padding,
      constraints: constraints,
      selectedIcon: selectedIcon == null
          ? null
          : Semantics(
              label: tooltip,
              child: ExcludeSemantics(child: selectedIcon),
            ),
      icon: Semantics(
        label: tooltip,
        child: ExcludeSemantics(child: icon),
      ),
    ),
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
      return Semantics(
        label: tooltip,
        button: true,
        enabled: onPressed != null,
        excludeSemantics: true,
        onTap: onPressed,
        child: IconButton(
          key: key,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: ExcludeSemantics(
            child: Icon(icon, color: context.appTheme.textMuted),
          ),
        ),
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
  Color? hoverBackgroundColor,
}) {
  return Semantics(
    label: tooltip,
    button: true,
    enabled: onPressed != null,
    excludeSemantics: true,
    onTap: onPressed,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      splashRadius: 16,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (hoverBackgroundColor == null) {
            return Colors.transparent;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return hoverBackgroundColor;
          }
          return Colors.transparent;
        }),
      ),
      iconSize: iconSize,
      icon: ExcludeSemantics(child: icon),
    ),
  );
}
