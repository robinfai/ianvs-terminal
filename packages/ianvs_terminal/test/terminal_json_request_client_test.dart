import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/src/runtime/terminal_json_request_client.dart';
import 'package:ianvs_terminal/src/runtime/terminal_zmodem_recovery.dart';
import 'package:ianvs_terminal/src/terminal/terminal_models.dart';

Matcher hasStatus(TerminalZmodemRecoveryResolutionStatus status) =>
    isA<TerminalZmodemRecoveryResolution>().having(
      (value) => value.status,
      'status',
      status,
    );

void main() {
  group('TerminalJsonRequestClient', () {
    test('sends SSH challenge responses without logging or reshaping them', () {
      final backend = _JsonRequestBackend('{"accepted":true}');
      final client = TerminalJsonRequestClient(backend);

      expect(
        client.respondSshAuthentication(
          '7',
          challengeId: 7,
          responses: const <String>['password', '654321'],
        ),
        isTrue,
      );
      expect(backend.requests.single, <String, Object?>{
        'kind': 'ssh.auth_response',
        'challengeId': 7,
        'responses': <String>['password', '654321'],
        'cancel': false,
      });
    });

    test('uses the exact correlated Session Request v1 envelope', () {
      final versioned = _JsonRequestBackend('{"text":"versioned"}');
      final versionedClient = TerminalJsonRequestClient(versioned);

      final versionedText = versionedClient.selectionText(
        '7',
        const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 2),
        block: false,
      );

      expect(versionedText, 'versioned');
      expect(versioned.v1Requests, hasLength(1));
      final v1 = versioned.v1Requests.single;
      expect(v1['schema_version'], 1);
      expect(v1['contract'], 'ianvs-session-request-v1');
      expect(v1['session_id'], '7');
      expect(v1['operation'], 'terminal.selection_text');
      expect(v1['request_id'], startsWith('dart-'));
      expect(v1['payload'], <String, Object?>{
        'selection': <String, Object?>{
          'start_row': 0,
          'start_col': 0,
          'end_row': 0,
          'end_col': 2,
        },
        'block': false,
      });
    });

    test('requests backend selection text and decodes the response', () {
      final backend = _JsonRequestBackend(r'{"text":"hello\n"}');
      final client = TerminalJsonRequestClient(backend);

      final text = client.selectionText(
        '7',
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
          '7',
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
          '7',
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
        '7',
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

      final result = client.searchTextResult('7', 'x');

      expect(result.matches, hasLength(1000));
      expect(result.matches.first.text, 'x0');
      expect(result.matches.last.text, 'x999');
    });

    test(
      'requests scrollback mutations and exports with bounded max lines',
      () {
        final backend = _JsonRequestBackend('{"cleared":true}');
        final client = TerminalJsonRequestClient(backend);

        expect(client.clearScrollback('7'), isTrue);
        expect(client.clearBuffer('7'), isTrue);
        backend.response = '{"dismissed":true}';
        expect(
          client.dismissOsc99Notification('7', 'deploy-1'),
          isTrue,
        );
        backend.response = r'{"content":"alpha\nbeta"}';
        final exported = client.exportScrollbackText(
          '7',
          maxLines: 500000,
        );

        expect(exported, 'alpha\nbeta');
        expect(backend.requests, <Map<String, Object?>>[
          <String, Object?>{'kind': 'terminal.clear_scrollback'},
          <String, Object?>{'kind': 'terminal.clear_buffer'},
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
      final client = TerminalJsonRequestClient(null);

      expect(client.searchTextResult('7', 'hit').matches, isEmpty);
      expect(client.clearScrollback('7'), isFalse);
      expect(client.clearBuffer('7'), isFalse);
      expect(client.dismissOsc99Notification('7', 'deploy-1'), isFalse);
      expect(client.exportScrollbackText('7'), isNull);
    });

    test('sends metadata-only ZMODEM authorization commands', () {
      final backend = _JsonRequestBackend('{"accepted":true}');
      final client = TerminalJsonRequestClient(backend);

      expect(
        client.acceptZmodemReceive(
          '7',
          transferId: '7',
          destination: '/tmp/downloads',
        ),
        isTrue,
      );
      expect(
        client.acceptZmodemSend(
          '7',
          transferId: '8',
          files: const <String>['/tmp/a.txt', '/tmp/b.bin'],
        ),
        isTrue,
      );
      backend.response = '{"cancelled":true}';
      expect(client.cancelZmodem('7', transferId: '9'), isTrue);
      backend.response = '{"reconciled":true,"outcome":"cancelled"}';
      expect(
        client.cancelActiveZmodem('7'),
        TerminalZmodemCancelActiveOutcome.cancelled,
      );
      backend.response = '{"available":true,"path":"/tmp/.report.ianvs-part"}';
      final recovery = client.resolveZmodemRecovery(
        '7',
        recoveryToken: '0123456789abcdef0123456789ABCDEF',
      );
      expect(recovery.status, TerminalZmodemRecoveryResolutionStatus.available);
      expect(recovery.path, '/tmp/.report.ianvs-part');
      backend.response = '{"consumed":true}';
      expect(
        client.consumeZmodemRecovery(
          '7',
          recoveryToken: '0123456789abcdef0123456789ABCDEF',
        ),
        TerminalZmodemRecoveryDisposition.success,
      );
      backend.response = '{"dismissed":false}';
      expect(
        client.dismissZmodemRecovery(
          '7',
          recoveryToken: '0123456789abcdef0123456789ABCDEF',
        ),
        TerminalZmodemRecoveryDisposition.unavailable,
      );

      expect(backend.requests, <Map<String, Object?>>[
        <String, Object?>{
          'kind': 'terminal.zmodem.accept_receive',
          'transferId': '7',
          'destination': '/tmp/downloads',
        },
        <String, Object?>{
          'kind': 'terminal.zmodem.accept_send',
          'transferId': '8',
          'files': <String>['/tmp/a.txt', '/tmp/b.bin'],
        },
        <String, Object?>{'kind': 'terminal.zmodem.cancel', 'transferId': '9'},
        <String, Object?>{'kind': 'terminal.zmodem.cancel_active'},
        <String, Object?>{
          'kind': 'terminal.zmodem.resolve_recovery',
          'recoveryToken': '0123456789abcdef0123456789ABCDEF',
        },
        <String, Object?>{
          'kind': 'terminal.zmodem.consume_recovery',
          'recoveryToken': '0123456789abcdef0123456789ABCDEF',
        },
        <String, Object?>{
          'kind': 'terminal.zmodem.dismiss_recovery',
          'recoveryToken': '0123456789abcdef0123456789ABCDEF',
        },
      ]);
    });

    test('distinguishes id-free ZMODEM cancellation outcomes', () {
      final backend = _JsonRequestBackend(
        '{"reconciled":true,"outcome":"draining"}',
      );
      final client = TerminalJsonRequestClient(backend);

      expect(
        client.cancelActiveZmodem('7'),
        TerminalZmodemCancelActiveOutcome.draining,
      );
      backend.response = '{"reconciled":true,"outcome":"idle"}';
      expect(
        client.cancelActiveZmodem('7'),
        TerminalZmodemCancelActiveOutcome.idle,
      );
      backend.response = '{"reconciled":true}';
      expect(client.cancelActiveZmodem('7'), isNull);
    });

    test('fails closed for invalid ZMODEM recovery tokens and paths', () {
      final backend = _JsonRequestBackend(
        '{"available":true,"path":"relative/file"}',
      );
      final client = TerminalJsonRequestClient(backend);

      expect(
        client.resolveZmodemRecovery('7', recoveryToken: 'not-a-token'),
        hasStatus(TerminalZmodemRecoveryResolutionStatus.requestFailed),
      );
      expect(
        client.consumeZmodemRecovery('7', recoveryToken: 'not-a-token'),
        TerminalZmodemRecoveryDisposition.requestFailed,
      );
      expect(backend.requests, isEmpty);

      expect(
        client.resolveZmodemRecovery(
          '7',
          recoveryToken: '0123456789abcdef0123456789abcdef',
        ),
        hasStatus(TerminalZmodemRecoveryResolutionStatus.requestFailed),
      );
      backend.response = r'{"available":true,"path":"/tmp/bad\u0000path"}';
      expect(
        client.resolveZmodemRecovery(
          '7',
          recoveryToken: '0123456789abcdef0123456789abcdef',
        ),
        hasStatus(TerminalZmodemRecoveryResolutionStatus.requestFailed),
      );
      backend.response = null;
      expect(
        client.resolveZmodemRecovery(
          '7',
          recoveryToken: '0123456789abcdef0123456789abcdef',
        ),
        hasStatus(TerminalZmodemRecoveryResolutionStatus.requestFailed),
      );
      backend.response = '{"available":false}';
      expect(
        client.resolveZmodemRecovery(
          '7',
          recoveryToken: '0123456789abcdef0123456789abcdef',
        ),
        hasStatus(TerminalZmodemRecoveryResolutionStatus.unavailable),
      );
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
        '7',
        const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 2),
        block: false,
      );
      final searchResult = client.searchTextResult('7', 'hit');
      final clearResult = client.clearScrollback('7');
      final clearBufferResult = client.clearBuffer('7');
      final dismissResult = client.dismissOsc99Notification(
        '7',
        'deploy-1',
      );
      final exportText = client.exportScrollbackText('7');
      final recoveryPath = client.resolveZmodemRecovery(
        '7',
        recoveryToken: '0123456789abcdef0123456789abcdef',
      );

      expect(selectionText, isNull);
      expect(searchResult.matches, isEmpty);
      expect(clearResult, isFalse);
      expect(clearBufferResult, isFalse);
      expect(dismissResult, isFalse);
      expect(exportText, isNull);
      expect(
        recoveryPath.status,
        TerminalZmodemRecoveryResolutionStatus.requestFailed,
      );
      expect(errors.map((error) => error.operation), <String>[
        'terminal.selection_text',
        'terminal.search_text',
        'terminal.clear_scrollback',
        'terminal.clear_buffer',
        'terminal.dismiss_osc99_notification',
        'terminal.export_scrollback',
        'terminal.zmodem.resolve_recovery',
      ]);
      expect(errors.every((error) => error.sessionId == '7'), isTrue);
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

final class _JsonRequestBackend implements PtySessionRequestV1Backend {
  _JsonRequestBackend(this.response);

  String? response;
  Object? requestError;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> v1Requests = <Map<String, Object?>>[];

  @override
  String? requestSessionV1Json(String sessionId, String requestJson) {
    final request = (jsonDecode(requestJson) as Map).cast<String, Object?>();
    v1Requests.add(request);
    requests.add(<String, Object?>{
      'kind': request['operation'],
      ...(request['payload']! as Map).cast<String, Object?>(),
    });
    final error = requestError;
    if (error != null) {
      // The fake must preserve the exact configured transport failure object.
      // ignore: only_throw_errors
      throw error;
    }
    final configured = response;
    if (configured == null || configured.isEmpty) {
      return configured;
    }
    final Object? payload;
    try {
      payload = jsonDecode(configured);
    } on FormatException {
      return configured;
    }
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-session-response-v1',
      'request_id': request['request_id'],
      'session_id': sessionId,
      'operation': request['operation'],
      'ok': true,
      'timestamp_micros': 1234,
      'payload': payload,
    });
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
