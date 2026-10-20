import 'dart:async';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_recovery_test.dart' show RecoveringTerminal;
import 'terminal_ai_test.dart'
    show FakeApi, MemoryAiStore, commandReply, contextFor;

void main() {
  late AiSettingsController settings;
  late RecoveringTerminal terminal;
  late FakeApi api;
  late TerminalAiController controller;
  setUp(() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = RecoveringTerminal();
    api = FakeApi()
      ..respond = (n) async =>
          n == 1 ? commandReply('ls') : const AiReply(text: 'Done');
    controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
    );
    await controller.ask('Inspect files');
  });
  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  test(
    'retained proposal waits for a fresh foreground read and explicit approval',
    () async {
      final proposal = controller.pending;
      controller.suspendForBackground();
      await controller.approve();
      await controller.ask('Unexpected background request');
      expect(terminal.writes, isEmpty);
      expect(api.requests, hasLength(1));
      final read = terminal.contextRead = Completer<AiTerminalContext>();
      final resume = controller.resumeFromBackground();
      await Future<void>.delayed(Duration.zero);
      expect(controller.canApprove, false);
      await controller.approve();
      read.complete(terminal.context);
      await resume;
      terminal.contextRead = null;
      expect(controller.pending, same(proposal));
      expect(controller.canApprove, true);
      expect(terminal.writes, isEmpty);
      expect(api.requests, hasLength(1));
      await controller.approve();
      expect(terminal.writes.single.command, 'ls');
    },
  );

  for (final change in [
    'guard',
    'disconnect',
    'manual input',
    'settings',
    'task',
  ]) {
    test('$change still revokes a background proposal', () async {
      controller.suspendForBackground();
      switch (change) {
        case 'guard':
          terminal.context = contextFor(guard: 'different-lease');
        case 'disconnect':
          terminal.disconnected = true;
        case 'manual input':
          terminal.inputs.add(null);
        case 'settings':
          await settings.save(
            const AiConfiguration.mock(
              approvalSensitivity: AiApprovalSensitivity.relaxed,
            ),
          );
        case 'task':
          controller.newTask();
      }
      await controller.resumeFromBackground();
      expect(controller.canApprove, false);
      expect(controller.pending, isNull);
      await controller.approve();
      expect(terminal.writes, isEmpty);
    });
  }

  test(
    'a pre-background context read cannot unlock approval on resume',
    () async {
      final oldRead = terminal.contextRead = Completer<AiTerminalContext>();
      final poll = controller.refreshContext();
      await Future<void>.delayed(Duration.zero);
      controller.suspendForBackground();
      final resume = controller.resumeFromBackground();
      terminal.contextRead = null;
      terminal.context = contextFor(guard: 'new-foreground-lease');
      oldRead.complete(contextFor());
      await poll;
      await resume;
      expect(controller.pending, isNull);
      expect(controller.canApprove, false);
      expect(terminal.writes, isEmpty);
    },
  );

  test('backgrounding during resume cannot reactivate approval', () async {
    controller.suspendForBackground();
    final read = terminal.contextRead = Completer<AiTerminalContext>();
    final resume = controller.resumeFromBackground();
    await Future<void>.delayed(Duration.zero);
    controller.suspendForBackground();
    read.complete(terminal.context);
    await resume;
    expect(controller.canApprove, false);
    expect(controller.pending, isNotNull);
    terminal.contextRead = null;
    await controller.resumeFromBackground();
    expect(controller.canApprove, true);
    expect(terminal.writes, isEmpty);
  });
}
