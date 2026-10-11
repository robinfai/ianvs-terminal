import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_chat_stream.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

String event(Map<String, Object?> delta, {String? finish, String id = 'r1'}) =>
    'data: ${jsonEncode({'id': id, 'model': 'test', 'choices': [
      {'index': 0, 'delta': delta, 'finish_reason': finish}
    ]})}\r\n\r\n';
Stream<List<int>> fragmented(String value) => Stream.fromIterable(
    utf8.encode(value).map((byte) => [byte]));
Map<String, Object?> tool(String arguments, {bool first = false, int index = 0}) => {
  'tool_calls': [{'index': index, if (first) 'id': 'call-1',
    if (first) 'type': 'function', 'function': {
      if (first) 'name': 'run_command', 'arguments': arguments,
    }}],
};

void main() {
  test('stream decodes UTF-8 split bytes, comments, BOM and real text deltas', () async {
    final updates = <AiStreamUpdate>[];
    final reply = await decodeAiChatStream(fragmented('\uFEFF: hello\r\n\r\n'
        '${event({'role': 'assistant'})}'
        '${event({'content': '你好'})}${event({'content': ' 🧭'})}'
        '${event({}, finish: 'stop')}data: [DONE]\r\n\r\n'),
        AiCancellation(), updates.add);
    expect(reply.text, '你好 🧭');
    expect(updates.map((e) => e.textDelta).join(), reply.text);
    expect(reply.action, isNull);
  });

  test('tool arguments are assembled but never returned before full completion', () async {
    final input = StreamController<List<int>>();
    final updates = <AiStreamUpdate>[];
    var finished = false;
    final reply = decodeAiChatStream(input.stream, AiCancellation(), updates.add)
        .then((value) { finished = true; return value; });
    input.add(utf8.encode(event(tool('{"command":"p', first: true))));
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(updates.single.stage, AiStreamStage.receivingTool);
    input.add(utf8.encode(event(tool('wd","reason":"Inspect"}'), finish: 'tool_calls')));
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    input.add(utf8.encode('data: [DONE]\n\n'));
    final result = await reply;
    expect(result.action?.command, 'pwd');
    await input.close();
  });

  test('SSE multiline data and CR line endings follow the event framing', () async {
    final raw = 'data: {"id":"r1",\r'
        'data: "choices":[{"index":0,"delta":{"content":"ok"},"finish_reason":"stop"}]}\r\r'
        'data: [DONE]\r\r';
    final reply = await decodeAiChatStream(fragmented(raw), AiCancellation(), (_) {});
    expect(reply.text, 'ok');
  });

  for (final tail in ['', 'data: [DONE]\n', event({}, finish: 'length')]) {
    test('unfinished stream is not a successful response: ${tail.length}', () async {
      await expectLater(decodeAiChatStream(fragmented(
          '${event({'content': 'partial'})}$tail'), AiCancellation(), (_) {}),
          throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'stream_incomplete')));
    });
  }
  test('finish alone without DONE does not authorize a tool', () async {
    await expectLater(decodeAiChatStream(fragmented(event(
        tool('{"command":"pwd","reason":"Inspect"}', first: true),
        finish: 'tool_calls')), AiCancellation(), (_) {}), throwsA(isA<AiFailure>()));
  });
  test('second indexed tool and changed response identity are rejected', () async {
    await expectLater(decodeAiChatStream(fragmented(event(
        tool('{}', first: true, index: 1))), AiCancellation(), (_) {}),
        throwsA(isA<AiInvalidAction>()));
    await expectLater(decodeAiChatStream(fragmented('${event({'content':'a'})}'
        '${event({'content':'b'}, id:'r2')}'), AiCancellation(), (_) {}),
        throwsA(isA<AiFailure>()));
  });
  test('review-only stream cannot receive tools', () async {
    await expectLater(decodeAiChatStream(fragmented(event(tool('{}', first:true))),
        AiCancellation(), (_) {}, toolsEnabled: false),
        throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'review_tool_call')));
  });
  test('cancellation rejects delayed chunks without producing a reply', () async {
    final cancel = AiCancellation()..cancel();
    await expectLater(decodeAiChatStream(fragmented(event({'content':'late'})),
        cancel, (_) => fail('cancelled delta delivered')),
        throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'cancelled')));
  });
  test('wire byte budget bounds even an unterminated SSE line', () async {
    await expectLater(decodeAiChatStream(Stream.value(List.filled(4*1024*1024+1, 65)),
        AiCancellation(), (_) {}), throwsA(isA<AiFailure>()));
  });

  test('HTTP uses stream:true, yields before EOF and keeps exact UTF-8 request length', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force:true));
    final release = Completer<void>();
    final receivedText = Completer<void>();
    final handled = server.first.then((request) async {
      final length = request.contentLength;
      final bytes = await request.expand((chunk) => chunk).toList();
      expect(bytes.length, length);
      final body = jsonDecode(utf8.decode(bytes)) as Map;
      expect(body['stream'], isTrue);
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.bufferOutput = false;
      request.response.write(event({'content':'先到'}));
      await request.response.flush();
      await release.future;
      request.response.write('${event({'content':'后到'})}${event({}, finish:'stop')}data: [DONE]\n\n');
      await request.response.close();
    });
    final future = const AiApiClient().completeStreaming(AiConfiguration(
        endpoint:'http://127.0.0.1:${server.port}/v1',apiKey:'synthetic',model:'test'),
        [{'role':'user','content':'中文'}], AiCancellation(), onUpdate:(update) {
      if (update.textDelta == '先到' && !receivedText.isCompleted) receivedText.complete();
    });
    await receivedText.future.timeout(const Duration(seconds:3));
    release.complete();
    expect((await future).text, '先到后到');
    await handled;
  });

  test('JSON gateway response is handled once without a second POST', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force:true));
    var requests = 0;
    final subscription = server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'choices':[{'message':{'content':'buffered'}}]}));
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final reply = await const AiApiClient().completeStreaming(AiConfiguration(
        endpoint:'http://127.0.0.1:${server.port}/v1',apiKey:'synthetic',model:'test'),
        [],AiCancellation(),onUpdate:(_){});
    expect(reply.text,'buffered');
    expect(requests,1);
  });
}
