import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/src/runtime/terminal_diagnostics.dart';

void main() {
  group('TerminalDiagnosticsClient', () {
    test('exports diagnostics using private policy defaults', () {
      final backend = _JsonRequestBackend(
        jsonEncode(<String, Object?>{
          'manifest': <String, Object?>{
            'schema_version': 'terminal-diagnostics-session-v1',
            'session_id': 7,
          },
          'resource_samples': <Object?>[
            <String, Object?>{'timestamp_micros': 1, 'rss_bytes': 100},
          ],
          'terminal_stats': <String, Object?>{
            'session': <String, Object?>{'bytes_read': 4},
          },
          'events': <Object?>[
            <String, Object?>{'kind': 'started'},
          ],
          'summary': <String, Object?>{
            'conclusion': 'insufficient-evidence',
            'markdown': '# Terminal diagnostics',
          },
        }),
      );
      final client = TerminalDiagnosticsClient(backend);

      final export = client.exportSession('7');

      expect(export, isNotNull);
      expect(export!.conclusion, 'insufficient-evidence');
      expect(export.resourceSamples.single['rss_bytes'], 100);
      expect(backend.requests.single, <String, Object?>{
        'kind': 'terminal.export_diagnostics',
        'maxSamples': 60,
        'includeContent': false,
        'redactionMode': 'basic',
        'policy': <String, Object?>{
          'includeScrollback': false,
          'includeRawCommand': false,
          'includeRawCwd': false,
          'includeEnv': false,
        },
      });
    });

    test('uses the correlated Session Request v1 envelope', () {
      final backend = _JsonRequestBackend(
        jsonEncode(<String, Object?>{
          'manifest': <String, Object?>{'schema_version': 1},
          'summary': <String, Object?>{'conclusion': 'ok'},
        }),
      );
      final client = TerminalDiagnosticsClient(backend);

      expect(client.exportSession('7')!.conclusion, 'ok');
      expect(backend.requests, hasLength(1));
      expect(backend.v1Requests, hasLength(1));
      expect(
        backend.v1Requests.single['operation'],
        'terminal.export_diagnostics',
      );
      expect(backend.v1Requests.single['session_id'], '7');
    });

    test('returns null when backend response cannot be decoded', () {
      final backend = _JsonRequestBackend('{');
      final client = TerminalDiagnosticsClient(backend);

      expect(client.exportSession('7'), isNull);

      backend
        ..response = ''
        ..requests.clear();
      expect(client.exportSession('7'), isNull);

      backend.response = null;
      expect(client.exportSession('7'), isNull);
    });

    test('reports backend request errors and returns null', () {
      final backend = _JsonRequestBackend(null)
        ..requestError = StateError('diagnostics request failed');
      final errors = <_RequestError>[];
      final client = TerminalDiagnosticsClient(
        backend,
        onRequestError: (sessionId, operation, error, stackTrace) {
          errors.add(_RequestError(sessionId, operation, error, stackTrace));
        },
      );

      expect(client.exportSession('7'), isNull);

      expect(errors.map((error) => error.operation), <String>[
        'terminal.export_diagnostics',
      ]);
      expect(errors.single.sessionId, '7');
      expect(
        errors.single.error.toString(),
        contains('diagnostics request failed'),
      );
      expect(errors.single.stackTrace, isNot(StackTrace.empty));
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
  String? requestSessionV1Json(String sessionId, String requestV1Json) {
    final request = (jsonDecode(requestV1Json) as Map).cast<String, Object?>();
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
    final configuredPayload = response;
    if (configuredPayload == null || configuredPayload.isEmpty) {
      return configuredPayload;
    }
    final payload = jsonDecode(configuredPayload);
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
