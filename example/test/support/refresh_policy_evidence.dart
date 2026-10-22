/// A skipped tick or a new request does not replace the last completed poll.
/// Select the latest result, so callers still reject an obsolete policy state
/// when a newer completed result has advanced its backoff.
Map<String, Object?>? latestRefreshResult(
  List<Map<String, Object?>> events,
  String sessionId,
) {
  for (final event in events.reversed) {
    if (event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
        event['session_id'] == sessionId &&
        event['event'] == 'refresh_result') {
      return event;
    }
  }
  return null;
}
