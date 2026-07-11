import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;
import 'dart:io' show File, FileMode, IOSink, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/local_terminal_config_bootstrap.dart';
import '../config/local_terminal_config_loader.dart';
import '../config/local_terminal_config_models.dart';
import '../config/local_terminal_config_preferences_adapter.dart';
import '../config/local_terminal_config_repository.dart';
import '../pty/pty.dart';
import '../preferences/app_preferences_models.dart';
import '../preferences/app_preferences_repository.dart';
import '../profiles/profile_models.dart';
import '../profiles/profile_repository.dart';
import '../terminal/terminal.dart' hide TerminalEmulation;
import 'session_ports.dart';
import 'session_state.dart';

final ptySessionBackendProvider = Provider<PtySessionBackend>((ref) {
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
          request.operation == TerminalClipboardOperation.pasteRequest
              ? await ref
                    .read(sessionOsc52PromptControllerProvider)
                    .request(await promptRequestFor(request))
              : true,
        LocalTerminalOsc52Policy.allow => true,
      };
    } on Object {
      return false;
    }
  }

  final controller = TerminalRuntimeController(
    backend: ref.read(ptySessionBackendProvider),
    copyToClipboard: ref.read(sessionClipboardCopyProvider),
    readClipboard: ref.read(sessionClipboardPasteProvider),
    allowClipboardCopyWithContext: osc52ClipboardAccessAllowed,
    allowClipboardPasteRequestWithContext: osc52ClipboardAccessAllowed,
    resizeWindowBy: ref.read(sessionWindowResizeProvider),
    enableSessionPolling: ref.read(sessionPollingEnabledProvider),
    enableWarmUpRefresh: ref.read(driverWarmUpRefreshEnabledProvider),
    benchmarkEventSink: ref.watch(terminalGraphicsTraceSinkProvider),
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

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository();
});

final appPreferencesRepositoryProvider = Provider<AppPreferencesRepository>((
  ref,
) {
  return AppPreferencesRepository();
});

final localTerminalConfigRepositoryProvider =
    Provider<LocalTerminalConfigRepository>((ref) {
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

typedef _LocalConfigUpdater =
    LocalTerminalConfigDocument Function(LocalTerminalConfigDocument config);

class SessionOsc52PromptRequest {
  const SessionOsc52PromptRequest({
    required this.operation,
    this.sessionId,
    this.selection,
    this.byteCount,
    this.characterCount,
    this.textPreview,
    this.textPreviewTruncated = false,
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
    );
  }

  final TerminalClipboardOperation operation;
  final String? sessionId;
  final String? selection;
  final int? byteCount;
  final int? characterCount;
  final String? textPreview;
  final bool textPreviewTruncated;
}

typedef SessionOsc52PromptHandler =
    Future<bool> Function(SessionOsc52PromptRequest request);

class SessionOsc52PromptController {
  SessionOsc52PromptHandler? _handler;

  void setHandler(SessionOsc52PromptHandler handler) {
    _handler = handler;
  }

  void clearHandler() {
    _handler = null;
  }

  Future<bool> request(SessionOsc52PromptRequest request) async {
    final handler = _handler;
    if (handler == null) {
      return false;
    }
    return handler(request);
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
  TerminalAppPreferencesDocument _appPreferences =
      const TerminalAppPreferencesDocument();
  LocalTerminalConfigDocument _localConfigDocument =
      const LocalTerminalConfigDocument();
  LocalTerminalConfigBootstrapSource _configBootstrapSource =
      LocalTerminalConfigBootstrapSource.defaults;
  bool _preferencesLoadedFromDisk = false;
  StreamSubscription<TerminalSessionEvent>? _runtimeEventsSubscription;
  final Map<String, bool> _runtimeSessionActivation = <String, bool>{};
  bool _progressFlushScheduled = false;
  int _progressEventOrder = 0;

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
    Future.microtask(_bootstrap);
    ref.onDispose(() {
      _runtimeEventsSubscription?.cancel();
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

    _ensureRuntimeSubscription();
    final profiles = await ref.read(profileRepositoryProvider).load();
    final runtimeProfiles = profiles.profiles.isEmpty
        ? <TerminalProfile>[defaultTerminalProfile()]
        : profiles.profiles;
    final preferencesRepository = ref.read(appPreferencesRepositoryProvider);
    final configBootstrap = await _loadBootstrapConfig();
    _configBootstrapSource = configBootstrap.source;
    _localConfigDocument = configBootstrap.config;
    _preferencesLoadedFromDisk =
        configBootstrap.source != LocalTerminalConfigBootstrapSource.defaults;
    final seededPreferences =
        LocalTerminalConfigPreferencesAdapter.toAppPreferences(
          configBootstrap.config,
        );
    final resolution = _resolveBootstrapPreferences(
      profiles: runtimeProfiles,
      preferences: seededPreferences,
      explicitDefaultProfileId: bootstrapDefaultProfileIdOverride,
    );
    _appPreferences = resolution.preferences;
    if (resolution.shouldRepairWritePreferences) {
      if (_usesLocalConfigPersistence) {
        _localConfigDocument = _localConfigDocument.copyWith(
          defaultProfileId: _appPreferences.defaults.defaultProfileId,
        );
        await ref
            .read(localTerminalConfigRepositoryProvider)
            .save(_localConfigDocument);
      } else {
        await preferencesRepository.save(_appPreferences);
      }
      _preferencesLoadedFromDisk = true;
    }
    if (!ref.mounted) {
      return;
    }
    final effectiveDefaultProfileId = resolution.effectiveDefaultProfileId;
    TerminalProfile? initialProfile;
    TerminalProfile? initialLaunchProfile;
    String? initialSessionId;
    if (effectiveDefaultProfileId != null) {
      initialProfile = runtimeProfiles.firstWhere(
        (profile) => profile.id == effectiveDefaultProfileId,
        orElse: () => runtimeProfiles.first,
      );
      final environmentOverrides = ref.read(
        sessionEnvironmentOverridesProvider,
      );
      initialLaunchProfile = _profileWithSessionEnvironment(
        initialProfile,
        environmentOverrides,
      );
      initialSessionId = _createRuntimeSession(initialLaunchProfile);
    }

    state = state.copyWith(
      profiles: runtimeProfiles,
      tabs: initialSessionId == null || initialLaunchProfile == null
          ? state.tabs
          : <TerminalTab>[
              TerminalTab(
                sessionId: initialSessionId,
                title: initialLaunchProfile.name,
                profileId: initialProfile!.id,
                profileSnapshot: initialLaunchProfile,
              ),
            ],
      activeSessionId: initialSessionId,
      defaultProfileId: effectiveDefaultProfileId,
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
      configurationWarnings: profiles.loadWarnings,
      themeMode: _appPreferences.appearance.themeMode,
      terminalViewportPadding:
          _appPreferences.appearance.terminalViewportPadding,
      isReady: true,
    );
    _syncRuntimeSessionActivation();
    if (initialLaunchProfile != null) {
      _setWindowTitle(initialLaunchProfile.name);
    }
  }

  Future<LocalTerminalConfigBootstrapResult> _loadBootstrapConfig() async {
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

  void _ensureRuntimeSubscription() {
    _runtimeEventsSubscription ??= _runtime.events.listen(_handleRuntimeEvent);
  }

  void createSession(TerminalProfile profile) {
    if (ref.read(sessionDemoFixtureProvider) != null) {
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
    state = state.copyWith(
      tabs: <TerminalTab>[
        ...state.tabs,
        TerminalTab(
          sessionId: sessionId,
          title: launchProfile.name,
          profileId: profile.id,
          profileSnapshot: launchProfile,
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
    if (ref.read(sessionDemoFixtureProvider) != null) {
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

  String? _createRuntimeSession(TerminalProfile launchProfile) {
    try {
      return _runtime.createSession(launchProfile.toSessionConfig());
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

  void closeSession(String sessionId) {
    if (ref.read(sessionDemoFixtureProvider) != null) {
      _removeSessionState(sessionId);
      return;
    }
    _runtime.closeSession(sessionId);
    _removeSessionState(sessionId);
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

  void closeTab(String tabSessionId) {
    final tabIndex = state.tabs.indexWhere(
      (tab) => tab.sessionId == tabSessionId,
    );
    if (tabIndex == -1) {
      return;
    }

    final closingTab = state.tabs[tabIndex];
    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture == null) {
      for (final pane in closingTab.effectivePanes) {
        if (_runtime.hasSession(pane.sessionId)) {
          _runtime.closeSession(pane.sessionId);
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
      return;
    }
    if (state.activeSessionId == null) {
      _publishTerminalContent(
        terminalHasVisibleContent: false,
        terminalPreview: null,
      );
      return;
    }
    final activePane = _paneForSession(state.activeSessionId!);
    if (activePane != null) {
      _setWindowTitle(activePane.title);
      _publishActiveTabTerminalContent();
    }
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
      case TerminalSessionFrameEvent():
        _applyFrame(event.sessionId, event.frame);
        break;
      case TerminalSessionExitEvent():
        _removeSessionState(event.sessionId, runtimeAlreadyClosed: true);
        break;
      case TerminalSessionBellEvent():
        break;
      case TerminalSessionShellHookEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _applyShellHook(event);
        break;
      case TerminalSessionShellContextEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _applyShellContext(event);
        break;
      case TerminalSessionShellCommandEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _applyShellCommand(event);
        break;
      case TerminalSessionShellUserVarEvent():
        if (!_sessionShellIntegrationEnabled(event.sessionId)) {
          return;
        }
        _applyShellUserVar(event);
        break;
      case TerminalSessionNotificationEvent():
        _applySessionNotification(event);
        break;
      case TerminalSessionProgressEvent():
        _queueSessionProgress(event);
        break;
      case TerminalSessionBadgeEvent():
        _applySessionBadge(event);
        break;
      case TerminalSessionResetEvent():
        _applySessionReset(event);
        break;
      case TerminalSessionClipboardEvent():
        break;
      case TerminalSessionBackendErrorEvent():
        _applyBackendError(event);
        break;
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
    var nextPromptMarks = eventType == 'prompt_start' && globalLine != null
        ? _promptMarksForValues(
            current.promptMarks,
            globalLine: globalLine,
            command: command,
            cwd: current.currentDirectory,
          )
        : current.promptMarks;
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

  void _applySessionNotification(TerminalSessionNotificationEvent event) {
    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    final identifier = _boundedShellMetadata(event.identifier, 128);
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
    final source = _boundedShellMetadata(event.source, 48) ?? 'osc';
    final applicationName = _boundedShellMetadata(event.applicationName, 160);
    final notificationTypes = event.notificationTypes
        .map((value) => _boundedShellMetadata(value, 64))
        .whereType<String>()
        .take(8)
        .toList(growable: false);
    final expiresAfterMs = event.expiresAfterMs?.clamp(0, 0xFFFFFFFF);
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

  void _applySessionBadge(TerminalSessionBadgeEvent event) {
    final currentPane = _paneForSession(event.sessionId);
    if (currentPane == null) {
      return;
    }
    final text = _boundedShellMetadata(event.text, 80);
    _replaceSessionPane(event.sessionId, currentPane.copyWith(oscBadge: text));
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
      percent: event.percent?.clamp(0, 100).toInt(),
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
    if (currentTab.panes.isEmpty && currentTab.sessionId == sessionId) {
      nextTabs[tabIndex] = currentTab.copyWith(
        title: replacement.title,
        profileId: replacement.profileId,
        profileSnapshot: replacement.profileSnapshot,
        isExited: replacement.isExited,
        exitCode: replacement.exitCode,
        shellIntegration: replacement.shellIntegration,
        oscBadge: replacement.oscBadge,
        progress: replacement.progress,
        namedProgress: replacement.namedProgress,
        recentNotifications: replacement.recentNotifications,
      );
    } else {
      nextTabs[tabIndex] = currentTab.replacePane(replacement);
    }
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
            value.runes.where((rune) => rune >= 0x20 && rune != 0x7f),
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

  Future<void> saveProfile(TerminalProfile profile) async {
    final nextProfiles = <TerminalProfile>[
      for (final existing in state.profiles)
        if (existing.id == profile.id) profile else existing,
      if (!state.profiles.any((existing) => existing.id == profile.id)) profile,
    ];
    await ref
        .read(profileRepositoryProvider)
        .save(TerminalProfilesDocument(profiles: nextProfiles));
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

  Future<void> setOsc52Policy(LocalTerminalOsc52Policy policy) async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    final latestConfig = await repository.load() ?? _localConfigDocument;
    _localConfigDocument = latestConfig.copyWith(
      clipboard: latestConfig.clipboard.copyWith(osc52: policy),
    );
    _configBootstrapSource = LocalTerminalConfigBootstrapSource.localConfig;
    await repository.save(_localConfigDocument);
    _preferencesLoadedFromDisk = true;
  }

  Future<void> deleteProfile(String profileId) async {
    final nextProfiles = state.profiles
        .where((profile) => profile.id != profileId)
        .toList();
    await ref
        .read(profileRepositoryProvider)
        .save(TerminalProfilesDocument(profiles: nextProfiles));
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
    required _LocalConfigUpdater localConfigUpdater,
  }) async {
    if (_usesLocalConfigPersistence) {
      final repository = ref.read(localTerminalConfigRepositoryProvider);
      final latestConfig = await repository.load() ?? _localConfigDocument;
      _localConfigDocument = localConfigUpdater(latestConfig);
      await repository.save(_localConfigDocument);
    } else {
      await ref.read(appPreferencesRepositoryProvider).save(_appPreferences);
    }
    _preferencesLoadedFromDisk = true;
  }

  _BootstrapPreferencesResolution _resolveBootstrapPreferences({
    required List<TerminalProfile> profiles,
    required TerminalAppPreferencesDocument preferences,
    required String? explicitDefaultProfileId,
  }) {
    final explicitDefaultId = _normalizeProfileId(explicitDefaultProfileId);
    if (_hasProfileId(profiles, explicitDefaultId)) {
      return _BootstrapPreferencesResolution(
        effectiveDefaultProfileId: explicitDefaultId,
        preferences: preferences,
      );
    }

    final preferencesDefaultId = _normalizeProfileId(
      preferences.defaults.defaultProfileId,
    );
    if (_hasProfileId(profiles, preferencesDefaultId)) {
      return _BootstrapPreferencesResolution(
        effectiveDefaultProfileId: preferencesDefaultId,
        preferences: preferences,
      );
    }

    if (preferencesDefaultId != null) {
      final repairedPreferences = preferences.copyWith(
        defaults: preferences.defaults.copyWith(defaultProfileId: null),
      );
      return _BootstrapPreferencesResolution(
        effectiveDefaultProfileId: profiles.isEmpty ? null : profiles.first.id,
        preferences: repairedPreferences,
        shouldRepairWritePreferences: true,
      );
    }

    return _BootstrapPreferencesResolution(
      effectiveDefaultProfileId: profiles.isEmpty ? null : profiles.first.id,
      preferences: preferences,
    );
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

class _BootstrapPreferencesResolution {
  const _BootstrapPreferencesResolution({
    required this.effectiveDefaultProfileId,
    required this.preferences,
    this.shouldRepairWritePreferences = false,
  });

  final String? effectiveDefaultProfileId;
  final TerminalAppPreferencesDocument preferences;
  final bool shouldRepairWritePreferences;
}
