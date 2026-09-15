import '../sessions/session_state.dart';

enum SessionSidebarCategory { interactive, running, directory }

const sessionSidebarLongRunningThreshold = Duration(seconds: 10);

SessionSidebarCategory sessionSidebarCategory(
  TerminalTab tab, {
  required bool alternateScreen,
  required DateTime now,
}) {
  final pane = tab.activePane;
  if (pane.isExited) return SessionSidebarCategory.directory;
  if (alternateScreen) return SessionSidebarCategory.interactive;
  final started = pane.shellIntegration.commandStartedAt;
  if (started != null &&
      now.difference(started) >= sessionSidebarLongRunningThreshold) {
    return SessionSidebarCategory.running;
  }
  return SessionSidebarCategory.directory;
}

String sessionSidebarElapsed(DateTime start, DateTime now) {
  final seconds = now.difference(start).inSeconds.clamp(0, 0x7fffffff);
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}
