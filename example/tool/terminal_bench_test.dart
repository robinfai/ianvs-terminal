// Explicitly launched by tools/terminal_bench/trail_agent.py. Not part of the
// ordinary test suite and never enables automatic approval in the shipped app.
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_runtime.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class _BenchmarkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _MemoryStore implements AiConfigurationStore {
  _MemoryStore(this.configuration);
  final AiConfiguration configuration;
  @override
  Future<AiConfiguration> read() async => configuration;
  @override
  Future<void> write(AiConfiguration? value) =>
      throw UnsupportedError('ephemeral');
}

class _RecordedApi implements AiApi {
  _RecordedApi(this.log, String effort)
    : delegate = AiApiClient(
        timeout: const Duration(minutes: 10),
        reasoningEffort: effort,
      );
  final IOSink log;
  final AiApiClient delegate;
  int requests = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int cacheTokens = 0;

  void countUsage(Map<String, Object?>? usage) {
    inputTokens += (usage?['prompt_tokens'] as num?)?.toInt() ?? 0;
    outputTokens += (usage?['completion_tokens'] as num?)?.toInt() ?? 0;
    cacheTokens +=
        ((usage?['prompt_tokens_details'] as Map?)?['cached_tokens'] as num?)
            ?.toInt() ??
        0;
  }

  void record(Map<String, Object?> event) => log.writeln(
    jsonEncode({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      ...event,
    }),
  );

  @override
  Future<AiReply> complete(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
  ) async {
    final sequence = ++requests;
    record({
      'event': 'request',
      'sequence': sequence,
      'model': configuration.model,
      'reasoning_effort': delegate.reasoningEffort,
      'messages': messages,
    });
    final watch = Stopwatch()..start();
    try {
      final reply = await delegate.complete(
        configuration,
        messages,
        cancellation,
      );
      final usage = reply.usage;
      countUsage(usage);
      record({
        'event': 'response',
        'sequence': sequence,
        'response_model': reply.responseModel,
        'request_id': reply.requestId,
        'usage': usage,
        'duration_ms': watch.elapsedMilliseconds,
        'message': reply.toMessage(),
      });
      await log.flush();
      if (reply.responseModel != configuration.model) {
        throw const AiFailure('model_mismatch');
      }
      return reply;
    } on Object catch (error) {
      if (error is AiInvalidAction) {
        countUsage(error.usage);
        record({
          'event': 'rejected_proposal',
          'sequence': sequence,
          'validation': error.detail,
          'response_model': error.responseModel,
          'request_id': error.requestId,
          'usage': error.usage,
          'message': error.responseMessage,
          'terminal_input_sent': false,
        });
      }
      record({
        'event': 'inference_error',
        'sequence': sequence,
        'error': error.toString(),
        'duration_ms': watch.elapsedMilliseconds,
      });
      await log.flush();
      if (error is AiInvalidAction &&
          error.responseModel != configuration.model) {
        throw const AiFailure('model_mismatch');
      }
      rethrow;
    }
  }
}

void main() {
  // test(), rather than testWidgets(), keeps real async time and real HTTP/PTY.
  // No fake HTTP overrides, model mocks, filesystem helpers or alternate solver.
  _BenchmarkBinding();
  final jobPath = Platform.environment['TRAIL_BENCH_JOB'];
  test(
    'Trail AI operates the Harbor task through native PTY',
    () async {
      final job = jsonDecode(await File(jobPath!).readAsString()) as Map;
      final container = job['container'] as String;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(container) ||
          job['docker_context'] != 'colima-trail-tbench') {
        throw StateError('Benchmark requires a pinned isolated container.');
      }
      final output = Directory(job['output'] as String);
      final model = job['model'] as String;
      final settings = AiSettingsController(
        _MemoryStore(
          AiConfiguration(
            endpoint: 'http://127.0.0.1:8317/v1',
            apiKey: (await File(
              job['key_file'] as String,
            ).readAsString()).trim(),
            model: model,
          ),
        ),
      );
      final trajectory = File(
        '${output.path}/trail-trajectory.jsonl',
      ).openWrite();
      final api = _RecordedApi(trajectory, job['reasoning_effort'] as String);
      final runtime = TerminalRuntimeController.native(
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      TerminalAiController? controller;
      String? session;
      try {
        session = runtime.createSession(
          TerminalSessionConfig(
            launch: TerminalLaunchConfig(
              program: job['docker_executable'] as String,
              args: [
                '--context',
                'colima-trail-tbench',
                'exec',
                '-it',
                if (job['user'] != null) ...['--user', job['user'].toString()],
                if (job['cwd'] != null) ...['--workdir', job['cwd'] as String],
                '--env',
                'TERM=xterm-256color',
                '--env',
                r'PS1=trail-bench [exit:$?] \w > ',
                container,
                '/bin/bash',
                '--noprofile',
                '--norc',
                '-i',
              ],
            ),
          ),
        );
        runtime.resizeSessionCells(session, cols: 160, rows: 48);
        final pane = TerminalPane(
          sessionId: session,
          title: 'Benchmark',
          profileId: 'benchmark',
        );
        final port = TerminalAiRuntime(
          sessionId: session,
          runtime: runtime,
          readPane: () => pane,
          isReadOnly: () => false,
        );
        controller = TerminalAiController(
          settings: settings,
          terminal: port,
          api: api,
          maxSteps: 2048,
        );
        await settings.loaded;
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!(await port.readContext()).screen.contains('trail-bench')) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Container shell did not start');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        api.record({
          'event': 'started',
          'container': container,
          'model': model,
          'terminal_context': (await port.readContext()).toJson(),
        });
        final instruction = await File(
          job['instruction_file'] as String,
        ).readAsString();
        await controller.ask('''
Complete the following task using this terminal.
This is an isolated, disposable benchmark container. The benchmark operator has
authorized the harness to approve your proposed actions inside this container.
Use the terminal tools to inspect, implement and validate the result yourself.
No human will answer questions during the task. Do not stop after a plan. Finish
only after completing the work or explaining a concrete blocker. The shell is
unintegrated: use send_keys for commands and ENTER, and read_screen to observe.
Long text can be sent in multiple chunks; each text item is limited to 4096 chars.
The prompt displays the previous command's exit code. Avoid dumping huge files;
read bounded ranges so they fit the screen. Keep any progress notes in /tmp.
Do not search for benchmark solutions or access hidden verifiers or host files.

$instruction''');
        while (controller.canApprove) {
          api.record({
            'event': 'approval',
            'action': controller.pending!.rawCall,
            'scope': container,
          });
          await controller.approve();
        }
        final result = {
          'model': model,
          'phase': controller.phase.name,
          'error': controller.error,
          'requests': api.requests,
          'n_input_tokens': api.inputTokens,
          'n_output_tokens': api.outputTokens,
          'n_cache_tokens': api.cacheTokens,
          'terminal_context': (await port.readContext()).toJson(),
          'final': controller.transcript.lastOrNull?.text,
        };
        await File(
          '${output.path}/trail-result.json',
        ).writeAsString(jsonEncode(result));
        if (controller.phase != AiPhase.idle) {
          throw StateError('Trail AI stopped: ${controller.error}');
        }
      } finally {
        controller?.dispose();
        if (session != null) runtime.closeSession(session);
        runtime.dispose();
        settings.dispose();
        await trajectory.flush();
        await trajectory.close();
      }
    },
    skip: jobPath == null
        ? 'Run via the explicit Terminal-Bench harness'
        : false,
    timeout: const Timeout(Duration(hours: 8, minutes: 5)),
  );
}
