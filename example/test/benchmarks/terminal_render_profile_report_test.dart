import 'dart:convert';
import 'dart:io';

import 'package:app/benchmarks/terminal_render_profile_report.dart';
import 'package:flutter_test/flutter_test.dart';

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
          'paint_kind': 'non_frame',
          'paint_micros': 60,
        },
        {
          'schema_version': 'ianvs-bench-flutter-render-v1',
          'frame_version': 2,
          'frame_kind': 'delta',
          'viewport_rows': 2,
          'row_cache_hits': 1,
          'row_cache_misses': 1,
          'paint_kind': 'non_frame',
          'paint_micros': 100,
        },
        {
          'schema_version': 'ianvs-bench-flutter-cursor-v1',
          'paint_micros': 12,
          'paint_bounds_area': 120,
          'cell_width_px': 10,
          'cell_height_px': 20,
          'device_pixel_ratio': 2,
          'cursor_picture_live_count': 1,
          'cursor_picture_estimated_bytes': 6400,
          'overlay_layer_count': 1,
        },
        {
          'schema_version': 'ianvs-bench-flutter-cursor-v1',
          'paint_micros': 20,
          'paint_bounds_area': 200,
          'cell_width_px': 10,
          'cell_height_px': 20,
          'device_pixel_ratio': 2,
          'cursor_picture_live_count': 1,
          'cursor_picture_estimated_bytes': 6400,
          'overlay_layer_count': 1,
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
    expect(summary['p50_surface_paint_micros'], 60);
    expect(summary['p95_surface_paint_micros'], 100);
    expect(summary['p50_cursor_paint_micros'], 12);
    expect(summary['p95_cursor_paint_micros'], 20);
    expect(summary['p50_build_duration_micros'], isA<num>());
    expect(summary['p95_build_duration_micros'], isA<num>());
    expect(summary['p50_raster_duration_micros'], isA<num>());
    expect(summary['p95_raster_duration_micros'], isA<num>());
    expect(summary['p50_total_span_micros'], isA<num>());
    expect(summary['p95_total_span_micros'], isA<num>());
    expect(summary['max_cursor_paint_bounds_area'], 200);
    expect(summary['max_cursor_picture_live_count'], 1);
    expect(summary['max_cursor_picture_estimated_bytes'], 6400);
    expect(summary['max_overlay_layer_count'], 1);
    expect(summary['missed_vsync_metric_valid'], isTrue);
    expect(summary['overlay_layer_count_metric_valid'], isTrue);
    expect(summary['cursor_paint_bounds_metric_valid'], isTrue);
    expect(summary['cursor_cell_width_metric_valid'], isTrue);
    expect(summary['cursor_cell_height_metric_valid'], isTrue);
    expect(summary['cursor_device_pixel_ratio_metric_valid'], isTrue);
    expect(summary['cursor_picture_live_count_metric_valid'], isTrue);
    expect(summary['cursor_picture_estimated_bytes_metric_valid'], isTrue);
    expect(summary['cursor_paint_bounds_violation_count'], 0);
    expect(summary['cursor_picture_estimated_bytes_violation_count'], 0);
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

    expect(_readLines(outputDir, 'flutter_render.ndjson'), hasLength(4));
    expect(_readLines(outputDir, 'flutter_frame_timing.ndjson'), hasLength(2));
    final summaryCsv = _readLines(outputDir, 'summary.csv');
    expect(summaryCsv, hasLength(2));
    final headerColumns = summaryCsv.first.split(',');
    final valueColumns = summaryCsv.last.split(',');
    expect(valueColumns, hasLength(headerColumns.length));
    expect(
      headerColumns,
      containsAllInOrder(<String>[
        'p50_surface_paint_micros',
        'p95_surface_paint_micros',
        'p50_cursor_paint_micros',
        'p95_cursor_paint_micros',
        'missed_vsync_metric_valid',
        'cursor_paint_bounds_violation_count',
        'cursor_picture_estimated_bytes_violation_count',
      ]),
    );
    expect(File('${outputDir.path}/summary.md').existsSync(), isTrue);
  });

  test(
    'marks incomplete frame timing samples instead of using partial data',
    () {
      final outputDir = Directory.systemTemp.createTempSync(
        'ianvs_flutter_profile_incomplete_timing_test_',
      );
      addTearDown(() => outputDir.deleteSync(recursive: true));

      final summary = writeTerminalRenderProfileReport(
        outputDir: outputDir,
        workload: 'cursor_blink_idle_surface_profile',
        policy: 'real_flutter_profile',
        repeatIndex: 1,
        targetPlatform: 'macos',
        targetDevice: 'macos-darwin',
        semanticGenerations: 1,
        flutterRenderEvents: const <Map<String, Object?>>[],
        flutterFrameTimingEvents: const <Map<String, Object?>>[
          <String, Object?>{
            'build_duration_micros': 10,
            'raster_duration_micros': 20,
            'total_span_micros': 30,
            'missed_vsync': false,
          },
          <String, Object?>{
            'build_duration_micros': 11,
            'total_span_micros': 31,
          },
        ],
        expectedViewportHash: 'same',
        actualViewportHash: 'same',
      );

      expect(summary['p95_build_duration_micros'], 11);
      expect(summary['p95_raster_duration_micros'], 'N/A');
      expect(summary['p50_raster_duration_micros'], 'N/A');
      expect(summary['p95_total_span_micros'], 31);
      expect(summary['missed_vsync_metric_valid'], isFalse);
    },
  );

  test(
    'surface cursor workload records the known overlay layer count as zero',
    () {
      final outputDir = Directory.systemTemp.createTempSync(
        'ianvs_flutter_profile_surface_layer_test_',
      );
      addTearDown(() => outputDir.deleteSync(recursive: true));

      final summary = writeTerminalRenderProfileReport(
        outputDir: outputDir,
        workload: 'cursor_blink_idle_surface_profile',
        policy: 'real_flutter_profile',
        repeatIndex: 1,
        targetPlatform: 'macos',
        targetDevice: 'macos-darwin',
        semanticGenerations: 1,
        flutterRenderEvents: const <Map<String, Object?>>[
          <String, Object?>{
            'schema_version': 'ianvs-bench-flutter-render-v1',
            'frame_version': 1,
            'frame_kind': 'snapshot',
            'viewport_rows': 2,
            'row_cache_hits': 0,
            'row_cache_misses': 2,
            'paint_kind': 'non_frame',
            'paint_micros': 60,
          },
        ],
        flutterFrameTimingEvents: const <Map<String, Object?>>[
          <String, Object?>{
            'build_duration_micros': 10,
            'raster_duration_micros': 20,
            'total_span_micros': 30,
            'missed_vsync': false,
          },
        ],
        expectedViewportHash: 'same',
        actualViewportHash: 'same',
      );

      expect(summary['max_overlay_layer_count'], 0);
      expect(summary['overlay_layer_count_metric_valid'], isTrue);
    },
  );

  test('marks incomplete or negative paint timing samples invalid', () {
    final outputDir = Directory.systemTemp.createTempSync(
      'ianvs_flutter_profile_invalid_paint_timing_test_',
    );
    addTearDown(() => outputDir.deleteSync(recursive: true));

    final summary = writeTerminalRenderProfileReport(
      outputDir: outputDir,
      workload: 'cursor_blink_idle_overlay_profile',
      policy: 'real_flutter_profile',
      repeatIndex: 1,
      targetPlatform: 'macos',
      targetDevice: 'macos-darwin',
      semanticGenerations: 1,
      flutterRenderEvents: const <Map<String, Object?>>[
        <String, Object?>{
          'schema_version': 'ianvs-bench-flutter-render-v1',
          'paint_kind': 'non_frame',
          'paint_micros': 10,
        },
        <String, Object?>{
          'schema_version': 'ianvs-bench-flutter-render-v1',
          'paint_kind': 'non_frame',
        },
        <String, Object?>{
          'schema_version': 'ianvs-bench-flutter-cursor-v1',
          'paint_micros': 5,
        },
        <String, Object?>{
          'schema_version': 'ianvs-bench-flutter-cursor-v1',
          'paint_micros': -1,
        },
      ],
      flutterFrameTimingEvents: const <Map<String, Object?>>[],
      expectedViewportHash: 'same',
      actualViewportHash: 'same',
    );

    expect(summary['p95_paint_micros'], 'N/A');
    expect(summary['p50_surface_paint_micros'], 'N/A');
    expect(summary['p95_surface_paint_micros'], 'N/A');
    expect(summary['p50_cursor_paint_micros'], 'N/A');
    expect(summary['p95_cursor_paint_micros'], 'N/A');
  });

  test('summarizes cursor bounds and memory violations per event', () {
    final outputDir = Directory.systemTemp.createTempSync(
      'ianvs_flutter_profile_cursor_constraint_test_',
    );
    addTearDown(() => outputDir.deleteSync(recursive: true));

    final summary = writeTerminalRenderProfileReport(
      outputDir: outputDir,
      workload: 'cursor_blink_idle_overlay_profile',
      policy: 'real_flutter_profile',
      repeatIndex: 1,
      targetPlatform: 'macos',
      targetDevice: 'macos-darwin',
      semanticGenerations: 1,
      flutterRenderEvents: const <Map<String, Object?>>[
        <String, Object?>{
          'schema_version': 'ianvs-bench-flutter-cursor-v1',
          'paint_micros': 1,
          'paint_bounds_area': 300,
          'cell_width_px': 10,
          'cell_height_px': 10,
          'device_pixel_ratio': 1,
          'cursor_picture_live_count': 1,
          'cursor_picture_estimated_bytes': 1000,
          'overlay_layer_count': 1,
        },
        <String, Object?>{
          'schema_version': 'ianvs-bench-flutter-cursor-v1',
          'paint_micros': 2,
          'paint_bounds_area': 100,
          'cell_width_px': 20,
          'cell_height_px': 20,
          'device_pixel_ratio': 2,
          'cursor_picture_live_count': 1,
          'cursor_picture_estimated_bytes': 100,
          'overlay_layer_count': 1,
        },
      ],
      flutterFrameTimingEvents: const <Map<String, Object?>>[],
      expectedViewportHash: 'same',
      actualViewportHash: 'same',
    );

    expect(summary['cursor_paint_bounds_violation_count'], 1);
    expect(summary['cursor_picture_estimated_bytes_violation_count'], 1);
    expect(summary['cursor_paint_bounds_metric_valid'], isTrue);
    expect(summary['cursor_picture_estimated_bytes_metric_valid'], isTrue);
  });

  test('marks missing cursor observation fields invalid', () {
    final outputDir = Directory.systemTemp.createTempSync(
      'ianvs_flutter_profile_cursor_missing_test_',
    );
    addTearDown(() => outputDir.deleteSync(recursive: true));

    final summary = writeTerminalRenderProfileReport(
      outputDir: outputDir,
      workload: 'cursor_blink_idle_overlay_profile',
      policy: 'real_flutter_profile',
      repeatIndex: 1,
      targetPlatform: 'macos',
      targetDevice: 'macos-darwin',
      semanticGenerations: 1,
      flutterRenderEvents: const <Map<String, Object?>>[
        <String, Object?>{
          'schema_version': 'ianvs-bench-flutter-cursor-v1',
          'paint_micros': 1,
          'overlay_layer_count': 1,
        },
      ],
      flutterFrameTimingEvents: const <Map<String, Object?>>[],
      expectedViewportHash: 'same',
      actualViewportHash: 'same',
    );

    expect(summary['cursor_paint_bounds_metric_valid'], isFalse);
    expect(summary['cursor_cell_width_metric_valid'], isFalse);
    expect(summary['cursor_cell_height_metric_valid'], isFalse);
    expect(summary['cursor_device_pixel_ratio_metric_valid'], isFalse);
    expect(summary['cursor_picture_live_count_metric_valid'], isFalse);
    expect(summary['cursor_picture_estimated_bytes_metric_valid'], isFalse);
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

  test('filters refresh diagnostics out of transport frame metrics', () {
    final outputDir = Directory.systemTemp.createTempSync(
      'ianvs_flutter_profile_runtime_filter_test_',
    );
    addTearDown(() => outputDir.deleteSync(recursive: true));

    final summary = writeTerminalRenderProfileReport(
      outputDir: outputDir,
      workload: 'protobuf_burst_stdout_profile',
      policy: 'native_runtime_profile',
      repeatIndex: 1,
      targetPlatform: 'macos',
      targetDevice: 'macos-darwin',
      semanticGenerations: 1,
      flutterRenderEvents: const <Map<String, Object?>>[],
      flutterFrameTimingEvents: const <Map<String, Object?>>[],
      dartRuntimeEvents: const <Map<String, Object?>>[
        <String, Object?>{
          'schema_version': 'ianvs-terminal-refresh-policy-v1',
          'event': 'refresh_requested',
        },
        <String, Object?>{
          'schema_version': 'ianvs-bench-dart-runtime-v1',
          'wire_format': 'protobuf',
          'raw_frame_bytes': 42,
          'json_decode_micros': 0,
          'protobuf_decode_micros': 7,
          'native_frame_build_micros': 11,
          'native_json_encode_micros': 0,
          'native_protobuf_encode_micros': 5,
          'native_rows_scanned': 2,
          'native_rows_emitted': 1,
          'apply_frame_micros': 13,
        },
        <String, Object?>{
          'schema_version': 'ianvs-terminal-graphics-diagnostic-v1',
          'event': 'frame_applied',
        },
      ],
      expectedViewportHash: 'same',
      actualViewportHash: 'same',
    );

    final runtimeEvents = File(
      '${outputDir.path}/dart_runtime.ndjson',
    ).readAsLinesSync();
    expect(runtimeEvents, hasLength(1));
    expect(
      jsonDecode(runtimeEvents.single),
      containsPair('schema_version', 'ianvs-bench-dart-runtime-v1'),
    );

    final metadata = _readJson(outputDir, 'metadata.json');
    expect(
      (metadata['mode']! as Map<String, Object?>)['wire_format'],
      'protobuf',
    );
    expect(summary['wire_format'], 'protobuf');
    expect(summary['runtime_frame_count'], 1);
    expect(summary['runtime_raw_frame_bytes_total'], 42);
    expect(summary['p95_protobuf_decode_micros'], 7);
    expect(summary['p95_apply_frame_micros'], 13);
  });
}

Map<String, Object?> _readJson(Directory dir, String name) {
  final decoded = jsonDecode(File('${dir.path}/$name').readAsStringSync());
  return (decoded as Map).cast<String, Object?>();
}

List<String> _readLines(Directory dir, String name) {
  return File('${dir.path}/$name').readAsLinesSync();
}
