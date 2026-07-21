import 'dart:convert';

import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:test/test.dart';

void main() {
  group('PtyHostRequestV1', () {
    test('decodes a correlated request and ignores additive fields', () {
      final request = PtyHostRequestV1.fromJson(
        <String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-host-request-v1',
          'request_id': 'host:7:3',
          'session_id': '7',
          'operation': 'clipboard.read_text',
          'sequence': 3,
          'timestamp_micros': 1200,
          'payload': <String, Object?>{'selection': 'c'},
          'future': true,
        },
        expectedSessionId: '7',
        expectedSequence: 3,
        expectedTimestampMicros: 1200,
      );

      expect(request.requestId, 'host:7:3');
      expect(request.operation, 'clipboard.read_text');
      expect(request.payload, <String, Object?>{'selection': 'c'});
    });

    test('rejects outer Runtime Event correlation drift', () {
      expect(
        () => PtyHostRequestV1.fromJson(
          _requestJson(),
          expectedSessionId: '7',
          expectedSequence: 4,
          expectedTimestampMicros: 1200,
        ),
        throwsA(
          isA<PtyHostRequestContractException>().having(
            (error) => error.code,
            'code',
            'correlation_mismatch',
          ),
        ),
      );
    });
  });

  group('PtyHostResponseV1', () {
    test('encodes success and structured denial with exact identity', () {
      final request = PtyHostRequestV1.fromJson(
        _requestJson(),
        expectedSessionId: '7',
        expectedSequence: 3,
        expectedTimestampMicros: 1200,
      );
      final success = PtyHostResponseV1.success(
        request: request,
        timestampMicros: 1300,
        payload: <String, Object?>{
          'data_base64': base64.encode(utf8.encode('hello')),
        },
      );
      final denied = PtyHostResponseV1.failure(
        request: request,
        timestampMicros: 1301,
        code: 'permission_denied',
        message: 'clipboard access was denied',
      );

      expect(jsonDecode(success.toJsonString()), <String, Object?>{
        'schema_version': 1,
        'contract': 'ianvs-host-response-v1',
        'request_id': 'host:7:3',
        'session_id': '7',
        'operation': 'clipboard.read_text',
        'ok': true,
        'timestamp_micros': 1300,
        'payload': <String, Object?>{'data_base64': 'aGVsbG8='},
      });
      expect(
        jsonDecode(denied.toJsonString()),
        containsPair('error', <String, Object?>{
          'code': 'permission_denied',
          'message': 'clipboard access was denied',
        }),
      );
    });
  });
}

Map<String, Object?> _requestJson() => <String, Object?>{
  'schema_version': 1,
  'contract': 'ianvs-host-request-v1',
  'request_id': 'host:7:3',
  'session_id': '7',
  'operation': 'clipboard.read_text',
  'sequence': 3,
  'timestamp_micros': 1200,
  'payload': <String, Object?>{'selection': 'c'},
};
