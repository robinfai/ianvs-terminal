import 'dart:async';

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

final terminalRuntimeControllerProvider = Provider<TerminalRuntimeController>((
  ref,
) {
  Future<bool> osc52ClipboardAccessAllowed() async {
    try {
      final config = await ref.read(localTerminalConfigLoaderProvider).load();
      return switch (config.config.clipboard.osc52) {
        LocalTerminalOsc52Policy.disabled => false,
        LocalTerminalOsc52Policy.profile ||
        LocalTerminalOsc52Policy.allow => true,
      };
    } on Object {
      return true;
    }
  }

  final controller = TerminalRuntimeController(
    backend: ref.read(ptySessionBackendProvider),
    copyToClipboard: ref.read(sessionClipboardCopyProvider),
    readClipboard: ref.read(sessionClipboardPasteProvider),
    allowClipboardCopy: osc52ClipboardAccessAllowed,
    allowClipboardPasteRequest: osc52ClipboardAccessAllowed,
    resizeWindowBy: ref.read(sessionWindowResizeProvider),
    enableSessionPolling: ref.read(sessionPollingEnabledProvider),
    enableWarmUpRefresh: ref.read(driverWarmUpRefreshEnabledProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

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
final sessionEnvironmentOverridesProvider = Provider<Map<String, String>>((
  ref,
) {
  return const <String, String>{};
});

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

typedef _LocalConfigUpdater =
    LocalTerminalConfigDocument Function(LocalTerminalConfigDocument config);

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
  final List<TerminalTab> _recentlyClosedTabs = <TerminalTab>[];
  final Map<String, List<TerminalPane>> _recentlyClosedPanesByTabSessionId =
      <String, List<TerminalPane>>{};
  TerminalAppPreferencesDocument _appPreferences =
      const TerminalAppPreferencesDocument();
  LocalTerminalConfigDocument _localConfigDocument =
      const LocalTerminalConfigDocument();
  LocalTerminalConfigBootstrapSource _configBootstrapSource =
      LocalTerminalConfigBootstrapSource.defaults;
  bool _preferencesLoadedFromDisk = false;
  StreamSubscription<TerminalSessionEvent>? _runtimeEventsSubscription;

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
    final tabSessionId = state.tabs[tabIndex].sessionId;
    return _recentlyClosedPanesByTabSessionId[tabSessionId]?.isNotEmpty ??
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
      initialSessionId = _runtime.createSession(
        initialLaunchProfile.toSessionConfig(),
      );
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
    final sessionId = _runtime.createSession(launchProfile.toSessionConfig());
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
    _setWindowTitle(launchProfile.name);
  }

  void splitActiveSession(TerminalProfile profile, TerminalSplitAxis axis) {
    if (ref.read(sessionDemoFixtureProvider) != null) {
      return;
    }
    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      createSession(profile);
      return;
    }

    final activeTabIndex = _tabIndexContainingSession(activeSessionId);
    if (activeTabIndex == -1) {
      createSession(profile);
      return;
    }

    _ensureRuntimeSubscription();
    final environmentOverrides = ref.read(sessionEnvironmentOverridesProvider);
    final launchProfile = _profileWithSessionEnvironment(
      profile,
      environmentOverrides,
    );
    final sessionId = _runtime.createSession(launchProfile.toSessionConfig());
    final newPane = TerminalPane(
      sessionId: sessionId,
      title: launchProfile.name,
      profileId: profile.id,
      profileSnapshot: launchProfile,
    );
    final activeTab = state.tabs[activeTabIndex];
    final nextPaneLayout = activeTab.effectivePaneLayout.splitPane(
      sessionId: activeSessionId,
      newPane: newPane,
      axis: axis,
    );
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[activeTabIndex] = activeTab.copyWith(
      panes: nextPaneLayout.panes,
      paneLayout: nextPaneLayout,
      activePaneSessionId: sessionId,
      splitAxis: axis,
    );
    state = state.copyWith(tabs: nextTabs, activeSessionId: sessionId);
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
    _setWindowTitle(pane.title);

    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      _publishDemoContent(demoFixture, pane.sessionId);
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
    final tabIndex = _tabIndexContainingSession(activeSessionId);
    if (tabIndex == -1) {
      return;
    }

    final activeTab = state.tabs[tabIndex];
    final nextPaneLayout = activeTab.effectivePaneLayout.resizeSplit(
      splitNodeId,
      ratio,
    );
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = activeTab.copyWith(
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
      final sessionId = _runtime.createSession(launchProfile.toSessionConfig());
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
    final activePane = reopenedTab.paneFor(activeSessionId);
    _setWindowTitle(activePane?.title ?? reopenedTab.title);
  }

  void reopenClosedPane({
    TerminalSplitAxis axis = TerminalSplitAxis.horizontal,
  }) {
    if (ref.read(sessionDemoFixtureProvider) != null) {
      return;
    }
    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final activeTabIndex = _tabIndexContainingSession(activeSessionId);
    if (activeTabIndex == -1) {
      return;
    }
    final activeTab = state.tabs[activeTabIndex];
    final closedPanes = _recentlyClosedPanesByTabSessionId[activeTab.sessionId];
    if (closedPanes == null || closedPanes.isEmpty) {
      return;
    }

    final sourcePane = closedPanes.removeAt(0);
    if (closedPanes.isEmpty) {
      _recentlyClosedPanesByTabSessionId.remove(activeTab.sessionId);
    }
    final profile = _profileForClosedPane(sourcePane);
    if (profile == null) {
      return;
    }

    _ensureRuntimeSubscription();
    final environmentOverrides = ref.read(sessionEnvironmentOverridesProvider);
    final launchProfile = _profileWithSessionEnvironment(
      profile,
      environmentOverrides,
    );
    final sessionId = _runtime.createSession(launchProfile.toSessionConfig());
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
    nextTabs[activeTabIndex] = activeTab.copyWith(
      panes: nextPaneLayout.panes,
      paneLayout: nextPaneLayout,
      activePaneSessionId: sessionId,
      splitAxis: axis,
    );
    state = state.copyWith(tabs: nextTabs, activeSessionId: sessionId);
    _setWindowTitle(sourcePane.title);
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
        _applyShellHook(event);
        break;
    }
  }

  void _applyFrame(String sessionId, TerminalFrameDiff frame) {
    _updateTabTitleFromFrame(
      sessionId,
      windowTitle: frame.windowTitle,
      windowIconName: frame.windowIconName,
    );

    String? preview;
    for (final row in frame.rows) {
      final text = row.text.trim();
      if (text.isNotEmpty) {
        preview = text;
        break;
      }
    }
    _publishTerminalContent(
      terminalHasVisibleContent: preview != null,
      terminalPreview: preview,
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

  TerminalShellIntegrationSnapshot _shellIntegrationForHook(
    TerminalShellIntegrationSnapshot current,
    TerminalSessionShellHookEvent event,
  ) {
    final command = _trimShellHookValue(event.command);
    final cwd = _trimShellHookValue(event.cwd);
    final hostname = _trimShellHookValue(event.hostname);
    final username = _trimShellHookValue(event.username);
    final shell = _trimShellHookValue(event.shell);
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
    required String? command,
    required String? cwd,
  }) {
    final promptOffset = event.promptScrollbackOffset;
    if (promptOffset == null || promptOffset < 0) {
      return current;
    }

    final nextMarks = <TerminalShellPromptMark>[
      for (final mark in current)
        if (mark.scrollbackOffset != promptOffset) mark,
      TerminalShellPromptMark(
        scrollbackOffset: promptOffset,
        command: command,
        cwd: cwd,
      ),
    ];
    final boundedMarks = nextMarks.length > 100
        ? nextMarks.sublist(nextMarks.length - 100)
        : nextMarks;
    boundedMarks.sort(
      (a, b) => a.scrollbackOffset.compareTo(b.scrollbackOffset),
    );
    return boundedMarks;
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
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
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
      nextTabs[tabIndex] = TerminalTab(
        sessionId: currentTab.sessionId,
        title: baseline.title,
        profileId: baseline.profileId,
        profileSnapshot: baseline.profileSnapshot,
        isExited: currentTab.isExited,
        exitCode: currentTab.exitCode,
        panes: currentTab.panes,
        paneLayout: currentTab.paneLayout,
        activePaneSessionId: currentTab.activePaneSessionId,
        splitAxis: currentTab.splitAxis,
        shellIntegration: shellIntegration,
      );
    } else {
      nextTabs[tabIndex] = currentTab
          .replacePane(
            TerminalPane(
              sessionId: currentPane.sessionId,
              title: baseline.title,
              profileId: baseline.profileId,
              profileSnapshot: baseline.profileSnapshot,
              isExited: currentPane.isExited,
              exitCode: currentPane.exitCode,
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
    final frame = sessionId == null ? null : fixture.frameFor(sessionId);
    final preview = frame == null ? null : _previewForFrame(frame);
    _publishTerminalContent(
      terminalHasVisibleContent: preview != null,
      terminalPreview: preview,
    );
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
      final closingPane = tab.paneFor(sessionId);
      if (!runtimeAlreadyClosed && closingPane != null) {
        _recordRecentlyClosedPane(tab.sessionId, closingPane);
      }
      final nextPaneLayout = tab.effectivePaneLayout.removePane(sessionId);
      if (nextPaneLayout == null) {
        _removeTabState(tabIndex, recordClosedTab: !runtimeAlreadyClosed);
        return;
      }
      final nextPanes = nextPaneLayout.panes;
      final closingActivePane = state.activeSessionId == sessionId;
      final nextActivePaneId = closingActivePane
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
        activeSessionId: closingActivePane
            ? nextActivePaneId
            : state.activeSessionId,
      );
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
    _recentlyClosedPanesByTabSessionId.remove(closingTab.sessionId);
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
  }

  void _recordRecentlyClosedPane(String tabSessionId, TerminalPane pane) {
    final closedPanes = _recentlyClosedPanesByTabSessionId.putIfAbsent(
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
    final nextPadding = padding
        .clamp(
          TerminalAppAppearance.minTerminalViewportPadding,
          TerminalAppAppearance.maxTerminalViewportPadding,
        )
        .toDouble();
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
