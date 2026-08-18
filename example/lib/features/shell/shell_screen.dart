import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ianvs_pty/ianvs_pty.dart' as pty;
import 'package:path_provider/path_provider.dart';

import '../../data/configuration/data_api_configuration.dart';
import '../../data/configuration/data_api_configuration_providers.dart';
import '../../data/configuration/data_api_configuration_repository.dart';
import '../../data/services/data_api_client.dart';
import '../../data/services/data_api_migration_service.dart';
import '../../data/services/data_api_runtime.dart';
import '../../platform/clipboard_bridge.dart';
import '../../platform/terminal_graphic_image_actions.dart';
import '../../ui/app_ui.dart';
import '../config/local_terminal_config_bootstrap.dart';
import '../config/local_terminal_config_models.dart';
import '../config/shortcut_editor.dart';
import '../persistence/versioned_document.dart';
import '../policies/local_terminal_paste_decision.dart';
import '../policies/local_terminal_policy_models.dart';
import '../preferences/app_preferences_models.dart';
import '../profiles/dynamic_profiles_sheet.dart';
import '../profiles/profile_editor.dart';
import '../profiles/profile_models.dart';
import '../profiles/profiles_sheet.dart';
import '../recording/local_session_recording_repository.dart';
import '../recording/recording_replay_search_index.dart';
import '../recording/replay_viewport_layout.dart';
import '../sessions/session_controller.dart';
import '../sessions/session_state.dart';
import '../sessions/terminal_event_coordinator.dart';
import '../sessions/terminal_session_launch_policy.dart';
import '../sftp/sftp_side_panel.dart';
import '../ssh/new_session_launcher.dart';
import '../ssh/ssh_auth_prompt.dart';
import '../ssh/ssh_feature_access.dart';
import '../ssh/ssh_profile_import_service.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal.dart' as terminal;
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart';
import '../terminal/terminal_viewport_colors.dart';
import '../visual/local_terminal_diagnostics_exporter.dart';
import '../visual/local_terminal_scrollback_exporter.dart';
import '../visual/local_terminal_visual_models.dart';
import 'advanced_paste_transformer.dart';
import 'defaults_appearance_dialog.dart';
import 'instant_replay_store.dart';
import 'local_terminal_shell_ui_wiring_exports.dart';
import 'osc72_drag_drop_controller.dart';
import 'password_manager_store.dart';
import 'paste_history_repository.dart';
import 'reference_demo.dart';
import 'shell_acceptance.dart';
import 'shell_action_registry.dart';
import 'shell_action_runtime_bindings.dart';
import 'shell_shortcut_bridge.dart';
import 'window_bridge.dart';

part 'shell_screen_chrome.dart';
part 'shell_screen_command_menu.dart';
part 'shell_screen_completion.dart';
part 'shell_screen_instant_replay.dart';
part 'shell_screen_mobile_input.dart';
part 'shell_screen_models.dart';
part 'shell_screen_recording_library.dart';
part 'shell_screen_replay_timeline.dart';
part 'shell_screen_search.dart';
part 'shell_screen_shared_buttons.dart';
part 'shell_screen_sheets.dart';
part 'shell_screen_shell_integration.dart';
part 'shell_screen_sftp.dart';
part 'shell_screen_ssh_empty_state.dart';
part 'shell_screen_state_clipboard.dart';
part 'shell_screen_state_command_actions.dart';
part 'shell_screen_state_coprocesses.dart';
part 'shell_screen_state_events.dart';
part 'shell_screen_state_folders.dart';
part 'shell_screen_state_instant_replay.dart';
part 'shell_screen_state_integrations.dart';
part 'shell_screen_state_profile_actions.dart';
part 'shell_screen_state_recording.dart';
part 'shell_screen_state_recording_library.dart';
part 'shell_screen_state_search_completion.dart';
part 'shell_screen_state_sessions.dart';
part 'shell_screen_state_shortcuts_status.dart';
part 'shell_screen_state_terminal_layout.dart';
part 'shell_screen_toolbelt.dart';

typedef ShellFileDownloadWriter =
    Future<void> Function(String path, List<int> bytes);
typedef ShellExternalUrlOpener = Future<void> Function(String url);
typedef ShellClock = DateTime Function();
typedef ShellRecordingFilePicker =
    Future<String?> Function({String? initialDirectory});
typedef ShellRecordingPathAction = Future<void> Function(String path);
typedef ShellRecordingTrashAction = Future<bool> Function(String path);
typedef ShellRecordingExportPicker =
    Future<String?> Function(String suggestedName);

final shellAcceptanceProbeProvider = Provider<ShellAcceptanceProbe?>((ref) {
  return null;
});

abstract interface class ShellUserAttentionBridge {
  Future<int?> request(NativeUserAttentionType type);

  Future<void> cancel(int requestId);
}

final class WindowShellUserAttentionBridge implements ShellUserAttentionBridge {
  const WindowShellUserAttentionBridge();

  @override
  Future<int?> request(NativeUserAttentionType type) {
    return WindowBridge.requestUserAttention(type);
  }

  @override
  Future<void> cancel(int requestId) {
    return WindowBridge.cancelUserAttention(requestId);
  }
}

final shellFileDownloadWriterProvider = Provider<ShellFileDownloadWriter>((
  ref,
) {
  return (path, bytes) => File(path).writeAsBytes(bytes, flush: true);
});

final shellExternalUrlOpenerProvider = Provider<ShellExternalUrlOpener>((ref) {
  return WindowBridge.openExternalUrl;
});

final shellUserAttentionBridgeProvider = Provider<ShellUserAttentionBridge>((
  ref,
) {
  return const WindowShellUserAttentionBridge();
});

final shellClockProvider = Provider<ShellClock>((ref) => DateTime.now);

final sshProfileImportServiceProvider = Provider<SshProfileImportService>((
  ref,
) {
  return const NativeSshProfileImportService();
});

final shellRecordingFilePickerProvider = Provider<ShellRecordingFilePicker>((
  ref,
) {
  return WindowBridge.chooseRecordingFile;
});

final shellRecordingRevealProvider = Provider<ShellRecordingPathAction>((ref) {
  return WindowBridge.revealInFinder;
});

final shellRecordingTrashProvider = Provider<ShellRecordingTrashAction>((ref) {
  return WindowBridge.movePathToTrash;
});

final shellRecordingExportPickerProvider = Provider<ShellRecordingExportPicker>(
  (ref) {
    return (suggestedName) =>
        WindowBridge.chooseFileDownloadLocation(suggestedName: suggestedName);
  },
);

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({this.activeDataApiDeployment, super.key});

  final DataApiDeployment? activeDataApiDeployment;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  static const _layoutCueDuration = Duration(milliseconds: 1400);
  static const _viewportResizeDebounce = Duration(milliseconds: 240);
  static const _terminalOverlayPadding = EdgeInsets.fromLTRB(12, 10, 14, 12);
  static const int _pasteHistoryLimit = maxPasteHistoryEntries;
  static const _annotationLimit = 80;
  static const _protocolAnnotationTextRefreshLimit = 16;
  static const _capturedOutputLimit = 80;
  static const _coprocessInputHistoryLimit = 512;
  static const _minimumHorizontalPaneCols = 24;
  static const _minimumVerticalPaneRows = 8;
  static const _paneGrowRatioStep = 0.08;
  static const _minimumSiblingPaneRatio = 0.24;
  static const _paneDividerDragThickness = 8.0;
  static const int _profileTriggerRegexCacheLimit =
      maxTerminalProfileTriggers * 4;
  static const _triggerMatchHistoryLimit = 512;
  static const _activityPreviewMaxCharacters = 512;
  static const _activityNotificationTrailingDelay = Duration(milliseconds: 200);
  static const _osc1337OpenUrlPromptCooldown = Duration(seconds: 5);
  static const _osc1337ReportVariablePromptCooldown = Duration(seconds: 30);
  static const _osc1337SystemAttentionSessionCooldown = Duration(seconds: 2);
  static const _osc1337SystemAttentionGlobalCooldown = Duration(
    milliseconds: 750,
  );
  static const _osc1337FireworksCooldown = Duration(milliseconds: 800);
  static const _osc1337FireworksLifetime = Duration(milliseconds: 420);
  static const _osc1337MaxOutstandingAttentionRequests = 8;

  final Map<String, SelectionController> _selectionControllers = {};
  final Map<String, FocusNode> _terminalFocusNodes = {};
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'shell-search');
  final Map<String, Size> _scheduledViewportSizes = {};
  final Map<String, Size> _committedViewportSizes = {};
  final Map<String, Size> _measuredTerminalCellSizes = {};
  final Map<({String tabId, String sessionId}), GlobalKey>
  _terminalViewportKeys = {};
  final Map<({String tabId, String sessionId}), GlobalKey> _paneDropTargetKeys =
      {};
  final GlobalKey<_ShellTabStripState> _sessionDropTabStripKey =
      GlobalKey<_ShellTabStripState>(
        debugLabel: 'shell-session-drop-tab-strip',
      );
  final Map<String, double> _terminalViewportDevicePixelRatios = {};
  final Map<String, double> _mobileTerminalFontScales = <String, double>{};
  final Map<String, double> _mobileTerminalPinchStartScales =
      <String, double>{};
  final Map<String, terminal.TerminalViewportController>
  _tabColorViewportControllers = {};
  final Map<String, VoidCallback> _tabColorViewportListeners = {};
  final Map<String, Color?> _lastTabColors = {};
  final Set<String> _readOnlySessionIds = {};
  final Map<String, DateTime> _lastActivityNotificationAt = {};
  final Map<String, Timer> _activityNotificationTrailingTimers = {};
  final Map<String, String?> _lastActivityFramePreviews = {};
  final Map<String, String?> _lastNewOutputFramePreviews = {};
  final Map<String, Set<String>> _triggerMatchesBySession = {};
  final Map<String, RegExp?> _profileTriggerRegexCache = {};
  final Map<String, int> _terminalFrameSequenceBySession = {};
  final Map<String, String> _instantReplayRemoteCommands = <String, String>{};
  final Map<String, String> _searchRefreshFrameSignatures = {};
  final TextEditingController _autoComposerController = TextEditingController();
  final FocusNode _autoComposerFocusNode = FocusNode();
  final Set<String> _sessionsSeenForActivityNotifications = {};
  final Set<String> _sessionsSeenForNewOutputBadges = {};
  final Set<String> _sessionsWithNewOutput = {};
  TerminalEventSinkAttachment? _terminalUiEffectAttachment;
  late final LocalTerminalShellUiWiringSnapshot _completionDiagnosticsSnapshot;
  late final Osc72DragDropController _osc72DragDropController;
  late final ShellUserAttentionBridge _userAttentionBridge;
  late final ShellClock _clock;
  late final AppLifecycleListener _appLifecycleListener;
  Timer? _layoutCueTimer;
  final Map<String, Timer> _viewportResizeTimers = {};
  bool _isCommandMenuOpen = false;
  bool _isDefaultsOpen = false;
  bool _isProfilesOpen = false;
  bool _dataApiStartupWarningDismissed = false;
  bool _isSearchOpen = false;
  bool _isAutocompleteOpen = false;
  bool _isAutoComposerOpen = false;
  bool _isCopyModeOpen = false;
  bool _isToolbeltOpen = false;
  bool _isSftpPanelOpen = false;
  String? _sftpPanelSessionId;
  bool _activeTerminalHasFocus = false;
  bool _recentlyClosedLastSession = false;
  bool _showLayoutCue = false;
  bool _showReturningCueOnNextFocus = false;
  _ShellSessionDragData? _sessionDragData;
  Offset? _sessionDragGlobalPosition;
  _ShellPaneDropTarget? _sessionPaneDropTarget;
  bool _sessionDropOverTabStrip = false;
  int? _sessionTabDropInsertionIndex;
  String? _sessionDragFallbackTargetSessionId;
  String _layoutCueTitle = 'Back in shell';
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
  LocalTerminalHostActionsConfig _hostActionsConfig =
      const LocalTerminalHostActionsConfig();
  bool _osc1337OpenUrlPromptActive = false;
  DateTime? _lastOsc1337OpenUrlPromptAt;
  bool _osc1337ReportVariablePromptActive = false;
  DateTime? _lastOsc1337ReportVariablePromptAt;
  final Map<String, int> _osc1337AttentionRequestIds = <String, int>{};
  final Map<String, int> _osc1337AttentionEpochs = <String, int>{};
  final Set<String> _osc1337AttentionRequestsPending = <String>{};
  final Map<String, DateTime> _lastOsc1337SystemAttentionAt =
      <String, DateTime>{};
  DateTime? _lastOsc1337GlobalSystemAttentionAt;
  final Map<String, DateTime> _lastOsc1337FireworksAt = <String, DateTime>{};
  final Map<String, int> _osc1337FireworksSerials = <String, int>{};
  final Map<String, Timer> _osc1337FireworksTimers = <String, Timer>{};
  LocalTerminalBracketedPastePolicy _bracketedPastePolicy =
      LocalTerminalBracketedPastePolicy.auto;
  LocalTerminalPastePolicy _pastePolicy = const LocalTerminalPastePolicy();
  LocalTerminalPasteHistoryPolicy _pasteHistoryPolicy =
      const LocalTerminalPasteHistoryPolicy();
  bool _notificationsBlockedBySystem = false;
  final Set<String> _notificationFailureCodesShown = <String>{};
  int _lastObservedTabCount = 0;
  String? _lastObservedActiveSessionId;
  String? _zoomedPaneSessionId;
  String? _lastRenderableSessionId;
  String _searchQuery = '';
  String? _searchErrorText;
  Map<String, List<terminal.TerminalSearchMatch>> _searchMatchesBySession =
      const {};
  List<_ScopedSearchMatch> _searchHits = const [];
  int _activeSearchIndex = 0;
  int _searchFocusRequestSerial = 0;
  terminal.TerminalSearchMode _searchMode =
      terminal.TerminalSearchMode.smartCaseSubstring;
  _TerminalSearchScope _searchScope = _TerminalSearchScope.activePane;
  String? _lastSearchScopeSessionSignature;
  terminal.TerminalLinkTarget? _hoveredTerminalLink;
  String? _hoveredTerminalLinkSessionId;
  String? _copyModeSessionId;
  SessionOsc52PromptController? _osc52PromptController;
  String? _autocompleteSessionId;
  String _autocompletePrefix = '';
  List<String> _autocompleteSuggestions = const [];
  int _activeAutocompleteIndex = 0;
  String? _autoComposerSessionId;
  List<String> _autoComposerSuggestions = const [];
  int _activeAutoComposerIndex = 0;
  List<PasteHistoryEntry> _pasteHistoryEntries = const [];
  VersionedDocument<PasteHistoryDocument?>? _pasteHistoryDocument;
  Future<VersionedDocument<PasteHistoryDocument?>>? _pasteHistoryLoadFuture;
  Future<void> _pasteHistoryWriteChain = Future<void>.value();
  _InstantReplayLayoutSession? _instantReplayLayoutSession;
  List<_TerminalAnnotation> _annotations = const [];
  bool _recordingLibraryLoading = false;
  bool _recordingSelectionLoading = false;
  String? _recordingLibraryError;
  List<LocalSessionRecordingEntry> _recordingEntries = const [];
  String _recordingSearchQuery = '';
  _RecordingLibrarySort _recordingLibrarySort = _RecordingLibrarySort.newest;
  bool _recordingLibraryPlayableOnly = false;
  LocalSessionRecordingEntry? _selectedRecordingEntry;
  terminal.TerminalRecording? _selectedRecording;
  final GlobalKey<_AnnotationsSheetState> _annotationSheetKey = GlobalKey();
  List<_CapturedOutputEntry> _capturedOutputEntries = const [];
  final GlobalKey<_CapturedOutputSheetState> _capturedOutputSheetKey =
      GlobalKey();
  String? _capturedOutputSheetSessionId;
  Map<String, _ShellCoprocess> _coprocesses = const {};
  bool _pasteHistoryPersistToDisk = false;
  bool _pasteHistoryLoaded = false;
  int _nextAnnotationId = 0;
  bool _annotationSheetOpen = false;
  String? _annotationSheetSessionId;
  int _nextCapturedOutputId = 0;
  final Map<String, _ShellZmodemTransferState> _zmodemTransfers =
      <String, _ShellZmodemTransferState>{};
  final Map<String, terminal.TerminalSessionZmodemEvent> _zmodemRecoveries =
      <String, terminal.TerminalSessionZmodemEvent>{};
  final Set<String> _zmodemAuthorizedTransferIds = <String>{};
  final Set<String> _zmodemTransportFailureSessionIds = <String>{};
  final Map<String, String> _pendingZmodemTerminalMessages = <String, String>{};
  final SshAuthenticationPromptPresenter _sshAuthPromptPresenter =
      SshAuthenticationPromptPresenter();
  final _sshHostKeyPromptPresenter = SshHostKeyPromptPresenter();
  _ShellZmodemPickerRequest? _zmodemPickerRequest;
  int _zmodemPickerRequestSeed = 0;
  final Map<String, Set<String>> _coprocessInputKeysBySession =
      <String, Set<String>>{};
  int? _copyModeAnchorRow;
  int? _copyModeAnchorCol;
  int? _copyModeExtentRow;
  int? _copyModeExtentCol;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(referenceDemoModeProvider)
        ? null
        : ref.read(terminalRuntimeControllerProvider);
    _userAttentionBridge = ref.read(shellUserAttentionBridgeProvider);
    _clock = ref.read(shellClockProvider);
    _osc72DragDropController = Osc72DragDropController(
      sendInput: runtime == null ? (_, _) {} : runtime.sendInput,
    );
    _appLifecycleListener = AppLifecycleListener(
      onPause: () => unawaited(
        ref.read(sessionControllerProvider.notifier).flushLayoutPersistence(),
      ),
      onDetach: () => unawaited(
        ref.read(sessionControllerProvider.notifier).flushLayoutPersistence(),
      ),
      onExitRequested: () async {
        await ref
            .read(sessionControllerProvider.notifier)
            .flushLayoutPersistence();
        return AppExitResponse.exit;
      },
    );
    WindowBridge.setNativeMenuHandlers(
      onPaste: _handleNativePasteMenu,
      onOpenTerminalAtFolder: _openTerminalAtFolderFromPicker,
      onAppAction: _handleNativeAppMenuAction,
      onFind: _handleNativeFindMenu,
      onOsc72DragEvent: _handleNativeOsc72DragEvent,
    );
    _completionDiagnosticsSnapshot =
        LocalTerminalShellUiWiringSnapshot.verified(capturedAt: DateTime.now());
    _osc52PromptController = ref.read(sessionOsc52PromptControllerProvider);
    _osc52PromptController?.setAuthorizationHandler(_confirmOsc52Access);
    if (runtime != null) {
      _terminalUiEffectAttachment = ref
          .read(terminalEventCoordinatorProvider)
          .attachUiSink(_handleTerminalUiEffect);
    }
    ref.listenManual<SessionState>(
      sessionControllerProvider,
      _handleSessionStateChanged,
      fireImmediately: true,
    );
    unawaited(Future<void>.microtask(_loadPasteHistory));
    unawaited(Future<void>.microtask(_loadNotificationPreferences));
  }

  @override
  void dispose() {
    WindowBridge.setNativeMenuHandlers();
    _appLifecycleListener.dispose();
    unawaited(_osc72DragDropController.dispose());
    _osc52PromptController?.clearAuthorizationHandler();
    _terminalUiEffectAttachment?.detach();
    _layoutCueTimer?.cancel();
    for (final timer in _viewportResizeTimers.values) {
      timer.cancel();
    }
    _viewportResizeTimers.clear();
    for (final timer in _activityNotificationTrailingTimers.values) {
      timer.cancel();
    }
    _activityNotificationTrailingTimers.clear();
    for (final timer in _osc1337FireworksTimers.values) {
      timer.cancel();
    }
    _osc1337FireworksTimers.clear();
    unawaited(_cancelAllOsc1337AttentionRequests());
    for (final selectionController in _selectionControllers.values) {
      selectionController.dispose();
    }
    for (final entry in _tabColorViewportControllers.entries) {
      final listener = _tabColorViewportListeners[entry.key];
      if (listener != null) {
        entry.value.removeListener(listener);
      }
    }
    _tabColorViewportControllers.clear();
    _tabColorViewportListeners.clear();
    _lastTabColors.clear();
    for (final focusNode in _terminalFocusNodes.values) {
      focusNode.dispose();
    }
    _searchFocusNode.dispose();
    _autoComposerController.dispose();
    _autoComposerFocusNode.dispose();
    super.dispose();
  }

  void _mutateState(VoidCallback fn) {
    setState(fn);
    _publishAcceptanceSnapshot();
  }

  void _handleSessionStateChanged(SessionState? _, SessionState next) {
    _syncPresentationState(next);
    _publishAcceptanceSnapshot(next);
    final activeSessionId = next.activeSessionId;
    final pendingMessage = activeSessionId == null
        ? null
        : _pendingZmodemTerminalMessages.remove(activeSessionId);
    if (pendingMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(sessionControllerProvider).activeSessionId ==
                activeSessionId) {
          _showShellSnackBar(pendingMessage);
        }
      });
    }
  }

  void _showShellSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  void _showShellPathSnackBar({required String message, required String path}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Reveal',
            onPressed: () => unawaited(_revealShellPath(path)),
          ),
        ),
      );
  }

  Future<void> _revealShellPath(String path) async {
    try {
      if (!await WindowBridge.revealInFinder(path)) {
        _showShellSnackBar('Could not reveal export on this platform');
      }
    } on Object catch (error) {
      _showShellSnackBar('Could not reveal export: $error');
    }
  }

  Future<void> _revealZmodemRecovery(
    terminal.TerminalSessionZmodemEvent event,
  ) async {
    final recoveryKey = '${event.sessionId}:${event.transferId}';
    final runtime = ref.read(terminalRuntimeControllerProvider);
    final resolution = runtime.resolveZmodemRecovery(event);
    switch (resolution.status) {
      case terminal.TerminalZmodemRecoveryResolutionStatus.unavailable:
        _mutateState(() {
          _zmodemRecoveries.remove(recoveryKey);
        });
        _showShellSnackBar('Preserved ZMODEM file is no longer available');
        return;
      case terminal.TerminalZmodemRecoveryResolutionStatus.requestFailed:
        _showShellSnackBar(
          'Could not resolve the preserved ZMODEM file; try again',
        );
        return;
      case terminal.TerminalZmodemRecoveryResolutionStatus.available:
        break;
    }
    final path = resolution.path!;
    try {
      final revealed = await WindowBridge.revealInFinder(path);
      if (!revealed) {
        if (mounted) {
          _showShellSnackBar('Could not reveal preserved ZMODEM file');
        }
        return;
      }
      // Capture the runtime before awaiting. A successful Reveal transfers the
      // path to the user even if this widget was closed in the meantime, so the
      // native lease must still be consumed without touching ref/context.
      final disposition = runtime.consumeZmodemRecovery(event);
      if (!mounted) {
        return;
      }
      if (disposition ==
          terminal.TerminalZmodemRecoveryDisposition.requestFailed) {
        _showShellSnackBar('Could not release the ZMODEM recovery token');
        return;
      }
      _mutateState(() {
        _zmodemRecoveries.remove(recoveryKey);
      });
    } on Object {
      if (mounted) {
        _showShellSnackBar('Could not reveal preserved ZMODEM file');
      }
    }
  }

  void _dismissZmodemRecovery(terminal.TerminalSessionZmodemEvent event) {
    final disposition = ref
        .read(terminalRuntimeControllerProvider)
        .dismissZmodemRecovery(event);
    if (disposition ==
        terminal.TerminalZmodemRecoveryDisposition.requestFailed) {
      _showShellSnackBar('Could not dismiss the ZMODEM recovery notice');
      return;
    }
    _mutateState(() {
      _zmodemRecoveries.remove('${event.sessionId}:${event.transferId}');
    });
  }

  Future<void> _confirmDiscardZmodemRecovery(
    terminal.TerminalSessionZmodemEvent event,
  ) async {
    final filename =
        event.recoverablePartialName ?? 'the preserved ZMODEM file';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permanently discard file?'),
        content: Text(
          '$filename is the only recovery copy retained by Ianvs Terminal. '
          'Discarding it permanently deletes the file and cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('shell-zmodem-recovery-discard-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('shell-zmodem-recovery-discard-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard file'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _dismissZmodemRecovery(event);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(sessionControllerProvider);
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
    final launchPolicy = ref.watch(terminalSessionLaunchPolicyProvider);
    final canOpenNewSession = _canOpenNewSessionLauncher(sessionState);
    final referenceDemoMode = ref.watch(referenceDemoModeProvider);
    final animationsEnabled = ref.watch(shellAnimationsEnabledProvider);
    final dataApiStartupWarning = ref.watch(dataApiStartupWarningProvider);
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
    final displayedPane = displayedSessionId == null
        ? activePane
        : displayedTab?.paneFor(displayedSessionId) ?? activePane;
    final displayedProfile = displayedPane == null
        ? null
        : _profileForPane(displayedPane, sessionState.profiles);
    final shellChromeBackground = displayedProfile == null
        ? activeTab == null
              ? _terminalColorsForProfile(
                  context,
                  defaultProfile,
                ).canvasBackground
              : _tabTerminalBackgroundColor(context, sessionState, activeTab)
        : _terminalColorsForProfile(context, displayedProfile).canvasBackground;
    final instantReplaySession = _instantReplayLayoutSession;
    final instantReplayPane = instantReplaySession == null
        ? null
        : _paneForSession(sessionState, instantReplaySession.sourceSessionId);
    final instantReplayProfile = instantReplayPane == null
        ? null
        : _profileForPane(instantReplayPane, sessionState.profiles);
    final instantReplayConfig = instantReplayProfile?.toSessionConfig();
    final instantReplayColors = _terminalColorsForProfile(
      context,
      instantReplayProfile ?? displayedProfile ?? defaultProfile,
    );
    final recordingReplayProfile = displayedProfile ?? defaultProfile;
    final recordingReplayConfig =
        recordingReplayProfile?.toSessionConfig() ??
        defaultTerminalProfile().toSessionConfig();
    final zmodemTransfer = activeSessionId == null
        ? null
        : _zmodemTransfers[activeSessionId];
    final zmodemRecovery =
        _zmodemRecoveries.values
            .where((event) => event.sessionId == activeSessionId)
            .firstOrNull ??
        _zmodemRecoveries.values.firstOrNull;
    final zmodemRecoverySourceLabel = zmodemRecovery == null
        ? null
        : _zmodemRecoverySourceLabel(zmodemRecovery.sessionId);

    KeyEventResult handleShellShortcut(KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final editor = focusedEditableTextForCurrentRoute();
      if (editor != null) {
        return KeyEventResult.ignored;
      }
      if (_shellModalInputBlocked) return KeyEventResult.handled;
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
          'reopenClosedPane',
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
          'clearBuffer',
          'toggleCommandPalette',
          'toggleHotkeyWindow',
          'openDefaults',
        },
        callbacks: ShellActionProductionCallbacks(
          newTab: (_) {
            if (!canOpenNewSession) {
              return const ShellActionBindingResult.skipped(
                'No terminal session option is available.',
              );
            }
            unawaited(_openNewSessionLauncher(sessionController, sessionState));
            return const ShellActionBindingResult.completed();
          },
          closeTab: (_) {
            if (activeSessionId == null || activeTab == null) {
              return const ShellActionBindingResult.skipped(
                'Close tab requires an active session.',
              );
            }
            _closeTab(sessionController, sessionState, activeTab.sessionId);
            return const ShellActionBindingResult.completed();
          },
          reopenClosedPane: (_) {
            if (!sessionController.canReopenClosedPane) {
              return const ShellActionBindingResult.skipped(
                'No recently closed pane is available for this tab.',
              );
            }
            final reopenedSessionId = sessionController.reopenClosedPane();
            if (reopenedSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'No recently closed pane could be reopened.',
              );
            }
            _syncZoomedPaneForActivation(
              _tabForSession(
                ref.read(sessionControllerProvider),
                reopenedSessionId,
              ),
              reopenedSessionId,
            );
            _focusSession(reopenedSessionId);
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
            final paneManagementBlockedReason = activeTab == null
                ? null
                : _zoomedPaneManagementUnavailableReason(activeTab);
            if (paneManagementBlockedReason != null) {
              return ShellActionBindingResult.skipped(
                paneManagementBlockedReason,
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
            if (!_splitActiveSession(
              sessionController,
              defaultProfile,
              TerminalSplitAxis.horizontal,
            )) {
              return const ShellActionBindingResult.skipped(
                'Split right is unavailable.',
              );
            }
            return const ShellActionBindingResult.completed();
          },
          splitDown: (_) {
            if (defaultProfile == null || activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Split down requires a default profile and active session.',
              );
            }
            final paneManagementBlockedReason = activeTab == null
                ? null
                : _zoomedPaneManagementUnavailableReason(activeTab);
            if (paneManagementBlockedReason != null) {
              return ShellActionBindingResult.skipped(
                paneManagementBlockedReason,
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
            if (!_splitActiveSession(
              sessionController,
              defaultProfile,
              TerminalSplitAxis.vertical,
            )) {
              return const ShellActionBindingResult.skipped(
                'Split down is unavailable.',
              );
            }
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
                'Replay recent activity requires an active session.',
              );
            }
            await _openInstantReplay(sessionState);
            return const ShellActionBindingResult.completed();
          },
          clearBuffer: (_) {
            if (activeSessionId == null) {
              return const ShellActionBindingResult.skipped(
                'Clear buffer requires an active session.',
              );
            }
            final cleared = ref
                .read(terminalRuntimeControllerProvider)
                .clearBuffer(activeSessionId);
            if (!cleared) {
              return const ShellActionBindingResult.skipped(
                'Clear buffer is not supported by this runtime.',
              );
            }
            ref
                .read(sessionControllerProvider.notifier)
                .clearPromptMarks(activeSessionId);
            _showShellSnackBar(
              'Buffer cleared. The current command line was kept.',
            );
            return const ShellActionBindingResult.completed('Cleared buffer.');
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
        case TerminalActionId.openSftpPanel:
          _openSftpPanel(sessionState, activeSessionId);
          return KeyEventResult.handled;
        case TerminalActionId.newTab:
          if (!canOpenNewSession) {
            return KeyEventResult.handled;
          }
          unawaited(_openNewSessionLauncher(sessionController, sessionState));
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
          if (activeSessionId == null || activeTab == null) {
            return KeyEventResult.handled;
          }
          _closeTab(sessionController, sessionState, activeTab.sessionId);
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
                tabStripKey: _sessionDropTabStripKey,
                paneDropInsertionIndex: _sessionTabDropInsertionIndex,
                tabs: sessionState.tabs,
                activeSessionId: activeSessionId,
                tabHasNewOutput: _tabHasNewOutput,
                tabNewOutputTooltip: _tabNewOutputTooltip,
                hiddenTabsNewOutputTooltip: _hiddenTabsNewOutputTooltip,
                hiddenTabsNewOutputPaneSessionId:
                    _hiddenTabsNewOutputPaneSessionId,
                tabNewOutputPaneSessionId: _tabNewOutputPaneSessionId,
                tabColor: (tab) => _tabProfileColor(sessionState, tab),
                referenceDemoMode: referenceDemoMode,
                onNewTab: canOpenNewSession
                    ? () => unawaited(
                        _openNewSessionLauncher(
                          sessionController,
                          sessionState,
                        ),
                      )
                    : null,
                onActivateSession: (sessionId) =>
                    _activateSession(sessionController, sessionId),
                onActivateBadgePane: (sessionId) =>
                    _activateSession(sessionController, sessionId),
                onNotificationInteraction: _handleOscNotificationInteraction,
                onActivateNewOutputPane: (sessionId) =>
                    _activateSession(sessionController, sessionId),
                onCloseSession: (sessionId) =>
                    _closeTab(sessionController, sessionState, sessionId),
                onReorderTab: sessionController.reorderTab,
                onSessionDragStarted: _startSessionDrag,
                onSessionDragUpdated: _updateSessionDrag,
                onSessionDragEnded: (data) =>
                    _finishSessionDrag(sessionController, data),
                onSessionDragCancelled: _cancelSessionDrag,
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
              if (dataApiStartupWarning != null &&
                  !_dataApiStartupWarningDismissed)
                _DataApiStartupWarningBanner(
                  message: dataApiStartupWarning.message,
                  palette: palette,
                  onDismiss: () {
                    setState(() {
                      _dataApiStartupWarningDismissed = true;
                    });
                  },
                ),
              if (sessionState.isReady && sessionState.lastError != null)
                _ShellRuntimeErrorBanner(
                  palette: palette,
                  message: sessionState.lastError!,
                  onDismiss: sessionController.dismissLastError,
                ),
              if (zmodemTransfer != null)
                _ShellZmodemTransferBanner(
                  palette: palette,
                  transfer: zmodemTransfer,
                  onCancel: zmodemTransfer.cancelling
                      ? null
                      : () => _cancelZmodemTransfer(zmodemTransfer),
                  onRetry: zmodemTransfer.canRetry
                      ? () => _retryZmodemOperation(zmodemTransfer)
                      : null,
                ),
              if (zmodemRecovery != null)
                _ShellZmodemRecoveryBanner(
                  palette: palette,
                  filename:
                      zmodemRecovery.recoverablePartialName ??
                      'preserved partial file',
                  sourceLabel: zmodemRecoverySourceLabel!,
                  onReveal: () =>
                      unawaited(_revealZmodemRecovery(zmodemRecovery)),
                  onDiscard: () =>
                      unawaited(_confirmDiscardZmodemRecovery(zmodemRecovery)),
                ),
              Expanded(
                child: _RecordingLibraryLayout(
                  palette: palette,
                  shelfOpen: false,
                  layout: AnimatedSwitcher(
                    duration: animationsEnabled
                        ? const Duration(milliseconds: 160)
                        : Duration.zero,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child:
                        _selectedRecordingEntry != null &&
                            _selectedRecording != null
                        ? _RecordingReplayLayout(
                            key: ValueKey(_selectedRecordingEntry!.path),
                            palette: palette,
                            entry: _selectedRecordingEntry!,
                            recording: _selectedRecording!,
                            delegate: ref.read(ptySessionBackendProvider),
                            sessionConfig: recordingReplayConfig,
                            terminalColors: instantReplayColors,
                            font: recordingReplayConfig.display.font,
                            cursor: recordingReplayConfig.display.cursor,
                            onClose: _closeRecordingReplay,
                          )
                        : instantReplaySession != null
                        ? _InstantReplayLayout(
                            key: const Key('instant-replay-layout'),
                            layout: instantReplaySession,
                            palette: palette,
                            runtime: ref.read(
                              terminalRuntimeControllerProvider,
                            ),
                            terminalColors: instantReplayColors,
                            font:
                                instantReplayConfig?.display.font ??
                                const terminal.TerminalFontConfig(),
                            cursor:
                                instantReplayConfig?.display.cursor ??
                                const terminal.TerminalCursorConfig(),
                            onCopyVisible: _copyInstantReplayVisibleText,
                            onClear: _confirmClearInstantReplayHistory,
                            onExit: _closeInstantReplayLayout,
                          )
                        : !sessionState.isReady ||
                              (activeSessionId != null &&
                                  displayedSessionId == null)
                        ? _ShellStartupSurface(
                            key: const Key('shell-startup-state'),
                            palette: palette,
                            errorMessage: sessionState.isReady
                                ? null
                                : sessionState.lastError,
                            onRetry:
                                !sessionState.isReady &&
                                    sessionState.lastError != null
                                ? sessionController.retryBootstrap
                                : null,
                            onOpenSettings: () => _openDefaultsAndAppearance(
                              sessionController,
                              sessionState,
                            ),
                          )
                        : activeSessionId == null || activeTab == null
                        ? launchPolicy.isSshOnly
                              ? _SshOnlyShellEmptyState(
                                  key: const Key('shell-empty-state'),
                                  palette: palette,
                                  profiles: sessionState.profiles,
                                  onOpenProfile: (profile) => _createSession(
                                    sessionController,
                                    profile,
                                    returningToLayout: true,
                                  ),
                                  onCreateProfile: () => unawaited(
                                    _openSshProfileCreator(
                                      sessionController,
                                      sessionState,
                                    ),
                                  ),
                                )
                              : _ShellEmptyState(
                                  key: const Key('shell-empty-state'),
                                  palette: palette,
                                  title: _emptyStateTitle,
                                  message: _emptyStateMessage,
                                  defaultSummary: defaultSummary,
                                  onNewTab: canOpenNewSession
                                      ? () => unawaited(
                                          _openNewSessionLauncher(
                                            sessionController,
                                            sessionState,
                                          ),
                                        )
                                      : null,
                                )
                        : KeyedSubtree(
                            key: ValueKey(
                              (displayedTab ?? activeTab).sessionId,
                            ),
                            child: _buildSftpSupportingPane(
                              sessionState: sessionState,
                              activeSessionId: activeSessionId,
                              primary: Row(
                                children: [
                                  Expanded(
                                    child: _buildTerminalLayout(
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
                                      capturedOutputEntries:
                                          _capturedOutputForSession(
                                            activeSessionId,
                                          ),
                                      pasteHistoryEntries: _pasteHistoryEntries,
                                      shellIntegration: activeShellIntegration,
                                      promptMarkCount:
                                          _effectivePromptMarksForSession(
                                            activeSessionId,
                                            sessionState: sessionState,
                                          ).length,
                                      tmuxControlModeActive:
                                          _tmuxControlModeActive(
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
                                      onClose: _closeToolbelt,
                                      onOpenCapturedOutput: () =>
                                          _openToolbeltChild(
                                            () => _openCapturedOutput(
                                              activeSessionId,
                                            ),
                                          ),
                                      onOpenPasteHistory: () =>
                                          _openToolbeltChild(
                                            () =>
                                                _openPasteHistory(sessionState),
                                          ),
                                      onOpenShellIntegrationUtilities: () =>
                                          _openToolbeltChild(
                                            () =>
                                                _openShellIntegrationUtilities(
                                                  sessionState,
                                                  activeSessionId,
                                                ),
                                          ),
                                      onInsertCommand: (command) {
                                        _closeToolbelt();
                                        _sendPlainTextToSession(
                                          activeSessionId,
                                          command,
                                        );
                                      },
                                      onChangeDirectory: (directory) {
                                        _closeToolbelt();
                                        _sendPlainTextToSession(
                                          activeSessionId,
                                          'cd ${_shellQuotedPath(directory)}',
                                        );
                                      },
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
                                      onOpenInstantReplay: () =>
                                          _openToolbeltChild(
                                            () => _openInstantReplay(
                                              sessionState,
                                            ),
                                          ),
                                      onOpenPasswordManager: () =>
                                          _openToolbeltChild(
                                            () => _openPasswordManager(
                                              sessionController,
                                              activeSessionId,
                                            ),
                                          ),
                                      showHiddenRedesignEntryPointsForTesting:
                                          ref.watch(
                                            shellHiddenRedesignEntryPointsProvider,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  shelf: _SavedRecordingsShelf(
                    palette: palette,
                    entries: _recordingEntries,
                    selectedPath: _selectedRecordingEntry?.path,
                    searchQuery: _recordingSearchQuery,
                    sort: _recordingLibrarySort,
                    playableOnly: _recordingLibraryPlayableOnly,
                    loading: _recordingLibraryLoading,
                    selectionLoading: _recordingSelectionLoading,
                    error: _recordingLibraryError,
                    onSearchChanged: (value) {
                      _mutateState(() {
                        _recordingSearchQuery = value;
                      });
                    },
                    onSortChanged: (value) {
                      _mutateState(() {
                        _recordingLibrarySort = value;
                      });
                    },
                    onPlayableOnlyChanged: (value) {
                      _mutateState(() {
                        _recordingLibraryPlayableOnly = value;
                      });
                    },
                    onRefresh: () => unawaited(_loadRecordingLibrary()),
                    onImport: () => unawaited(_importRecording()),
                    onSelect: (entry) => unawaited(_selectRecording(entry)),
                    onRename: (entry) => unawaited(_renameRecording(entry)),
                    onReveal: (entry) => unawaited(_revealRecording(entry)),
                    onExport: (entry) => unawaited(_exportRecording(entry)),
                    onDelete: (entry) => unawaited(_deleteRecording(entry)),
                    onClose: () {},
                  ),
                ),
              ),
              if (!referenceDemoMode &&
                  defaultTargetPlatform == TargetPlatform.iOS &&
                  activeSessionId != null)
                _IosTerminalInputBar(
                  key: const Key('ios-terminal-input-bar'),
                  palette: palette,
                  fontScale: _mobileFontScaleFor(activeSessionId),
                  keyboardVisible: MediaQuery.viewInsetsOf(context).bottom > 0,
                  onSendBytes: (bytes) =>
                      _sendMobileTerminalBytes(activeSessionId, bytes),
                  onDecreaseFont: () =>
                      _stepMobileTerminalFont(activeSessionId, -0.1),
                  onIncreaseFont: () =>
                      _stepMobileTerminalFont(activeSessionId, 0.1),
                  onResetFont: () => _resetMobileTerminalFont(activeSessionId),
                  onDismissKeyboard: () =>
                      _dismissMobileTerminalKeyboard(activeSessionId),
                ),
            ],
          ),
        ).withSafeArea,
      ),
    );
  }
}

extension on Widget {
  Widget get withSafeArea => SafeArea(child: this);
}
