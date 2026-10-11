import 'dart:async';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

import '../support/fake_pty_backend.dart';

class _Sessions extends SessionController {
  @override
  SessionState build() => SessionState.initial();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePtyBackend backend;
  late ProviderContainer container;
  late SessionController sessions;
  setUp(() {
    backend = FakePtyBackend();
    container = ProviderContainer(overrides: [
      ptySessionBackendProvider.overrideWithValue(backend),
      sessionControllerProvider.overrideWith(_Sessions.new),
      sessionPollingEnabledProvider.overrideWithValue(false),
      driverWarmUpRefreshEnabledProvider.overrideWithValue(false),
    ]);
    sessions = container.read(sessionControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  test('missing runtime becomes unavailable without a fabricated exit code or input', () {
    final id = sessions.createSession(defaultTerminalProfile())!;
    final runtime = container.read(terminalRuntimeControllerProvider);
    final original = container.read(sessionControllerProvider).tabs.single;
    expect(runtime.tryCloseSession(id), isTrue);
    expect(sessions.existingViewportFor(id), isNull);
    expect(sessions.reconcileUnavailableSession(id, expectedTab: original), isTrue);
    final next = container.read(sessionControllerProvider).tabs.single;
    expect(next.paneFor(id)!.isExited, isTrue);
    expect(next.paneFor(id)!.exitCode, isNull);
    expect(next.paneFor(id)!.runtimeError?.operation, 'sessionUnavailable');
    expect(backend.writes, isEmpty);
    // The singleton-tab getter creates a fresh TerminalPane on every access;
    // reconciliation must guard the actual immutable TerminalTab, not that view.
    expect(identical(original.paneFor(id), original.paneFor(id)), isFalse);
    expect(sessions.reconcileUnavailableSession(id, expectedTab: original), isFalse);
    expect(sessions.reconcileUnavailableSession(id, expectedTab: next), isFalse);
    expect(() => sessions.resizeSession(id, const Size(390, 600), 3), returnsNormally);
  });

  test('live runtime and stale tab callbacks are not marked exited', () {
    final id = sessions.createSession(defaultTerminalProfile())!;
    final original = container.read(sessionControllerProvider).tabs.single;
    expect(sessions.reconcileUnavailableSession(id, expectedTab: original), isFalse);
    final runtime = container.read(terminalRuntimeControllerProvider);
    runtime.tryCloseSession(id);
    sessions.activateSession(id); // Replaces the immutable tab snapshot.
    expect(sessions.reconcileUnavailableSession(id, expectedTab: original), isFalse);
    final current = container.read(sessionControllerProvider).tabs.single;
    expect(sessions.reconcileUnavailableSession(id, expectedTab: current), isTrue);
    expect(backend.writes, isEmpty);
  });

  test('resize after native removal reconciles rather than reading a released viewport', () {
    final id = sessions.createSession(defaultTerminalProfile())!;
    container.read(terminalRuntimeControllerProvider).tryCloseSession(id);
    sessions.resizeSession(id, const Size(390, 600), 3);
    expect(container.read(sessionControllerProvider).tabs.single.isExited, isTrue);
    expect(backend.writes, isEmpty);
  });

  test('ordinary exit event still removes its pane rather than turning it into a retained error', () async {
    final id = sessions.createSession(defaultTerminalProfile())!;
    final runtime = container.read(terminalRuntimeControllerProvider);
    backend.enqueueEvent(id, PtyEvent(kind: 'exit', sessionId: id, payload: {'code': 0}));
    runtime.refreshSession(id);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (container.read(sessionControllerProvider).tabs.isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(sessionControllerProvider).tabs, isEmpty);
    expect(container.read(sessionControllerProvider).activeSessionId, isNull);
    expect(runtime.hasSession(id), isFalse);
    expect(backend.writes, isEmpty);
  });
}
