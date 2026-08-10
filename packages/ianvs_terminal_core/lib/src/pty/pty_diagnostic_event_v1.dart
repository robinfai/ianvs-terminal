import 'dart:convert';

import 'pty_runtime_envelope.dart';

/// A bounded, correlated diagnostic specialization of Runtime Envelope v1.
final class PtyDiagnosticEventV1 {
  PtyDiagnosticEventV1._({
    required this.schemaVersion,
    required this.name,
    required this.sessionId,
    required this.sequence,
    required this.timestampMicros,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  static const int maxEncodedBytes = 1024 * 1024;

  final int schemaVersion;
  final String name;
  final String sessionId;
  final int sequence;
  final int timestampMicros;
  final Map<String, Object?> payload;

  factory PtyDiagnosticEventV1.fromJsonString(
    String raw, {
    String? expectedSessionId,
    String? expectedName,
  }) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const PtyRuntimeContractException(
        code: 'encoded_diagnostic_too_large',
        path: r'$',
        message: 'Encoded Diagnostic Event exceeds the v1 limit',
      );
    }
    try {
      return PtyDiagnosticEventV1.fromJson(
        jsonDecode(raw),
        expectedSessionId: expectedSessionId,
        expectedName: expectedName,
      );
    } on PtyRuntimeContractException {
      rethrow;
    } on FormatException catch (error) {
      throw PtyRuntimeContractException(
        code: 'invalid_json',
        path: r'$',
        message: error.message,
      );
    }
  }

  factory PtyDiagnosticEventV1.fromJson(
    Object? json, {
    String? expectedSessionId,
    String? expectedName,
  }) {
    final envelope = PtyRuntimeEnvelope.fromJson(json);
    if (envelope.messageClass != PtyRuntimeMessageClass.diagnostic) {
      throw const PtyRuntimeContractException(
        code: 'invalid_diagnostic_class',
        path: r'$.message_class',
        message: 'Diagnostic Event message_class must be diagnostic',
      );
    }
    final sessionId = envelope.sessionId;
    if (sessionId == null) {
      throw const PtyRuntimeContractException(
        code: 'missing_field',
        path: r'$.session_id',
        message: 'Diagnostic Event session_id is required',
      );
    }
    final sequence = envelope.sequence;
    if (sequence == null) {
      throw const PtyRuntimeContractException(
        code: 'missing_field',
        path: r'$.sequence',
        message: 'Diagnostic Event sequence is required',
      );
    }
    if (expectedSessionId != null && sessionId != expectedSessionId) {
      throw const PtyRuntimeContractException(
        code: 'diagnostic_session_mismatch',
        path: r'$.session_id',
        message: 'Diagnostic Event session_id does not match the request',
      );
    }
    if (expectedName != null && envelope.messageName != expectedName) {
      throw const PtyRuntimeContractException(
        code: 'diagnostic_name_mismatch',
        path: r'$.message_name',
        message: 'Diagnostic Event message_name does not match the request',
      );
    }
    final rawPayload = envelope.payload;
    if (rawPayload is! Map) {
      throw const PtyRuntimeContractException(
        code: 'invalid_type',
        path: r'$.payload',
        message: 'Diagnostic Event payload must be a JSON object',
      );
    }
    final payload = <String, Object?>{};
    for (final entry in rawPayload.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const PtyRuntimeContractException(
          code: 'invalid_type',
          path: r'$.payload',
          message: 'Diagnostic Event payload keys must be strings',
        );
      }
      payload[key] = entry.value;
    }
    return PtyDiagnosticEventV1._(
      schemaVersion: envelope.schemaVersion,
      name: envelope.messageName,
      sessionId: sessionId,
      sequence: sequence,
      timestampMicros: envelope.timestampMicros,
      payload: payload,
    );
  }
}
