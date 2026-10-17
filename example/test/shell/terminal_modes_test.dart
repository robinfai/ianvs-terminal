import 'dart:convert';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal_composer/command_blocks_pane.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../support/current_terminal_frame_fixture.dart';
import '../support/fake_pty_backend.dart';
import '../support/memory_profile_repository.dart';
import '../support/shell_command_actions.dart';
import 'shell_screen_phase1a_test.dart' show pumpShellScreen;

class _ModeBackend extends FakePtyBackend {
  final owners = <String, String>{};
  final contexts = <String, String>{};
  final leases = <String, String>{};
  final screens = <String, String>{};

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    if (request['kind'] == 'composer.state') {
      final owner = owners[sessionId] ?? 'ready';
      return jsonEncode({
        'state': owner,
        'lease': owner == 'ready'
            ? leases[sessionId] ?? 'lease-$sessionId'
            : null,
        'cwd': '/workspace',
        'dialect': 'zsh',
        'contextId': contexts[sessionId] ?? 'root',
        'transport': contexts.containsKey(sessionId) ? 'shell' : 'local',
      });
    }
    if (request['kind'] == 'terminal.command_blocks') {
      return jsonEncode({'blocks': <Object?>[]});
    }
    if (request['kind'] == 'terminal.live_screen') {
      return jsonEncode({'text': screens[sessionId] ?? 'ianvs terminal ready'});
    }
    return super.requestSessionJson(sessionId, requestJson);
  }
}

class _ExitBackend extends _ModeBackend implements PtyRuntimeCapabilityBackend {
  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson({
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': ['terminal-frame-diff-v1'],
        'recording_schema_versions': <Object?>[],
        'features': ['session-config.json.v1', 'ssh-session.v1'],
      });
}

class _PreferenceBackend extends _ModeBackend {
  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final response = super.requestSessionJson(sessionId, requestJson);
    if ((jsonDecode(requestJson) as Map)['kind'] != 'composer.state') {
      return response;
    }
    return jsonEncode({
      ...jsonDecode(response!) as Map<String, Object?>,
      'transport': 'shell',
    });
  }

  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson({
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <String>[],
        'recording_schema_versions': <int>[],
        'features': ['session-config.json.v1', 'ssh-session.v1'],
      });
}

Future<void> _settleMode(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _chooseMode(WidgetTester tester, String id, String mode) async {
  await tester.tap(
    find.byKey(Key('shell-tab-$id')),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('terminal-mode-$mode-$id')));
  await _settleMode(tester);
}

void main() {
  for (final exitCode in [0, 255]) {
    testWidgets('queued shell events and resize settle exit $exitCode', (
      tester,
    ) async {
      final backend = _ExitBackend();
      final profile = TerminalProfile(
        id: 'exit-regression',
        name: 'Exit regression',
        shell: '',
        connection: const TerminalConnectionConfig.ssh(
          host: 'fixture.test',
          user: 'test',
        ),
      );
      await pumpShellScreen(
        tester,
        fakeBindings: backend,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [profile]),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(profile);
      await _settleMode(tester);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      final runtime = container.read(terminalRuntimeControllerProvider);
      // ShellScreen attaches the real UI sink. The bell defers reduction of
      // subsequent hooks until after native exit has disposed the viewport.
      backend.enqueueEvent(id, PtyEvent(kind: 'bell', sessionId: id));
      backend.enqueueEvent(
        id,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: id,
          payload: {'hook': 'prompt_started', 'prompt_scrollback_offset': 0},
        ),
      );
      backend.enqueueEvent(
        id,
        PtyEvent(kind: 'exit', sessionId: id, payload: {'code': exitCode}),
      );
      runtime.refreshSession(id);
      expect(
        () => controller.resizeSession(id, const Size(390, 600), 1),
        returnsNormally,
      );
      await _settleMode(tester);
      final state = container.read(sessionControllerProvider);
      final panes = state.tabs
          .expand((tab) => tab.effectivePanes)
          .where((pane) => pane.sessionId == id);
      if (exitCode == 0) {
        expect(panes, isEmpty);
        expect(state.activeSessionId, isNot(id));
        expect(runtime.existingViewportFor(id), isNull);
      } else {
        expect(panes.single.isExited, true);
        expect(runtime.existingViewportFor(id), isNotNull);
        final replacement = controller.reconnectSession(id);
        expect(replacement, isNot(id));
        expect(
          container.read(sessionControllerProvider).liveReconnectionFor(id),
          replacement,
        );
        expect(backend.writes, isEmpty);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'missing viewport presents a usable fallback and keeps AI reachable',
    (tester) async {
      final backend = _ModeBackend();
      final profile = defaultTerminalProfile();
      await pumpShellScreen(
        tester,
        fakeBindings: backend,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [profile]),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(profile);
      await _settleMode(tester);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      container.read(terminalRuntimeControllerProvider).closeSession(id);
      // Trigger a real host rebuild without recreating the missing runtime.
      controller.activateSession(id);
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _settleMode(tester);
      expect(find.byKey(Key('terminal-unavailable-$id')), findsOneWidget);
      expect(find.text('Close session'), findsOneWidget);
      await tester.tap(find.byKey(Key('terminal-unavailable-ai-$id')));
      await _settleMode(tester);
      expect(find.byKey(ValueKey('ai-workspace-$id')), findsOneWidget);
      expect(
        container
            .read(terminalRuntimeControllerProvider)
            .existingViewportFor(id),
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'reset platform preference affects only new sessions $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final backend = _PreferenceBackend();
        final profile = platform == TargetPlatform.iOS
            ? TerminalProfile(
                id: 'cloud-test',
                name: 'Cloud',
                shell: '',
                connection: const TerminalConnectionConfig.ssh(
                  host: 'cloud.test',
                  user: 'test',
                ),
              )
            : defaultTerminalProfile();
        await pumpShellScreen(
          tester,
          fakeBindings: backend,
          repository: MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [profile]),
          ),
        );
        await _settleMode(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ShellScreen)),
        );
        final controller = container.read(sessionControllerProvider.notifier);
        SessionState state() => container.read(sessionControllerProvider);
        final expected = platform == TargetPlatform.iOS
            ? TerminalViewMode.blocks
            : TerminalViewMode.normal;
        final explicit = platform == TargetPlatform.iOS
            ? TerminalViewMode.normal
            : TerminalViewMode.blocks;
        await controller.setPreferredTerminalMode(explicit);
        controller.createSession(profile);
        await _settleMode(tester);
        final original = state().activeSessionId!;
        expect(state().tabs.last.terminalMode.mode, explicit);
        final writes = backend.writes.length;
        if (platform == TargetPlatform.macOS) {
          await openShellCommand(tester, 'shell-command-defaults');
          await tester.pumpAndSettle();
          final modes = find.byKey(const Key('defaults-terminal-mode-options'));
          await tester.ensureVisible(modes);
          await tester.tap(modes);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('default-terminal-mode-platform')).last,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('defaults-save')));
          await tester.pumpAndSettle();
        } else {
          await controller.setPreferredTerminalMode(null);
        }
        await _settleMode(tester);
        expect(controller.preferredTerminalModeOverride, isNull);
        expect(state().preferredTerminalMode, expected);
        expect(state().tabs.last.terminalMode.mode, explicit);
        expect(backend.writes, hasLength(writes));
        controller.createSession(profile);
        await _settleMode(tester);
        expect(
          state().tabs.last.terminalMode.mode,
          platform == TargetPlatform.iOS ? TerminalViewMode.normal : expected,
        );
        if (platform == TargetPlatform.iOS) {
          expect(
            state().tabs.last.terminalMode.unavailableReason,
            BlockUnavailableReason.llmRequired,
          );
        }
        expect(
          state().tabs
              .firstWhere((tab) => tab.containsSession(original))
              .terminalMode
              .mode,
          explicit,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('open tab menu follows capability recovery and loss', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _ModeBackend();
    await pumpShellScreen(
      tester,
      fakeBindings: backend,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );
    await _settleMode(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final id = container.read(sessionControllerProvider).activeSessionId!;
    await _chooseMode(tester, id, 'blocks');
    backend.owners[id] = 'suspended';
    await _settleMode(tester);
    await tester.tap(
      find.byKey(Key('shell-tab-$id')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(Key('terminal-mode-blocks-$id'));
    bool enabled() =>
        tester.widget<CheckedPopupMenuItem<Object>>(entry).enabled;
    expect(enabled(), false);

    // Keep this exact popup open while the program exits and another program
    // takes terminal input. Both changes must update the available actions.
    backend.owners[id] = 'ready';
    await _settleMode(tester);
    expect(enabled(), true);
    expect(find.byType(TerminalCommandBlocksView), findsNothing);
    backend.owners[id] = 'suspended';
    await _settleMode(tester);
    expect(enabled(), false);
    backend.owners[id] = 'ready';
    await _settleMode(tester);
    expect(enabled(), true);
    await tester.tap(entry);
    await _settleMode(tester);
    expect(
      find.byType(TerminalCommandBlocksView).hitTestable(),
      findsOneWidget,
    );
    expect(backend.writes, isEmpty);
    expect(backend.closedSessionIds, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final initialOwner in ['ready', 'draft']) {
    testWidgets(
      'unmounted background tab detects support and keeps polling: $initialOwner',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final backend = _ModeBackend();
        await pumpShellScreen(
          tester,
          fakeBindings: backend,
          repository: MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ShellScreen)),
        );
        final controller = container.read(sessionControllerProvider.notifier);
        SessionState state() => container.read(sessionControllerProvider);
        // Restored/background tabs can exist before their pane is ever built.
        // Do not pump between these creations: only the last pane mounts.
        final background = controller.createSession(defaultTerminalProfile())!;
        backend.owners[background] = initialOwner;
        final active = controller.createSession(defaultTerminalProfile())!;
        await _settleMode(tester);
        TerminalModeState mode() => state().tabs
            .firstWhere((tab) => tab.sessionId == background)
            .activePane
            .terminalMode;
        expect(mode().unavailableReason, BlockUnavailableReason.checking);
        final created = backend.lastCreatedSessionPayload;
        await tester.tap(
          find.byKey(Key('shell-tab-$background')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        bool enabled() => tester
            .widget<CheckedPopupMenuItem<Object>>(
              find.byKey(Key('terminal-mode-blocks-$background')),
            )
            .enabled;
        expect(enabled(), initialOwner == 'ready');
        expect(
          mode().unavailableReason,
          initialOwner == 'ready'
              ? isNull
              : BlockUnavailableReason.unsupportedShell,
        );
        expect(find.text('Checking shell support…'), findsNothing);
        expect(state().activeSessionId, active);

        // A background handshake completing while the popup is open must
        // update it without activating the pane or sending terminal input.
        backend.owners[background] = 'ready';
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(enabled(), isTrue);
        await tester.tap(find.byKey(Key('terminal-mode-recheck-$background')));
        await _settleMode(tester);
        expect(mode().notice, TerminalModeNotice.supportChecked);
        expect(mode().mode, TerminalViewMode.normal);
        expect(state().activeSessionId, active);
        expect(backend.lastCreatedSessionPayload, same(created));
        expect(backend.closedSessionIds, isEmpty);
        expect(backend.writes, isEmpty);

        await _chooseMode(tester, background, 'blocks');
        expect(state().activeSessionId, background);
        expect(mode().mode, TerminalViewMode.blocks);
        expect(
          find.byKey(const Key('ai-prompt')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'desktop tab recheck preserves Normal, draft and the same session',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final backend = _ModeBackend();
      await pumpShellScreen(
        tester,
        fakeBindings: backend,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      await _settleMode(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final id = container.read(sessionControllerProvider).activeSessionId!;
      await _chooseMode(tester, id, 'blocks');
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'retained command',
      );
      await _chooseMode(tester, id, 'normal');
      final created = backend.lastCreatedSessionPayload;
      await tester.tap(
        find.byKey(Key('shell-tab-$id')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('terminal-mode-recheck-$id')));
      await _settleMode(tester);
      final mode = container
          .read(sessionControllerProvider)
          .tabs
          .first
          .activePane
          .terminalMode;
      expect(mode.mode, TerminalViewMode.normal);
      expect(mode.notice, TerminalModeNotice.supportChecked);
      expect(backend.lastCreatedSessionPayload, same(created));
      expect(backend.closedSessionIds, isEmpty);
      expect(backend.writes, isEmpty);
      await _chooseMode(tester, id, 'blocks');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-prompt')))
            .controller!
            .text,
        'retained command',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('output checks refresh ownership before falling back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _ModeBackend();
    await pumpShellScreen(
      tester,
      fakeBindings: backend,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );
    await _settleMode(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final id = container.read(sessionControllerProvider).activeSessionId!;
    await _chooseMode(tester, id, 'blocks');
    final pane = tester.widget<CommandBlocksPane>(
      find.byType(CommandBlocksPane),
    );
    final session = pane.session;
    void output(String text) {
      backend.screens[id] = text;
      final before = pane.viewport.frame;
      final frame = <String, Object?>{
        'rows': [
          {'index': 0, 'text': text},
        ],
        'cursor': {'row': 0, 'col': text.length, 'visible': true},
        'viewport_rows': before.viewportRows,
        'viewport_cols': before.viewportCols,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      };
      backend.setFrame(id, frame);
      pane.viewport.updateFrame(terminalFrameFixtureFromJson(frame));
    }

    // An AI/native submission can produce output before the pane's 150 ms
    // ownership poll; the output check runs after only 80 ms.
    session.setVisible(true);
    expect(session.controller.ownership, ComposerOwnership.ready);
    backend.owners[id] = 'running';
    output('command output before the next ownership poll');
    await tester.pump(const Duration(milliseconds: 81));
    expect(session.mode.state.mode, TerminalViewMode.blocks);
    expect(session.controller.ownership, ComposerOwnership.running);

    // A finished command's native screen can precede its decoded UI frame.
    backend.owners[id] = 'ready';
    backend.leases[id] = 'next-ready-lease';
    backend.screens[id] = 'finished command and prompt';
    session.setVisible(true);
    await tester.pump(const Duration(milliseconds: 81));
    output('finished command and prompt');
    await tester.pump(const Duration(milliseconds: 81));
    expect(session.mode.state.mode, TerminalViewMode.blocks);

    // Still preserve genuine output arriving at the same idle prompt.
    await _settleMode(tester);
    session.setVisible(true);
    output('background output outside a command block');
    await tester.pump(const Duration(milliseconds: 81));
    expect(session.mode.state.mode, TerminalViewMode.normal);
    expect(
      session.mode.state.unavailableReason,
      BlockUnavailableReason.unattributedOutput,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'tab mode switching follows SSH context and preserves the draft',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final backend = _ModeBackend();
      await pumpShellScreen(
        tester,
        fakeBindings: backend,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      await _settleMode(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      TerminalModeState mode() => container
          .read(sessionControllerProvider)
          .tabs
          .first
          .paneFor(id)!
          .terminalMode;
      expect(find.byKey(Key('composer-toggle-$id')), findsNothing);
      expect(find.byType(TerminalComposerView), findsNothing);
      expect(mode().canUseBlocks, isTrue);
      expect(find.byKey(Key('terminal-mode-notice-$id')), findsNothing);
      await _chooseMode(tester, id, 'blocks');
      final editor = find.byKey(const Key('ai-prompt'));
      await tester.enterText(editor, 'saved local draft');
      Future<void> hook(Map<String, Object?> payload) async {
        backend.enqueueEvent(
          id,
          PtyEvent(kind: 'shell_hook', sessionId: id, payload: payload),
        );
        await _settleMode(tester);
      }

      backend.owners[id] = 'running';
      await hook({
        'hook': 'bootstrap.checking',
        'context_id': 'hop-a',
        'parent_context_id': 'root',
        'context_kind': 'ssh',
        'host_context_id': 'hop-a',
        'host': 'node-a.example',
      });
      expect(mode().mode, TerminalViewMode.normal);
      expect(mode().unavailableReason, BlockUnavailableReason.checking);
      expect(find.byType(TerminalComposerView), findsNothing);
      expect(
        tester
            .widget<TerminalViewport>(find.byType(TerminalViewport))
            .focusNode!
            .hasFocus,
        isFalse,
      );
      await tester.tap(
        find.byKey(Key('shell-tab-$id')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<Object>>(
              find.byKey(Key('terminal-mode-blocks-$id')),
            )
            .enabled,
        isFalse,
      );
      expect(find.text('Checking shell support…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settleMode(tester);
      // The remote prompt's own authenticated adapter enables manual restore.
      backend.contexts[id] = 'hop-a';
      backend.owners[id] = 'ready';
      await hook({
        'hook': 'bootstrap.ready',
        'context_id': 'hop-a',
        'parent_context_id': 'root',
        'context_kind': 'ssh',
        'host_context_id': 'hop-a',
        'registered': true,
        'shell': 'bash',
      });
      expect(mode().canUseBlocks, isTrue);
      expect(mode().mode, TerminalViewMode.normal);
      expect(mode().notice, TerminalModeNotice.blocksRestored);
      await _chooseMode(tester, id, 'blocks');
      expect(mode().mode, TerminalViewMode.blocks);
      // A parent adapter never enables the next node before its negotiation.
      await hook({
        'hook': 'bootstrap.checking',
        'context_id': 'hop-b',
        'parent_context_id': 'hop-a',
        'context_kind': 'ssh',
        'host_context_id': 'hop-b',
      });
      expect(mode().canUseBlocks, isFalse);
      backend.contexts.remove(id);
      backend.owners[id] = 'ready';
      await hook({
        'hook': 'bootstrap.resume',
        'context_id': 'root',
        'context_kind': 'root',
        'host_context_id': 'root',
      });
      expect(mode().mode, TerminalViewMode.normal);
      expect(mode().canUseBlocks, isTrue);
      expect(mode().notice, TerminalModeNotice.blocksRestored);
      await _chooseMode(tester, id, 'blocks');
      expect(
        tester.widget<TextField>(editor).controller!.text,
        'saved local draft',
      );
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
      await controller.setPreferredTerminalMode(TerminalViewMode.normal);
      expect(
        mode().mode,
        TerminalViewMode.blocks,
        reason: 'Changing the default must not switch existing sessions',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('new session preference and manual choices survive pane moves', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpShellScreen(
      tester,
      fakeBindings: _ModeBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );
    await _settleMode(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    SessionState state() => container.read(sessionControllerProvider);
    final originalId = state().activeSessionId!;
    await _chooseMode(tester, originalId, 'normal');
    await controller.setPreferredTerminalMode(TerminalViewMode.blocks);
    controller.createSession(defaultTerminalProfile());
    await _settleMode(tester);
    final secondId = state().activeSessionId!;
    expect(secondId, isNot(originalId));
    expect(state().tabs.first.terminalMode.mode, TerminalViewMode.normal);
    expect(
      state().tabs.last.activePane.terminalMode.mode,
      TerminalViewMode.blocks,
    );
    await tester.enterText(
      find.byKey(const Key('ai-prompt')),
      'draft before splitting',
    );

    controller.splitSession(
      secondId,
      defaultTerminalProfile(),
      TerminalSplitAxis.horizontal,
    );
    await _settleMode(tester);
    final thirdId = state().activeSessionId!;
    expect(state().tabs.last.effectivePanes, hasLength(2));
    expect(
      state().tabs.last.activePane.terminalMode.mode,
      TerminalViewMode.blocks,
    );
    expect(
      controller.detachPaneToTab(sessionId: secondId, insertionIndex: 2),
      isTrue,
    );
    await _settleMode(tester);
    expect(state().tabs, hasLength(3));
    expect(state().tabs.first.terminalMode.mode, TerminalViewMode.normal);
    final remainingTab = state().tabs.firstWhere(
      (tab) => tab.containsSession(thirdId),
    );
    expect(remainingTab.terminalMode.mode, TerminalViewMode.blocks);
    expect(state().tabs.last.terminalMode.mode, TerminalViewMode.blocks);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ai-prompt')))
          .controller!
          .text,
      'draft before splitting',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
