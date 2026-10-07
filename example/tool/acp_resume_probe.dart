// Explicit live-adapter lifecycle check; no terminal or task-container writes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/acp/codex_acp_backend.dart';
import 'package:app/features/ai/ai_models.dart';

Future<void> main(List<String> args) async {
  final backend = CodexAcpBackend(
    AiConfiguration.acp(agentCommand: args[0], agentArguments: args.sublist(1)),
  );
  final first = AiCancellation();
  final sessions = <String>[];
  var observed = false;
  var resumed = '';
  void event(Map<String, Object?> value) {
    if (value['sessionUpdate'] == 'trail_connection') {
      sessions.add(value['session_id']! as String);
      stdout.writeln(jsonEncode(value));
    }
  }

  try {
    try {
      await backend.prompt(
        'Remember the phrase SILVER-OTTER-739 for our next turn. '
        'Call trail_terminal get_terminal_state once now. Do not use other tools.',
        tools: (name, _) async {
          if (name != 'get_terminal_state') throw const AiFailure('read_only');
          observed = true;
          first.cancel();
          return {'cancelled': true};
        },
        events: event,
        cancellation: first,
      );
      throw StateError('First turn was not cancelled');
    } on AiFailure catch (failure) {
      if (failure.code != 'cancelled') rethrow;
    }
    if (!observed) throw StateError('Agent never reached the bridge');
    await backend.prompt(
      'What exact phrase did I ask you to remember? Reply with only that phrase. '
      'Do not use tools.',
      tools: (_, _) async => throw const AiFailure('read_only'),
      events: (value) {
        event(value);
        if (value['sessionUpdate'] == 'agent_message_chunk') {
          resumed += ((value['content'] as Map?)?['text'] as String?) ?? '';
        }
      },
      cancellation: AiCancellation(),
    );
    if (sessions.length != 2 ||
        sessions.toSet().length != 1 ||
        !resumed.contains('SILVER-OTTER-739')) {
      throw StateError('Cancelled session did not resume its conversation');
    }
    stdout.writeln(
      jsonEncode({'cancel_resume': 'passed', 'same_session': true}),
    );
  } finally {
    await backend.dispose();
  }
}
