import 'terminal_mcp_server.dart';

/// Access to the scoped MCP bridge is not approval to write terminal input.
class BridgePermissions {
  final _calls = <String>{};
  void clear() => _calls.clear();
  void observe(Map<String, Object?> event) {
    final input = event['rawInput'] as Map?;
    final id = event['toolCallId'];
    if (id is String &&
        input?['server'] == 'trail_terminal' &&
        TerminalMcpServer.toolDefinitions.any(
          (t) => t['name'] == input?['tool'],
        )) {
      _calls.add(id);
    }
    if (event['status'] == 'completed' || event['status'] == 'failed') {
      _calls.remove(id);
    }
  }

  String? option(
    Map<String, Object?> request, {
    required String session,
    required bool active,
  }) {
    if (!active || request['sessionId'] != session) return null;
    final call = request['toolCall'] as Map?;
    if (!_calls.remove(call?['toolCallId'])) return null;
    for (final option in request['options'] as List? ?? []) {
      if ((option as Map)['kind'] == 'allow_once') {
        return option['optionId'] as String?;
      }
    }
    return null;
  }
}
