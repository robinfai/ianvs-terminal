import '../terminal/terminal.dart' as terminal;

/// A location resolved from the command that produced the text. The current
/// prompt directory is deliberately not an input to this resolver.
final class TerminalFileLocation {
  const TerminalFileLocation({
    required this.path,
    required this.remote,
    required this.contextId,
    this.line,
    this.column,
  });

  final String path;
  final bool remote;
  final String contextId;
  final int? line;
  final int? column;

  String get name => path.split('/').last;
  String get parent {
    final slash = path.lastIndexOf('/');
    return slash <= 0 ? '/' : path.substring(0, slash);
  }

  String get localUri => Uri.file(path).toString();
}

TerminalFileLocation? resolveTerminalFileLocation({
  required terminal.TerminalSemanticFileTarget target,
  required terminal.CommandOccurrenceScope scope,
  required String activeContextId,
  required bool hasRemoteRoute,
  String? remoteHost,
  String? remoteContextId,
  required Set<String> localHostnames,
}) {
  final context = target.context;
  if (context.sessionId != scope.sessionId ||
      context.sessionEpoch != scope.sessionEpoch ||
      scope.transport.kind == terminal.CommandTransportKind.replay ||
      (context.contextId ?? 'root') != activeContextId) {
    return null;
  }
  final remote =
      scope.transport.kind == terminal.CommandTransportKind.ssh ||
      hasRemoteRoute;
  // A shell's claimed hostname never turns SSH into a local filesystem. An
  // unfamiliar hostname on a local PTY is also not proof of a usable SSH route.
  final host = context.shellHostname?.trim().toLowerCase();
  if (!remote &&
      host != null &&
      host.isNotEmpty &&
      !localHostnames.map((host) => host.toLowerCase()).contains(host)) {
    return null;
  }
  if (remote && !hasRemoteRoute) return null;
  if (remote) {
    // A nested host name or shell context can be reused. Only its captured
    // native route lease identifies the connection that produced this output.
    if (remoteContextId == null ||
        (context.sftpContextId != null &&
            context.sftpContextId != remoteContextId) ||
        (remoteContextId != 'root' && context.sftpContextId == null)) {
      return null;
    }
  }
  // A different shell-declared host may be an unregistered nested SSH. It
  // cannot authorize falling back to the outer endpoint. Host aliases without
  // evidence remain unavailable rather than choosing a same-named remote file.
  if (remote &&
      host != null &&
      host.isNotEmpty &&
      host != (remoteHost ?? scope.transport.host)?.trim().toLowerCase()) {
    return null;
  }
  final raw = target.path;
  final cwd = context.cwd;
  if (raw.isEmpty ||
      raw.startsWith('~') ||
      raw.startsWith('//') ||
      cwd.startsWith('//') ||
      raw.split('/').contains('..') ||
      cwd.split('/').contains('..') ||
      raw.contains('://') ||
      raw.runes.any(_invalidPathRune) ||
      cwd.runes.any(_invalidPathRune) ||
      (!raw.startsWith('/') && !cwd.startsWith('/'))) {
    return null;
  }
  // Resolving '..' lexically would cross symlinks differently from the real
  // filesystem. Without endpoint canonicalization those paths are unavailable.
  // POSIX also leaves a leading double slash implementation-defined.
  final combined = raw.startsWith('/') ? raw : '$cwd/$raw';
  final segments = <String>[];
  for (final segment in combined.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    segments.add(segment);
  }
  if (segments.isEmpty) return null;
  return TerminalFileLocation(
    path: '/${segments.join('/')}',
    remote: remote,
    contextId: context.contextId ?? 'root',
    line: target.line,
    column: target.column,
  );
}

bool _invalidPathRune(int rune) => rune < 32 || (rune >= 127 && rune <= 159);
