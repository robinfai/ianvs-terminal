import 'dart:convert';

const int ptyHostRequestSchemaVersion = 1;
const String ptyHostRequestContract = 'ianvs-host-request-v1';
const String ptyHostResponseContract = 'ianvs-host-response-v1';

const int _maxSafeJsonInteger = 9007199254740991;
final BigInt _maxUint64 = BigInt.parse('18446744073709551615');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$');
final RegExp _operationPattern = RegExp(r'^[a-z][a-z0-9._-]*$');
final RegExp _errorCodePattern = RegExp(r'^[a-z][a-z0-9._-]*$');
final RegExp _sessionIdPattern = RegExp(r'^[1-9][0-9]*$');

final class PtyHostRequestContractException implements Exception {
  const PtyHostRequestContractException({
    required this.code,
    required this.path,
    required this.message,
  });

  final String code;
  final String path;
  final String message;

  @override
  String toString() =>
      'PtyHostRequestContractException($code at $path: $message)';
}

final class PtyHostRequestV1 {
  const PtyHostRequestV1._({
    required this.requestId,
    required this.sessionId,
    required this.operation,
    required this.sequence,
    required this.timestampMicros,
    required this.payload,
  });

  static const int maxEncodedBytes = 64 * 1024;

  int get schemaVersion => ptyHostRequestSchemaVersion;
  String get contract => ptyHostRequestContract;
  final String requestId;
  final String sessionId;
  final String operation;
  final int sequence;
  final int timestampMicros;
  final Map<String, Object?> payload;

  factory PtyHostRequestV1.fromJson(
    Object? value, {
    required String expectedSessionId,
    required int expectedSequence,
    required int expectedTimestampMicros,
  }) {
    _validateEncodedSize(value, maximum: maxEncodedBytes, kind: 'request');
    final json = _objectMap(value, r'$');
    if (json['schema_version'] != ptyHostRequestSchemaVersion) {
      throw const PtyHostRequestContractException(
        code: 'unsupported_schema',
        path: r'$.schema_version',
        message: 'expected schema version 1',
      );
    }
    if (json['contract'] != ptyHostRequestContract) {
      throw const PtyHostRequestContractException(
        code: 'unsupported_contract',
        path: r'$.contract',
        message: 'expected ianvs-host-request-v1',
      );
    }
    final requestId = _boundedToken(
      json['request_id'],
      path: r'$.request_id',
      pattern: _requestIdPattern,
    );
    final sessionId = _sessionId(json['session_id'], r'$.session_id');
    final operation = _boundedToken(
      json['operation'],
      path: r'$.operation',
      pattern: _operationPattern,
    );
    final sequence = _safeInteger(json['sequence'], r'$.sequence');
    final timestampMicros = _safeInteger(
      json['timestamp_micros'],
      r'$.timestamp_micros',
    );
    final payload = _objectMap(json['payload'], r'$.payload');
    if (sessionId != expectedSessionId ||
        sequence != expectedSequence ||
        timestampMicros != expectedTimestampMicros ||
        requestId != 'host:$sessionId:$sequence') {
      throw const PtyHostRequestContractException(
        code: 'correlation_mismatch',
        path: r'$',
        message: 'Host Request identity does not match its Runtime Event',
      );
    }
    return PtyHostRequestV1._(
      requestId: requestId,
      sessionId: sessionId,
      operation: operation,
      sequence: sequence,
      timestampMicros: timestampMicros,
      payload: Map<String, Object?>.unmodifiable(payload),
    );
  }
}

final class PtyHostResponseErrorV1 {
  const PtyHostResponseErrorV1({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
  };
}

final class PtyHostResponseV1 {
  const PtyHostResponseV1._({
    required this.requestId,
    required this.sessionId,
    required this.operation,
    required this.ok,
    required this.timestampMicros,
    required this.payload,
    required this.error,
  });

  // A 4 MiB clipboard value expands to roughly 5.34 MiB in Base64. Leave a
  // bounded margin for JSON keys and escaping without making this transport
  // an unbounded general-purpose response channel.
  static const int maxEncodedBytes = 6 * 1024 * 1024;

  int get schemaVersion => ptyHostRequestSchemaVersion;
  String get contract => ptyHostResponseContract;
  final String requestId;
  final String sessionId;
  final String operation;
  final bool ok;
  final int timestampMicros;
  final Map<String, Object?>? payload;
  final PtyHostResponseErrorV1? error;

  factory PtyHostResponseV1.success({
    required PtyHostRequestV1 request,
    required int timestampMicros,
    required Map<String, Object?> payload,
  }) {
    _safeInteger(timestampMicros, r'$.timestamp_micros');
    return PtyHostResponseV1._(
      requestId: request.requestId,
      sessionId: request.sessionId,
      operation: request.operation,
      ok: true,
      timestampMicros: timestampMicros,
      payload: Map<String, Object?>.unmodifiable(payload),
      error: null,
    );
  }

  factory PtyHostResponseV1.failure({
    required PtyHostRequestV1 request,
    required int timestampMicros,
    required String code,
    required String message,
  }) {
    _safeInteger(timestampMicros, r'$.timestamp_micros');
    final validatedCode = _boundedToken(
      code,
      path: r'$.error.code',
      pattern: _errorCodePattern,
    );
    final validatedMessage = _boundedString(
      message,
      path: r'$.error.message',
      maximum: 1024,
    );
    return PtyHostResponseV1._(
      requestId: request.requestId,
      sessionId: request.sessionId,
      operation: request.operation,
      ok: false,
      timestampMicros: timestampMicros,
      payload: null,
      error: PtyHostResponseErrorV1(
        code: validatedCode,
        message: validatedMessage,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': schemaVersion,
    'contract': contract,
    'request_id': requestId,
    'session_id': sessionId,
    'operation': operation,
    'ok': ok,
    'timestamp_micros': timestampMicros,
    if (payload != null) 'payload': payload,
    if (error != null) 'error': error!.toJson(),
  };

  String toJsonString() {
    final String encoded;
    try {
      encoded = jsonEncode(toJson());
    } on JsonUnsupportedObjectError catch (error) {
      throw PtyHostRequestContractException(
        code: 'invalid_payload',
        path: r'$.payload',
        message: error.toString(),
      );
    }
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const PtyHostRequestContractException(
        code: 'encoded_response_too_large',
        path: r'$',
        message: 'encoded Host Response exceeds 6 MiB',
      );
    }
    return encoded;
  }
}

void _validateEncodedSize(
  Object? value, {
  required int maximum,
  required String kind,
}) {
  final String encoded;
  try {
    encoded = jsonEncode(value);
  } on JsonUnsupportedObjectError catch (error) {
    throw PtyHostRequestContractException(
      code: 'invalid_json_value',
      path: r'$',
      message: error.toString(),
    );
  }
  if (utf8.encode(encoded).length > maximum) {
    throw PtyHostRequestContractException(
      code: 'encoded_${kind}_too_large',
      path: r'$',
      message:
          'encoded Host ${kind[0].toUpperCase()}${kind.substring(1)} is too large',
    );
  }
}

Map<String, Object?> _objectMap(Object? value, String path) {
  if (value is! Map) {
    throw PtyHostRequestContractException(
      code: 'invalid_type',
      path: path,
      message: 'expected a JSON object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw PtyHostRequestContractException(
        code: 'invalid_type',
        path: path,
        message: 'object keys must be strings',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _sessionId(Object? value, String path) {
  if (value is! String ||
      value.length > 20 ||
      !_sessionIdPattern.hasMatch(value)) {
    throw PtyHostRequestContractException(
      code: value == null ? 'missing_field' : 'invalid_session_id',
      path: path,
      message: 'session_id must be a positive uint64 string',
    );
  }
  final parsed = BigInt.parse(value);
  if (parsed > _maxUint64) {
    throw PtyHostRequestContractException(
      code: 'invalid_session_id',
      path: path,
      message: 'session_id must be a positive uint64 string',
    );
  }
  return value;
}

int _safeInteger(Object? value, String path) {
  if (value is! int || value < 0 || value > _maxSafeJsonInteger) {
    throw PtyHostRequestContractException(
      code: value == null ? 'missing_field' : 'invalid_integer',
      path: path,
      message: 'expected a non-negative JSON-safe integer',
    );
  }
  return value;
}

String _boundedToken(
  Object? value, {
  required String path,
  required RegExp pattern,
}) {
  final token = _boundedString(value, path: path, maximum: 128);
  if (!pattern.hasMatch(token)) {
    throw PtyHostRequestContractException(
      code: 'invalid_token',
      path: path,
      message: 'value is not a valid bounded protocol token',
    );
  }
  return token;
}

String _boundedString(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value is! String || value.isEmpty || value.length > maximum) {
    throw PtyHostRequestContractException(
      code: value == null ? 'missing_field' : 'invalid_string',
      path: path,
      message: 'expected a non-empty string of at most $maximum characters',
    );
  }
  if (value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw PtyHostRequestContractException(
      code: 'invalid_string',
      path: path,
      message: 'control characters are not allowed',
    );
  }
  return value;
}
