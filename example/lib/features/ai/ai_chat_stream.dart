import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_models.dart';

/// Transport progress, not an executable proposal. Tool fragments never leave
/// the decoder until both finish_reason and the terminal SSE marker validate.
enum AiStreamStage { waiting, receivingText, receivingTool }

class AiStreamUpdate {
  const AiStreamUpdate(this.stage, {this.textDelta = ''});
  final AiStreamStage stage;
  final String textDelta;
}

typedef AiStreamListener = void Function(AiStreamUpdate update);

const _maxResponseBytes = 4 * 1024 * 1024;
const _maxEventCharacters = 256 * 1024;
const _maxTextCharacters = 1024 * 1024;
const _maxArgumentCharacters = 64 * 1024;

/// One POST, no redirect and no transparent retry. Gateways which ignore stream
/// and answer application/json are consumed once, never requested a second time.
Future<AiReply> requestAiChatStream({
  required AiConfiguration configuration,
  required List<Map<String, Object?>> messages,
  required AiCancellation cancellation,
  required AiStreamListener onUpdate,
  required List<Map<String, Object?>> tools,
  required bool toolsEnabled,
  required Duration timeout,
  required Duration totalTimeout,
  String? reasoningEffort,
}) async {
  cancellation.check();
  final client = HttpClient()..connectionTimeout = timeout;
  var finished = false;
  cancellation.onCancel(() {
    if (!finished) client.close(force: true);
  });
  try {
    return await (() async {
      final request = await client.postUrl(configuration.completionsUri)
          .timeout(timeout);
      cancellation.check();
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader,
          'text/event-stream, application/json');
      request.headers.set(HttpHeaders.authorizationHeader,
          'Bearer ${configuration.apiKey.trim()}');
      final payload = utf8.encode(jsonEncode({
        'model': configuration.model.trim(),
        'messages': messages,
        if (toolsEnabled) ...{
          'tools': tools,
          'tool_choice': 'auto',
          'parallel_tool_calls': false,
        },
        'stream': true,
        if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
      }));
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close().timeout(timeout);
      cancellation.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiFailure(switch (response.statusCode) {
          401 || 403 => 'authentication',
          429 => 'rate_limit',
          _ => 'http_${response.statusCode}',
        });
      }
      onUpdate(const AiStreamUpdate(AiStreamStage.waiting));
      final mime = response.headers.contentType?.mimeType;
      final bytes = _boundedBytes(response.timeout(timeout), cancellation);
      if (mime == 'application/json') {
        final body = await bytes.expand((chunk) => chunk).toList();
        cancellation.check();
        final reply = decodeAiChatReply(
          (jsonDecode(utf8.decode(body)) as Map).cast<String, Object?>(),
          toolsEnabled: toolsEnabled,
        );
        // Buffered compatibility is not simulated typing.
        if (reply.text.isNotEmpty) {
          onUpdate(AiStreamUpdate(AiStreamStage.receivingText,
              textDelta: reply.text));
        }
        return reply;
      }
      if (mime != 'text/event-stream') {
        throw const AiFailure('response_format');
      }
      return decodeAiChatStream(bytes, cancellation, onUpdate,
          toolsEnabled: toolsEnabled, alreadyBounded: true);
    })().timeout(totalTimeout);
  } on Object catch (failure) {
    // Cancellation wins over whichever socket/decoder/timeout noticed first.
    cancellation.check();
    if (failure is AiFailure) rethrow;
    if (failure is TimeoutException) throw const AiFailure('timeout');
    if (failure is SocketException || failure is HttpException) {
      throw const AiFailure('connection');
    }
    throw const AiFailure('response_format');
  } finally {
    finished = true;
    client.close(force: true);
  }
}

Stream<List<int>> _boundedBytes(
    Stream<List<int>> source, AiCancellation cancellation) async* {
  var size = 0;
  await for (final chunk in source) {
    cancellation.check();
    size += chunk.length;
    if (size > _maxResponseBytes) throw const AiFailure('response_too_large');
    yield chunk;
  }
}

/// WHATWG line framing (LF/CRLF/CR), UTF-8 chunk boundaries, BOM, comments and
/// multi-line data fields. An unterminated event at EOF is not a completion.
Future<AiReply> decodeAiChatStream(
  Stream<List<int>> source,
  AiCancellation cancellation,
  AiStreamListener onUpdate, {
  bool toolsEnabled = true,
  bool alreadyBounded = false,
}) async {
  final bytes = alreadyBounded ? source : _boundedBytes(source, cancellation);
  final accumulator = _ChatAccumulator(toolsEnabled, onUpdate);
  final data = <String>[];
  var eventSize = 0;
  var first = true;
  var eventType = '';
  await for (var line in bytes.transform(utf8.decoder)
      .transform(const LineSplitter())) {
    cancellation.check();
    if (first) {
      first = false;
      if (line.startsWith('\uFEFF')) line = line.substring(1);
    }
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        final payload = data.join('\n');
        data.clear();
        eventSize = 0;
        if (eventType == 'error') throw const AiFailure('stream_error');
        if (payload.trim() == '[DONE]') {
          cancellation.check();
          return accumulator.finish();
        }
        if (payload.trim().isNotEmpty) accumulator.add(payload);
      }
      eventType = '';
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') eventType = value;
    if (field == 'data') {
      eventSize += value.length + 1;
      if (eventSize > _maxEventCharacters) {
        throw const AiFailure('response_too_large');
      }
      data.add(value);
    }
  }
  cancellation.check();
  throw const AiFailure('stream_incomplete');
}

class _ChatAccumulator {
  _ChatAccumulator(this.toolsEnabled, this.onUpdate);
  final bool toolsEnabled;
  final AiStreamListener onUpdate;
  final _text = StringBuffer();
  final _arguments = StringBuffer();
  final _name = StringBuffer();
  String? _id;
  String? _model;
  String? _callId;
  String? _finishReason;
  Map<String, Object?>? _usage;
  var _hasTool = false;

  void add(String raw) {
    final data = (jsonDecode(raw) as Map).cast<String, Object?>();
    if (data['error'] != null) throw const AiFailure('stream_error');
    for (final field in ['id', 'model']) {
      final value = data[field];
      if (value != null && value is! String) {
        throw const AiFailure('response_format');
      }
      final previous = field == 'id' ? _id : _model;
      if (value != null && previous != null && value != previous) {
        throw const AiFailure('response_format');
      }
      if (field == 'id') _id ??= value as String?;
      if (field == 'model') _model ??= value as String?;
    }
    if (data['usage'] case final Map usage) {
      _usage = usage.cast<String, Object?>();
    }
    final choices = data['choices'];
    if (choices is! List || choices.length > 1) {
      throw const AiFailure('response_format');
    }
    if (choices.isEmpty) return; // Optional usage-only final event.
    final choice = (choices.single as Map).cast<String, Object?>();
    if (choice['index'] != 0) throw const AiFailure('response_format');
    final delta = (choice['delta'] as Map).cast<String, Object?>();
    if (_finishReason != null) throw const AiFailure('response_format');
    if (delta['role'] != null && delta['role'] != 'assistant' ||
        delta['function_call'] != null) {
      throw const AiFailure('response_format');
    }
    final content = delta['content'];
    if (content != null && content is! String) {
      throw const AiFailure('response_format');
    }
    if (content is String && content.isNotEmpty) {
      if (_text.length + content.length > _maxTextCharacters) {
        throw const AiFailure('response_too_large');
      }
      _text.write(content);
      onUpdate(AiStreamUpdate(AiStreamStage.receivingText, textDelta: content));
    }
    final calls = delta['tool_calls'];
    if (calls != null) {
      if (calls is! List || calls.length > 1) {
        throw const AiInvalidAction('Return exactly one tool call per response.');
      }
      for (final rawCall in calls) {
        if (!toolsEnabled) throw const AiFailure('review_tool_call');
        final call = (rawCall as Map).cast<String, Object?>();
        if (call['index'] != 0 ||
            call['type'] != null && call['type'] != 'function') {
          throw const AiInvalidAction('Only one indexed function call is supported.');
        }
        _hasTool = true;
        if (call['id'] case final Object id) {
          if (id is! String || id.isEmpty ||
              (_callId != null && _callId != id)) {
            throw const AiFailure('response_format');
          }
          _callId = id;
        }
        if (call['function'] case final Object function) {
          final fields = (function as Map).cast<String, Object?>();
          for (final field in ['name', 'arguments']) {
            final value = fields[field];
            if (value != null && value is! String) {
              throw const AiFailure('response_format');
            }
            if (value is String) {
              final buffer = field == 'name' ? _name : _arguments;
              buffer.write(value);
              if (buffer.length > (field == 'name' ? 128 : _maxArgumentCharacters)) {
                throw const AiFailure('response_too_large');
              }
            }
          }
        }
        onUpdate(const AiStreamUpdate(AiStreamStage.receivingTool));
      }
    }
    final reason = choice['finish_reason'];
    if (reason != null) {
      if (reason != 'stop' && reason != 'tool_calls') {
        throw const AiFailure('stream_incomplete');
      }
      _finishReason = reason as String;
    }
  }

  AiReply finish() {
    if (_finishReason == null ||
        (_hasTool ? _finishReason != 'tool_calls' : _finishReason != 'stop')) {
      throw const AiFailure('stream_incomplete');
    }
    return decodeAiChatReply({
      'id': _id,
      'model': _model,
      'usage': _usage,
      'choices': [
        {'message': {
          'role': 'assistant',
          'content': _text.toString(),
          if (_hasTool) 'tool_calls': [
            {'id': _callId, 'type': 'function', 'function': {
              'name': _name.toString(), 'arguments': _arguments.toString(),
            }},
          ],
        }},
      ],
    }, toolsEnabled: toolsEnabled);
  }
}

AiReply decodeAiChatReply(Map<String, Object?> data, {required bool toolsEnabled}) {
  final choices = data['choices'] as List;
  if (choices.length != 1) throw const AiFailure('response_format');
  final choice = choices.single as Map;
  final finish = choice['finish_reason'];
  if (finish != null && finish != 'stop' && finish != 'tool_calls') {
    throw const AiFailure('stream_incomplete');
  }
  final message = (choice['message'] as Map).cast<String, Object?>();
  final content = message['content'];
  if (content != null && content is! String) {
    throw const AiFailure('response_format');
  }
  final calls = message['tool_calls'];
  if (!toolsEnabled && calls is List && calls.isNotEmpty) {
    throw const AiFailure('review_tool_call');
  }
  final AiAction? action;
  try {
    if (calls != null && (calls is! List || calls.length > 1)) {
      throw const AiInvalidAction('Return exactly one tool call per response.');
    }
    action = calls is List && calls.isNotEmpty
        ? AiAction.fromToolCall((calls.single as Map).cast<String, Object?>())
        : null;
  } on AiInvalidAction catch (failure) {
    throw AiInvalidAction(failure.detail, responseMessage: message,
        responseModel: data['model'] as String?, requestId: data['id'] as String?,
        usage: (data['usage'] as Map?)?.cast<String, Object?>());
  }
  if ((content == null || (content as String).trim().isEmpty) && action == null) {
    throw const AiFailure('empty_response');
  }
  return AiReply(text: content as String? ?? '', action: action,
      responseModel: data['model'] as String?, requestId: data['id'] as String?,
      usage: (data['usage'] as Map?)?.cast<String, Object?>());
}
