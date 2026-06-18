import 'command_block_models.dart';
import 'command_invocation_models.dart';
import 'command_search_index.dart';
import 'global_command_history_repository.dart';
import 'session_command_history_buffer.dart';
import 'shell_hook_lifecycle_adapter.dart';

class CommandCenterRuntimeState {
  const CommandCenterRuntimeState({
    this.lifecycle = const CommandLifecycleState(),
    this.history = const SessionCommandHistoryBuffer(),
    this.cwdBySession = const <String, String>{},
    this.openInvocationIdsBySession = const <String, String>{},
  });

  final CommandLifecycleState lifecycle;
  final SessionCommandHistoryBuffer history;
  final Map<String, String> cwdBySession;
  final Map<String, String> openInvocationIdsBySession;

  String? cwdForSession(String sessionId) {
    return cwdBySession[sessionId];
  }

  CommandInvocation? runningInvocationForSession(String sessionId) {
    final invocationId = openInvocationIdsBySession[sessionId];
    if (invocationId == null) {
      return null;
    }
    final invocation = lifecycle.invocationById(invocationId);
    if (invocation?.status == CommandInvocationStatus.running) {
      return invocation;
    }
    return null;
  }

  CommandSearchIndex searchIndex({
    GlobalCommandHistoryDocument globalHistory =
        const GlobalCommandHistoryDocument(),
  }) {
    return CommandSearchIndex([
      ...history.entries.map(GlobalCommandHistoryEntry.fromSessionEntry),
      ...globalHistory.entries,
    ]);
  }

  CommandBlockRangeState blockRangeState({
    required Map<String, CommandBlockTerminalRanges> rangesByInvocationId,
    bool shellIntegrationEnabled = true,
  }) {
    return CommandBlockRangeState.fromInvocations(
      lifecycle.invocations,
      rangesByInvocationId: rangesByInvocationId,
      shellIntegrationEnabled: shellIntegrationEnabled,
    );
  }

  CommandCenterRuntimeState copyWith({
    CommandLifecycleState? lifecycle,
    SessionCommandHistoryBuffer? history,
    Map<String, String>? cwdBySession,
    Map<String, String>? openInvocationIdsBySession,
  }) {
    return CommandCenterRuntimeState(
      lifecycle: lifecycle ?? this.lifecycle,
      history: history ?? this.history,
      cwdBySession: cwdBySession ?? this.cwdBySession,
      openInvocationIdsBySession:
          openInvocationIdsBySession ?? this.openInvocationIdsBySession,
    );
  }
}

class CommandCenterRuntimeReducer {
  const CommandCenterRuntimeReducer();

  CommandCenterRuntimeState apply(
    CommandCenterRuntimeState state,
    CommandLifecycleEvent event,
  ) {
    return switch (event) {
      CommandLifecycleStartedEvent() => _started(state, event),
      CommandLifecycleFinishedEvent() => _finished(state, event),
      CommandLifecycleCwdChangedEvent() => _cwdChanged(state, event),
    };
  }

  CommandCenterRuntimeState _started(
    CommandCenterRuntimeState state,
    CommandLifecycleStartedEvent event,
  ) {
    final cwd =
        _trimmedOrNull(event.cwd) ?? state.cwdForSession(event.sessionId);
    final invocation = CommandInvocation.running(
      id: _invocationIdFor(event),
      sessionId: event.sessionId,
      command: event.command,
      cwd: cwd,
      startedAt: event.receivedAt,
    );
    return state.copyWith(
      lifecycle: state.lifecycle.addInvocation(invocation),
      cwdBySession: _updatedCwdMap(state.cwdBySession, event.sessionId, cwd),
      openInvocationIdsBySession: {
        ...state.openInvocationIdsBySession,
        event.sessionId: invocation.id,
      },
    );
  }

  CommandCenterRuntimeState _finished(
    CommandCenterRuntimeState state,
    CommandLifecycleFinishedEvent event,
  ) {
    final existing = _runningInvocationForFinish(state, event);
    final cwd =
        _trimmedOrNull(event.cwd) ??
        existing?.cwd ??
        state.cwdForSession(event.sessionId);
    final finished = CommandInvocation.completed(
      id: existing?.id ?? _invocationIdFor(event),
      sessionId: event.sessionId,
      command: event.command,
      cwd: cwd,
      startedAt: existing?.startedAt ?? event.receivedAt,
      finishedAt: event.receivedAt,
      exitCode: event.exitCode,
    );
    final lifecycle = CommandLifecycleState(
      invocations: _replaceOrAppendInvocation(
        state.lifecycle.invocations,
        finished,
      ),
    );
    final nextOpen = Map<String, String>.of(state.openInvocationIdsBySession);
    if (nextOpen[event.sessionId] == finished.id) {
      nextOpen.remove(event.sessionId);
    }

    final historyEvent = CommandLifecycleFinishedEvent(
      sessionId: event.sessionId,
      receivedAt: event.receivedAt,
      command: event.command,
      cwd: cwd,
      exitCode: event.exitCode,
    );
    return state.copyWith(
      lifecycle: lifecycle,
      history: state.history.recordFinished(
        historyEvent,
        invocationId: finished.id,
      ),
      cwdBySession: _updatedCwdMap(state.cwdBySession, event.sessionId, cwd),
      openInvocationIdsBySession: nextOpen,
    );
  }

  CommandCenterRuntimeState _cwdChanged(
    CommandCenterRuntimeState state,
    CommandLifecycleCwdChangedEvent event,
  ) {
    return state.copyWith(
      cwdBySession: _updatedCwdMap(
        state.cwdBySession,
        event.sessionId,
        event.cwd,
      ),
    );
  }
}

CommandInvocation? _runningInvocationForFinish(
  CommandCenterRuntimeState state,
  CommandLifecycleFinishedEvent event,
) {
  final current = state.runningInvocationForSession(event.sessionId);
  if (current != null && current.command == event.command) {
    return current;
  }
  for (final invocation in state.lifecycle.invocations.reversed) {
    if (invocation.sessionId == event.sessionId &&
        invocation.command == event.command &&
        invocation.status == CommandInvocationStatus.running) {
      return invocation;
    }
  }
  return null;
}

List<CommandInvocation> _replaceOrAppendInvocation(
  List<CommandInvocation> invocations,
  CommandInvocation invocation,
) {
  final index = invocations.indexWhere((item) => item.id == invocation.id);
  if (index == -1) {
    return <CommandInvocation>[...invocations, invocation];
  }
  return <CommandInvocation>[
    ...invocations.take(index),
    invocation,
    ...invocations.skip(index + 1),
  ];
}

Map<String, String> _updatedCwdMap(
  Map<String, String> current,
  String sessionId,
  String? cwd,
) {
  final trimmed = _trimmedOrNull(cwd);
  if (trimmed == null) {
    return current;
  }
  return {...current, sessionId: trimmed};
}

String _invocationIdFor(CommandLifecycleEvent event) {
  return [
    event.sessionId,
    event.receivedAt.microsecondsSinceEpoch,
    if (event is CommandLifecycleStartedEvent) _stableHash(event.command),
    if (event is CommandLifecycleFinishedEvent) _stableHash(event.command),
  ].join(':');
}

int _stableHash(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = 0x1fffffff & (hash + codeUnit);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash ^= hash >> 11;
  return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
