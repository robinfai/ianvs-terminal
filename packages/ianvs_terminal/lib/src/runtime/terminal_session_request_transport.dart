import 'dart:convert';

import 'package:ianvs_pty/ianvs_pty.dart';

int _sessionRequestSeed = 0;

/// Internal compatibility transport for synchronous Dart-to-native session
/// commands. Operation-specific clients continue to own their payload models.
final class TerminalSessionRequestTransport {
  TerminalSessionRequestTransport(PtySessionJsonRequestBackend? backend)
    : _legacyBackend = backend,
      _versionedBackend = backend is PtySessionRequestV1Backend
          ? backend! as PtySessionRequestV1Backend
          : null;

  final PtySessionJsonRequestBackend? _legacyBackend;
  final PtySessionRequestV1Backend? _versionedBackend;

  bool get isSupported => _legacyBackend != null;

  Map<String, Object?>? requestObject(
    String sessionId,
    Map<String, Object?> legacyRequest,
  ) {
    final operation = legacyRequest['kind'];
    if (operation is! String || operation.isEmpty) {
      throw ArgumentError.value(
        operation,
        'legacyRequest.kind',
        'must be a non-empty operation string',
      );
    }
    final versionedBackend = _versionedBackend;
    if (versionedBackend != null && versionedBackend.supportsSessionRequestV1) {
      final requestId = 'dart-${++_sessionRequestSeed}';
      final payload = Map<String, Object?>.of(legacyRequest)..remove('kind');
      final request = PtySessionRequestV1(
        requestId: requestId,
        sessionId: sessionId,
        operation: operation,
        payload: payload,
      );
      final raw = versionedBackend.requestSessionV1Json(
        sessionId,
        request.toJsonString(),
      );
      if (raw == null || raw.isEmpty) {
        throw const PtySessionRequestContractException(
          code: 'missing_response',
          path: r'$',
          message: 'v1 backend returned no response',
        );
      }
      final response = PtySessionResponseV1.fromJsonString(
        raw,
        expectedRequestId: requestId,
        expectedSessionId: sessionId,
        expectedOperation: operation,
      );
      if (response.ok) {
        return response.payload;
      }
      return <String, Object?>{'ok': false, 'error': response.error!.toJson()};
    }
    final legacyBackend = _legacyBackend;
    if (legacyBackend == null) {
      return null;
    }
    final raw = legacyBackend.requestSessionJson(
      sessionId,
      jsonEncode(legacyRequest),
    );
    return _tryDecodeJsonObject(raw);
  }
}

Map<String, Object?>? _tryDecodeJsonObject(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    final json = <String, Object?>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is String) {
        json[key] = entry.value;
      }
    }
    return json;
  } on Object {
    return null;
  }
}
