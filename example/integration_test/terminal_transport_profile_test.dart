import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:integration_test/integration_test.dart';

import 'package:app/benchmarks/terminal_render_profile_report.dart';

const String _configuredOutputDir = String.fromEnvironment(
  'IANVS_BENCH_TRANSPORT_PROFILE_OUTPUT',
  defaultValue: '',
);
const String _workloadList = String.fromEnvironment(
  'IANVS_BENCH_TRANSPORT_PROFILE_WORKLOADS',
  defaultValue:
      'burst_stdout_profile,scrollback_heavy_profile,resize_churn_profile',
);
const String _wireFormatList = String.fromEnvironment(
  'IANVS_BENCH_TRANSPORT_PROFILE_WIRE_FORMATS',
  defaultValue: 'protobuf,json',
);
const String _targetLabel = String.fromEnvironment(
  'IANVS_BENCH_TRANSPORT_PROFILE_TARGET_LABEL',
  defaultValue: '',
);
const int _frameCount = int.fromEnvironment(
  'IANVS_BENCH_TRANSPORT_PROFILE_FRAME_COUNT',
  defaultValue: 96,
);
const int _repeatCount = int.fromEnvironment(
  'IANVS_BENCH_TRANSPORT_PROFILE_REPEATS',
  defaultValue: 3,
);
const int _viewportRows = int.fromEnvironment(
  'IANVS_BENCH_TRANSPORT_PROFILE_ROWS',
  defaultValue: 40,
);
const int _viewportCols = int.fromEnvironment(
  'IANVS_BENCH_TRANSPORT_PROFILE_COLS',
  defaultValue: 120,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'exports end-to-end frame transport profile matrix',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(2560, 1440);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final outputRoot = Directory(_configuredOutputDir);
      final targetPlatform = Platform.operatingSystem;
      final targetDevice = _profileTargetDevice();
      final summaries = <Map<String, Object?>>[];
      final pairedHashes = <String, Map<String, String>>{};
      final workloads = _profileWorkloads();
      final wireFormats = _profileWireFormats();

      expect(workloads, isNotEmpty);
      expect(wireFormats, isNotEmpty);
      expect(_repeatCount, greaterThan(0));

      for (final wireFormat in wireFormats) {
        for (final workload in workloads) {
          for (
            var repeatIndex = 1;
            repeatIndex <= _repeatCount;
            repeatIndex += 1
          ) {
            final workloadLabel = '${wireFormat.name}_${workload.name}';
            final runDir = Directory(
              '${outputRoot.path}/${_pathSegment(workloadLabel)}/repeat_$repeatIndex',
            );
            final summary = await _runTransportProfileCase(
              binding: binding,
              tester: tester,
              wireFormat: wireFormat,
              workload: workload,
              workloadLabel: workloadLabel,
              repeatIndex: repeatIndex,
              outputDir: runDir,
              targetPlatform: targetPlatform,
              targetDevice: targetDevice,
            );
            summaries.add(summary);
            pairedHashes.putIfAbsent(
              '${workload.name}\u0000$repeatIndex',
              () => <String, String>{},
            )[wireFormat.name] = summary['actual_viewport_hash'] as String;
          }
        }
      }

      _assertPairedHashesMatch(pairedHashes);
      writeTerminalRenderProfileAggregateSummary(outputRoot, summaries);
      _writePairedHashes(outputRoot, pairedHashes);
    },
    skip: _configuredOutputDir.isEmpty || !Platform.isMacOS,
  );
}

Future<Map<String, Object?>> _runTransportProfileCase({
  required IntegrationTestWidgetsFlutterBinding binding,
  required WidgetTester tester,
  required _WireFormat wireFormat,
  required _ProfileWorkload workload,
  required String workloadLabel,
  required int repeatIndex,
  required Directory outputDir,
  required String targetPlatform,
  required String targetDevice,
}) async {
  final flutterRenderEvents = <Map<String, Object?>>[];
  final dartRuntimeEvents = <Map<String, Object?>>[];
  final frameTimings = <FrameTiming>[];
  void handleTimings(List<FrameTiming> timings) {
    frameTimings.addAll(timings);
  }

  SchedulerBinding.instance.addTimingsCallback(handleTimings);

  final backend = NativePtyBackend.load();
  final runtime = terminal.TerminalRuntimeController(
    backend: backend,
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: true,
    frameWireFormatPreference: wireFormat.preference,
    benchmarkEventSink: dartRuntimeEvents.add,
  );
  final sessionId = runtime.createSession(
    const terminal.TerminalSessionConfig(
      launch: terminal.TerminalLaunchConfig(
        program: '/bin/sh',
        args: ['-lc', 'stty -echo; exec /bin/cat'],
        env: {'LC_ALL': 'C'},
      ),
      shellIntegration: terminal.TerminalShellIntegrationConfig(enabled: false),
      graphics: terminal.TerminalGraphicsConfig(enabled: false),
    ),
  );
  final viewportController = runtime.viewportFor(sessionId);
  final selectionController = terminal.SelectionController();
  final inputController = terminal.TerminalInputController(
    sessionId: sessionId,
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
    runtime.resizeSessionCells(
      sessionId,
      cols: workload.colsForFrame(0),
      rows: workload.rowsForFrame(0),
      devicePixelRatio: 2,
      cellSize: const Size(10, 18),
    );
    await tester.pump(const Duration(milliseconds: 120));
    flutterRenderEvents.clear();
    dartRuntimeEvents.clear();
    frameTimings.clear();

    final startedAt = DateTime.now().toUtc();
    await binding.traceAction(
      () async {
        for (var index = 0; index < _frameCount; index += 1) {
          final nextSize = workload.viewportSizeForFrame(index);
          if (nextSize != viewportSize) {
            setHarnessState(() {
              viewportSize = nextSize;
            });
            runtime.resizeSessionCells(
              sessionId,
              cols: workload.colsForFrame(index),
              rows: workload.rowsForFrame(index),
              devicePixelRatio: 2,
              cellSize: const Size(10, 18),
            );
            await tester.pump();
          }

          runtime.sendInput(
            sessionId,
            Uint8List.fromList(utf8.encode(_inputForFrame(workload, index))),
          );
          await tester.pump(const Duration(milliseconds: 34));
        }
        await tester.pump(const Duration(milliseconds: 300));
      },
      reportKey:
          'ianvs_transport_${wireFormat.name}_${workload.name}_$repeatIndex',
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    final completedAt = DateTime.now().toUtc();

    final finalHash = terminal.terminalBenchmarkViewportHash(
      viewportController.frame,
    );
    final timingEvents = frameTimings
        .map(terminal.terminalBenchmarkFrameTimingEvent)
        .toList(growable: false);

    expect(flutterRenderEvents, isNotEmpty);
    expect(dartRuntimeEvents, isNotEmpty);
    expect(
      dartRuntimeEvents.map((event) => event['wire_format']).toSet(),
      <String>{wireFormat.runtimeWireName},
    );
    expect(
      timingEvents,
      isNotEmpty,
      reason: 'Run this target with flutter drive --profile on macOS.',
    );

    final summary = writeTerminalRenderProfileReport(
      outputDir: outputDir,
      workload: workloadLabel,
      policy: 'native_runtime_profile',
      repeatIndex: repeatIndex,
      targetPlatform: targetPlatform,
      targetDevice: targetDevice,
      semanticGenerations: _frameCount,
      flutterRenderEvents: flutterRenderEvents,
      flutterFrameTimingEvents: timingEvents,
      dartRuntimeEvents: dartRuntimeEvents,
      expectedViewportHash: finalHash,
      actualViewportHash: finalHash,
      startedAt: startedAt,
      completedAt: completedAt,
    );
    return <String, Object?>{...summary, 'actual_viewport_hash': finalHash};
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(handleTimings);
    runtime.closeSession(sessionId);
    runtime.dispose();
    selectionController.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
}

String _inputForFrame(_ProfileWorkload workload, int frameIndex) {
  final lines = workload.kind == _ProfileWorkloadKind.burst ? 4 : 1;
  final buffer = StringBuffer();
  for (var line = 0; line < lines; line += 1) {
    buffer
      ..write('frame=')
      ..write(frameIndex.toString().padLeft(4, '0'))
      ..write(' line=')
      ..write(line)
      ..write(' ')
      ..write(workload.name)
      ..write(' ianvs-terminal native-transport-profile ');
    while (buffer.length % 160 < 96) {
      buffer.write('payload ');
    }
    buffer.write('\n');
  }
  return buffer.toString();
}

String _profileTargetDevice() {
  if (_targetLabel.isNotEmpty) {
    return _targetLabel;
  }
  return '${Platform.operatingSystem}-${Platform.localHostname}';
}

List<_ProfileWorkload> _profileWorkloads() {
  return _workloadList
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .map(_ProfileWorkload.fromName)
      .toList(growable: false);
}

List<_WireFormat> _profileWireFormats() {
  return _wireFormatList
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .map(_WireFormat.fromName)
      .toList(growable: false);
}

void _assertPairedHashesMatch(Map<String, Map<String, String>> pairedHashes) {
  for (final entry in pairedHashes.entries) {
    final hashes = entry.value.values.toSet();
    expect(hashes, hasLength(1), reason: 'Mismatched hashes for ${entry.key}');
  }
}

void _writePairedHashes(
  Directory outputRoot,
  Map<String, Map<String, String>> pairedHashes,
) {
  final file = File('${outputRoot.path}/paired_hashes.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'schema_version': 'ianvs-bench-transport-profile-paired-hashes-v1',
      'pairs': pairedHashes.map((key, value) {
        final parts = key.split('\u0000');
        return MapEntry<String, Object?>(key, <String, Object?>{'workload': parts.first, 'repeat': int.parse(parts.last), 'hashes': value, 'match': value.values.toSet().length == 1});
      }),
    })}\n',
  );
}

String _pathSegment(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return sanitized.isEmpty ? 'unknown' : sanitized;
}

enum _WireFormat {
  protobuf,
  json;

  factory _WireFormat.fromName(String name) {
    return switch (name) {
      'protobuf' => _WireFormat.protobuf,
      'json' => _WireFormat.json,
      _ => throw ArgumentError.value(name, 'name', 'Unknown wire format'),
    };
  }

  terminal.TerminalFrameWireFormatPreference get preference {
    return switch (this) {
      _WireFormat.protobuf =>
        terminal.TerminalFrameWireFormatPreference.automatic,
      _WireFormat.json => terminal.TerminalFrameWireFormatPreference.json,
    };
  }

  String get runtimeWireName {
    return switch (this) {
      _WireFormat.protobuf => 'protobuf',
      _WireFormat.json => 'json',
    };
  }
}

enum _ProfileWorkloadKind { burst, scrollback, resize }

class _ProfileWorkload {
  const _ProfileWorkload({
    required this.name,
    required this.kind,
    required this.baseRows,
    required this.baseCols,
  });

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
    return switch ((frameIndex ~/ 8) % 4) {
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
    return switch ((frameIndex ~/ 8) % 4) {
      0 => baseCols,
      1 => math.max(80, baseCols - 20),
      2 => baseCols + 16,
      _ => math.max(80, baseCols - 12),
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
