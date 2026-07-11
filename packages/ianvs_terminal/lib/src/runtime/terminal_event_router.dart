import 'package:ianvs_pty/ianvs_pty.dart';

enum TerminalAsyncEventKind { resize, clipboardCopy, clipboardPasteRequest }

enum TerminalImmediateEventKind {
  bell,
  shellHook,
  shellContext,
  shellCommand,
  shellUserVar,
  sessionNotification,
  sessionProgress,
  sessionBadge,
  terminalContext,
  sessionReset,
}

sealed class TerminalEventRoute {
  const TerminalEventRoute();
}

final class TerminalExitEventRoute extends TerminalEventRoute {
  const TerminalExitEventRoute({required this.exitCode});

  final int? exitCode;
}

final class TerminalAsyncEventRoute extends TerminalEventRoute {
  const TerminalAsyncEventRoute({required this.kind, this.payload});

  final TerminalAsyncEventKind kind;
  final Map<String, Object?>? payload;
}

final class TerminalImmediateEventRoute extends TerminalEventRoute {
  const TerminalImmediateEventRoute({required this.kind, this.payload});

  final TerminalImmediateEventKind kind;
  final Map<String, Object?>? payload;
}

final class TerminalIgnoredEventRoute extends TerminalEventRoute {
  const TerminalIgnoredEventRoute();
}

final class TerminalEventRouter {
  const TerminalEventRouter();

  TerminalEventRoute route(PtyEvent event) {
    return switch (event.kind) {
      'exit' => TerminalExitEventRoute(
        exitCode: _wholeIntValue(event.payload?['code']),
      ),
      'resize' => TerminalAsyncEventRoute(
        kind: TerminalAsyncEventKind.resize,
        payload: event.payload,
      ),
      'clipboard_copy' => TerminalAsyncEventRoute(
        kind: TerminalAsyncEventKind.clipboardCopy,
        payload: event.payload,
      ),
      'clipboard_paste_request' => TerminalAsyncEventRoute(
        kind: TerminalAsyncEventKind.clipboardPasteRequest,
        payload: event.payload,
      ),
      'bell' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.bell,
        payload: event.payload,
      ),
      'shell_hook' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.shellHook,
        payload: event.payload,
      ),
      'shell_context' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.shellContext,
        payload: event.payload,
      ),
      'shell_command' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.shellCommand,
        payload: event.payload,
      ),
      'shell_user_var' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.shellUserVar,
        payload: event.payload,
      ),
      'session_notification' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionNotification,
        payload: event.payload,
      ),
      'session_progress' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionProgress,
        payload: event.payload,
      ),
      'session_badge' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionBadge,
        payload: event.payload,
      ),
      'terminal_context' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.terminalContext,
        payload: event.payload,
      ),
      'session_reset' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionReset,
        payload: event.payload,
      ),
      _ => const TerminalIgnoredEventRoute(),
    };
  }
}

int? _wholeIntValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    final parsed = value.toInt();
    if (value == parsed) {
      return parsed;
    }
  }
  return null;
}
