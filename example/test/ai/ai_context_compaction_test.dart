import 'dart:convert';
import 'package:app/features/ai/ai_context_compaction.dart';
import 'package:app/features/ai/ai_errors.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'old observations compress without losing goals, tool pairing or receipts',
    () {
      final history = <Map<String, Object?>>[];
      for (var i = 0; i < 20; i++) {
        history.add({
          'role': 'user',
          'content': jsonEncode({
            'request': 'Keep constraint $i',
            'terminal_context': {
              'screen': 'x' * 16000,
              'session_id': 'one',
              'cwd': '/tmp',
            },
            'selected_block': {
              'id': 'block-$i',
              'output': 'x' * 16000,
              'output_start_line': 0,
              'output_end_line': 200,
              'exit_code': 0,
              'command': 'ls $i',
            },
          }),
        });
        history.add({
          'role': 'assistant',
          'content': 'Result $i',
          'tool_calls': [
            {
              'id': 'call-$i',
              'function': {'name': 'run_command', 'arguments': '{}'},
            },
          ],
        });
        history.add({
          'role': 'tool',
          'tool_call_id': 'call-$i',
          'content': jsonEncode({
            'submission_id': 'receipt-$i',
            'accepted': true,
            'terminal_context': {'screen': 'x' * 16000},
          }),
        });
      }
      final before = jsonEncode(history);
      final result = compactAiObservations(history);
      expect(utf8.encode(jsonEncode(result)).length, lessThan(200000));
      expect(jsonEncode(history), before);
      expect(result.length, history.length);
      for (var i = 0; i < 20; i++) {
        expect(jsonEncode(result), contains('Keep constraint $i'));
        expect(jsonEncode(result), contains('receipt-$i'));
        expect(
          result[i * 3 + 2]['tool_call_id'],
          ((result[i * 3 + 1]['tool_calls']! as List).single as Map)['id'],
        );
      }
      expect(result.last, history.last);
      final evidence = suppliedAiEvidence(result, sessionId: 'one');
      expect(evidence.any((r) => r.id == 'block-0'), isFalse);
      expect(evidence.any((r) => r.id == 'block-19'), isTrue);
    },
  );
  test(
    'explicit context rejection can compact a small request more aggressively',
    () {
      final messages = [
        for (var i = 0; i < 10; i++)
          {
            'role': 'user',
            'content': jsonEncode({
              'request': 'constraint $i',
              'terminal_context': {'screen': 'output $i'},
            }),
          },
      ];
      expect(compactAiObservations(messages), messages);
      final compacted = compactAiObservations(messages, force: true);
      expect(jsonEncode(compacted.first), contains('observation_compacted'));
      expect(compacted.last, messages.last);
    },
  );
  test('gateway byte limit is distinct from model context', () async {
    expect(
      aiErrorCode({
        'error': {'code': 'ai_request_too_large'},
      }),
      'ai_request_too_large',
    );
    expect(
      aiErrorCode({
        'error': {'code': 'context_length_exceeded'},
      }),
      'context_too_large',
    );
    expect(
      await readAiHttpError(Stream.value(utf8.encode('too big')), 413),
      'ai_request_too_large',
    );
  });
}
