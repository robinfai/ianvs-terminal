import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app/features/terminal/selection_controller.dart';
import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/current_terminal_frame_fixture.dart';
import '../support/fake_pty_backend.dart';
import '../support/test_runtime.dart';

const String _configuredOutDir = String.fromEnvironment(
  'CAT_LOG_BENCH_OUT_DIR',
  defaultValue: '',
);
const String _coreProfile = String.fromEnvironment(
  'CAT_LOG_BENCH_CORE_PROFILE',
  defaultValue: 'unknown',
);
const String _coreLibPath = String.fromEnvironment(
  'CAT_LOG_BENCH_CORE_LIB',
  defaultValue: '',
);
const double _droppedFrameThresholdMs = 16.67;
const String _urlHeavyScenario = 'url-heavy';
const int _urlProbeColumn = 24;

void main() {
  testWidgets('cat log benchmark exports metrics', (tester) async {
    final outDir = Directory(_configuredOutDir);
    final traceFile = File('${outDir.path}/cat-log-benchmark.trace.json');
    expect(traceFile.existsSync(), isTrue, reason: 'missing benchmark trace');

    final traceJson = (jsonDecode(traceFile.readAsStringSync()) as Map)
        .cast<String, Object?>();
    final scenario = traceJson['scenario'] as String? ?? 'bulk-output';
    final inputEcho = (traceJson['inputEcho'] as Map<Object?, Object?>?)
        ?.cast<String, Object?>();
    final pasteProbe = (traceJson['pasteProbe'] as Map<Object?, Object?>?)
        ?.cast<String, Object?>();
    final searchProbe = (traceJson['searchProbe'] as Map<Object?, Object?>?)
        ?.cast<String, Object?>();
    final viewport = (traceJson['viewport']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final frames = (traceJson['frames'] as List<dynamic>? ?? const [])
        .cast<Map<Object?, Object?>>()
        .map((frame) => frame.cast<String, Object?>())
        .toList(growable: false);
    expect(frames, isNotEmpty, reason: 'trace file contains no frames');
    final includesRawFrames = traceJson['includeRawFrames'] as bool? ?? true;
    final hasRawFrames = frames.any((frame) {
      final raw = frame['raw'] as String?;
      return raw != null && raw.isNotEmpty;
    });

    final devicePixelRatio =
        (viewport['devicePixelRatio'] as num?)?.toDouble() ?? 2.0;
    final viewportLogicalSize = Size(
      (viewport['logicalWidth'] as num?)?.toDouble() ?? 1280,
      (viewport['logicalHeight'] as num?)?.toDouble() ?? 720,
    );
    final pixelWidth =
        (viewport['pixelWidth'] as num?)?.toInt() ??
        (viewportLogicalSize.width * devicePixelRatio).round();
    final pixelHeight =
        (viewport['pixelHeight'] as num?)?.toInt() ??
        (viewportLogicalSize.height * devicePixelRatio).round();
    final viewportRows = (viewport['rows'] as num?)?.toInt() ?? 40;
    final viewportCols = (viewport['cols'] as num?)?.toInt() ?? 142;

    TerminalViewportController? viewportController;
    Size measuredCellSize = const Size(14, 22);
    final openedLinks = <String>[];
    if (hasRawFrames) {
      tester.view.devicePixelRatio = devicePixelRatio;
      tester.view.physicalSize = Size(
        viewportLogicalSize.width * devicePixelRatio,
        viewportLogicalSize.height * devicePixelRatio,
      );
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: 'cat-log-benchmark',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: viewportLogicalSize.width,
              height: viewportLogicalSize.height,
              child: TerminalViewport(
                controller: viewportController,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                onOpenLink: openedLinks.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      measuredCellSize = _terminalRenderObject(tester).debugCellSize;
    }
    final frameSamples = <Map<String, Object?>>[];
    final frameDurationsMicros = <int>[];
    final jsonSizes = <int>[];
    final rowCounts = <int>[];
    final dirtyRowCounts = <int>[];
    final rebuiltRowCounts = <int>[];
    final paintedRowCounts = <int>[];
    final viewportRowShifts = <int>[];
    final rowsScanned = <int>[];
    final frameBuildMicros = <int>[];
    final stateLockWaitMicros = <int>[];
    final frameExtractMicros = <int>[];
    final jsonEncodeMicros = <int>[];
    final fallbackReasons = <String>[];

    for (final frameEntry in frames) {
      final rawFrame = frameEntry['raw'] as String?;
      final jsonBytes =
          (frameEntry['jsonBytes'] as num?)?.toInt() ??
          (rawFrame == null ? 0 : utf8.encode(rawFrame).length);
      var durationMicros = 0;
      var rebuiltRows = 0;
      var paintedRows = 0;
      var dirtyRowCount = (frameEntry['dirtyRowCount'] as num?)?.toInt() ?? 0;
      var frameKind = frameEntry['frameKind'] as String? ?? 'snapshot';
      var rowCount = (frameEntry['rowCount'] as num?)?.toInt() ?? 0;
      var scrollbackOffset =
          (frameEntry['scrollbackOffset'] as num?)?.toInt() ?? 0;
      var dirtyRanges = const <Map<String, int>>[];

      if (rawFrame != null && rawFrame.isNotEmpty) {
        final decodeWatch = Stopwatch()..start();
        final incomingFrame = terminalFrameFixtureFromJson(
          (jsonDecode(rawFrame) as Map).cast<String, Object?>(),
        );
        viewportController!.updateFrame(incomingFrame);
        await tester.pump();
        decodeWatch.stop();

        final renderObject = _terminalRenderObject(tester);
        durationMicros = decodeWatch.elapsedMicroseconds;
        rebuiltRows = renderObject.debugLastRebuiltRowIndexes.length;
        paintedRows = renderObject.debugLastPaintedRowTexts.length;
        dirtyRowCount = _dirtyRowCount(incomingFrame.dirtyRanges);
        frameKind = incomingFrame.frameKind.name;
        rowCount = incomingFrame.rows.length;
        scrollbackOffset = incomingFrame.scrollbackOffset;
        dirtyRanges = incomingFrame.dirtyRanges
            .map(
              (range) => <String, int>{'start': range.start, 'end': range.end},
            )
            .toList(growable: false);
      }

      final viewportRowShift =
          (frameEntry['viewportRowShift'] as num?)?.toInt() ?? 0;
      final rustRowsScanned = (frameEntry['rowsScanned'] as num?)?.toInt() ?? 0;
      final rustFrameBuildMicros =
          (frameEntry['frameBuildMicros'] as num?)?.toInt() ?? 0;
      final rustStateLockWaitMicros =
          (frameEntry['stateLockWaitMicros'] as num?)?.toInt() ?? 0;
      final rustFrameExtractMicros =
          (frameEntry['frameExtractMicros'] as num?)?.toInt() ?? 0;
      final rustJsonEncodeMicros =
          (frameEntry['jsonEncodeMicros'] as num?)?.toInt() ?? 0;
      final snapshotFallbackReason =
          frameEntry['snapshotFallbackReason'] as String?;
      frameDurationsMicros.add(durationMicros);
      jsonSizes.add(jsonBytes);
      rowCounts.add(rowCount);
      dirtyRowCounts.add(dirtyRowCount);
      rebuiltRowCounts.add(rebuiltRows);
      paintedRowCounts.add(paintedRows);
      viewportRowShifts.add(viewportRowShift.abs());
      rowsScanned.add(rustRowsScanned);
      frameBuildMicros.add(rustFrameBuildMicros);
      stateLockWaitMicros.add(rustStateLockWaitMicros);
      frameExtractMicros.add(rustFrameExtractMicros);
      jsonEncodeMicros.add(rustJsonEncodeMicros);
      if (snapshotFallbackReason != null && snapshotFallbackReason.isNotEmpty) {
        fallbackReasons.add(snapshotFallbackReason);
      }
      frameSamples.add(<String, Object?>{
        'index': frameSamples.length,
        'frameKind': frameKind,
        'durationMicros': durationMicros,
        'jsonBytes': jsonBytes,
        'rowCount': rowCount,
        'rowsScanned': rustRowsScanned,
        'frameBuildMicros': rustFrameBuildMicros,
        'stateLockWaitMicros': rustStateLockWaitMicros,
        'frameExtractMicros': rustFrameExtractMicros,
        'jsonEncodeMicros': rustJsonEncodeMicros,
        'snapshotFallbackReason': snapshotFallbackReason,
        'dirtyRowCount': dirtyRowCount,
        'rebuiltRowCount': rebuiltRows,
        'paintedRowCount': paintedRows,
        'scrollbackOffset': scrollbackOffset,
        'viewportRowShift': viewportRowShift,
        'dirtyRanges': dirtyRanges,
      });
    }

    expect(frameSamples, isNotEmpty);
    final visibleUrlProbe = hasRawFrames && scenario == _urlHeavyScenario
        ? await _probeVisibleUrlLinks(
            tester: tester,
            measuredCellSize: measuredCellSize,
            frame: viewportController!.frame,
            openedLinks: openedLinks,
          )
        : null;

    final metricsFile = File('${outDir.path}/cat-log-benchmark.metrics.json');
    final metrics = <String, Object?>{
      'captureMode': 'cat_log_benchmark',
      'scenario': scenario,
      'fixturePath': traceJson['fixturePath'],
      'tracePath': traceFile.path,
      'traceBytes': traceFile.lengthSync(),
      'coreProfile': _coreProfile,
      'coreLibPath': _coreLibPath,
      'fixtureBytes': traceJson['fixtureBytes'] ?? 0,
      'includeRawFrames': includesRawFrames,
      'rawFrameCount': frames
          .where((frame) => (frame['raw'] as String?)?.isNotEmpty ?? false)
          .length,
      'viewport': <String, Object?>{
        'logicalWidth': viewportLogicalSize.width,
        'logicalHeight': viewportLogicalSize.height,
        'devicePixelRatio': devicePixelRatio,
        'pixelWidth': pixelWidth,
        'pixelHeight': pixelHeight,
        'rows': viewportRows,
        'cols': viewportCols,
        'cellSize': <String, double>{
          'width': measuredCellSize.width,
          'height': measuredCellSize.height,
        },
      },
      'summary': <String, Object?>{
        'frameCount': frameSamples.length,
        'traceFrameCount': frames.length,
        'sessionDebugStats':
            (traceJson['summary'] as Map?)?['sessionDebugStats'],
        'snapshotRatio': _ratio(
          frameSamples
              .where((sample) => sample['frameKind'] == 'snapshot')
              .length,
          frameSamples.length,
        ),
        'deltaRatio': _ratio(
          frameSamples.where((sample) => sample['frameKind'] == 'delta').length,
          frameSamples.length,
        ),
        'totalJsonBytes': jsonSizes.fold<int>(0, (sum, value) => sum + value),
        'totalRowsEmitted': frames.fold<int>(
          0,
          (sum, frame) => sum + ((frame['rowsEmitted'] as num?)?.toInt() ?? 0),
        ),
        'durationMs': _distributionSummary(frameDurationsMicros, scale: 1000),
        'jsonBytes': _distributionSummary(jsonSizes),
        'rowCount': _distributionSummary(rowCounts),
        'dirtyRowCount': _distributionSummary(dirtyRowCounts),
        'rowsScanned': _distributionSummary(rowsScanned),
        'frameBuildMicros': _distributionSummary(frameBuildMicros),
        'stateLockWaitMicros': _distributionSummary(stateLockWaitMicros),
        'frameExtractMicros': _distributionSummary(frameExtractMicros),
        'jsonEncodeMicros': _distributionSummary(jsonEncodeMicros),
        'rebuiltRowCount': _distributionSummary(rebuiltRowCounts),
        'paintedRowCount': _distributionSummary(paintedRowCounts),
        'viewportRowShiftAbs': _distributionSummary(viewportRowShifts),
        'fallbackReasons': _frequencySummary(fallbackReasons),
        if (inputEcho != null)
          'inputEcho': <String, Object?>{
            'observed': inputEcho['observed'] as bool? ?? false,
            'inputToDisplayMicros': inputEcho['inputToDisplayMicros'],
          },
        if (pasteProbe != null)
          'pasteProbe': <String, Object?>{
            'observed': pasteProbe['observed'] as bool? ?? false,
            'inputToDisplayMicros': pasteProbe['inputToDisplayMicros'],
            'payloadBytes': pasteProbe['payloadBytes'],
            'payloadLines': pasteProbe['payloadLines'],
          },
        'searchProbe': ?searchProbe,
        'visibleUrlProbe': ?visibleUrlProbe,
        'droppedFrames': <String, Object?>{
          'thresholdMs': _droppedFrameThresholdMs,
          'count': frameDurationsMicros
              .where((value) => value / 1000.0 > _droppedFrameThresholdMs)
              .length,
          'ratio': frameDurationsMicros.isEmpty
              ? 0
              : frameDurationsMicros
                        .where(
                          (value) => value / 1000.0 > _droppedFrameThresholdMs,
                        )
                        .length /
                    frameDurationsMicros.length,
        },
        'frameKinds': <String, int>{
          'snapshot': frameSamples
              .where((sample) => sample['frameKind'] == 'snapshot')
              .length,
          'delta': frameSamples
              .where((sample) => sample['frameKind'] == 'delta')
              .length,
        },
      },
      'frames': frameSamples,
    };
    metricsFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(metrics),
    );
    metrics['metricsBytes'] = metricsFile.lengthSync();
    metricsFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(metrics),
    );
  }, skip: _configuredOutDir.isEmpty);
}

RenderTerminalViewport _terminalRenderObject(WidgetTester tester) {
  return tester.allRenderObjects.whereType<RenderTerminalViewport>().last;
}

Future<Map<String, Object?>> _probeVisibleUrlLinks({
  required WidgetTester tester,
  required Size measuredCellSize,
  required TerminalFrameDiff frame,
  required List<String> openedLinks,
}) async {
  final renderObject = _terminalRenderObject(tester);
  final urlRows = frame.rows
      .where((row) => row.text.contains('https://'))
      .map((row) => row.index)
      .toList(growable: false);
  expect(urlRows, isNotEmpty, reason: 'url-heavy trace should expose URLs');
  final probeRows = <int>{
    urlRows.first,
    urlRows[urlRows.length ~/ 2],
  }.toList(growable: false);
  final openedBefore = openedLinks.length;
  final watch = Stopwatch()..start();
  for (final row in probeRows) {
    final probePosition = renderObject.localToGlobal(
      Offset(
        (_urlProbeColumn + 0.5) * measuredCellSize.width,
        (row + 0.5) * measuredCellSize.height,
      ),
    );
    await tester.tapAt(probePosition);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
  }
  watch.stop();
  final openedDuringProbe = openedLinks
      .skip(openedBefore)
      .toList(growable: false);
  expect(
    openedDuringProbe,
    hasLength(probeRows.length),
    reason: 'url-heavy probe should open one visible URL per tapped row',
  );
  return <String, Object?>{
    'attempts': probeRows.length,
    'openedCount': openedDuringProbe.length,
    'elapsedMicros': watch.elapsedMicroseconds,
    'links': openedDuringProbe,
  };
}

int _dirtyRowCount(List<TerminalDirtyRange> ranges) {
  var total = 0;
  for (final range in ranges) {
    total += math.max(0, range.end - range.start);
  }
  return total;
}

Map<String, Object?> _distributionSummary(
  List<int> values, {
  double scale = 1,
}) {
  if (values.isEmpty) {
    return <String, Object?>{
      'count': 0,
      'min': 0,
      'max': 0,
      'mean': 0,
      'p50': 0,
      'p95': 0,
      'total': 0,
    };
  }

  final sorted = values.toList()..sort();
  final total = values.fold<int>(0, (sum, value) => sum + value);
  double scaled(int value) => value / scale;

  return <String, Object?>{
    'count': values.length,
    'min': scaled(sorted.first),
    'max': scaled(sorted.last),
    'mean': scaled(total) / values.length,
    'p50': scaled(_percentile(sorted, 0.50)),
    'p95': scaled(_percentile(sorted, 0.95)),
    'total': scaled(total),
  };
}

int _percentile(List<int> sorted, double percentile) {
  if (sorted.length == 1) {
    return sorted.single;
  }
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index.clamp(0, sorted.length - 1)];
}

Map<String, int> _frequencySummary(List<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

double _ratio(int count, int total) {
  if (total == 0) {
    return 0;
  }
  return count / total;
}
