import 'dart:convert';

// Do not display arbitrary provider messages: they can echo prompts or secrets.
// Only expose diagnoses the app knows how to explain and recover from.
String? aiErrorCode(Object? data) {
  if (data is! Map || data['error'] is! Map) return null;
  final error = data['error'] as Map;
  final code = error['code'];
  const known = {
    'ai_provider_quota',
    'ai_model_unavailable',
    'context_too_large',
    'ai_protocol_unsupported',
    'ai_provider_authentication',
    'ai_provider_rate_limited',
    'ai_request_rejected',
    'ai_upstream_error',
    'ai_upstream_unavailable',
    'ai_rate_limited',
    'ai_model_forbidden',
    'ai_unavailable',
    'invalid_model',
    'response_incomplete',
  };
  if (known.contains(code)) return code as String;
  if (code == 'model_not_found') return 'ai_model_unavailable';
  if (code == 'insufficient_quota') return 'ai_provider_quota';
  if (code == 'context_length_exceeded') return 'context_too_large';
  if (error['param'] == 'reasoning_effort' &&
      '${error['message']}'.contains('/v1/responses')) {
    return 'ai_protocol_unsupported';
  }
  return null;
}

Future<String> readAiHttpError(
  Stream<List<int>> stream,
  int status, {
  bool quotaExhausted = false,
}) async {
  // Preserve application quota semantics independently of upstream quotas.
  if (quotaExhausted) return 'quota_exceeded';
  final bytes = <int>[];
  try {
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 64 * 1024) break;
      bytes.addAll(chunk);
    }
    final code = aiErrorCode(jsonDecode(utf8.decode(bytes)));
    if (code != null) return code;
  } on FormatException {
    // HTML proxy errors and malformed JSON still get an actionable fallback.
  }
  return switch (status) {
    401 || 403 => 'authentication',
    429 => 'rate_limit',
    400 || 422 => 'ai_request_rejected',
    502 || 503 || 504 => 'ai_upstream_unavailable',
    _ => 'http_$status',
  };
}
