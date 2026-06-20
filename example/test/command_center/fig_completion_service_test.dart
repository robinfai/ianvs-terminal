import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/command_center/fig_completion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FigCompletionService', () {
    test('decodes sidecar completion suggestions', () {
      final response = FigCompletionResponse.fromJson({
        'items': [
          {
            'name': 'checkout',
            'insertText': 'checkout',
            'replaceStart': 4,
            'replaceEnd': 7,
            'cursorOffset': 12,
            'description': 'Switch branches',
            'type': 'subcommand',
            'source': 'fig:git',
            'priority': 75,
          },
        ],
      });

      expect(response.items, hasLength(1));
      expect(response.items.single.name, 'checkout');
      expect(response.items.single.replacementText, 'checkout');
      expect(response.items.single.replaceStart, 4);
      expect(response.items.single.replaceEnd, 7);
      expect(response.items.single.cursorOffset, 12);
      expect(response.items.single.source, 'fig:git');
    });

    test('posts command input context to the sidecar', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = <Map<String, Object?>>[];
      unawaited(() async {
        await for (final request in server) {
          final body = await utf8.decoder.bind(request).join();
          received.add(jsonDecode(body) as Map<String, Object?>);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'items': [
                {
                  'name': 'checkout',
                  'insertText': 'checkout',
                  'replaceStart': 4,
                  'replaceEnd': 7,
                  'type': 'subcommand',
                },
              ],
            }),
          );
          await request.response.close();
        }
      }());

      final service = FigCompletionService(
        endpoint: Uri.parse('http://${server.address.host}:${server.port}'),
        timeout: const Duration(seconds: 1),
        failureBackoff: Duration.zero,
      );
      addTearDown(service.close);

      final response = await service.complete(
        const FigCompletionRequest(
          text: 'git che',
          cursorOffset: 7,
          cwd: '/repo',
          shell: '/bin/zsh',
          sessionId: 'session-a',
          environmentVariables: {'TERM': 'xterm-256color'},
          recentCommands: ['git checkout main'],
        ),
      );

      expect(response, isNotNull);
      expect(response!.items.single.name, 'checkout');
      expect(received, hasLength(1));
      expect(received.single['text'], 'git che');
      expect(received.single['cursorOffset'], 7);
      expect(received.single['cwd'], '/repo');
      expect(received.single['shell'], '/bin/zsh');
      expect(received.single['sessionId'], 'session-a');
    });

    test('returns null when the sidecar rejects a request', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(() async {
        await for (final request in server) {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
      }());

      final service = FigCompletionService(
        endpoint: Uri.parse('http://${server.address.host}:${server.port}'),
        timeout: const Duration(seconds: 1),
        failureBackoff: Duration.zero,
      );
      addTearDown(service.close);

      final response = await service.complete(
        const FigCompletionRequest(text: 'git che', cursorOffset: 7),
      );

      expect(response, isNull);
    });
  });
}
