enum CommandInvocationStatus { running, succeeded, failed, unknown }

class CommandInvocation {
  const CommandInvocation({
    required this.id,
    required this.sessionId,
    required this.command,
    required this.startedAt,
    required this.status,
    this.cwd,
    this.paneId,
    this.profileId,
    this.finishedAt,
    this.exitCode,
  });

  factory CommandInvocation.running({
    required String id,
    required String sessionId,
    required String command,
    required DateTime startedAt,
    String? cwd,
    String? paneId,
    String? profileId,
  }) {
    return CommandInvocation(
      id: id,
      sessionId: sessionId,
      command: command,
      cwd: cwd,
      paneId: paneId,
      profileId: profileId,
      startedAt: startedAt,
      status: CommandInvocationStatus.running,
    );
  }

  factory CommandInvocation.completed({
    required String id,
    required String sessionId,
    required String command,
    required DateTime startedAt,
    required DateTime finishedAt,
    int? exitCode,
    String? cwd,
    String? paneId,
    String? profileId,
  }) {
    return CommandInvocation(
      id: id,
      sessionId: sessionId,
      command: command,
      cwd: cwd,
      paneId: paneId,
      profileId: profileId,
      startedAt: startedAt,
      finishedAt: finishedAt,
      exitCode: exitCode,
      status: exitCode == 0
          ? CommandInvocationStatus.succeeded
          : CommandInvocationStatus.failed,
    );
  }

  factory CommandInvocation.unknown({
    required String id,
    required String sessionId,
    required String command,
    required DateTime startedAt,
    String? cwd,
    String? paneId,
    String? profileId,
  }) {
    return CommandInvocation(
      id: id,
      sessionId: sessionId,
      command: command,
      cwd: cwd,
      paneId: paneId,
      profileId: profileId,
      startedAt: startedAt,
      status: CommandInvocationStatus.unknown,
    );
  }

  final String id;
  final String sessionId;
  final String command;
  final String? cwd;
  final String? paneId;
  final String? profileId;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final CommandInvocationStatus status;

  Duration? get duration => finishedAt?.difference(startedAt);
}

class CommandLifecycleState {
  const CommandLifecycleState({this.invocations = const <CommandInvocation>[]});

  final List<CommandInvocation> invocations;

  CommandLifecycleState addInvocation(CommandInvocation invocation) {
    return CommandLifecycleState(
      invocations: <CommandInvocation>[...invocations, invocation],
    );
  }

  List<CommandInvocation> invocationsForSession(String sessionId) {
    return List<CommandInvocation>.unmodifiable(
      invocations.where((invocation) => invocation.sessionId == sessionId),
    );
  }

  CommandInvocation? invocationById(String id) {
    for (final invocation in invocations) {
      if (invocation.id == id) {
        return invocation;
      }
    }
    return null;
  }
}
