import 'dart:convert';

import 'ai_models.dart';

enum AiResponseStage { waitingForFirstToken, generating }

/// Text is presentation-only until the entire response has been validated.
class AiResponseUpdate {
  const AiResponseUpdate(this.stage, {this.textDelta = ''});

  final AiResponseStage stage;
  final String textDelta;
}

/// Decodes SSE events independently of HTTP, UTF-8 and line chunk boundaries.
/// A tool is never returned until both finish_reason and the `[DONE]` sentinel were received.
Future<Map<String, Object?>> readAiResponseStream(
  Stream<List<int>> bytes,
  AiCancellation cancellation,
  void Function(AiResponseUpdate) onUpdate,
) async {
  var byteCount = 0;
  final content = StringBuffer();
  final callId = StringBuffer();
  final name = StringBuffer();
  final arguments = StringBuffer();
  final dataLines = <String>[];
  String? finishReason;
  String? responseId;
  String? model;
  Map<String, Object?>? usage;
  var hasTool = false;
  var done = false;

  void consumeEvent() {
    if (dataLines.isEmpty) return;
    final data = dataLines.join('\n');
    dataLines.clear();
    if (data == '[DONE]') {
      if (finishReason == null) throw const AiFailure('response_incomplete');
      done = true;
      return;
    }
    final event = jsonDecode(data) as Map<String, Object?>;
    if (event['error'] != null) throw const AiFailure('response_stream');
    responseId = event['id'] as String? ?? responseId;
    model = event['model'] as String? ?? model;
    usage = (event['usage'] as Map?)?.cast<String, Object?>() ?? usage;
    final choices = event['choices']! as List<Object?>;
    if (choices.isEmpty) return; // A final usage-only event is valid.
    if (choices.length != 1) throw const AiFailure('response_format');
    final choice = choices.single! as Map<String, Object?>;
    if (choice['index'] != 0) throw const AiFailure('response_format');
    final delta = choice['delta']! as Map<String, Object?>;
    final text = delta['content'] as String? ?? '';
    final reasoning = delta['reasoning_content'] as String? ?? '';
    final calls = delta['tool_calls'] as List<Object?>? ?? const [];
    if (finishReason != null &&
        (text.isNotEmpty || reasoning.isNotEmpty || calls.isNotEmpty)) {
      throw const AiFailure('response_format');
    }
    content.write(text);
    for (final rawCall in calls) {
      final call = rawCall! as Map<String, Object?>;
      if (call['index'] != 0 ||
          (call['type'] != null && call['type'] != 'function')) {
        throw const AiFailure('response_format');
      }
      hasTool = true;
      callId.write(call['id'] as String? ?? '');
      final function = call['function'] as Map<String, Object?>?;
      name.write(function?['name'] as String? ?? '');
      arguments.write(function?['arguments'] as String? ?? '');
    }
    if (text.isNotEmpty || reasoning.isNotEmpty || calls.isNotEmpty) {
      cancellation.check();
      onUpdate(AiResponseUpdate(AiResponseStage.generating, textDelta: text));
    }
    if (choice['finish_reason'] case final String reason) {
      if (finishReason != null ||
          (reason != 'stop' && reason != 'tool_calls') ||
          (hasTool != (reason == 'tool_calls'))) {
        throw const AiFailure('response_incomplete');
      }
      finishReason = reason;
    }
  }

  final lines = bytes
      .map((chunk) {
        cancellation.check();
        byteCount += chunk.length;
        if (byteCount > 1024 * 1024) {
          throw const AiFailure('response_too_large');
        }
        return chunk;
      })
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (final line in lines) {
    cancellation.check();
    if (line.isEmpty) {
      consumeEvent();
      if (done) break;
    } else if (line.startsWith('data:')) {
      final value = line.substring(5);
      dataLines.add(value.startsWith(' ') ? value.substring(1) : value);
    }
  }
  cancellation.check();
  if (!done) throw const AiFailure('response_incomplete');
  return {
    'id': responseId,
    'model': model,
    'usage': usage,
    'choices': [
      {
        'message': {
          'role': 'assistant',
          'content': content.toString(),
          if (hasTool)
            'tool_calls': [
              {
                'id': callId.toString(),
                'type': 'function',
                'function': {
                  'name': name.toString(),
                  'arguments': arguments.toString(),
                },
              },
            ],
        },
      },
    ],
  };
}
