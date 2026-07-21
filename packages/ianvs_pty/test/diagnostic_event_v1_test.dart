import 'dart:convert';

import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:test/test.dart';

void main() {
  group('PtyDiagnosticEventV1', () {
    test(
      'decodes a diagnostic Runtime Envelope and ignores unknown fields',
      () {
        final event = PtyDiagnosticEventV1.fromJsonString(
          jsonEncode(<String, Object?>{
            'schema_version': 1,
            'contract': 'ianvs-runtime-envelope-v1',
            'message_class': 'diagnostic',
            'message_name': 'frame_stats',
            'session_id': '7',
            'sequence': 12,
            'timestamp_micros': 42,
            'payload': <String, Object?>{'rows_scanned': 8},
            'future_field': true,
          }),
          expectedSessionId: '7',
          expectedName: 'frame_stats',
        );

        expect(event.schemaVersion, 1);
        expect(event.name, 'frame_stats');
        expect(event.sessionId, '7');
        expect(event.sequence, 12);
        expect(event.timestampMicros, 42);
        expect(event.payload, <String, Object?>{'rows_scanned': 8});
      },
    );

    test('rejects non-diagnostic, uncorrelated, or malformed envelopes', () {
      Map<String, Object?> envelope({
        Object? messageClass = 'diagnostic',
        Object? sessionId = '7',
        Object? sequence = 0,
        Object? payload = const <String, Object?>{},
      }) => <String, Object?>{
        'schema_version': 1,
        'contract': 'ianvs-runtime-envelope-v1',
        'message_class': messageClass,
        'message_name': 'session_stats',
        'session_id': sessionId,
        'sequence': sequence,
        'timestamp_micros': 42,
        'payload': payload,
      };

      expect(
        () => PtyDiagnosticEventV1.fromJson(envelope(messageClass: 'event')),
        throwsA(isA<PtyRuntimeContractException>()),
      );
      expect(
        () => PtyDiagnosticEventV1.fromJson(envelope(sessionId: null)),
        throwsA(isA<PtyRuntimeContractException>()),
      );
      expect(
        () => PtyDiagnosticEventV1.fromJson(envelope(sequence: null)),
        throwsA(isA<PtyRuntimeContractException>()),
      );
      expect(
        () => PtyDiagnosticEventV1.fromJson(envelope(payload: <Object?>[])),
        throwsA(isA<PtyRuntimeContractException>()),
      );
      expect(
        () => PtyDiagnosticEventV1.fromJson(envelope(), expectedSessionId: '8'),
        throwsA(isA<PtyRuntimeContractException>()),
      );
    });
  });
}
