import 'terminal_mcp_server.dart';

/// Access to the scoped MCP bridge is not approval to write terminal input.
class BridgePermissions {
  final _answered = <String>{};
  final _calls = <(String, String), String>{};
  void clear() {
    _answered.clear();
    _calls.clear();
  }

  bool _bridgeInput(Map<Object?, Object?> input) =>
      input['server'] == 'trail_terminal' &&
      TerminalMcpServer.toolDefinitions.any((t) => t['name'] == input['tool']);

  /// Codex ACP 2.1.1 sends MCP identity in the preceding tool update and
  /// only its call ID in the permission request. Remember identity, never
  /// command arguments or an execution approval. The host still reviews every
  /// write when the scoped MCP endpoint is actually called.
  void observeTool(Map<String, Object?> update) {
    if (update['kind'] != 'tool_call') return;
    final session = update['sessionId'];
    final metadata = update['metadata'];
    if (session is! String || metadata is! Map) return;
    final id = metadata['toolCallId'];
    if (id is! String || id.isEmpty) return;
    final key = (session, id);
    if (['completed', 'failed'].contains(metadata['status'])) {
      _calls.remove(key);
      return;
    }
    final input = metadata['rawInput'];
    if (input == null) return; // Partial progress update, not a new identity.
    _calls.remove(key);
    if (input is Map && _bridgeInput(input)) {
      if (_calls.length >= 256) _calls.remove(_calls.keys.first);
      _calls[key] = input['tool'] as String;
    }
  }

  String? option(
    Map<String, Object?> request, {
    required String session,
    required bool active,
  }) {
    if (!active || request['sessionId'] != session) return null;
    // Runtime owns request identity and expiry. A correlated tool update may
    // supply the bridge identity omitted by a sparse control request.
    final id = request['requestId'];
    final toolCallId = request['toolCallId'];
    final input = request['rawInput'];
    if (id is! String ||
        id.isEmpty ||
        toolCallId is! String ||
        toolCallId.isEmpty ||
        !(input is Map
            ? _bridgeInput(input)
            : input == null &&
                  request['toolKind'] == 'execute' &&
                  _calls.containsKey((session, toolCallId))) ||
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
