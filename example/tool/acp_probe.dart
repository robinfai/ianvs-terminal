import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/acp/codex_acp_backend.dart';
import 'package:app/features/ai/ai_models.dart';

Future<void> main(List<String> args) async {
  final backend = CodexAcpBackend(
    AiConfiguration.acp(agentCommand: args[0], agentArguments: args.sublist(1)),
  );
  try {
    await backend.prompt(
      'Reply with exactly OK. Do not use tools.',
      tools: (_, _) async => throw const AiFailure('read_only'),
      events: (event) {
        if ([
          'trail_connection',
          'trail_complete',
          'agent_message_chunk',
          'usage_update',
        ].contains(event['sessionUpdate'])) {
          stdout.writeln(jsonEncode(event));
        }
      },
      cancellation: AiCancellation(),
    );
  } finally {
    await backend.dispose();
  }
}
