import 'package:ianvs_terminal_core/src/pty/ianvs_pty.dart';

int _sessionRequestSeed = 0;

/// Current Session Request v1 transport for synchronous Dart-to-native
/// commands. Operation-specific clients continue to own their payload models.
final class TerminalSessionRequestTransport {
  TerminalSessionRequestTransport(PtySessionRequestV1Backend? backend)
    : _backend = backend;

  final PtySessionRequestV1Backend? _backend;

  bool get isSupported => _backend != null;

  Map<String, Object?>? requestObject(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) {
    if (operation.isEmpty) {
      throw ArgumentError.value(
        operation,
        'operation',
        'must be a non-empty operation string',
      );
    }
    final backend = _backend;
    if (backend == null) {
      return null;
    }
    final requestId = 'dart-${++_sessionRequestSeed}';
    final request = PtySessionRequestV1(
      requestId: requestId,
      sessionId: sessionId,
      operation: operation,
      payload: payload,
    );
    final raw = backend.requestSessionV1Json(sessionId, request.toJsonString());
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
}
