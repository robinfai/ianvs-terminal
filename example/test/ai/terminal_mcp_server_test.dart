import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/acp/terminal_mcp_server.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Terminal MCP transport', () {
    late TerminalMcpServer server;
    late HttpClient client;
    final calls = <String>[];
    setUp(() async {
      calls.clear();
      client = HttpClient();
      server = TerminalMcpServer((name, args) async {
        calls.add(name);
        return {'state': 'ready', 'context_version': 'one'};
      });
      await server.start();
    });
    tearDown(() async {
      client.close(force: true);
      await server.dispose();
    });
    Future<HttpClientResponse> send(
      Map<String, Object?> body, {
      bool authenticated = true,
      String? origin,
    }) async {
      final request = await client.postUrl(Uri.parse(server.url));
      request.headers.contentType = ContentType.json;
      if (authenticated) {
        request.headers.set('Authorization', 'Bearer ${server.token}');
      }
      if (origin != null) request.headers.set('Origin', origin);
      request.write(jsonEncode(body));
      return request.close();
    }

    test(
      'unauthenticated and browser-origin requests never reach terminal tools',
      () async {
        for (final response in [
          await send({'id': 1, 'method': 'tools/call'}, authenticated: false),
          await send({
            'id': 2,
            'method': 'tools/call',
          }, origin: 'https://example.com'),
        ]) {
          expect(response.statusCode, 403);
          await response.drain<void>();
        }
        expect(calls, isEmpty);
      },
    );
    test(
      'advertises scoped tools and requires context and operation IDs',
      () async {
        final response = await send({'id': 1, 'method': 'tools/list'});
        final result =
            jsonDecode(await utf8.decoder.bind(response).join()) as Map;
        final tools = (result['result'] as Map)['tools'] as List;
        expect(tools, hasLength(6));
        final write = tools.cast<Map<Object?, Object?>>().firstWhere(
          (t) => t['name'] == 'run_command',
        );
        expect(
          (write['inputSchema']! as Map)['required'],
          containsAll(['context_version', 'operation_id']),
        );
        expect(calls, isEmpty);
      },
    );
    test(
      'only pre-input validation errors invite correcting arguments',
      () async {
        await server.dispose();
        var validation = true;
        server = TerminalMcpServer((name, args) async {
          if (validation) {
            throw const AiInvalidAction('reason must be a nonblank string.');
          }
          throw const AiFailure('submission_unknown');
        });
        await server.start();
        for (final invalid in [true, false]) {
          validation = invalid;
          final response = await send({
            'id': 1,
            'method': 'tools/call',
            'params': {'name': 'run_command', 'arguments': <String, Object?>{}},
          });
          final output =
              jsonDecode(await utf8.decoder.bind(response).join()) as Map;
          final result = output['result'] as Map;
          expect(result['isError'], isTrue);
          final content = (result['content'] as List).single as Map;
          final error = jsonDecode(content['text'] as String) as Map;
          if (invalid) {
            expect(error['submitted'], isFalse);
            expect(error['detail'], contains('reason'));
            expect(error['instruction'], contains('Correct the arguments'));
          } else {
            expect(error.containsKey('submitted'), isFalse);
            expect(error.containsKey('detail'), isFalse);
            expect(error['instruction'], contains('Do not resend'));
          }
        }
      },
    );
    test(
      'dispatches authenticated observations but rejects unknown tools',
      () async {
        for (final name in ['get_terminal_state', 'exec_host_shell']) {
          final response = await send({
            'id': 1,
            'method': 'tools/call',
            'params': {'name': name, 'arguments': <String, Object?>{}},
          });
          final output =
              jsonDecode(await utf8.decoder.bind(response).join()) as Map;
          expect(
            output.containsKey(
              name == 'get_terminal_state' ? 'result' : 'error',
            ),
            isTrue,
          );
        }
        expect(calls, ['get_terminal_state']);
      },
    );
  });
}
