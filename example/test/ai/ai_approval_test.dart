import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/acp/agent_backend.dart';
import 'package:app/features/ai/ai_approval.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply, contextFor;

String decision({
  String id = 'call-1',
  String risk = 'low',
  bool scope = true,
  bool confirmation = false,
  String effect = 'read_only',
}) => jsonEncode({
  'action_id': id,
  'decision': 'allow',
  'risk': risk,
  'within_scope': scope,
  'needs_confirmation': confirmation,
  'effect': effect,
  'reason': 'Scoped inspection.',
});

class ControlledReviewer implements AiActionReviewer {
  int calls = 0;
  final started = Completer<void>();
  final result = Completer<AiApprovalReview>();
  @override
  Future<AiApprovalReview> review({
    required AiConfiguration configuration,
    required AiAction action,
    required AiTerminalContext target,
    required List<String> userRequests,
    required AiCancellation cancellation,
  }) {
    calls++;
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

void main() {
  const smart = AiConfiguration.mock(approvalMode: AiApprovalMode.smart);
  group('independent review', () {
    late FakeApi api;
    late AiModelActionReviewer reviewer;
    setUp(() {
      api = FakeApi()..respond = (_) async => AiReply(text: decision());
      reviewer = AiModelActionReviewer(api: api);
    });
    Future<AiApprovalReview> review([String command = 'ls -la']) =>
        reviewer.review(
          configuration: smart,
          action: commandReply(command).action!,
          target: contextFor(),
          userRequests: ['Inspect current files.'],
          cancellation: AiCancellation(),
        );

    test('read-only and reversible scoped actions can pass', () async {
      expect((await review()).automatic, isTrue);
      api.respond = (_) async =>
          AiReply(text: decision(effect: 'reversible_write'));
      expect((await review('mkdir new-directory')).automatic, isTrue);
      final payload =
          jsonDecode(api.requests.last.last['content']! as String) as Map;
      expect(payload['proposed_input'], 'mkdir new-directory');
      expect(payload['user_requests'], ['Inspect current files.']);
      expect(api.requests.last, hasLength(2));
      expect(payload.toString(), isNot(contains('readyLease')));
    });

    for (final response in [
      decision(scope: false),
      decision(risk: 'high'),
      decision(effect: 'external'),
      decision(confirmation: true),
      decision(id: 'old-action'),
      '{}',
      'allow',
      '```json\n{}\n```',
    ]) {
      test('unsafe or invalid result cannot auto-approve: $response', () async {
        api.respond = (_) async => AiReply(text: response);
        expect((await review()).automatic, isFalse);
      });
    }
    for (final command in [
      'rm -rf /tmp/cache',
      'sudo ls',
      'sudo -n rm -rf /tmp/cache',
      'sudo --non-interactive chmod 777 /etc/app',
      'sudo -n ls; sudo reboot',
      'sudo -n -u another ls',
      'sudo -n',
      'git push origin main',
      'echo ok; /bin/rm file',
      'cat ~/.ssh/id_rsa',
      r'echo $(danger)',
      'python3 -c "print(1)"',
      'ssh cloud',
    ]) {
      test('mandatory confirmation cannot be overruled: $command', () async {
        expect((await review(command)).automatic, isFalse);
        expect(api.requests, isEmpty);
      });
    }
    for (final command in [
      'sudo -n df -h',
      'sudo --non-interactive du -xhd1 /var/log',
      '/usr/bin/sudo -n docker ps -a --size',
      r"sudo -n docker ps -a --size --format 'table {{.Names}}\t{{.Size}}'",
    ]) {
      test(
        'noninteractive privilege use gets a full independent review: $command',
        () async {
          expect((await review(command)).automatic, isTrue);
          expect(api.requests, hasLength(1));
          final payload =
              jsonDecode(api.requests.single.last['content']! as String) as Map;
          expect(payload['proposed_input'], command);
          api.respond = (_) async => AiReply(text: decision(risk: 'high'));
          expect((await review(command)).automatic, isFalse);
          expect(api.requests, hasLength(2));
        },
      );
    }
    test('tool proposals from a reviewer never execute', () async {
      api.respond = (_) async => commandReply('touch unexpected');
      expect((await review()).source, 'unavailable');
    });
    test('review timeout falls back and cancels inference', () async {
      final response = Completer<AiReply>();
      api.respond = (_) => response.future;
      reviewer = AiModelActionReviewer(
        api: api,
        timeout: const Duration(milliseconds: 10),
      );
      expect((await review()).automatic, isFalse);
      expect(api.cancellations.single.isCancelled, isTrue);
      response.complete(AiReply(text: decision()));
    });
    test(
      'ACP review uses a fresh disposable session and denies tools',
      () async {
        final agents = <ReviewAgent>[];
        reviewer = AiModelActionReviewer(
          agentFactory: (_) {
            final agent = ReviewAgent();
            agents.add(agent);
            return agent;
          },
        );
        Future<AiApprovalReview> acp() => reviewer.review(
          configuration: const AiConfiguration.acp(
            agentCommand: '/fixture',
            approvalMode: AiApprovalMode.smart,
          ),
          action: commandReply('ls').action!,
          target: contextFor(),
          userRequests: ['List files'],
          cancellation: AiCancellation(),
        );
        expect((await acp()).automatic, isTrue);
        expect((await acp()).automatic, isTrue);
        expect(agents, hasLength(2));
        expect(agents.every((a) => a.disposed), isTrue);
        reviewer = AiModelActionReviewer(
          agentFactory: (_) => ReviewAgent(attemptTool: true),
        );
        expect((await acp()).automatic, isFalse);
      },
    );
  });

  group('execution gate', () {
    late AiSettingsController settings;
    late TerminalAiController controller;
    late FakeTerminal terminal;
    late FakeApi api;
    late ControlledReviewer reviewer;
    setUp(() async {
      settings = AiSettingsController(MemoryAiStore(smart));
      await settings.loaded;
      terminal = FakeTerminal();
      api = FakeApi()
        ..respond = (n) async =>
            n == 1 ? commandReply('ls -la') : const AiReply(text: 'Done');
      reviewer = ControlledReviewer();
      controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
        reviewer: reviewer,
      );
    });
    tearDown(() {
      controller.dispose();
      settings.dispose();
    });
    const allow = AiApprovalReview(
      automatic: true,
      reason: 'Scoped inspection.',
    );

    test(
      'automatic approval executes once and preserves review with receipt',
      () async {
        final task = controller.ask('List files');
        await reviewer.started.future;
        expect(controller.phase, AiPhase.reviewing);
        expect(controller.busy, isTrue);
        expect(controller.canApprove, isFalse);
        expect(terminal.writes, isEmpty);
        reviewer.result.complete(allow);
        await task;
        expect(terminal.writes, hasLength(1));
        expect(controller.phase, AiPhase.idle);
        final record = controller.transcript.singleWhere(
          (e) => e.action != null,
        );
        expect(record.state, AiEntryState.accepted);
        expect(record.approvalReview!.automatic, isTrue);
        expect(api.requests, hasLength(2));
      },
    );
    test(
      'uncertain decision offers normal approval, edited input clears old audit',
      () async {
        final task = controller.ask('List files');
        await reviewer.started.future;
        reviewer.result.complete(
          const AiApprovalReview(automatic: false, reason: 'Scope is unclear.'),
        );
        await task;
        expect(controller.canApprove, isTrue);
        expect(terminal.writes, isEmpty);
        controller.editPendingCommand(
          'pwd',
          revision: controller.proposalRevision,
        );
        expect(controller.transcript.last.approvalReview, isNull);
        await controller.approve();
        expect(terminal.writes.single.command, 'pwd');
      },
    );
    for (final change in ['pause', 'task', 'node', 'settings']) {
      test('$change invalidates a delayed allow decision', () async {
        final task = controller.ask('List files');
        await reviewer.started.future;
        switch (change) {
          case 'pause':
            controller.takeOver();
          case 'task':
            controller.newTask();
          case 'node':
            terminal.context = contextFor(guard: 'ssh:2');
          case 'settings':
            await settings.save(const AiConfiguration.mock());
        }
        reviewer.result.complete(allow);
        await task;
        expect(terminal.writes, isEmpty);
        expect(controller.canApprove, isFalse);
      });
    }
    test('unknown submission is not retried by automatic review', () async {
      terminal.execution = Completer<Map<String, Object?>>();
      final task = controller.ask('List files');
      await reviewer.started.future;
      reviewer.result.complete(allow);
      while (terminal.writes.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      terminal.execution!.completeError(const AiFailure('submission_unknown'));
      await task;
      expect(terminal.writes, hasLength(1));
      expect(reviewer.calls, 1);
      expect(controller.hasUnresolvedSubmission, isTrue);
      expect(controller.canApprove, isFalse);
    });
    test('manual policy never invokes the reviewer', () async {
      await settings.save(const AiConfiguration.mock());
      await controller.ask('List files');
      expect(reviewer.calls, 0);
      expect(controller.canApprove, isTrue);
      expect(terminal.writes, isEmpty);
      expect(controller.transcript.last.approvalReview!.source, 'manual');
      expect(controller.transcript.last.approvalReview!.automatic, isFalse);
    });
    test('editing as a review completes cannot reuse its approval', () async {
      var changed = false;
      controller.addListener(() {
        if (!changed && controller.canApprove) {
          changed = true;
          controller.editPendingCommand(
            'touch different-input',
            revision: controller.proposalRevision,
          );
        }
      });
      final task = controller.ask('List files');
      await reviewer.started.future;
      reviewer.result.complete(allow);
      await task;
      expect(terminal.writes, isEmpty);
      expect(controller.pending!.command, 'touch different-input');
      expect(controller.transcript.last.approvalReview, isNull);
      expect(controller.canApprove, isTrue);
    });
  });
  test(
    'saved preferences round trip; old and invalid policies stay manual',
    () {
      expect(
        AiConfiguration.fromJson(smart.toJson()).approvalMode,
        AiApprovalMode.smart,
      );
      final legacy = smart.toJson()..remove('approvalMode');
      expect(
        AiConfiguration.fromJson(legacy).approvalMode,
        AiApprovalMode.manual,
      );
      expect(
        AiConfiguration.fromJson({
          ...legacy,
          'approvalMode': 'allow_all',
        }).approvalMode,
        AiApprovalMode.manual,
      );
    },
  );

  test(
    'ACP automatic gate releases tool replies and deduplicates operations',
    () async {
      final settings = AiSettingsController(
        MemoryAiStore(
          const AiConfiguration.acp(
            agentCommand: '/fixture',
            approvalMode: AiApprovalMode.smart,
          ),
        ),
      );
      await settings.loaded;
      final terminal = FakeTerminal();
      final reviewer = ControlledReviewer()
        ..result.complete(
          const AiApprovalReview(automatic: true, reason: 'Scoped inspection.'),
        );
      final agent = ActingAgent();
      final controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        reviewer: reviewer,
        agentFactory: (_) => agent,
      );
      addTearDown(() {
        controller.dispose();
        settings.dispose();
      });
      await controller.ask('Inspect the directory and location');
      await agent.finished.future.timeout(const Duration(seconds: 2));
      expect(terminal.writes.map((a) => a.command), ['ls', 'pwd']);
      expect(reviewer.calls, 2);
      expect(
        controller.transcript.where((e) => e.approvalReview?.automatic == true),
        hasLength(2),
      );
      expect(controller.canApprove, isFalse);
    },
  );
}

class ActingAgent implements AgentBackend {
  final finished = Completer<void>();
  @override
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  }) async {
    for (final command in ['ls', 'pwd']) {
      final context = await tools('get_terminal_state', {});
      final args = {
        'command': command,
        'reason': 'Inspect',
        'context_version': context['context_version'],
        'operation_id': command,
      };
      await tools('run_command', args);
      await tools('run_command', args);
    }
    finished.complete();
  }

  @override
  Future<void> dispose() async {}
}

class ReviewAgent implements AgentBackend {
  ReviewAgent({this.attemptTool = false});
  final bool attemptTool;
  bool disposed = false;
  @override
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  }) async {
    if (attemptTool) {
      await tools('run_command', {'command': 'unexpected'});
    }
    events({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': decision()},
    });
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
