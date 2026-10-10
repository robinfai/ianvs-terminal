// Hermetic ACP adapter. The test owns the loopback observer and can hold one
// protocol reply without depending on a clock, a real adapter, or credentials.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  final observer = Uri.parse(arguments.single);
  final client = HttpClient();
  var model = 'fixture-model';
  const session = 'fixture-session';

  void send(Map<String, Object?> value) =>
      stdout.writeln(jsonEncode({'jsonrpc': '2.0', ...value}));

  Future<void> receive(String line) async {
    final input = (jsonDecode(line) as Map).cast<String, Object?>();
    final method = input['method'];
    final id = input['id'];
    if (method is! String || id == null) return;
    final params = (input['params']! as Map).cast<String, Object?>();
    final request = await client.postUrl(observer);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'method': method, 'params': params, 'pid': pid}));
    final response = await request.close();
    await response.drain<void>();
    final Map<String, Object?> result;
    switch (method) {
      case 'initialize':
        result = {
          'protocolVersion': 1,
          'agentInfo': {
            'name': '@agentclientprotocol/codex-acp',
            'fixture_pid': pid,
          },
          'agentCapabilities': {
            'mcpCapabilities': {'http': true},
          },
        };
      case 'session/new':
      case 'session/load':
        result = {
          'sessionId': session,
          'configOptions': [
            {'id': 'model', 'category': 'model', 'currentValue': model},
          ],
        };
      case 'session/set_config_option':
        model = params['value']! as String;
        result = {
          'configOptions': [
            {'id': 'model', 'currentValue': model},
          ],
        };
      case 'session/prompt':
        send({
          'method': 'session/update',
          'params': {
            'sessionId': session,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {
                'type': 'text',
                'text': 'Latest requirement received.',
              },
            },
          },
        });
        result = {
          'stopReason': 'end_turn',
          '_meta': {
            'quota': {
              'model_usage': [
                {'model': model},
              ],
            },
          },
        };
      default:
        result = {};
    }
    send({'id': id, 'result': result});
  }

  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) => unawaited(receive(line).catchError((Object _) {})),
        onDone: () {
          // Cancellation closes stdin even while a held observer request remains.
          client.close(force: true);
          exit(0);
        },
      );
}
