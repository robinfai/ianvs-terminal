enum RecordingSearchScope { all, command, screen }

final class RecordingSearchQuery {
  const RecordingSearchQuery({
    this.text = '',
    this.hostname = '',
    this.scope = RecordingSearchScope.all,
    this.fromUtc,
    this.untilUtc,
  });
  final String text;
  final String hostname;
  final RecordingSearchScope scope;
  final DateTime? fromUtc;
  final DateTime? untilUtc;
  bool get hasCriteria =>
      text.trim().isNotEmpty ||
      hostname.trim().isNotEmpty ||
      scope != RecordingSearchScope.all ||
      fromUtc != null ||
      untilUtc != null;
  bool includesDate(DateTime created) =>
      (fromUtc == null || !created.isBefore(fromUtc!)) &&
      (untilUtc == null || created.isBefore(untilUtc!));
}

final class RecordingSearchResult {
  const RecordingSearchResult({
    required this.path,
    required this.title,
    required this.createdAtUtc,
    required this.offset,
    required this.scope,
    required this.preview,
    this.hostname,
  });
  final String path;
  final String title;
  final DateTime createdAtUtc;
  final Duration offset;
  final RecordingSearchScope scope;
  final String preview;
  final String? hostname;
}
