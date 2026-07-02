import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/proto/frame_diff.pb.dart' as frame_pb;

const String _configuredOutPath = String.fromEnvironment(
  'FRAME_DIFF_TRANSPORT_BENCH_OUT',
  defaultValue: '',
);
const int _iterations = int.fromEnvironment(
  'FRAME_DIFF_TRANSPORT_BENCH_ITERATIONS',
  defaultValue: 80,
);
const int _frameCount = int.fromEnvironment(
  'FRAME_DIFF_TRANSPORT_BENCH_FRAMES',
  defaultValue: 120,
);
const int _viewportRows = int.fromEnvironment(
  'FRAME_DIFF_TRANSPORT_BENCH_ROWS',
  defaultValue: 40,
);
const int _viewportCols = int.fromEnvironment(
  'FRAME_DIFF_TRANSPORT_BENCH_COLS',
  defaultValue: 120,
);

void main() {
  test(
    'frame diff transport benchmark exports metrics',
    () {
      final fixtures = _buildFixtures(
        frameCount: _frameCount,
        viewportRows: _viewportRows,
        viewportCols: _viewportCols,
      );
      expect(fixtures, isNotEmpty);

      _warmUp(fixtures);

      final jsonDecodeRounds = <int>[];
      final protobufDecodeRounds = <int>[];
      final jsonHashes = <String>[];
      final protobufHashes = <String>[];

      for (var iteration = 0; iteration < _iterations; iteration += 1) {
        final jsonWatch = Stopwatch()..start();
        for (final fixture in fixtures) {
          final frame = TerminalFrameDiff.fromJson(
            (jsonDecode(fixture.jsonPayload) as Map).cast<String, Object?>(),
          );
          if (iteration == 0) {
            jsonHashes.add(terminalBenchmarkViewportHash(frame));
          }
        }
        jsonWatch.stop();
        jsonDecodeRounds.add(jsonWatch.elapsedMicroseconds);

        final protobufWatch = Stopwatch()..start();
        for (final fixture in fixtures) {
          final frame = TerminalFrameDiff.fromProtobufBytes(
            fixture.protobufPayload,
          );
          if (iteration == 0) {
            protobufHashes.add(terminalBenchmarkViewportHash(frame));
          }
        }
        protobufWatch.stop();
        protobufDecodeRounds.add(protobufWatch.elapsedMicroseconds);
      }

      expect(protobufHashes, jsonHashes);

      final totalJsonBytes = fixtures.fold<int>(
        0,
        (sum, fixture) => sum + fixture.jsonPayloadBytes,
      );
      final totalProtobufBytes = fixtures.fold<int>(
        0,
        (sum, fixture) => sum + fixture.protobufPayload.length,
      );
      final jsonDecodeTotal = jsonDecodeRounds.fold<int>(
        0,
        (sum, value) => sum + value,
      );
      final protobufDecodeTotal = protobufDecodeRounds.fold<int>(
        0,
        (sum, value) => sum + value,
      );
      final sampleCount = fixtures.length * _iterations;
      final metrics = <String, Object?>{
        'schema_version': 'ianvs-frame-diff-transport-benchmark-v1',
        'mode': 'flutter_test_debug',
        'iterations': _iterations,
        'frame_count': fixtures.length,
        'sample_count': sampleCount,
        'viewport_rows': _viewportRows,
        'viewport_cols': _viewportCols,
        'correctness': <String, Object?>{
          'frame_hashes_match': true,
          'first_hash': jsonHashes.first,
          'last_hash': jsonHashes.last,
        },
        'json': <String, Object?>{
          'total_bytes': totalJsonBytes,
          'mean_bytes': totalJsonBytes / fixtures.length,
          'decode_round_micros': _distributionSummary(jsonDecodeRounds),
          'decode_mean_micros_per_frame': jsonDecodeTotal / sampleCount,
        },
        'protobuf': <String, Object?>{
          'total_bytes': totalProtobufBytes,
          'mean_bytes': totalProtobufBytes / fixtures.length,
          'decode_round_micros': _distributionSummary(protobufDecodeRounds),
          'decode_mean_micros_per_frame': protobufDecodeTotal / sampleCount,
        },
        'ratios': <String, Object?>{
          'protobuf_bytes_to_json': totalProtobufBytes / totalJsonBytes,
          'protobuf_decode_to_json': protobufDecodeTotal / jsonDecodeTotal,
        },
      };

      File(_configuredOutPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(metrics),
        );
    },
    skip: _configuredOutPath.isEmpty,
  );
}

void _warmUp(List<_FrameWireFixture> fixtures) {
  for (var repeat = 0; repeat < 8; repeat += 1) {
    for (final fixture in fixtures) {
      TerminalFrameDiff.fromJson(
        (jsonDecode(fixture.jsonPayload) as Map).cast<String, Object?>(),
      );
      TerminalFrameDiff.fromProtobufBytes(fixture.protobufPayload);
    }
  }
}

List<_FrameWireFixture> _buildFixtures({
  required int frameCount,
  required int viewportRows,
  required int viewportCols,
}) {
  return List<_FrameWireFixture>.generate(frameCount, (frameIndex) {
    final isSnapshot = frameIndex == 0 || frameIndex % 30 == 0;
    final dirtyStart = isSnapshot ? 0 : (frameIndex * 7) % (viewportRows - 8);
    final dirtyEnd = isSnapshot ? viewportRows : dirtyStart + 8;
    final rowIndexes = isSnapshot
        ? List<int>.generate(viewportRows, (index) => index)
        : List<int>.generate(dirtyEnd - dirtyStart, (index) {
            return dirtyStart + index;
          });
    final rows = [
      for (final rowIndex in rowIndexes)
        _rowJson(
          frameIndex: frameIndex,
          rowIndex: rowIndex,
          viewportCols: viewportCols,
        ),
    ];
    final protobufRows = [
      for (final rowIndex in rowIndexes)
        _rowProtobuf(
          frameIndex: frameIndex,
          rowIndex: rowIndex,
          viewportCols: viewportCols,
        ),
    ];
    final cursorRow = rowIndexes.last;
    final cursorCol = (frameIndex * 11) % viewportCols;
    final includeGraphic = frameIndex % 13 == 0;
    final includeHyperlink = frameIndex % 5 == 0;
    final json = <String, Object?>{
      'frame_schema_version': TerminalFrameDiff.currentFrameSchemaVersion,
      'frame_kind': isSnapshot ? 'snapshot' : 'delta',
      'rows': rows,
      'cursor': <String, Object?>{
        'row': cursorRow,
        'col': cursorCol,
        'visible': true,
      },
      'viewport_rows': viewportRows,
      'viewport_cols': viewportCols,
      'dirty_ranges': [
        <String, Object?>{'start': dirtyStart, 'end': dirtyEnd},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': frameIndex * 3,
      'viewport_start_row': frameIndex * 2,
      'viewport_row_shift': isSnapshot ? 0 : -1,
      'default_foreground': '#d8dee9',
      'default_background': '#101820',
      'cursor_color': '#88c0d0',
      'modes': <String, Object?>{
        'alternate_screen': frameIndex % 17 == 0,
        'alternate_scroll': false,
        'application_cursor': frameIndex % 7 == 0,
        'application_keypad': false,
        'insert_mode': false,
        'origin_mode': false,
        'line_feed_new_line_mode': false,
        'hide_cursor': false,
        'bracketed_paste': frameIndex % 11 == 0,
        'focus_tracking': false,
        'char_protected': false,
        'mouse_mode': frameIndex % 9 == 0 ? 'any_event' : 'off',
        'mouse_encoding': frameIndex % 9 == 0 ? 'sgr_pixels' : 'default',
        'kitty_keyboard_flags': frameIndex % 8,
        'synchronized_output': frameIndex % 19 == 0,
      },
      'window_title': 'bench frame $frameIndex',
      'window_icon_name': 'ianvs',
      'hyperlinks': includeHyperlink
          ? [
              <String, Object?>{
                'row': cursorRow,
                'start_col': 8,
                'end_col': 34,
                'uri': 'https://example.com/frame/$frameIndex',
              },
            ]
          : const <Object?>[],
      'inline_images': const <Object?>[],
      'graphics': includeGraphic
          ? [
              <String, Object?>{
                'placement_id': frameIndex + 1,
                'render_id': frameIndex + 1001,
                'asset_id': 7,
                'asset_version': frameIndex + 1,
                'protocol': 'kitty',
                'row': 2,
                'col': 4,
                'width_px': 64,
                'height_px': 32,
                'width_cells': 8,
                'height_cells': 2,
                'source_x_offset_px': 4,
                'visible_width_px': 60,
                'source_y_offset_px': 2,
                'visible_height_px': 30,
                'z_index': frameIndex % 3,
                'x_offset_px': 1,
                'y_offset_px': 0,
                'preserve_aspect_ratio': true,
              },
            ]
          : const <Object?>[],
    };
    final protobuf = frame_pb.TerminalFrameDiff(
      frameSchemaVersion: TerminalFrameDiff.currentFrameSchemaVersion,
      frameKind: isSnapshot
          ? frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_SNAPSHOT
          : frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_DELTA,
      rows: protobufRows,
      cursor: frame_pb.TerminalCursor(
        row: cursorRow,
        col: cursorCol,
        visible: true,
      ),
      viewportRows: viewportRows,
      viewportCols: viewportCols,
      dirtyRanges: [
        frame_pb.TerminalDirtyRange(start: dirtyStart, end: dirtyEnd),
      ],
      scrollbackOffset: 0,
      scrollbackMaxOffset: frameIndex * 3,
      viewportStartRow: frameIndex * 2,
      viewportRowShift: isSnapshot ? 0 : -1,
      defaultForeground: frame_pb.ColorRgb(present: true, rgb: 0xd8dee9),
      defaultBackground: frame_pb.ColorRgb(present: true, rgb: 0x101820),
      cursorColor: frame_pb.ColorRgb(present: true, rgb: 0x88c0d0),
      modes: frame_pb.TerminalFrameModes(
        alternateScreen: frameIndex % 17 == 0,
        applicationCursor: frameIndex % 7 == 0,
        bracketedPaste: frameIndex % 11 == 0,
        mouseMode: frameIndex % 9 == 0 ? 'any_event' : 'off',
        mouseEncoding: frameIndex % 9 == 0 ? 'sgr_pixels' : 'default',
        kittyKeyboardFlags: frameIndex % 8,
        synchronizedOutput: frameIndex % 19 == 0,
      ),
      windowTitle: 'bench frame $frameIndex',
      windowIconName: 'ianvs',
      hyperlinks: includeHyperlink
          ? [
              frame_pb.TerminalHyperlinkRange(
                row: cursorRow,
                startCol: 8,
                endCol: 34,
                uri: 'https://example.com/frame/$frameIndex',
              ),
            ]
          : const <frame_pb.TerminalHyperlinkRange>[],
      inlineImages: const <frame_pb.TerminalInlineImage>[],
      graphics: includeGraphic
          ? [
              frame_pb.TerminalGraphicPlacement(
                placementId: frameIndex + 1,
                renderId: frameIndex + 1001,
                assetKey: frame_pb.TerminalGraphicAssetKey(
                  assetId: 7,
                  assetVersion: frameIndex + 1,
                ),
                protocol: 'kitty',
                row: 2,
                col: 4,
                widthPx: 64,
                heightPx: 32,
                widthCells: 8,
                heightCells: 2,
                sourceXOffsetPx: 4,
                visibleWidthPx: 60,
                sourceYOffsetPx: 2,
                visibleHeightPx: 30,
                zIndex: frameIndex % 3,
                xOffsetPx: 1,
                preserveAspectRatio: true,
              ),
            ]
          : const <frame_pb.TerminalGraphicPlacement>[],
    );
    return _FrameWireFixture(
      jsonPayload: jsonEncode(json),
      protobufPayload: Uint8List.fromList(protobuf.writeToBuffer()),
    );
  }, growable: false);
}

Map<String, Object?> _rowJson({
  required int frameIndex,
  required int rowIndex,
  required int viewportCols,
}) {
  final text = _rowText(
    frameIndex: frameIndex,
    rowIndex: rowIndex,
    viewportCols: viewportCols,
  );
  return <String, Object?>{
    'index': rowIndex,
    'text': text,
    'wrapped': rowIndex.isOdd,
    'style_runs': [
      <String, Object?>{
        'start': 0,
        'end': text.length,
        'foreground': rowIndex.isEven ? '#a3be8c' : '#ebcb8b',
        'background': null,
        'bold': rowIndex % 3 == 0,
        'dim': false,
        'italic': rowIndex % 5 == 0,
        'underline': rowIndex % 7 == 0,
        'blink': false,
        'inverse': false,
      },
    ],
  };
}

frame_pb.TerminalRow _rowProtobuf({
  required int frameIndex,
  required int rowIndex,
  required int viewportCols,
}) {
  final text = _rowText(
    frameIndex: frameIndex,
    rowIndex: rowIndex,
    viewportCols: viewportCols,
  );
  return frame_pb.TerminalRow(
    index: rowIndex,
    text: text,
    wrapped: rowIndex.isOdd,
    styleRuns: [
      frame_pb.TerminalStyleRun(
        start: 0,
        end: text.length,
        foreground: frame_pb.ColorRgb(
          present: true,
          rgb: rowIndex.isEven ? 0xa3be8c : 0xebcb8b,
        ),
        bold: rowIndex % 3 == 0,
        italic: rowIndex % 5 == 0,
        underline: rowIndex % 7 == 0,
      ),
    ],
  );
}

String _rowText({
  required int frameIndex,
  required int rowIndex,
  required int viewportCols,
}) {
  final prefix =
      'frame=$frameIndex row=$rowIndex service=terminal status=ok trace=${frameIndex * 1000 + rowIndex} ';
  final suffix = 'payload=${'x' * ((frameIndex + rowIndex) % 48)}';
  final text = '$prefix$suffix';
  if (text.length >= viewportCols) {
    return text.substring(0, viewportCols);
  }
  return text.padRight(viewportCols);
}

Map<String, Object?> _distributionSummary(List<int> values) {
  final sorted = values.toList()..sort();
  final total = values.fold<int>(0, (sum, value) => sum + value);
  return <String, Object?>{
    'count': values.length,
    'min': sorted.first,
    'max': sorted.last,
    'mean': total / values.length,
    'p50': _percentile(sorted, 0.50),
    'p95': _percentile(sorted, 0.95),
    'total': total,
  };
}

int _percentile(List<int> sorted, double percentile) {
  if (sorted.length == 1) {
    return sorted.single;
  }
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index.clamp(0, sorted.length - 1)];
}

final class _FrameWireFixture {
  const _FrameWireFixture({
    required this.jsonPayload,
    required this.protobufPayload,
  });

  final String jsonPayload;
  final Uint8List protobufPayload;

  int get jsonPayloadBytes => utf8.encode(jsonPayload).length;
}
