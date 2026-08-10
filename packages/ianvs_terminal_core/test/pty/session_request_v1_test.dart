import 'dart:convert';

import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';
import 'package:test/test.dart';

void main() {
  group('PtySessionRequestV1', () {
    test('encodes the declared request envelope without a legacy kind', () {
      const request = PtySessionRequestV1(
        requestId: 'dart-1',
        sessionId: '7',
        operation: 'terminal.search_text',
        payload: <String, Object?>{
          'query': 'error',
          'mode': 'smart_case_substring',
        },
      );

      final json = jsonDecode(request.toJsonString()) as Map<String, dynamic>;

      expect(json['schema_version'], 1);
      expect(json['contract'], 'ianvs-session-request-v1');
      expect(json['request_id'], 'dart-1');
      expect(json['session_id'], '7');
      expect(json['operation'], 'terminal.search_text');
      expect(json['payload'], <String, Object?>{
        'query': 'error',
        'mode': 'smart_case_substring',
      });
      expect(json, isNot(contains('kind')));
    });

    test('rejects invalid identity and oversized requests structurally', () {
      expect(
        () => const PtySessionRequestV1(
          requestId: 'dart-1',
          sessionId: 'not-native',
          operation: 'terminal.search_text',
          payload: <String, Object?>{},
        ).toJsonString(),
        throwsA(
          isA<PtySessionRequestContractException>().having(
            (error) => error.code,
            'code',
            'invalid_session_id',
          ),
        ),
      );
      expect(
        () => PtySessionRequestV1(
          requestId: 'dart-1',
          sessionId: '7',
          operation: 'terminal.search_text',
          payload: <String, Object?>{
            'padding': 'x' * PtySessionRequestV1.maxEncodedBytes,
          },
        ).toJsonString(),
        throwsA(
          isA<PtySessionRequestContractException>().having(
            (error) => error.code,
            'code',
            'encoded_request_too_large',
          ),
        ),
      );
    });
  });

  group('PtySessionResponseV1', () {
    test('decodes additive fields and enforces exact correlation', () {
      final response = PtySessionResponseV1.fromJsonString(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-session-response-v1',
          'request_id': 'dart-1',
          'session_id': '7',
          'operation': 'terminal.search_text',
          'ok': true,
          'timestamp_micros': 1234,
          'payload': <String, Object?>{'matches': <Object?>[]},
          'future': true,
        }),
        expectedRequestId: 'dart-1',
        expectedSessionId: '7',
        expectedOperation: 'terminal.search_text',
      );

      expect(response.ok, isTrue);
      expect(response.timestampMicros, 1234);
      expect(response.payload, <String, Object?>{'matches': <Object?>[]});
      expect(response.error, isNull);
    });

    test('decodes structured remote errors', () {
      final response = PtySessionResponseV1.fromJsonString(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-session-response-v1',
          'request_id': 'dart-2',
          'session_id': '7',
          'operation': 'terminal.future_operation',
          'ok': false,
          'timestamp_micros': 1235,
          'error': <String, Object?>{
            'code': 'unsupported_operation',
            'message': 'unsupported',
          },
        }),
        expectedRequestId: 'dart-2',
        expectedSessionId: '7',
        expectedOperation: 'terminal.future_operation',
      );

      expect(response.ok, isFalse);
      expect(response.payload, isNull);
      expect(response.error!.code, 'unsupported_operation');
    });

    test('rejects correlation drift and oversized responses', () {
      final valid = jsonEncode(<String, Object?>{
        'schema_version': 1,
        'contract': 'ianvs-session-response-v1',
        'request_id': 'wrong',
        'session_id': '7',
        'operation': 'terminal.search_text',
        'ok': true,
        'timestamp_micros': 1234,
        'payload': <String, Object?>{},
      });
      expect(
        () => PtySessionResponseV1.fromJsonString(
          valid,
          expectedRequestId: 'dart-1',
          expectedSessionId: '7',
          expectedOperation: 'terminal.search_text',
        ),
        throwsA(
          isA<PtySessionRequestContractException>().having(
            (error) => error.code,
            'code',
            'correlation_mismatch',
          ),
        ),
      );
      expect(
        () => PtySessionResponseV1.fromJsonString(
          ' ' * (PtySessionResponseV1.maxEncodedBytes + 1),
          expectedRequestId: 'dart-1',
          expectedSessionId: '7',
          expectedOperation: 'terminal.search_text',
        ),
        throwsA(
          isA<PtySessionRequestContractException>().having(
            (error) => error.code,
            'code',
            'encoded_response_too_large',
          ),
        ),
      );
    });
  });
}
