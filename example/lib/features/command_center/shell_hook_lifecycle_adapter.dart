import '../terminal/terminal.dart' as terminal;

sealed class CommandLifecycleEvent {
  const CommandLifecycleEvent({
    required this.sessionId,
    required this.receivedAt,
  });

  final String sessionId;
  final DateTime receivedAt;
}

class CommandLifecycleStartedEvent extends CommandLifecycleEvent {
  const CommandLifecycleStartedEvent({
    required super.sessionId,
    required super.receivedAt,
    required this.command,
    this.cwd,
  });

  final String command;
  final String? cwd;
}

class CommandLifecycleFinishedEvent extends CommandLifecycleEvent {
  const CommandLifecycleFinishedEvent({
    required super.sessionId,
    required super.receivedAt,
    required this.command,
    this.cwd,
    this.exitCode,
  });

  final String command;
  final String? cwd;
  final int? exitCode;
}

class CommandLifecycleCwdChangedEvent extends CommandLifecycleEvent {
  const CommandLifecycleCwdChangedEvent({
    required super.sessionId,
    required super.receivedAt,
    required this.cwd,
  });

  final String cwd;
}

enum ShellHookLifecycleIgnoredReason { unknownHook, missingCommand, missingCwd }

class ShellHookLifecycleAdapterResult {
  const ShellHookLifecycleAdapterResult.event(this.event)
    : ignoredReason = null;

  const ShellHookLifecycleAdapterResult.ignored(this.ignoredReason)
    : event = null;

  final CommandLifecycleEvent? event;
  final ShellHookLifecycleIgnoredReason? ignoredReason;

  bool get isIgnored => ignoredReason != null;
}

class ShellHookLifecycleAdapter {
  const ShellHookLifecycleAdapter();

  ShellHookLifecycleAdapterResult adapt(
    terminal.TerminalSessionShellHookEvent event, {
    DateTime? receivedAt,
  }) {
    final timestamp = receivedAt ?? DateTime.now();
    final hook = event.hook;
    return switch (hook) {
      'preexec' => _started(event, timestamp),
      'command_finished' => _finished(event, timestamp),
      'precmd.pwd' => _cwdChanged(event, timestamp),
      _ => const ShellHookLifecycleAdapterResult.ignored(
        ShellHookLifecycleIgnoredReason.unknownHook,
      ),
    };
  }

  ShellHookLifecycleAdapterResult _started(
    terminal.TerminalSessionShellHookEvent event,
    DateTime receivedAt,
  ) {
    final command = _trimmedOrNull(event.command);
    if (command == null) {
      return const ShellHookLifecycleAdapterResult.ignored(
        ShellHookLifecycleIgnoredReason.missingCommand,
      );
    }
    return ShellHookLifecycleAdapterResult.event(
      CommandLifecycleStartedEvent(
        sessionId: event.sessionId,
        receivedAt: receivedAt,
        command: command,
        cwd: _trimmedOrNull(event.cwd),
      ),
    );
  }

  ShellHookLifecycleAdapterResult _finished(
    terminal.TerminalSessionShellHookEvent event,
    DateTime receivedAt,
  ) {
    final command = _trimmedOrNull(event.command);
    if (command == null) {
      return const ShellHookLifecycleAdapterResult.ignored(
        ShellHookLifecycleIgnoredReason.missingCommand,
      );
    }
    return ShellHookLifecycleAdapterResult.event(
      CommandLifecycleFinishedEvent(
        sessionId: event.sessionId,
        receivedAt: receivedAt,
        command: command,
        cwd: _trimmedOrNull(event.cwd),
        exitCode: event.exitCode,
      ),
    );
  }

  ShellHookLifecycleAdapterResult _cwdChanged(
    terminal.TerminalSessionShellHookEvent event,
    DateTime receivedAt,
  ) {
    final cwd = _trimmedOrNull(event.cwd);
    if (cwd == null) {
      return const ShellHookLifecycleAdapterResult.ignored(
        ShellHookLifecycleIgnoredReason.missingCwd,
      );
    }
    return ShellHookLifecycleAdapterResult.event(
      CommandLifecycleCwdChangedEvent(
        sessionId: event.sessionId,
        receivedAt: receivedAt,
        cwd: cwd,
      ),
    );
  }
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
