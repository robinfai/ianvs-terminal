import 'package:duration/duration.dart';
import 'package:duration/locale.dart';

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

String sessionSidebarElapsed(
  DateTime start,
  DateTime now, {
  String languageCode = 'en',
}) {
  final elapsed = now.isBefore(start) ? Duration.zero : now.difference(start);
  return prettyDuration(
    elapsed,
    locale: DurationLocale.fromLanguageCode(languageCode) ?? englishLocale,
    abbreviated: true,
    spacer: '',
    delimiter: ' ',
    upperTersity: DurationTersity.day,
    tersity: elapsed.inDays > 0
        ? DurationTersity.hour
        : elapsed.inMinutes > 0
        ? DurationTersity.minute
        : DurationTersity.second,
  );
}
