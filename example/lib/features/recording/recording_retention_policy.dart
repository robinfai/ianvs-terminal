/// Local policy for the schema-2 library. Both limits apply to ordinary files.
final class RecordingRetentionPolicy {
  RecordingRetentionPolicy({
    required this.maximumAgeDays,
    required this.maximumBytes,
  }) {
    if (maximumAgeDays < 1 ||
        maximumAgeDays > 36500 ||
        maximumBytes < 1 ||
        maximumBytes > 9007199254740991) {
      throw ArgumentError('Invalid recording retention limits');
    }
  }

  factory RecordingRetentionPolicy.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.length != 3 ||
        raw['schema_version'] != 2 ||
        raw['schema_version'] is! int ||
        raw['maximum_age_days'] is! int ||
        raw['maximum_bytes'] is! int) {
      throw const FormatException('Invalid or unsupported retention policy');
    }
    try {
      return RecordingRetentionPolicy(
        maximumAgeDays: raw['maximum_age_days'] as int,
        maximumBytes: raw['maximum_bytes'] as int,
      );
    } on ArgumentError {
      throw const FormatException('Invalid recording retention limits');
    }
  }

  final int maximumAgeDays;
  final int maximumBytes;
  Duration get maximumAge => Duration(days: maximumAgeDays);

  Map<String, Object?> toJson() => {
    'schema_version': 2,
    'maximum_age_days': maximumAgeDays,
    'maximum_bytes': maximumBytes,
  };
}
