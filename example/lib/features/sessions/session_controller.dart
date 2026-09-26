import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;
import 'dart:io' show File, FileMode, IOSink, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/configuration/data_api_configuration_providers.dart';
import '../../platform/app_shutdown_coordinator.dart';
import '../config/local_terminal_config_bootstrap.dart';
import '../config/local_terminal_config_loader.dart';
import '../config/local_terminal_config_models.dart';
import '../config/local_terminal_config_repository.dart';
import '../layout/local_session_layout_codec.dart';
import '../layout/local_terminal_layout_models.dart';
import '../layout/local_terminal_layout_repository.dart';
import '../persistence/versioned_document.dart';
import '../preferences/app_preferences_models.dart';
import '../preferences/app_preferences_repository.dart';
import '../profiles/profile_models.dart';
import '../profiles/profile_repository.dart';
import '../pty/pty.dart';
import '../recording/recording_retention_maintenance.dart';
import '../recording/sampled_recording_library.dart';
import '../ssh/ssh_feature_access.dart';
import '../terminal/terminal.dart' hide TerminalEmulation;
import 'session_bootstrap.dart';
import 'session_ports.dart';
import 'session_shutdown.dart';
import 'session_state.dart';
import 'terminal_event_coordinator.dart';
import 'terminal_session_launch_policy.dart';

const Object _recordingLastErrorNoChange = Object();

final ptySessionBackendProvider = Provider<PtySessionBackend>((ref) {
  if (ref.watch(sessionDemoFixtureProvider) != null) {
    return ReferenceDemoPtySessionBackend();
  }
  throw StateError(
    'The PTY backend must be supplied by the ready application runtime graph.',
  );
});

final Provider<TerminalPreCloseSignalRelay>
terminalPreCloseSignalRelayProvider = Provider<TerminalPreCloseSignalRelay>(
  (ref) => TerminalPreCloseSignalRelay(),
);

final terminalGraphicsTraceSinkProvider = Provider<TerminalBenchmarkEventSink?>(
  (ref) {
    const dartDefinePath = String.fromEnvironment(
      'IANVS_TERMINAL_GRAPHICS_TRACE',
    );
    final path = dartDefinePath.isNotEmpty
        ? dartDefinePath
        : Platform.environment['IANVS_TERMINAL_GRAPHICS_TRACE'];
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final output = File(path.trim());
    output.parent.createSync(recursive: true);
    final sink = output.openWrite(mode: FileMode.write);
    ref.onDispose(() {
      unawaited(sink.close());
    });
    _writeTerminalTraceEvent(sink, <String, Object?>{
      'schema_version': 'ianvs-terminal-graphics-trace-meta-v1',
      'timestamp_micros': DateTime.now().microsecondsSinceEpoch,
      'event': 'trace_start',
      'path': output.path,
    });
    return (event) => _writeTerminalTraceEvent(sink, event);
  },
);

final sessionCommandClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final Provider<TerminalRuntimeController>
terminalRuntimeControllerProvider = Provider<TerminalRuntimeController>((ref) {
  const osc52PromptPreviewRunes = 120;

  ({
    int byteCount,
    int characterCount,
    String textPreview,
    bool textPreviewTruncated,
  })
  clipboardPromptSummary(String text) {
    final runes = text.runes.toList(growable: false);
    return (
      byteCount: utf8.encode(text).length,
      characterCount: runes.length,
      textPreview: String.fromCharCodes(runes.take(osc52PromptPreviewRunes)),
      textPreviewTruncated: runes.length > osc52PromptPreviewRunes,
    );
  }

  Future<SessionOsc52PromptRequest> promptRequestFor(
    TerminalClipboardAccessRequest request,
  ) async {
    if (request.operation == TerminalClipboardOperation.pasteRequest &&
        request.textPreview == null &&
        request.resolveText != null) {
      try {
        final clipboardText = await request.resolveText!();
        final summary = clipboardPromptSummary(clipboardText);
        return SessionOsc52PromptRequest(
          operation: request.operation,
          sessionId: request.sessionId,
          selection: request.selection,
          byteCount: summary.byteCount,
          characterCount: summary.characterCount,
          textPreview: summary.textPreview,
          textPreviewTruncated: summary.textPreviewTruncated,
        );
      } on Object {
        return SessionOsc52PromptRequest.fromAccessRequest(request);
      }
    }
    return SessionOsc52PromptRequest.fromAccessRequest(request);
  }

  Future<bool> osc52ClipboardAccessAllowed(
    TerminalClipboardAccessRequest request,
  ) async {
    try {
      final config = await ref.read(localTerminalConfigLoaderProvider).load();
      return switch (config.config.clipboard.osc52) {
        LocalTerminalOsc52Policy.disabled => false,
        LocalTerminalOsc52Policy.ask =>
          await ref
              .read(sessionOsc52PromptControllerProvider)
              .request(await promptRequestFor(request)),
        LocalTerminalOsc52Policy.profile =>
          !(request.operation == TerminalClipboardOperation.pasteRequest ||
                  request.operation == TerminalClipboardOperation.mimeRead) ||
              await ref
                  .read(sessionOsc52PromptControllerProvider)
                  .request(await promptRequestFor(request)),
        LocalTerminalOsc52Policy.allow => true,
      };
    } on Object {
      return false;
    }
  }

  Future<TerminalClipboardAuthorization> osc5522ClipboardAccessAuthorized(
    TerminalClipboardAccessRequest request,
  ) async {
    try {
      final config = await ref.read(localTerminalConfigLoaderProvider).load();
      return switch (config.config.clipboard.osc52) {
        LocalTerminalOsc52Policy.disabled =>
          TerminalClipboardAuthorization.denied,
        LocalTerminalOsc52Policy.ask =>
          await ref
              .read(sessionOsc52PromptControllerProvider)
              .authorize(await promptRequestFor(request)),
        LocalTerminalOsc52Policy.profile =>
          request.operation == TerminalClipboardOperation.mimeRead
              ? await ref
                    .read(sessionOsc52PromptControllerProvider)
                    .authorize(await promptRequestFor(request))
              : TerminalClipboardAuthorization.allowOnce,
        LocalTerminalOsc52Policy.allow =>
          TerminalClipboardAuthorization.allowOnce,
      };
    } on Object {
      return TerminalClipboardAuthorization.denied;
    }
  }

  final preCloseSignalRelay = ref.watch(terminalPreCloseSignalRelayProvider);
  final controller = TerminalRuntimeController(
    backend: ref.read(ptySessionBackendProvider),
    copyToClipboard: ref.read(sessionClipboardCopyProvider),
    writeTextClipboard: ref.read(sessionClipboardTextWriteProvider),
    readClipboard: ref.read(sessionClipboardPasteProvider),
    writeMimeClipboard: ref.read(sessionClipboardMimeWriteProvider),
    readMimeClipboard: ref.read(sessionClipboardMimeReadProvider),
    listClipboardMimeTypes: ref.read(sessionClipboardMimeTypeListProvider),
    authorizeMimeClipboardAccessWithContext: osc5522ClipboardAccessAuthorized,
    allowClipboardCopyWithContext: osc52ClipboardAccessAllowed,
    allowClipboardPasteRequestWithContext: osc52ClipboardAccessAllowed,
    resizeWindowBy: ref.read(sessionWindowResizeProvider),
    enableSessionPolling: ref.read(sessionPollingEnabledProvider),
    enableWarmUpRefresh: ref.read(driverWarmUpRefreshEnabledProvider),
    benchmarkEventSink: ref.watch(terminalGraphicsTraceSinkProvider),
    beforeSessionCloseOnExitSignal: preCloseSignalRelay.add,
  );
  final shutdownCoordinator = ref.read(appShutdownCoordinatorProvider);
  const shutdownTaskName = 'terminal-runtime-provider';
  shutdownCoordinator.registerTask(
    shutdownTaskName,
    () async => controller.dispose(),
    phase: AppShutdownPhase.infrastructure,
  );
  ref.onDispose(() {
    if (!shutdownCoordinator.hasStarted) {
      // ProviderScope disposal order is not a lifecycle contract. Whichever
      // Ready-graph provider is released first starts the same idempotent,
      // ordered shutdown while all registered application tasks still exist.
      // Provider teardown has no caller that can consume a bounded result.
      // Start the same settlement without allocating a timeout timer that can
      // outlive a Flutter test frame; native/app lifecycle callers still use
      // the coordinator's bounded shutdown response.
      unawaited(shutdownCoordinator.shutdown(bounded: false));
    }
  });
  return controller;
});

final Provider<TerminalEventCoordinator> terminalEventCoordinatorProvider =
    Provider<TerminalEventCoordinator>((ref) {
      final coordinator = TerminalEventCoordinator(
        signals: ref.watch(terminalRuntimeControllerProvider).runtimeSignals,
      );
      final preCloseAttachment = ref
          .watch(terminalPreCloseSignalRelayProvider)
          .attach(coordinator.handlePreClose);
      ref.onDispose(() {
        preCloseAttachment.detach();
        unawaited(coordinator.beginShutdown());
      });
      return coordinator;
    });

void _writeTerminalTraceEvent(IOSink sink, Map<String, Object?> event) {
  try {
    sink.writeln(jsonEncode(event));
  } on Object {
    // Diagnostics must never affect terminal rendering.
  }
}

final profileRepositoryProvider = Provider<ProfileRepositoryPort>((ref) {
  return ProfileRepository();
});

final appPreferencesRepositoryProvider = Provider<AppPreferencesRepositoryPort>(
  (ref) {
    return AppPreferencesRepository();
  },
);

final localTerminalConfigRepositoryProvider =
    Provider<TerminalConfigRepository>((ref) {
      return LocalTerminalConfigRepository();
    });

final localTerminalConfigLoaderProvider = Provider<LocalTerminalConfigLoader>((
  ref,
) {
  return LocalTerminalConfigLoader(
    localConfigRepository: ref.read(localTerminalConfigRepositoryProvider),
  );
});

final localTerminalLayoutRepositoryProvider =
    Provider<TerminalLayoutRepository>((ref) {
      return LocalTerminalLayoutRepository();
    });

typedef TerminalLayoutRetryDelay = Duration Function(int attempt);

final terminalLayoutRetryDelayProvider = Provider<TerminalLayoutRetryDelay>(
  (ref) =>
      (attempt) => switch (attempt) {
        0 => const Duration(seconds: 2),
        1 => const Duration(seconds: 5),
        2 => const Duration(seconds: 15),
        _ => const Duration(seconds: 30),
      },
);

final sampledRecordingFileApiProvider = Provider<NativeRecordingFileApi>((ref) {
  final api = NativeRecordingFileApi();
  ref.onDispose(api.dispose);
  return api;
});

final sampledRecordingLibraryProvider = Provider<SampledRecordingLibrary>(
  (ref) =>
      SampledRecordingLibrary(files: ref.read(sampledRecordingFileApiProvider)),
);
final sampledRecordingCaptureClientProvider =
    Provider<SampledRecordingCaptureClient?>((ref) {
      final backend = ref.read(ptySessionBackendProvider);
      if (backend is PtyRuntimeCapabilityBackend) {
        final capabilities =
            (backend as PtyRuntimeCapabilityBackend).runtimeCapabilities;
        if (capabilities?.supports(ptyRuntimeFeatureSessionRecordingV2) !=
                true ||
            capabilities?.recordingSchemaVersions.contains(2) != true) {
          return null;
        }
      }
      return backend is PtySessionRequestV1Backend
          ? SampledRecordingCaptureClient(
              backend: backend as PtySessionRequestV1Backend,
            )
          : null;
    });

final sessionBootstrapServiceProvider = Provider<SessionBootstrapService>((
  ref,
) {
  final localConfigRepository = ref.read(localTerminalConfigRepositoryProvider);
  return SessionBootstrapService(
    profileRepository: ref.read(profileRepositoryProvider),
    localConfigRepository: localConfigRepository,
    localConfigLoader: ref.read(localTerminalConfigLoaderProvider),
  );
});

final sessionPollingEnabledProvider = Provider<bool>((ref) => true);
final driverWarmUpRefreshEnabledProvider = Provider<bool>((ref) => false);
final sessionOsc52PromptControllerProvider =
    Provider<SessionOsc52PromptController>((ref) {
      return SessionOsc52PromptController();
    });
final sessionEnvironmentOverridesProvider = Provider<Map<String, String>>((
  ref,
) {
  return const <String, String>{};
});

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionOsc52PromptRequest {
  const SessionOsc52PromptRequest({
    required this.operation,
    this.sessionId,
    this.selection,
    this.byteCount,
    this.characterCount,
    this.textPreview,
    this.textPreviewTruncated = false,
    this.protocol = 'osc52',
    this.mimeTypes = const <String>[],
    this.applicationName,
    this.canRememberPassword = false,
  });

  factory SessionOsc52PromptRequest.fromAccessRequest(
    TerminalClipboardAccessRequest request,
  ) {
    return SessionOsc52PromptRequest(
      operation: request.operation,
      sessionId: request.sessionId,
      selection: request.selection,
      byteCount: request.byteCount,
      characterCount: request.characterCount,
      textPreview: request.textPreview,
      textPreviewTruncated: request.textPreviewTruncated,
      protocol: request.protocol,
      mimeTypes: request.mimeTypes,
      applicationName: request.applicationName,
      canRememberPassword: request.canRememberPassword,
    );
  }

  final TerminalClipboardOperation operation;
  final String? sessionId;
  final String? selection;
  final int? byteCount;
  final int? characterCount;
  final String? textPreview;
  final bool textPreviewTruncated;
  final String protocol;
  final List<String> mimeTypes;
  final String? applicationName;
  final bool canRememberPassword;
}

typedef SessionOsc52PromptHandler =
    Future<bool> Function(SessionOsc52PromptRequest request);
typedef SessionOsc52AuthorizationPromptHandler =
    Future<TerminalClipboardAuthorization> Function(
      SessionOsc52PromptRequest request,
    );

class SessionOsc52PromptController {
  SessionOsc52PromptHandler? _handler;
  SessionOsc52AuthorizationPromptHandler? _authorizationHandler;

  void setHandler(SessionOsc52PromptHandler handler) {
    _handler = handler;
  }

  void clearHandler() {
    _handler = null;
  }

  void setAuthorizationHandler(SessionOsc52AuthorizationPromptHandler handler) {
    _authorizationHandler = handler;
  }

  void clearAuthorizationHandler() {
    _authorizationHandler = null;
  }

  Future<bool> request(SessionOsc52PromptRequest request) async {
    final handler = _handler;
    if (handler != null) {
      return handler(request);
    }
    final authorizationHandler = _authorizationHandler;
    if (authorizationHandler != null) {
      return (await authorizationHandler(request)).allowed;
    }
    return false;
  }

  Future<TerminalClipboardAuthorization> authorize(
    SessionOsc52PromptRequest request,
  ) async {
    final handler = _authorizationHandler;
    if (handler != null) {
      return handler(request);
    }
    return await this.request(request)
        ? TerminalClipboardAuthorization.allowOnce
        : TerminalClipboardAuthorization.denied;
  }
}

class _AutomaticProfileBaseline {
  const _AutomaticProfileBaseline({
    required this.title,
    required this.profileId,
    required this.profileSnapshot,
  });

  final String title;
  final String profileId;
  final TerminalProfile? profileSnapshot;
}

class SessionController extends Notifier<SessionState> {
  final Map<String, Map<String, TerminalShellIntegrationSnapshot>>
  _shellContexts = {};
  static const _layoutPersistenceDebounce = Duration(milliseconds: 60);

  final SessionBootstrapRunner _bootstrapRunner = SessionBootstrapRunner();
  final Map<String, TerminalViewportController> _demoViewports =
      <String, TerminalViewportController>{};
  final Map<String, _AutomaticProfileBaseline> _automaticProfileBaselines =
      <String, _AutomaticProfileBaseline>{};
  final Map<String, Timer> _progressGraceTimers = <String, Timer>{};
  final Map<String, Timer> _notificationExpiryTimers = <String, Timer>{};
  final Map<String, ({int order, TerminalSessionProgressEvent event})>
  _pendingProgressEvents =
      <String, ({int order, TerminalSessionProgressEvent event})>{};
  final List<TerminalTab> _recentlyClosedTabs = <TerminalTab>[];
  final Map<String, List<TerminalPane>> _recentlyClosedPanesByTab =
      <String, List<TerminalPane>>{};
  final Map<String, SampledRecordingClaim> _recordingClaims = {};
  final Map<String, Future<bool>> _recordingStarts = {};
  final Map<String, TerminalSessionExitClaim> _recordingExitClaims = {};
  Timer? _recordingTimer;
  RecordingRetentionMaintenance? _recordingMaintenance;
  bool _recordingPollRunning = false;
  Future<void>? _bootstrapFuture;
  Future<void>? _recordingShutdownFuture;
  Future<void>? _sessionShutdownFuture;
  VersionedDocument<TerminalProfilesDocument> _profileDocument =
      const VersionedDocument<TerminalProfilesDocument>.local(
        TerminalProfilesDocument(profiles: <TerminalProfile>[]),
      );
  VersionedDocument<TerminalAppPreferencesDocument> _appPreferencesDocument =
      const VersionedDocument<TerminalAppPreferencesDocument>.local(
        TerminalAppPreferencesDocument(),
      );
  VersionedDocument<LocalTerminalConfigDocument> _localConfigVersioned =
      const VersionedDocument<LocalTerminalConfigDocument>.local(
        LocalTerminalConfigDocument(),
      );
  VersionedDocument<TerminalLayout?> _layoutDocument =
      const VersionedDocument<TerminalLayout?>.local(null);
  LocalTerminalConfigBootstrapSource _configBootstrapSource =
      LocalTerminalConfigBootstrapSource.defaults;
  bool _preferencesLoadedFromDisk = false;
  TerminalEventSinkAttachment? _runtimeEventAttachment;
  final Map<String, bool> _runtimeSessionActivation = <String, bool>{};
  bool _progressFlushScheduled = false;
  int _progressEventOrder = 0;
  bool _layoutPersistenceEnabled = false;
  bool _layoutPersistenceBlocked = false;
  Timer? _layoutPersistenceTimer;
  Timer? _layoutRetryTimer;
  int _layoutRetryAttempt = 0;
  String? _lastLayoutSnapshot;
  Future<void> _layoutSaveChain = Future<void>.value();
  bool _isShuttingDown = false;
  bool _terminalConfigRepairAvailable = false;
  ({String profileId, String message})? _lastSshExitFailure;

  TerminalAppPreferencesDocument get _appPreferences =>
      _appPreferencesDocument.value;

  set _appPreferences(TerminalAppPreferencesDocument value) {
    _appPreferencesDocument = _appPreferencesDocument.withValue(value);
  }

  LocalTerminalConfigDocument get _localConfigDocument =>
      _localConfigVersioned.value;

  set _localConfigDocument(LocalTerminalConfigDocument value) {
    _localConfigVersioned = _localConfigVersioned.withValue(value);
  }

  @protected
  String? get bootstrapDefaultProfileIdOverride => null;

  TerminalRuntimeController get _runtime =>
      ref.read(terminalRuntimeControllerProvider);

  bool get canReopenClosedTab => _recentlyClosedTabs.isNotEmpty;

  bool get canReopenClosedPane {
    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      return false;
    }
    final tabIndex = _tabIndexContainingSession(activeSessionId);
    if (tabIndex == -1) {
      return false;
    }
    return _recentlyClosedPanesByTab[state.tabs[tabIndex].sessionId]
            ?.isNotEmpty ??
        false;
  }

  bool get isShuttingDown => _isShuttingDown;

  bool get terminalConfigRepairAvailable => _terminalConfigRepairAvailable;

  @visibleForTesting
  bool get hasRuntimeEventSubscriptionForTesting =>
      _runtimeEventAttachment != null;

  bool get _bootstrapWorkAllowed => ref.mounted && !_isShuttingDown;

  void _setWindowTitle(String title) {
    unawaited(ref.read(sessionWindowTitleWriterProvider)(title));
  }

  void _publishTerminalContent({
    required bool terminalHasVisibleContent,
    required String? terminalPreview,
  }) {
    ref.read(sessionTerminalContentPublisherProvider)(
      terminalHasVisibleContent: terminalHasVisibleContent,
      terminalPreview: terminalPreview,
    );
  }

  @override
  SessionState build() {
    listenSelf(_handleLayoutStateChanged);
    _ensureRuntimeSubscription();
    _scheduleBootstrap();
    final liveRecorder = ref.read(sessionDemoFixtureProvider) == null
        ? ref.read(sampledRecordingCaptureClientProvider)
        : null;
    final recordingRepository = ref.read(sampledRecordingLibraryProvider);
    final layoutRepository = ref.read(localTerminalLayoutRepositoryProvider);
    final terminalRuntime = ref.read(terminalRuntimeControllerProvider);
    final terminalEventCoordinator = ref.read(terminalEventCoordinatorProvider);
    final shutdownCoordinator = ref.read(appShutdownCoordinatorProvider);
    const shutdownTaskName = 'session-runtime';
    shutdownCoordinator.registerTask(
      shutdownTaskName,
      () => _shutdownSessions(
        liveRecorder,
        recordingRepository,
        layoutRepository,
        terminalRuntime,
        terminalEventCoordinator,
      ),
    );
    ref.onDispose(() {
      if (!shutdownCoordinator.hasStarted) {
        // A Ready ProviderScope can be removed before its Host State disposes.
        // Start the shared graph owner instead of discarding recordings or
        // bypassing application-phase layout/recording finalization.
        // See the runtime provider above: Riverpod teardown starts the shared
        // ordered settlement, while the stable app owner remains responsible
        // for the bounded native shutdown response.
        unawaited(shutdownCoordinator.shutdown(bounded: false));
      }
      _layoutPersistenceTimer?.cancel();
      _layoutRetryTimer?.cancel();
      unawaited(_recordingMaintenance?.stop());
      _runtimeEventAttachment?.detach();
      for (final timer in _progressGraceTimers.values) {
        timer.cancel();
      }
      _progressGraceTimers.clear();
      for (final timer in _notificationExpiryTimers.values) {
        timer.cancel();
      }
      _notificationExpiryTimers.clear();
      _pendingProgressEvents.clear();
      for (final controller in _demoViewports.values) {
        controller.dispose();
      }
    });
    return SessionState.initial();
  }

  Future<void> retryBootstrap() async {
    if (_isShuttingDown || state.isReady) {
      return;
    }
    _scheduleBootstrap();
    await _bootstrapFuture!;
  }

  Future<void> repairTerminalConfigAndRetry() async {
    if (_isShuttingDown || state.isReady || !_terminalConfigRepairAvailable) {
      return;
    }
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    if (repository is! TerminalConfigRecoveryRepository) {
      throw StateError(
        'The active terminal config repository does not support recovery.',
      );
    }
    final recoveryRepository = repository as TerminalConfigRecoveryRepository;
    _terminalConfigRepairAvailable = false;
    try {
      await recoveryRepository.repairNonCanonicalCurrentDocument();
    } on Object {
      _terminalConfigRepairAvailable = true;
      rethrow;
    }
    await retryBootstrap();
  }

  void _scheduleBootstrap() {
    if (_bootstrapFuture != null) {
      return;
    }
    late final Future<void> attempt;
    attempt = Future<void>.microtask(() async {
      try {
        await _runBootstrap();
      } finally {
        if (identical(_bootstrapFuture, attempt)) {
          _bootstrapFuture = null;
        }
      }
    });
    _bootstrapFuture = attempt;
  }

  Future<void> _runBootstrap() async {
    final outcome = await _bootstrapRunner.run(
      isMounted: () => _bootstrapWorkAllowed,
      onStarted: () {
        _terminalConfigRepairAvailable = false;
        state = state.copyWith(isReady: false, lastError: null);
      },
      operation: _bootstrap,
      onFailed: (error, _) {
        _terminalConfigRepairAvailable =
            error is NonCanonicalCurrentTerminalConfigException;
        state = state.copyWith(
          isReady: false,
          lastError: 'Terminal startup failed: $error',
        );
      },
    );
    if (outcome case SessionBootstrapFailure(
      :final error,
      :final stackTrace,
      reportedToMountedConsumer: false,
    )) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  TerminalViewportController viewportFor(String sessionId) {
    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      return _demoViewportFor(sessionId, demoFixture);
    }
    return _runtime.viewportFor(sessionId);
  }

  TerminalViewportController? existingViewportFor(String sessionId) {
    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      return _demoViewports[sessionId];
    }
    return _runtime.existingViewportFor(sessionId);
  }

  TerminalGraphicsCache? graphicsCacheFor(String sessionId) {
    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      return null;
    }
    return _runtime.graphicsCacheFor(sessionId);
  }

  TerminalViewportController _demoViewportFor(
    String sessionId,
    SessionDemoFixture fixture,
  ) {
    return _demoViewports.putIfAbsent(sessionId, () {
      final controller = TerminalViewportController();
      final frame = fixture.frameFor(sessionId);
      if (frame != null) {
        controller.updateFrame(frame);
      }
      return controller;
    });
  }

  Future<void> _bootstrap() async {
    _layoutPersistenceBlocked = false;
    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      for (final tab in demoFixture.tabs) {
        for (final pane in tab.effectivePanes) {
          final frame = demoFixture.frameFor(pane.sessionId);
          if (frame == null) {
            continue;
          }
          _demoViewports
              .putIfAbsent(pane.sessionId, TerminalViewportController.new)
              .updateFrame(frame);
        }
      }
      state = state.copyWith(
        profiles: demoFixture.profiles,
        tabs: demoFixture.tabs,
        activeSessionId: demoFixture.activeSessionId,
        defaultProfileId: demoFixture.defaultProfileId,
        themeMode: demoFixture.themeMode,
        isReady: true,
      );
      _publishDemoContent(demoFixture, demoFixture.activeSessionId);
      return;
    }

    String? recordingRecoveryError;
    try {
      final recordingLibrary = ref.read(sampledRecordingLibraryProvider);
      final recovery = await recordingLibrary.recover();
      await recordingLibrary.applyRetention();
      if (recovery.errors.isNotEmpty) {
        recordingRecoveryError =
            'Recording recovery found ${recovery.errors.length} unavailable recording(s): ${recovery.errors.first}';
      }
    } on MissingPluginException {
      if (!_bootstrapWorkAllowed) {
        return;
      }
      // Platform persistence is unavailable in unit/widget hosts.
    } on Object catch (error) {
      if (!_bootstrapWorkAllowed) {
        return;
      }
      recordingRecoveryError =
          'Recording recovery failed: '
          '${_boundedShellMetadata(error.toString(), 240)}';
    }
    if (!_bootstrapWorkAllowed) {
      return;
    }

    _ensureRuntimeSubscription();
    final preparation = await ref
        .read(sessionBootstrapServiceProvider)
        .prepare(explicitDefaultProfileId: bootstrapDefaultProfileIdOverride);
    if (!_bootstrapWorkAllowed) {
      return;
    }
    final launchPolicy = ref.read(terminalSessionLaunchPolicyProvider);
    final runtimeProfiles = launchPolicy.visibleProfiles(preparation.profiles);
    _profileDocument = preparation.profileDocument;
    _configBootstrapSource = preparation.configSource;
    _localConfigVersioned = preparation.localConfigDocument;
    _preferencesLoadedFromDisk = preparation.preferencesLoadedFromDisk;
    _appPreferencesDocument = preparation.appPreferencesDocument;
    final effectiveDefaultProfileId = _effectiveDefaultProfileIdFor(
      runtimeProfiles,
      preferredProfileId: preparation.effectiveDefaultProfileId,
    );
    final runtimeProfileIds = runtimeProfiles
        .map((profile) => profile.id)
        .toSet();
    var initialTabs = <TerminalTab>[];
    String? initialSessionId;
    String? layoutRestoreError;
    final canHaveSavedLayout =
        _configBootstrapSource != LocalTerminalConfigBootstrapSource.defaults;
    if (_localConfigDocument.layout.restoreLayout) {
      try {
        final layoutDocument = await ref
            .read(localTerminalLayoutRepositoryProvider)
            .loadVersioned();
        if (!_bootstrapWorkAllowed) {
          return;
        }
        _layoutDocument = layoutDocument;
        final layout = _layoutDocument.value;
        if (canHaveSavedLayout && layout != null && !layout.isEmpty) {
          final restored = _restoreTerminalLayout(
            layout,
            profiles: runtimeProfiles,
          );
          initialTabs = restored.tabs;
          initialSessionId = restored.activeSessionId;
          if (restored.failures.isNotEmpty) {
            _layoutPersistenceBlocked = true;
            layoutRestoreError = _layoutRestoreFailureMessage(
              restored.failures,
            );
          }
        }
      } on MissingPluginException {
        if (!_bootstrapWorkAllowed) {
          return;
        }
        // Platform persistence is unavailable in unit/widget hosts.
        _layoutPersistenceBlocked = true;
      } on Object catch (error) {
        if (!_bootstrapWorkAllowed) {
          return;
        }
        _layoutPersistenceBlocked = true;
        layoutRestoreError =
            'Terminal layout could not be loaded: '
            '${_boundedShellMetadata(error.toString(), 240)}';
      }
    }
    if (!_bootstrapWorkAllowed) {
      return;
    }

    if (initialTabs.isEmpty &&
        effectiveDefaultProfileId != null &&
        launchPolicy.opensDefaultSessionOnEmptyLayout) {
      final initialProfile = runtimeProfiles.firstWhere(
        (profile) => profile.id == effectiveDefaultProfileId,
        orElse: () => runtimeProfiles.first,
      );
      final environmentOverrides = ref.read(
        sessionEnvironmentOverridesProvider,
      );
      final initialLaunchProfile = _profileWithSessionEnvironment(
        initialProfile,
        environmentOverrides,
      );
      initialSessionId = _createRuntimeSession(initialLaunchProfile);
      if (initialSessionId != null) {
        final descriptor = _relaunchSpecForLaunch(
          profileId: initialProfile.id,
          launchProfile: initialLaunchProfile,
        );
        initialTabs = <TerminalTab>[
          TerminalTab(
            sessionId: initialSessionId,
            title: initialLaunchProfile.name,
            profileId: initialProfile.id,
            profileSnapshot: initialLaunchProfile,
            relaunchSpec: descriptor,
          ),
        ];
      }
    }

    state = state.copyWith(
      profiles: runtimeProfiles,
      tabs: initialTabs.isEmpty ? state.tabs : initialTabs,
      activeSessionId: initialSessionId,
      defaultProfileId: effectiveDefaultProfileId,
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
      configurationWarnings: preparation.configurationWarnings
          .where((warning) => runtimeProfileIds.contains(warning.profileId))
          .toList(growable: false),
      themeMode: _appPreferences.appearance.themeMode,
      languageMode: _appPreferences.appearance.languageMode,
      terminalViewportPadding:
          _appPreferences.appearance.terminalViewportPadding,
      isReady: true,
      lastError:
          layoutRestoreError ?? recordingRecoveryError ?? state.lastError,
    );
    _recordingMaintenance ??= RecordingRetentionMaintenance(
      run: ref.read(sampledRecordingLibraryProvider).applyRetention,
      onError: (error) {
        if (ref.mounted && !_isShuttingDown) {
          state = state.copyWith(
            lastError: _recordingError('Recording cleanup failed', error),
          );
        }
      },
    );
    _recordingMaintenance!.start();
    _syncRuntimeSessionActivation();
    final activePane = initialSessionId == null
        ? null
        : _paneForSession(initialSessionId);
    if (activePane != null) {
      _setWindowTitle(activePane.title);
    }
    _enableLayoutPersistence();
    _refreshRemoteFallbackSnapshot();
  }

  void _refreshRemoteFallbackSnapshot() {
    final controller = ref.read(dataApiRemoteFallbackControllerProvider);
    if (controller == null) {
      return;
    }
    unawaited(() async {
      try {
        await controller.refreshSnapshot();
      } on Object catch (error, stackTrace) {
        // A failed refresh must not affect the live remote session or replace
        // the prior last-known-good checkpoint.
        debugPrint(
          'Remote fallback snapshot refresh failed: $error\n$stackTrace',
        );
      }
    }());
  }

  LocalTerminalLayoutRestoreResult _restoreTerminalLayout(
    TerminalLayout layout, {
    required List<TerminalProfile> profiles,
  }) {
    final profilesById = <String, TerminalProfile>{
      for (final profile in profiles) profile.id: profile,
    };
    final environmentOverrides = ref.read(sessionEnvironmentOverridesProvider);
    return LocalSessionLayoutCodec.restore(
      layout,
      relaunch: (descriptor) {
        final profile = profilesById[descriptor.profileId];
        if (profile == null) {
          return null;
        }
        var descriptorProfile = profile;
        if (descriptor.cwd != null) {
          descriptorProfile = descriptorProfile.copyWith(cwd: descriptor.cwd);
        }
        var launchProfile = _profileWithSessionEnvironment(
          descriptorProfile,
          environmentOverrides,
        );
        var sessionId = _createRuntimeSession(launchProfile);
        if (sessionId == null && descriptor.cwd != null) {
          launchProfile = _profileWithSessionEnvironment(
            profile,
            environmentOverrides,
          );
          sessionId = _createRuntimeSession(launchProfile);
        }
        if (sessionId == null) {
          return null;
        }
        final title = launchProfile.name;
        return TerminalPane(
          sessionId: sessionId,
          title: title,
          profileId: profile.id,
          profileSnapshot: launchProfile,
          relaunchSpec: _relaunchSpecForLaunch(
            profileId: profile.id,
            launchProfile: launchProfile,
          ),
        );
      },
    );
  }

  String _layoutRestoreFailureMessage(
    List<LocalTerminalLayoutRelaunchFailure> failures,
  ) {
    if (ref.read(terminalSessionLaunchPolicyProvider).isSshOnly) {
      return 'iOS skipped ${failures.length} saved pane(s) that are not '
          'available as SSH profiles. Choose an SSH profile to open a tab.';
    }
    final profileIds = failures
        .map((failure) => failure.intent.profileId)
        .where((profileId) => profileId.trim().isNotEmpty)
        .toSet()
        .take(3)
        .join(', ');
    return 'Terminal layout restore skipped ${failures.length} pane(s)'
        '${profileIds.isEmpty ? '' : ' for profile(s): $profileIds'}.';
  }

  void _enableLayoutPersistence() {
    _layoutPersistenceEnabled =
        _localConfigDocument.layout.restoreLayout && !_layoutPersistenceBlocked;
    if (!_layoutPersistenceEnabled) {
      _layoutRetryTimer?.cancel();
      _layoutRetryTimer = null;
      _layoutRetryAttempt = 0;
      _lastLayoutSnapshot = null;
      return;
    }
    _lastLayoutSnapshot = jsonEncode(
      LocalSessionLayoutCodec.capture(state).toJson(),
    );
  }

  void _handleLayoutStateChanged(SessionState? previous, SessionState next) {
    if (_isShuttingDown || !_layoutPersistenceEnabled || !next.isReady) {
      return;
    }
    final layout = LocalSessionLayoutCodec.capture(next);
    final snapshot = jsonEncode(layout.toJson());
    if (snapshot == _lastLayoutSnapshot) {
      return;
    }
    _lastLayoutSnapshot = snapshot;
    _layoutPersistenceTimer?.cancel();
    _layoutPersistenceTimer = Timer(_layoutPersistenceDebounce, () {
      _layoutPersistenceTimer = null;
      _queueLayoutSave(layout);
    });
  }

  void _queueLayoutSave(TerminalLayout layout) {
    _layoutRetryTimer?.cancel();
    _layoutRetryTimer = null;
    final previousSave = _layoutSaveChain;
    final repository = ref.read(localTerminalLayoutRepositoryProvider);
    _layoutSaveChain = _saveLayoutAfter(previousSave, layout, repository);
  }

  Future<void> flushLayoutPersistence() async {
    if (_isShuttingDown) {
      await (_sessionShutdownFuture ?? _layoutSaveChain);
      return;
    }
    if (!_layoutPersistenceEnabled || !state.isReady) {
      return;
    }
    _layoutPersistenceTimer?.cancel();
    _layoutPersistenceTimer = null;
    final layout = LocalSessionLayoutCodec.capture(state);
    _lastLayoutSnapshot = jsonEncode(layout.toJson());
    _queueLayoutSave(layout);
    await _layoutSaveChain;
  }

  Future<void> _saveLayoutAfter(
    Future<void> previousSave,
    TerminalLayout layout,
    TerminalLayoutRepository repository,
  ) async {
    try {
      await previousSave;
      _layoutDocument = await repository.saveVersioned(
        _layoutDocument.withValue(layout),
      );
      _layoutRetryTimer?.cancel();
      _layoutRetryTimer = null;
      _layoutRetryAttempt = 0;
    } on TerminalLayoutSaveUnavailableException {
      _scheduleLayoutRetry();
    } on Object catch (error) {
      if (ref.mounted) {
        final detail = _boundedShellMetadata(error.toString(), 240);
        state = state.copyWith(
          lastError:
              'Terminal layout save failed'
              '${detail == null ? '' : ': $detail'}',
        );
      }
    }
  }

  void _scheduleLayoutRetry() {
    if (_isShuttingDown || !_layoutPersistenceEnabled || !state.isReady) {
      return;
    }
    _layoutRetryTimer?.cancel();
    final attempt = _layoutRetryAttempt;
    if (_layoutRetryAttempt < 1000000) {
      _layoutRetryAttempt += 1;
    }
    _layoutRetryTimer = Timer(
      ref.read(terminalLayoutRetryDelayProvider)(attempt),
      () {
        _layoutRetryTimer = null;
        if (_isShuttingDown || !_layoutPersistenceEnabled || !state.isReady) {
          return;
        }
        final latestLayout = LocalSessionLayoutCodec.capture(state);
        _lastLayoutSnapshot = jsonEncode(latestLayout.toJson());
        _queueLayoutSave(latestLayout);
      },
    );
  }

  Future<bool> openTerminalAtFolder(String folderPath) async {
    final normalizedPath = folderPath.trim();
    if (_isShuttingDown || !state.isReady || normalizedPath.isEmpty) {
      return false;
    }
    if (ref.read(sessionDemoFixtureProvider) != null) {
      state = state.copyWith(
        lastError: 'New tab at folder is unavailable in reference demo mode.',
      );
      return false;
    }
    if (ref.read(terminalSessionLaunchPolicyProvider).isSshOnly) {
      state = state.copyWith(
        lastError:
            'Opening a local folder is unavailable on iOS. Choose an SSH '
            'profile instead.',
      );
      return false;
    }
    final defaultProfile = _effectiveDefaultProfile();
    if (defaultProfile == null) {
      state = state.copyWith(
        lastError: 'New tab at folder requires an available terminal profile.',
      );
      return false;
    }
    final previousSessionId = state.activeSessionId;
    createSession(defaultProfile.copyWith(cwd: normalizedPath));
    return state.activeSessionId != null &&
        state.activeSessionId != previousSessionId;
  }

  TerminalProfile? _effectiveDefaultProfile() {
    if (state.profiles.isEmpty) {
      return null;
    }
    final defaultProfileId = state.defaultProfileId;
    if (defaultProfileId == null) {
      return state.profiles.first;
    }
    return state.profiles.firstWhere(
      (profile) => profile.id == defaultProfileId,
      orElse: () => state.profiles.first,
    );
  }

  void _ensureRuntimeSubscription() {
    _runtimeEventAttachment ??= ref
        .read(terminalEventCoordinatorProvider)
        .attachBusinessSink(
          onEffect: _handleRuntimeEffect,
          onPreClose: _prepareRecordingForRuntimeExit,
        );
  }

  void createSession(TerminalProfile profile) {
    if (_isShuttingDown || ref.read(sessionDemoFixtureProvider) != null) {
      return;
    }
    _ensureRuntimeSubscription();
    final environmentOverrides = ref.read(sessionEnvironmentOverridesProvider);
    final launchProfile = _profileWithSessionEnvironment(
      profile,
      environmentOverrides,
    );
    final sessionId = _createRuntimeSession(launchProfile);
    if (sessionId == null) {
      return;
    }
    _clearMatchingSshExitFailureForRetry(profile);
    final descriptor = _relaunchSpecForLaunch(
      profileId: profile.id,
      launchProfile: launchProfile,
    );
    state = state.copyWith(
      tabs: <TerminalTab>[
        ...state.tabs,
        TerminalTab(
          sessionId: sessionId,
          title: launchProfile.name,
          profileId: profile.id,
          profileSnapshot: launchProfile,
          relaunchSpec: descriptor,
        ),
      ],
      activeSessionId: sessionId,
    );
    _syncRuntimeSessionActivation();
    _setWindowTitle(launchProfile.name);
  }

  void splitActiveSession(TerminalProfile profile, TerminalSplitAxis axis) {
    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      createSession(profile);
      return;
    }

    splitSession(activeSessionId, profile, axis);
  }

  void splitSession(
    String targetSessionId,
    TerminalProfile profile,
    TerminalSplitAxis axis,
  ) {
    if (_isShuttingDown || ref.read(sessionDemoFixtureProvider) != null) {
      return;
    }
    final targetTabIndex = _tabIndexContainingSession(targetSessionId);
    if (targetTabIndex == -1) {
      createSession(profile);
      return;
    }

    _ensureRuntimeSubscription();
    final environmentOverrides = ref.read(sessionEnvironmentOverridesProvider);
    final launchProfile = _profileWithSessionEnvironment(
      profile,
      environmentOverrides,
    );
    final sessionId = _createRuntimeSession(launchProfile);
    if (sessionId == null) {
      return;
    }
    _clearMatchingSshExitFailureForRetry(profile);
    final newPane = TerminalPane(
      sessionId: sessionId,
      title: launchProfile.name,
      profileId: profile.id,
      profileSnapshot: launchProfile,
      relaunchSpec: _relaunchSpecForLaunch(
        profileId: profile.id,
        launchProfile: launchProfile,
      ),
    );
    final targetTab = state.tabs[targetTabIndex];
    final nextPaneLayout = targetTab.effectivePaneLayout.splitPane(
      sessionId: targetSessionId,
      newPane: newPane,
      axis: axis,
    );
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[targetTabIndex] = targetTab.copyWith(
      panes: nextPaneLayout.panes,
      paneLayout: nextPaneLayout,
      activePaneSessionId: sessionId,
      splitAxis: axis,
    );
    state = state.copyWith(tabs: nextTabs, activeSessionId: sessionId);
    _syncRuntimeSessionActivation();
    _setWindowTitle(launchProfile.name);
  }

  TerminalProfile _profileWithSessionEnvironment(
    TerminalProfile profile,
    Map<String, String> environmentOverrides,
  ) {
    final integration = profile.sessionConfig.shellIntegration;
    final autoInject =
        integration.sshAutoInject ??
        _localConfigDocument.shellIntegration.sshAutoInject;
    final configuredProfile = profile.copyWith(
      sessionConfig: profile.sessionConfig.copyWith(
        shellIntegration: integration.copyWith(
          sshWrapper: profile.isSsh
              ? autoInject
              : _localConfigDocument.shellIntegration.sshWrapper,
          sshAutoInject: autoInject,
        ),
      ),
    );
    if (configuredProfile.isSsh) {
      return configuredProfile;
    }
    final launchProfile = configuredProfile.copyWith(
      env: <String, String>{
        ..._defaultEnvironmentForEmulation(profile.terminalEmulation),
        ...profile.env,
        ...environmentOverrides,
      },
    );
    if (_localConfigDocument.shellIntegration.enabled) {
      return launchProfile;
    }

    return launchProfile.copyWith(
      sessionConfig: launchProfile.sessionConfig.copyWith(
        shellIntegration: launchProfile.sessionConfig.shellIntegration.copyWith(
          enabled: false,
        ),
      ),
    );
  }

  Map<String, String> _defaultEnvironmentForEmulation(
    TerminalEmulation emulation,
  ) {
    return switch (emulation) {
      TerminalEmulation.xterm256 => const <String, String>{
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
      TerminalEmulation.vt220 => const <String, String>{'TERM': 'vt220'},
    };
  }

  TerminalRelaunchSpec _relaunchSpecForLaunch({
    required String profileId,
    required TerminalProfile launchProfile,
  }) {
    return TerminalRelaunchSpec(profileId: profileId, cwd: launchProfile.cwd);
  }

  String? _createRuntimeSession(TerminalProfile launchProfile) {
    if (!ref.read(terminalSessionLaunchPolicyProvider).allows(launchProfile)) {
      state = state.copyWith(
        lastError:
            'Local terminal sessions are unavailable on iOS. Choose an SSH '
            'profile instead.',
      );
      return null;
    }
    try {
      return _runtime.createSession(
        launchProfile.toSessionConfig().copyWith(
          // The macOS example installs the native OSC 72 bridge. Other
          // platforms retain the package's deny-by-default behavior.
          dragDropEnabled: Platform.isMacOS,
        ),
      );
    } on Object catch (error) {
      final detail = _boundedShellMetadata(error.toString(), 240);
      state = state.copyWith(
        lastError:
            'Terminal backend createSession failed'
            '${detail == null ? '' : ': $detail'}',
      );
      return null;
    }
  }

  void activateSession(String sessionId) {
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return;
    }

    final tab = state.tabs[tabIndex];
    final pane = tab.paneFor(sessionId);
    if (pane == null) {
      return;
    }
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = tab.copyWith(
      activePaneSessionId: pane.sessionId == tab.sessionId
          ? null
          : pane.sessionId,
    );
    state = state.copyWith(tabs: nextTabs, activeSessionId: pane.sessionId);
    _syncRuntimeSessionActivation();
    _setWindowTitle(pane.title);

    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      _publishDemoContent(demoFixture, pane.sessionId);
    } else {
      _publishActiveTabTerminalContent();
    }
  }

  void swapActivePaneWithSibling() {
    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final tabIndex = _tabIndexContainingSession(activeSessionId);
    if (tabIndex == -1) {
      return;
    }

    final activeTab = state.tabs[tabIndex];
    final panes = activeTab.effectivePanes;
    if (panes.length < 2) {
      return;
    }
    final activeIndex = panes.indexWhere(
      (pane) => pane.sessionId == activeSessionId,
    );
    if (activeIndex < 0) {
      return;
    }
    final nextPaneLayout = activeTab.effectivePaneLayout.swapPaneWithSibling(
      activeSessionId,
    );

    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = activeTab.copyWith(
      panes: nextPaneLayout.panes,
      paneLayout: nextPaneLayout,
      activePaneSessionId: activeSessionId == activeTab.sessionId
          ? null
          : activeSessionId,
    );
    state = state.copyWith(tabs: nextTabs);
  }

  void resizeActivePaneSplit(String splitNodeId, double ratio) {
    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      return;
    }

    resizePaneSplit(activeSessionId, splitNodeId, ratio);
  }

  void resizePaneSplit(
    String targetSessionId,
    String splitNodeId,
    double ratio,
  ) {
    final tabIndex = _tabIndexContainingSession(targetSessionId);
    if (tabIndex == -1) {
      return;
    }

    final targetTab = state.tabs[tabIndex];
    final nextPaneLayout = targetTab.effectivePaneLayout.resizeSplit(
      splitNodeId,
      ratio,
    );
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = targetTab.copyWith(
      panes: nextPaneLayout.panes,
      paneLayout: nextPaneLayout,
    );
    state = state.copyWith(tabs: nextTabs);
  }

  void growPane(String sessionId) {
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return;
    }

    final activeTab = state.tabs[tabIndex];
    final nextPaneLayout = activeTab.effectivePaneLayout.growPane(
      sessionId,
      0.08,
    );
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = activeTab.copyWith(
      panes: nextPaneLayout.panes,
      paneLayout: nextPaneLayout,
    );
    state = state.copyWith(tabs: nextTabs);
  }

  void reorderTab({required int oldIndex, required int newIndex}) {
    if (oldIndex < 0 || oldIndex >= state.tabs.length) {
      return;
    }
    final targetIndex = newIndex.clamp(0, state.tabs.length - 1);
    if (oldIndex == targetIndex) {
      return;
    }

    final nextTabs = <TerminalTab>[...state.tabs];
    final movingTab = nextTabs.removeAt(oldIndex);
    nextTabs.insert(targetIndex, movingTab);
    state = state.copyWith(tabs: nextTabs);
  }

  bool moveSessionToPane({
    required String sourceSessionId,
    required String targetSessionId,
    required TerminalSplitAxis axis,
    required bool before,
  }) {
    if (sourceSessionId == targetSessionId) {
      return false;
    }
    final sourceTabIndex = _tabIndexContainingSession(sourceSessionId);
    final targetTabIndex = _tabIndexContainingSession(targetSessionId);
    if (sourceTabIndex == -1 || targetTabIndex == -1) {
      return false;
    }

    final sourceTab = state.tabs[sourceTabIndex];
    final sourcePane = sourceTab.paneFor(sourceSessionId);
    if (sourcePane == null) {
      return false;
    }
    final sourceLayout = sourceTab.effectivePaneLayout.removePane(
      sourceSessionId,
    );

    if (sourceTabIndex == targetTabIndex) {
      if (sourceLayout == null ||
          !sourceLayout.containsSession(targetSessionId)) {
        return false;
      }
      final nextLayout = sourceLayout.insertPane(
        targetSessionId: targetSessionId,
        pane: sourcePane,
        axis: axis,
        before: before,
      );
      final nextTabs = <TerminalTab>[...state.tabs];
      nextTabs[sourceTabIndex] = sourceTab.copyWith(
        panes: nextLayout.panes,
        paneLayout: nextLayout,
        activePaneSessionId: sourceSessionId,
        splitAxis: axis,
      );
      state = state.copyWith(tabs: nextTabs, activeSessionId: sourceSessionId);
      _syncRuntimeSessionActivation();
      _setWindowTitle(sourcePane.title);
      return true;
    }

    final nextTabs = <TerminalTab>[...state.tabs];
    if (sourceLayout == null) {
      nextTabs.removeAt(sourceTabIndex);
    } else {
      nextTabs[sourceTabIndex] = _tabAfterMovingPaneOut(
        sourceTab: sourceTab,
        movedSessionId: sourceSessionId,
        sourceLayout: sourceLayout,
      );
    }

    final nextTargetTabIndex = nextTabs.indexWhere(
      (tab) => tab.containsSession(targetSessionId),
    );
    if (nextTargetTabIndex == -1) {
      return false;
    }
    final targetTab = nextTabs[nextTargetTabIndex];
    final nextTargetLayout = targetTab.effectivePaneLayout.insertPane(
      targetSessionId: targetSessionId,
      pane: sourcePane,
      axis: axis,
      before: before,
    );
    nextTabs[nextTargetTabIndex] = targetTab.copyWith(
      panes: nextTargetLayout.panes,
      paneLayout: nextTargetLayout,
      activePaneSessionId: sourceSessionId,
      splitAxis: axis,
    );
    state = state.copyWith(tabs: nextTabs, activeSessionId: sourceSessionId);
    _syncRuntimeSessionActivation();
    _setWindowTitle(sourcePane.title);
    return true;
  }

  bool detachPaneToTab({
    required String sessionId,
    required int insertionIndex,
  }) {
    final sourceTabIndex = _tabIndexContainingSession(sessionId);
    if (sourceTabIndex == -1) {
      return false;
    }
    final sourceTab = state.tabs[sourceTabIndex];
    final sourcePane = sourceTab.paneFor(sessionId);
    if (sourcePane == null) {
      return false;
    }

    if (sourceTab.effectivePanes.length < 2) {
      final nextTabs = <TerminalTab>[...state.tabs];
      final movingTab = nextTabs.removeAt(sourceTabIndex);
      var targetIndex = insertionIndex.clamp(0, state.tabs.length);
      if (sourceTabIndex < targetIndex) {
        targetIndex -= 1;
      }
      nextTabs.insert(targetIndex.clamp(0, nextTabs.length), movingTab);
      state = state.copyWith(tabs: nextTabs, activeSessionId: sessionId);
      _syncRuntimeSessionActivation();
      _setWindowTitle(sourcePane.title);
      return true;
    }

    final sourceLayout = sourceTab.effectivePaneLayout.removePane(sessionId);
    if (sourceLayout == null) {
      return false;
    }
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[sourceTabIndex] = _tabAfterMovingPaneOut(
      sourceTab: sourceTab,
      movedSessionId: sessionId,
      sourceLayout: sourceLayout,
    );
    final detachedTab = TerminalTab(
      sessionId: sourcePane.sessionId,
      title: sourcePane.title,
      profileId: sourcePane.profileId,
      profileSnapshot: sourcePane.profileSnapshot,
      relaunchSpec: sourcePane.relaunchSpec,
      isExited: sourcePane.isExited,
      exitCode: sourcePane.exitCode,
      shellIntegration: sourcePane.shellIntegration,
      oscBadge: sourcePane.oscBadge,
      tabStatus: sourcePane.tabStatus,
      progress: sourcePane.progress,
      namedProgress: sourcePane.namedProgress,
      recentNotifications: sourcePane.recentNotifications,
    );
    nextTabs.insert(insertionIndex.clamp(0, nextTabs.length), detachedTab);
    state = state.copyWith(tabs: nextTabs, activeSessionId: sessionId);
    _syncRuntimeSessionActivation();
    _setWindowTitle(sourcePane.title);
    return true;
  }

  TerminalTab _tabAfterMovingPaneOut({
    required TerminalTab sourceTab,
    required String movedSessionId,
    required TerminalPaneLayoutNode sourceLayout,
  }) {
    final nextActiveSessionId = sourceTab.activeSessionId == movedSessionId
        ? sourceLayout.panes.last.sessionId
        : sourceTab.activeSessionId;
    if (sourceTab.sessionId != movedSessionId) {
      return sourceTab.copyWith(
        panes: sourceLayout.panes,
        paneLayout: sourceLayout,
        activePaneSessionId: nextActiveSessionId == sourceTab.sessionId
            ? null
            : nextActiveSessionId,
      );
    }

    final replacementRoot = sourceLayout.panes.first;
    return TerminalTab(
      sessionId: replacementRoot.sessionId,
      title: replacementRoot.title,
      profileId: replacementRoot.profileId,
      profileSnapshot: replacementRoot.profileSnapshot,
      relaunchSpec: replacementRoot.relaunchSpec,
      isExited: replacementRoot.isExited,
      exitCode: replacementRoot.exitCode,
      panes: sourceLayout.panes,
      paneLayout: sourceLayout,
      activePaneSessionId: nextActiveSessionId == replacementRoot.sessionId
          ? null
          : nextActiveSessionId,
      splitAxis: sourceTab.splitAxis,
      shellIntegration: replacementRoot.shellIntegration,
      oscBadge: replacementRoot.oscBadge,
      tabStatus: replacementRoot.tabStatus,
      progress: replacementRoot.progress,
      namedProgress: replacementRoot.namedProgress,
      recentNotifications: replacementRoot.recentNotifications,
    );
  }

  Future<bool> startSessionRecording(
    String sessionId, {
    TerminalRecordingInputPolicy inputPolicy =
        TerminalRecordingInputPolicy.redact,
  }) {
    if (_recordingStarts.containsKey(sessionId)) return Future.value(false);
    final future = _startSampledRecording(sessionId, inputPolicy);
    _recordingStarts[sessionId] = future;
    return future.whenComplete(() => _recordingStarts.remove(sessionId));
  }

  Future<bool> _startSampledRecording(
    String sessionId,
    TerminalRecordingInputPolicy inputPolicy,
  ) async {
    if (_isShuttingDown || !ref.mounted) return false;
    final pane = _paneForSession(sessionId);
    if (!state.isReady ||
        pane == null ||
        pane.isExited ||
        !_runtime.hasSession(sessionId) ||
        _recordingNeedsFinalization(sessionId)) {
      return false;
    }
    if (ref.read(sessionDemoFixtureProvider) != null ||
        inputPolicy != TerminalRecordingInputPolicy.redact) {
      state = state.copyWith(
        lastError:
            'Sampled recording saves screens and observed commands; raw input recording is unavailable.',
      );
      return false;
    }
    final client = ref.read(sampledRecordingCaptureClientProvider);
    if (client == null) {
      state = state.copyWith(
        lastError: 'The active backend does not support sampled recording.',
      );
      return false;
    }
    final library = ref.read(sampledRecordingLibraryProvider);
    _setRecordingStatus(sessionId, busy: true, lastError: null);
    SampledRecordingClaim? claim;
    try {
      final epoch = _runtime.sessionEpochFor(sessionId);
      if (epoch == null) {
        throw StateError('Runtime session identity is unavailable');
      }
      claim = await library.reserve(
        sessionId: sessionId,
        sessionEpoch: epoch,
        title: pane.title,
        hostname: pane.shellIntegration.hostname,
      );
      if (_isShuttingDown ||
          !ref.mounted ||
          !_runtime.hasSession(sessionId) ||
          _runtime.sessionEpochFor(sessionId) != epoch) {
        await library.abandonUndispatched(claim);
        return false;
      }
      _recordingClaims[sessionId] = claim;
      final status = await library.start(claim, client);
      _ensureRecordingPolling();
      if (_isShuttingDown || !ref.mounted) return false;
      _setRecordingStatus(
        sessionId,
        active: !status.settled && status.phase != SampledCapturePhase.failed,
        pendingSave:
            status.settled || status.phase == SampledCapturePhase.failed,
        busy: false,
        lastError: status.error,
      );
      if (status.settled) await stopSessionRecording(sessionId);
      return !status.settled && status.phase != SampledCapturePhase.failed;
    } on Object catch (error) {
      if (claim != null && !claim.dispatched) {
        await library.abandonUndispatched(claim);
        _recordingClaims.remove(sessionId);
      }
      if (claim?.dispatched == true) _ensureRecordingPolling();
      if (ref.mounted && !_isShuttingDown) {
        _setRecordingStatus(
          sessionId,
          active: false,
          pendingSave: claim?.dispatched == true,
          busy: false,
          lastError: _recordingError('Recording start failed', error),
        );
      }
      return false;
    } finally {
      if (ref.mounted && !_isShuttingDown) {
        _setRecordingStatus(sessionId, busy: false);
      }
    }
  }

  Future<String?> stopSessionRecording(String sessionId) async {
    if (_isShuttingDown || !ref.mounted) return null;
    final claim = _recordingClaims[sessionId];
    final client = ref.read(sampledRecordingCaptureClientProvider);
    if (claim == null ||
        client == null ||
        state.recordingBusySessionIds.contains(sessionId)) {
      return null;
    }
    final library = ref.read(sampledRecordingLibraryProvider);
    _setRecordingStatus(sessionId, busy: true, lastError: null);
    try {
      final path = await library.finish(claim, client);
      _forgetRecording(sessionId);
      if (claim.entry.state != 'finished' && ref.mounted && !_isShuttingDown) {
        state = state.copyWith(
          lastError: _recordingError(
            'Recording interrupted; committed content was preserved',
            claim.entry.error ?? 'writer interrupted',
          ),
        );
      }
      return path;
    } on Object catch (error) {
      if (ref.mounted && !_isShuttingDown) {
        _setRecordingStatus(
          sessionId,
          active: false,
          pendingSave: true,
          busy: false,
          lastError: _recordingError('Recording save needs attention', error),
        );
      }
      return null;
    }
  }

  void _ensureRecordingPolling() {
    if (_isShuttingDown) return;
    _recordingTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pollRecordings()),
    );
  }

  Future<void> _pollRecordings() async {
    if (_recordingPollRunning || _isShuttingDown || !ref.mounted) return;
    final client = ref.read(sampledRecordingCaptureClientProvider);
    if (client == null) return;
    final library = ref.read(sampledRecordingLibraryProvider);
    _recordingPollRunning = true;
    try {
      for (final claim in _recordingClaims.values.toList(growable: false)) {
        if (_isShuttingDown || !ref.mounted) break;
        final id = claim.handle.sessionId;
        if (!claim.dispatched || state.recordingBusySessionIds.contains(id)) {
          continue;
        }
        try {
          final status = client.status(claim.handle);
          await library.update(claim, status);
          if (_isShuttingDown || !ref.mounted) break;
          if (!identical(_recordingClaims[id], claim)) continue;
          if (status.settled) {
            await stopSessionRecording(id);
          } else if (status.phase == SampledCapturePhase.failed) {
            _setRecordingStatus(
              id,
              active: false,
              pendingSave: true,
              lastError: _recordingError('Recording stopped', status.error!),
            );
          }
        } on Object catch (error) {
          if (ref.mounted && !_isShuttingDown) {
            _setRecordingStatus(
              id,
              lastError: _recordingError('Recording state unavailable', error),
            );
          }
        }
      }
    } finally {
      _recordingPollRunning = false;
      if (_recordingClaims.isEmpty) {
        _recordingTimer?.cancel();
        _recordingTimer = null;
      }
    }
  }

  TerminalSessionPreCloseOutcome _prepareRecordingForRuntimeExit(
    TerminalSessionExitClaim exit,
  ) {
    if (_isShuttingDown || !ref.mounted) {
      return TerminalSessionPreCloseOutcome.retryableFailure(
        error: StateError('Application shutdown owns this close'),
        stackTrace: StackTrace.current,
      );
    }
    final claim = _recordingClaims[exit.sessionId];
    if (claim == null) return const TerminalSessionPreCloseOutcome.allowClose();
    if (claim.sessionEpoch != exit.sessionEpoch) {
      return TerminalSessionPreCloseOutcome.retryableFailure(
        error: StateError('Stale recording session epoch'),
        stackTrace: StackTrace.current,
      );
    }
    final previous = _recordingExitClaims[exit.sessionId];
    if (previous != null && previous.claimId != exit.claimId) {
      return TerminalSessionPreCloseOutcome.retryableFailure(
        error: StateError('Another exit owns the recording'),
        stackTrace: StackTrace.current,
      );
    }
    if (!claim.dispatched) {
      return TerminalSessionPreCloseOutcome.retryableFailure(
        error: StateError('Recording start is in progress'),
        stackTrace: StackTrace.current,
      );
    }
    final client = ref.read(sampledRecordingCaptureClientProvider);
    if (client == null) {
      return TerminalSessionPreCloseOutcome.retryableFailure(
        error: StateError('Recording backend unavailable'),
        stackTrace: StackTrace.current,
      );
    }
    try {
      client.stop(claim.handle);
      // The manifest and file claim already exist. Native writer monitoring
      // survives Session removal; the exit observer waits for real settlement.
      _recordingExitClaims[exit.sessionId] = exit;
      return const TerminalSessionPreCloseOutcome.allowClose();
    } on Object catch (error, stackTrace) {
      return TerminalSessionPreCloseOutcome.retryableFailure(
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _recordingNeedsFinalization(String sessionId) {
    return state.recordingSessionIds.contains(sessionId) ||
        state.recordingPendingSaveSessionIds.contains(sessionId) ||
        state.recordingBusySessionIds.contains(sessionId);
  }

  Future<bool> _finalizeSessionRecordings(Iterable<String> sessionIds) async {
    for (final sessionId in sessionIds) {
      if (_isShuttingDown) {
        return false;
      }
      if (state.recordingBusySessionIds.contains(sessionId)) {
        state = state.copyWith(
          lastError: 'Recording operation is still in progress. Try again.',
        );
        return false;
      }
      if (state.recordingSessionIds.contains(sessionId) ||
          state.recordingPendingSaveSessionIds.contains(sessionId)) {
        final path = await stopSessionRecording(sessionId);
        if (_isShuttingDown || path == null) {
          return false;
        }
      }
    }
    return true;
  }

  Map<String, TerminalRecordingInputPolicy> _activeRecordingPolicies(
    Iterable<String> sessionIds,
  ) {
    return <String, TerminalRecordingInputPolicy>{
      for (final sessionId in sessionIds)
        if (state.recordingSessionIds.contains(sessionId))
          sessionId: TerminalRecordingInputPolicy.redact,
    };
  }

  Future<bool> _resumeRecordingsAfterRejectedClose(
    Map<String, TerminalRecordingInputPolicy> policies,
  ) async {
    var resumedAll = true;
    for (final entry in policies.entries) {
      if (_isShuttingDown) {
        return false;
      }
      final sessionId = entry.key;
      if (!_runtime.hasSession(sessionId) ||
          _paneForSession(sessionId) == null) {
        continue;
      }
      if (state.recordingSessionIds.contains(sessionId)) {
        continue;
      }
      // Native recording stop is destructive, so an asynchronous save cannot
      // be rolled back. If the later native close linearization is rejected,
      // immediately start a continuation recording instead of silently
      // leaving the still-live terminal unrecorded.
      final resumed = await startSessionRecording(
        sessionId,
        inputPolicy: entry.value,
      );
      if (_isShuttingDown) {
        return false;
      }
      resumedAll = resumed && resumedAll;
    }
    return resumedAll;
  }

  void _setRecordingStatus(
    String sessionId, {
    bool? active,
    bool? pendingSave,
    bool? busy,
    Object? lastError = _recordingLastErrorNoChange,
  }) {
    final activeIds = <String>{...state.recordingSessionIds};
    final pendingSaveIds = <String>{...state.recordingPendingSaveSessionIds};
    final busyIds = <String>{...state.recordingBusySessionIds};
    _updateMembership(activeIds, sessionId, active);
    _updateMembership(pendingSaveIds, sessionId, pendingSave);
    _updateMembership(busyIds, sessionId, busy);
    state = state.copyWith(
      recordingSessionIds: activeIds,
      recordingPendingSaveSessionIds: pendingSaveIds,
      recordingBusySessionIds: busyIds,
      lastError: identical(lastError, _recordingLastErrorNoChange)
          ? state.lastError
          : lastError as String?,
    );
  }

  void _updateMembership(Set<String> values, String sessionId, bool? included) {
    if (included == true) {
      values.add(sessionId);
    } else if (included == false) {
      values.remove(sessionId);
    }
  }

  String _recordingError(String prefix, Object error) {
    final detail = _boundedShellMetadata(error.toString(), 240);
    return '$prefix${detail == null ? '' : ': $detail'}';
  }

  Future<void> _finalizeRecordingOnRuntimeExitBestEffort(
    String sessionId, {
    TerminalSessionExitClaim? exitClaim,
  }) async {
    final owned = _recordingExitClaims[sessionId];
    if (exitClaim == null ||
        owned?.claimId != exitClaim.claimId ||
        owned?.sessionEpoch != exitClaim.sessionEpoch) {
      return;
    }
    await stopSessionRecording(sessionId);
  }

  Future<void> _finalizeRecordingsForShutdown(
    SampledRecordingCaptureClient? client,
    SampledRecordingLibrary library,
  ) {
    return _recordingShutdownFuture ??= _runRecordingShutdownFinalization(
      client,
      library,
    );
  }

  Future<void> _shutdownSessions(
    SampledRecordingCaptureClient? recorder,
    SampledRecordingLibrary recordingRepository,
    TerminalLayoutRepository layoutRepository,
    TerminalRuntimeController terminalRuntime,
    TerminalEventCoordinator terminalEventCoordinator,
  ) {
    final existing = _sessionShutdownFuture;
    if (existing != null) {
      return existing;
    }

    _isShuttingDown = true;
    unawaited(_recordingMaintenance?.stop());
    final bootstrapSettlement = _bootstrapFuture ?? Future<void>.value();
    final runtimeEventsCancellation = terminalEventCoordinator.beginShutdown();
    _runtimeEventAttachment?.detach();
    _runtimeEventAttachment = null;
    terminalRuntime.beginShutdown();
    _layoutPersistenceTimer?.cancel();
    _layoutPersistenceTimer = null;
    _layoutRetryTimer?.cancel();
    _layoutRetryTimer = null;

    final pendingLayoutWrites = _layoutSaveChain;
    final finalLayout = _layoutPersistenceEnabled && state.isReady
        ? LocalSessionLayoutCodec.capture(state)
        : null;
    if (finalLayout != null) {
      _lastLayoutSnapshot = jsonEncode(finalLayout.toJson());
    }

    // The recorder snapshot is captured synchronously before its first await,
    // after the event coordinator has gated new effects. Encoding remains
    // async.
    final recordingFinalization = _finalizeRecordingsForShutdown(
      recorder,
      recordingRepository,
    );
    return _sessionShutdownFuture = _completeSessionShutdown(
      bootstrapSettlement: bootstrapSettlement,
      runtimeEventsCancellation: runtimeEventsCancellation,
      recordingFinalization: recordingFinalization,
      pendingLayoutWrites: pendingLayoutWrites,
      finalLayout: finalLayout,
      layoutRepository: layoutRepository,
    );
  }

  Future<void> _completeSessionShutdown({
    required Future<void> bootstrapSettlement,
    required Future<void> runtimeEventsCancellation,
    required Future<void> recordingFinalization,
    required Future<void> pendingLayoutWrites,
    required TerminalLayout? finalLayout,
    required TerminalLayoutRepository layoutRepository,
  }) async {
    await const SessionShutdownSettler().settle(
      startedOperations: <SessionShutdownResource, Future<void>>{
        SessionShutdownResource.bootstrap: bootstrapSettlement,
        SessionShutdownResource.runtime: runtimeEventsCancellation,
        SessionShutdownResource.recording: recordingFinalization,
      },
      deferredOperations: <SessionShutdownResource, SessionShutdownOperation>{
        SessionShutdownResource.layout: () => _flushCapturedLayoutForShutdown(
          pendingLayoutWrites: pendingLayoutWrites,
          finalLayout: finalLayout,
          repository: layoutRepository,
        ),
      },
    );
  }

  Future<void> _flushCapturedLayoutForShutdown({
    required Future<void> pendingLayoutWrites,
    required TerminalLayout? finalLayout,
    required TerminalLayoutRepository repository,
  }) async {
    await pendingLayoutWrites;
    if (finalLayout != null) {
      _layoutDocument = await repository.saveVersioned(
        _layoutDocument.withValue(finalLayout),
      );
    }
  }

  Future<void> _runRecordingShutdownFinalization(
    SampledRecordingCaptureClient? client,
    SampledRecordingLibrary library,
  ) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _recordingMaintenance?.stop();
    await library.drain();
    await Future.wait(_recordingStarts.values.toList(growable: false));
    for (final claim in library.activeClaims.toList(growable: false)) {
      if (!claim.dispatched) {
        await library.abandonUndispatched(claim);
        _recordingClaims.remove(claim.handle.sessionId);
        continue;
      }
      // A timeout or transport error never releases the file claim. Keep the
      // application phase pending while the shutdown coordinator reports delay.
      while (true) {
        try {
          if (client == null) throw StateError('Recording backend unavailable');
          await library.finish(claim, client);
          _recordingClaims.remove(claim.handle.sessionId);
          break;
        } on Object {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
  }

  void _forgetRecording(String sessionId) {
    _recordingClaims.remove(sessionId);
    _recordingExitClaims.remove(sessionId);
    if (!ref.mounted || _isShuttingDown) return;
    _setRecordingStatus(
      sessionId,
      active: false,
      pendingSave: false,
      busy: false,
    );
  }

  Future<bool> closeSession(String sessionId) async {
    if (_isShuttingDown) {
      return false;
    }
    if (ref.read(sessionDemoFixtureProvider) != null) {
      _removeSessionState(sessionId);
      return true;
    }
    if (_runtime.isZmodemTransferActive(sessionId)) {
      reportRuntimeError(
        'Cancel the active ZMODEM transfer and wait for it to finish before '
        'closing this pane.',
      );
      return false;
    }
    final recordingsToResume = _activeRecordingPolicies(<String>[sessionId]);
    if (_recordingNeedsFinalization(sessionId)) {
      final finalized = await _finalizeSessionRecordings(<String>[sessionId]);
      if (_isShuttingDown || !finalized) {
        return false;
      }
    }
    if (_isShuttingDown) {
      return false;
    }
    // Recording finalization yields to the event loop, so repeat the guard at
    // the actual close boundary. Native also rejects the narrower receive
    // publication critical section and retains its event queue on failure.
    if (_runtime.isZmodemTransferActive(sessionId)) {
      final resumed = await _resumeRecordingsAfterRejectedClose(
        recordingsToResume,
      );
      if (_isShuttingDown) {
        return false;
      }
      reportRuntimeError(
        resumed
            ? 'Cancel the active ZMODEM transfer and wait for it to finish '
                  'before closing this pane. Recording continued in a new file.'
            : 'Cancel the active ZMODEM transfer before closing this pane. '
                  'The recording continuation could not be started.',
      );
      return false;
    }
    if (_isShuttingDown || !_runtime.tryCloseSession(sessionId)) {
      final resumed = await _resumeRecordingsAfterRejectedClose(
        recordingsToResume,
      );
      if (_isShuttingDown) {
        return false;
      }
      reportRuntimeError(
        resumed
            ? 'A native ZMODEM transfer or file publication is still active. '
                  'Recording continued in a new file; cancel the transfer and '
                  'try closing the pane again.'
            : 'A native ZMODEM transfer or file publication is still active, '
                  'and the recording continuation could not be started.',
      );
      return false;
    }
    _removeSessionState(sessionId);
    return true;
  }

  void clearPromptMarks(String sessionId) {
    final pane = _paneForSession(sessionId);
    if (pane == null || pane.shellIntegration.promptMarks.isEmpty) {
      return;
    }
    _replaceSessionPane(
      sessionId,
      pane.copyWith(
        shellIntegration: pane.shellIntegration.copyWith(
          promptMarks: const <TerminalShellPromptMark>[],
        ),
      ),
    );
  }

  Future<bool> closeTab(String tabSessionId) async {
    if (_isShuttingDown) {
      return false;
    }
    var tabIndex = state.tabs.indexWhere(
      (tab) => tab.sessionId == tabSessionId,
    );
    if (tabIndex == -1) {
      return false;
    }

    var closingTab = state.tabs[tabIndex];
    if (closingTab.effectivePanes.any(
      (pane) => _runtime.isZmodemTransferActive(pane.sessionId),
    )) {
      reportRuntimeError(
        'Cancel active ZMODEM transfers and wait for them to finish before '
        'closing this tab.',
      );
      return false;
    }
    final recordingsToResume = _activeRecordingPolicies(
      closingTab.effectivePanes.map((pane) => pane.sessionId),
    );
    final recordingSessionIds = closingTab.effectivePanes
        .map((pane) => pane.sessionId)
        .where(_recordingNeedsFinalization)
        .toList(growable: false);
    if (recordingSessionIds.isNotEmpty) {
      final finalized = await _finalizeSessionRecordings(recordingSessionIds);
      if (_isShuttingDown) {
        return false;
      }
      if (!finalized) {
        final finalizationError = state.lastError;
        await _resumeRecordingsAfterRejectedClose(recordingsToResume);
        if (_isShuttingDown) {
          return false;
        }
        // A successful sibling continuation must not erase the save/stop
        // error that rejected the tab close.
        state = state.copyWith(lastError: finalizationError);
        return false;
      }
    }
    // Recording finalization yields. Re-resolve the tab and repeat the
    // tab-wide guard at the actual close boundary so a newly started transfer
    // cannot slip into the sequential native close loop.
    tabIndex = state.tabs.indexWhere((tab) => tab.sessionId == tabSessionId);
    if (tabIndex == -1) {
      return false;
    }
    closingTab = state.tabs[tabIndex];
    if (closingTab.effectivePanes.any(
      (pane) => _runtime.isZmodemTransferActive(pane.sessionId),
    )) {
      final resumed = await _resumeRecordingsAfterRejectedClose(
        recordingsToResume,
      );
      if (_isShuttingDown) {
        return false;
      }
      reportRuntimeError(
        resumed
            ? 'Cancel active ZMODEM transfers before closing this tab. '
                  'Recording continued in new files.'
            : 'Cancel active ZMODEM transfers before closing this tab. One or '
                  'more recording continuations could not be started.',
      );
      return false;
    }
    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture == null) {
      final closedPaneIds = <String>[];
      for (final pane in closingTab.effectivePanes) {
        if (_isShuttingDown) {
          return false;
        }
        if (_runtime.hasSession(pane.sessionId)) {
          if (!_runtime.tryCloseSession(pane.sessionId)) {
            // Native close is intentionally per session. If a later pane turns
            // busy after earlier panes closed, immediately reconcile the UI
            // with those successful closes instead of leaving dead panes in
            // the tab. The remaining pane(s) stay reachable for retry.
            for (final closedSessionId in closedPaneIds) {
              _removeSessionState(closedSessionId);
            }
            final resumed = await _resumeRecordingsAfterRejectedClose(
              recordingsToResume,
            );
            if (_isShuttingDown) {
              return false;
            }
            reportRuntimeError(
              resumed
                  ? 'A native ZMODEM transfer or file publication is still '
                        'active. Recording continued in new files; cancel the '
                        'transfer and try closing the tab again.'
                  : 'A native ZMODEM transfer or file publication is still '
                        'active, and one or more recording continuations could '
                        'not be started.',
            );
            return false;
          }
          closedPaneIds.add(pane.sessionId);
        }
      }
    } else {
      for (final pane in closingTab.effectivePanes) {
        _demoViewports.remove(pane.sessionId)?.dispose();
      }
    }
    _removeTabState(tabIndex, recordClosedTab: true);
    if (demoFixture != null) {
      if (state.tabs.isEmpty) {
        _publishTerminalContent(
          terminalHasVisibleContent: false,
          terminalPreview: null,
        );
      } else {
        _publishDemoContent(demoFixture, state.activeSessionId);
      }
      return true;
    }
    if (state.activeSessionId == null) {
      _publishTerminalContent(
        terminalHasVisibleContent: false,
        terminalPreview: null,
      );
      return true;
    }
    final activePane = _paneForSession(state.activeSessionId!);
    if (activePane != null) {
      _setWindowTitle(activePane.title);
      _publishActiveTabTerminalContent();
    }
    return true;
  }

  void reopenClosedTab() {
    if (ref.read(sessionDemoFixtureProvider) != null) {
      return;
    }
    if (_recentlyClosedTabs.isEmpty) {
      return;
    }
    final closedTab = _recentlyClosedTabs.removeAt(0);
    final sourcePanes = closedTab.effectivePanes;
    final environmentOverrides = ref.read(sessionEnvironmentOverridesProvider);
    final reopenedPanes = <TerminalPane>[];
    final replacementsBySourceSessionId = <String, TerminalPane>{};
    String? activeSessionId;

    _ensureRuntimeSubscription();
    for (final sourcePane in sourcePanes) {
      final profile = _profileForClosedPane(sourcePane);
      if (profile == null) {
        continue;
      }
      final launchProfile = _profileWithSessionEnvironment(
        profile,
        environmentOverrides,
      );
      final sessionId = _createRuntimeSession(launchProfile);
      if (sessionId == null) {
        continue;
      }
      reopenedPanes.add(
        TerminalPane(
          sessionId: sessionId,
          title: sourcePane.title,
          profileId: profile.id,
          profileSnapshot: launchProfile,
          relaunchSpec: _relaunchSpecForLaunch(
            profileId: profile.id,
            launchProfile: launchProfile,
          ),
        ),
      );
      replacementsBySourceSessionId[sourcePane.sessionId] = reopenedPanes.last;
      if (sourcePane.sessionId == closedTab.activeSessionId) {
        activeSessionId = sessionId;
      }
    }

    if (reopenedPanes.isEmpty) {
      _recentlyClosedTabs.insert(0, closedTab);
      return;
    }
    activeSessionId ??= reopenedPanes.first.sessionId;
    final tabSessionId = reopenedPanes.first.sessionId;
    final reopenedLayout = _reopenedPaneLayout(
      closedTab.effectivePaneLayout,
      replacementsBySourceSessionId,
    );
    final layoutPanes = reopenedLayout?.panes ?? reopenedPanes;
    final reopenedTab = TerminalTab(
      sessionId: tabSessionId,
      title: closedTab.title,
      profileId: reopenedPanes.first.profileId,
      profileSnapshot: reopenedPanes.first.profileSnapshot,
      relaunchSpec: reopenedPanes.first.relaunchSpec,
      panes: layoutPanes,
      paneLayout: reopenedLayout,
      activePaneSessionId: activeSessionId == tabSessionId
          ? null
          : activeSessionId,
      splitAxis: closedTab.splitAxis,
    );

    state = state.copyWith(
      tabs: [...state.tabs, reopenedTab],
      activeSessionId: activeSessionId,
    );
    _syncRuntimeSessionActivation();
    final activePane = reopenedTab.paneFor(activeSessionId);
    _setWindowTitle(activePane?.title ?? reopenedTab.title);
  }

  String? reopenClosedPane({
    TerminalSplitAxis axis = TerminalSplitAxis.horizontal,
  }) {
    if (ref.read(sessionDemoFixtureProvider) != null) {
      return null;
    }
    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      return null;
    }
    final tabIndex = _tabIndexContainingSession(activeSessionId);
    if (tabIndex == -1) {
      return null;
    }

    final activeTab = state.tabs[tabIndex];
    final closedPanes = _recentlyClosedPanesByTab[activeTab.sessionId];
    if (closedPanes == null || closedPanes.isEmpty) {
      return null;
    }

    final sourcePane = closedPanes.first;
    final profile = _profileForClosedPane(sourcePane);
    if (profile == null) {
      return null;
    }

    _ensureRuntimeSubscription();
    final environmentOverrides = ref.read(sessionEnvironmentOverridesProvider);
    final launchProfile = _profileWithSessionEnvironment(
      profile,
      environmentOverrides,
    );
    final sessionId = _createRuntimeSession(launchProfile);
    if (sessionId == null) {
      return null;
    }
    final reopenedPane = TerminalPane(
      sessionId: sessionId,
      title: sourcePane.title,
      profileId: profile.id,
      profileSnapshot: launchProfile,
      relaunchSpec: _relaunchSpecForLaunch(
        profileId: profile.id,
        launchProfile: launchProfile,
      ),
    );
    final nextPaneLayout = activeTab.effectivePaneLayout.splitPane(
      sessionId: activeSessionId,
      newPane: reopenedPane,
      axis: axis,
    );
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = activeTab.copyWith(
      panes: nextPaneLayout.panes,
      paneLayout: nextPaneLayout,
      activePaneSessionId: sessionId,
      splitAxis: axis,
    );

    closedPanes.removeAt(0);
    if (closedPanes.isEmpty) {
      _recentlyClosedPanesByTab.remove(activeTab.sessionId);
    }

    state = state.copyWith(tabs: nextTabs, activeSessionId: sessionId);
    _syncRuntimeSessionActivation();
    _setWindowTitle(reopenedPane.title);
    return sessionId;
  }

  TerminalPaneLayoutNode? _reopenedPaneLayout(
    TerminalPaneLayoutNode source,
    Map<String, TerminalPane> replacementsBySourceSessionId,
  ) {
    if (source.isLeaf) {
      final replacement = replacementsBySourceSessionId[source.pane!.sessionId];
      return replacement == null
          ? null
          : TerminalPaneLayoutNode.leaf(replacement);
    }

    final first = _reopenedPaneLayout(
      source.first!,
      replacementsBySourceSessionId,
    );
    final second = _reopenedPaneLayout(
      source.second!,
      replacementsBySourceSessionId,
    );
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }

    return TerminalPaneLayoutNode.split(
      id: source.id,
      splitAxis: source.splitAxis!,
      first: first,
      second: second,
      ratio: source.ratio,
    );
  }

  TerminalProfile? _profileForClosedPane(TerminalPane pane) {
    if (pane.profileSnapshot != null) {
      return pane.profileSnapshot;
    }
    for (final profile in state.profiles) {
      if (profile.id == pane.profileId) {
        return profile;
      }
    }
    return null;
  }

  void resizeActiveSession(Size viewportSize, double devicePixelRatio) {
    final sessionId = state.activeSessionId;
    if (sessionId == null) {
      return;
    }
    resizeSession(sessionId, viewportSize, devicePixelRatio);
  }

  void resizeSession(
    String sessionId,
    Size viewportSize,
    double devicePixelRatio,
  ) {
    if (_isShuttingDown || !ref.mounted) return;
    if (ref.read(sessionDemoFixtureProvider) != null) {
      return;
    }
    if (_tabIndexContainingSession(sessionId) == -1) {
      return;
    }
    _runtime.resizeSession(sessionId, viewportSize, devicePixelRatio);
    _applyFrame(sessionId, _runtime.viewportFor(sessionId).frame);
  }

  TerminalUiEffectContext? _handleRuntimeEffect(TerminalBusinessEffect effect) {
    final signal = effect.signal;
    if (signal is TerminalRuntimeSessionEventSignal) {
      final uiContext = signal.payload is TerminalSessionExitEvent
          ? _exitUiContext(signal.sessionId)
          : null;
      _handleRuntimeEvent(signal.payload, exitClaim: effect.exitClaim);
      return uiContext;
    }
    return null;
  }

  TerminalSessionExitUiContext? _exitUiContext(String sessionId) {
    for (final tab in state.tabs) {
      final panes = tab.effectivePanes;
      final paneIndex = panes.indexWhere((pane) => pane.sessionId == sessionId);
      if (paneIndex >= 0) {
        return TerminalSessionExitUiContext(
          title: panes[paneIndex].title,
          paneIndex: paneIndex,
          paneCount: panes.length,
        );
      }
    }
    return null;
  }

  void _handleRuntimeEvent(
    TerminalSessionEvent event, {
    TerminalSessionExitClaim? exitClaim,
  }) {
    if (!ref.mounted) {
      return;
    }
    switch (event) {
      case TerminalSessionSshAuthPromptEvent():
        // ShellScreen owns the secure modal prompt and native response.
        break;
      case TerminalSessionSshHostKeyPromptEvent():
        // ShellScreen owns explicit host-key verification and native response.
        break;
      case TerminalSessionFrameEvent():
        _applyFrame(event.sessionId, event.frame);
      case TerminalSessionExitEvent():
        _shellContexts.remove(event.sessionId);
        final failedProfileId = _paneForSession(event.sessionId)?.profileId;
        final sshExitError = _sshExitErrorMessage(event);
        unawaited(
          _finalizeRecordingOnRuntimeExitBestEffort(
            event.sessionId,
            exitClaim: exitClaim,
          ),
        );
        _removeSessionState(event.sessionId, runtimeAlreadyClosed: true);
        if (sshExitError != null) {
          if (failedProfileId != null) {
            _lastSshExitFailure = (
              profileId: failedProfileId,
              message: sshExitError,
            );
          }
          state = state.copyWith(lastError: sshExitError);
        }
      case TerminalSessionBellEvent():
        break;
      case TerminalSessionShellHookEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        if (event.hook?.startsWith('bootstrap.') ?? false) {
          _applyBootstrapHook(event);
          return;
        }
        final shellPane = _paneForSession(event.sessionId);
        final shellProfile = shellPane?.profileSnapshot;
        if (shellPane?.shellIntegration.bootstrapPhase == 'checking' ||
            (shellPane?.shellIntegration.bootstrapPhase == null &&
                shellProfile?.isSsh == true &&
                shellProfile?.sessionConfig.shellIntegration.enabled == true &&
                shellProfile?.sessionConfig.shellIntegration.sshAutoInject !=
                    false)) {
          return;
        }
        final contextId = event.rawPayload['context_id'];
        if (contextId is String &&
            contextId !=
                (_paneForSession(event.sessionId)?.shellIntegration.contextId ??
                    'root')) {
          return;
        }
        _applyShellHook(event);
        _observeShellCapabilities(event);
      case TerminalSessionShellContextEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _applyShellContext(event);
        _observeShellCapabilities(event);
      case TerminalSessionShellCommandEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _applyShellCommand(event);
        _observeShellCapabilities(event);
      case TerminalSessionShellUserVarEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _applyShellUserVar(event);
        _observeShellCapabilities(event);
      case TerminalSessionAnnotationEvent():
        // ShellScreen owns the annotation sheet and terminal-range preview.
        break;
      case TerminalSessionNotificationEvent():
        _applySessionNotification(event);
      case TerminalSessionProgressEvent():
        _queueSessionProgress(event);
      case TerminalSessionBadgeEvent():
        _applySessionBadge(event);
      case TerminalSessionTabStatusEvent():
        _applySessionTabStatus(event);
      case TerminalSessionContextEvent():
        // OSC 3008 remains typed metadata only; it does not drive product UI.
        break;
      case TerminalSessionDragDropCommandEvent():
        // ShellScreen owns the system drag/drop bridge and active-pane routing.
        break;
      case TerminalSessionFileDownloadEvent():
      case TerminalSessionFileDownloadFailedEvent():
      case TerminalSessionFileUploadDeniedEvent():
        // ShellScreen owns explicit save consent and active-pane routing.
        break;
      case TerminalSessionCellSizeReportRequestEvent():
        // TerminalRuntimeController owns the immediate protocol reply.
        break;
      case TerminalSessionClearCapturedOutputEvent():
        // ShellScreen owns the product-scoped captured-output collection.
        break;
      case TerminalSessionReportVariableRequestEvent():
        _replyToOsc1337ReportVariable(event);
      case TerminalSessionOpenUrlRequestEvent():
        // ShellScreen owns active-pane policy and explicit host authorization.
        break;
      case TerminalSessionAttentionRequestEvent():
        // ShellScreen owns persisted policy, rate limiting, and cancellation.
        break;
      case TerminalSessionResetEvent():
        _applySessionReset(event);
      case TerminalSessionClipboardEvent():
        break;
      case TerminalSessionBackendErrorEvent():
        _applyBackendError(event);
    }
  }

  void _applyBackendError(TerminalSessionBackendErrorEvent event) {
    final operation = _boundedShellMetadata(event.operation, 80) ?? 'operation';
    final sessionId =
        _boundedShellMetadata(event.sessionId, 80) ?? event.sessionId;
    final detail = _boundedShellMetadata(event.error.toString(), 240);
    final message =
        'Terminal backend $operation failed for session $sessionId'
        '${detail == null ? '' : ': $detail'}';
    final pane = _paneForSession(event.sessionId);
    if (pane == null) {
      state = state.copyWith(lastError: message);
      return;
    }
    _replaceSessionPane(
      event.sessionId,
      pane.copyWith(
        runtimeError: TerminalPaneRuntimeErrorState(
          operation: operation,
          message: message,
        ),
      ),
    );
  }

  String? _sshExitErrorMessage(TerminalSessionExitEvent event) {
    final pane = _paneForSession(event.sessionId);
    final profile = pane?.profileSnapshot ?? _profileForPane(pane);
    if (profile == null || !profile.isSsh) {
      return null;
    }

    final detail = _sshFailureDetail(event.finalFrame);
    // The native SSH adapter reserves 255 for transport/setup failures. Other
    // remote exit codes are ordinary shell exits and must retain the existing
    // silent auto-close behavior.
    if (detail == null && event.exitCode != 255) {
      return null;
    }

    final connection = profile.connection;
    final host = connection.host.contains(':')
        ? '[${connection.host}]'
        : connection.host;
    final userPrefix = connection.user.trim().isEmpty
        ? ''
        : '${connection.user}@';
    final target = '$userPrefix$host:${connection.port}';
    final exitStatus = event.exitCode == null
        ? ''
        : ' (exit code ${event.exitCode})';
    final prefix =
        'SSH connection “${profile.name}” to $target failed$exitStatus';
    if (detail != null) {
      return '$prefix: $detail';
    }
    return '$prefix. Check the host, network, ProxyCommand, and authentication settings.';
  }

  void _clearMatchingSshExitFailureForRetry(TerminalProfile profile) {
    final failure = _lastSshExitFailure;
    if (!profile.isSsh ||
        failure == null ||
        failure.profileId != profile.id ||
        state.lastError != failure.message) {
      return;
    }
    _lastSshExitFailure = null;
    state = state.copyWith(lastError: null);
  }

  TerminalProfile? _profileForPane(TerminalPane? pane) {
    if (pane == null) {
      return null;
    }
    for (final profile in state.profiles) {
      if (profile.id == pane.profileId) {
        return profile;
      }
    }
    return null;
  }

  String? _sshFailureDetail(TerminalFrameDiff? frame) {
    if (frame == null || frame.rows.isEmpty) {
      return null;
    }
    const marker = 'Ianvs SSH:';
    for (final line in _logicalFrameLines(frame).reversed) {
      final markerIndex = line.indexOf(marker);
      if (markerIndex == -1) {
        continue;
      }
      return _boundedShellMetadata(
        line.substring(markerIndex + marker.length),
        240,
      );
    }
    return null;
  }

  List<String> _logicalFrameLines(TerminalFrameDiff frame) {
    final lines = <String>[];
    var start = 0;
    while (start < frame.rows.length) {
      final buffer = StringBuffer(frame.rows[start].text);
      var end = start;
      while (end < frame.rows.length - 1 && frame.rows[end].wrapped) {
        end += 1;
        buffer.write(frame.rows[end].text);
      }
      lines.add(buffer.toString());
      start = end + 1;
    }
    return lines;
  }

  void _applyFrame(String sessionId, TerminalFrameDiff frame) {
    _updateTabTitleFromFrame(
      sessionId,
      windowTitle: frame.windowTitle,
      windowIconName: frame.windowIconName,
    );

    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      _publishTerminalContent(
        terminalHasVisibleContent: false,
        terminalPreview: null,
      );
      return;
    }
    final activeTabIndex = _tabIndexContainingSession(activeSessionId);
    if (activeTabIndex == -1 ||
        !state.tabs[activeTabIndex].containsSession(sessionId)) {
      return;
    }

    _publishActiveTabTerminalContent(
      updatedSessionId: sessionId,
      updatedFrame: frame,
    );
  }

  void _applyBootstrapHook(TerminalSessionShellHookEvent event) {
    final pane = _paneForSession(event.sessionId);
    final id = event.rawPayload['context_id'];
    if (pane == null || id is! String || id.isEmpty || id.length > 64) return;
    final contexts = _shellContexts.putIfAbsent(event.sessionId, () => {});
    final current = pane.shellIntegration.copyWith(
      connectionChain: pane.shellConnectionChain,
    );
    contexts[current.contextId ?? 'root'] = current;
    if (contexts.length > 128) return;
    TerminalShellIntegrationSnapshot next;
    if (event.hook == 'bootstrap.resume') {
      final previous = contexts[id];
      if (previous == null) return;
      next = previous;
      final retired = event.rawPayload['retired_contexts'];
      if (retired is List) {
        for (final context in retired.whereType<String>().take(128)) {
          if (context != id) contexts.remove(context);
        }
      }
    } else if (event.hook == 'bootstrap.checking') {
      next = TerminalShellIntegrationSnapshot(
        contextId: id,
        bootstrapPhase: 'checking',
      );
    } else if (event.hook == 'bootstrap.ready') {
      final checks = event.rawPayload['checks'];
      next =
          (current.contextId == id
                  ? current
                  : TerminalShellIntegrationSnapshot(contextId: id))
              .copyWith(
                bootstrapPhase: event.rawPayload['registered'] == true
                    ? 'ready'
                    : 'degraded',
                bootstrapSource: switch (event.rawPayload['source']) {
                  final String value => value,
                  _ => 'unknown',
                },
                registrationChecks: checks is Map
                    ? Map.unmodifiable({
                        for (final capability
                            in ShellIntegrationCapability.values)
                          capability.id: switch (checks[capability.id]) {
                            final String value
                                when const {
                                  'registered',
                                  'unavailable',
                                  'unverified',
                                }.contains(value) =>
                              value,
                            _ => 'unknown',
                          },
                      })
                    : const {},
                shell: event.shell,
              );
      next = next.copyWith(
        capabilities: next.capabilities.applyRegistration(
          next.registrationChecks,
        ),
      );
    } else {
      return;
    }
    next = next.copyWith(
      contextId: id,
      contextKind: switch (event.rawPayload['context_kind']) {
        final String value
            when const {'root', 'ssh', 'shell'}.contains(value) =>
          value,
        _ => null,
      },
      hostContextId: switch (event.rawPayload['host_context_id']) {
        final String value when value.isNotEmpty && value.length <= 64 => value,
        _ => null,
      },
      sftpRoute: event.rawPayload['sftp_route'] == true,
      sshHost: switch (event.rawPayload['host']) {
        final String value => value,
        _ => null,
      },
      sshUser: switch (event.rawPayload['user']) {
        final String value => value,
        _ => null,
      },
      sshPort: switch (event.rawPayload['port']) {
        final int value => value,
        _ => null,
      },
    );
    var chain = contexts[id]?.connectionChain ?? const <ShellConnectionHop>[];
    if (chain.isEmpty) {
      if (id == 'root') {
        chain = ShellConnectionHop.forProfile(pane.profileSnapshot);
      } else {
        final parentId = event.rawPayload['parent_context_id'];
        final parent = contexts[parentId] ?? current;
        chain = [
          ...parent.connectionChain,
          if (next.contextKind != 'shell')
            ShellConnectionHop(
              kind: ShellConnectionHopKind.sshShell,
              contextId: id,
            ),
        ];
      }
    }
    next = next.copyWith(
      connectionChain: List.unmodifiable([
        for (final hop in chain)
          if (hop.contextId == id &&
              hop.kind == ShellConnectionHopKind.sshShell &&
              next.sshHost?.isNotEmpty == true)
            ShellConnectionHop(
              kind: hop.kind,
              contextId: id,
              host: next.sshHost,
              user: next.sshUser,
              port: next.sshPort,
            )
          else
            hop,
      ]),
    );
    contexts[id] = next;
    _replaceSessionPane(event.sessionId, pane.copyWith(shellIntegration: next));
  }

  void _applyShellHook(TerminalSessionShellHookEvent event) {
    final tabIndex = _tabIndexContainingSession(event.sessionId);
    if (tabIndex == -1) {
      return;
    }

    final currentTab = state.tabs[tabIndex];
    final currentPane = currentTab.paneFor(event.sessionId);
    if (currentPane == null) {
      return;
    }

    final nextIntegration = _shellIntegrationForHook(
      currentPane.shellIntegration,
      event,
      frame: _runtime.viewportFor(event.sessionId).frame,
    );
    final nextTabs = <TerminalTab>[...state.tabs];
    if (currentTab.panes.isEmpty && currentTab.sessionId == event.sessionId) {
      nextTabs[tabIndex] = currentTab.copyWith(
        shellIntegration: nextIntegration,
      );
    } else {
      nextTabs[tabIndex] = currentTab.replacePane(
        currentPane.copyWith(shellIntegration: nextIntegration),
      );
    }
    state = state.copyWith(tabs: nextTabs);
    _applyAutomaticProfileSwitch(event.sessionId, nextIntegration);
  }

  void _observeShellCapabilities(TerminalSessionEvent event) {
    final pane = _paneForSession(event.sessionId);
    if (pane == null) return;
    var promptMarkRecorded = false;
    if (event is TerminalSessionShellHookEvent) {
      final offset = event.promptScrollbackOffset;
      if (offset != null) {
        final frame = _runtime.viewportFor(event.sessionId).frame;
        final line = terminalPromptGlobalLineFromScrollbackOffset(
          globalBottomRow: frame.globalBottomRow,
          scrollbackMaxOffset: frame.scrollbackMaxOffset,
          scrollbackOffset: offset,
        );
        promptMarkRecorded =
            line != null &&
            pane.shellIntegration.promptMarks.any(
              (mark) => mark.globalLine == line,
            );
      }
    }
    final before = pane.shellCapabilities;
    final after = before.observe(event, promptMarkRecorded: promptMarkRecorded);
    if (identical(before, after)) return;
    _replaceSessionPane(
      event.sessionId,
      pane.copyWith(
        shellIntegration: pane.shellIntegration.copyWith(capabilities: after),
      ),
    );
  }

  void _applyShellContext(TerminalSessionShellContextEvent event) {
    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    final cwd = _boundedShellMetadata(event.cwd, 1024);
    final hostname = _boundedShellMetadata(event.hostname, 255);
    final username = _boundedShellMetadata(event.username, 255);
    final hostnameIsAuthoritative = event.rawPayload.containsKey('hostname');
    final usernameIsAuthoritative = event.rawPayload.containsKey('username');
    if (cwd == null && hostname == null && username == null) {
      if (!hostnameIsAuthoritative && !usernameIsAuthoritative) {
        return;
      }
    }
    final nextDirectories = _prependRecentShellValue(
      currentPane.shellIntegration.recentDirectories,
      cwd,
      limit: 40,
    );
    final nextIntegration = currentPane.shellIntegration.copyWith(
      currentDirectory: cwd ?? currentPane.shellIntegration.currentDirectory,
      hostname: hostnameIsAuthoritative
          ? hostname
          : currentPane.shellIntegration.hostname,
      username: usernameIsAuthoritative
          ? username
          : currentPane.shellIntegration.username,
      recentDirectories: nextDirectories,
    );
    _replaceSessionPane(
      event.sessionId,
      currentPane.copyWith(shellIntegration: nextIntegration),
    );
    _applyAutomaticProfileSwitch(event.sessionId, nextIntegration);
  }

  void _applyShellCommand(TerminalSessionShellCommandEvent event) {
    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    final eventType = _boundedShellMetadata(event.eventType, 64);
    if (eventType == null) {
      return;
    }
    final current = currentPane.shellIntegration;
    final command =
        _boundedShellMetadata(event.command, 512) ?? current.lastCommand;
    if (eventType == 'zone_scrolled_out') {
      final zoneId = event.zoneId;
      if (zoneId == null || current.promptMarks.isEmpty) {
        return;
      }
      final retainedMarks = current.promptMarks
          .where((mark) => mark.zoneId != zoneId)
          .toList(growable: false);
      if (retainedMarks.length == current.promptMarks.length) {
        return;
      }
      _replaceSessionPane(
        event.sessionId,
        currentPane.copyWith(
          shellIntegration: current.copyWith(promptMarks: retainedMarks),
        ),
      );
      return;
    }
    final globalLine = event.cursorLine;
    var nextPromptMarks =
        (eventType == 'prompt_start' || eventType == 'mark') &&
            globalLine != null
        ? _promptMarksForValues(
            current.promptMarks,
            globalLine: globalLine,
            command: command,
            cwd: current.currentDirectory,
            promptKind: _boundedShellMetadata(event.promptKind, 32),
            aid: _boundedShellMetadata(event.aid, 256),
            parentAid: _boundedShellMetadata(event.parentAid, 256),
          )
        : current.promptMarks;
    if (eventType == 'integration_version') {
      final version = _boundedShellMetadata(event.integrationVersion, 32);
      final shell = _boundedShellMetadata(event.shell, 32);
      if (version == null && shell == null) {
        return;
      }
      _replaceSessionPane(
        event.sessionId,
        currentPane.copyWith(
          shellIntegration: current.copyWith(
            shell: shell ?? current.shell,
            integrationVersion: version ?? current.integrationVersion,
          ),
        ),
      );
      return;
    }
    if (eventType == 'zone_opened' &&
        event.zoneType == 'prompt' &&
        event.zoneId != null &&
        event.absRowStart != null) {
      nextPromptMarks = _bindPromptZone(
        nextPromptMarks,
        zoneId: event.zoneId!,
        globalLine: event.absRowStart!,
        command: command,
        cwd: current.currentDirectory,
      );
    }
    final shouldTrackCommand =
        eventType == 'command_start' ||
        eventType == 'command_executed' ||
        eventType == 'command_finished' ||
        (eventType == 'zone_closed' && event.zoneType == 'output');
    if (!shouldTrackCommand &&
        eventType != 'prompt_start' &&
        identical(nextPromptMarks, current.promptMarks)) {
      return;
    }
    final nextCommands = _prependRecentShellValue(
      current.recentCommands,
      shouldTrackCommand ? command : null,
      limit: 40,
    );
    final nextIntegration = current
        .copyWith(
          lastCommand: shouldTrackCommand ? command : current.lastCommand,
          lastExitCode: event.exitCode ?? current.lastExitCode,
          recentCommands: nextCommands,
          promptMarks: nextPromptMarks,
        )
        .observeExecution(
          phase: eventType,
          command: _boundedShellMetadata(event.command, 512),
          now: ref.read(sessionCommandClockProvider)(),
        );
    _replaceSessionPane(
      event.sessionId,
      currentPane.copyWith(shellIntegration: nextIntegration),
    );
  }

  void _applyShellUserVar(TerminalSessionShellUserVarEvent event) {
    final name = _boundedShellMetadata(event.name, 80);
    final value = _boundedShellMetadata(event.value, 512);
    if (name == null || value == null || !_oscUserVarAllowed(name)) {
      return;
    }
    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    final nextVariables = <String, String>{
      ...currentPane.shellIntegration.userVariables,
      name: value,
    };
    final nextIntegration = currentPane.shellIntegration.copyWith(
      userVariables: Map.unmodifiable(nextVariables),
    );
    _replaceSessionPane(
      event.sessionId,
      currentPane.copyWith(shellIntegration: nextIntegration),
    );
  }

  void _replyToOsc1337ReportVariable(
    TerminalSessionReportVariableRequestEvent event,
  ) {
    ({String? value, bool useNativeValue}) resolution = (
      value: null,
      useNativeValue: false,
    );
    if (event.isSupported &&
        _localConfigDocument.hostActions.osc1337ReportVariables[event.name!] ==
            LocalTerminalReportVariablePolicy.allow) {
      resolution = _resolvedOsc1337ReportVariable(event);
    }
    final responded = _runtime.respondToOsc1337ReportVariable(
      event,
      value: resolution.value,
      useNativeResolvedValue: resolution.useNativeValue,
    );
    if (!responded && resolution.value != null) {
      // A product-owned value can still exceed the runtime's defensive reply
      // bound. The one-shot request remains pending in that case, so end it
      // with the protocol-defined empty value instead of leaving the caller
      // waiting indefinitely.
      _runtime.respondToOsc1337ReportVariable(event);
    }
  }

  ({String? value, bool useNativeValue}) _resolvedOsc1337ReportVariable(
    TerminalSessionReportVariableRequestEvent event,
  ) {
    final pane = _paneForSession(event.sessionId);
    if (pane == null) {
      return (value: null, useNativeValue: false);
    }
    final frame = _runtime.viewportFor(event.sessionId).frame;
    return switch (event.name) {
      'session.name' when pane.title.isNotEmpty => (
        value: pane.title,
        useNativeValue: false,
      ),
      'session.name' => (value: null, useNativeValue: true),
      'session.terminalIconName' => (
        value: frame.windowIconName,
        useNativeValue: false,
      ),
      'session.terminalWindowName' => (
        value: frame.windowTitle,
        useNativeValue: false,
      ),
      'session.columns' when frame.viewportCols > 0 => (
        value: frame.viewportCols.toString(),
        useNativeValue: false,
      ),
      'session.rows' when frame.viewportRows > 0 => (
        value: frame.viewportRows.toString(),
        useNativeValue: false,
      ),
      'session.hostname' when pane.shellIntegration.hostname != null => (
        value: pane.shellIntegration.hostname,
        useNativeValue: false,
      ),
      'session.hostname' => (value: null, useNativeValue: true),
      'session.lastCommand' => (
        value: pane.shellIntegration.lastCommand,
        useNativeValue: false,
      ),
      'session.username' when pane.shellIntegration.username != null => (
        value: pane.shellIntegration.username,
        useNativeValue: false,
      ),
      'session.username' => (value: null, useNativeValue: true),
      'session.path' when pane.shellIntegration.currentDirectory != null => (
        value: pane.shellIntegration.currentDirectory,
        useNativeValue: false,
      ),
      'session.path' => (value: null, useNativeValue: true),
      'session.shell' => (
        value: pane.shellIntegration.shell,
        useNativeValue: false,
      ),
      'session.badge' => (value: pane.oscBadge, useNativeValue: false),
      'session.profileName' => (
        value: pane.profileSnapshot?.name,
        useNativeValue: false,
      ),
      final name? when name.startsWith('user.') => (
        value: pane.shellIntegration.userVariables[name.substring(5)],
        useNativeValue: true,
      ),
      _ => (value: null, useNativeValue: false),
    };
  }

  void _applySessionNotification(TerminalSessionNotificationEvent event) {
    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    final source = _boundedShellMetadata(event.source, 48) ?? 'osc';
    final identifier = source == 'osc99'
        ? _boundedOsc99Identifier(event.identifier)
        : _boundedShellMetadata(event.identifier, 128);
    if (event.isClose) {
      if (identifier == null) {
        return;
      }
      _notificationExpiryTimers
          .remove(_notificationExpiryKey(event.sessionId, identifier))
          ?.cancel();
      final nextNotifications = currentPane.recentNotifications
          .where(
            (notification) =>
                notification.identifier != identifier ||
                notification.source != 'osc99',
          )
          .toList(growable: false);
      if (nextNotifications.length == currentPane.recentNotifications.length) {
        return;
      }
      _replaceSessionPane(
        event.sessionId,
        currentPane.copyWith(recentNotifications: nextNotifications),
      );
      return;
    }
    final title =
        _boundedShellMetadata(event.title, 160) ?? 'Terminal notification';
    final message = _boundedShellMetadata(event.message, 512) ?? '';
    final applicationName = _boundedShellMetadata(event.applicationName, 160);
    final notificationTypes = event.notificationTypes
        .map((value) => _boundedShellMetadata(value, 64))
        .whereType<String>()
        .take(8)
        .toList(growable: false);
    final expiresAfterMs = event.expiresAfterMs?.clamp(0, 0xFFFFFFFF);
    final buttons = event.buttons
        .take(5)
        .map((value) => _boundedShellMetadata(value, 64) ?? '')
        .toList(growable: false);
    final remoteHost = _isRemoteShellHost(currentPane.shellIntegration.hostname)
        ? _boundedShellMetadata(currentPane.shellIntegration.hostname, 255)
        : null;
    final remoteUser = remoteHost == null
        ? null
        : _boundedShellMetadata(currentPane.shellIntegration.username, 255);
    final recent = currentPane.recentNotifications;
    final isDuplicate =
        identifier == null &&
        source != 'osc99' &&
        recent.isNotEmpty &&
        recent.first.source == source &&
        recent.first.identifier == identifier &&
        recent.first.title == title &&
        recent.first.message == message &&
        recent.first.applicationName == applicationName &&
        _sameNotificationTypes(
          recent.first.notificationTypes,
          notificationTypes,
        ) &&
        recent.first.reportActivation == event.reportActivation &&
        recent.first.reportClose == event.reportClose &&
        _sameNotificationTypes(recent.first.buttons, buttons) &&
        recent.first.remoteHost == remoteHost &&
        recent.first.remoteUser == remoteUser;
    final correlatedIndex = identifier == null
        ? -1
        : recent.indexWhere(
            (notification) =>
                notification.source == source &&
                notification.identifier == identifier,
          );
    final correlated = correlatedIndex == -1 ? null : recent[correlatedIndex];
    final nextNotification = TerminalPaneNotificationState(
      source: source,
      identifier: identifier,
      title: title,
      message: message,
      applicationName: applicationName,
      notificationTypes: notificationTypes,
      expiresAfterMs: expiresAfterMs,
      reportActivation: event.reportActivation,
      reportClose: event.reportClose,
      buttons: buttons,
      remoteHost: remoteHost,
      remoteUser: remoteUser,
      count: correlated?.count ?? 1,
    );
    final nextNotifications = <TerminalPaneNotificationState>[
      if (isDuplicate)
        recent.first.copyWith(count: recent.first.count + 1)
      else
        nextNotification,
      for (var index = isDuplicate ? 1 : 0; index < recent.length; index += 1)
        if (index != correlatedIndex) recent[index],
    ].take(20).toList(growable: false);
    _replaceSessionPane(
      event.sessionId,
      currentPane.copyWith(recentNotifications: nextNotifications),
    );
    if (identifier != null) {
      final expiryKey = _notificationExpiryKey(event.sessionId, identifier);
      _notificationExpiryTimers.remove(expiryKey)?.cancel();
      if (expiresAfterMs != null && expiresAfterMs > 0) {
        _notificationExpiryTimers[expiryKey] = Timer(
          Duration(milliseconds: expiresAfterMs),
          () {
            _notificationExpiryTimers.remove(expiryKey);
            if (!ref.mounted) {
              return;
            }
            final pane = _paneForSession(event.sessionId);
            if (pane == null) {
              return;
            }
            final retained = pane.recentNotifications
                .where(
                  (notification) =>
                      notification.identifier != identifier ||
                      notification.source != source,
                )
                .toList(growable: false);
            if (retained.length != pane.recentNotifications.length) {
              final expiring = pane.recentNotifications.where(
                (notification) =>
                    notification.identifier == identifier &&
                    notification.source == source,
              );
              if (source == 'osc99') {
                _runtime.dismissOsc99Notification(event.sessionId, identifier);
              }
              if (expiring.any((notification) => notification.reportClose)) {
                _sendOsc99NotificationReport(
                  event.sessionId,
                  identifier,
                  close: true,
                );
              }
              _replaceSessionPane(
                event.sessionId,
                pane.copyWith(recentNotifications: retained),
              );
            }
          },
        );
      }
    }
  }

  bool _sameNotificationTypes(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  String _notificationExpiryKey(String sessionId, String identifier) =>
      '$sessionId:$identifier';

  bool reportSessionNotificationAction(
    String sessionId,
    TerminalPaneNotificationState expectedNotification, {
    int? buttonNumber,
  }) {
    final pane = _paneForSession(sessionId);
    if (pane == null) {
      return false;
    }
    if (expectedNotification.source != 'osc99' ||
        expectedNotification.identifier == null ||
        !pane.recentNotifications.any(
          (notification) => identical(notification, expectedNotification),
        ) ||
        !expectedNotification.reportActivation) {
      return false;
    }
    if (buttonNumber != null &&
        (buttonNumber < 1 ||
            buttonNumber > expectedNotification.buttons.length)) {
      return false;
    }
    return _sendOsc99NotificationReport(
      sessionId,
      expectedNotification.identifier!,
      buttonNumber: buttonNumber,
    );
  }

  bool dismissSessionNotification(
    String sessionId,
    TerminalPaneNotificationState expectedNotification,
  ) {
    final pane = _paneForSession(sessionId);
    if (pane == null ||
        !pane.recentNotifications.any(
          (notification) => identical(notification, expectedNotification),
        )) {
      return false;
    }
    final identifier = expectedNotification.identifier;
    final retained = pane.recentNotifications
        .where((notification) => !identical(notification, expectedNotification))
        .toList(growable: false);
    if (identifier != null) {
      _notificationExpiryTimers
          .remove(_notificationExpiryKey(sessionId, identifier))
          ?.cancel();
      if (expectedNotification.source == 'osc99') {
        _runtime.dismissOsc99Notification(sessionId, identifier);
      }
    }
    _replaceSessionPane(
      sessionId,
      pane.copyWith(recentNotifications: retained),
    );
    if (expectedNotification.source == 'osc99' &&
        identifier != null &&
        expectedNotification.reportClose) {
      _sendOsc99NotificationReport(sessionId, identifier, close: true);
    }
    return true;
  }

  bool _sendOsc99NotificationReport(
    String sessionId,
    String identifier, {
    int? buttonNumber,
    bool close = false,
  }) {
    if ((close && buttonNumber != null) ||
        !_runtime.hasSession(sessionId) ||
        _boundedOsc99Identifier(identifier) != identifier) {
      return false;
    }
    final metadata = close ? 'i=$identifier:p=close' : 'i=$identifier';
    final payload = buttonNumber?.toString() ?? '';
    _runtime.sendInput(
      sessionId,
      Uint8List.fromList(utf8.encode('\x1b]99;$metadata;$payload\x1b\\')),
    );
    return true;
  }

  void _applySessionBadge(TerminalSessionBadgeEvent event) {
    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    final text = _boundedShellMetadata(event.text, 80);
    _replaceSessionPane(event.sessionId, currentPane.copyWith(oscBadge: text));
  }

  void _applySessionTabStatus(TerminalSessionTabStatusEvent event) {
    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    var next = currentPane.tabStatus;
    if (event.indicatorPresent) {
      next = next.copyWith(indicator: event.indicator);
    }
    if (event.statusPresent) {
      next = next.copyWith(status: _boundedShellMetadata(event.status, 256));
    }
    if (event.statusColorPresent) {
      next = next.copyWith(statusColor: event.statusColor);
    }
    _replaceSessionPane(event.sessionId, currentPane.copyWith(tabStatus: next));
  }

  void _applySessionReset(TerminalSessionResetEvent event) {
    _shellContexts.remove(event.sessionId);
    _clearNotificationTrackingForSession(event.sessionId);
    final progressKeyPrefix = '${event.sessionId}:';
    _pendingProgressEvents.removeWhere(
      (key, _) => key.startsWith(progressKeyPrefix),
    );
    final graceKeys = _progressGraceTimers.keys
        .where((key) => key.startsWith(progressKeyPrefix))
        .toList(growable: false);
    for (final key in graceKeys) {
      _progressGraceTimers.remove(key)?.cancel();
    }

    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    final nextIntegration = currentPane.shellIntegration.copyWith(
      capabilities: const ShellIntegrationCapabilities.pending(),
      currentDirectory: null,
      hostname: null,
      username: null,
      lastCommand: null,
      runningCommand: null,
      commandStartedAt: null,
      lastExitCode: null,
      recentCommands: const <String>[],
      recentDirectories: const <String>[],
      promptMarks: const <TerminalShellPromptMark>[],
      userVariables: const <String, String>{},
    );
    _replaceSessionPane(
      event.sessionId,
      currentPane.copyWith(
        shellIntegration: nextIntegration,
        oscBadge: null,
        tabStatus: const TerminalPaneTabStatusState(),
        progress: null,
        namedProgress: const <String, TerminalPaneProgressState>{},
        recentNotifications: const <TerminalPaneNotificationState>[],
      ),
    );
    _applyAutomaticProfileSwitch(event.sessionId, nextIntegration);
    // A reset frame carries no OSC title/icon. Resolve that absence back to
    // the active profile/process baseline instead of retaining the last OSC 2.
    _updateTabTitleFromFrame(event.sessionId);
  }

  void _applySessionProgress(TerminalSessionProgressEvent event) {
    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    if (event.named) {
      _applyNamedSessionProgress(event, currentPane);
      return;
    }
    _progressGraceTimers.remove(_progressGraceKey(event.sessionId))?.cancel();
    final progress = _progressStateForEvent(event);
    if (progress == null) {
      final currentProgress = currentPane.progress;
      if (currentProgress != null && currentProgress.active) {
        final completedProgress = _completedProgress(currentProgress);
        _replaceSessionPane(
          event.sessionId,
          currentPane.copyWith(progress: completedProgress),
        );
        _scheduleProgressGraceClear(event.sessionId);
        return;
      }
    }
    _replaceSessionPane(
      event.sessionId,
      currentPane.copyWith(progress: progress),
    );
  }

  void _applyNamedSessionProgress(
    TerminalSessionProgressEvent event,
    TerminalPane currentPane,
  ) {
    final action = _boundedShellMetadata(event.action, 32);
    if (action == 'remove_all') {
      final completed = <String, TerminalPaneProgressState>{};
      for (final entry in currentPane.namedProgress.entries) {
        if (entry.value.active) {
          completed[entry.key] = _completedProgress(entry.value);
          _scheduleProgressGraceClear(event.sessionId, id: entry.key);
        }
      }
      _replaceSessionPane(
        event.sessionId,
        currentPane.copyWith(namedProgress: Map.unmodifiable(completed)),
      );
      return;
    }

    final id = _osc934ProgressId(event.id);
    if (id == null) {
      return;
    }
    _progressGraceTimers
        .remove(_progressGraceKey(event.sessionId, id))
        ?.cancel();
    final progress = _progressStateForEvent(event);
    final next = <String, TerminalPaneProgressState>{
      ...currentPane.namedProgress,
    };
    if (action == 'remove' || progress == null) {
      final current = next[id];
      if (current != null && current.active) {
        next[id] = _completedProgress(current);
        _replaceSessionPane(
          event.sessionId,
          currentPane.copyWith(namedProgress: Map.unmodifiable(next)),
        );
        _scheduleProgressGraceClear(event.sessionId, id: id);
        return;
      }
      next.remove(id);
    } else {
      next
        ..remove(id)
        ..[id] = progress;
      while (next.length > 8) {
        next.remove(next.keys.first);
      }
    }
    _replaceSessionPane(
      event.sessionId,
      currentPane.copyWith(namedProgress: Map.unmodifiable(next)),
    );
  }

  void _scheduleProgressGraceClear(String sessionId, {String? id}) {
    final key = _progressGraceKey(sessionId, id);
    _progressGraceTimers.remove(key)?.cancel();
    _progressGraceTimers[key] = Timer(const Duration(milliseconds: 1400), () {
      _progressGraceTimers.remove(key);
      if (!ref.mounted) {
        return;
      }
      final pane = _paneForSession(sessionId);
      if (pane == null) {
        return;
      }
      if (id == null) {
        if (pane.progress?.action != 'complete') {
          return;
        }
        _replaceSessionPane(sessionId, pane.copyWith(progress: null));
        return;
      }
      if (pane.namedProgress[id]?.action != 'complete') {
        return;
      }
      final next = <String, TerminalPaneProgressState>{...pane.namedProgress}
        ..remove(id);
      _replaceSessionPane(
        sessionId,
        pane.copyWith(namedProgress: Map.unmodifiable(next)),
      );
    });
  }

  TerminalPaneProgressState _completedProgress(
    TerminalPaneProgressState progress,
  ) {
    return progress.copyWith(
      action: 'complete',
      state: 'complete',
      percent: 100,
    );
  }

  void _queueSessionProgress(TerminalSessionProgressEvent event) {
    final key = _progressEventKey(event);
    _pendingProgressEvents[key] = (
      order: _progressEventOrder += 1,
      event: event,
    );
    if (_progressFlushScheduled) {
      return;
    }
    _progressFlushScheduled = true;
    scheduleMicrotask(_flushPendingProgressEvents);
  }

  void _flushPendingProgressEvents() {
    _progressFlushScheduled = false;
    if (!ref.mounted) {
      _pendingProgressEvents.clear();
      return;
    }
    final entries = _pendingProgressEvents.values.toList(growable: false)
      ..sort((a, b) => a.order.compareTo(b.order));
    _pendingProgressEvents.clear();
    for (final entry in entries) {
      _applySessionProgress(entry.event);
    }
  }

  String _progressEventKey(TerminalSessionProgressEvent event) {
    if (!event.named) {
      return '${event.sessionId}:primary';
    }
    final action = event.action ?? '';
    if (action == 'remove_all') {
      return '${event.sessionId}:named:*';
    }
    return '${event.sessionId}:named:${_osc934ProgressId(event.id) ?? action}';
  }

  String _progressGraceKey(String sessionId, [String? id]) {
    return id == null ? '$sessionId:primary' : '$sessionId:named:$id';
  }

  TerminalPaneProgressState? _progressStateForEvent(
    TerminalSessionProgressEvent event,
  ) {
    if (!event.active) {
      return null;
    }
    return TerminalPaneProgressState(
      source: _boundedShellMetadata(event.source, 48) ?? 'osc',
      named: event.named,
      action: _boundedShellMetadata(event.action, 32) ?? 'set',
      id: _osc934ProgressId(event.id),
      state: _boundedShellMetadata(event.state, 32),
      percent: event.percent?.clamp(0, 100),
      label: _boundedShellMetadata(event.label, 160),
    );
  }

  TerminalShellIntegrationSnapshot _shellIntegrationForHook(
    TerminalShellIntegrationSnapshot current,
    TerminalSessionShellHookEvent event, {
    required TerminalFrameDiff frame,
  }) {
    final command = _boundedShellMetadata(event.command, 512);
    final cwd = _boundedShellMetadata(event.cwd, 1024);
    final hostname = _boundedShellMetadata(event.hostname, 255);
    final username = _boundedShellMetadata(event.username, 255);
    final shell = _boundedShellMetadata(event.shell, 80);
    final nextCommands = _prependRecentShellValue(
      current.recentCommands,
      command,
      limit: 40,
    );
    final nextDirectories = _prependRecentShellValue(
      current.recentDirectories,
      cwd,
      limit: 40,
    );
    final nextCurrentDirectory = cwd ?? current.currentDirectory;
    final nextPromptMarks = _promptMarksForHook(
      current.promptMarks,
      event,
      frame: frame,
      command: command ?? current.lastCommand,
      cwd: nextCurrentDirectory,
    );

    return current
        .copyWith(
          currentDirectory: nextCurrentDirectory,
          hostname: hostname ?? current.hostname,
          username: username ?? current.username,
          shell: shell ?? current.shell,
          lastCommand: command ?? current.lastCommand,
          lastExitCode: event.exitCode ?? current.lastExitCode,
          recentCommands: nextCommands,
          recentDirectories: nextDirectories,
          promptMarks: nextPromptMarks,
        )
        .observeExecution(
          phase: event.hook?.trim().toLowerCase(),
          command: command,
          now: ref.read(sessionCommandClockProvider)(),
        );
  }

  List<TerminalShellPromptMark> _promptMarksForHook(
    List<TerminalShellPromptMark> current,
    TerminalSessionShellHookEvent event, {
    required TerminalFrameDiff frame,
    required String? command,
    required String? cwd,
  }) {
    final promptOffset = event.promptScrollbackOffset;
    if (promptOffset == null || promptOffset < 0) {
      return current;
    }
    final globalLine = terminalPromptGlobalLineFromScrollbackOffset(
      globalBottomRow: frame.globalBottomRow,
      scrollbackMaxOffset: frame.scrollbackMaxOffset,
      scrollbackOffset: promptOffset,
    );
    if (globalLine == null) {
      return current;
    }
    return _promptMarksForValues(
      current,
      globalLine: globalLine,
      command: command,
      cwd: cwd,
    );
  }

  List<TerminalShellPromptMark> _promptMarksForValues(
    List<TerminalShellPromptMark> current, {
    required int globalLine,
    int? zoneId,
    required String? command,
    required String? cwd,
    String? promptKind,
    String? aid,
    String? parentAid,
  }) {
    if (globalLine < 0 || (zoneId != null && zoneId < 0)) {
      return current;
    }
    final nextMarks = <TerminalShellPromptMark>[
      for (final mark in current)
        if (zoneId != null
            ? mark.zoneId != zoneId &&
                  !(mark.zoneId == null && mark.globalLine == globalLine)
            : !(mark.zoneId == null && mark.globalLine == globalLine))
          mark,
      TerminalShellPromptMark(
        globalLine: globalLine,
        zoneId: zoneId,
        command: command,
        cwd: cwd,
        promptKind: promptKind,
        aid: aid,
        parentAid: parentAid,
      ),
    ];
    final boundedMarks = nextMarks.length > 100
        ? nextMarks.sublist(nextMarks.length - 100)
        : nextMarks;
    boundedMarks.sort(_comparePromptMarks);
    return boundedMarks;
  }

  int _comparePromptMarks(
    TerminalShellPromptMark left,
    TerminalShellPromptMark right,
  ) {
    return left.globalLine.compareTo(right.globalLine);
  }

  List<TerminalShellPromptMark> _bindPromptZone(
    List<TerminalShellPromptMark> current, {
    required int zoneId,
    required int globalLine,
    required String? command,
    required String? cwd,
  }) {
    if (zoneId < 0 || globalLine < 0) {
      return current;
    }
    final matchingIndex = current.lastIndexWhere(
      (mark) => mark.zoneId == null && mark.globalLine == globalLine,
    );
    if (matchingIndex == -1) {
      return _promptMarksForValues(
        current,
        globalLine: globalLine,
        zoneId: zoneId,
        command: command,
        cwd: cwd,
      );
    }
    final matched = current[matchingIndex];
    final next = <TerminalShellPromptMark>[...current];
    next[matchingIndex] = TerminalShellPromptMark(
      globalLine: globalLine,
      zoneId: zoneId,
      command: matched.command,
      cwd: matched.cwd,
      promptKind: matched.promptKind,
      aid: matched.aid,
      parentAid: matched.parentAid,
    );
    return next;
  }

  void _replaceSessionPane(String sessionId, TerminalPane replacement) {
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return;
    }
    final currentTab = state.tabs[tabIndex];
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = currentTab.replacePane(replacement);
    state = state.copyWith(tabs: nextTabs);
  }

  bool _oscUserVarAllowed(String name) {
    return name.startsWith('IANVS_');
  }

  bool _sessionShellIntegrationEnabled(String sessionId) {
    final pane = _paneForSession(sessionId);
    return pane?.profileSnapshot?.sessionConfig.shellIntegration.enabled ??
        true;
  }

  List<String> _prependRecentShellValue(
    List<String> current,
    String? value, {
    required int limit,
  }) {
    if (value == null) {
      return current;
    }
    return <String>[
      value,
      for (final existing in current)
        if (existing != value) existing,
    ].take(limit).toList(growable: false);
  }

  String? _trimShellHookValue(String? value) {
    final sanitized = value == null
        ? null
        : String.fromCharCodes(
            value.runes.where(
              (rune) =>
                  rune >= 0x20 && rune != 0x7f && (rune < 0x80 || rune > 0x9f),
            ),
          );
    final trimmed = sanitized?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String? _boundedShellMetadata(String? value, int maxRunes) {
    final trimmed = _trimShellHookValue(value);
    if (trimmed == null) {
      return null;
    }
    final runes = trimmed.runes.toList(growable: false);
    if (runes.length <= maxRunes) {
      return trimmed;
    }
    return String.fromCharCodes(runes.take(maxRunes));
  }

  String? _boundedOsc99Identifier(String? value) {
    if (value == null ||
        value.isEmpty ||
        value.length > 128 ||
        value.codeUnits.any(
          (byte) =>
              !(byte >= 0x30 && byte <= 0x39) &&
              !(byte >= 0x41 && byte <= 0x5A) &&
              !(byte >= 0x61 && byte <= 0x7A) &&
              !'_-+.'.codeUnits.contains(byte),
        )) {
      return null;
    }
    return value;
  }

  String? _osc934ProgressId(String? value) {
    final trimmed = _trimShellHookValue(value);
    if (trimmed == null || utf8.encode(trimmed).length > 128) {
      return null;
    }
    return trimmed;
  }

  void _applyAutomaticProfileSwitch(
    String sessionId,
    TerminalShellIntegrationSnapshot shellIntegration,
  ) {
    final profile = _matchingAutomaticProfile(shellIntegration);
    if (profile == null) {
      _restoreAutomaticProfileBaseline(sessionId, shellIntegration);
      return;
    }
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return;
    }
    final currentTab = state.tabs[tabIndex];
    final currentPane = currentTab.paneFor(sessionId);
    if (currentPane == null || currentPane.profileId == profile.id) {
      return;
    }
    _automaticProfileBaselines.putIfAbsent(
      sessionId,
      () => _AutomaticProfileBaseline(
        title: currentPane.title,
        profileId: currentPane.profileId,
        profileSnapshot: currentPane.profileSnapshot,
      ),
    );

    final nextTabs = <TerminalTab>[...state.tabs];
    if (currentTab.panes.isEmpty && currentTab.sessionId == sessionId) {
      nextTabs[tabIndex] = currentTab.copyWith(
        title: profile.name,
        profileId: profile.id,
        profileSnapshot: profile,
        shellIntegration: shellIntegration,
      );
    } else {
      nextTabs[tabIndex] = currentTab
          .replacePane(
            currentPane.copyWith(
              title: profile.name,
              profileId: profile.id,
              profileSnapshot: profile,
              shellIntegration: shellIntegration,
            ),
          )
          .copyWith(
            title: sessionId == currentTab.sessionId
                ? profile.name
                : currentTab.title,
          );
    }
    state = state.copyWith(tabs: nextTabs);
    if (sessionId == state.activeSessionId) {
      _setWindowTitle(profile.name);
    }
  }

  void _restoreAutomaticProfileBaseline(
    String sessionId,
    TerminalShellIntegrationSnapshot shellIntegration,
  ) {
    final baseline = _automaticProfileBaselines.remove(sessionId);
    if (baseline == null) {
      return;
    }
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return;
    }
    final currentTab = state.tabs[tabIndex];
    final currentPane = currentTab.paneFor(sessionId);
    if (currentPane == null) {
      return;
    }

    final nextTabs = <TerminalTab>[...state.tabs];
    if (currentTab.panes.isEmpty && currentTab.sessionId == sessionId) {
      nextTabs[tabIndex] = currentTab.copyWith(
        title: baseline.title,
        profileId: baseline.profileId,
        profileSnapshot: baseline.profileSnapshot,
        shellIntegration: shellIntegration,
      );
    } else {
      nextTabs[tabIndex] = currentTab
          .replacePane(
            currentPane.copyWith(
              title: baseline.title,
              profileId: baseline.profileId,
              profileSnapshot: baseline.profileSnapshot,
              shellIntegration: shellIntegration,
            ),
          )
          .copyWith(
            title: sessionId == currentTab.sessionId
                ? baseline.title
                : currentTab.title,
          );
    }
    state = state.copyWith(tabs: nextTabs);
    if (sessionId == state.activeSessionId) {
      _setWindowTitle(baseline.title);
    }
  }

  TerminalProfile? _matchingAutomaticProfile(
    TerminalShellIntegrationSnapshot shellIntegration,
  ) {
    for (final profile in state.profiles) {
      for (final rule in profile.switchRules) {
        if (_profileSwitchRuleMatches(rule, shellIntegration)) {
          return profile;
        }
      }
    }
    return null;
  }

  bool _profileSwitchRuleMatches(
    TerminalProfileSwitchRule rule,
    TerminalShellIntegrationSnapshot shellIntegration,
  ) {
    final value = switch (rule.kind) {
      TerminalProfileSwitchRuleKind.hostname => shellIntegration.hostname,
      TerminalProfileSwitchRuleKind.username => shellIntegration.username,
      TerminalProfileSwitchRuleKind.directory =>
        shellIntegration.currentDirectory,
    };
    if (value == null || value.isEmpty) {
      return false;
    }
    if (rule.kind == TerminalProfileSwitchRuleKind.directory &&
        _isRemoteShellHost(shellIntegration.hostname)) {
      return false;
    }
    if (rule.kind == TerminalProfileSwitchRuleKind.directory &&
        !rule.pattern.contains('*')) {
      return _directoryRuleMatches(value, rule);
    }
    return _shellPatternMatches(
      value,
      rule.pattern,
      caseSensitive: rule.caseSensitive,
    );
  }

  bool _directoryRuleMatches(String directory, TerminalProfileSwitchRule rule) {
    final candidate = rule.caseSensitive ? directory : directory.toLowerCase();
    final pattern = rule.caseSensitive
        ? rule.pattern
        : rule.pattern.toLowerCase();
    final normalizedPattern = pattern.endsWith('/')
        ? pattern.substring(0, pattern.length - 1)
        : pattern;
    return candidate == normalizedPattern ||
        candidate.startsWith('$normalizedPattern/');
  }

  bool _isRemoteShellHost(String? hostname) {
    final normalized = hostname?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    final localHostname = Platform.localHostname.toLowerCase();
    return normalized != 'localhost' &&
        normalized != '127.0.0.1' &&
        normalized != '::1' &&
        normalized != localHostname &&
        normalized != '$localHostname.local';
  }

  bool _shellPatternMatches(
    String value,
    String pattern, {
    required bool caseSensitive,
  }) {
    final buffer = StringBuffer('^');
    for (var index = 0; index < pattern.length; index += 1) {
      final character = pattern[index];
      buffer.write(character == '*' ? '.*' : RegExp.escape(character));
    }
    buffer.write(r'$');
    return RegExp(
      buffer.toString(),
      caseSensitive: caseSensitive,
    ).hasMatch(value);
  }

  void _publishDemoContent(SessionDemoFixture fixture, String? sessionId) {
    final activeTab = _activeTabForSessionId(sessionId);
    final preview = activeTab == null
        ? null
        : _previewForActiveTabPanes(
            activeTab,
            frameForSession: fixture.frameFor,
          );
    _publishTerminalContent(
      terminalHasVisibleContent: preview != null,
      terminalPreview: preview,
    );
  }

  void _publishActiveTabTerminalContent({
    String? updatedSessionId,
    TerminalFrameDiff? updatedFrame,
  }) {
    final activeSessionId = state.activeSessionId;
    final activeTab = _activeTabForSessionId(activeSessionId);
    final preview = activeTab == null
        ? null
        : _previewForActiveTabPanes(
            activeTab,
            frameForSession: (sessionId) {
              if (sessionId == updatedSessionId) {
                return updatedFrame;
              }
              return _runtime.existingViewportFor(sessionId)?.frame;
            },
          );
    _publishTerminalContent(
      terminalHasVisibleContent: preview != null,
      terminalPreview: preview,
    );
  }

  TerminalTab? _activeTabForSessionId(String? sessionId) {
    if (sessionId == null) {
      return null;
    }
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return null;
    }
    return state.tabs[tabIndex];
  }

  String? _previewForActiveTabPanes(
    TerminalTab activeTab, {
    required TerminalFrameDiff? Function(String sessionId) frameForSession,
  }) {
    for (final pane in _activeTabPanesInPreviewOrder(activeTab)) {
      final frame = frameForSession(pane.sessionId);
      if (frame == null) {
        continue;
      }
      final preview = _previewForFrame(frame);
      if (preview != null) {
        return preview;
      }
    }
    return null;
  }

  List<TerminalPane> _activeTabPanesInPreviewOrder(TerminalTab activeTab) {
    final activePane = activeTab.activePane;
    return <TerminalPane>[
      activePane,
      for (final pane in activeTab.effectivePanes)
        if (pane.sessionId != activePane.sessionId) pane,
    ];
  }

  String? _previewForFrame(TerminalFrameDiff frame) {
    for (final row in frame.rows) {
      final text = row.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  void _updateTabTitleFromFrame(
    String sessionId, {
    String? windowTitle,
    String? windowIconName,
  }) {
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return;
    }

    final currentTab = state.tabs[tabIndex];
    final currentPane = currentTab.paneFor(sessionId);
    if (currentPane == null) {
      return;
    }
    final nextTitle = _resolvedPaneTitle(
      currentPane,
      windowTitle: windowTitle,
      windowIconName: windowIconName,
    );
    if (nextTitle == currentPane.title) {
      return;
    }

    state = state.withPaneTitle(sessionId, nextTitle);
    if (sessionId == state.activeSessionId) {
      _setWindowTitle(nextTitle);
    }
  }

  String _resolvedPaneTitle(
    TerminalPane pane, {
    String? windowTitle,
    String? windowIconName,
  }) {
    if (windowTitle != null && windowTitle.isNotEmpty) {
      return windowTitle;
    }
    if (windowIconName != null && windowIconName.isNotEmpty) {
      return windowIconName;
    }

    final profileSnapshot = pane.profileSnapshot;
    if (profileSnapshot != null) {
      return profileSnapshot.name;
    }

    for (final profile in state.profiles) {
      if (profile.id == pane.profileId) {
        return profile.name;
      }
    }
    return pane.title;
  }

  void _removeSessionState(
    String sessionId, {
    bool runtimeAlreadyClosed = false,
  }) {
    _clearProgressTrackingForSession(sessionId);
    _automaticProfileBaselines.remove(sessionId);
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return;
    }

    final tab = state.tabs[tabIndex];
    final tabHasMultiplePanes = tab.effectivePanes.length > 1;
    if (!tabHasMultiplePanes) {
      _removeTabState(tabIndex, recordClosedTab: !runtimeAlreadyClosed);
    } else {
      if (!runtimeAlreadyClosed) {
        final closingPane = tab.paneFor(sessionId);
        if (closingPane != null) {
          _recordClosedPane(tab.sessionId, closingPane);
        }
      }
      final nextPaneLayout = tab.effectivePaneLayout.removePane(sessionId);
      if (nextPaneLayout == null) {
        _removeTabState(tabIndex, recordClosedTab: !runtimeAlreadyClosed);
        return;
      }
      final nextPanes = nextPaneLayout.panes;
      final closingGlobalActivePane = state.activeSessionId == sessionId;
      final closingTabActivePane = tab.activeSessionId == sessionId;
      final nextActivePaneId = closingTabActivePane
          ? nextPanes.last.sessionId
          : tab.activeSessionId;
      final nextTabs = <TerminalTab>[...state.tabs];
      nextTabs[tabIndex] = tab.copyWith(
        panes: nextPanes,
        paneLayout: nextPaneLayout,
        activePaneSessionId: nextActivePaneId == tab.sessionId
            ? null
            : nextActivePaneId,
      );
      state = state.copyWith(
        tabs: nextTabs,
        activeSessionId: closingGlobalActivePane
            ? nextActivePaneId
            : state.activeSessionId,
      );
      _syncRuntimeSessionActivation();
    }

    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      _demoViewports.remove(sessionId)?.dispose();
      if (state.tabs.isEmpty) {
        _publishTerminalContent(
          terminalHasVisibleContent: false,
          terminalPreview: null,
        );
      } else {
        _publishDemoContent(demoFixture, state.activeSessionId);
      }
      return;
    }

    if (state.activeSessionId != null) {
      final activePane = _paneForSession(state.activeSessionId!);
      if (activePane != null) {
        _setWindowTitle(activePane.title);
        _publishActiveTabTerminalContent();
      }
    } else {
      _publishTerminalContent(
        terminalHasVisibleContent: false,
        terminalPreview: null,
      );
    }

    if (!runtimeAlreadyClosed && _runtime.hasSession(sessionId)) {
      _runtime.closeSession(sessionId);
    }
  }

  void _removeTabState(int tabIndex, {bool recordClosedTab = false}) {
    final closingTab = state.tabs[tabIndex];
    _recentlyClosedPanesByTab.remove(closingTab.sessionId);
    if (recordClosedTab) {
      _recentlyClosedTabs
        ..removeWhere((tab) => tab.sessionId == closingTab.sessionId)
        ..insert(0, closingTab);
      if (_recentlyClosedTabs.length > 10) {
        _recentlyClosedTabs.removeRange(10, _recentlyClosedTabs.length);
      }
    }
    for (final pane in closingTab.effectivePanes) {
      _automaticProfileBaselines.remove(pane.sessionId);
      _clearProgressTrackingForSession(pane.sessionId);
      _clearNotificationTrackingForSession(pane.sessionId);
    }
    final nextTabs = <TerminalTab>[
      ...state.tabs.take(tabIndex),
      ...state.tabs.skip(tabIndex + 1),
    ];
    final closingActiveTab =
        state.activeSessionId != null &&
        closingTab.containsSession(state.activeSessionId!);
    final nextActiveSessionId = closingActiveTab
        ? (nextTabs.isEmpty ? null : nextTabs.last.activeSessionId)
        : state.activeSessionId;

    state = state.copyWith(
      tabs: nextTabs,
      activeSessionId: nextActiveSessionId,
    );
    _syncRuntimeSessionActivation();
  }

  void _syncRuntimeSessionActivation() {
    if (ref.read(sessionDemoFixtureProvider) != null) {
      return;
    }
    final nextSessionId = state.activeSessionId;
    final desiredActivation = <String, bool>{};
    for (final tab in state.tabs) {
      for (final pane in tab.effectivePanes) {
        final sessionId = pane.sessionId;
        desiredActivation[sessionId] = sessionId == nextSessionId;
      }
    }
    for (final sessionId
        in _runtimeSessionActivation.keys
            .where((sessionId) => !desiredActivation.containsKey(sessionId))
            .toList(growable: false)) {
      if (_runtimeSessionActivation[sessionId] == true &&
          _runtime.hasSession(sessionId)) {
        _runtime.setSessionActive(sessionId, active: false);
      }
      _runtimeSessionActivation.remove(sessionId);
    }
    for (final entry in desiredActivation.entries) {
      if (_runtimeSessionActivation[entry.key] == entry.value ||
          !_runtime.hasSession(entry.key)) {
        continue;
      }
      _runtime.setSessionActive(entry.key, active: entry.value);
      _runtimeSessionActivation[entry.key] = entry.value;
    }
  }

  void _recordClosedPane(String tabSessionId, TerminalPane pane) {
    final closedPanes = _recentlyClosedPanesByTab.putIfAbsent(
      tabSessionId,
      () => <TerminalPane>[],
    );
    closedPanes
      ..removeWhere((closedPane) => closedPane.sessionId == pane.sessionId)
      ..insert(0, pane);
    if (closedPanes.length > 10) {
      closedPanes.removeRange(10, closedPanes.length);
    }
  }

  int _tabIndexContainingSession(String sessionId) {
    return state.tabs.indexWhere((tab) => tab.containsSession(sessionId));
  }

  TerminalPane? _paneForSession(String sessionId) {
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return null;
    }
    return state.tabs[tabIndex].paneFor(sessionId);
  }

  void _clearProgressTrackingForSession(String sessionId) {
    final prefix = '$sessionId:';
    for (final key
        in _progressGraceTimers.keys
            .where((key) => key.startsWith(prefix))
            .toList(growable: false)) {
      _progressGraceTimers.remove(key)?.cancel();
    }
    for (final key
        in _pendingProgressEvents.keys
            .where((key) => key.startsWith(prefix))
            .toList(growable: false)) {
      _pendingProgressEvents.remove(key);
    }
  }

  void _clearNotificationTrackingForSession(String sessionId) {
    final prefix = '$sessionId:';
    for (final key
        in _notificationExpiryTimers.keys
            .where((key) => key.startsWith(prefix))
            .toList(growable: false)) {
      _notificationExpiryTimers.remove(key)?.cancel();
    }
  }

  Future<void> saveProfile(
    TerminalProfile profile, {
    Set<ProfileSecretField> clearSecrets = const {},
  }) async {
    if (!ref.read(terminalSessionLaunchPolicyProvider).allows(profile)) {
      throw UnsupportedError(
        'Local terminal profiles cannot be created on iOS.',
      );
    }
    if (profile.isSsh &&
        !ref.read(customSshProfileConfigurationEnabledProvider)) {
      throw const CustomSshProfileConfigurationUnavailableException();
    }
    _profileDocument = await ref
        .read(profileRepositoryProvider)
        .updateVersioned(
          (current) => TerminalProfilesDocument(
            schemaVersion: current.schemaVersion,
            profiles: <TerminalProfile>[
              for (final existing in current.profiles)
                if (existing.id == profile.id) profile else existing,
              if (!current.profiles.any(
                (existing) => existing.id == profile.id,
              ))
                profile,
            ],
            loadWarnings: <TerminalProfileLoadWarning>[
              for (final warning in current.loadWarnings)
                if (warning.profileId != profile.id) warning,
            ],
            secretClearIntents: <String, Set<ProfileSecretField>>{
              if (clearSecrets.isNotEmpty) profile.id: clearSecrets,
            },
          ),
          base: _profileDocument,
        );
    final nextProfiles = ref
        .read(terminalSessionLaunchPolicyProvider)
        .visibleProfiles(_profileDocument.value.profiles);
    state = state.copyWith(
      profiles: nextProfiles,
      defaultProfileId: _effectiveDefaultProfileIdFor(nextProfiles),
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
      configurationWarnings: <TerminalProfileLoadWarning>[
        for (final warning in state.configurationWarnings)
          if (warning.profileId != profile.id) warning,
      ],
    );
  }

  /// Refresh saved configuration after a sync pull without replacing running
  /// sessions or applying new credentials to an existing SSH connection.
  Future<void> refreshSyncedConfiguration() async {
    await _bootstrapFuture;
    if (!_bootstrapWorkAllowed || !state.isReady) return;
    try {
      final preparation = await ref
          .read(sessionBootstrapServiceProvider)
          .prepare();
      if (!_bootstrapWorkAllowed) return;
      _profileDocument = preparation.profileDocument;
      _configBootstrapSource = preparation.configSource;
      _localConfigVersioned = preparation.localConfigDocument;
      _preferencesLoadedFromDisk = preparation.preferencesLoadedFromDisk;
      _appPreferencesDocument = preparation.appPreferencesDocument;
      final profiles = ref
          .read(terminalSessionLaunchPolicyProvider)
          .visibleProfiles(preparation.profiles);
      state = state.copyWith(
        profiles: profiles,
        defaultProfileId: _effectiveDefaultProfileIdFor(profiles),
        configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
        configurationWarnings: preparation.configurationWarnings,
        themeMode: _appPreferences.appearance.themeMode,
        languageMode: _appPreferences.appearance.languageMode,
        terminalViewportPadding:
            _appPreferences.appearance.terminalViewportPadding,
      );
    } on Object {
      // A failed refresh must not interrupt an active terminal. The durable
      // repositories remain authoritative and the next pull can retry.
    }
  }

  void dismissConfigurationWarnings() {
    if (state.configurationWarnings.isEmpty) {
      return;
    }
    state = state.copyWith(configurationWarnings: const []);
  }

  void dismissLastError() {
    if (state.lastError == null) {
      return;
    }
    _lastSshExitFailure = null;
    state = state.copyWith(lastError: null);
  }

  void reportRuntimeError(String message) {
    if (message.isEmpty || state.lastError == message) {
      return;
    }
    state = state.copyWith(lastError: message);
  }

  Future<void> setDefaultProfile(String profileId) async {
    _appPreferences = _appPreferences.copyWith(
      defaults: _appPreferences.defaults.copyWith(defaultProfileId: profileId),
    );
    await _savePreferences(
      localConfigUpdater: (config) =>
          config.copyWith(defaultProfileId: profileId),
    );
    state = state.copyWith(
      defaultProfileId: _effectiveDefaultProfileIdFor(state.profiles),
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
    );
  }

  Future<void> resetDefaultProfile() async {
    _appPreferences = _appPreferences.copyWith(
      defaults: _appPreferences.defaults.copyWith(defaultProfileId: null),
    );
    await _savePreferences(
      localConfigUpdater: (config) => config.copyWith(defaultProfileId: null),
    );
    state = state.copyWith(
      defaultProfileId: _effectiveDefaultProfileIdFor(state.profiles),
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
    );
  }

  Future<void> setThemeMode(TerminalThemeMode themeMode) async {
    _appPreferences = _appPreferences.copyWith(
      appearance: _appPreferences.appearance.copyWith(themeMode: themeMode),
    );
    await _savePreferences(
      localConfigUpdater: (config) =>
          config.copyWith(appearance: _appPreferences.appearance),
    );
    state = state.copyWith(themeMode: _appPreferences.appearance.themeMode);
  }

  Future<void> resetThemeMode() async {
    await setThemeMode(TerminalThemeMode.system);
  }

  Future<void> setLanguageMode(TerminalLanguageMode languageMode) async {
    _appPreferences = _appPreferences.copyWith(
      appearance: _appPreferences.appearance.copyWith(
        languageMode: languageMode,
      ),
    );
    await _savePreferences(
      localConfigUpdater: (config) =>
          config.copyWith(appearance: _appPreferences.appearance),
    );
    state = state.copyWith(
      languageMode: _appPreferences.appearance.languageMode,
    );
  }

  Future<void> setTerminalViewportPadding(double padding) async {
    final nextPadding = TerminalAppAppearance.normalizeTerminalViewportPadding(
      padding,
    );
    _appPreferences = _appPreferences.copyWith(
      appearance: _appPreferences.appearance.copyWith(
        terminalViewportPadding: nextPadding,
      ),
    );
    await _savePreferences(
      localConfigUpdater: (config) =>
          config.copyWith(appearance: _appPreferences.appearance),
    );
    state = state.copyWith(
      terminalViewportPadding:
          _appPreferences.appearance.terminalViewportPadding,
    );
  }

  LocalTerminalShellIntegrationConfig get sshIntegrationDefaults =>
      _localConfigDocument.shellIntegration;

  Future<void> setSshIntegrationDefaults({
    required bool wrapper,
    required bool autoInject,
  }) async {
    await _savePreferences(
      localConfigUpdater: (config) => config.copyWith(
        shellIntegration: LocalTerminalShellIntegrationConfig(
          enabled: config.shellIntegration.enabled,
          sshWrapper: wrapper,
          sshAutoInject: autoInject,
        ),
      ),
    );
    state = state.copyWith();
  }

  Future<void> setRestoreLayout(bool restoreLayout) async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    _localConfigDocument = await repository.update(
      (latestConfig) => latestConfig.copyWith(
        layout: LocalTerminalLayoutConfig(restoreLayout: restoreLayout),
      ),
      fallback: _localConfigDocument,
    );
    _configBootstrapSource = LocalTerminalConfigBootstrapSource.localConfig;
    _preferencesLoadedFromDisk = true;

    _layoutPersistenceTimer?.cancel();
    _layoutPersistenceTimer = null;
    _layoutRetryTimer?.cancel();
    _layoutRetryTimer = null;
    if (restoreLayout && !_layoutPersistenceEnabled) {
      try {
        _layoutDocument = await ref
            .read(localTerminalLayoutRepositoryProvider)
            .loadVersioned();
        _layoutPersistenceBlocked = false;
      } on Object catch (error) {
        _layoutPersistenceBlocked = true;
        state = state.copyWith(
          lastError:
              'Terminal layout could not be enabled: '
              '${_boundedShellMetadata(error.toString(), 240)}',
        );
      }
    }
    _layoutPersistenceEnabled = restoreLayout && !_layoutPersistenceBlocked;
    _lastLayoutSnapshot = null;
    if (restoreLayout && state.isReady) {
      await flushLayoutPersistence();
    }
  }

  Future<void> setKeybindings(
    LocalTerminalKeybindingsConfig keybindings,
  ) async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    _localConfigDocument = await repository.update(
      (latestConfig) => latestConfig.copyWith(keybindings: keybindings),
      fallback: _localConfigDocument,
    );
    _configBootstrapSource = LocalTerminalConfigBootstrapSource.localConfig;
    _preferencesLoadedFromDisk = true;
  }

  Future<void> setOsc52Policy(LocalTerminalOsc52Policy policy) async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    _localConfigDocument = await repository.update(
      (latestConfig) => latestConfig.copyWith(
        clipboard: latestConfig.clipboard.copyWith(osc52: policy),
      ),
      fallback: _localConfigDocument,
    );
    _configBootstrapSource = LocalTerminalConfigBootstrapSource.localConfig;
    _preferencesLoadedFromDisk = true;
  }

  Future<void> setOsc1337OpenUrlPolicy(
    LocalTerminalOpenUrlPolicy policy,
  ) async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    _localConfigDocument = await repository.update(
      (latestConfig) => latestConfig.copyWith(
        hostActions: latestConfig.hostActions.copyWith(osc1337OpenUrl: policy),
      ),
      fallback: _localConfigDocument,
    );
    _configBootstrapSource = LocalTerminalConfigBootstrapSource.localConfig;
    _preferencesLoadedFromDisk = true;
  }

  Future<void> setOsc1337RequestAttentionPolicy(
    LocalTerminalRequestAttentionPolicy policy,
  ) async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    _localConfigDocument = await repository.update(
      (latestConfig) => latestConfig.copyWith(
        hostActions: latestConfig.hostActions.copyWith(
          osc1337RequestAttention: policy,
        ),
      ),
      fallback: _localConfigDocument,
    );
    _configBootstrapSource = LocalTerminalConfigBootstrapSource.localConfig;
    _preferencesLoadedFromDisk = true;
  }

  Future<void> setOsc1337ReportVariableDecision(
    String name,
    LocalTerminalReportVariablePolicy? policy,
  ) async {
    if (!isLocalTerminalReportVariableNameSupported(name)) {
      return;
    }
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    _localConfigDocument = await repository.update((latestConfig) {
      final decisions = <String, LocalTerminalReportVariablePolicy>{
        ...latestConfig.hostActions.osc1337ReportVariables,
      };
      decisions.remove(name);
      if (policy != null) {
        while (decisions.length >= maxLocalTerminalReportVariableDecisions) {
          decisions.remove(decisions.keys.first);
        }
        decisions[name] = policy;
      }
      return latestConfig.copyWith(
        hostActions: latestConfig.hostActions.copyWith(
          osc1337ReportVariables: Map.unmodifiable(decisions),
        ),
      );
    }, fallback: _localConfigDocument);
    _configBootstrapSource = LocalTerminalConfigBootstrapSource.localConfig;
    _preferencesLoadedFromDisk = true;
  }

  Future<void> replaceOsc1337ReportVariableDecisions(
    Map<String, LocalTerminalReportVariablePolicy> decisions,
  ) async {
    final normalized = <String, LocalTerminalReportVariablePolicy>{};
    for (final entry in decisions.entries) {
      if (normalized.length >= maxLocalTerminalReportVariableDecisions) {
        break;
      }
      if (isLocalTerminalReportVariableNameSupported(entry.key)) {
        normalized[entry.key] = entry.value;
      }
    }
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    _localConfigDocument = await repository.update(
      (latestConfig) => latestConfig.copyWith(
        hostActions: latestConfig.hostActions.copyWith(
          osc1337ReportVariables: Map.unmodifiable(normalized),
        ),
      ),
      fallback: _localConfigDocument,
    );
    _configBootstrapSource = LocalTerminalConfigBootstrapSource.localConfig;
    _preferencesLoadedFromDisk = true;
  }

  Future<void> deleteProfile(String profileId) async {
    _profileDocument = await ref
        .read(profileRepositoryProvider)
        .updateVersioned(
          (current) => TerminalProfilesDocument(
            schemaVersion: current.schemaVersion,
            profiles: current.profiles
                .where((profile) => profile.id != profileId)
                .toList(growable: false),
            loadWarnings: <TerminalProfileLoadWarning>[
              for (final warning in current.loadWarnings)
                if (warning.profileId != profileId) warning,
            ],
          ),
          base: _profileDocument,
        );
    final nextProfiles = ref
        .read(terminalSessionLaunchPolicyProvider)
        .visibleProfiles(_profileDocument.value.profiles);
    final deletedConfiguredDefault =
        _normalizeProfileId(_appPreferences.defaults.defaultProfileId) ==
        profileId;
    if (deletedConfiguredDefault) {
      _appPreferences = _appPreferences.copyWith(
        defaults: _appPreferences.defaults.copyWith(defaultProfileId: null),
      );
      await _savePreferences(
        localConfigUpdater: (config) => config.copyWith(defaultProfileId: null),
      );
    }
    state = state.copyWith(
      profiles: nextProfiles,
      defaultProfileId: _effectiveDefaultProfileIdFor(nextProfiles),
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
      configurationWarnings: <TerminalProfileLoadWarning>[
        for (final warning in state.configurationWarnings)
          if (warning.profileId != profileId) warning,
      ],
    );
  }

  String? _effectiveDefaultProfileIdFor(
    List<TerminalProfile> profiles, {
    String? preferredProfileId,
  }) {
    final configuredDefaultId = _normalizeProfileId(
      preferredProfileId ?? _appPreferences.defaults.defaultProfileId,
    );
    if (_hasProfileId(profiles, configuredDefaultId)) {
      return configuredDefaultId;
    }
    if (profiles.isEmpty) {
      return null;
    }
    return profiles.first.id;
  }

  String? _configuredDefaultProfileIdForUi() {
    if (!_preferencesLoadedFromDisk) {
      return null;
    }
    return _normalizeProfileId(_appPreferences.defaults.defaultProfileId);
  }

  Future<void> _savePreferences({
    required LocalTerminalConfigDocument Function(LocalTerminalConfigDocument)
    localConfigUpdater,
  }) async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    _localConfigDocument = await repository.update(
      localConfigUpdater,
      fallback: _localConfigDocument,
    );
    _configBootstrapSource = LocalTerminalConfigBootstrapSource.localConfig;
    _preferencesLoadedFromDisk = true;
  }

  String? _normalizeProfileId(String? profileId) {
    final normalized = profileId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  bool _hasProfileId(List<TerminalProfile> profiles, String? profileId) {
    if (profileId == null) {
      return false;
    }
    return profiles.any((profile) => profile.id == profileId);
  }
}
