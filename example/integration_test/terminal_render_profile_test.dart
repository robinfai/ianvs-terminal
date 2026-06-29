import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:integration_test/integration_test.dart';

import 'package:app/benchmarks/terminal_render_profile_report.dart';

import '../test/support/fake_pty_backend.dart';
import '../test/support/test_runtime.dart';

const String _configuredOutputDir = String.fromEnvironment(
  'IANVS_BENCH_PROFILE_OUTPUT',
  defaultValue: '',
);
const String _singleWorkload = String.fromEnvironment(
  'IANVS_BENCH_PROFILE_WORKLOAD',
  defaultValue: '',
);
const String _workloadList = String.fromEnvironment(
  'IANVS_BENCH_PROFILE_WORKLOADS',
  defaultValue:
      'burst_stdout_profile,scrollback_heavy_profile,resize_churn_profile',
);
const String _targetLabel = String.fromEnvironment(
  'IANVS_BENCH_PROFILE_TARGET_LABEL',
  defaultValue: '',
);
const int _frameCount = int.fromEnvironment(
  'IANVS_BENCH_PROFILE_FRAME_COUNT',
  defaultValue: 96,
);
const int _repeatCount = int.fromEnvironment(
  'IANVS_BENCH_PROFILE_REPEATS',
  defaultValue: 5,
);
const int _viewportRows = int.fromEnvironment(
  'IANVS_BENCH_PROFILE_ROWS',
  defaultValue: 40,
);
const int _viewportCols = int.fromEnvironment(
  'IANVS_BENCH_PROFILE_COLS',
  defaultValue: 120,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exports real Flutter render profile matrix', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2560, 1440);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final outputRoot = _profileOutputDirectory();
    final targetPlatform = Platform.operatingSystem;
    final targetDevice = _profileTargetDevice();
    final summaries = <Map<String, Object?>>[];
    final workloads = _profileWorkloads();
    expect(workloads, isNotEmpty);
    expect(_repeatCount, greaterThan(0));

    for (final workload in workloads) {
      for (var repeatIndex = 1; repeatIndex <= _repeatCount; repeatIndex += 1) {
        final runDir = Directory(
          '${outputRoot.path}/${_pathSegment(workload.name)}/repeat_$repeatIndex',
        );
        final summary = await _runProfileCase(
          binding: binding,
          tester: tester,
          workload: workload,
          repeatIndex: repeatIndex,
          outputDir: runDir,
          targetPlatform: targetPlatform,
          targetDevice: targetDevice,
        );
        summaries.add(summary);
      }
    }

    writeTerminalRenderProfileAggregateSummary(outputRoot, summaries);
  });
}

Future<Map<String, Object?>> _runProfileCase({
  required IntegrationTestWidgetsFlutterBinding binding,
  required WidgetTester tester,
  required _ProfileWorkload workload,
  required int repeatIndex,
  required Directory outputDir,
  required String targetPlatform,
  required String targetDevice,
}) async {
  final flutterRenderEvents = <Map<String, Object?>>[];
  final frameTimings = <FrameTiming>[];
  void handleTimings(List<FrameTiming> timings) {
    frameTimings.addAll(timings);
  }

  SchedulerBinding.instance.addTimingsCallback(handleTimings);

  final backend = FakePtyBackend();
  final runtime = testRuntime(backend);
  final viewportController = terminal.TerminalViewportController();
  final selectionController = terminal.SelectionController();
  final inputController = terminal.TerminalInputController(
    sessionId: '${workload.name}-$repeatIndex',
    runtime: runtime,
    readSelection: () => '',
    copySelection: (_) async {},
    readClipboard: () async => '',
  );

  try {
    var viewportSize = workload.viewportSizeForFrame(0);
    late StateSetter setHarnessState;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0EA5E9)),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF05070A),
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                setHarnessState = setState;
                return SizedBox(
                  width: viewportSize.width,
                  height: viewportSize.height,
                  child: terminal.TerminalViewport(
                    controller: viewportController,
                    selectionController: selectionController,
                    inputController: inputController,
                    onScrollLines: (_) {},
                    onScrollToOffset: (_) {},
                    backgroundColor: const Color(0xFF05070A),
                    foregroundColor: const Color(0xFFE5E7EB),
                    benchmarkEventSink: flutterRenderEvents.add,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    flutterRenderEvents.clear();
    frameTimings.clear();

    final frames = _profileFrames(workload);
    final oracleController = terminal.TerminalViewportController();
    for (final frame in frames) {
      oracleController.updateFrame(frame);
    }
    final expectedHash = terminal.terminalBenchmarkViewportHash(
      oracleController.frame,
    );

    final startedAt = DateTime.now().toUtc();
    await binding.traceAction(() async {
      for (var index = 0; index < frames.length; index += 1) {
        final nextSize = workload.viewportSizeForFrame(index);
        if (nextSize != viewportSize) {
          setHarnessState(() {
            viewportSize = nextSize;
          });
          await tester.pump();
        }
        viewportController.updateFrame(frames[index]);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 100));
    }, reportKey: 'ianvs_${workload.name}_repeat_$repeatIndex');
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    final completedAt = DateTime.now().toUtc();

    final actualHash = terminal.terminalBenchmarkViewportHash(
      viewportController.frame,
    );
    final timingEvents = frameTimings
        .map(terminal.terminalBenchmarkFrameTimingEvent)
        .toList(growable: false);

    expect(flutterRenderEvents, isNotEmpty);
    expect(
      timingEvents,
      isNotEmpty,
      reason: 'Run this target with flutter drive --profile on macOS.',
    );
    expect(actualHash, expectedHash);

    return writeTerminalRenderProfileReport(
      outputDir: outputDir,
      workload: workload.name,
      policy: 'real_flutter_profile',
      repeatIndex: repeatIndex,
      targetPlatform: targetPlatform,
      targetDevice: targetDevice,
      semanticGenerations: frames.length,
      flutterRenderEvents: flutterRenderEvents,
      flutterFrameTimingEvents: timingEvents,
      expectedViewportHash: expectedHash,
      actualViewportHash: actualHash,
      startedAt: startedAt,
      completedAt: completedAt,
    );
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(handleTimings);
    runtime.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
}

Directory _profileOutputDirectory() {
  if (_configuredOutputDir.isNotEmpty) {
    return Directory(_configuredOutputDir);
  }
  return Directory.systemTemp.createTempSync('ianvs_flutter_render_profile_');
}

String _profileTargetDevice() {
  if (_targetLabel.isNotEmpty) {
    return _targetLabel;
  }
  return '${Platform.operatingSystem}-${Platform.localHostname}';
}

List<_ProfileWorkload> _profileWorkloads() {
  final source = _singleWorkload.isNotEmpty ? _singleWorkload : _workloadList;
  return source
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .map(_ProfileWorkload.fromName)
      .toList(growable: false);
}

List<terminal.TerminalFrameDiff> _profileFrames(_ProfileWorkload workload) {
  final frames = <terminal.TerminalFrameDiff>[
    terminal.TerminalFrameDiff(
      frameKind: terminal.TerminalFrameKind.snapshot,
      rows: List<terminal.TerminalRow>.generate(
        workload.rowsForFrame(0),
        (row) => _profileRow(
          workloadName: workload.name,
          frameIndex: 0,
          rowIndex: row,
          viewportCols: workload.colsForFrame(0),
        ),
        growable: false,
      ),
      cursor: const terminal.TerminalCursor(row: 0, col: 0, visible: true),
      viewportRows: workload.rowsForFrame(0),
      viewportCols: workload.colsForFrame(0),
      dirtyRanges: [
        terminal.TerminalDirtyRange(start: 0, end: workload.rowsForFrame(0)),
      ],
      scrollbackOffset: 0,
      scrollbackMaxOffset: math.max(0, _frameCount - workload.rowsForFrame(0)),
      defaultForeground: const Color(0xFFE5E7EB),
      defaultBackground: const Color(0xFF05070A),
    ),
  ];

  for (var index = 1; index < _frameCount; index += 1) {
    final rows = workload.rowsForFrame(index);
    final cols = workload.colsForFrame(index);
    final previousRows = workload.rowsForFrame(index - 1);
    final previousCols = workload.colsForFrame(index - 1);
    final dimensionsChanged = rows != previousRows || cols != previousCols;
    frames.add(
      terminal.TerminalFrameDiff(
        frameKind: dimensionsChanged
            ? terminal.TerminalFrameKind.snapshot
            : terminal.TerminalFrameKind.delta,
        rows: _rowsForWorkloadFrame(workload, index, rows, cols),
        cursor: terminal.TerminalCursor(
          row: rows - 1,
          col: index % cols,
          visible: true,
        ),
        viewportRows: rows,
        viewportCols: cols,
        dirtyRanges: [
          dimensionsChanged || workload.kind == _ProfileWorkloadKind.burst
              ? terminal.TerminalDirtyRange(start: 0, end: rows)
              : terminal.TerminalDirtyRange(start: rows - 1, end: rows),
        ],
        scrollbackOffset: index,
        scrollbackMaxOffset: math.max(0, _frameCount - rows),
        viewportRowShift: dimensionsChanged ? 0 : workload.viewportRowShift,
        defaultForeground: const Color(0xFFE5E7EB),
        defaultBackground: const Color(0xFF05070A),
      ),
    );
  }

  return frames;
}

List<terminal.TerminalRow> _rowsForWorkloadFrame(
  _ProfileWorkload workload,
  int frameIndex,
  int viewportRows,
  int viewportCols,
) {
  if (workload.kind == _ProfileWorkloadKind.burst ||
      workload.kind == _ProfileWorkloadKind.resize &&
          frameIndex % _ProfileWorkload.resizeCadence == 0) {
    return List<terminal.TerminalRow>.generate(
      viewportRows,
      (row) => _profileRow(
        workloadName: workload.name,
        frameIndex: frameIndex,
        rowIndex: row,
        viewportCols: viewportCols,
      ),
      growable: false,
    );
  }

  return [
    _profileRow(
      workloadName: workload.name,
      frameIndex: frameIndex,
      rowIndex: viewportRows - 1,
      viewportCols: viewportCols,
    ),
  ];
}

terminal.TerminalRow _profileRow({
  required String workloadName,
  required int frameIndex,
  required int rowIndex,
  required int viewportCols,
}) {
  final text = _profileText(
    workloadName: workloadName,
    frameIndex: frameIndex,
    rowIndex: rowIndex,
    viewportCols: viewportCols,
  );
  final stylePivot = math.min(text.length, 48);
  return terminal.TerminalRow(
    index: rowIndex,
    text: text,
    styleRuns: [
      terminal.TerminalStyleRun(
        start: 0,
        end: math.min(text.length, 18),
        foreground: const Color(0xFF7DD3FC),
        bold: true,
      ),
      if (stylePivot < text.length)
        terminal.TerminalStyleRun(
          start: stylePivot,
          end: text.length,
          foreground: const Color(0xFFFDE68A),
          dim: frameIndex.isOdd,
        ),
    ],
  );
}

String _profileText({
  required String workloadName,
  required int frameIndex,
  required int rowIndex,
  required int viewportCols,
}) {
  final buffer = StringBuffer()
    ..write('frame=')
    ..write(frameIndex.toString().padLeft(4, '0'))
    ..write(' row=')
    ..write(rowIndex.toString().padLeft(2, '0'))
    ..write(' ')
    ..write(workloadName)
    ..write(' ianvs-terminal render-profile ');
  while (buffer.length < viewportCols) {
    buffer.write(' gpu-raster/cache/dirty-row ');
  }
  return buffer.toString().substring(0, viewportCols);
}

String _pathSegment(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return sanitized.isEmpty ? 'unknown' : sanitized;
}

enum _ProfileWorkloadKind { burst, scrollback, resize }

class _ProfileWorkload {
  const _ProfileWorkload({
    required this.name,
    required this.kind,
    required this.baseRows,
    required this.baseCols,
  });

  static const resizeCadence = 8;

  factory _ProfileWorkload.fromName(String name) {
    return switch (name) {
      'burst_stdout_profile' => const _ProfileWorkload(
        name: 'burst_stdout_profile',
        kind: _ProfileWorkloadKind.burst,
        baseRows: _viewportRows,
        baseCols: _viewportCols,
      ),
      'scrollback_heavy_profile' => const _ProfileWorkload(
        name: 'scrollback_heavy_profile',
        kind: _ProfileWorkloadKind.scrollback,
        baseRows: _viewportRows,
        baseCols: _viewportCols,
      ),
      'resize_churn_profile' => const _ProfileWorkload(
        name: 'resize_churn_profile',
        kind: _ProfileWorkloadKind.resize,
        baseRows: _viewportRows,
        baseCols: _viewportCols,
      ),
      _ => throw ArgumentError.value(name, 'name', 'Unknown profile workload'),
    };
  }

  final String name;
  final _ProfileWorkloadKind kind;
  final int baseRows;
  final int baseCols;

  int rowsForFrame(int frameIndex) {
    if (kind != _ProfileWorkloadKind.resize) {
      return baseRows;
    }
    return switch ((frameIndex ~/ resizeCadence) % 4) {
      0 => baseRows,
      1 => math.max(16, baseRows - 8),
      2 => baseRows + 8,
      _ => math.max(16, baseRows - 4),
    };
  }

  int colsForFrame(int frameIndex) {
    if (kind != _ProfileWorkloadKind.resize) {
      return baseCols;
    }
    return switch ((frameIndex ~/ resizeCadence) % 4) {
      0 => baseCols,
      1 => math.max(80, baseCols - 20),
      2 => baseCols + 16,
      _ => math.max(80, baseCols - 12),
    };
  }

  int get viewportRowShift {
    return switch (kind) {
      _ProfileWorkloadKind.burst => 0,
      _ProfileWorkloadKind.scrollback => -1,
      _ProfileWorkloadKind.resize => -1,
    };
  }

  Size viewportSizeForFrame(int frameIndex) {
    if (kind != _ProfileWorkloadKind.resize) {
      return const Size(1280, 720);
    }
    final cols = colsForFrame(frameIndex);
    final rows = rowsForFrame(frameIndex);
    return Size((cols * 10.0).clamp(960, 1440), (rows * 18.0).clamp(540, 820));
  }
}
