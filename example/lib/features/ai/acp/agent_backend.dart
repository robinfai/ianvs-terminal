import '../ai_models.dart';

typedef AgentToolHandler =
    Future<Map<String, Object?>> Function(
      String name,
      Map<String, Object?> args,
    );
typedef AgentEventHandler = void Function(Map<String, Object?> event);

/// A conversation owns its inference loop. Terminal tools remain host-owned.
abstract interface class AgentBackend {
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  });
  Future<void> dispose();
}

typedef AgentBackendFactory = AgentBackend Function(AiConfiguration config);
