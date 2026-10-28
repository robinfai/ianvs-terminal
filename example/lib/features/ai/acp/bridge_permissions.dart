import 'terminal_mcp_server.dart';

/// Access to the scoped MCP bridge is not approval to write terminal input.
class BridgePermissions {
  final _answered = <String>{};
  void clear() => _answered.clear();

  String? option(
    Map<String, Object?> request, {
    required String session,
    required bool active,
  }) {
    if (!active || request['sessionId'] != session) return null;
    // Use the runtime's control request, not a lossy render projection. Runtime
    // owns permission expiry; this policy only grants access to the MCP bridge.
    final id = request['requestId'];
    final toolCallId = request['toolCallId'];
    final input = request['rawInput'] as Map?;
    if (id is! String ||
        id.isEmpty ||
        toolCallId is! String ||
        toolCallId.isEmpty ||
        input?['server'] != 'trail_terminal' ||
        !TerminalMcpServer.toolDefinitions.any(
          (t) => t['name'] == input?['tool'],
        ) ||
        !_answered.add(id)) {
      return null;
    }
    for (final option in request['options'] as List? ?? []) {
      if ((option as Map)['kind'] == 'allow_once') {
        return option['optionId'] as String?;
      }
    }
    return null;
  }
}
