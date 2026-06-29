import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/benchmarks/terminal_render_profile_report.dart';

void main() {
  test('writes Flutter render profile events and summary artifacts', () {
    final outputDir = Directory.systemTemp.createTempSync(
      'ianvs_flutter_profile_report_test_',
    );
    addTearDown(() {
      if (outputDir.existsSync()) {
        outputDir.deleteSync(recursive: true);
      }
    });

    final summary = writeTerminalRenderProfileReport(
      outputDir: outputDir,
      workload: 'scrollback_heavy_profile',
      policy: 'real_flutter_profile',
      repeatIndex: 1,
      targetPlatform: 'macos',
      targetDevice: 'MacBook Pro',
      semanticGenerations: 3,
      flutterRenderEvents: const [
        {
          'schema_version': 'ianvs-bench-flutter-render-v1',
          'frame_version': 1,
          'frame_kind': 'snapshot',
          'viewport_rows': 2,
          'row_cache_hits': 0,
          'row_cache_misses': 2,
          'paint_micros': 100,
        },
        {
          'schema_version': 'ianvs-bench-flutter-render-v1',
          'frame_version': 2,
          'frame_kind': 'delta',
          'viewport_rows': 2,
          'row_cache_hits': 1,
          'row_cache_misses': 1,
          'paint_micros': 75,
        },
      ],
      flutterFrameTimingEvents: const [
        {
          'schema_version': 'ianvs-bench-flutter-frame-timing-v1',
          'build_duration_micros': 1000,
          'raster_duration_micros': 2000,
          'total_span_micros': 3000,
          'missed_vsync': false,
        },
        {
          'schema_version': 'ianvs-bench-flutter-frame-timing-v1',
          'build_duration_micros': 1200,
          'raster_duration_micros': 2500,
          'total_span_micros': 3700,
          'missed_vsync': false,
        },
      ],
      expectedViewportHash: 'abcdef01',
      actualViewportHash: 'abcdef01',
    );

    expect(summary['frames_presented'], 2);
    expect(summary['target_platform'], 'macos');
    expect(summary['target_device'], 'MacBook Pro');
    expect(summary['p95_build_duration_micros'], 1200);
    expect(summary['p95_total_span_micros'], 3700);
    expect(summary['p95_raster_duration_micros'], 2500);
    expect(summary['p95_paint_micros'], 100);
    expect(summary['missed_vsync_count'], 0);
    expect(summary['row_cache_hit_rate'], 1 / 4);

    final metadata = _readJson(outputDir, 'metadata.json');
    expect(metadata['schema_version'], 'ianvs-bench-metadata-v1');
    expect(metadata['workload'], 'scrollback_heavy_profile');
    expect(metadata['target'], {
      'platform': 'macos',
      'device': 'MacBook Pro',
      'flutter_mode': 'profile',
    });

    final correctness = _readJson(outputDir, 'correctness.json');
    expect(correctness['schema_version'], 'ianvs-bench-correctness-v1');
    expect(correctness['hash_match'], isTrue);

    expect(_readLines(outputDir, 'flutter_render.ndjson'), hasLength(2));
    expect(_readLines(outputDir, 'flutter_frame_timing.ndjson'), hasLength(2));
    expect(File('${outputDir.path}/summary.csv').existsSync(), isTrue);
    expect(File('${outputDir.path}/summary.md').existsSync(), isTrue);
  });

  test('writes aggregate summary for multiple profile runs', () {
    final outputDir = Directory.systemTemp.createTempSync(
      'ianvs_flutter_profile_aggregate_test_',
    );
    addTearDown(() {
      if (outputDir.existsSync()) {
        outputDir.deleteSync(recursive: true);
      }
    });

    writeTerminalRenderProfileAggregateSummary(outputDir, const [
      {
        'target_platform': 'macos',
        'target_device': 'MacBook Pro',
        'workload': 'burst_stdout_profile',
        'policy': 'real_flutter_profile',
        'repeat': 1,
        'hash_match': true,
        'frames_presented': 96,
        'p95_total_span_micros': 1800,
        'missed_vsync_count': 0,
        'row_cache_hit_rate': 0.5,
      },
      {
        'target_platform': 'macos',
        'target_device': 'MacBook Pro',
        'workload': 'burst_stdout_profile',
        'policy': 'real_flutter_profile',
        'repeat': 2,
        'hash_match': true,
        'frames_presented': 104,
        'p95_total_span_micros': 2200,
        'missed_vsync_count': 1,
        'row_cache_hit_rate': 0.7,
      },
      {
        'target_platform': 'macos',
        'target_device': 'MacBook Pro',
        'workload': 'resize_churn_profile',
        'policy': 'real_flutter_profile',
        'repeat': 1,
        'hash_match': false,
        'frames_presented': 80,
        'p95_total_span_micros': 2600,
        'missed_vsync_count': 2,
        'row_cache_hit_rate': 0.9,
      },
    ]);

    final csvLines = _readLines(outputDir, 'summary.csv');
    expect(csvLines, hasLength(4));
    expect(csvLines.first, contains('target_platform,target_device'));
    expect(csvLines[1], contains('burst_stdout_profile'));
    expect(csvLines[3], contains('resize_churn_profile'));

    final groupedLines = _readLines(outputDir, 'summary_by_workload.csv');
    expect(groupedLines, hasLength(3));
    expect(groupedLines.first, contains('repeat_count'));
    expect(groupedLines[1], contains('burst_stdout_profile'));
    expect(groupedLines[1], contains('2'));
    expect(groupedLines[1], contains('2000.0000'));
    expect(groupedLines[2], contains('resize_churn_profile'));
    expect(groupedLines[2], contains('0'));

    final markdown = File('${outputDir.path}/summary.md').readAsStringSync();
    expect(markdown, contains('Flutter Render Profile Matrix Summary'));
    expect(markdown, contains('burst_stdout_profile'));
    expect(markdown, contains('resize_churn_profile'));
  });
}

Map<String, Object?> _readJson(Directory dir, String name) {
  final decoded = jsonDecode(File('${dir.path}/$name').readAsStringSync());
  return (decoded as Map).cast<String, Object?>();
}

List<String> _readLines(Directory dir, String name) {
  return File('${dir.path}/$name').readAsLinesSync();
}
