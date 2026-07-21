import 'dart:convert';

import 'terminal_config.dart';

const int terminalSessionConfigSchemaVersion = 1;
const String terminalSessionConfigContract = 'ianvs-session-config-v1';

/// A structured boundary failure for the product-neutral SessionConfig wire.
final class TerminalSessionConfigContractException implements Exception {
  const TerminalSessionConfigContractException({
    required this.code,
    required this.path,
    required this.message,
  });

  final String code;
  final String path;
  final String message;

  @override
  String toString() =>
      'TerminalSessionConfigContractException($code at $path: $message)';
}

/// Versioned, product-neutral session creation payload shared with the native
/// runtime. Unknown fields are ignored so additive minor evolution is safe.
final class TerminalSessionConfigV1 {
  const TerminalSessionConfigV1({
    required this.sessionId,
    required this.displayName,
    required this.config,
  });

  static const int maxEncodedBytes = 1024 * 1024;
  static const int _maxSessionIdLength = 128;
  static const int _maxDisplayNameLength = 256;
  static const int _maxProgramLength = 4096;

  int get schemaVersion => terminalSessionConfigSchemaVersion;
  String get contract => terminalSessionConfigContract;
  final String sessionId;
  final String displayName;
  final TerminalSessionConfig config;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': schemaVersion,
      'contract': contract,
      'session_id': sessionId,
      'display_name': displayName,
      'config': config.toJson(),
    };
  }

  String toJsonString() {
    final json = toJson();
    TerminalSessionConfigV1.fromJson(json);
    final encoded = jsonEncode(json);
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const TerminalSessionConfigContractException(
        code: 'encoded_config_too_large',
        path: r'$',
        message: 'encoded SessionConfig exceeds 1 MiB',
      );
    }
    return encoded;
  }

  factory TerminalSessionConfigV1.fromJsonString(String raw) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const TerminalSessionConfigContractException(
        code: 'encoded_config_too_large',
        path: r'$',
        message: 'encoded SessionConfig exceeds 1 MiB',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw TerminalSessionConfigContractException(
        code: 'invalid_json',
        path: r'$',
        message: error.message,
      );
    }
    if (decoded is! Map) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_type',
        path: r'$',
        message: 'SessionConfig must be a JSON object',
      );
    }
    return TerminalSessionConfigV1.fromJson(_objectMap(decoded, r'$'));
  }

  factory TerminalSessionConfigV1.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schema_version'];
    if (schemaVersion != terminalSessionConfigSchemaVersion) {
      throw TerminalSessionConfigContractException(
        code: 'unsupported_schema',
        path: r'$.schema_version',
        message: 'expected schema version $terminalSessionConfigSchemaVersion',
      );
    }
    if (json['contract'] != terminalSessionConfigContract) {
      throw const TerminalSessionConfigContractException(
        code: 'unsupported_contract',
        path: r'$.contract',
        message: 'expected ianvs-session-config-v1',
      );
    }
    final sessionId = _boundedRequiredString(
      json['session_id'],
      path: r'$.session_id',
      maximum: _maxSessionIdLength,
    );
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(sessionId)) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_session_id',
        path: r'$.session_id',
        message: 'session_id contains unsupported characters',
      );
    }
    final displayName = _boundedRequiredString(
      json['display_name'],
      path: r'$.display_name',
      maximum: _maxDisplayNameLength,
    );
    final rawConfig = json['config'];
    if (rawConfig == null) {
      throw const TerminalSessionConfigContractException(
        code: 'missing_field',
        path: r'$.config',
        message: 'config is required',
      );
    }
    final configJson = _objectMap(rawConfig, r'$.config');
    final rawLaunch = configJson['launch'];
    if (rawLaunch == null) {
      throw const TerminalSessionConfigContractException(
        code: 'missing_field',
        path: r'$.config.launch',
        message: 'launch is required',
      );
    }
    final launch = _objectMap(rawLaunch, r'$.config.launch');
    final program = launch['program'];
    if (program is! String ||
        program.trim().isEmpty ||
        program.length > _maxProgramLength ||
        program.contains('\u0000')) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_launch_program',
        path: r'$.config.launch.program',
        message: 'launch program must be a non-empty bounded string',
      );
    }
    _validateStringList(
      launch['args'],
      path: r'$.config.launch.args',
      maximum: maxTerminalLaunchArgs,
    );
    _validateStringMap(
      launch['env'],
      path: r'$.config.launch.env',
      maximum: maxTerminalEnvironmentEntries,
    );
    final cwd = launch['cwd'];
    if (cwd != null && (cwd is! String || cwd.length > _maxProgramLength)) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_type',
        path: r'$.config.launch.cwd',
        message: 'cwd must be null or a bounded string',
      );
    }
    return TerminalSessionConfigV1(
      sessionId: sessionId,
      displayName: displayName,
      config: TerminalSessionConfig.fromJson(configJson),
    );
  }
}

Map<String, Object?> _objectMap(Object? value, String path) {
  if (value is! Map) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_type',
      path: path,
      message: 'expected a JSON object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw TerminalSessionConfigContractException(
        code: 'invalid_type',
        path: path,
        message: 'object keys must be strings',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _boundedRequiredString(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value is! String || value.trim().isEmpty || value.length > maximum) {
    throw TerminalSessionConfigContractException(
      code: value == null ? 'missing_field' : 'invalid_string',
      path: path,
      message: 'expected a non-empty string of at most $maximum characters',
    );
  }
  if (value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_string',
      path: path,
      message: 'control characters are not allowed',
    );
  }
  return value;
}

void _validateStringList(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value == null) {
    return;
  }
  if (value is! List ||
      value.length > maximum ||
      value.any((item) => item is! String)) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_collection',
      path: path,
      message: 'expected at most $maximum string entries',
    );
  }
}

void _validateStringMap(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value == null) {
    return;
  }
  if (value is! Map ||
      value.length > maximum ||
      value.entries.any(
        (entry) => entry.key is! String || entry.value is! String,
      )) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_collection',
      path: path,
      message: 'expected at most $maximum string-to-string entries',
    );
  }
}
