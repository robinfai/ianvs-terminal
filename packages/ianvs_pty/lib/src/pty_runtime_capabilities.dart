import 'dart:convert';

const int ptyRuntimeCapabilitiesSchemaVersion = 1;
const String ptyRuntimeContractV1 = 'ianvs-runtime-contract-v1';
const String ptyRuntimeFeatureSftpDirectoryListingV1 =
    'ssh-sftp-directory-listing.v1';
const String ptyRuntimeFeatureSftpFileOperationsV1 =
    'ssh-sftp-file-operations.v1';

final class UnsupportedPtyRuntimeCapabilitiesSchemaVersion
    implements Exception {
  const UnsupportedPtyRuntimeCapabilitiesSchemaVersion(this.schemaVersion);

  final int schemaVersion;

  @override
  String toString() =>
      'UnsupportedPtyRuntimeCapabilitiesSchemaVersion($schemaVersion)';
}

final class PtyRuntimeCapabilities {
  PtyRuntimeCapabilities._({
    required this.schemaVersion,
    required this.runtimeContract,
    required List<String> frameSchemaVersions,
    required List<int> recordingSchemaVersions,
    required List<String> features,
  }) : frameSchemaVersions = List<String>.unmodifiable(frameSchemaVersions),
       recordingSchemaVersions = List<int>.unmodifiable(
         recordingSchemaVersions,
       ),
       features = List<String>.unmodifiable(features);

  static const int maxEncodedBytes = 64 * 1024;
  static const int _maxEntries = 64;
  static const int _maxStringLength = 128;

  final int schemaVersion;
  final String runtimeContract;
  final List<String> frameSchemaVersions;
  final List<int> recordingSchemaVersions;
  final List<String> features;

  factory PtyRuntimeCapabilities.fromJsonString(String raw) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const FormatException('Runtime capabilities JSON is too large');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw FormatException(
        'Invalid Runtime capabilities JSON: ${error.message}',
      );
    }
    return PtyRuntimeCapabilities.fromJson(decoded);
  }

  factory PtyRuntimeCapabilities.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Runtime capabilities must be a JSON object');
    }

    final schemaVersion = json['schema_version'];
    if (schemaVersion is! int) {
      throw const FormatException('schema_version must be an integer');
    }
    if (schemaVersion != ptyRuntimeCapabilitiesSchemaVersion) {
      throw UnsupportedPtyRuntimeCapabilitiesSchemaVersion(schemaVersion);
    }

    final runtimeContract = _requiredBoundedString(
      json['runtime_contract'],
      'runtime_contract',
    );
    if (runtimeContract != ptyRuntimeContractV1) {
      throw FormatException('Unsupported runtime_contract: $runtimeContract');
    }

    return PtyRuntimeCapabilities._(
      schemaVersion: schemaVersion,
      runtimeContract: runtimeContract,
      frameSchemaVersions: _boundedStringList(
        json['frame_schema_versions'],
        'frame_schema_versions',
      ),
      recordingSchemaVersions: _boundedPositiveIntList(
        json['recording_schema_versions'],
        'recording_schema_versions',
      ),
      features: _boundedStringList(json['features'], 'features'),
    );
  }

  bool supports(String feature) => features.contains(feature);
}

String _requiredBoundedString(Object? value, String fieldName) {
  if (value is! String ||
      value.isEmpty ||
      value.length > PtyRuntimeCapabilities._maxStringLength) {
    throw FormatException(
      '$fieldName must be a non-empty string no longer than '
      '${PtyRuntimeCapabilities._maxStringLength} characters',
    );
  }
  return value;
}

List<String> _boundedStringList(Object? value, String fieldName) {
  if (value is! List<Object?> ||
      value.length > PtyRuntimeCapabilities._maxEntries) {
    throw FormatException(
      '$fieldName must be a list with at most '
      '${PtyRuntimeCapabilities._maxEntries} entries',
    );
  }
  final result = <String>[];
  final seen = <String>{};
  for (var index = 0; index < value.length; index += 1) {
    final entry = _requiredBoundedString(value[index], '$fieldName[$index]');
    if (!seen.add(entry)) {
      throw FormatException('$fieldName contains duplicate entry: $entry');
    }
    result.add(entry);
  }
  return result;
}

List<int> _boundedPositiveIntList(Object? value, String fieldName) {
  if (value is! List<Object?> ||
      value.length > PtyRuntimeCapabilities._maxEntries) {
    throw FormatException(
      '$fieldName must be a list with at most '
      '${PtyRuntimeCapabilities._maxEntries} entries',
    );
  }
  final result = <int>[];
  final seen = <int>{};
  for (var index = 0; index < value.length; index += 1) {
    final entry = value[index];
    if (entry is! int || entry <= 0) {
      throw FormatException('$fieldName[$index] must be a positive integer');
    }
    if (!seen.add(entry)) {
      throw FormatException('$fieldName contains duplicate entry: $entry');
    }
    result.add(entry);
  }
  return result;
}
