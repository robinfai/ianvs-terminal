import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late AiConfiguration configuration;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    configuration = AiConfiguration(
      endpoint: 'http://127.0.0.1:${server.port}/v1',
      apiKey: 'test-secret',
      model: 'test-model',
    );
  });
  tearDown(() async => server.close(force: true));

  test(
    'real HTTP request sends configured auth, model, messages and tool schema',
    () async {
      Map<String, Object?>? body;
      String? authorization;
      String? path;
      int? length;
      server.listen((request) async {
        length = request.contentLength;
        path = request.uri.path;
        authorization = request.headers.value('Authorization');
        body = (jsonDecode(await utf8.decodeStream(request)) as Map)
            .cast<String, Object?>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'Use this command',
                  'tool_calls': [
                    {
                      'id': 'run-1',
                      'function': {
                        'name': 'run_command',
                        'arguments': jsonEncode({
                          'command': 'ls -la',
                          'reason': 'List files',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      final reply = await const AiApiClient().complete(configuration, [
        {'role': 'user', 'content': 'list all files'},
      ], AiCancellation());
      expect(path, '/v1/chat/completions');
      expect(length, greaterThan(0));
      expect(authorization, 'Bearer test-secret');
      expect(body!['model'], 'test-model');
      expect(body!['tools'], hasLength(3));
      expect(body!['parallel_tool_calls'], false);
      expect(reply.action!.command, 'ls -la');
    },
  );

  test('endpoint normalization accepts base, v1 and full completions URL', () {
    for (final path in ['', '/v1/', '/v1/chat/completions']) {
      final config = AiConfiguration(
        endpoint: 'http://localhost:8787$path',
        apiKey: 'test',
        model: 'model',
      );
      expect(config.completionsUri.path, '/v1/chat/completions');
    }
    for (final url in [
      'file:///tmp/model',
      'https://key@example.com/v1',
      'https://example.com?api_key=x',
    ]) {
      expect(
        () => AiConfiguration(
          endpoint: url,
          apiKey: 'test',
          model: 'model',
        ).completionsUri,
        throwsA(isA<AiFailure>()),
      );
    }
  });

  test(
    'authentication failures do not echo potentially sensitive response bodies',
    () async {
      server.listen((request) async {
        request.response.statusCode = 401;
        request.response.write('sensitive provider diagnostic test-secret');
        await request.response.close();
      });
      await expectLater(
        const AiApiClient().complete(configuration, [], AiCancellation()),
        throwsA(
          isA<AiFailure>().having((e) => e.code, 'code', 'authentication'),
        ),
      );
    },
  );

  test('redirects are not followed with the configured credential', () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.statusCode = 307;
      request.response.headers.set('Location', '/other');
      await request.response.close();
    });
    await expectLater(
      const AiApiClient().complete(configuration, [], AiCancellation()),
      throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'http_307')),
    );
    expect(requests, 1);
  });

  test('takeover closes an in-flight network request', () async {
    final received = Completer<void>();
    server.listen((request) {
      received.complete();
    });
    final cancellation = AiCancellation();
    final result = const AiApiClient().complete(
      configuration,
      [],
      cancellation,
    );
    final assertion = expectLater(
      result,
      throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    await received.future;
    cancellation.cancel();
    await assertion;
  });

  test(
    'unsupported or multiple tool calls never reach terminal execution',
    () async {
      server.listen((request) async {
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'tool_calls': [
                    {
                      'id': 'a',
                      'function': {
                        'name': 'delete_everything',
                        'arguments': '{}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      await expectLater(
        const AiApiClient().complete(configuration, [], AiCancellation()),
        throwsA(isA<AiFailure>()),
      );
    },
  );
}
