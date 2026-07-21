import 'dart:convert';

const int ptySessionRequestSchemaVersion = 1;
const String ptySessionRequestContract = 'ianvs-session-request-v1';
const String ptySessionResponseContract = 'ianvs-session-response-v1';

final class PtySessionRequestContractException implements Exception {
  const PtySessionRequestContractException({
    required this.code,
    required this.path,
    required this.message,
  });

  final String code;
  final String path;
  final String message;

  @override
  String toString() =>
      'PtySessionRequestContractException($code at $path: $message)';
}

final class PtySessionRequestV1 {
  const PtySessionRequestV1({
    required this.requestId,
    required this.sessionId,
    required this.operation,
    required this.payload,
  });

  static const int maxEncodedBytes = 1024 * 1024;

  int get schemaVersion => ptySessionRequestSchemaVersion;
  String get contract => ptySessionRequestContract;
  final String requestId;
  final String sessionId;
  final String operation;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': schemaVersion,
      'contract': contract,
      'request_id': requestId,
      'session_id': sessionId,
      'operation': operation,
      'payload': payload,
    };
  }

  String toJsonString() {
    _validateCorrelationIdentity(
      requestId: requestId,
      sessionId: sessionId,
      operation: operation,
    );
    final String encoded;
    try {
      encoded = jsonEncode(toJson());
    } on JsonUnsupportedObjectError catch (error) {
      throw PtySessionRequestContractException(
        code: 'invalid_payload',
        path: r'$.payload',
        message: error.toString(),
      );
    }
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const PtySessionRequestContractException(
        code: 'encoded_request_too_large',
        path: r'$',
        message: 'encoded request exceeds 1 MiB',
      );
    }
    return encoded;
  }
}

final class PtySessionResponseErrorV1 {
  const PtySessionResponseErrorV1({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
  };
}

final class PtySessionResponseV1 {
  const PtySessionResponseV1._({
    required this.requestId,
    required this.sessionId,
    required this.operation,
    required this.ok,
    required this.timestampMicros,
    required this.payload,
    required this.error,
  });

  static const int maxEncodedBytes = 16 * 1024 * 1024;

  int get schemaVersion => ptySessionRequestSchemaVersion;
  String get contract => ptySessionResponseContract;
  final String requestId;
  final String sessionId;
  final String operation;
  final bool ok;
  final int timestampMicros;
  final Map<String, Object?>? payload;
  final PtySessionResponseErrorV1? error;

  factory PtySessionResponseV1.fromJsonString(
    String raw, {
    required String expectedRequestId,
    required String expectedSessionId,
    required String expectedOperation,
  }) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const PtySessionRequestContractException(
        code: 'encoded_response_too_large',
        path: r'$',
        message: 'encoded response exceeds 16 MiB',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw PtySessionRequestContractException(
        code: 'invalid_json',
        path: r'$',
        message: error.message,
      );
    }
    final json = _objectMap(decoded, r'$');
    if (json['schema_version'] != ptySessionRequestSchemaVersion) {
      throw const PtySessionRequestContractException(
        code: 'unsupported_schema',
        path: r'$.schema_version',
        message: 'expected schema version 1',
      );
    }
    if (json['contract'] != ptySessionResponseContract) {
      throw const PtySessionRequestContractException(
        code: 'unsupported_contract',
        path: r'$.contract',
        message: 'expected ianvs-session-response-v1',
      );
    }
    final requestId = _requiredString(json['request_id'], r'$.request_id');
    final sessionId = _requiredString(json['session_id'], r'$.session_id');
    final operation = _requiredString(json['operation'], r'$.operation');
    _validateCorrelationIdentity(
      requestId: requestId,
      sessionId: sessionId,
      operation: operation,
    );
    if (requestId != expectedRequestId ||
        sessionId != expectedSessionId ||
        operation != expectedOperation) {
      throw const PtySessionRequestContractException(
        code: 'correlation_mismatch',
        path: r'$',
        message: 'response identity does not match the request',
      );
    }
    final ok = json['ok'];
    if (ok is! bool) {
      throw const PtySessionRequestContractException(
        code: 'invalid_type',
        path: r'$.ok',
        message: 'ok must be a boolean',
      );
    }
    final timestampMicros = json['timestamp_micros'];
    if (timestampMicros is! int || timestampMicros < 0) {
      throw const PtySessionRequestContractException(
        code: 'invalid_timestamp',
        path: r'$.timestamp_micros',
        message: 'timestamp_micros must be a non-negative integer',
      );
    }
    if (ok) {
      if (json['error'] != null) {
        throw const PtySessionRequestContractException(
          code: 'invalid_response_state',
          path: r'$.error',
          message: 'successful responses cannot include an error',
        );
      }
      return PtySessionResponseV1._(
        requestId: requestId,
        sessionId: sessionId,
        operation: operation,
        ok: true,
        timestampMicros: timestampMicros,
        payload: _objectMap(json['payload'], r'$.payload'),
        error: null,
      );
    }
    if (json['payload'] != null) {
      throw const PtySessionRequestContractException(
        code: 'invalid_response_state',
        path: r'$.payload',
        message: 'failed responses cannot include a payload',
      );
    }
    final errorJson = _objectMap(json['error'], r'$.error');
    final code = _boundedString(
      errorJson['code'],
      path: r'$.error.code',
      maximum: 128,
    );
    final message = _boundedString(
      errorJson['message'],
      path: r'$.error.message',
      maximum: 1024,
    );
    return PtySessionResponseV1._(
      requestId: requestId,
      sessionId: sessionId,
      operation: operation,
      ok: false,
      timestampMicros: timestampMicros,
      payload: null,
      error: PtySessionResponseErrorV1(code: code, message: message),
    );
  }
}

final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$');
final RegExp _sessionIdPattern = RegExp(r'^[0-9]+$');
final RegExp _operationPattern = RegExp(r'^[a-z][a-z0-9._-]*$');
final BigInt _maxUint64 = BigInt.parse('18446744073709551615');

void _validateCorrelationIdentity({
  required String requestId,
  required String sessionId,
  required String operation,
}) {
  if (requestId.length > 128 || !_requestIdPattern.hasMatch(requestId)) {
    throw const PtySessionRequestContractException(
      code: 'invalid_request_id',
      path: r'$.request_id',
      message: 'request_id is not a bounded correlation token',
    );
  }
  if (sessionId.length > 20 || !_sessionIdPattern.hasMatch(sessionId)) {
    throw const PtySessionRequestContractException(
      code: 'invalid_session_id',
      path: r'$.session_id',
      message: 'session_id must be a positive uint64 string',
    );
  }
  final parsedSessionId = BigInt.parse(sessionId);
  if (parsedSessionId <= BigInt.zero || parsedSessionId > _maxUint64) {
    throw const PtySessionRequestContractException(
      code: 'invalid_session_id',
      path: r'$.session_id',
      message: 'session_id must be a positive uint64 string',
    );
  }
  if (operation.length > 128 || !_operationPattern.hasMatch(operation)) {
    throw const PtySessionRequestContractException(
      code: 'invalid_operation',
      path: r'$.operation',
      message: 'operation is not a bounded runtime operation token',
    );
  }
}

Map<String, Object?> _objectMap(Object? value, String path) {
  if (value is! Map) {
    throw PtySessionRequestContractException(
      code: 'invalid_type',
      path: path,
      message: 'expected a JSON object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw PtySessionRequestContractException(
        code: 'invalid_type',
        path: path,
        message: 'object keys must be strings',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Object? value, String path) {
  return _boundedString(value, path: path, maximum: 128);
}

String _boundedString(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value is! String || value.isEmpty || value.length > maximum) {
    throw PtySessionRequestContractException(
      code: value == null ? 'missing_field' : 'invalid_string',
      path: path,
      message: 'expected a non-empty string of at most $maximum characters',
    );
  }
  if (value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw PtySessionRequestContractException(
      code: 'invalid_string',
      path: path,
      message: 'control characters are not allowed',
    );
  }
  return value;
}
