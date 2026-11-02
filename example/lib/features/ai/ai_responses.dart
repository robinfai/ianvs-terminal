import 'dart:convert';

import 'ai_models.dart';

/// Official OpenAI tool calling uses Responses. Third-party compatible servers
/// and the Trail gateway continue to expose their Chat Completions contract.
bool usesOpenAiResponses(Uri uri) => uri.host == 'api.openai.com';

Map<String, Object?> toAiResponses(Map<String, Object?> chat) {
  final input = <Map<String, Object?>>[];
  for (final raw in chat['messages']! as List) {
    final message = raw as Map;
    if (message['role'] == 'tool') {
      input.add({
        'type': 'function_call_output',
        'call_id': message['tool_call_id'],
        'output': message['content'],
      });
      continue;
    }
    final content = message['content'];
    if (content != null && content != '') {
      input.add({'role': message['role'], 'content': content});
    }
    for (final rawCall in message['tool_calls'] as List? ?? const []) {
      final call = rawCall as Map;
      final function = call['function'] as Map;
      input.add({
        'type': 'function_call',
        'call_id': call['id'],
        'name': function['name'],
        'arguments': function['arguments'],
      });
    }
  }
  return {
    'model': chat['model'],
    'input': input,
    'stream': chat['stream'],
    'store': false,
    if (chat['reasoning_effort'] != null)
      'reasoning': {'effort': chat['reasoning_effort']},
    if (chat['tools'] case final List<Object?> tools)
      'tools': [
        for (final tool in tools)
          {
            ...(tool! as Map)['function'] as Map,
            'type': 'function',
            'strict': false,
          },
      ],
    if (chat.containsKey('tool_choice')) 'tool_choice': chat['tool_choice'],
    if (chat.containsKey('parallel_tool_calls'))
      'parallel_tool_calls': chat['parallel_tool_calls'],
  };
}

Map<String, Object?> fromAiResponse(Map<String, Object?> response) {
  if (response['status'] != 'completed') {
    throw const AiFailure('response_incomplete');
  }
  final text = StringBuffer();
  final calls = <Map<String, Object?>>[];
  for (final raw in response['output']! as List) {
    final item = raw as Map;
    if (item['type'] == 'message') {
      for (final rawPart in item['content'] as List) {
        final part = rawPart as Map;
        if (part['type'] == 'output_text') text.write(part['text']);
      }
    } else if (item['type'] == 'function_call') {
      calls.add({
        'index': calls.length,
        'id': item['call_id'],
        'type': 'function',
        'function': {'name': item['name'], 'arguments': item['arguments']},
      });
    }
  }
  final usage = response['usage'] as Map?;
  return {
    'id': response['id'],
    'model': response['model'],
    'choices': [
      {
        'index': 0,
        'message': {
          'role': 'assistant',
          'content': text.toString(),
          if (calls.isNotEmpty) 'tool_calls': calls,
        },
        'finish_reason': calls.isEmpty ? 'stop' : 'tool_calls',
      },
    ],
    if (usage != null)
      'usage': {
        'prompt_tokens': usage['input_tokens'],
        'completion_tokens': usage['output_tokens'],
        'prompt_tokens_details': usage['input_tokens_details'],
      },
  };
}

/// Release tool proposals only after the provider's completed event. Never
/// synthesize successful completion after a disconnect, failure or truncation.
Stream<List<int>> aiResponsesStream(Stream<List<int>> source) async* {
  var size = 0;
  final lines = <String>[];
  final bounded = source.map((chunk) {
    size += chunk.length;
    if (size > 1024 * 1024) throw const AiFailure('response_too_large');
    return chunk;
  });
  await for (final line
      in bounded.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.startsWith('data:')) {
      lines.add(line.substring(5).trimLeft());
      continue;
    }
    if (line.isNotEmpty || lines.isEmpty) continue;
    final event = jsonDecode(lines.join('\n')) as Map;
    lines.clear();
    Map<String, Object?> chunk = {'choices': <Object>[]};
    switch (event['type']) {
      case 'response.output_text.delta':
        chunk = {
          'choices': [
            {
              'index': 0,
              'delta': {'content': event['delta']},
            },
          ],
        };
      case 'response.completed':
        final data = fromAiResponse(
          (event['response'] as Map).cast<String, Object?>(),
        );
        final choice = (data['choices']! as List).single as Map;
        final delta = Map<String, Object?>.from(choice['message'] as Map)
          ..remove('content');
        chunk = {
          ...data,
          'choices': [
            {
              'index': 0,
              'delta': delta,
              'finish_reason': choice['finish_reason'],
            },
          ],
        };
        yield utf8.encode('data: ${jsonEncode(chunk)}\n\ndata: [DONE]\n\n');
        return;
      case 'response.failed':
      case 'response.incomplete':
      case 'error':
        throw const AiFailure('response_incomplete');
    }
    // Empty chunks keep the existing timeout active during reasoning, without
    // exposing private reasoning or partially generated tool arguments.
    yield utf8.encode('data: ${jsonEncode(chunk)}\n\n');
  }
  throw const AiFailure('response_incomplete');
}
