import 'dart:convert';

import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:test/test.dart';

void main() {
  group('PtyRuntimeEnvelope v1', () {
    test('decodes an additive unknown event without losing its payload', () {
      final envelope = PtyRuntimeEnvelope.fromJson(<String, Object?>{
        'schema_version': 1,
        'contract': 'ianvs-runtime-envelope-v1',
        'message_class': 'event',
        'message_name': 'future_event',
        'session_id': '7',
        'sequence': 3,
        'timestamp_micros': 1234,
        'payload': <String, Object?>{'future': true},
        'additive_field': 'ignored',
      });

      expect(envelope.messageClass, PtyRuntimeMessageClass.event);
      expect(envelope.messageName, 'future_event');
      expect(envelope.sessionId, '7');
      expect(envelope.sequence, 3);
      expect(envelope.timestampMicros, 1234);
      expect(envelope.payload, <String, Object?>{'future': true});
    });

    test('keeps the declared message taxonomy closed for schema v1', () {
      expect(
        PtyRuntimeMessageClass.values.map((value) => value.wireName),
        <String>[
          'command',
          'event',
          'frame',
          'asset_transfer',
          'diagnostic',
          'error',
        ],
      );
    });

    test(
      'returns structured errors for unsupported or malformed envelopes',
      () {
        expect(
          () => PtyRuntimeEnvelope.fromJson(<String, Object?>{
            'schema_version': 2,
          }),
          throwsA(
            isA<PtyRuntimeContractException>()
                .having((error) => error.code, 'code', 'unsupported_schema')
                .having((error) => error.path, 'path', r'$.schema_version'),
          ),
        );
        expect(
          () => PtyRuntimeEnvelope.fromJson(<String, Object?>{
            'schema_version': 1,
            'contract': 'ianvs-runtime-envelope-v1',
            'message_class': 'future_class',
            'message_name': 'event',
            'timestamp_micros': 1,
          }),
          throwsA(
            isA<PtyRuntimeContractException>().having(
              (error) => error.code,
              'code',
              'unsupported_message_class',
            ),
          ),
        );
      },
    );
  });

  group('PtyRuntimeEventBatch v1', () {
    test('decodes ordered messages and ignores additive batch fields', () {
      final batch = PtyRuntimeEventBatch.fromJsonString(
        jsonEncode(_batchJson(sequences: <int>[4, 5])..['future'] = true),
      );

      expect(batch.sessionId, '7');
      expect(batch.nextSequence, 6);
      expect(batch.droppedCount, 0);
      expect(batch.messages.map((message) => message.sequence), <int>[4, 5]);
    });

    test('retains an empty loss-only batch', () {
      final batch = PtyRuntimeEventBatch.fromJson(<String, Object?>{
        ..._batchJson(sequences: const <int>[]),
        'next_sequence': 3,
        'dropped_count': 3,
      });

      expect(batch.messages, isEmpty);
      expect(batch.nextSequence, 3);
      expect(batch.droppedCount, 3);
    });

    test('rejects reordered and cross-session event messages', () {
      expect(
        () => PtyRuntimeEventBatch.fromJson(_batchJson(sequences: <int>[2, 1])),
        throwsA(
          isA<PtyRuntimeContractException>().having(
            (error) => error.code,
            'code',
            'event_sequence_reordered',
          ),
        ),
      );

      final crossSession = _batchJson(sequences: <int>[0]);
      final messages = crossSession['messages']! as List<Object?>;
      (messages.single! as Map<String, Object?>)['session_id'] = '8';
      expect(
        () => PtyRuntimeEventBatch.fromJson(crossSession),
        throwsA(
          isA<PtyRuntimeContractException>().having(
            (error) => error.code,
            'code',
            'event_session_mismatch',
          ),
        ),
      );
    });

    test('rejects oversized encoded batches before JSON parsing', () {
      expect(
        () => PtyRuntimeEventBatch.fromJsonString(
          ' ' * (PtyRuntimeEventBatch.maxEncodedBytes + 1),
        ),
        throwsA(
          isA<PtyRuntimeContractException>().having(
            (error) => error.code,
            'code',
            'encoded_batch_too_large',
          ),
        ),
      );
    });
  });
}

Map<String, Object?> _batchJson({required List<int> sequences}) {
  final nextSequence = sequences.isEmpty ? 0 : sequences.last + 1;
  return <String, Object?>{
    'schema_version': 1,
    'contract': 'ianvs-runtime-event-batch-v1',
    'message_class': 'event',
    'session_id': '7',
    'next_sequence': nextSequence,
    'dropped_count': 0,
    'messages': <Object?>[
      for (final sequence in sequences)
        <String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-runtime-envelope-v1',
          'message_class': 'event',
          'message_name': sequence == 0 ? 'started' : 'future_event',
          'session_id': '7',
          'sequence': sequence,
          'timestamp_micros': 1000 + sequence,
          'payload': <String, Object?>{'sequence': sequence},
        },
    ],
  };
}
