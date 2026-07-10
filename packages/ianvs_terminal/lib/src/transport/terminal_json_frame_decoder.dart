import 'dart:convert';

import '../terminal/terminal_models.dart';

final class TerminalJsonFrameDecoder {
  const TerminalJsonFrameDecoder();

  TerminalFrameDiff? decode(String rawFrame) {
    try {
      final decoded = jsonDecode(rawFrame);
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
      return TerminalFrameDiff.fromJson(json);
    } on Object {
      return null;
    }
  }
}
