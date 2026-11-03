import 'dart:convert';

/// Compact observations, never user requirements, commands, receipts or tool
/// pairing. Full history stays in the task; this is only the inference view.
List<Map<String, Object?>> compactAiObservations(
  List<Map<String, Object?>> messages, {
  bool force = false,
  int targetBytes = 128000,
}) {
  final result = messages.map(Map<String, Object?>.of).toList();
  if (!force && utf8.encode(jsonEncode(result)).length <= targetBytes) {
    return result;
  }
  // Retain recent verbatim observations. Explicit overflow recovery keeps the
  // latest request/result pair and compacts more of the older observations.
  final keep = force ? 2 : 8;
  final cutoff = (result.length - keep).clamp(0, result.length);
  for (var i = 0; i < cutoff; i++) {
    final message = result[i];
    if (message['role'] != 'user' && message['role'] != 'tool') continue;
    final raw = message['content'];
    if (raw is! String) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      continue;
    }
    if (decoded is! Map) continue;
    final content = Map<String, Object?>.from(decoded);
    // Only known terminal evidence containers are eligible; arbitrary user
    // JSON and execution receipts must remain exact.
    for (final key in [
      'terminal_context',
      'selected_block',
      'selected_blocks',
      'block',
    ]) {
      if (content.containsKey(key)) {
        content[key] = _observationMetadata(content[key]);
      }
    }
    result[i] = {...message, 'content': jsonEncode(content)};
    if (!force && utf8.encode(jsonEncode(result)).length <= targetBytes) break;
  }
  return result;
}

Object? _observationMetadata(Object? value) {
  if (value is List) return value.map(_observationMetadata).toList();
  if (value is! Map) return value;
  final result = <String, Object?>{};
  var omitted = false;
  for (final entry in value.entries) {
    final key = entry.key as String;
    if (key == 'screen' || key == 'output' || key == 'output_ranges') {
      omitted = true;
      continue;
    }
    if (key == 'citation' ||
        key == 'output_start_line' ||
        key == 'output_end_line' ||
        key == 'included_line_count') {
      continue;
    }
    result[key] = _observationMetadata(entry.value);
  }
  if (omitted) {
    result['observation_compacted'] = true;
    result['compaction_note'] =
        'Older terminal output omitted from this request; '
        'full history is retained in the app. Metadata is historical, not current '
        'evidence or authorization. Read the block or current screen again before '
        'relying on omitted output. Do not repeat a prior command just to recover output.';
  }
  return result;
}
