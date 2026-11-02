import 'dart:convert';
import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_errors.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_response_stream.dart';
import 'package:app/features/ai/ai_responses.dart';
import 'package:app/features/ai/ai_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Responses preserves tools and full local history', () {
    final payload = toAiResponses({
      'model': 'gpt-6.1-sol',
      'stream': true,
      'tools': aiTerminalTools,
      'parallel_tool_calls': false,
      'messages': [
        {'role': 'system', 'content': 'safe'},
        {
          'role': 'assistant',
          'tool_calls': [
            {
              'id': 'c1',
              'function': {'name': 'read_screen', 'arguments': '{}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'c1', 'content': 'ready'},
      ],
    });
    expect(payload['store'], false);
    expect(payload['parallel_tool_calls'], false);
    final input = payload['input']! as List<Map<String, Object?>>;
    expect(input[1]['type'], 'function_call');
    expect(input[2]['call_id'], 'c1');
    expect(((payload['tools']! as List).first as Map)['strict'], false);
    expect(
      usesOpenAiResponses(
        Uri.parse('https://api.deepseek.com/v1/chat/completions'),
      ),
      false,
    );
  });
  final response = {
    'id': 'r1',
    'model': 'gpt-6.1-sol',
    'status': 'completed',
    'output': [
      {
        'type': 'function_call',
        'call_id': 'c1',
        'name': 'read_screen',
        'arguments': '{"reason":"inspect"}',
      },
    ],
    'usage': {
      'input_tokens': 100,
      'output_tokens': 20,
      'input_tokens_details': {'cached_tokens': 40},
    },
  };
  test('SSE completion releases tools and normalizes usage once', () async {
    final events = [
      {'type': 'response.created'},
      {'type': 'response.output_text.delta', 'delta': '你好'},
      {'type': 'response.completed', 'response': response},
    ];
    final bytes = utf8.encode(
      events.map((e) => 'data: ${jsonEncode(e)}\n\n').join(),
    );
    final result = await readAiResponseStream(
      aiResponsesStream(Stream.fromIterable(bytes.map((b) => [b]))),
      AiCancellation(),
      (_) {},
    );
    final choice = (result['choices']! as List).single as Map;
    final message = choice['message'] as Map;
    expect(message['content'], '你好');
    expect(((message['tool_calls'] as List).single as Map)['id'], 'c1');
    expect((result['usage']! as Map)['prompt_tokens'], 100);
  });
  test('failed and truncated streams never release a tool', () async {
    for (final type in [
      'response.failed',
      'response.incomplete',
      'response.output_item.done',
    ]) {
      final bytes = utf8.encode(
        'data: ${jsonEncode({'type': type, 'response': response})}\n\n',
      );
      await expectLater(
        readAiResponseStream(
          aiResponsesStream(Stream.value(bytes)),
          AiCancellation(),
          (_) {},
        ),
        throwsA(
          isA<AiFailure>().having((e) => e.code, 'code', 'response_incomplete'),
        ),
      );
    }
  });
  test('provider diagnoses never echo secrets', () async {
    final code = await readAiHttpError(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'error': {
              'code': 'ai_provider_quota',
              'message': 'secret-key-user-prompt',
            },
          }),
        ),
      ),
      502,
    );
    expect(code, 'ai_provider_quota');
    expect(aiErrorText(code, true), contains('购买 Trail 额度不能解决'));
    expect(aiErrorText(code, true), isNot(contains('secret')));
    expect(
      await readAiHttpError(
        Stream.value(utf8.encode('<html>secret</html>')),
        502,
      ),
      'ai_upstream_unavailable',
    );
    expect(
      await readAiHttpError(Stream.value([]), 429, quotaExhausted: true),
      'quota_exceeded',
    );
  });
}
