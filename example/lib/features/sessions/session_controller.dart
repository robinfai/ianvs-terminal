import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';

import '../preferences/app_preferences_models.dart';
import '../preferences/app_preferences_repository.dart';
import '../profiles/profile_models.dart';
import '../profiles/profile_repository.dart';
import 'session_ports.dart';
import 'session_state.dart';

final ptySessionBackendProvider = Provider<PtySessionBackend>((ref) {
  return NativePtyBackend.load();
});

final terminalRuntimeControllerProvider = Provider<TerminalRuntimeController>((
  ref,
) {
  final controller = TerminalRuntimeController(
    backend: ref.read(ptySessionBackendProvider),
    copyToClipboard: ref.read(sessionClipboardCopyProvider),
    readClipboard: ref.read(sessionClipboardPasteProvider),
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

final sessionPollingEnabledProvider = Provider<bool>((ref) => true);
final driverWarmUpRefreshEnabledProvider = Provider<bool>((ref) => false);
final sessionEnvironmentOverridesProvider = Provider<Map<String, String>>((
  ref,
) {
  return const <String, String>{};
});

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  final Map<String, TerminalViewportController> _demoViewports =
      <String, TerminalViewportController>{};
  TerminalAppPreferencesDocument _appPreferences =
      const TerminalAppPreferencesDocument();
  bool _preferencesLoadedFromDisk = false;
  StreamSubscription<TerminalSessionEvent>? _runtimeEventsSubscription;

  @protected
  String? get bootstrapDefaultProfileIdOverride => null;

  TerminalRuntimeController get _runtime =>
      ref.read(terminalRuntimeControllerProvider);

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
        final frame = demoFixture.frameFor(tab.sessionId);
        if (frame == null) {
          continue;
        }
        _demoViewports
            .putIfAbsent(tab.sessionId, TerminalViewportController.new)
            .updateFrame(frame);
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
    final persistedPreferences = await preferencesRepository.load();
    _preferencesLoadedFromDisk = persistedPreferences != null;
    final seededPreferences =
        persistedPreferences ?? const TerminalAppPreferencesDocument();
    final resolution = _resolveBootstrapPreferences(
      profiles: runtimeProfiles,
      preferences: seededPreferences,
      explicitDefaultProfileId: bootstrapDefaultProfileIdOverride,
    );
    _appPreferences = resolution.preferences;
    if (resolution.shouldRepairWritePreferences) {
      await preferencesRepository.save(_appPreferences);
      _preferencesLoadedFromDisk = true;
    }
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      profiles: runtimeProfiles,
      defaultProfileId: resolution.effectiveDefaultProfileId,
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
      configurationWarnings: profiles.loadWarnings,
      themeMode: _appPreferences.appearance.themeMode,
      isReady: true,
    );
    if (resolution.effectiveDefaultProfileId != null) {
      createSession(
        runtimeProfiles.firstWhere(
          (profile) => profile.id == resolution.effectiveDefaultProfileId,
          orElse: () => runtimeProfiles.first,
        ),
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
    final launchProfile = environmentOverrides.isEmpty
        ? profile
        : profile.copyWith(
            env: <String, String>{...profile.env, ...environmentOverrides},
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

  void activateSession(String sessionId) {
    state = state.copyWith(activeSessionId: sessionId);
    for (final tab in state.tabs) {
      if (tab.sessionId == sessionId) {
        _setWindowTitle(tab.title);
        break;
      }
    }
    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      _publishDemoContent(demoFixture, sessionId);
    }
  }

  void closeSession(String sessionId) {
    if (ref.read(sessionDemoFixtureProvider) != null) {
      _removeSessionState(sessionId);
      return;
    }
    _runtime.closeSession(sessionId);
    _removeSessionState(sessionId);
  }

  void resizeActiveSession(Size viewportSize, double devicePixelRatio) {
    if (ref.read(sessionDemoFixtureProvider) != null) {
      return;
    }
    final sessionId = state.activeSessionId;
    if (sessionId == null) {
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
    final tabIndex = state.tabs.indexWhere((tab) => tab.sessionId == sessionId);
    if (tabIndex == -1) {
      return;
    }

    final currentTab = state.tabs[tabIndex];
    final nextTitle = _resolvedTabTitle(
      currentTab,
      windowTitle: windowTitle,
      windowIconName: windowIconName,
    );
    if (nextTitle == currentTab.title) {
      return;
    }

    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = currentTab.copyWith(title: nextTitle);
    state = state.copyWith(tabs: nextTabs);
    if (sessionId == state.activeSessionId) {
      _setWindowTitle(nextTitle);
    }
  }

  String _resolvedTabTitle(
    TerminalTab tab, {
    String? windowTitle,
    String? windowIconName,
  }) {
    if (windowTitle != null && windowTitle.isNotEmpty) {
      return windowTitle;
    }
    if (windowIconName != null && windowIconName.isNotEmpty) {
      return windowIconName;
    }

    final profileSnapshot = tab.profileSnapshot;
    if (profileSnapshot != null) {
      return profileSnapshot.name;
    }

    for (final profile in state.profiles) {
      if (profile.id == tab.profileId) {
        return profile.name;
      }
    }
    return tab.title;
  }

  void _removeSessionState(
    String sessionId, {
    bool runtimeAlreadyClosed = false,
  }) {
    final nextTabs = state.tabs
        .where((tab) => tab.sessionId != sessionId)
        .toList();
    final nextActiveSessionId = state.activeSessionId == sessionId
        ? (nextTabs.isEmpty ? null : nextTabs.last.sessionId)
        : state.activeSessionId;

    state = state.copyWith(
      tabs: nextTabs,
      activeSessionId: nextActiveSessionId,
    );

    final demoFixture = ref.read(sessionDemoFixtureProvider);
    if (demoFixture != null) {
      _demoViewports.remove(sessionId)?.dispose();
      if (nextTabs.isEmpty) {
        _publishTerminalContent(
          terminalHasVisibleContent: false,
          terminalPreview: null,
        );
      } else {
        _publishDemoContent(demoFixture, nextActiveSessionId);
      }
      return;
    }

    if (nextActiveSessionId != null) {
      final activeTab = nextTabs.firstWhere(
        (tab) => tab.sessionId == nextActiveSessionId,
      );
      _setWindowTitle(activeTab.title);
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
    await ref.read(appPreferencesRepositoryProvider).save(_appPreferences);
    _preferencesLoadedFromDisk = true;
    state = state.copyWith(
      defaultProfileId: _effectiveDefaultProfileIdFor(state.profiles),
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
    );
  }

  Future<void> resetDefaultProfile() async {
    _appPreferences = _appPreferences.copyWith(
      defaults: _appPreferences.defaults.copyWith(defaultProfileId: null),
    );
    await ref.read(appPreferencesRepositoryProvider).save(_appPreferences);
    _preferencesLoadedFromDisk = true;
    state = state.copyWith(
      defaultProfileId: _effectiveDefaultProfileIdFor(state.profiles),
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
    );
  }

  Future<void> setThemeMode(TerminalThemeMode themeMode) async {
    _appPreferences = _appPreferences.copyWith(
      appearance: _appPreferences.appearance.copyWith(themeMode: themeMode),
    );
    await ref.read(appPreferencesRepositoryProvider).save(_appPreferences);
    _preferencesLoadedFromDisk = true;
    state = state.copyWith(themeMode: _appPreferences.appearance.themeMode);
  }

  Future<void> resetThemeMode() async {
    await setThemeMode(TerminalThemeMode.system);
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
      await ref.read(appPreferencesRepositoryProvider).save(_appPreferences);
      _preferencesLoadedFromDisk = true;
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
    if (profileId == null || profileId.isEmpty) {
      return null;
    }
    return profileId;
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
