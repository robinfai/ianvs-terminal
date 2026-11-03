import 'package:flutter/foundation.dart';
import 'acp/agent_backend.dart';
import 'acp/codex_acp_backend.dart';
import 'ai_api_client.dart';
import 'ai_models.dart';

Future<void> runAiConnectionTest(
  AiConfiguration configuration,
  AiCancellation cancellation,
  ValueChanged<AiConnectionStage> onStage,
) async {
  if (configuration.backend == AiBackendKind.acp) {
    final agent = CodexAcpBackend(configuration, onConnectionStage: onStage);
    try {
      await agent.prompt(
        'Connection check. Reply with OK. Do not use tools.',
        tools: (_, _) async => throw const AiFailure('read_only'),
        events: (_) {},
        cancellation: cancellation,
      );
    } finally {
      await agent.dispose();
    }
  } else {
    onStage(AiConnectionStage.request);
    await const AiApiClient().complete(configuration, [
      {
        'role': 'user',
        'content': 'Connection check. Reply with OK. Do not use tools.',
      },
    ], cancellation);
  }
}
