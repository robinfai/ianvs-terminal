import 'dart:convert';

import '../terminal/terminal_models.dart';

final class TerminalDecodedFrame {
  const TerminalDecodedFrame({required this.frame, required this.metrics});

  final TerminalFrameDiff frame;
  final TerminalFrameDecodeMetrics? metrics;
}

final class TerminalFrameDecodeMetrics {
  const TerminalFrameDecodeMetrics({
    required this.rawFrameBytes,
    required this.jsonDecodeMicros,
  });

  final int rawFrameBytes;
  final int jsonDecodeMicros;
}

final class TerminalFrameDecoder {
  const TerminalFrameDecoder({this.collectMetrics = false});

  final bool collectMetrics;

  TerminalDecodedFrame? decode(String rawFrame) {
    final decodeWatch = collectMetrics ? (Stopwatch()..start()) : null;
    final json = _tryDecodeJsonObject(rawFrame);
    if (json == null) {
      return null;
    }
    try {
      final frame = TerminalFrameDiff.fromJson(json);
      decodeWatch?.stop();
      return TerminalDecodedFrame(
        frame: frame,
        metrics: collectMetrics
            ? TerminalFrameDecodeMetrics(
                rawFrameBytes: utf8.encode(rawFrame).length,
                jsonDecodeMicros: decodeWatch?.elapsedMicroseconds ?? 0,
              )
            : null,
      );
    } on Object {
      return null;
    }
  }
}

Map<String, Object?>? _tryDecodeJsonObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return _stringKeyedJsonMap(decoded);
  } on Object {
    return null;
  }
}

Map<String, Object?> _stringKeyedJsonMap(Map<dynamic, dynamic> decoded) {
  final json = <String, Object?>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (key is String) {
      json[key] = entry.value;
    }
  }
  return json;
}
