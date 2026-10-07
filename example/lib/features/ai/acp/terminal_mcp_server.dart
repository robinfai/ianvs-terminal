import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../ai_api_client.dart';
import '../ai_models.dart';
import 'agent_backend.dart';

/// One authenticated loopback endpoint per task; no host filesystem or shell.
class TerminalMcpServer {
  TerminalMcpServer(this.tools);
  final AgentToolHandler tools;
  HttpServer? _server;
  final String token = base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  String get url => 'http://127.0.0.1:${_server!.port}/mcp';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  static List<Map<String, Object?>> get toolDefinitions => [
    for (final definition in aiTerminalTools)
      () {
        final function = definition['function']! as Map;
        final schema = Map<String, Object?>.from(function['parameters'] as Map);
        if (function['name'] == 'run_command' ||
            function['name'] == 'send_keys') {
          schema['properties'] = {
            ...Map<String, Object?>.from(schema['properties']! as Map),
            'context_version': {
              'type': 'string',
              'description':
                  'Exact context_version from the latest observation.',
            },
            'operation_id': {
              'type': 'string',
              'description':
                  'Unique operation ID. Reuse ONLY for this exact request. Never resubmit an unknown operation under a new ID.',
            },
          };
          schema['required'] = [
            ...schema['required']! as List,
            'context_version',
            'operation_id',
          ];
        }
        return <String, Object?>{
          'name': function['name'],
          'description': function['description'],
          'inputSchema': schema,
        };
      }(),
    {
      'name': 'get_terminal_state',
      'description':
          'Observe the bound terminal, capabilities and context version. The terminal target is independent from the agent host.',
      'inputSchema': {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'inspect_submission',
      'description':
          'Inspect an original operation without sending input. Never retry an unknown submission automatically.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'operation_id': {'type': 'string'},
        },
        'required': ['operation_id'],
        'additionalProperties': false,
      },
    },
  ];

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path != '/mcp' ||
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $token' ||
          request.headers.value('origin') != null) {
        request.response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (request.method != 'POST') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > 128 * 1024) {
          request.response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
      }
      final input = (jsonDecode(utf8.decode(bytes)) as Map)
          .cast<String, Object?>();
      final id = input['id'];
      if (id == null) {
        request.response.statusCode = HttpStatus.accepted;
        return;
      }
      Object? result;
      Map<String, Object?>? error;
      switch (input['method']) {
        case 'initialize':
          result = {
            'protocolVersion': '2025-03-26',
            'capabilities': {'tools': <String, Object?>{}},
            'serverInfo': {'name': 'trail-terminal', 'version': '1.0.0'},
          };
        case 'ping':
          result = <String, Object?>{};
        case 'tools/list':
          result = {'tools': toolDefinitions};
        case 'tools/call':
          final params = (input['params']! as Map).cast<String, Object?>();
          final name = params['name']! as String;
          if (!toolDefinitions.any((t) => t['name'] == name)) {
            error = {'code': -32602, 'message': 'Unknown terminal tool'};
            break;
          }
          try {
            final output = await tools(
              name,
              (params['arguments'] as Map? ?? {}).cast<String, Object?>(),
            );
            result = {
              'content': [
                {'type': 'text', 'text': jsonEncode(output)},
              ],
            };
          } on Object catch (failure) {
            result = {
              'isError': true,
              'content': [
                {
                  'type': 'text',
                  'text': jsonEncode({
                    'error': failure is AiFailure
                        ? failure.code
                        : 'terminal_tool',
                    if (failure is AiInvalidAction) ...{
                      'detail': failure.detail,
                      'submitted': false,
                      'instruction':
                          'The proposal failed validation before any input was sent. Correct the arguments using this detail and the tool schema.',
                    } else
                      'instruction':
                          'Observe the terminal and inspect the original submission. Do not resend uncertain input.',
                  }),
                },
              ],
            };
          }
        default:
          error = {'code': -32601, 'message': 'Method unavailable'};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          if (error == null) 'result': result else 'error': error,
        }),
      );
    } on Object {
      request.response.statusCode = HttpStatus.badRequest;
    } finally {
      try {
        await request.response.close();
      } on Object {
        // Agent cancellation can close a socket while its tool is awaiting UI.
      }
    }
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
  }
}
