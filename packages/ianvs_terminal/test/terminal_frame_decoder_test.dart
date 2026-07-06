import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_decoder.dart';
import 'package:ianvs_terminal/src/terminal/terminal_models.dart';

void main() {
  group('TerminalFrameDecoder', () {
    test('decodes valid frame JSON and records decode metrics', () {
      final decoder = TerminalFrameDecoder(collectMetrics: true);

      final decoded = decoder.decode(jsonEncode(_singleRowSnapshot('ready')));

      expect(decoded, isNotNull);
      expect(decoded!.frame.frameKind, TerminalFrameKind.snapshot);
      expect(decoded.frame.rows.single.text, 'ready');
      expect(decoded.metrics, isNotNull);
      expect(decoded.metrics!.rawFrameBytes, greaterThan(0));
      expect(decoded.metrics!.jsonDecodeMicros, greaterThanOrEqualTo(0));
    });

    test('omits metrics when collection is disabled', () {
      final decoder = TerminalFrameDecoder();

      final decoded = decoder.decode(jsonEncode(_singleRowSnapshot('quiet')));

      expect(decoded, isNotNull);
      expect(decoded!.frame.rows.single.text, 'quiet');
      expect(decoded.metrics, isNull);
    });

    test('returns null for malformed JSON and non-object payloads', () {
      final decoder = TerminalFrameDecoder(collectMetrics: true);

      expect(decoder.decode('{'), isNull);
      expect(decoder.decode(jsonEncode(<Object?>['not', 'a', 'map'])), isNull);
    });
  });
}

Map<String, Object?> _singleRowSnapshot(String text) {
  return <String, Object?>{
    'frame_kind': 'snapshot',
    'rows': <Object?>[
      <String, Object?>{'index': 0, 'text': text, 'style_runs': const []},
    ],
    'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
    'viewport_rows': 24,
    'viewport_cols': 80,
    'dirty_ranges': <Object?>[
      <String, Object?>{'start': 0, 'end': 1},
    ],
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
  };
}
