import 'dart:async';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, contextFor;

void main() {
  test('classification metadata is excluded from model context', () {
    const context = AiTerminalContext(
      sessionId: 'one',
      contextId: 'root',
      guard: 'lease',
      screen: '',
      commandNames: {'private-command'},
      aliases: {'private-alias': 'secret-body'},
    );
    expect(context.toJson().toString(), isNot(contains('private-command')));
    expect(context.toJson().toString(), isNot(contains('secret-body')));
  });
  late AiSettingsController settings;
  late TerminalAiController controller;
  late FakeTerminal terminal;
  late FakeApi api;
  setUp(() async {
    settings = AiSettingsController(MemoryAiStore(null));
    await settings.loaded;
    terminal = FakeTerminal();
    api = FakeApi();
    controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
    );
    await controller.refreshContext();
  });
  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  test('human command runs without configured AI or inference', () async {
    controller.setDraft('ls -la');
    expect(controller.inputIntentDecision().intent, InputIntent.command);
    await controller.runUserCommand('ls -la');
    expect(terminal.writes.single.command, 'ls -la');
    expect(api.requests, isEmpty);
    expect(controller.draft, isEmpty);
    expect(controller.transcript.single.state, AiEntryState.accepted);
  });

  test('stale terminal target rejects input and retains draft', () async {
    controller.setDraft('pwd');
    terminal.context = contextFor(guard: 'remote:2');
    await controller.runUserCommand('pwd');
    expect(terminal.writes, isEmpty);
    expect(controller.draft, 'pwd');
    expect(controller.transcript.single.state, AiEntryState.revoked);
    expect(api.requests, isEmpty);
  });

  test('unknown receipt blocks duplicate Enter and preserves draft', () async {
    terminal.execution = Completer<Map<String, Object?>>();
    controller.setDraft('touch marker');
    final first = controller.runUserCommand('touch marker');
    await controller.runUserCommand('touch marker');
    terminal.execution!.completeError(const AiFailure('submission_unknown'));
    await first;
    expect(terminal.writes, hasLength(1));
    expect(controller.hasUnresolvedSubmission, isTrue);
    expect(controller.canRunUserCommand, isFalse);
    expect(controller.draft, 'touch marker');
    await controller.runUserCommand('touch marker');
    expect(terminal.writes, hasLength(1));
  });

  test('task switch cannot write through or clear another draft', () async {
    terminal.execution = Completer<Map<String, Object?>>();
    controller.setDraft('pwd');
    final running = controller.runUserCommand('pwd');
    controller.newTask();
    controller.setDraft('解释输出');
    terminal.execution!.complete({'status': 'input_sent'});
    await running;
    expect(controller.draft, '解释输出');
    expect(controller.inputIntentDecision().intent, InputIntent.ai);
  });

  test('manual choice belongs to a task and clears after submission', () async {
    controller.setDraft('解释失败');
    controller.chooseInputIntent(InputIntentChoice.command);
    expect(controller.inputIntentDecision().intent, InputIntent.command);
    await controller.runUserCommand('解释失败');
    controller.setDraft('检查输出');
    expect(controller.inputIntentDecision().intent, InputIntent.ai);
    expect(controller.inputIntentChoice, InputIntentChoice.automatic);
  });
}
