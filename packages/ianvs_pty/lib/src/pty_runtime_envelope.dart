import 'dart:convert';

const int ptyRuntimeEnvelopeSchemaVersion = 1;
const String ptyRuntimeEnvelopeContractV1 = 'ianvs-runtime-envelope-v1';
const String ptyRuntimeEventBatchContractV1 = 'ianvs-runtime-event-batch-v1';

const int _maxSafeJsonInteger = 9007199254740991;
final BigInt _maxUint64 = BigInt.parse('18446744073709551615');
final RegExp _sessionIdPattern = RegExp(r'^[1-9][0-9]*$');

enum PtyRuntimeMessageClass {
  command('command'),
  event('event'),
  frame('frame'),
  assetTransfer('asset_transfer'),
  diagnostic('diagnostic'),
  error('error');

  const PtyRuntimeMessageClass(this.wireName);

  final String wireName;

  static PtyRuntimeMessageClass? tryParse(Object? value) {
    for (final messageClass in values) {
      if (messageClass.wireName == value) {
        return messageClass;
      }
    }
    return null;
  }
}

final class PtyRuntimeContractException implements Exception {
  const PtyRuntimeContractException({
    required this.code,
    required this.path,
    required this.message,
  });

  final String code;
  final String path;
  final String message;

  @override
  String toString() => 'PtyRuntimeContractException($code at $path): $message';
}

final class PtyRuntimeEnvelope {
  const PtyRuntimeEnvelope._({
    required this.schemaVersion,
    required this.contract,
    required this.messageClass,
    required this.messageName,
    required this.sessionId,
    required this.sequence,
    required this.timestampMicros,
    required this.payload,
  });

  static const int maxMessageNameLength = 128;

  final int schemaVersion;
  final String contract;
  final PtyRuntimeMessageClass messageClass;
  final String messageName;
  final String? sessionId;
  final int? sequence;
  final int timestampMicros;
  final Object? payload;

  factory PtyRuntimeEnvelope.fromJson(Object? json) {
    final map = _jsonObject(json, r'$');
    final schemaVersion = _requiredSafeInt(map, 'schema_version', r'$');
    if (schemaVersion != ptyRuntimeEnvelopeSchemaVersion) {
      throw PtyRuntimeContractException(
        code: 'unsupported_schema',
        path: r'$.schema_version',
        message: 'Unsupported Runtime Envelope schema $schemaVersion',
      );
    }

    final contract = _requiredString(map, 'contract', r'$');
    if (contract != ptyRuntimeEnvelopeContractV1) {
      throw PtyRuntimeContractException(
        code: 'unsupported_contract',
        path: r'$.contract',
        message: 'Unsupported Runtime Envelope contract $contract',
      );
    }

    final messageClass = PtyRuntimeMessageClass.tryParse(map['message_class']);
    if (messageClass == null) {
      throw const PtyRuntimeContractException(
        code: 'unsupported_message_class',
        path: r'$.message_class',
        message:
            'message_class is not part of the Runtime Envelope v1 taxonomy',
      );
    }

    final messageName = _requiredString(map, 'message_name', r'$');
    if (messageName.length > maxMessageNameLength) {
      throw const PtyRuntimeContractException(
        code: 'string_too_long',
        path: r'$.message_name',
        message: 'message_name exceeds the v1 limit',
      );
    }

    return PtyRuntimeEnvelope._(
      schemaVersion: schemaVersion,
      contract: contract,
      messageClass: messageClass,
      messageName: messageName,
      sessionId: _optionalSessionId(map['session_id'], r'$.session_id'),
      sequence: _optionalSafeInt(map['sequence'], r'$.sequence'),
      timestampMicros: _requiredSafeInt(map, 'timestamp_micros', r'$'),
      payload: map['payload'],
    );
  }
}

final class PtyRuntimeEventBatch {
  PtyRuntimeEventBatch._({
    required this.schemaVersion,
    required this.contract,
    required this.messageClass,
    required this.sessionId,
    required this.nextSequence,
    required this.droppedCount,
    required List<PtyRuntimeEnvelope> messages,
  }) : messages = List<PtyRuntimeEnvelope>.unmodifiable(messages);

  static const int maxEncodedBytes = 9 * 1024 * 1024;
  static const int maxMessages = 1024;

  final int schemaVersion;
  final String contract;
  final PtyRuntimeMessageClass messageClass;
  final String sessionId;
  final int nextSequence;
  final int droppedCount;
  final List<PtyRuntimeEnvelope> messages;

  factory PtyRuntimeEventBatch.fromJsonString(String raw) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const PtyRuntimeContractException(
        code: 'encoded_batch_too_large',
        path: r'$',
        message: 'Encoded Runtime Event batch exceeds the v1 limit',
      );
    }
    try {
      return PtyRuntimeEventBatch.fromJson(jsonDecode(raw));
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

  factory PtyRuntimeEventBatch.fromJson(Object? json) {
    final map = _jsonObject(json, r'$');
    final schemaVersion = _requiredSafeInt(map, 'schema_version', r'$');
    if (schemaVersion != ptyRuntimeEnvelopeSchemaVersion) {
      throw PtyRuntimeContractException(
        code: 'unsupported_schema',
        path: r'$.schema_version',
        message: 'Unsupported Runtime Event batch schema $schemaVersion',
      );
    }

    final contract = _requiredString(map, 'contract', r'$');
    if (contract != ptyRuntimeEventBatchContractV1) {
      throw PtyRuntimeContractException(
        code: 'unsupported_contract',
        path: r'$.contract',
        message: 'Unsupported Runtime Event batch contract $contract',
      );
    }

    final messageClass = PtyRuntimeMessageClass.tryParse(map['message_class']);
    if (messageClass != PtyRuntimeMessageClass.event) {
      throw const PtyRuntimeContractException(
        code: 'unsupported_message_class',
        path: r'$.message_class',
        message: 'Runtime Event batch message_class must be event',
      );
    }

    final sessionId = _requiredSessionId(map['session_id'], r'$.session_id');
    final nextSequence = _requiredSafeInt(map, 'next_sequence', r'$');
    final droppedCount = _requiredSafeInt(map, 'dropped_count', r'$');
    final rawMessages = map['messages'];
    if (rawMessages is! List<Object?>) {
      throw const PtyRuntimeContractException(
        code: 'invalid_type',
        path: r'$.messages',
        message: 'messages must be a JSON array',
      );
    }
    if (rawMessages.length > maxMessages) {
      throw const PtyRuntimeContractException(
        code: 'too_many_messages',
        path: r'$.messages',
        message: 'Runtime Event batch exceeds the v1 message count limit',
      );
    }

    final messages = <PtyRuntimeEnvelope>[];
    int? previousSequence;
    for (var index = 0; index < rawMessages.length; index += 1) {
      final message = PtyRuntimeEnvelope.fromJson(rawMessages[index]);
      final path = '\$.messages[$index]';
      if (message.messageClass != PtyRuntimeMessageClass.event) {
        throw PtyRuntimeContractException(
          code: 'invalid_event_class',
          path: '$path.message_class',
          message: 'Runtime Event batch entries must have class event',
        );
      }
      if (message.sessionId != sessionId) {
        throw PtyRuntimeContractException(
          code: 'event_session_mismatch',
          path: '$path.session_id',
          message: 'Event session_id does not match its batch',
        );
      }
      final sequence = message.sequence;
      if (sequence == null) {
        throw PtyRuntimeContractException(
          code: 'missing_field',
          path: '$path.sequence',
          message: 'Event sequence is required',
        );
      }
      if (previousSequence != null && sequence <= previousSequence) {
        throw PtyRuntimeContractException(
          code: 'event_sequence_reordered',
          path: '$path.sequence',
          message: 'Event sequences must be strictly increasing',
        );
      }
      previousSequence = sequence;
      messages.add(message);
    }

    for (var index = 0; index < messages.length; index += 1) {
      if (messages[index].sequence! >= nextSequence) {
        throw PtyRuntimeContractException(
          code: 'invalid_event_sequence',
          path: '\$.messages[$index].sequence',
          message: 'Event sequence must be below next_sequence',
        );
      }
    }

    if (droppedCount > nextSequence) {
      throw const PtyRuntimeContractException(
        code: 'invalid_dropped_count',
        path: r'$.dropped_count',
        message: 'dropped_count cannot exceed next_sequence',
      );
    }

    return PtyRuntimeEventBatch._(
      schemaVersion: schemaVersion,
      contract: contract,
      messageClass: PtyRuntimeMessageClass.event,
      sessionId: sessionId,
      nextSequence: nextSequence,
      droppedCount: droppedCount,
      messages: messages,
    );
  }
}

Map<String, Object?> _jsonObject(Object? value, String path) {
  if (value is! Map) {
    throw PtyRuntimeContractException(
      code: 'invalid_type',
      path: path,
      message: 'Expected a JSON object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw PtyRuntimeContractException(
        code: 'invalid_type',
        path: path,
        message: 'JSON object keys must be strings',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(
  Map<String, Object?> map,
  String field,
  String parentPath,
) {
  final value = map[field];
  if (value is! String || value.isEmpty) {
    throw PtyRuntimeContractException(
      code: value == null ? 'missing_field' : 'invalid_type',
      path: '$parentPath.$field',
      message: '$field must be a non-empty string',
    );
  }
  return value;
}

int _requiredSafeInt(
  Map<String, Object?> map,
  String field,
  String parentPath,
) {
  final value = map[field];
  if (value is! int || value < 0 || value > _maxSafeJsonInteger) {
    throw PtyRuntimeContractException(
      code: value == null ? 'missing_field' : 'invalid_integer',
      path: '$parentPath.$field',
      message: '$field must be a non-negative JSON-safe integer',
    );
  }
  return value;
}

int? _optionalSafeInt(Object? value, String path) {
  if (value == null) {
    return null;
  }
  if (value is! int || value < 0 || value > _maxSafeJsonInteger) {
    throw PtyRuntimeContractException(
      code: 'invalid_integer',
      path: path,
      message: 'Expected a non-negative JSON-safe integer',
    );
  }
  return value;
}

String _requiredSessionId(Object? value, String path) {
  final sessionId = _optionalSessionId(value, path);
  if (sessionId == null) {
    throw PtyRuntimeContractException(
      code: 'missing_field',
      path: path,
      message: 'session_id is required',
    );
  }
  return sessionId;
}

String? _optionalSessionId(Object? value, String path) {
  if (value == null) {
    return null;
  }
  if (value is! String || !_sessionIdPattern.hasMatch(value)) {
    throw PtyRuntimeContractException(
      code: 'invalid_session_id',
      path: path,
      message: 'session_id must be a positive decimal u64 string',
    );
  }
  final parsed = BigInt.parse(value);
  if (parsed > _maxUint64) {
    throw PtyRuntimeContractException(
      code: 'invalid_session_id',
      path: path,
      message: 'session_id exceeds u64',
    );
  }
  return value;
}
