import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/src/runtime/terminal_json_request_client.dart';
import 'package:ianvs_terminal/src/terminal/terminal_models.dart';

void main() {
  group('TerminalJsonRequestClient', () {
    test('requests backend selection text and decodes the response', () {
      final backend = _JsonRequestBackend('{"text":"hello\\n"}');
      final client = TerminalJsonRequestClient(backend);

      final text = client.selectionText(
        'session-a',
        const TerminalSelection(startRow: 1, startCol: 2, endRow: 3, endCol: 4),
        block: true,
      );

      expect(text, 'hello\n');
      expect(backend.requests.single, <String, Object?>{
        'kind': 'terminal.selection_text',
        'selection': <String, Object?>{
          'start_row': 1,
          'start_col': 2,
          'end_row': 3,
          'end_col': 4,
        },
        'block': true,
      });
    });

    test('returns null for undecodable selection responses', () {
      final backend = _JsonRequestBackend('{');
      final client = TerminalJsonRequestClient(backend);

      expect(
        client.selectionText(
          'session-a',
          const TerminalSelection(
            startRow: 0,
            startCol: 0,
            endRow: 0,
            endCol: 2,
          ),
          block: false,
        ),
        isNull,
      );

      backend
        ..response = '{"text":7}'
        ..requests.clear();
      expect(
        client.selectionText(
          'session-a',
          const TerminalSelection(
            startRow: 0,
            startCol: 0,
            endRow: 0,
            endCol: 2,
          ),
          block: false,
        ),
        isNull,
      );
    });

    test('decodes search results conservatively', () {
      final backend = _JsonRequestBackend(
        jsonEncode(<String, Object?>{
          'matches': <Object?>[
            for (var index = 0; index < 1004; index += 1)
              <String, Object?>{'row': 'bad-$index'},
            <String, Object?>{
              'row': 3,
              'start_col': 1,
              'end_col': 4,
              'text': 'hit',
              'scrollback_offset': 2,
            },
          ],
          'error_text': ' invalid regex ',
        }),
      );
      final client = TerminalJsonRequestClient(backend);

      final result = client.searchTextResult(
        'session-a',
        'hit',
        mode: TerminalSearchMode.caseSensitiveRegex,
      );

      expect(result.matches.single.text, 'hit');
      expect(result.matches.single.scrollbackOffset, 2);
      expect(result.errorText, 'invalid regex');
      expect(backend.requests.single, <String, Object?>{
        'kind': 'terminal.search_text',
        'query': 'hit',
        'mode': 'case_sensitive_regex',
      });
    });

    test('caps oversized search result responses', () {
      final backend = _JsonRequestBackend(
        jsonEncode(<String, Object?>{
          'matches': <Object?>[
            for (var index = 0; index < 1002; index += 1)
              <String, Object?>{
                'row': index,
                'start_col': 0,
                'end_col': 1,
                'text': 'x$index',
                'scrollback_offset': index,
              },
          ],
        }),
      );
      final client = TerminalJsonRequestClient(backend);

      final result = client.searchTextResult('session-a', 'x');

      expect(result.matches, hasLength(1000));
      expect(result.matches.first.text, 'x0');
      expect(result.matches.last.text, 'x999');
    });

    test(
      'requests scrollback mutations and exports with bounded max lines',
      () {
        final backend = _JsonRequestBackend('{"cleared":true}');
        final client = TerminalJsonRequestClient(backend);

        expect(client.clearScrollback('session-a'), isTrue);
        backend.response = '{"dismissed":true}';
        expect(
          client.dismissOsc99Notification('session-a', 'deploy-1'),
          isTrue,
        );
        backend.response = '{"content":"alpha\\nbeta"}';
        final exported = client.exportScrollbackText(
          'session-a',
          maxLines: 500000,
        );

        expect(exported, 'alpha\nbeta');
        expect(backend.requests, <Map<String, Object?>>[
          <String, Object?>{'kind': 'terminal.clear_scrollback'},
          <String, Object?>{
            'kind': 'terminal.dismiss_osc99_notification',
            'id': 'deploy-1',
          },
          <String, Object?>{
            'kind': 'terminal.export_scrollback',
            'maxLines': 100000,
          },
        ]);
      },
    );

    test('returns empty values without a JSON request backend', () {
      const client = TerminalJsonRequestClient(null);

      expect(client.searchTextResult('session-a', 'hit').matches, isEmpty);
      expect(client.clearScrollback('session-a'), isFalse);
      expect(client.dismissOsc99Notification('session-a', 'deploy-1'), isFalse);
      expect(client.exportScrollbackText('session-a'), isNull);
    });

    test('reports backend request errors and returns empty values', () {
      final backend = _JsonRequestBackend(null)
        ..requestError = StateError('json request failed');
      final errors = <_RequestError>[];
      final client = TerminalJsonRequestClient(
        backend,
        onRequestError: (sessionId, operation, error, stackTrace) {
          errors.add(_RequestError(sessionId, operation, error, stackTrace));
        },
      );

      final selectionText = client.selectionText(
        'session-a',
        const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 2),
        block: false,
      );
      final searchResult = client.searchTextResult('session-a', 'hit');
      final clearResult = client.clearScrollback('session-a');
      final dismissResult = client.dismissOsc99Notification(
        'session-a',
        'deploy-1',
      );
      final exportText = client.exportScrollbackText('session-a');

      expect(selectionText, isNull);
      expect(searchResult.matches, isEmpty);
      expect(clearResult, isFalse);
      expect(dismissResult, isFalse);
      expect(exportText, isNull);
      expect(errors.map((error) => error.operation), <String>[
        'terminal.selection_text',
        'terminal.search_text',
        'terminal.clear_scrollback',
        'terminal.dismiss_osc99_notification',
        'terminal.export_scrollback',
      ]);
      expect(errors.every((error) => error.sessionId == 'session-a'), isTrue);
      expect(
        errors.every(
          (error) => error.error.toString().contains('json request failed'),
        ),
        isTrue,
      );
      expect(
        errors.every((error) => error.stackTrace != StackTrace.empty),
        isTrue,
      );
    });
  });
}

final class _JsonRequestBackend implements PtySessionJsonRequestBackend {
  _JsonRequestBackend(this.response);

  String? response;
  Object? requestError;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    requests.add((jsonDecode(requestJson) as Map).cast<String, Object?>());
    final error = requestError;
    if (error != null) {
      throw error;
    }
    return response;
  }
}

final class _RequestError {
  const _RequestError(
    this.sessionId,
    this.operation,
    this.error,
    this.stackTrace,
  );

  final String sessionId;
  final String operation;
  final Object error;
  final StackTrace stackTrace;
}
