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
  final activePrompts = <Object>{};
  final cancelledPrompts = <Object>{};
  final permissions = <String, Completer<Map<String, Object?>>>{};
  Map<String, Object?>? bridge;

  Future<Map<String, Object?>> tool(
    String name,
    Map<String, Object?> args,
  ) async {
    final request = await client.postUrl(Uri.parse(bridge!['url']! as String));
    for (final header
        in (bridge!['headers']! as List).cast<Map<String, Object?>>()) {
      request.headers.set(
        header['name']! as String,
        header['value']! as String,
      );
    }
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': name, 'arguments': args},
      }),
    );
    final response = await request.close();
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    final result = body['result'] as Map;
    final content = (result['content'] as List).first as Map;
    return (jsonDecode(content['text'] as String) as Map)
        .cast<String, Object?>();
  }

  Map<String, Object?> modelOption() => {
    'id': 'model',
    'name': 'Model',
    'category': 'model',
    'type': 'select',
    'currentValue': model,
    'options': [
      {'value': model, 'name': model},
    ],
  };

  void send(Map<String, Object?> value) =>
      stdout.writeln(jsonEncode({'jsonrpc': '2.0', ...value}));

  Future<void> receive(String line) async {
    final input = (jsonDecode(line) as Map).cast<String, Object?>();
    final method = input['method'];
    final id = input['id'];
    if (method == null && permissions.containsKey(id)) {
      permissions
          .remove(id)!
          .complete((input['result']! as Map).cast<String, Object?>());
      return;
    }
    if (method == 'session/cancel') {
      for (final prompt in activePrompts.toList()) {
        cancelledPrompts.add(prompt);
        send({
          'id': prompt,
          'result': {'stopReason': 'cancelled'},
        });
      }
      activePrompts.clear();
      return;
    }
    if (method is! String || id == null) return;
    if (method == 'session/prompt') activePrompts.add(id);
    final params = (input['params']! as Map).cast<String, Object?>();
    final request = await client.postUrl(observer);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'method': method,
        'params': params,
        'pid': pid,
        if (method == 'initialize') ...{
          'hostOnlyLeaked': Platform.environment.containsKey(
            'TRAIL_ACP_HOST_ONLY',
          ),
          'isolatedHome':
              Platform.environment['CODEX_HOME']?.contains('trail-acp-') ==
              true,
          'profile': jsonDecode(Platform.environment['CODEX_CONFIG']!),
          'authMode':
              File(
                '${Platform.environment['CODEX_HOME']}/auth.json',
              ).statSync().mode &
              511,
        },
      }),
    );
    final response = await request.close();
    await response.drain<void>();
    if (cancelledPrompts.contains(id)) return;
    final Map<String, Object?> result;
    switch (method) {
      case 'initialize':
        result = {
          'protocolVersion': 1,
          'agentInfo': {
            'name': '@agentclientprotocol/codex-acp',
            'version': '1.0.0',
            'fixture_pid': pid,
          },
          'agentCapabilities': {
            'loadSession': true,
            'mcpCapabilities': {'http': true},
          },
        };
      case 'session/new':
      case 'session/load':
        bridge = ((params['mcpServers']! as List).firstOrNull as Map?)
            ?.cast<String, Object?>();
        result = {
          'sessionId': session,
          'configOptions': [modelOption()],
        };
      case 'session/set_config_option':
        model = params['value']! as String;
        result = {
          'configOptions': [modelOption()],
        };
      case 'session/prompt':
        if (jsonEncode(
          params['prompt'],
        ).contains('sparse-permission-fixture')) {
          final observation = await tool('get_terminal_state', {});
          final args = <String, Object?>{
            'command': 'ls',
            'reason': 'Inspect files',
            'operation_id': 'sparse-operation',
            'context_version': observation['context_version'],
          };
          send({
            'method': 'session/update',
            'params': {
              'sessionId': session,
              'update': {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'sparse-call',
                'kind': 'execute',
                'status': 'pending',
                'title': 'mcp.trail_terminal.run_command',
                'rawInput': {
                  'server': 'trail_terminal',
                  'tool': 'run_command',
                  'arguments': args,
                },
              },
            },
          });
          final permission = Completer<Map<String, Object?>>();
          permissions['sparse-permission'] = permission;
          // Codex ACP 2.1.1 ElicitationReporter omits rawInput/title when the
          // permission can be correlated to the preceding MCP tool call.
          send({
            'id': 'sparse-permission',
            'method': 'session/request_permission',
            'params': {
              'sessionId': session,
              'toolCall': {
                'toolCallId': 'sparse-call',
                'kind': 'execute',
                'status': 'pending',
              },
              'options': [
                {
                  'optionId': 'allow',
                  'name': 'Allow once',
                  'kind': 'allow_once',
                },
                {'optionId': 'reject', 'name': 'Reject', 'kind': 'reject_once'},
              ],
            },
          });
          final decision = await permission.future;
          if ((decision['outcome'] as Map?)?['optionId'] == 'allow') {
            await tool('run_command', args);
          }
        }
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
    activePrompts.remove(id);
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
