import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart'
    hide TerminalEmulation;

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
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[activeTabIndex] = activeTab.copyWith(
      panes: <TerminalPane>[...activeTab.effectivePanes, newPane],
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
    return profile.copyWith(
      env: <String, String>{
        ..._defaultEnvironmentForEmulation(profile.terminalEmulation),
        ...profile.env,
        ...environmentOverrides,
      },
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
    _removeTabState(tabIndex);
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
      nextTabs[tabIndex] = currentTab.copyWith(
        panes: [
          for (final pane in currentTab.effectivePanes)
            if (pane.sessionId == event.sessionId)
              pane.copyWith(shellIntegration: nextIntegration)
            else
              pane,
        ],
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

    final nextTabs = <TerminalTab>[...state.tabs];
    if (currentTab.panes.isEmpty && currentTab.sessionId == sessionId) {
      nextTabs[tabIndex] = currentTab.copyWith(
        title: profile.name,
        profileId: profile.id,
        profileSnapshot: profile,
        shellIntegration: shellIntegration,
      );
    } else {
      nextTabs[tabIndex] = currentTab.copyWith(
        title: sessionId == currentTab.sessionId
            ? profile.name
            : currentTab.title,
        panes: [
          for (final pane in currentTab.effectivePanes)
            if (pane.sessionId == sessionId)
              pane.copyWith(
                title: profile.name,
                profileId: profile.id,
                profileSnapshot: profile,
                shellIntegration: shellIntegration,
              )
            else
              pane,
        ],
      );
    }
    state = state.copyWith(tabs: nextTabs);
    if (sessionId == state.activeSessionId) {
      _setWindowTitle(profile.name);
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

    final nextPanes = <TerminalPane>[
      for (final pane in currentTab.effectivePanes)
        if (pane.sessionId == sessionId)
          pane.copyWith(title: nextTitle)
        else
          pane,
    ];
    final nextTabs = <TerminalTab>[...state.tabs];
    nextTabs[tabIndex] = currentTab.copyWith(
      title: sessionId == currentTab.sessionId ? nextTitle : currentTab.title,
      panes: nextPanes,
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
    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex == -1) {
      return;
    }

    final tab = state.tabs[tabIndex];
    final tabHasMultiplePanes = tab.effectivePanes.length > 1;
    if (!tabHasMultiplePanes) {
      _removeTabState(tabIndex);
    } else {
      final nextPanes = tab.effectivePanes
          .where((pane) => pane.sessionId != sessionId)
          .toList();
      final closingActivePane = state.activeSessionId == sessionId;
      final nextActivePaneId = closingActivePane
          ? nextPanes.last.sessionId
          : tab.activeSessionId;
      final nextTabs = <TerminalTab>[...state.tabs];
      nextTabs[tabIndex] = tab.copyWith(
        panes: nextPanes,
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

  void _removeTabState(int tabIndex) {
    final closingTab = state.tabs[tabIndex];
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
