import 'dart:convert';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_profile_repository.dart';
import 'shell_screen_phase1a_test.dart' show pumpShellScreen;

class _ModeBackend extends FakePtyBackend {
  final owners = <String, String>{};
  final contexts = <String, String>{};

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    if (request['kind'] == 'composer.state') {
      final owner = owners[sessionId] ?? 'ready';
      return jsonEncode({
        'state': owner,
        'lease': owner == 'ready' ? 'lease-$sessionId' : null,
        'cwd': '/workspace',
        'dialect': 'zsh',
        'contextId': contexts[sessionId] ?? 'root',
        'transport': contexts.containsKey(sessionId) ? 'shell' : 'local',
      });
    }
    if (request['kind'] == 'terminal.command_blocks') {
      return jsonEncode({'blocks': <Object?>[]});
    }
    return super.requestSessionJson(sessionId, requestJson);
  }
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
      expect(
        find.byKey(Key('terminal-mode-notice-$id')).hitTestable(),
        findsOneWidget,
      );
      await _chooseMode(tester, id, 'blocks');
      final editor = find.byKey(const Key('composer-editor'));
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
        isTrue,
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
      find.byKey(const Key('composer-editor')),
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
          .widget<TextField>(find.byKey(const Key('composer-editor')))
          .controller!
          .text,
      'draft before splitting',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
