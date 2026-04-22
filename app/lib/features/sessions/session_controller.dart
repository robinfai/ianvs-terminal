import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/flutterm_core.dart';
import '../preferences/app_preferences_models.dart';
import '../preferences/app_preferences_repository.dart';
import '../profiles/profile_models.dart';
import '../profiles/profile_repository.dart';
import '../shell/shell_acceptance.dart';
import '../shell/reference_demo.dart';
import '../shell/window_bridge.dart';
import '../terminal/clipboard_bridge.dart';
import '../terminal/terminal_painter_models.dart';
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
        _viewportControllers
            .putIfAbsent(tab.sessionId, TerminalViewportController.new)
            .updateFrame(referenceDemoFrame);
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
          _applyFrame(tab.sessionId, frame);
        }

        final events = ref
            .read(terminalCoreClientProvider)
            .pollEvents(tab.sessionId);
        unawaited(_processEvents(tab.sessionId, events));
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
        : profile.copyWith(env: {...profile.env, ...environmentOverrides});
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
    unawaited(WindowBridge.setTitle(launchProfile.name));
    if (!ref.read(sessionPollingEnabledProvider)) {
      _refreshSession(sessionId);
      _scheduleWarmUpRefreshes(sessionId);
    }
  }

  void activateSession(String sessionId) {
    state = state.copyWith(activeSessionId: sessionId);
    TerminalTab? activeTab;
    for (final tab in state.tabs) {
      if (tab.sessionId == sessionId) {
        activeTab = tab;
        break;
      }
    }
    if (activeTab != null) {
      unawaited(WindowBridge.setTitle(activeTab.title));
    }
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
    final measuredCellSize = _cellSizeFor(sessionId);
    final cellWidth = measuredCellSize.width;
    final cellHeight = measuredCellSize.height;
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
      logicalWidth: viewportSize.width,
      logicalHeight: viewportSize.height,
      devicePixelRatio: devicePixelRatio,
    );
    if (!ref.read(sessionPollingEnabledProvider)) {
      _refreshSession(sessionId);
    }
  }

  void _refreshSession(String sessionId) {
    final frame = ref.read(terminalCoreClientProvider).takeFrameDiff(sessionId);
    if (frame != null) {
      _applyFrame(sessionId, frame);
    } else {
      shellAcceptanceProbe.mergeTerminalContent(
        terminalHasVisibleContent: false,
        terminalPreview: null,
      );
    }
    final events = ref.read(terminalCoreClientProvider).pollEvents(sessionId);
    unawaited(_processEvents(sessionId, events));
  }

  void _applyFrame(String sessionId, TerminalFrameDiff frame) {
    viewportFor(sessionId).updateFrame(frame);
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
    shellAcceptanceProbe.mergeTerminalContent(
      terminalHasVisibleContent: preview != null,
      terminalPreview: preview,
    );
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

    final nextTabs = [...state.tabs];
    nextTabs[tabIndex] = currentTab.copyWith(title: nextTitle);
    state = state.copyWith(tabs: nextTabs);
    if (sessionId == state.activeSessionId) {
      unawaited(WindowBridge.setTitle(nextTitle));
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

    for (final profile in state.profiles) {
      if (profile.id == tab.profileId) {
        return profile.name;
      }
    }
    return tab.title;
  }

  Future<void> _processEvents(
    String sessionId,
    List<TerminalEvent> events,
  ) async {
    for (final event in events) {
      switch (event.kind) {
        case 'exit':
          closeSession(sessionId);
          return;
        case 'resize':
          await _handleResizeEvent(sessionId, event.payload);
          break;
        case 'clipboard_copy':
          await _handleClipboardCopyEvent(event.payload);
          break;
        case 'clipboard_paste_request':
          await _handleClipboardPasteRequestEvent(sessionId, event.payload);
          break;
        default:
          break;
      }
    }
  }

  Future<void> _handleResizeEvent(
    String sessionId,
    Map<String, Object?>? payload,
  ) async {
    if (sessionId != state.activeSessionId || payload == null) {
      return;
    }

    final cols = (payload['cols'] as num?)?.toInt();
    final rows = (payload['rows'] as num?)?.toInt();
    final metric = _lastResizeMetrics[sessionId];
    if (cols == null ||
        rows == null ||
        cols <= 0 ||
        rows <= 0 ||
        metric == null) {
      return;
    }

    final measuredCellSize = _cellSizeFor(sessionId);
    final targetWidth = cols * measuredCellSize.width;
    final targetHeight = rows * measuredCellSize.height;
    final widthDelta = targetWidth - metric.logicalWidth;
    final heightDelta = targetHeight - metric.logicalHeight;
    final targetPixelWidth = math.max(
      1,
      (targetWidth * metric.devicePixelRatio).round(),
    );
    final targetPixelHeight = math.max(
      1,
      (targetHeight * metric.devicePixelRatio).round(),
    );

    ref
        .read(terminalCoreClientProvider)
        .resizeSession(
          sessionId,
          cols: cols,
          rows: rows,
          pixelSize: Size(
            targetPixelWidth.toDouble(),
            targetPixelHeight.toDouble(),
          ),
          devicePixelRatio: 1,
        );
    _lastResizeMetrics[sessionId] = _SessionResizeMetric(
      cols: cols,
      rows: rows,
      pixelWidth: targetPixelWidth,
      pixelHeight: targetPixelHeight,
      logicalWidth: targetWidth,
      logicalHeight: targetHeight,
      devicePixelRatio: metric.devicePixelRatio,
    );
    if (!ref.read(sessionPollingEnabledProvider)) {
      _refreshSession(sessionId);
    }

    if (widthDelta == 0 && heightDelta == 0) {
      return;
    }

    await WindowBridge.resizeBy(
      widthDelta: widthDelta,
      heightDelta: heightDelta,
    );
  }

  Size _cellSizeFor(String sessionId) {
    return viewportFor(sessionId).measuredCellSize ?? terminalFallbackCellSize;
  }

  Future<void> _handleClipboardCopyEvent(Map<String, Object?>? payload) async {
    if (payload == null) {
      return;
    }

    final raw = payload['data'] as String?;
    if (raw == null || raw.isEmpty) {
      return;
    }

    final decoded = utf8.decode(base64.decode(raw), allowMalformed: true);
    if (decoded.isEmpty) {
      return;
    }
    await ClipboardBridge.copy(decoded);
  }

  Future<void> _handleClipboardPasteRequestEvent(
    String sessionId,
    Map<String, Object?>? payload,
  ) async {
    final selection = payload?['selection'] as String? ?? 'c';
    final clipboardText = await ClipboardBridge.paste();
    final encoded = base64.encode(utf8.encode(clipboardText));
    final response = '\x1B]52;$selection;$encoded\x07';
    ref
        .read(terminalCoreClientProvider)
        .sendInput(sessionId, Uint8List.fromList(utf8.encode(response)));
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
          final hasVisibleContent =
              controller != null &&
              controller.frame.rows.any((row) => row.text.trim().isNotEmpty);
          if (hasVisibleContent) {
            for (final timer
                in _warmUpTimers.remove(sessionId) ?? const <Timer>[]) {
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
        .save(TerminalProfilesDocument(profiles: nextProfiles));
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

class _SessionResizeMetric {
  _SessionResizeMetric({
    required this.cols,
    required this.rows,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
  });

  final int cols;
  final int rows;
  final int pixelWidth;
  final int pixelHeight;
  final double logicalWidth;
  final double logicalHeight;
  final double devicePixelRatio;
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
