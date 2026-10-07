// Explicit Harbor runner. Never enables automatic approval in the product.
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_runtime.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _Store implements AiConfigurationStore {
  _Store(this.value);
  final AiConfiguration value;
  @override
  Future<AiConfiguration?> read() async => value;
  @override
  Future<void> write(AiConfiguration? value) async =>
      throw UnsupportedError('ephemeral');
}

void main() {
  _Binding();
  final path = Platform.environment['TRAIL_ACP_BENCH_JOB'];
  test(
    'ACP operates the official container through Trail native SSH blocks',
    () async {
      final job = jsonDecode(await File(path!).readAsString()) as Map;
      final output = job['output'] as String;
      final log = File('$output/trajectory.jsonl').openWrite();
      void record(Map<String, Object?> event) => log.writeln(
        jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), ...event}),
      );
      final settings = AiSettingsController(
        _Store(
          AiConfiguration.acp(
            agentCommand: job['agent_command'] as String,
            agentArguments: (job['agent_arguments'] as List).cast<String>(),
            model: job['model'] as String,
          ),
        ),
      );
      final runtime = TerminalRuntimeController.native(
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      TerminalAiController? controller;
      String? session;
      final result = <String, Object?>{
        'requested_model': job['model'],
        'container': job['container'],
        'scope':
            'production controller + ACP + native SSH blocks; not UI acceptance',
      };
      try {
        session = runtime.createSession(
          TerminalSessionConfig(
            launch: const TerminalLaunchConfig(program: '/bin/bash'),
            connection: TerminalConnectionConfig.fromJson(job['connection']),
            shellIntegration: const TerminalShellIntegrationConfig(
              sshAutoInject: true,
            ),
          ),
        );
        runtime.resizeSessionCells(session, cols: 160, rows: 48);
        final pane = TerminalPane(
          sessionId: session,
          title: 'ACP benchmark',
          profileId: 'benchmark',
        );
        final terminal = TerminalAiRuntime(
          sessionId: session,
          runtime: runtime,
          readPane: () => pane,
          isReadOnly: () => false,
        );
        controller = TerminalAiController(
          settings: settings,
          terminal: terminal,
          maxSteps: 2048,
          onAgentEvent: (event) {
            record({'kind': 'agent', ...event});
            if (event['sessionUpdate'] == 'trail_connection') {
              result['connection'] = event;
            }
            if (event['sessionUpdate'] == 'trail_complete') {
              result['last_inference_usage'] = event['usage'];
              result['usage_scope'] =
                  'Adapter 2.1.1 exposes last inference, not total task tokens';
              result['adapter_model_metadata'] =
                  (event['_meta'] as Map?)?['quota'];
            }
          },
        );
        await settings.loaded;
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (true) {
          try {
            if ((await terminal.readContext()).canRunCommand) break;
          } on Object {
            /* Wait for SSH/bootstrap. */
          }
          if (DateTime.now().isAfter(deadline)) {
            record({
              'kind': 'bootstrap_failed',
              'context': (await terminal.readContext()).toJson(),
            });
            throw StateError('SSH did not negotiate structured commands');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        result['negotiated_blocks'] = true;
        record({
          'kind': 'ready',
          'context': (await terminal.readContext()).toJson(),
        });
        final instruction = await File(
          job['instruction_file'] as String,
        ).readAsString();
        await controller.ask('''
Complete the following task in the bound disposable container terminal.
The benchmark operator authorizes the harness to approve operations inside this
container. Use Trail tools for all task file and terminal operations. The agent
host is not the task environment. Do not access hidden tests, benchmark solutions
or host files. Do not ask a human for help; work until done or concretely blocked.
Commands are integrated: use run_command at a ready prompt. Use send_keys only
for interactive input, and read_screen/read_block to observe retained output.

$instruction''');
        var approvals = 0;
        while (controller.canApprove) {
          record({
            'kind': 'approval',
            'action': controller.pending!.rawCall,
            'target': controller.context!.toJson(),
            'revision': controller.proposalRevision,
          });
          approvals++;
          await controller.approve(revision: controller.proposalRevision);
        }
        await controller.refreshContext();
        Map<String, Object?>? finalTerminal;
        String? terminalError;
        try {
          finalTerminal = (await terminal.readContext()).toJson();
        } on AiFailure catch (failure) {
          // A solver can exit its shell. Preserve the result and let the
          // official verifier inspect files instead of failing during cleanup.
          terminalError = failure.code;
        }
        result.addAll({
          'approvals': approvals,
          'phase': controller.phase.name,
          'error': controller.error,
          'final': controller.transcript.lastOrNull?.text,
          'actions': [
            for (final entry in controller.transcript)
              if (entry.action != null)
                {
                  'command': entry.action!.preview,
                  'state': entry.state.name,
                  'submission_id': entry.submissionId,
                  'block_id': entry.blockId,
                },
          ],
          'terminal': finalTerminal,
          'terminal_read_error': ?terminalError,
        });
        result['solver_finished'] = true;
      } finally {
        await File('$output/acp-result.json').writeAsString(jsonEncode(result));
        await controller?.closeAgentSessions();
        controller?.dispose();
        if (session != null) runtime.closeSession(session);
        runtime.dispose();
        settings.dispose();
        await log.flush();
        await log.close();
      }
    },
    skip: path == null ? 'Explicit Harbor runner only' : false,
    timeout: const Timeout(Duration(hours: 3)),
  );
}
