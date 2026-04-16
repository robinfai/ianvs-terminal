import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/flutterm_core.dart';
import '../profiles/profile_models.dart';
import '../profiles/profile_repository.dart';
import '../terminal/terminal_viewport.dart';
import 'session_state.dart';

final terminalCoreClientProvider = Provider<TerminalCoreClient>((ref) {
  return TerminalCoreClient.load();
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository();
});

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  final Map<String, TerminalViewportController> _viewportControllers = {};
  final Map<String, _SessionResizeMetric> _lastResizeMetrics = {};
  Timer? _pollTimer;

  @override
  SessionState build() {
    Future.microtask(_bootstrap);
    ref.onDispose(() {
      _pollTimer?.cancel();
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
    final profiles = await ref.read(profileRepositoryProvider).load();
    state = state.copyWith(
      profiles: profiles.profiles,
      defaultProfileId: profiles.defaultProfileId,
      isReady: true,
    );
    _startPolling();
    if (profiles.profiles.isNotEmpty) {
      createSession(
        profiles.profiles.firstWhere(
          (profile) => profile.id == profiles.defaultProfileId,
          orElse: () => profiles.profiles.first,
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
    final sessionId = ref
        .read(terminalCoreClientProvider)
        .createSession(profile);
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
  }

  void activateSession(String sessionId) {
    state = state.copyWith(activeSessionId: sessionId);
  }

  void closeSession(String sessionId) {
    ref.read(terminalCoreClientProvider).closeSession(sessionId);
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
  }

  void resizeActiveSession(Size viewportSize, double devicePixelRatio) {
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
  }

  Future<void> saveProfile(TerminalProfile profile) async {
    final nextProfiles = [
      for (final existing in state.profiles)
        if (existing.id == profile.id) profile else existing,
      if (!state.profiles.any((existing) => existing.id == profile.id)) profile,
    ];
    final defaultProfileId = state.defaultProfileId ?? profile.id;
    await ref
        .read(profileRepositoryProvider)
        .save(
          TerminalProfilesDocument(
            defaultProfileId: defaultProfileId,
            profiles: nextProfiles,
          ),
        );
    state = state.copyWith(
      profiles: nextProfiles,
      defaultProfileId: defaultProfileId,
    );
  }

  Future<void> setDefaultProfile(String profileId) async {
    await ref
        .read(profileRepositoryProvider)
        .save(
          TerminalProfilesDocument(
            defaultProfileId: profileId,
            profiles: state.profiles,
          ),
        );
    state = state.copyWith(defaultProfileId: profileId);
  }

  Future<void> deleteProfile(String profileId) async {
    final nextProfiles = state.profiles
        .where((profile) => profile.id != profileId)
        .toList();
    final defaultProfileId = nextProfiles.isEmpty
        ? null
        : nextProfiles.first.id;
    await ref
        .read(profileRepositoryProvider)
        .save(
          TerminalProfilesDocument(
            defaultProfileId: defaultProfileId ?? '',
            profiles: nextProfiles,
          ),
        );
    state = state.copyWith(
      profiles: nextProfiles,
      defaultProfileId: defaultProfileId,
    );
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
