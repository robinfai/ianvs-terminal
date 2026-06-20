import 'dart:convert';

import 'package:app/features/command_center/fig_completion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

void main() {
  group('FigCompletionService', () {
    test('decodes native completion suggestions', () {
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

    test('passes command input context through native bindings', () async {
      final bindings = _FakeFigCompletionBindings(
        responseJson: jsonEncode({
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
      final service = FigCompletionService(bindings: bindings);

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
      expect(bindings.requests, hasLength(1));
      final received =
          jsonDecode(bindings.requests.single) as Map<String, Object?>;
      expect(received['text'], 'git che');
      expect(received['cursorOffset'], 7);
      expect(received['cwd'], '/repo');
      expect(received['shell'], '/bin/zsh');
      expect(received['sessionId'], 'session-a');
    });

    test('returns null when native bindings return invalid JSON', () async {
      final service = FigCompletionService(
        bindings: _FakeFigCompletionBindings(responseJson: '{'),
      );

      final response = await service.complete(
        const FigCompletionRequest(text: 'git che', cursorOffset: 7),
      );

      expect(response, isNull);
    });
  });
}

class _FakeFigCompletionBindings implements FigCompletionBindings {
  _FakeFigCompletionBindings({required this.responseJson});

  final String? responseJson;
  final List<String> requests = <String>[];

  @override
  String? completeJson(String requestJson) {
    requests.add(requestJson);
    return responseJson;
  }
}
