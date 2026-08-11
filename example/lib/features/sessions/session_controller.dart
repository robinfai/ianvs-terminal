import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;
import 'dart:io' show Directory, File, FileMode, IOSink, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../recording/local_session_recording_repository.dart';
import '../terminal/terminal.dart' hide TerminalEmulation;
import 'session_bootstrap.dart';
import 'session_ports.dart';
import 'session_state.dart';

const Object _recordingLastErrorNoChange = Object();

final ptySessionBackendProvider = Provider<PtySessionBackend>((ref) {
  if (ref.watch(sessionDemoFixtureProvider) != null) {
    return ReferenceDemoPtySessionBackend();
  }
  return loadDefaultPtySessionBackend();
});

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

final terminalRuntimeControllerProvider = Provider<TerminalRuntimeController>((
  ref,
) {
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
    beforeSessionCloseOnExit: (sessionId, _) {
      if (ref.mounted) {
        ref
            .read(sessionControllerProvider.notifier)
            .finalizeRecordingBeforeRuntimeClose(sessionId);
      }
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
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
    legacyPreferencesRepository: ref.read(appPreferencesRepositoryProvider),
  );
});

final localTerminalLayoutRepositoryProvider =
    Provider<TerminalLayoutRepository>((ref) {
      return LocalTerminalLayoutRepository();
    });

final localSessionRecordingRepositoryProvider =
    Provider<LocalSessionRecordingRepository>((ref) {
      return LocalSessionRecordingRepository();
    });

final terminalLiveRecorderProvider = Provider<TerminalLiveRecorder?>((ref) {
  final backend = ref.read(ptySessionBackendProvider);
  if (backend is! PtySessionJsonRequestBackend) {
    return null;
  }
  return TerminalLiveRecorder(backend: backend as PtySessionJsonRequestBackend);
});

final sessionBootstrapServiceProvider = Provider<SessionBootstrapService>((
  ref,
) {
  final localConfigRepository = ref.read(localTerminalConfigRepositoryProvider);
  return SessionBootstrapService(
    profileRepository: ref.read(profileRepositoryProvider),
    appPreferencesRepository: ref.read(appPreferencesRepositoryProvider),
    localConfigRepository: localConfigRepository,
    localConfigLoader: ref.read(localTerminalConfigLoaderProvider),
    // The Flutter test host has no path_provider plugin. Data/API, protocol,
    // I/O and schema errors never match this compatibility-only exception and
    // therefore cannot switch persistence resources.
    shouldFallbackToLegacyPreferences: (error) =>
        localConfigRepository is LocalTerminalConfigRepository &&
        error is MissingPluginException,
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
  static const _layoutPersistenceDebounce = Duration(milliseconds: 60);
  static const _runtimeShutdownTimeout = Duration(seconds: 3);
  static const _runtimeShutdownRetryInterval = Duration(milliseconds: 25);

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
  final Map<String, LocalSessionRecordingDestination> _recordingDestinations =
      <String, LocalSessionRecordingDestination>{};
  final Map<String, TerminalRecording> _pendingRecordings =
      <String, TerminalRecording>{};
  final Map<
    String,
    ({
      TerminalRecordingFinalizeJob job,
      Directory handoffDirectory,
      List<TerminalRecordingSemanticEvent> semanticEvents,
    })
  >
  _pendingRecordingFinalizeJobs =
      <
        String,
        ({
          TerminalRecordingFinalizeJob job,
          Directory handoffDirectory,
          List<TerminalRecordingSemanticEvent> semanticEvents,
        })
      >{};
  final Map<String, Stopwatch> _recordingStopwatches = <String, Stopwatch>{};
  final Map<String, TerminalRecordingInputPolicy> _recordingInputPolicies =
      <String, TerminalRecordingInputPolicy>{};
  final Map<String, List<TerminalRecordingSemanticEvent>>
  _recordingSemanticEvents = <String, List<TerminalRecordingSemanticEvent>>{};
  final Map<String, int> _recordingSemanticEventLimits = <String, int>{};
  final Map<String, int> _recordingSemanticByteBudgets = <String, int>{};
  final Map<String, int> _recordingSemanticRetainedBytes = <String, int>{};
  final Map<String, int> _recordingDroppedSemanticCounts = <String, int>{};
  final Map<String, String> _recordingRemoteCommands = <String, String>{};
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
  StreamSubscription<TerminalSessionEvent>? _runtimeEventsSubscription;
  final Map<String, bool> _runtimeSessionActivation = <String, bool>{};
  bool _progressFlushScheduled = false;
  int _progressEventOrder = 0;
  bool _layoutPersistenceEnabled = false;
  bool _layoutPersistenceBlocked = false;
  Timer? _layoutPersistenceTimer;
  String? _lastLayoutSnapshot;
  Future<void> _layoutSaveChain = Future<void>.value();
  bool _isShuttingDown = false;

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
    unawaited(Future<void>.microtask(_runBootstrap));
    final liveRecorder = ref.read(sessionDemoFixtureProvider) == null
        ? ref.read(terminalLiveRecorderProvider)
        : null;
    final recordingRepository = ref.read(
      localSessionRecordingRepositoryProvider,
    );
    final shutdownCoordinator = ref.read(appShutdownCoordinatorProvider);
    const shutdownTaskName = 'session-runtime';
    shutdownCoordinator.registerTask(
      shutdownTaskName,
      () => _shutdownSessions(liveRecorder, recordingRepository),
    );
    ref.onDispose(() {
      if (!shutdownCoordinator.hasStarted) {
        shutdownCoordinator.unregisterTask(shutdownTaskName);
        _discardRecordingsOnDispose(liveRecorder, recordingRepository);
      }
      _layoutPersistenceTimer?.cancel();
      unawaited(_runtimeEventsSubscription?.cancel());
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
    await _runBootstrap();
  }

  Future<void> _runBootstrap() async {
    await _bootstrapRunner.run(
      isMounted: () => ref.mounted,
      onStarted: () {
        state = state.copyWith(isReady: false, lastError: null);
      },
      operation: _bootstrap,
      onFailed: (error, _) {
        state = state.copyWith(
          isReady: false,
          lastError: 'Terminal startup failed: $error',
        );
      },
    );
  }

  TerminalViewportController viewportFor(String sessionId) {
    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      return _demoViewportFor(sessionId, demoFixture);
    }
    return _runtime.viewportFor(sessionId);
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
      final recovery = await ref
          .read(localSessionRecordingRepositoryProvider)
          .recoverNativeRecordings();
      if (recovery.hasIssues) {
        recordingRecoveryError =
            'Recording recovery found '
            '${recovery.pendingJobIds.length} pending and '
            '${recovery.failures.length} failed job(s), plus '
            '${recovery.orphanPaths.length} orphan artifact(s).';
      }
    } on MissingPluginException {
      // Platform persistence is unavailable in unit/widget hosts.
    } on Object catch (error) {
      recordingRecoveryError =
          'Recording recovery failed: '
          '${_boundedShellMetadata(error.toString(), 240)}';
    }

    _ensureRuntimeSubscription();
    final preparation = await ref
        .read(sessionBootstrapServiceProvider)
        .prepare(explicitDefaultProfileId: bootstrapDefaultProfileIdOverride);
    final runtimeProfiles = preparation.profiles;
    _profileDocument = preparation.profileDocument;
    _configBootstrapSource = preparation.configSource;
    _localConfigVersioned = preparation.localConfigDocument;
    _preferencesLoadedFromDisk = preparation.preferencesLoadedFromDisk;
    _appPreferencesDocument = preparation.appPreferencesDocument;
    if (!ref.mounted) {
      return;
    }
    final effectiveDefaultProfileId = preparation.effectiveDefaultProfileId;
    var initialTabs = <TerminalTab>[];
    String? initialSessionId;
    String? layoutRestoreError;
    final canHaveSavedLayout =
        _configBootstrapSource != LocalTerminalConfigBootstrapSource.defaults;
    if (_localConfigDocument.layout.restoreLayout && canHaveSavedLayout) {
      try {
        _layoutDocument = await ref
            .read(localTerminalLayoutRepositoryProvider)
            .loadVersioned();
        final layout = _layoutDocument.value;
        if (layout != null && !layout.isEmpty) {
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
        // Platform persistence is unavailable in unit/widget hosts.
        _layoutPersistenceBlocked = true;
      } on Object catch (error) {
        _layoutPersistenceBlocked = true;
        layoutRestoreError =
            'Terminal layout could not be loaded: '
            '${_boundedShellMetadata(error.toString(), 240)}';
      }
    }

    if (initialTabs.isEmpty && effectiveDefaultProfileId != null) {
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
      configurationWarnings: preparation.configurationWarnings,
      themeMode: _appPreferences.appearance.themeMode,
      terminalViewportPadding:
          _appPreferences.appearance.terminalViewportPadding,
      isReady: true,
      lastError:
          layoutRestoreError ?? recordingRecoveryError ?? state.lastError,
    );
    _syncRuntimeSessionActivation();
    final activePane = initialSessionId == null
        ? null
        : _paneForSession(initialSessionId);
    if (activePane != null) {
      _setWindowTitle(activePane.title);
    }
    _enableLayoutPersistence();
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
    _runtimeEventsSubscription ??= _runtime.events.listen(_handleRuntimeEvent);
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
    if (profile.isSsh) {
      return profile.copyWith(
        sessionConfig: profile.sessionConfig.copyWith(
          shellIntegration: profile.sessionConfig.shellIntegration.copyWith(
            enabled: false,
          ),
        ),
      );
    }
    final launchProfile = profile.copyWith(
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
    return TerminalRelaunchSpec(
      profileId: profileId,
      command: TerminalRelaunchCommand(
        program: launchProfile.shell,
        arguments: launchProfile.args,
      ),
      cwd: launchProfile.cwd,
    );
  }

  String? _createRuntimeSession(TerminalProfile launchProfile) {
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
  }) async {
    if (_isShuttingDown) {
      return false;
    }
    if (ref.read(sessionDemoFixtureProvider) != null) {
      state = state.copyWith(
        lastError: 'Session recording is unavailable in reference demo mode.',
      );
      return false;
    }
    final pane = _paneForSession(sessionId);
    if (!state.isReady ||
        pane == null ||
        pane.isExited ||
        !_runtime.hasSession(sessionId) ||
        state.recordingSessionIds.contains(sessionId) ||
        state.recordingPendingSaveSessionIds.contains(sessionId) ||
        state.recordingBusySessionIds.contains(sessionId)) {
      return false;
    }
    final recorder = ref.read(terminalLiveRecorderProvider);
    if (recorder == null) {
      state = state.copyWith(
        lastError: 'The active PTY backend does not support session recording.',
      );
      return false;
    }

    final repository = ref.read(localSessionRecordingRepositoryProvider);
    _setRecordingStatus(sessionId, busy: true, lastError: null);
    LocalSessionRecordingDestination? destination;
    try {
      destination = await repository.reserve(
        runtimeSessionId: sessionId,
        createdAtUtc: DateTime.now().toUtc(),
      );
      if (!ref.mounted) {
        repository.release(destination);
        return false;
      }
      final recordingCapacity = recorder.start(
        sessionId,
        inputPolicy: inputPolicy,
      );
      _recordingDestinations[sessionId] = destination;
      _recordingInputPolicies[sessionId] = inputPolicy;
      _recordingStopwatches[sessionId] = Stopwatch()..start();
      _recordingSemanticEvents[sessionId] = <TerminalRecordingSemanticEvent>[];
      _recordingSemanticEventLimits[sessionId] =
          recordingCapacity.maxEvents < 4096
          ? recordingCapacity.maxEvents
          : 4096;
      _recordingSemanticByteBudgets[sessionId] =
          recordingCapacity.maxPayloadBytes < 512 * 1024
          ? recordingCapacity.maxPayloadBytes
          : 512 * 1024;
      _recordingSemanticRetainedBytes[sessionId] = 0;
      _recordingDroppedSemanticCounts[sessionId] = 0;
      _setRecordingStatus(
        sessionId,
        active: true,
        pendingSave: false,
        busy: false,
        lastError: null,
      );
      return true;
    } on Object catch (error) {
      if (destination != null) {
        repository.release(destination);
      }
      if (ref.mounted) {
        _setRecordingStatus(
          sessionId,
          active: false,
          pendingSave: false,
          busy: false,
          lastError: _recordingError('Recording start failed', error),
        );
      }
      return false;
    }
  }

  Future<String?> stopSessionRecording(String sessionId) async {
    if (state.recordingBusySessionIds.contains(sessionId) ||
        (!state.recordingSessionIds.contains(sessionId) &&
            !state.recordingPendingSaveSessionIds.contains(sessionId))) {
      return null;
    }
    final recorder = ref.read(terminalLiveRecorderProvider);
    final repository = ref.read(localSessionRecordingRepositoryProvider);
    final destination = _recordingDestinations[sessionId];
    if (recorder == null || destination == null) {
      _setRecordingStatus(
        sessionId,
        active: false,
        pendingSave: false,
        busy: false,
        lastError: 'Recording save state is unavailable.',
      );
      return null;
    }

    _setRecordingStatus(sessionId, busy: true, lastError: null);
    try {
      final path = await _persistStoppedRecording(
        sessionId: sessionId,
        recorder: recorder,
        repository: repository,
        destination: destination,
        displayName: _paneForSession(sessionId)?.title,
      );
      _pendingRecordings.remove(sessionId);
      _pendingRecordingFinalizeJobs.remove(sessionId);
      _recordingDestinations.remove(sessionId);
      _recordingInputPolicies.remove(sessionId);
      final droppedSemantics = _recordingDroppedSemanticCounts[sessionId] ?? 0;
      _clearRecordingSemanticCapacity(sessionId);
      if (ref.mounted) {
        _setRecordingStatus(
          sessionId,
          active: false,
          pendingSave: false,
          busy: false,
          lastError: droppedSemantics == 0
              ? null
              : 'Recording completed after dropping $droppedSemantics '
                    'shell metadata event(s) at its bounded semantic '
                    'retention limit.',
        );
      }
      return path;
    } on Object catch (error) {
      if (!ref.mounted) {
        return null;
      }
      final hasRecoverableFinalize =
          _pendingRecordings.containsKey(sessionId) ||
          _pendingRecordingFinalizeJobs.containsKey(sessionId);
      final isStillRecording = recorder.isRecording(sessionId);
      if (!hasRecoverableFinalize && !isStillRecording) {
        repository.release(destination);
        _recordingDestinations.remove(sessionId);
        _recordingInputPolicies.remove(sessionId);
        _recordingStopwatches.remove(sessionId)?.stop();
        _recordingSemanticEvents.remove(sessionId);
        _recordingRemoteCommands.remove(sessionId);
        _clearRecordingSemanticCapacity(sessionId);
      }
      _setRecordingStatus(
        sessionId,
        active: isStillRecording,
        pendingSave: hasRecoverableFinalize,
        busy: false,
        lastError: _recordingError(
          hasRecoverableFinalize
              ? 'Recording finalize failed'
              : isStillRecording
              ? 'Recording finalize preparation failed'
              : 'Recording stop failed',
          error,
        ),
      );
      return null;
    }
  }

  Future<String> _persistStoppedRecording({
    required String sessionId,
    required TerminalLiveRecorder? recorder,
    required LocalSessionRecordingRepository repository,
    required LocalSessionRecordingDestination destination,
    required String? displayName,
  }) async {
    var legacyRecording = _pendingRecordings[sessionId];
    var finalizeJob = _pendingRecordingFinalizeJobs[sessionId];
    if (legacyRecording == null && finalizeJob == null) {
      if (recorder == null || !recorder.isRecording(sessionId)) {
        throw StateError('Native recording state is unavailable.');
      }
      final handoffDirectory = await repository.ensureNativeHandoffDirectory();
      final semanticEvents = _takeRecordingSemantics(sessionId);
      final reservedJob = await repository.reserveNativeRecordingJob(
        sessionId: sessionId,
        handoffDirectory: handoffDirectory,
        destination: destination,
        semanticEvents: semanticEvents,
        displayName: displayName,
      );
      finalizeJob = (
        job: reservedJob,
        handoffDirectory: handoffDirectory,
        semanticEvents: semanticEvents,
      );
      _pendingRecordingFinalizeJobs[sessionId] = finalizeJob;
      try {
        final job = recorder.prepareStop(
          sessionId,
          handoffDirectory: handoffDirectory.path,
          jobId: reservedJob.jobId,
        );
        finalizeJob = (
          job: job,
          handoffDirectory: handoffDirectory,
          semanticEvents: semanticEvents,
        );
        _pendingRecordingFinalizeJobs[sessionId] = finalizeJob;
        await repository.registerNativeRecordingJob(
          job: finalizeJob.job,
          handoffDirectory: finalizeJob.handoffDirectory,
          destination: destination,
          semanticEvents: finalizeJob.semanticEvents,
          displayName: displayName,
        );
      } on TerminalRecordingBackendException catch (error) {
        if (error.code ==
            TerminalRecordingBackendErrorCode.unsupportedBackend) {
          _pendingRecordingFinalizeJobs.remove(sessionId);
          await repository.abandonNativeRecordingJobReservation(reservedJob);
          finalizeJob = null;
          legacyRecording = _recordingWithSemanticEvents(
            recorder.stop(sessionId),
            semanticEvents,
          );
          _pendingRecordings[sessionId] = legacyRecording;
        } else {
          if (recorder.isRecording(sessionId)) {
            _pendingRecordingFinalizeJobs.remove(sessionId);
            await repository.abandonNativeRecordingJobReservation(reservedJob);
          }
          rethrow;
        }
      }
      if (ref.mounted) {
        _setRecordingStatus(
          sessionId,
          active: false,
          pendingSave: true,
          busy: true,
        );
      }
    }
    if (finalizeJob != null) {
      return repository.finalizeNativeRecording(
        job: finalizeJob.job,
        handoffDirectory: finalizeJob.handoffDirectory,
        destination: destination,
        semanticEvents: finalizeJob.semanticEvents,
        displayName: displayName,
      );
    }
    return repository.save(
      destination,
      legacyRecording!,
      displayName: displayName,
    );
  }

  bool _recordingNeedsFinalization(String sessionId) {
    return state.recordingSessionIds.contains(sessionId) ||
        state.recordingPendingSaveSessionIds.contains(sessionId) ||
        state.recordingBusySessionIds.contains(sessionId);
  }

  Future<bool> _finalizeSessionRecordings(Iterable<String> sessionIds) async {
    for (final sessionId in sessionIds) {
      if (state.recordingBusySessionIds.contains(sessionId)) {
        state = state.copyWith(
          lastError: 'Recording operation is still in progress. Try again.',
        );
        return false;
      }
      if ((state.recordingSessionIds.contains(sessionId) ||
              state.recordingPendingSaveSessionIds.contains(sessionId)) &&
          await stopSessionRecording(sessionId) == null) {
        return false;
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
          sessionId:
              _recordingInputPolicies[sessionId] ??
              TerminalRecordingInputPolicy.redact,
    };
  }

  Future<bool> _resumeRecordingsAfterRejectedClose(
    Map<String, TerminalRecordingInputPolicy> policies,
  ) async {
    var resumedAll = true;
    for (final entry in policies.entries) {
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
      resumedAll =
          await startSessionRecording(sessionId, inputPolicy: entry.value) &&
          resumedAll;
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

  void _captureRecordingShellHook(TerminalSessionShellHookEvent event) {
    final hook = event.hook?.trim().toLowerCase();
    if (hook == null) {
      return;
    }
    final command = _boundedShellMetadata(event.command, 512);
    final cwd = _boundedShellMetadata(event.cwd, 1024);
    switch (hook) {
      case 'preexec':
        final remote = command != null && _isRemoteShellCommand(command);
        if (remote) {
          final activeRemote = _recordingRemoteCommands[event.sessionId];
          if (activeRemote != null &&
              _sameSemanticCommand(activeRemote, command)) {
            return;
          }
          _recordingRemoteCommands[event.sessionId] = command;
        }
        _appendRecordingSemantic(
          event.sessionId,
          kind: remote
              ? TerminalRecordingSemanticKind.remoteSessionStarted
              : TerminalRecordingSemanticKind.commandStarted,
          command: command,
          cwd: cwd,
        );
      case 'command_finished':
        final remoteCommand = _recordingRemoteCommands.remove(event.sessionId);
        if (remoteCommand == null &&
            command != null &&
            _isRemoteShellCommand(command)) {
          return;
        }
        _appendRecordingSemantic(
          event.sessionId,
          kind: remoteCommand == null
              ? TerminalRecordingSemanticKind.commandFinished
              : TerminalRecordingSemanticKind.remoteSessionFinished,
          command: remoteCommand ?? command,
          cwd: cwd,
          exitCode: event.exitCode,
        );
      case 'precmd.pwd':
        _appendRecordingSemantic(
          event.sessionId,
          kind: TerminalRecordingSemanticKind.directoryChanged,
          cwd: cwd,
          remote: _recordingRemoteCommands.containsKey(event.sessionId),
        );
      case 'precmd':
        _appendRecordingSemantic(
          event.sessionId,
          kind: TerminalRecordingSemanticKind.prompt,
          cwd: cwd,
          remote: _recordingRemoteCommands.containsKey(event.sessionId),
        );
    }
  }

  void _captureRecordingShellContext(TerminalSessionShellContextEvent event) {
    _appendRecordingSemantic(
      event.sessionId,
      kind: TerminalRecordingSemanticKind.directoryChanged,
      cwd: _boundedShellMetadata(event.cwd, 1024),
      hostname: _boundedShellMetadata(event.hostname, 255),
      remote: _recordingRemoteCommands.containsKey(event.sessionId),
    );
  }

  void _captureRecordingShellCommand(TerminalSessionShellCommandEvent event) {
    final eventType = event.eventType?.trim().toLowerCase();
    if (eventType == null) {
      return;
    }
    final command = _boundedShellMetadata(event.command, 512);
    final remoteCommand = _recordingRemoteCommands[event.sessionId];
    switch (eventType) {
      case 'command_start':
      case 'command_executed':
        if (command != null && _isRemoteShellCommand(command)) {
          if (remoteCommand == null) {
            _recordingRemoteCommands[event.sessionId] = command;
            _appendRecordingSemantic(
              event.sessionId,
              kind: TerminalRecordingSemanticKind.remoteSessionStarted,
              command: command,
            );
            return;
          }
          if (_sameSemanticCommand(remoteCommand, command)) {
            return;
          }
        }
        _appendRecordingSemantic(
          event.sessionId,
          kind: TerminalRecordingSemanticKind.commandStarted,
          command: command,
          remote: remoteCommand != null,
        );
      case 'command_finished':
        if (remoteCommand != null &&
            command != null &&
            _sameSemanticCommand(remoteCommand, command)) {
          _recordingRemoteCommands.remove(event.sessionId);
          _appendRecordingSemantic(
            event.sessionId,
            kind: TerminalRecordingSemanticKind.remoteSessionFinished,
            command: remoteCommand,
            exitCode: event.exitCode,
          );
          return;
        }
        _appendRecordingSemantic(
          event.sessionId,
          kind: TerminalRecordingSemanticKind.commandFinished,
          command: command,
          exitCode: event.exitCode,
          remote: remoteCommand != null,
        );
      case 'prompt_start':
      case 'mark':
        _appendRecordingSemantic(
          event.sessionId,
          kind: TerminalRecordingSemanticKind.prompt,
          command: command,
          remote: remoteCommand != null,
        );
    }
  }

  void _appendRecordingSemantic(
    String sessionId, {
    required TerminalRecordingSemanticKind kind,
    String? command,
    String? cwd,
    String? hostname,
    int? exitCode,
    bool remote = false,
  }) {
    final stopwatch = _recordingStopwatches[sessionId];
    final events = _recordingSemanticEvents[sessionId];
    if (stopwatch == null || events == null) {
      return;
    }
    final candidate = TerminalRecordingSemanticEvent(
      monotonicOffset: stopwatch.elapsed,
      kind: kind,
      command: command,
      cwd: cwd,
      hostname: hostname,
      exitCode: exitCode,
      remote: remote,
    );
    if (events.isNotEmpty) {
      final previous = events.last;
      final sameCommand =
          previous.command == candidate.command ||
          previous.command == null ||
          candidate.command == null;
      if (previous.kind == candidate.kind &&
          sameCommand &&
          previous.remote == candidate.remote &&
          candidate.monotonicOffset - previous.monotonicOffset <
              const Duration(milliseconds: 80)) {
        final replacement = TerminalRecordingSemanticEvent(
          monotonicOffset: previous.monotonicOffset,
          kind: candidate.kind,
          command: candidate.command ?? previous.command,
          cwd: candidate.cwd ?? previous.cwd,
          hostname: candidate.hostname ?? previous.hostname,
          exitCode: candidate.exitCode ?? previous.exitCode,
          remote: candidate.remote,
        );
        final previousBytes = _estimateRecordingSemanticBytes(previous);
        final replacementBytes = _estimateRecordingSemanticBytes(replacement);
        final retainedBytes = _recordingSemanticRetainedBytes[sessionId] ?? 0;
        final byteBudget = _recordingSemanticByteBudgets[sessionId] ?? 0;
        if (retainedBytes - previousBytes + replacementBytes <= byteBudget) {
          events[events.length - 1] = replacement;
          _recordingSemanticRetainedBytes[sessionId] =
              retainedBytes - previousBytes + replacementBytes;
          return;
        }
      }
    }
    final candidateBytes = _estimateRecordingSemanticBytes(candidate);
    if (!_makeRoomForRecordingSemantic(
      sessionId,
      events,
      candidateBytes,
      requiredSlots: _recordingSemanticRequiredSlots(kind),
      preservePairing: _isPairedRecordingSemantic(kind),
    )) {
      _recordingDroppedSemanticCounts.update(
        sessionId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      return;
    }
    events.add(candidate);
    _recordingSemanticRetainedBytes.update(
      sessionId,
      (bytes) => bytes + candidateBytes,
      ifAbsent: () => candidateBytes,
    );
  }

  bool _makeRoomForRecordingSemantic(
    String sessionId,
    List<TerminalRecordingSemanticEvent> events,
    int candidateBytes, {
    required int requiredSlots,
    required bool preservePairing,
  }) {
    final eventLimit = _recordingSemanticEventLimits[sessionId] ?? 0;
    final byteBudget = _recordingSemanticByteBudgets[sessionId] ?? 0;
    if (eventLimit <= 0 || byteBudget <= 0 || candidateBytes > byteBudget) {
      return false;
    }
    var retainedBytes = _recordingSemanticRetainedBytes[sessionId] ?? 0;
    if (requiredSlots > eventLimit) {
      return false;
    }
    while (events.length + requiredSlots > eventLimit ||
        retainedBytes + candidateBytes > byteBudget) {
      final lowValueIndex = events.indexWhere(
        (event) =>
            event.kind == TerminalRecordingSemanticKind.directoryChanged ||
            event.kind == TerminalRecordingSemanticKind.prompt,
      );
      if (lowValueIndex >= 0) {
        retainedBytes -= _estimateRecordingSemanticBytes(
          events.removeAt(lowValueIndex),
        );
        _recordingDroppedSemanticCounts.update(
          sessionId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        continue;
      }
      final completedPair = preservePairing
          ? _oldestCompletedRecordingSemanticPair(events)
          : null;
      if (completedPair == null) {
        _recordingSemanticRetainedBytes[sessionId] = retainedBytes;
        return false;
      }
      final (startIndex, finishIndex) = completedPair;
      retainedBytes -= _estimateRecordingSemanticBytes(
        events.removeAt(finishIndex),
      );
      retainedBytes -= _estimateRecordingSemanticBytes(
        events.removeAt(startIndex),
      );
      _recordingDroppedSemanticCounts.update(
        sessionId,
        (count) => count + 2,
        ifAbsent: () => 2,
      );
    }
    _recordingSemanticRetainedBytes[sessionId] = retainedBytes;
    return true;
  }

  (int, int)? _oldestCompletedRecordingSemanticPair(
    List<TerminalRecordingSemanticEvent> events,
  ) {
    for (var startIndex = 0; startIndex < events.length; startIndex += 1) {
      final start = events[startIndex];
      final expectedFinish = switch (start.kind) {
        TerminalRecordingSemanticKind.commandStarted =>
          TerminalRecordingSemanticKind.commandFinished,
        TerminalRecordingSemanticKind.remoteSessionStarted =>
          TerminalRecordingSemanticKind.remoteSessionFinished,
        _ => null,
      };
      if (expectedFinish == null) {
        continue;
      }
      for (
        var finishIndex = startIndex + 1;
        finishIndex < events.length;
        finishIndex += 1
      ) {
        final finish = events[finishIndex];
        if (finish.kind == expectedFinish &&
            (start.command == null ||
                finish.command == null ||
                _sameSemanticCommand(start.command!, finish.command!))) {
          return (startIndex, finishIndex);
        }
      }
    }
    return null;
  }

  bool _isPairedRecordingSemantic(TerminalRecordingSemanticKind kind) {
    return switch (kind) {
      TerminalRecordingSemanticKind.commandStarted ||
      TerminalRecordingSemanticKind.commandFinished ||
      TerminalRecordingSemanticKind.remoteSessionStarted ||
      TerminalRecordingSemanticKind.remoteSessionFinished => true,
      _ => false,
    };
  }

  int _recordingSemanticRequiredSlots(TerminalRecordingSemanticKind kind) {
    return switch (kind) {
      TerminalRecordingSemanticKind.commandStarted ||
      TerminalRecordingSemanticKind.remoteSessionStarted => 2,
      _ => 1,
    };
  }

  int _estimateRecordingSemanticBytes(TerminalRecordingSemanticEvent event) {
    return 96 +
        (event.command?.length ?? 0) * 2 +
        (event.cwd?.length ?? 0) * 2 +
        (event.hostname?.length ?? 0) * 2;
  }

  TerminalRecording _recordingWithSemanticEvents(
    TerminalRecording recording,
    List<TerminalRecordingSemanticEvent> semanticEvents,
  ) {
    return const TerminalRecordingSemanticMerger().merge(
      recording,
      semanticEvents,
    );
  }

  List<TerminalRecordingSemanticEvent> _takeRecordingSemantics(
    String sessionId,
  ) {
    _recordingStopwatches.remove(sessionId)?.stop();
    final semantics =
        _recordingSemanticEvents.remove(sessionId) ??
        const <TerminalRecordingSemanticEvent>[];
    _recordingRemoteCommands.remove(sessionId);
    return List<TerminalRecordingSemanticEvent>.unmodifiable(semantics);
  }

  bool _isRemoteShellCommand(String command) {
    return RegExp(
      r'^\s*(?:(?:command|exec|sudo)\s+)?(?:ssh|mosh)(?:\s|$)',
    ).hasMatch(command);
  }

  bool _sameSemanticCommand(String left, String right) {
    String normalize(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalize(left) == normalize(right);
  }

  Future<void> _finalizeRecordingOnRuntimeExitBestEffort(
    String sessionId,
  ) async {
    if (!_recordingNeedsFinalization(sessionId)) {
      return;
    }
    final recorder = ref.read(terminalLiveRecorderProvider);
    final repository = ref.read(localSessionRecordingRepositoryProvider);
    final destination = _recordingDestinations[sessionId];
    try {
      if (destination != null) {
        await _persistStoppedRecording(
          sessionId: sessionId,
          recorder: recorder,
          repository: repository,
          destination: destination,
          displayName: _paneForSession(sessionId)?.title,
        );
      }
    } on Object catch (error) {
      state = state.copyWith(
        lastError: _recordingError('Recording exit save failed', error),
      );
    } finally {
      _forgetRecording(sessionId, repository: repository);
    }
  }

  void finalizeRecordingBeforeRuntimeClose(String sessionId) {
    unawaited(_finalizeRecordingOnRuntimeExitBestEffort(sessionId));
  }

  Future<void> _finalizeRecordingsForShutdown(
    TerminalLiveRecorder? recorder,
    LocalSessionRecordingRepository repository,
  ) {
    return _recordingShutdownFuture ??= _runRecordingShutdownFinalization(
      recorder,
      repository,
    );
  }

  Future<void> _shutdownSessions(
    TerminalLiveRecorder? recorder,
    LocalSessionRecordingRepository recordingRepository,
  ) {
    final existing = _sessionShutdownFuture;
    if (existing != null) {
      return existing;
    }

    _isShuttingDown = true;
    _layoutPersistenceTimer?.cancel();
    _layoutPersistenceTimer = null;

    final terminalRuntime = _runtime;
    final runtimeEventsSubscription = _runtimeEventsSubscription;
    _runtimeEventsSubscription = null;
    runtimeEventsSubscription?.pause();
    final runtimeEventsCancellation =
        runtimeEventsSubscription?.cancel() ?? Future<void>.value();

    final layoutRepository = ref.read(localTerminalLayoutRepositoryProvider);
    final pendingLayoutWrites = _layoutSaveChain;
    final finalLayout = _layoutPersistenceEnabled && state.isReady
        ? LocalSessionLayoutCodec.capture(state)
        : null;
    if (finalLayout != null) {
      _lastLayoutSnapshot = jsonEncode(finalLayout.toJson());
    }

    // The recorder snapshot is captured synchronously before its first await,
    // after the event subscription has been paused. Encoding remains async.
    final recordingFinalization = _finalizeRecordingsForShutdown(
      recorder,
      recordingRepository,
    );
    return _sessionShutdownFuture = _completeSessionShutdown(
      runtimeEventsCancellation: runtimeEventsCancellation,
      recordingFinalization: recordingFinalization,
      pendingLayoutWrites: pendingLayoutWrites,
      finalLayout: finalLayout,
      layoutRepository: layoutRepository,
      terminalRuntime: terminalRuntime,
    );
  }

  Future<void> _completeSessionShutdown({
    required Future<void> runtimeEventsCancellation,
    required Future<void> recordingFinalization,
    required Future<void> pendingLayoutWrites,
    required TerminalLayout? finalLayout,
    required TerminalLayoutRepository layoutRepository,
    required TerminalRuntimeController terminalRuntime,
  }) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> settle(Future<void> future) async {
      try {
        await future;
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await settle(runtimeEventsCancellation);
    await settle(recordingFinalization);
    await settle(
      _flushCapturedLayoutForShutdown(
        pendingLayoutWrites: pendingLayoutWrites,
        finalLayout: finalLayout,
        repository: layoutRepository,
      ),
    );
    await settle(_closeTerminalRuntimeForShutdown(terminalRuntime));

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
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

  Future<void> _closeTerminalRuntimeForShutdown(
    TerminalRuntimeController runtime,
  ) async {
    final deadline = DateTime.now().add(_runtimeShutdownTimeout);
    while (!runtime.tryDispose()) {
      if (!DateTime.now().isBefore(deadline)) {
        throw TimeoutException(
          'Terminal runtime did not release all sessions before shutdown.',
          _runtimeShutdownTimeout,
        );
      }
      await Future<void>.delayed(_runtimeShutdownRetryInterval);
    }
  }

  Future<void> _runRecordingShutdownFinalization(
    TerminalLiveRecorder? recorder,
    LocalSessionRecordingRepository repository,
  ) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    final sessionIds = _recordingDestinations.keys.toList(growable: false);
    await Future.wait(
      sessionIds.map((sessionId) async {
        final destination = _recordingDestinations[sessionId];
        try {
          if (destination != null) {
            await _persistStoppedRecording(
              sessionId: sessionId,
              recorder: recorder,
              repository: repository,
              destination: destination,
              displayName: null,
            );
          }
        } on Object catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
          if (recorder?.isRecording(sessionId) == true) {
            try {
              recorder?.cancel(sessionId);
            } on Object {
              // Continue finalizing the remaining sessions.
            }
          }
        } finally {
          _forgetRecording(sessionId, repository: repository);
        }
      }),
    );
    final shutdownError = firstError;
    if (shutdownError != null) {
      Error.throwWithStackTrace(shutdownError, firstStackTrace!);
    }
  }

  void _discardRecordingsOnDispose(
    TerminalLiveRecorder? recorder,
    LocalSessionRecordingRepository repository,
  ) {
    for (final sessionId in _recordingDestinations.keys.toList(
      growable: false,
    )) {
      try {
        recorder?.cancel(sessionId);
      } on Object {
        // Provider disposal cannot surface cleanup failures.
      }
      _forgetRecording(sessionId, repository: repository);
    }
    for (final stopwatch in _recordingStopwatches.values) {
      stopwatch.stop();
    }
    _recordingStopwatches.clear();
    _pendingRecordings.clear();
    _pendingRecordingFinalizeJobs.clear();
    _recordingInputPolicies.clear();
    _recordingSemanticEvents.clear();
    _recordingSemanticEventLimits.clear();
    _recordingSemanticByteBudgets.clear();
    _recordingSemanticRetainedBytes.clear();
    _recordingDroppedSemanticCounts.clear();
    _recordingRemoteCommands.clear();
  }

  void _forgetRecording(
    String sessionId, {
    LocalSessionRecordingRepository? repository,
  }) {
    final destination = _recordingDestinations.remove(sessionId);
    if (destination != null) {
      repository?.release(destination);
    }
    _pendingRecordings.remove(sessionId);
    _pendingRecordingFinalizeJobs.remove(sessionId);
    _recordingInputPolicies.remove(sessionId);
    _recordingStopwatches.remove(sessionId)?.stop();
    _recordingSemanticEvents.remove(sessionId);
    _clearRecordingSemanticCapacity(sessionId);
    _recordingRemoteCommands.remove(sessionId);
    if (!ref.mounted) {
      return;
    }
    _setRecordingStatus(
      sessionId,
      active: false,
      pendingSave: false,
      busy: false,
    );
  }

  void _clearRecordingSemanticCapacity(String sessionId) {
    _recordingSemanticEventLimits.remove(sessionId);
    _recordingSemanticByteBudgets.remove(sessionId);
    _recordingSemanticRetainedBytes.remove(sessionId);
    _recordingDroppedSemanticCounts.remove(sessionId);
  }

  Future<bool> closeSession(String sessionId) async {
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
    if (_recordingNeedsFinalization(sessionId) &&
        !await _finalizeSessionRecordings(<String>[sessionId])) {
      return false;
    }
    // Recording finalization yields to the event loop, so repeat the guard at
    // the actual close boundary. Native also rejects the narrower receive
    // publication critical section and retains its event queue on failure.
    if (_runtime.isZmodemTransferActive(sessionId)) {
      final resumed = await _resumeRecordingsAfterRejectedClose(
        recordingsToResume,
      );
      reportRuntimeError(
        resumed
            ? 'Cancel the active ZMODEM transfer and wait for it to finish '
                  'before closing this pane. Recording continued in a new file.'
            : 'Cancel the active ZMODEM transfer before closing this pane. '
                  'The recording continuation could not be started.',
      );
      return false;
    }
    if (!_runtime.tryCloseSession(sessionId)) {
      final resumed = await _resumeRecordingsAfterRejectedClose(
        recordingsToResume,
      );
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
      if (!finalized) {
        final finalizationError = state.lastError;
        await _resumeRecordingsAfterRejectedClose(recordingsToResume);
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
    if (ref.read(sessionDemoFixtureProvider) != null) {
      return;
    }
    if (_tabIndexContainingSession(sessionId) == -1) {
      return;
    }
    _runtime.resizeSession(sessionId, viewportSize, devicePixelRatio);
    _applyFrame(sessionId, _runtime.viewportFor(sessionId).frame);
  }

  void _handleRuntimeEvent(TerminalSessionEvent event) {
    if (!ref.mounted) {
      return;
    }
    switch (event) {
      case TerminalSessionSshAuthPromptEvent():
        // ShellScreen owns the secure modal prompt and native response.
        break;
      case TerminalSessionFrameEvent():
        _applyFrame(event.sessionId, event.frame);
      case TerminalSessionExitEvent():
        final sshExitError = _sshExitErrorMessage(event);
        unawaited(_finalizeRecordingOnRuntimeExitBestEffort(event.sessionId));
        _removeSessionState(event.sessionId, runtimeAlreadyClosed: true);
        if (sshExitError != null) {
          state = state.copyWith(lastError: sshExitError);
        }
      case TerminalSessionBellEvent():
        break;
      case TerminalSessionShellHookEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _captureRecordingShellHook(event);
        _applyShellHook(event);
      case TerminalSessionShellContextEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _captureRecordingShellContext(event);
        _applyShellContext(event);
      case TerminalSessionShellCommandEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _captureRecordingShellCommand(event);
        _applyShellCommand(event);
      case TerminalSessionShellUserVarEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _applyShellUserVar(event);
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
    state = state.copyWith(
      lastError:
          'Terminal backend $operation failed for session $sessionId'
          '${detail == null ? '' : ': $detail'}',
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
        identical(nextPromptMarks, current.promptMarks)) {
      return;
    }
    final nextCommands = _prependRecentShellValue(
      current.recentCommands,
      shouldTrackCommand ? command : null,
      limit: 40,
    );
    final nextIntegration = current.copyWith(
      lastCommand: shouldTrackCommand ? command : current.lastCommand,
      lastExitCode: event.exitCode ?? current.lastExitCode,
      recentCommands: nextCommands,
      promptMarks: nextPromptMarks,
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
        expectedNotification.source != 'osc99' ||
        expectedNotification.identifier == null ||
        !pane.recentNotifications.any(
          (notification) => identical(notification, expectedNotification),
        )) {
      return false;
    }
    final identifier = expectedNotification.identifier!;
    final retained = pane.recentNotifications
        .where(
          (notification) =>
              notification.source != 'osc99' ||
              notification.identifier != identifier,
        )
        .toList(growable: false);
    if (retained.length == pane.recentNotifications.length) {
      return false;
    }
    _notificationExpiryTimers
        .remove(_notificationExpiryKey(sessionId, identifier))
        ?.cancel();
    _runtime.dismissOsc99Notification(sessionId, identifier);
    _replaceSessionPane(
      sessionId,
      pane.copyWith(recentNotifications: retained),
    );
    if (expectedNotification.reportClose) {
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
      currentDirectory: null,
      hostname: null,
      username: null,
      lastCommand: null,
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

    return current.copyWith(
      currentDirectory: nextCurrentDirectory,
      hostname: hostname ?? current.hostname,
      username: username ?? current.username,
      shell: shell ?? current.shell,
      lastCommand: command ?? current.lastCommand,
      lastExitCode: event.exitCode ?? current.lastExitCode,
      recentCommands: nextCommands,
      recentDirectories: nextDirectories,
      promptMarks: nextPromptMarks,
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
      return _promptMarksForLegacyOffset(
        current,
        scrollbackOffset: promptOffset,
        command: command,
        cwd: cwd,
      );
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

  List<TerminalShellPromptMark> _promptMarksForLegacyOffset(
    List<TerminalShellPromptMark> current, {
    required int scrollbackOffset,
    required String? command,
    required String? cwd,
  }) {
    if (scrollbackOffset < 0) {
      return current;
    }
    final nextMarks = <TerminalShellPromptMark>[
      for (final mark in current)
        if (mark.legacyScrollbackOffset != scrollbackOffset) mark,
      TerminalShellPromptMark(
        legacyScrollbackOffset: scrollbackOffset,
        command: command,
        cwd: cwd,
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
    final leftGlobal = left.globalLine;
    final rightGlobal = right.globalLine;
    if (leftGlobal != null && rightGlobal != null) {
      return leftGlobal.compareTo(rightGlobal);
    }
    if (leftGlobal != null) {
      return -1;
    }
    if (rightGlobal != null) {
      return 1;
    }
    return (left.legacyScrollbackOffset ?? 0).compareTo(
      right.legacyScrollbackOffset ?? 0,
    );
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
              return _runtime.viewportFor(sessionId).frame;
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

    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = currentTab
        .replacePane(currentPane.copyWith(title: nextTitle))
        .copyWith(
          title: sessionId == currentTab.sessionId
              ? nextTitle
              : currentTab.title,
        );
    state = state.copyWith(tabs: nextTabs);
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
    final nextProfiles = <TerminalProfile>[
      for (final existing in state.profiles)
        if (existing.id == profile.id) profile else existing,
      if (!state.profiles.any((existing) => existing.id == profile.id)) profile,
    ];
    _profileDocument = await ref
        .read(profileRepositoryProvider)
        .saveVersioned(
          _profileDocument.withValue(
            TerminalProfilesDocument(
              profiles: nextProfiles,
              secretClearIntents: <String, Set<ProfileSecretField>>{
                if (clearSecrets.isNotEmpty) profile.id: clearSecrets,
              },
            ),
          ),
        );
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
    final nextProfiles = state.profiles
        .where((profile) => profile.id != profileId)
        .toList();
    _profileDocument = await ref
        .read(profileRepositoryProvider)
        .saveVersioned(
          _profileDocument.withValue(
            TerminalProfilesDocument(profiles: nextProfiles),
          ),
        );
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

  String? _effectiveDefaultProfileIdFor(List<TerminalProfile> profiles) {
    final configuredDefaultId = _normalizeProfileId(
      _appPreferences.defaults.defaultProfileId,
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

  bool get _usesLocalConfigPersistence =>
      _configBootstrapSource == LocalTerminalConfigBootstrapSource.localConfig;

  Future<void> _savePreferences({
    required LocalTerminalConfigDocument Function(LocalTerminalConfigDocument)
    localConfigUpdater,
  }) async {
    if (_usesLocalConfigPersistence) {
      final repository = ref.read(localTerminalConfigRepositoryProvider);
      _localConfigDocument = await repository.update(
        localConfigUpdater,
        fallback: _localConfigDocument,
      );
    } else {
      _appPreferencesDocument = await ref
          .read(appPreferencesRepositoryProvider)
          .saveVersioned(_appPreferencesDocument);
    }
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
