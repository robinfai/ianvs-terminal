import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/proto/frame_diff.pb.dart' as frame_pb;
import 'package:ianvs_terminal/src/transport/terminal_protobuf_frame_codec.dart';

import '../support/terminal_frame_from_json.dart';

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
const String _workload = String.fromEnvironment(
  'FRAME_DIFF_TRANSPORT_BENCH_WORKLOAD',
  defaultValue: 'mixed',
);

void main() {
  test(
    'frame diff transport benchmark exports metrics',
    () {
      expect(
        _workload,
        anyOf('mixed', 'resize_churn'),
        reason:
            'FRAME_DIFF_TRANSPORT_BENCH_WORKLOAD must be mixed or resize_churn',
      );
      final fixtures = _buildFixtures(
        frameCount: _frameCount,
        viewportRows: _viewportRows,
        viewportCols: _viewportCols,
        workload: _workload,
      );
      expect(fixtures, isNotEmpty);

      _warmUp(fixtures);

      final jsonMeasurements = _measureJsonDecode(fixtures);
      final protobufMeasurements = _measureProtobufDecode(fixtures);

      expect(protobufMeasurements.hashes, jsonMeasurements.hashes);

      final metrics = <String, Object?>{
        'schema_version': 'ianvs-frame-diff-transport-benchmark-v1',
        'mode': 'flutter_test_debug',
        'workload': _workload,
        'iterations': _iterations,
        'frame_count': fixtures.length,
        'sample_count': fixtures.length * _iterations,
        'viewport_rows': _viewportRows,
        'viewport_cols': _viewportCols,
        'correctness': <String, Object?>{
          'frame_hashes_match': true,
          'first_hash': jsonMeasurements.hashes.first,
          'last_hash': jsonMeasurements.hashes.last,
        },
        ..._wireMetrics(
          fixtures: fixtures,
          jsonMeasurements: jsonMeasurements,
          protobufMeasurements: protobufMeasurements,
        ),
        'by_frame_kind': _metricsByFrameKind(fixtures),
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
      terminalFrameFromJson(
        (jsonDecode(fixture.jsonPayload) as Map).cast<String, Object?>(),
      );
      const TerminalProtobufFrameCodec().decode(fixture.protobufPayload);
    }
  }
}

List<_FrameWireFixture> _buildFixtures({
  required int frameCount,
  required int viewportRows,
  required int viewportCols,
  required String workload,
}) {
  return List<_FrameWireFixture>.generate(frameCount, (frameIndex) {
    final currentRows = _rowsForFrame(
      workload: workload,
      frameIndex: frameIndex,
      baseRows: viewportRows,
    );
    final currentCols = _colsForFrame(
      workload: workload,
      frameIndex: frameIndex,
      baseCols: viewportCols,
    );
    final previousRows = frameIndex == 0
        ? currentRows
        : _rowsForFrame(
            workload: workload,
            frameIndex: frameIndex - 1,
            baseRows: viewportRows,
          );
    final previousCols = frameIndex == 0
        ? currentCols
        : _colsForFrame(
            workload: workload,
            frameIndex: frameIndex - 1,
            baseCols: viewportCols,
          );
    final dimensionsChanged =
        frameIndex == 0 ||
        currentRows != previousRows ||
        currentCols != previousCols;
    final isSnapshot = workload == 'resize_churn'
        ? dimensionsChanged
        : frameIndex == 0 || frameIndex % 30 == 0;
    final dirtyStart = isSnapshot
        ? 0
        : workload == 'resize_churn'
        ? currentRows - 1
        : (frameIndex * 7) % (currentRows - 8);
    final dirtyEnd = isSnapshot
        ? currentRows
        : workload == 'resize_churn'
        ? currentRows
        : dirtyStart + 8;
    final rowIndexes = isSnapshot
        ? List<int>.generate(currentRows, (index) => index)
        : List<int>.generate(dirtyEnd - dirtyStart, (index) {
            return dirtyStart + index;
          });
    final rows = [
      for (final rowIndex in rowIndexes)
        _rowJson(
          frameIndex: frameIndex,
          rowIndex: rowIndex,
          viewportCols: currentCols,
        ),
    ];
    final protobufRows = [
      for (final rowIndex in rowIndexes)
        _rowProtobuf(
          frameIndex: frameIndex,
          rowIndex: rowIndex,
          viewportCols: currentCols,
        ),
    ];
    final cursorRow = rowIndexes.last;
    final cursorCol = (frameIndex * 11) % currentCols;
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
      'viewport_rows': currentRows,
      'viewport_cols': currentCols,
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
      viewportRows: currentRows,
      viewportCols: currentCols,
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
                placementId: Int64(frameIndex + 1),
                renderId: Int64(frameIndex + 1001),
                assetKey: frame_pb.TerminalGraphicAssetKey(
                  assetId: Int64(7),
                  assetVersion: Int64(frameIndex + 1),
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
      frameKind: isSnapshot ? 'snapshot' : 'delta',
    );
  }, growable: false);
}

int _rowsForFrame({
  required String workload,
  required int frameIndex,
  required int baseRows,
}) {
  if (workload != 'resize_churn') {
    return baseRows;
  }
  return switch ((frameIndex ~/ 8) % 4) {
    0 => baseRows,
    1 => (baseRows - 8).clamp(16, baseRows),
    2 => baseRows + 8,
    _ => (baseRows - 4).clamp(16, baseRows),
  };
}

int _colsForFrame({
  required String workload,
  required int frameIndex,
  required int baseCols,
}) {
  if (workload != 'resize_churn') {
    return baseCols;
  }
  return switch ((frameIndex ~/ 8) % 4) {
    0 => baseCols,
    1 => (baseCols - 20).clamp(80, baseCols),
    2 => baseCols + 16,
    _ => (baseCols - 12).clamp(80, baseCols),
  };
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

_DecodeMeasurements _measureJsonDecode(List<_FrameWireFixture> fixtures) {
  final rounds = <int>[];
  final hashes = <String>[];
  for (var iteration = 0; iteration < _iterations; iteration += 1) {
    final watch = Stopwatch()..start();
    for (final fixture in fixtures) {
      final frame = terminalFrameFromJson(
        (jsonDecode(fixture.jsonPayload) as Map).cast<String, Object?>(),
      );
      if (iteration == 0) {
        hashes.add(terminalBenchmarkViewportHash(frame));
      }
    }
    watch.stop();
    rounds.add(watch.elapsedMicroseconds);
  }
  return _DecodeMeasurements(rounds: rounds, hashes: hashes);
}

_DecodeMeasurements _measureProtobufDecode(List<_FrameWireFixture> fixtures) {
  final rounds = <int>[];
  final hashes = <String>[];
  for (var iteration = 0; iteration < _iterations; iteration += 1) {
    final watch = Stopwatch()..start();
    for (final fixture in fixtures) {
      final frame = const TerminalProtobufFrameCodec().decode(
        fixture.protobufPayload,
      );
      if (iteration == 0) {
        hashes.add(terminalBenchmarkViewportHash(frame));
      }
    }
    watch.stop();
    rounds.add(watch.elapsedMicroseconds);
  }
  return _DecodeMeasurements(rounds: rounds, hashes: hashes);
}

Map<String, Object?> _wireMetrics({
  required List<_FrameWireFixture> fixtures,
  required _DecodeMeasurements jsonMeasurements,
  required _DecodeMeasurements protobufMeasurements,
}) {
  final totalJsonBytes = fixtures.fold<int>(
    0,
    (sum, fixture) => sum + fixture.jsonPayloadBytes,
  );
  final totalProtobufBytes = fixtures.fold<int>(
    0,
    (sum, fixture) => sum + fixture.protobufPayload.length,
  );
  final jsonDecodeTotal = jsonMeasurements.totalMicros;
  final protobufDecodeTotal = protobufMeasurements.totalMicros;
  final sampleCount = fixtures.length * _iterations;
  return <String, Object?>{
    'json': <String, Object?>{
      'total_bytes': totalJsonBytes,
      'mean_bytes': totalJsonBytes / fixtures.length,
      'decode_round_micros': _distributionSummary(jsonMeasurements.rounds),
      'decode_mean_micros_per_frame': jsonDecodeTotal / sampleCount,
    },
    'protobuf': <String, Object?>{
      'total_bytes': totalProtobufBytes,
      'mean_bytes': totalProtobufBytes / fixtures.length,
      'decode_round_micros': _distributionSummary(protobufMeasurements.rounds),
      'decode_mean_micros_per_frame': protobufDecodeTotal / sampleCount,
    },
    'ratios': <String, Object?>{
      'protobuf_bytes_to_json': totalProtobufBytes / totalJsonBytes,
      'protobuf_decode_to_json': protobufDecodeTotal / jsonDecodeTotal,
    },
  };
}

Map<String, Object?> _metricsByFrameKind(List<_FrameWireFixture> fixtures) {
  final result = <String, Object?>{};
  for (final frameKind in const ['snapshot', 'delta']) {
    final group = fixtures
        .where((fixture) => fixture.frameKind == frameKind)
        .toList(growable: false);
    if (group.isEmpty) {
      continue;
    }
    final jsonMeasurements = _measureJsonDecode(group);
    final protobufMeasurements = _measureProtobufDecode(group);
    expect(protobufMeasurements.hashes, jsonMeasurements.hashes);
    result[frameKind] = <String, Object?>{
      'frame_count': group.length,
      'sample_count': group.length * _iterations,
      ..._wireMetrics(
        fixtures: group,
        jsonMeasurements: jsonMeasurements,
        protobufMeasurements: protobufMeasurements,
      ),
    };
  }
  return result;
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
    required this.frameKind,
  });

  final String jsonPayload;
  final Uint8List protobufPayload;
  final String frameKind;

  int get jsonPayloadBytes => utf8.encode(jsonPayload).length;
}

final class _DecodeMeasurements {
  const _DecodeMeasurements({required this.rounds, required this.hashes});

  final List<int> rounds;
  final List<String> hashes;

  int get totalMicros => rounds.fold<int>(0, (sum, value) => sum + value);
}
