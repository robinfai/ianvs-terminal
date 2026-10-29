import 'package:app/features/ai/acp/bridge_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BridgePermissions permissions;
  setUp(() => permissions = BridgePermissions());

  Map<String, Object?> request({
    String session = 'current',
    String server = 'trail_terminal',
    String tool = 'run_command',
    String id = 'permission-1',
  }) => {
    'requestId': id,
    'sessionId': session,
    'toolCallId': 'call',
    'rawInput': {'server': server, 'tool': tool},
    'options': [
      {'kind': 'allow_always', 'optionId': 'always'},
      {'kind': 'allow_once', 'optionId': 'once'},
    ],
  };

  String? choose(Map<String, Object?> value, {bool active = true}) =>
      permissions.option(value, session: 'current', active: active);

  void observe({
    String session = 'current',
    String server = 'trail_terminal',
    String status = 'pending',
  }) => permissions.observeTool({
    'sessionId': session,
    'kind': 'tool_call',
    'metadata': {
      'toolCallId': 'call',
      'status': status,
      'rawInput': {'server': server, 'tool': 'run_command'},
    },
  });

  Map<String, Object?> sparse() => request()
    ..remove('rawInput')
    ..['toolKind'] = 'execute';

  test(
    'Codex 2.1.1 sparse permission correlates preceding MCP tool identity',
    () {
      observe();
      permissions.observeTool({
        'sessionId': 'current',
        'kind': 'tool_call',
        'metadata': {'toolCallId': 'call', 'status': 'in_progress'},
      });
      expect(choose(sparse()), 'once');
      expect(choose(sparse()), isNull);
    },
  );

  test('sparse permission needs a live same-session call and execute kind', () {
    expect(choose(sparse()), isNull);
    observe(session: 'other');
    expect(choose(sparse()), isNull);
    observe();
    expect(choose(sparse()..['toolKind'] = 'other'), isNull);
    expect(choose(sparse(), active: false), isNull);
    observe(status: 'completed');
    expect(choose(sparse()), isNull);
    observe();
    permissions.clear();
    expect(choose(sparse()), isNull);
  });

  test(
    'explicit conflicting or malformed input cannot use cached bridge identity',
    () {
      observe();
      expect(choose(request(server: 'host')), isNull);
      expect(choose(request()..['rawInput'] = 'trail_terminal'), isNull);
      observe(server: 'host');
      expect(choose(sparse()), isNull);
    },
  );

  test(
    'control request grants only offered once option without render events',
    () {
      expect(choose(request()), 'once');
      expect(choose(request()), isNull);
    },
  );

  test(
    'rejects other sessions, host tools, unknown tools and inactive turns',
    () {
      expect(choose(request(session: 'other')), isNull);
      expect(choose(request(server: 'host')), isNull);
      expect(choose(request(tool: 'shell')), isNull);
      expect(choose(request(), active: false), isNull);
      expect(choose(request()), 'once');
    },
  );

  test('requires control identity and never selects permanent permission', () {
    expect(choose(request()..remove('requestId')), isNull);
    expect(choose(request()..remove('toolCallId')), isNull);
    final permanentOnly = request()
      ..['options'] = [
        {'kind': 'allow_always', 'optionId': 'always'},
      ];
    expect(choose(permanentOnly), isNull);
  });

  test('new connection may reuse identity after old turn is closed', () {
    expect(choose(request()), 'once');
    permissions.clear();
    expect(choose(request(), active: false), isNull);
    expect(choose(request()), 'once');
  });
}
