import 'package:duration/duration.dart';
import 'package:duration/locale.dart';

import '../sessions/session_state.dart';

enum SessionSidebarCategory { interactive, running, directory }

const sessionSidebarLongRunningThreshold = Duration(seconds: 10);

/// SSH wrapper hooks and direct SSH routes carry the connection identity.
/// Ordinary shell context is only a fallback when neither is available.
String sessionSidebarDirectory(
  TerminalPane pane, {
  required String localHostname,
  required String? localHome,
  required String unknownDirectory,
}) {
  String? nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  final metadata = pane.shellIntegration;
  var path = nonEmpty(metadata.currentDirectory);
  if (path == null) return unknownDirectory;
  final remoteHops = pane.shellConnectionChain.where(
    (hop) => hop.kind == ShellConnectionHopKind.sshShell,
  );
  final hop = remoteHops.isEmpty ? null : remoteHops.last;
  final reportedHost = nonEmpty(metadata.hostname)?.toLowerCase();
  final local = localHostname.toLowerCase();
  final reportedRemote =
      reportedHost != null &&
      !{
        local,
        '$local.local',
        'localhost',
        '127.0.0.1',
        '::1',
      }.contains(reportedHost);
  final host =
      nonEmpty(metadata.sshHost)?.toLowerCase() ??
      nonEmpty(hop?.host)?.toLowerCase() ??
      (reportedRemote ? reportedHost : null);
  if (host != null) {
    final user =
        nonEmpty(metadata.sshUser) ??
        nonEmpty(hop?.user) ??
        nonEmpty(metadata.username) ??
        '';
    final port = metadata.sshPort ?? hop?.port;
    final address = host.contains(':') ? '[$host]' : host;
    final suffix = port != null && port > 0 && port != 22 ? ':$port' : '';
    return '$user@$address$suffix:$path';
  }
  if (localHome != null && localHome.isNotEmpty) {
    if (path == localHome) {
      path = '~';
    } else if (path.startsWith('$localHome/')) {
      path = '~${path.substring(localHome.length)}';
    }
  }
  return path;
}

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
