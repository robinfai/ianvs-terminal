import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart' show FakeTerminal, MemoryAiStore;

String event(Map<String, Object?> delta, {String? finish}) =>
    'data: ${jsonEncode({
      'id': 'response-1',
      'model': 'fixture',
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': finish},
      ],
    })}\r\n\r\n';

void main() {
  late HttpServer server;
  late AiConfiguration configuration;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    configuration = AiConfiguration(
      endpoint: 'http://127.0.0.1:${server.port}/v1',
      apiKey: 'fixture-only',
      model: 'fixture',
    );
  });
  tearDown(() async => server.close(force: true));

  test('real HTTP displays UTF-8 deltas before response completes', () async {
    final first = Completer<void>();
    final finish = Completer<void>();
    final updates = <AiResponseUpdate>[];
    Map<String, Object?>? payload;
    server.listen((request) async {
      payload =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.bufferOutput = false;
      request.response.write(': heartbeat\r\n\r\n');
      final bytes = utf8.encode(event({'content': '你好🙂'}));
      // Deliberately split inside multibyte code points and SSE line endings.
      final split = bytes.indexOf(0xe4) + 1;
      request.response.add(bytes.sublist(0, split));
      await request.response.flush();
      request.response.add(bytes.sublist(split));
      await request.response.flush();
      await finish.future;
      request.response.write(event({'content': '，完成。'}));
      request.response.write(event({}, finish: 'stop'));
      request.response.write(
        'data: {"choices":[],"usage":{"completion_tokens":7}}\n\n',
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    var completed = false;
    final future = const AiApiClient()
        .completeStreaming(
          configuration,
          [
            {'role': 'user', 'content': '测试'},
          ],
          AiCancellation(),
          (update) {
            updates.add(update);
            if (update.textDelta.isNotEmpty && !first.isCompleted) {
              first.complete();
            }
          },
        )
        .then((reply) {
          completed = true;
          return reply;
        });
    await first.future.timeout(const Duration(seconds: 3));
    expect(payload!['stream'], true);
    expect(completed, false);
    expect(updates.first.stage, AiResponseStage.waitingForFirstToken);
    expect(updates.last.textDelta, '你好🙂');
    finish.complete();
    final reply = await future;
    expect(reply.text, '你好🙂，完成。');
    expect(reply.requestId, 'response-1');
    expect(reply.usage?['completion_tokens'], 7);
  });

  test('tool arguments and finish marker alone cannot open approval', () async {
    final partial = Completer<void>();
    final allowArguments = Completer<void>();
    final argumentsSent = Completer<void>();
    final allowDone = Completer<void>();
    final settings = AiSettingsController(MemoryAiStore(configuration));
    await settings.loaded;
    final terminal = FakeTerminal();
    final controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
    );
    addTearDown(controller.dispose);
    addTearDown(settings.dispose);
    controller.addListener(() {
      if (controller.phase == AiPhase.generating && !partial.isCompleted) {
        partial.complete();
      }
    });
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.bufferOutput = false;
      request.response.write(
        event({
          'content': '检查目录',
          'tool_calls': [
            {
              'index': 0,
              'id': 'call-1',
              'type': 'function',
              'function': {
                'name': 'run_command',
                'arguments': '{"command":"pwd"',
              },
            },
          ],
        }),
      );
      await request.response.flush();
      await allowArguments.future;
      request.response.write(
        event({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': ',"reason":"检查目录"}'},
            },
          ],
        }),
      );
      request.response.write(event({}, finish: 'tool_calls'));
      await request.response.flush();
      argumentsSent.complete();
      await allowDone.future;
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final turn = controller.ask('检查目录');
    await partial.future.timeout(const Duration(seconds: 3));
    final entryId = controller.transcript.last.id;
    expect(controller.transcript.last.text, '检查目录');
    expect(controller.pending, isNull);
    expect(controller.canApprove, false);
    expect(terminal.writes, isEmpty);
    allowArguments.complete();
    await argumentsSent.future;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.pending, isNull);
    expect(controller.canApprove, false);
    allowDone.complete();
    await turn;
    expect(controller.canApprove, true);
    expect(controller.pending!.command, 'pwd');
    expect(
      controller.transcript.where((e) => e.role == 'assistant').single.id,
      entryId,
    );
    expect(terminal.writes, isEmpty);
  });

  for (final ending in ['eof', 'length', 'invalid', 'multiple']) {
    test('$ending stream fails once without proposal or retry', () async {
      var requests = 0;
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.bufferOutput = false;
        request.response.write(event({'content': '部分回复'}));
        switch (ending) {
          case 'eof':
            request.response.write(event({}, finish: 'stop'));
          case 'length':
            request.response.write(event({}, finish: 'length'));
          case 'invalid':
            request.response.write('data: {invalid}\n\n');
          case 'multiple':
            request.response.write(
              event({
                'tool_calls': [
                  {'index': 1},
                ],
              }),
            );
        }
        await request.response.close();
      });
      final settings = AiSettingsController(MemoryAiStore(configuration));
      await settings.loaded;
      final terminal = FakeTerminal();
      final controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
      );
      addTearDown(controller.dispose);
      addTearDown(settings.dispose);
      await controller.ask('Explain');
      expect(controller.phase, AiPhase.failed);
      expect(controller.transcript.last.text, '部分回复');
      expect(controller.pending, isNull);
      expect(terminal.writes, isEmpty);
      expect(requests, 1);
    });
  }

  test('timeout and cancellation close the stream without retry', () async {
    final responses = <HttpResponse>[];
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      responses.add(request.response);
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.bufferOutput = false;
      request.response.write(': waiting\n\n');
      await request.response.flush();
    });
    await expectLater(
      const AiApiClient(
        timeout: Duration(milliseconds: 80),
      ).completeStreaming(configuration, [], AiCancellation(), (_) {}),
      throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'timeout')),
    );
    final cancellation = AiCancellation();
    await expectLater(
      const AiApiClient().completeStreaming(configuration, [], cancellation, (
        _,
      ) {
        cancellation.cancel();
      }),
      throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(requests, 2);
    for (final response in responses) {
      unawaited(response.close());
    }
  });
}
