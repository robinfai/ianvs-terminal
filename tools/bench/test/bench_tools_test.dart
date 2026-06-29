import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../src/bench_config.dart';
import '../src/bench_policy.dart';
import '../src/bench_runner_core.dart';
import '../src/correctness_oracle.dart';
import '../src/flutter_profile_matrix.dart';
import '../src/flutter_profile_report_audit.dart';
import '../src/replay_terminal.dart';
import '../src/summary_analyzer.dart';
import '../src/workloads.dart';

void main() {
  group('BenchConfig', () {
    test(
      'parses ci smoke yaml into policies, workloads, viewport, and gates',
      () {
        final config = BenchConfig.fromYaml('''
suite: ianvs_terminal_bench_ci_smoke
version: 1
policies:
  frame:
    - snapshot_only
    - delta_coalesced
  render:
    - headless_state_only
workloads:
  - burst_stdout.seq_1000
  - scrollback_heavy.lines_1000
viewport:
  cols: 80
  rows: 24
repeat: 1
warmup_runs: 0
output_dir: build/bench-results-ci
collectors:
  rust_frame: true
  dart_runtime: true
  flutter_render: false
  flutter_frame_timing: false
gates:
  require_hash_match: true
  require_schema_valid: true
''');

        expect(config.suite, 'ianvs_terminal_bench_ci_smoke');
        expect(config.framePolicies, [
          BenchFramePolicy.snapshotOnly,
          BenchFramePolicy.deltaCoalesced,
        ]);
        expect(config.renderPolicies, [BenchRenderPolicy.headlessStateOnly]);
        expect(config.workloads, [
          'burst_stdout.seq_1000',
          'scrollback_heavy.lines_1000',
        ]);
        expect(config.viewportCols, 80);
        expect(config.viewportRows, 24);
        expect(config.collectors.flutterRender, isFalse);
        expect(config.gates.requireHashMatch, isTrue);
      },
    );
  });

  group('BenchWorkloadCatalog', () {
    test('generates deterministic workload bytes and metadata', () {
      final catalog = BenchWorkloadCatalog();
      final first = catalog.resolve('burst_stdout.seq_1000');
      final second = catalog.resolve('burst_stdout.seq_1000');

      expect(first.name, 'burst_stdout.seq_1000');
      expect(first.traceBytes, second.traceBytes);
      expect(utf8.decode(first.traceBytes), startsWith('1\n2\n3\n'));
      expect(first.expectedMetadata['requires_hash_match'], isTrue);
      expect(first.defaultCols, greaterThan(0));
      expect(first.defaultRows, greaterThan(0));
    });

    test('resize churn exposes deterministic resize steps', () {
      final workload = BenchWorkloadCatalog().resolve('resize_churn.tiny');

      expect(workload.resizeSteps, isNotEmpty);
      expect(workload.resizeSteps.first.cols, 120);
      expect(workload.resizeSteps.first.rows, 40);
      expect(workload.resizeSteps.last.cols, 80);
      expect(workload.resizeSteps.last.rows, 24);
    });
  });

  group('ReplayTerminalEngine', () {
    test('keeps final viewport hash equal while coalescing visual frames', () {
      final workload = BenchWorkloadCatalog().resolve('burst_stdout.seq_1000');
      final snapshot = ReplayTerminalEngine().run(
        workload: workload,
        framePolicy: BenchFramePolicy.snapshotOnly,
        renderPolicy: BenchRenderPolicy.headlessStateOnly,
        cols: 80,
        rows: 24,
        repeatIndex: 1,
      );
      final coalesced = ReplayTerminalEngine().run(
        workload: workload,
        framePolicy: BenchFramePolicy.deltaCoalesced,
        renderPolicy: BenchRenderPolicy.headlessStateOnly,
        cols: 80,
        rows: 24,
        repeatIndex: 1,
      );

      expect(coalesced.finalViewportHash, snapshot.finalViewportHash);
      expect(
        coalesced.rustFrameEvents.length,
        lessThan(snapshot.rustFrameEvents.length),
      );
      expect(
        snapshot.rustFrameEvents.every(
          (event) => event['frame_kind'] == 'snapshot',
        ),
        isTrue,
      );
      expect(
        coalesced.dartRuntimeEvents.every(
          (event) => event['schema_version'] == 'ianvs-bench-dart-runtime-v1',
        ),
        isTrue,
      );
    });
  });

  group('CorrectnessOracle', () {
    test('reports first divergent frame with enough diagnostics', () {
      final reference = BenchRunData(
        workload: 'burst_stdout.seq_1000',
        framePolicy: BenchFramePolicy.snapshotOnly,
        finalViewportHash: 'aaa',
        rustFrameEvents: const [
          {
            'frame_id': 1,
            'frame_kind': 'snapshot',
            'viewport_hash': 'aaa',
            'snapshot_fallback_reason': 'first_frame',
            'viewport_row_shift': 0,
            'rows_emitted': 24,
          },
        ],
      );
      final tested = BenchRunData(
        workload: 'burst_stdout.seq_1000',
        framePolicy: BenchFramePolicy.deltaCoalesced,
        finalViewportHash: 'bbb',
        rustFrameEvents: const [
          {
            'frame_id': 1,
            'frame_kind': 'delta',
            'viewport_hash': 'bbb',
            'snapshot_fallback_reason': null,
            'viewport_row_shift': 1,
            'rows_emitted': 1,
          },
        ],
      );

      final result = CorrectnessOracle.compare(
        reference: reference,
        tested: tested,
      );

      expect(result['hash_match'], isFalse);
      expect(result['reference_final_viewport_hash'], 'aaa');
      expect(result['tested_final_viewport_hash'], 'bbb');
      expect(result['first_divergence'], isA<Map<String, Object?>>());
      expect(
        (result['first_divergence'] as Map<String, Object?>)['frame_kind'],
        'delta',
      );
    });
  });

  group('SummaryAnalyzer', () {
    test(
      'writes stable csv and markdown while tolerating missing files',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'ianvs-bench-summary-',
        );
        addTearDown(() {
          if (dir.existsSync()) {
            dir.deleteSync(recursive: true);
          }
        });
        File('${dir.path}/metadata.json').writeAsStringSync(
          jsonEncode({
            'schema_version': 'ianvs-bench-metadata-v1',
            'workload': 'burst_stdout.seq_1000',
            'mode': {'frame_policy': 'delta_coalesced'},
            'repeat_index': 1,
          }),
        );
        File('${dir.path}/rust_frame.ndjson').writeAsStringSync(
          [
            jsonEncode({
              'schema_version': 'ianvs-bench-rust-frame-v1',
              'frame_id': 1,
              'semantic_generation': 1,
              'frame_kind': 'snapshot',
              'rows_emitted': 24,
              'viewport_rows': 24,
              'frame_build_micros': 100,
            }),
            jsonEncode({
              'schema_version': 'ianvs-bench-rust-frame-v1',
              'frame_id': 2,
              'semantic_generation': 1000,
              'frame_kind': 'delta',
              'rows_emitted': 1,
              'viewport_rows': 24,
              'frame_build_micros': 200,
            }),
          ].join('\n'),
        );
        File('${dir.path}/dart_runtime.ndjson').writeAsStringSync(
          '${jsonEncode({'schema_version': 'ianvs-bench-dart-runtime-v1', 'frame_id': 1, 'apply_frame_micros': 50})}\n',
        );
        File('${dir.path}/correctness.json').writeAsStringSync(
          jsonEncode({
            'schema_version': 'ianvs-bench-correctness-v1',
            'workload': 'burst_stdout.seq_1000',
            'reference_policy': 'snapshot_only',
            'tested_policy': 'delta_coalesced',
            'reference_final_viewport_hash': 'abc',
            'tested_final_viewport_hash': 'abc',
            'hash_match': true,
          }),
        );

        final summary = SummaryAnalyzer().summarizeRunDirectory(dir);

        expect(summary['hash_match'], isTrue);
        expect(summary['semantic_generations'], 1000);
        expect(summary['snapshot_count'], 1);
        expect(summary['delta_count'], 1);
        expect(summary['p95_frame_build_micros'], 200);
        expect(
          File('${dir.path}/summary.csv').readAsStringSync(),
          contains('workload,policy,repeat,hash_match,semantic_generations'),
        );
        expect(
          File('${dir.path}/summary.md').readAsStringSync(),
          contains('burst_stdout.seq_1000'),
        );
      },
    );
  });

  group('BenchRunnerCore', () {
    test(
      'runs ci smoke config and writes correctness plus top-level summary',
      () async {
        final outDir = await Directory.systemTemp.createTemp(
          'ianvs-bench-runner-',
        );
        addTearDown(() {
          if (outDir.existsSync()) {
            outDir.deleteSync(recursive: true);
          }
        });
        final config = BenchConfig.fromYaml('''
suite: ianvs_terminal_bench_ci_smoke
version: 1
policies:
  frame:
    - snapshot_only
    - delta_coalesced
  render:
    - headless_state_only
workloads:
  - burst_stdout.seq_1000
  - resize_churn.tiny
viewport:
  cols: 80
  rows: 24
repeat: 1
warmup_runs: 0
output_dir: ${outDir.path}
collectors:
  rust_frame: true
  dart_runtime: true
  flutter_render: false
  flutter_frame_timing: false
gates:
  require_hash_match: true
  require_schema_valid: true
''');

        final result = await BenchRunnerCore(
          clock: () => DateTime.utc(2026, 6, 29, 12),
        ).runConfig(config);

        expect(result.exitCode, 0);
        expect(
          File('${result.outputDirectory.path}/summary.csv').existsSync(),
          isTrue,
        );
        expect(
          File(
            '${result.outputDirectory.path}/burst_stdout.seq_1000/delta_coalesced/repeat_1/correctness.json',
          ).existsSync(),
          isTrue,
        );
        final correctness =
            jsonDecode(
                  File(
                    '${result.outputDirectory.path}/resize_churn.tiny/delta_coalesced/repeat_1/correctness.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        expect(correctness['hash_match'], isTrue);
      },
    );
  });

  group('FlutterProfileMatrix', () {
    const devicesJson = '''
[
  {
    "name": "macOS",
    "id": "macos",
    "targetPlatform": "darwin-arm64",
    "category": "desktop"
  },
  {
    "name": "Pixel 8",
    "id": "emulator-5554",
    "targetPlatform": "android-arm64",
    "category": "mobile"
  },
  {
    "name": "Chrome",
    "id": "chrome",
    "targetPlatform": "web-javascript",
    "category": "web"
  }
]
''';

    test('parses devices and filters web targets that cannot compile FFI', () {
      final devices = FlutterProfileDevice.parseMachineJson(devicesJson);
      final supported = devices.where((device) => device.isSupported).toList();
      final unsupported = devices
          .where((device) => !device.isSupported)
          .toList();

      expect(supported.map((device) => device.id), ['macos', 'emulator-5554']);
      expect(supported.first.targetPlatform, 'macos');
      expect(supported.last.targetPlatform, 'android');
      expect(unsupported.single.id, 'chrome');
      expect(unsupported.single.unsupportedReason, contains('dart:ffi'));
    });

    test('builds deterministic flutter drive args for a target device', () {
      final device = FlutterProfileDevice.parseMachineJson(
        devicesJson,
      ).firstWhere((device) => device.id == 'macos');

      final args = FlutterProfileMatrixCommand(
        device: device,
        outputRoot: 'build/profile-matrix',
        workloads: const ['burst_stdout_profile', 'scrollback_heavy_profile'],
        repeats: 5,
        frameCount: 96,
      ).flutterDriveArgs;

      expect(
        args,
        containsAllInOrder([
          'drive',
          '--driver=test_driver/integration_test.dart',
          '--target=integration_test/terminal_render_profile_test.dart',
          '-d',
          'macos',
          '--profile',
        ]),
      );
      expect(
        args,
        contains(
          '--dart-define=IANVS_BENCH_PROFILE_TARGET_LABEL=macos-darwin-arm64',
        ),
      );
      expect(
        args,
        contains(
          '--dart-define=IANVS_BENCH_PROFILE_OUTPUT=build/profile-matrix/macos-darwin-arm64',
        ),
      );
      expect(
        args,
        contains(
          '--dart-define=IANVS_BENCH_PROFILE_WORKLOADS=burst_stdout_profile,scrollback_heavy_profile',
        ),
      );
      expect(args, contains('--dart-define=IANVS_BENCH_PROFILE_REPEATS=5'));
      expect(
        args,
        contains('--dart-define=IANVS_BENCH_PROFILE_FRAME_COUNT=96'),
      );
    });

    test('reports a clear shortage when two native targets are required', () {
      final devices = FlutterProfileDevice.parseMachineJson(
        devicesJson,
      ).where((device) => device.id != 'emulator-5554').toList();

      expect(
        () => assertRequiredProfileTargetCount(devices, requiredCount: 2),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('requires 2 supported native Flutter targets, found 1'),
          ),
        ),
      );
    });

    test('builds a machine-readable target readiness report', () {
      final devices = FlutterProfileDevice.parseMachineJson(devicesJson);

      final readiness = FlutterProfileReadinessReport.fromDevices(
        devices,
        requiredTargetCount: 3,
      );
      final report = readiness.toJson();

      expect(
        report['schema_version'],
        'ianvs-bench-flutter-profile-readiness-v1',
      );
      expect(report['ready'], isFalse);
      expect(report['required_target_count'], 3);
      expect(report['supported_target_count'], 2);
      expect(
        ((report['supported_targets'] as List<Object?>)
                .cast<Map<String, Object?>>())
            .map((target) => target['id']),
        ['macos', 'emulator-5554'],
      );
      expect(
        ((report['unsupported_targets'] as List<Object?>)
                .cast<Map<String, Object?>>())
            .single,
        containsPair('id', 'chrome'),
      );
      expect(
        ((report['unsupported_targets'] as List<Object?>)
                .cast<Map<String, Object?>>())
            .single['reason'],
        contains('dart:ffi'),
      );
      expect(
        (report['failures'] as List<Object?>).single,
        contains('requires 3 supported native Flutter targets, found 2'),
      );
      final runbook = FlutterProfileReadinessRunbook(
        readiness: readiness,
        outputRoot: 'build/bench-results-profile/formal-run',
        readinessOutput:
            'build/bench-results-profile/formal-run/readiness.json',
        runbookOutput: 'build/bench-results-profile/formal-run/runbook.md',
        workloads: const ['burst_stdout_profile', 'resize_churn_profile'],
        repeats: 5,
        frameCount: 96,
      ).toMarkdown();

      expect(runbook, contains('# Flutter Profile Target Runbook'));
      expect(runbook, contains('Ready: `false`'));
      expect(runbook, contains('Missing native targets: `1`'));
      expect(runbook, contains('chrome'));
      expect(runbook, contains('dart:ffi'));
      expect(
        runbook,
        contains(
          'dart run tools/bench/runner/flutter_profile_matrix_runner.dart',
        ),
      );
      expect(runbook, contains('--runbook-output'));
      expect(
        runbook,
        contains('dart run tools/bench/analysis/flutter_profile_audit.dart'),
      );
    });

    test('parses runner options with formal multi-target gates', () {
      final options = FlutterProfileMatrixOptions.parse([
        '--output',
        'build/profile-formal',
        '--readiness-output',
        'build/profile-formal/readiness.json',
        '--runbook-output',
        'build/profile-formal/runbook.md',
        '--workloads',
        'burst_stdout_profile,resize_churn_profile',
        '--repeats',
        '5',
        '--frame-count',
        '96',
        '--require-target-count',
        '2',
        '--device',
        'macos',
        '--device',
        'emulator-5554',
        '--dry-run',
      ]);

      expect(options.outputRoot, 'build/profile-formal');
      expect(options.readinessOutput, 'build/profile-formal/readiness.json');
      expect(options.runbookOutput, 'build/profile-formal/runbook.md');
      expect(options.workloads, [
        'burst_stdout_profile',
        'resize_churn_profile',
      ]);
      expect(options.repeats, 5);
      expect(options.frameCount, 96);
      expect(options.requiredTargetCount, 2);
      expect(options.deviceIds, ['macos', 'emulator-5554']);
      expect(options.dryRun, isTrue);
    });
  });

  group('FlutterProfileReportAudit', () {
    test('merges multiple target matrices and validates formal gates', () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'ianvs-profile-audit-',
      );
      addTearDown(() {
        if (sandbox.existsSync()) {
          sandbox.deleteSync(recursive: true);
        }
      });
      final macosDir = Directory('${sandbox.path}/macos');
      final androidDir = Directory('${sandbox.path}/android');
      final outputDir = Directory('${sandbox.path}/formal');
      final readinessFile = File('${sandbox.path}/readiness.json')
        ..writeAsStringSync(
          jsonEncode({
            'schema_version': 'ianvs-bench-flutter-profile-readiness-v1',
            'ready': true,
          }),
        );
      final runbookFile = File('${sandbox.path}/runbook.md')
        ..writeAsStringSync('# runbook\n');
      const workloads = ['burst_stdout_profile', 'resize_churn_profile'];
      _writeSyntheticProfileMatrix(
        macosDir,
        targetPlatform: 'macos',
        targetDevice: 'macos-darwin-arm64',
        workloads: workloads,
        repeats: 2,
      );
      _writeSyntheticProfileMatrix(
        androidDir,
        targetPlatform: 'android',
        targetDevice: 'pixel8-android-arm64',
        workloads: workloads,
        repeats: 2,
      );

      final result =
          FlutterProfileReportAudit(
            requiredTargetCount: 2,
            requiredWorkloads: workloads,
            requiredRepeats: 2,
            readinessReportPath: readinessFile.path,
            runbookReportPath: runbookFile.path,
          ).audit(
            inputDirectories: [macosDir, androidDir],
            outputDirectory: outputDir,
          );

      expect(result.passed, isTrue);
      expect(result.targetCount, 2);
      expect(result.runCount, 8);
      expect(result.failures, isEmpty);
      expect(
        File('${outputDir.path}/formal_profile_summary.csv').readAsStringSync(),
        contains('pixel8-android-arm64'),
      );
      final auditJson =
          jsonDecode(
                File(
                  '${outputDir.path}/formal_profile_audit.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(auditJson['passed'], isTrue);
      expect(auditJson['target_count'], 2);
      final manifestJson =
          jsonDecode(
                File(
                  '${outputDir.path}/formal_profile_manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(
        manifestJson['schema_version'],
        'ianvs-bench-formal-profile-manifest-v1',
      );
      expect(manifestJson['input_directories'], [
        macosDir.path,
        androidDir.path,
      ]);
      expect(manifestJson['required_target_count'], 2);
      expect(manifestJson['required_repeats'], 2);
      expect(manifestJson['required_workloads'], workloads);
      expect(
        manifestJson['artifacts'],
        containsAll([
          'formal_profile_summary.csv',
          'formal_profile_audit.json',
          'formal_profile_report.md',
        ]),
      );
      expect(
        manifestJson['readiness_report'],
        containsPair('path', readinessFile.path),
      );
      expect(manifestJson['readiness_report'], containsPair('present', true));
      expect(
        manifestJson['runbook_report'],
        containsPair('path', runbookFile.path),
      );
      expect(manifestJson['runbook_report'], containsPair('present', true));
      final artifactFiles = (manifestJson['artifact_files'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        artifactFiles.map((artifact) => artifact['name']),
        containsAll([
          'formal_profile_summary.csv',
          'formal_profile_audit.json',
          'formal_profile_manifest.json',
          'formal_profile_report.md',
        ]),
      );
      expect(
        artifactFiles.firstWhere(
          (artifact) => artifact['name'] == 'formal_profile_report.md',
        )['byte_size'],
        greaterThan(0),
      );
      final reportMarkdown = File(
        '${outputDir.path}/formal_profile_report.md',
      ).readAsStringSync();
      expect(reportMarkdown, contains('Formal Flutter Profile Report'));
      expect(reportMarkdown, contains('## Performance Summary'));
      expect(
        reportMarkdown,
        contains(
          '| target | workload | repeats | hash matches | avg p95 total span | max p95 total span | missed vsync | row cache hit rate |',
        ),
      );
      expect(
        reportMarkdown,
        contains(
          '| macos-darwin-arm64 | burst_stdout_profile | 2 | 2 | 200.0000 | 200.0000 | 0 | 0.9000 |',
        ),
      );
      expect(
        reportMarkdown,
        contains(
          '| pixel8-android-arm64 | resize_churn_profile | 2 | 2 | 200.0000 | 200.0000 | 0 | 0.9000 |',
        ),
      );
    });

    test('fails when the formal target count is not met', () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'ianvs-profile-audit-short-',
      );
      addTearDown(() {
        if (sandbox.existsSync()) {
          sandbox.deleteSync(recursive: true);
        }
      });
      final macosDir = Directory('${sandbox.path}/macos');
      _writeSyntheticProfileMatrix(
        macosDir,
        targetPlatform: 'macos',
        targetDevice: 'macos-darwin-arm64',
        workloads: const ['burst_stdout_profile'],
        repeats: 1,
      );

      final result =
          FlutterProfileReportAudit(
            requiredTargetCount: 2,
            requiredWorkloads: const ['burst_stdout_profile'],
            requiredRepeats: 1,
          ).audit(
            inputDirectories: [macosDir],
            outputDirectory: Directory('${sandbox.path}/formal'),
          );

      expect(result.passed, isFalse);
      expect(
        result.failures,
        contains('requires at least 2 target devices, found 1'),
      );
    });
  });
}

void _writeSyntheticProfileMatrix(
  Directory root, {
  required String targetPlatform,
  required String targetDevice,
  required List<String> workloads,
  required int repeats,
}) {
  root.createSync(recursive: true);
  final rows = <String>[
    'target_platform,target_device,workload,policy,repeat,hash_match,semantic_generations,frame_diffs_generated,frames_presented,coalescing_ratio,snapshot_count,delta_count,avg_rows_emitted,p95_frame_build_micros,p95_apply_frame_micros,p95_build_duration_micros,p95_raster_duration_micros,p95_total_span_micros,p95_paint_micros,missed_vsync_count,row_cache_hit_rate',
  ];
  for (final workload in workloads) {
    for (var repeat = 1; repeat <= repeats; repeat += 1) {
      rows.add(
        '$targetPlatform,$targetDevice,$workload,real_flutter_profile,$repeat,true,12,12,12,1.0000,1,11,N/A,N/A,N/A,100,1,200,90,0,0.9000',
      );
      final runDir = Directory('${root.path}/$workload/repeat_$repeat')
        ..createSync(recursive: true);
      File('${runDir.path}/correctness.json').writeAsStringSync(
        jsonEncode({
          'schema_version': 'ianvs-bench-correctness-v1',
          'workload': workload,
          'hash_match': true,
        }),
      );
      File('${runDir.path}/flutter_frame_timing.ndjson').writeAsStringSync(
        '${jsonEncode({'schema_version': 'ianvs-bench-flutter-frame-timing-v1', 'total_span_micros': 200})}\n',
      );
      File('${runDir.path}/flutter_render.ndjson').writeAsStringSync(
        '${jsonEncode({'schema_version': 'ianvs-bench-flutter-render-v1', 'paint_micros': 90})}\n',
      );
    }
  }
  File('${root.path}/summary.csv').writeAsStringSync('${rows.join('\n')}\n');
}
