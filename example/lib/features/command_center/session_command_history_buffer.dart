import 'shell_hook_lifecycle_adapter.dart';

class SessionCommandHistoryEntry {
  const SessionCommandHistoryEntry({
    required this.sessionId,
    required this.command,
    required this.finishedAt,
    this.cwd,
    this.exitCode,
    this.invocationId,
  });

  final String sessionId;
  final String command;
  final String? cwd;
  final int? exitCode;
  final DateTime finishedAt;
  final String? invocationId;

  bool get succeeded => exitCode == 0;
}

class SessionCommandHistoryBuffer {
  const SessionCommandHistoryBuffer({
    this.limit = _defaultSessionCommandHistoryLimit,
    this.entries = const <SessionCommandHistoryEntry>[],
  });

  final int limit;
  final List<SessionCommandHistoryEntry> entries;

  SessionCommandHistoryBuffer recordFinished(
    CommandLifecycleFinishedEvent event, {
    String? invocationId,
  }) {
    final command = _trimmedOrNull(event.command);
    if (command == null) {
      return this;
    }

    final entry = SessionCommandHistoryEntry(
      sessionId: event.sessionId,
      command: command,
      cwd: _trimmedOrNull(event.cwd),
      exitCode: event.exitCode,
      finishedAt: event.receivedAt,
      invocationId: _trimmedOrNull(invocationId),
    );
    final withoutDuplicate = entries
        .where((candidate) => !_sameHistoryKey(candidate, entry))
        .toList(growable: false);
    final nextEntries = <SessionCommandHistoryEntry>[
      entry,
      ...withoutDuplicate,
    ];
    return SessionCommandHistoryBuffer(
      limit: limit,
      entries: _trimSessionEntries(
        nextEntries,
        sessionId: entry.sessionId,
        limit: _effectiveLimit(limit),
      ),
    );
  }

  List<SessionCommandHistoryEntry> entriesForSession(String sessionId) {
    return List<SessionCommandHistoryEntry>.unmodifiable(
      entries.where((entry) => entry.sessionId == sessionId),
    );
  }
}

const _defaultSessionCommandHistoryLimit = 100;

int _effectiveLimit(int limit) {
  return limit > 0 ? limit : _defaultSessionCommandHistoryLimit;
}

List<SessionCommandHistoryEntry> _trimSessionEntries(
  List<SessionCommandHistoryEntry> entries, {
  required String sessionId,
  required int limit,
}) {
  var keptForSession = 0;
  return entries
      .where((entry) {
        if (entry.sessionId != sessionId) {
          return true;
        }
        keptForSession += 1;
        return keptForSession <= limit;
      })
      .toList(growable: false);
}

bool _sameHistoryKey(
  SessionCommandHistoryEntry left,
  SessionCommandHistoryEntry right,
) {
  return left.sessionId == right.sessionId &&
      left.command == right.command &&
      left.cwd == right.cwd;
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
