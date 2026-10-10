import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/acp/acp_environment.dart';
import 'package:app/features/ai/acp/agent_backend.dart';
import 'package:app/features/ai/acp/codex_acp_backend.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart' show FakeTerminal, MemoryAiStore;

String _dart() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = File('${directory.path}/dart-sdk/bin/dart');
    if (candidate.existsSync()) return candidate.path;
    directory = directory.parent;
  }
  return Platform.resolvedExecutable;
}

// The production backend still performs its normal copy/isolation path, but
// every access to the host authentication file is redirected before any IO.
final class _SyntheticAuthentication extends IOOverrides {
  _SyntheticAuthentication(this.fixturePath);

  final String fixturePath;

  @override
  File createFile(String path) => super.createFile(
    path == readCodexAuthenticationPath() ? fixturePath : path,
  );
}

class _ReplyGate {
  _ReplyGate(this.method);

  final String method;
  int? processId;
  final reached = Completer<void>();
  final release = Completer<void>();
  final replied = Completer<void>();
}

class _ProtocolObserver {
  _ProtocolObserver(this.server) {
    server.listen((request) => unawaited(_receive(request)));
  }

  final HttpServer server;
  final requests = <Map<String, Object?>>[];
  final gates = <_ReplyGate>[];

  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/');

  _ReplyGate hold(String method) {
    final gate = _ReplyGate(method);
    gates.add(gate);
    return gate;
  }

  Future<void> _receive(HttpRequest request) async {
    _ReplyGate? gate;
    try {
      final text = await utf8.decoder.bind(request).join();
      final event = (jsonDecode(text) as Map).cast<String, Object?>();
      requests.add(event);
      gate = gates
          .where((g) => !g.reached.isCompleted && g.method == event['method'])
          .firstOrNull;
      if (gate != null) {
        gate.processId = event['pid']! as int;
        gate.reached.complete();
        await gate.release.future;
      }
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    } on Object {
      // A cancelled fixture closes its held request before the gate releases.
    } finally {
      if (gate != null && !gate.replied.isCompleted) gate.replied.complete();
    }
  }

  List<String> get userRequests => requests
      .where((request) => request['method'] == 'session/prompt')
      .map((request) {
        final parts = (request['params']! as Map)['prompt']! as List;
        final prompt =
            jsonDecode((parts.single as Map)['text']! as String) as Map;
        final user = jsonDecode(prompt['user_request']! as String) as Map;
        return user['request']! as String;
      })
      .toList();

  Map<String, Object?>? bridgeFor(int processId) {
    final connected = requests.where(
      (request) =>
          request['pid'] == processId &&
          {'session/new', 'session/load'}.contains(request['method']),
    );
    if (connected.isEmpty) return null;
    final servers = (connected.last['params']! as Map)['mcpServers']! as List;
    return (servers.single as Map).cast<String, Object?>();
  }

  Future<void> dispose() async {
    for (final gate in gates) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
    await server.close(force: true);
  }
}

class _ObservedBackend implements AgentBackend {
  _ObservedBackend(this.backend);

  final CodexAcpBackend backend;
  final settled = <Completer<String?>>[];
  final updates = <Map<String, Object?>>[];
  final toolCalls = <String>[];

  @override
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  }) async {
    final completion = Completer<String?>();
    settled.add(completion);
    try {
      await backend.prompt(
        prompt,
        tools: (name, arguments) {
          toolCalls.add(name);
          return tools(name, arguments);
        },
        events: (event) {
          updates.add(event);
          events(event);
        },
        cancellation: cancellation,
      );
      completion.complete(null);
    } on Object catch (error) {
      completion.complete(error is AiFailure ? error.code : error.toString());
      rethrow;
    }
  }

  @override
  Future<void> dispose() => backend.dispose();
}

Future<void> _probeOldBridge(Map<String, Object?> bridge) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(bridge['url']! as String));
    for (final header
        in (bridge['headers']! as List).cast<Map<String, Object?>>()) {
      request.headers.set(
        header['name']! as String,
        header['value']! as String,
      );
    }
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'get_terminal_state',
          'arguments': <String, Object?>{},
        },
      }),
    );
    final response = await request.close();
    await response.drain<void>();
  } on SocketException {
    // Closing the old bridge is the expected outcome.
  } on HttpException {
    // A cancellation may close the socket before any response headers.
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('ACP connection cancellation', () {
    for (final stage in [
      'initialize',
      'session/new',
      'session/set_config_option',
      'session/load',
    ]) {
      test(
        'supplement during $stage cancels the connection and delivers the latest requirement',
        () async {
          final fixture = await Directory.systemTemp.createTemp(
            'trail-acp-connection-test-',
          );
          final authentication = File('${fixture.path}/synthetic-auth.json');
          await authentication.writeAsString('{"fixture":true}');
          final observer = _ProtocolObserver(
            await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
          );
          final configuration = AiConfiguration.acp(
            agentCommand: _dart(),
            agentArguments: [
              File('test/fixtures/acp_connection_agent.dart').absolute.path,
              observer.uri.toString(),
            ],
            model: 'fixture-model',
          );
          try {
            await IOOverrides.runWithIOOverrides(() async {
              final backend = _ObservedBackend(CodexAcpBackend(configuration));
              final settings = AiSettingsController(
                MemoryAiStore(configuration),
              );
              await settings.loaded;
              final terminal = FakeTerminal();
              final controller = TerminalAiController(
                settings: settings,
                terminal: terminal,
                agentFactory: (_) => backend,
              );
              try {
                if (stage == 'session/load') {
                  // Establish a session, then cancel a held prompt so the next
                  // turn must reconnect through session/load on this backend.
                  final warmup = observer.hold('session/prompt');
                  final asked = controller.ask('Warm up the existing session.');
                  await warmup.reached.future.timeout(
                    const Duration(seconds: 5),
                  );
                  controller.takeOver();
                  expect(
                    await backend.settled.single.future.timeout(
                      const Duration(seconds: 5),
                    ),
                    'cancelled',
                  );
                  await asked;
                }

                final gate = observer.hold(stage);
                const original = 'Inspect the original target without changes.';
                const latest =
                    'Only inspect the replacement target; do not write.';
                final interruptedIndex = backend.settled.length;
                final updatesBefore = backend.updates.length;
                final asked = controller.ask(original);
                await gate.reached.future.timeout(const Duration(seconds: 5));
                final oldBridge = observer.bridgeFor(gate.processId!);
                await expectLater(
                  backend.backend.prompt(
                    'Uncancelled concurrent request',
                    tools: (_, _) async => throw StateError('Unexpected tool'),
                    events: (_) => fail('Concurrent request emitted an event'),
                    cancellation: AiCancellation(),
                  ),
                  throwsA(
                    isA<AiFailure>().having(
                      (failure) => failure.code,
                      'code',
                      'acp_busy',
                    ),
                  ),
                );

                // Do not wait for the old protocol reply or cancellation to
                // settle before requesting the replacement: this is the UI's
                // real supplement path and must not surface acp_busy.
                final supplemented = controller.supplement(latest);
                await supplemented.timeout(const Duration(seconds: 5));
                expect(controller.error, isNull);
                expect(backend.settled, hasLength(interruptedIndex + 2));
                expect(
                  await backend.settled[interruptedIndex].future.timeout(
                    const Duration(seconds: 5),
                  ),
                  'cancelled',
                );
                expect(
                  await backend.settled.last.future.timeout(
                    const Duration(seconds: 5),
                  ),
                  isNull,
                );
                await asked;
                expect(gate.release.isCompleted, isFalse);
                expect(observer.userRequests, isNot(contains(original)));
                expect(
                  observer.userRequests.where((request) => request == latest),
                  hasLength(1),
                );
                expect(controller.phase, AiPhase.idle);
                expect(
                  controller.transcript
                      .where((entry) => entry.role == 'assistant')
                      .map((entry) => entry.text),
                  contains('Latest requirement received.'),
                );
                expect(terminal.writes, isEmpty);

                // Release the stale connection reply while another legitimate
                // turn is active. It must neither restore old events nor use
                // the replacement turn's tools through its old MCP endpoint.
                final nextGate = observer.hold('session/prompt');
                const nextRequirement = 'Inspect once more without changes.';
                final next = controller.ask(nextRequirement);
                await nextGate.reached.future.timeout(
                  const Duration(seconds: 5),
                );
                gate.release.complete();
                await gate.replied.future.timeout(const Duration(seconds: 5));
                if (oldBridge != null) {
                  await _probeOldBridge(
                    oldBridge,
                  ).timeout(const Duration(seconds: 5));
                }
                expect(backend.toolCalls, isEmpty);
                nextGate.release.complete();
                await next.timeout(const Duration(seconds: 5));
                expect(await backend.settled.last.future, isNull);
                expect(controller.error, isNull);
                expect(controller.phase, AiPhase.idle);
                expect(observer.userRequests, isNot(contains(original)));
                expect(
                  observer.userRequests.where((request) => request == latest),
                  hasLength(1),
                );
                expect(observer.userRequests.last, nextRequirement);
                expect(
                  backend.updates
                      .skip(updatesBefore)
                      .where(
                        (event) =>
                            event['sessionUpdate'] == 'trail_connection' &&
                            (event['agent'] as Map?)?['fixture_pid'] ==
                                gate.processId,
                      ),
                  isEmpty,
                );
              } finally {
                controller.takeOver();
                await controller.closeAgentSessions();
                controller.dispose();
                settings.dispose();
              }
            }, _SyntheticAuthentication(authentication.path));
          } finally {
            await observer.dispose();
            await fixture.delete(recursive: true);
          }
        },
      );
    }
  });
}
