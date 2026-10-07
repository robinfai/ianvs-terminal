import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/acp/agent_backend.dart';
import 'package:app/features/ai/ai_approval.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ai_approval_test.dart' show ControlledReviewer;

class _Store implements AiConfigurationStore {
  @override
  Future<AiConfiguration?> read() async =>
      const AiConfiguration.acp(agentCommand: '/test/agent');
  @override
  Future<void> write(AiConfiguration? value) async {}
}

class _Terminal implements AiTerminalPort, AiSubmissionInspector {
  String guard = 'initial';
  String node = 'cloud';
  String cwd = '/srv/app';
  AiBlockContext? lastBlock;
  final input = StreamController<void>.broadcast(sync: true);
  final writes = <AiAction>[];
  Completer<Map<String, Object?>>? executing;
  @override
  Future<AiTerminalContext> readContext() async => AiTerminalContext(
    sessionId: 'tab-one',
    contextId: node,
    guard: guard,
    screen: 'cloud>',
    cwd: cwd,
    canRunCommand: true,
    readyLease: 'ready',
    lastBlock: lastBlock,
  );
  @override
  Stream<void> get userInput => input.stream;
  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    if (expected.guard != guard) throw const AiFailure('stale_context');
    writes.add(action);
    return executing == null
        ? {
            'submission_id': 'receipt',
            'block_id': 'block',
            'outcome': 'accepted',
          }
        : executing!.future;
  }

  @override
  String? submissionFor(String actionId) =>
      writes.any((a) => a.id == actionId) ? 'receipt' : null;
  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async => {
    'submission_id': id,
    'outcome': 'accepted',
  };
  @override
  void dispose() => unawaited(input.close());
}

class _Agent implements AgentBackend {
  Future<void> Function(AgentToolHandler, AgentEventHandler) run =
      (_, _) async {};
  AgentToolHandler? tools;
  final prompts = <String>[];
  bool disposed = false;
  @override
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  }) async {
    this.tools = tools;
    prompts.add(prompt);
    await run(tools, events);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  group('ACP terminal ownership', () {
    late _Agent agent;
    late _Terminal terminal;
    late AiSettingsController settings;
    late TerminalAiController controller;
    Map<String, Object?>? lastRequest;
    setUp(() async {
      agent = _Agent();
      terminal = _Terminal();
      settings = AiSettingsController(_Store());
      await settings.loaded;
      controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        agentFactory: (_) => agent,
      );
      lastRequest = null;
      agent.run = (tools, events) async {
        final observed = await tools('get_terminal_state', {});
        lastRequest = {
          'command': 'ls',
          'reason': 'Inspect current target',
          'operation_id': 'one',
          'context_version': observed['context_version'],
        };
        await tools('run_command', lastRequest!);
        events({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Done'},
        });
      };
    });
    tearDown(() {
      controller.dispose();
      settings.dispose();
    });

    for (final finishDuring in ['approval', 'execution', 'review']) {
      test(
        'finished ACP prompt preserves $finishDuring and resumes once',
        () async {
          final finishPrompt = Completer<void>();
          final toolFinished = Completer<Map<String, Object?>>();
          final reviewer = ControlledReviewer();
          if (finishDuring == 'review') {
            await settings.save(
              const AiConfiguration.acp(
                agentCommand: '/test/agent',
                approvalMode: AiApprovalMode.smart,
              ),
            );
            controller.dispose();
            terminal = _Terminal();
            controller = TerminalAiController(
              settings: settings,
              terminal: terminal,
              agentFactory: (_) => agent,
              reviewer: reviewer,
            );
          }
          agent.run = (tools, _) async {
            if (agent.prompts.length > 1) {
              final resume = jsonDecode(agent.prompts.last) as Map;
              final receipt = resume['approved_operation_result'] as Map;
              expect(receipt['submission_id'], 'receipt');
              // The old tool has released its lock before the resumed turn.
              await tools('get_terminal_state', {});
              return;
            }
            final observed = await tools('get_terminal_state', {});
            unawaited(
              tools('run_command', {
                'command': 'df -h',
                'reason': 'Inspect disk usage',
                'operation_id': 'disk',
                'context_version': observed['context_version'],
              }).then(toolFinished.complete),
            );
            await finishPrompt.future;
          };
          final asked = controller.ask('Inspect usage without changing files');
          if (finishDuring == 'review') {
            await reviewer.started.future;
          } else {
            await asked;
            final status = await agent.tools!('inspect_submission', {
              'operation_id': 'disk',
            });
            expect(status['state'], 'awaiting_approval');
            expect(status['submitted'], isFalse);
            expect(controller.canApprove, isTrue);
          }
          Future<void>? approved;
          if (finishDuring == 'execution') {
            terminal.executing = Completer<Map<String, Object?>>();
            approved = controller.approve();
            await Future<void>.delayed(Duration.zero);
            expect(controller.phase, AiPhase.executing);
          }
          finishPrompt.complete();
          await Future<void>.delayed(Duration.zero);
          switch (finishDuring) {
            case 'review':
              expect(controller.phase, AiPhase.reviewing);
              expect(terminal.writes, isEmpty);
              reviewer.result.complete(
                const AiApprovalReview(
                  automatic: true,
                  reason: 'Scoped read-only diagnostic.',
                ),
              );
            case 'approval':
              expect(controller.phase, AiPhase.awaitingApproval);
              expect(controller.canApprove, isTrue);
              expect(terminal.writes, isEmpty);
              approved = controller.approve();
            case 'execution':
              expect(controller.phase, AiPhase.executing);
              terminal.executing!.complete({
                'submission_id': 'receipt',
                'block_id': 'block',
                'outcome': 'accepted',
              });
          }
          await asked;
          await approved;
          await toolFinished.future;
          await Future<void>.delayed(Duration.zero);
          expect(terminal.writes, hasLength(1));
          expect(agent.prompts, hasLength(2));
          expect(controller.phase, AiPhase.idle);
          expect(controller.pending, isNull);
          expect(controller.error, isNull);
        },
      );
    }

    test('unchanged settings preserve the agent conversation', () async {
      agent.run = (_, _) async {};
      await controller.ask('Remember the original goal');
      final task = controller.taskId;
      await settings.save(
        const AiConfiguration.acp(agentCommand: '/test/agent'),
      );
      expect(agent.disposed, isFalse);
      expect(controller.taskId, task);
      await settings.save(
        const AiConfiguration.acp(
          agentCommand: '/test/agent',
          approvalMode: AiApprovalMode.smart,
        ),
      );
      expect(controller.taskId, task);
      expect(agent.disposed, isFalse);
      await controller.ask('Continue');
      expect(agent.prompts, hasLength(2));
    });

    test(
      'a changed agent starts a new task and keeps old tasks as evidence',
      () async {
        await controller.ask('Inspect cloud');
        final previous = controller.taskId;
        final oldTools = agent.tools!;
        await settings.save(
          const AiConfiguration.acp(agentCommand: '/test/other-agent'),
        );
        expect(agent.disposed, isTrue);
        expect(controller.taskId, isNot(previous));
        expect(controller.transcript, isEmpty);
        expect(terminal.writes, isEmpty);
        await expectLater(
          oldTools('run_command', lastRequest!),
          throwsA(isA<AiFailure>()),
        );
        controller.selectTask(previous);
        expect(controller.transcript.any((e) => e.role == 'user'), isTrue);
        expect(controller.canResume, isFalse);
        await controller.ask('Continue with the new agent');
        expect(controller.error, 'configuration_changed');
        expect(agent.prompts, hasLength(1));
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'step limit stops repeated observations without terminal writes',
      () async {
        controller.dispose();
        terminal = _Terminal();
        controller = TerminalAiController(
          settings: settings,
          terminal: terminal,
          agentFactory: (_) => agent,
          maxSteps: 2,
        );
        agent.run = (tools, _) async {
          for (var i = 0; i < 3; i++) {
            await tools('get_terminal_state', {});
          }
        };
        await controller.ask('Inspect');
        expect(controller.phase, AiPhase.failed);
        expect(controller.error, 'step_limit');
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'fresh state observations authorize only the supplied block citation',
      () async {
        agent.run = (tools, events) async {
          terminal.lastBlock = const AiBlockContext(
            id: 'fresh-output',
            command: 'printf result',
            output: 'result',
            exitCode: 0,
            cwd: '/srv/app',
            sourceSessionId: 'tab-one',
            outputStartLine: 5,
            outputEndLine: 6,
          );
          await tools('get_terminal_state', {});
          events({
            'sessionUpdate': 'agent_message_chunk',
            'content': {
              'type': 'text',
              'text': 'result [block:fresh-output:6-6]',
            },
          });
        };
        await controller.ask('Inspect current output');
        final evidence = controller.transcript.last.suppliedEvidence!;
        expect(evidence, hasLength(1));
        expect(evidence.single.id, 'fresh-output');
        expect(evidence.single.sessionId, 'tab-one');
        expect(evidence.single.first, 6);
        expect(evidence.single.last, 6);
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'waits for exact revision approval and keeps the real receipt',
      () async {
        await controller.ask('Inspect cloud');
        expect(controller.canApprove, isTrue);
        expect(terminal.writes, isEmpty);
        await controller.approve(revision: controller.proposalRevision - 1);
        expect(terminal.writes, isEmpty);
        await controller.approve(revision: controller.proposalRevision);
        expect(terminal.writes, hasLength(1));
        expect(controller.phase, AiPhase.idle);
        expect(
          controller.transcript.where((e) => e.blockId == 'block'),
          hasLength(1),
        );
        expect(controller.transcript.last.text, 'Done');
      },
    );

    test('rejects a stale observation before creating a proposal', () async {
      agent.run = (tools, _) async {
        final observed = await tools('get_terminal_state', {});
        terminal.guard = 'user-typed';
        await tools('run_command', {
          'command': 'ls',
          'reason': 'Inspect',
          'operation_id': 'one',
          'context_version': observed['context_version'],
        });
      };
      await controller.ask('Inspect');
      expect(controller.error, 'stale_context');
      expect(controller.pending, isNull);
      expect(terminal.writes, isEmpty);
    });

    for (final observation in ['get_terminal_state', 'read_screen']) {
      test('adopts delayed approved cd through $observation', () async {
        agent.run = (tools, _) async {
          var observed = await tools('get_terminal_state', {});
          await tools('run_command', {
            'command': 'cd /srv/build && make',
            'reason': 'Build in the requested directory',
            'operation_id': 'build',
            'context_version': observed['context_version'],
          });
          // The accepted receipt can precede the shell's cwd notification.
          terminal.cwd = '/srv/build';
          terminal.guard = 'late-cwd';
          terminal.lastBlock = const AiBlockContext(
            id: 'block',
            command: 'cd /srv/build && make',
            output: 'built',
            exitCode: 0,
            cwd: '/srv/app',
          );
          observed = await tools(observation, {
            if (observation == 'read_screen') 'reason': 'Inspect build output',
          });
          await tools('run_command', {
            'command': 'pwd',
            'reason': 'Verify the build directory',
            'operation_id': 'verify',
            'context_version': observed['context_version'],
          });
        };
        await controller.ask('Build and verify');
        await controller.approve();
        expect(controller.canApprove, isTrue);
        expect(controller.originalTarget!.cwd, '/srv/build');
        await controller.approve();
        expect(terminal.writes, hasLength(2));
        expect(controller.phase, AiPhase.idle);
      });
    }

    for (final change in ['unowned-block', 'ssh-node', 'manual-input']) {
      test('approved block cannot authorize a $change change', () async {
        agent.run = (tools, _) async {
          final observed = await tools('get_terminal_state', {});
          await tools('run_command', {
            'command': 'ls',
            'reason': 'Inspect',
            'operation_id': 'inspect',
            'context_version': observed['context_version'],
          });
          terminal.cwd = '/elsewhere';
          terminal.guard = 'changed-target';
          terminal.lastBlock = AiBlockContext(
            id: change == 'unowned-block' ? 'another-command' : 'block',
            command: 'ls',
            output: '',
            exitCode: 0,
            cwd: '/srv/app',
          );
          if (change == 'ssh-node') terminal.node = 'another-node';
          if (change == 'manual-input') terminal.input.add(null);
          await tools('get_terminal_state', {});
        };
        await controller.ask('Inspect');
        await controller.approve();
        expect(terminal.writes, hasLength(1));
        expect(controller.pending, isNull);
        expect(controller.originalTarget!.cwd, '/srv/app');
        if (change == 'manual-input') {
          expect(controller.takenOver, isTrue);
          await controller.resume();
        }
        expect(controller.error, 'target_changed');
      });
    }

    test('revokes approval after an SSH node change', () async {
      await controller.ask('Inspect');
      terminal.node = 'next-node';
      terminal.guard = 'next-guard';
      await controller.refreshContext();
      await controller.approve();
      expect(controller.takenOver, isTrue);
      expect(terminal.writes, isEmpty);
    });

    test(
      'manual input cancels queued agent input without sending Ctrl+C',
      () async {
        await controller.ask('Inspect');
        terminal.input.add(null);
        await Future<void>.delayed(Duration.zero);
        await controller.approve();
        expect(controller.pending, isNull);
        expect(controller.takenOver, isTrue);
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'deduplicates an operation even when its previous context is stale',
      () async {
        agent.run = (tools, _) async {
          final observed = await tools('get_terminal_state', {});
          final args = {
            'command': 'ls',
            'reason': 'Inspect',
            'operation_id': 'one',
            'context_version': observed['context_version'],
          };
          final first = await tools('run_command', args);
          final repeated = await tools('run_command', args);
          expect(repeated['submission_id'], first['submission_id']);
          expect(
            await tools('inspect_submission', {'operation_id': 'one'}),
            containsPair('submission_id', 'receipt'),
          );
        };
        await controller.ask('Inspect');
        await controller.approve();
        expect(terminal.writes, hasLength(1));
      },
    );

    test('rejects changed arguments under an existing operation ID', () async {
      await controller.ask('Inspect');
      await controller.approve();
      // A new turn cannot rewrite the old operation.
      agent.run = (tools, _) async {
        await tools('run_command', {...lastRequest!, 'command': 'rm example'});
      };
      await controller.ask('Continue');
      expect(controller.error, 'invalid_action');
      expect(terminal.writes, hasLength(1));
    });

    test(
      'does not replace a pending approval with a parallel tool request',
      () async {
        await controller.ask('Inspect');
        await expectLater(
          agent.tools!('run_command', {...lastRequest!, 'operation_id': 'two'}),
          throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'acp_busy')),
        );
        expect(controller.pending!.command, 'ls');
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'pause during submission retains unknown receipt and permits inspection only',
      () async {
        terminal.executing = Completer();
        await controller.ask('Inspect');
        final approval = controller.approve();
        await Future<void>.delayed(Duration.zero);
        controller.takeOver();
        terminal.executing!.complete({'submission_id': 'receipt'});
        await approval;
        expect(terminal.writes, hasLength(1));
        expect(
          controller.transcript.where((e) => e.state == AiEntryState.unknown),
          hasLength(1),
        );
        await controller.refreshContext();
        expect(terminal.writes, hasLength(1));
      },
    );

    test('switching tasks never routes late tools to the new task', () async {
      await controller.ask('Inspect');
      final oldTools = agent.tools!;
      controller.newTask();
      await expectLater(
        oldTools('get_terminal_state', {}),
        throwsA(isA<AiFailure>()),
      );
      expect(controller.transcript, isEmpty);
      expect(terminal.writes, isEmpty);
    });

    test('streamed reply chunks form one message', () async {
      agent.run = (_, events) async {
        for (final text in ['First', ' second']) {
          events({
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': text},
          });
        }
      };
      await controller.ask('Explain');
      expect(controller.transcript.last.text, 'First second');
      expect(
        controller.transcript.where((e) => e.role == 'assistant'),
        hasLength(1),
      );
      expect(jsonDecode(agent.prompts.single), contains('terminal'));
    });
  });
}
