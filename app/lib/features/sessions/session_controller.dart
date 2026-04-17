import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/flutterm_core.dart';
import '../preferences/app_preferences_models.dart';
import '../preferences/app_preferences_repository.dart';
import '../profiles/profile_models.dart';
import '../profiles/profile_repository.dart';
import '../shell/shell_acceptance.dart';
import '../shell/reference_demo.dart';
import '../terminal/terminal_viewport.dart';
import 'session_state.dart';

final terminalCoreClientProvider = Provider<TerminalCoreClient>((ref) {
  return TerminalCoreClient.load();
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
  final Map<String, TerminalViewportController> _viewportControllers = {};
  final Map<String, _SessionResizeMetric> _lastResizeMetrics = {};
  TerminalAppPreferencesDocument _appPreferences =
      const TerminalAppPreferencesDocument();
  String? _legacyDefaultProfileId;
  bool _preferencesLoadedFromDisk = false;
  Timer? _pollTimer;
  final Map<String, List<Timer>> _warmUpTimers = {};

  @protected
  String? get bootstrapDefaultProfileIdOverride => null;

  @override
  SessionState build() {
    Future.microtask(_bootstrap);
    ref.onDispose(() {
      _pollTimer?.cancel();
      for (final timers in _warmUpTimers.values) {
        for (final timer in timers) {
          timer.cancel();
        }
      }
      for (final controller in _viewportControllers.values) {
        controller.dispose();
      }
    });
    return SessionState.initial();
  }

  TerminalViewportController viewportFor(String sessionId) {
    return _viewportControllers.putIfAbsent(
      sessionId,
      TerminalViewportController.new,
    );
  }

  Future<void> _bootstrap() async {
    if (ref.read(referenceDemoModeProvider)) {
      for (final tab in referenceDemoTabs) {
        _viewportControllers.putIfAbsent(
          tab.sessionId,
          TerminalViewportController.new,
        ).updateFrame(referenceDemoFrame);
      }
      state = state.copyWith(
        profiles: [defaultTerminalProfile()],
        tabs: referenceDemoTabs,
        activeSessionId: referenceDemoActiveSessionId,
        defaultProfileId: defaultTerminalProfile().id,
        themeMode: TerminalThemeMode.dark,
        isReady: true,
      );
      shellAcceptanceProbe.mergeTerminalContent(
        terminalHasVisibleContent: true,
        terminalPreview: referenceDemoFrame.rows.first.text,
      );
      return;
    }

    final profiles = await ref.read(profileRepositoryProvider).load();
    final runtimeProfiles = profiles.profiles.isEmpty
        ? [defaultTerminalProfile()]
        : profiles.profiles;
    final preferencesRepository = ref.read(appPreferencesRepositoryProvider);
    _legacyDefaultProfileId = _normalizeProfileId(profiles.defaultProfileId);
    final persistedPreferences = await preferencesRepository.load();
    _preferencesLoadedFromDisk = persistedPreferences != null;
    final seededPreferences =
        persistedPreferences ??
        TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(
            defaultProfileId: _legacyDefaultProfileId,
          ),
        );
    final resolution = _resolveBootstrapPreferences(
      profiles: runtimeProfiles,
      preferences: seededPreferences,
      explicitDefaultProfileId: bootstrapDefaultProfileIdOverride,
      allowLegacyFallback: persistedPreferences == null,
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
      themeMode: _appPreferences.appearance.themeMode,
      isReady: true,
    );
    if (ref.read(sessionPollingEnabledProvider)) {
      _startPolling();
    }
    if (resolution.effectiveDefaultProfileId != null) {
      createSession(
        runtimeProfiles.firstWhere(
          (profile) => profile.id == resolution.effectiveDefaultProfileId,
          orElse: () => runtimeProfiles.first,
        ),
      );
    }
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      for (final tab in state.tabs) {
        final frame = ref
            .read(terminalCoreClientProvider)
            .takeFrameDiff(tab.sessionId);
        if (frame != null) {
          viewportFor(tab.sessionId).updateFrame(frame);
        }

        final events = ref
            .read(terminalCoreClientProvider)
            .pollEvents(tab.sessionId);
        for (final event in events) {
          if (event.kind == 'exit') {
            closeSession(tab.sessionId);
            break;
          }
        }
      }
    });
  }

  void createSession(TerminalProfile profile) {
    if (ref.read(referenceDemoModeProvider)) {
      return;
    }
    final environmentOverrides = ref.read(sessionEnvironmentOverridesProvider);
    final launchProfile = environmentOverrides.isEmpty
        ? profile
        : profile.copyWith(
            env: {
              ...profile.env,
              ...environmentOverrides,
            },
          );
    final sessionId = ref
        .read(terminalCoreClientProvider)
        .createSession(launchProfile);
    _viewportControllers.putIfAbsent(sessionId, TerminalViewportController.new);
    state = state.copyWith(
      tabs: [
        ...state.tabs,
        TerminalTab(
          sessionId: sessionId,
          title: profile.name,
          profileId: profile.id,
        ),
      ],
      activeSessionId: sessionId,
    );
    if (!ref.read(sessionPollingEnabledProvider)) {
      _refreshSession(sessionId);
      _scheduleWarmUpRefreshes(sessionId);
    }
  }

  void activateSession(String sessionId) {
    state = state.copyWith(activeSessionId: sessionId);
    if (ref.read(referenceDemoModeProvider)) {
      shellAcceptanceProbe.mergeTerminalContent(
        terminalHasVisibleContent: true,
        terminalPreview: referenceDemoFrame.rows.first.text,
      );
    }
  }

  void closeSession(String sessionId) {
    if (ref.read(referenceDemoModeProvider)) {
      final nextTabs = state.tabs
          .where((tab) => tab.sessionId != sessionId)
          .toList();
      final nextActiveSessionId = nextTabs.isEmpty
          ? null
          : nextTabs.last.sessionId;
      state = state.copyWith(
        tabs: nextTabs,
        activeSessionId: nextActiveSessionId,
      );
      if (nextTabs.isEmpty) {
        shellAcceptanceProbe.mergeTerminalContent(
          terminalHasVisibleContent: false,
          terminalPreview: null,
        );
      } else {
        shellAcceptanceProbe.mergeTerminalContent(
          terminalHasVisibleContent: true,
          terminalPreview: referenceDemoFrame.rows.first.text,
        );
      }
      return;
    }
    ref.read(terminalCoreClientProvider).closeSession(sessionId);
    for (final timer in _warmUpTimers.remove(sessionId) ?? const <Timer>[]) {
      timer.cancel();
    }
    _viewportControllers.remove(sessionId)?.dispose();
    _lastResizeMetrics.remove(sessionId);

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
    if (nextTabs.isEmpty) {
      shellAcceptanceProbe.mergeTerminalContent(
        terminalHasVisibleContent: false,
        terminalPreview: null,
      );
    }
  }

  void resizeActiveSession(Size viewportSize, double devicePixelRatio) {
    if (ref.read(referenceDemoModeProvider)) {
      return;
    }
    final sessionId = state.activeSessionId;
    if (sessionId == null) {
      return;
    }
    final cellWidth = 9.0;
    final cellHeight = 18.0;
    final cols = math.max(20, (viewportSize.width / cellWidth).floor());
    final rows = math.max(8, (viewportSize.height / cellHeight).floor());
    final pixelWidth = (viewportSize.width * devicePixelRatio).round();
    final pixelHeight = (viewportSize.height * devicePixelRatio).round();
    final previous = _lastResizeMetrics[sessionId];
    if (previous != null &&
        previous.cols == cols &&
        previous.rows == rows &&
        previous.pixelWidth == pixelWidth &&
        previous.pixelHeight == pixelHeight) {
      return;
    }
    ref
        .read(terminalCoreClientProvider)
        .resizeSession(
          sessionId,
          cols: cols,
          rows: rows,
          pixelSize: Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
          devicePixelRatio: 1,
        );
    _lastResizeMetrics[sessionId] = _SessionResizeMetric(
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
    if (!ref.read(sessionPollingEnabledProvider)) {
      _refreshSession(sessionId);
    }
  }

  void _refreshSession(String sessionId) {
    final frame = ref.read(terminalCoreClientProvider).takeFrameDiff(sessionId);
    if (frame != null) {
      viewportFor(sessionId).updateFrame(frame);
      String? preview;
      for (final row in frame.rows) {
        final text = row.text.trim();
        if (text.isNotEmpty) {
          preview = text;
          break;
        }
      }
      shellAcceptanceProbe.mergeTerminalContent(
        terminalHasVisibleContent: preview != null,
        terminalPreview: preview,
      );
    } else {
      shellAcceptanceProbe.mergeTerminalContent(
        terminalHasVisibleContent: false,
        terminalPreview: null,
      );
    }
    final events = ref.read(terminalCoreClientProvider).pollEvents(sessionId);
    for (final event in events) {
      if (event.kind == 'exit') {
        closeSession(sessionId);
        break;
      }
    }
  }

  void _scheduleWarmUpRefreshes(String sessionId) {
    if (!ref.read(driverWarmUpRefreshEnabledProvider)) {
      return;
    }

    for (final timer in _warmUpTimers.remove(sessionId) ?? const <Timer>[]) {
      timer.cancel();
    }

    final delays = <Duration>[
      const Duration(milliseconds: 60),
      const Duration(milliseconds: 140),
      const Duration(milliseconds: 260),
    ];
    final timers = <Timer>[];
    for (final delay in delays) {
      timers.add(
        Timer(delay, () {
          if (!ref.mounted) {
            return;
          }
          if (!state.tabs.any((tab) => tab.sessionId == sessionId)) {
            return;
          }
          final controller = _viewportControllers[sessionId];
          final hasVisibleContent = controller != null &&
              controller.frame.rows.any((row) => row.text.trim().isNotEmpty);
          if (hasVisibleContent) {
            for (final timer in _warmUpTimers.remove(sessionId) ?? const <Timer>[]) {
              timer.cancel();
            }
            return;
          }
          _refreshSession(sessionId);
        }),
      );
    }
    _warmUpTimers[sessionId] = timers;
  }

  Future<void> saveProfile(TerminalProfile profile) async {
    final nextProfiles = [
      for (final existing in state.profiles)
        if (existing.id == profile.id) profile else existing,
      if (!state.profiles.any((existing) => existing.id == profile.id)) profile,
    ];
    await ref
        .read(profileRepositoryProvider)
        .save(
          TerminalProfilesDocument(
            defaultProfileId: _legacyDefaultProfileId ?? '',
            profiles: nextProfiles,
          ),
        );
    state = state.copyWith(
      profiles: nextProfiles,
      defaultProfileId: _effectiveDefaultProfileIdFor(nextProfiles),
      configuredDefaultProfileId: _configuredDefaultProfileIdForUi(),
    );
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
        .save(
          TerminalProfilesDocument(
            defaultProfileId: _legacyDefaultProfileId ?? '',
            profiles: nextProfiles,
          ),
        );
    final deletedConfiguredDefault =
        _normalizeProfileId(_appPreferences.defaults.defaultProfileId) ==
            profileId ||
        (!_preferencesLoadedFromDisk && _legacyDefaultProfileId == profileId);
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
    required bool allowLegacyFallback,
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

    if (allowLegacyFallback &&
        _hasProfileId(profiles, _legacyDefaultProfileId)) {
      return _BootstrapPreferencesResolution(
        effectiveDefaultProfileId: _legacyDefaultProfileId,
        preferences: preferences,
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

class _SessionResizeMetric {
  _SessionResizeMetric({
    required this.cols,
    required this.rows,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final int cols;
  final int rows;
  final int pixelWidth;
  final int pixelHeight;
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
