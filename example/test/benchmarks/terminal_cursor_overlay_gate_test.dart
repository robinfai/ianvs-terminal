import 'dart:convert';

import 'package:app/benchmarks/terminal_cursor_overlay_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('eligible A/B emits the fixed schema, thresholds, and observations', () {
    final gate = evaluateTerminalCursorOverlayGate(
      summaries: _eligibleSummaries(),
      correctnessSuitesPassed: true,
    );

    expect(gate['schema_version'], 'ianvs-cursor-overlay-gate-v1');
    expect(gate['eligible'], isTrue);
    expect(gate['reason_codes'], isEmpty);
    expect(gate.keys.toSet(), <String>{
      'schema_version',
      'eligible',
      'reason_codes',
      'correctness_suites_passed',
      'thresholds',
      'observed',
    });
    expect(gate['thresholds'], {
      'min_repeats_per_variant': 5,
      'min_blink_transitions_per_repeat': 20,
      'max_cursor_paint_p95_ratio': 0.8,
      'max_frame_timing_p95_ratio': 1.05,
      'max_additional_overlay_layers': 1,
      'max_live_cursor_pictures': 1,
    });
    final observed = gate['observed']! as Map<String, Object?>;
    expect(observed.keys.toSet(), <String>{
      'surface',
      'overlay',
      'ratios',
      'surface_missed_vsync_total',
      'overlay_missed_vsync_total',
      'additional_overlay_layers',
      'max_cursor_picture_live_count',
      'max_cursor_paint_bounds_area',
      'max_cursor_picture_estimated_bytes',
      'max_cursor_picture_estimated_byte_limit',
      'cursor_paint_bounds_violation_count_total',
      'cursor_picture_estimated_bytes_violation_count_total',
    });
    final variantKeys = <String>{
      'repeat_count',
      'min_blink_transitions',
      'p50_surface_paint_micros_median',
      'p95_surface_paint_micros_median',
      'p50_cursor_paint_micros_median',
      'p95_cursor_paint_micros_median',
      'p50_build_duration_micros_median',
      'p95_build_duration_micros_median',
      'p50_raster_duration_micros_median',
      'p95_raster_duration_micros_median',
      'p50_total_span_micros_median',
      'p95_total_span_micros_median',
      'surface_non_frame_paint_count_total',
      'cursor_paint_count_total',
      'max_overlay_layer_count',
      'max_cursor_picture_live_count',
      'max_cursor_picture_estimated_bytes',
    };
    expect(
      (observed['surface']! as Map<String, Object?>).keys.toSet(),
      variantKeys,
    );
    expect(
      (observed['overlay']! as Map<String, Object?>).keys.toSet(),
      variantKeys,
    );
    expect((observed['ratios']! as Map<String, Object?>).keys.toSet(), <String>{
      'cursor_paint_p95',
      'build_p95',
      'raster_p95',
      'total_span_p95',
    });
  });

  final cases =
      <
        ({
          String name,
          String reason,
          List<Map<String, Object?>> Function() mutate,
        })
      >[
        (
          name: 'correctness suites',
          reason: 'correctness_suites_failed',
          mutate: _eligibleSummaries,
        ),
        (
          name: 'correctness hash',
          reason: 'correctness_hash_mismatch',
          mutate: () => _mutateSurface('hash_match', false),
        ),
        (
          name: 'surface repeat indices',
          reason: 'surface_repeat_indices_invalid',
          mutate: () =>
              _duplicateRepeatIndices('cursor_blink_idle_surface_profile'),
        ),
        (
          name: 'overlay repeat indices',
          reason: 'overlay_repeat_indices_invalid',
          mutate: () =>
              _duplicateRepeatIndices('cursor_blink_idle_overlay_profile'),
        ),
        (
          name: 'surface repeat count',
          reason: 'surface_repeat_count_below_minimum',
          mutate: () => _eligibleSummaries().sublist(1),
        ),
        (
          name: 'overlay repeat count',
          reason: 'overlay_repeat_count_below_minimum',
          mutate: () => _eligibleSummaries()
              .where(
                (entry) =>
                    entry['workload'] != 'cursor_blink_idle_overlay_profile' ||
                    entry['repeat'] != 5,
              )
              .toList(),
        ),
        (
          name: 'surface transition count',
          reason: 'surface_transition_count_below_minimum',
          mutate: () => _mutateSurface('sampled_blink_transitions', 19),
        ),
        (
          name: 'overlay transition count',
          reason: 'overlay_transition_count_below_minimum',
          mutate: () => _mutateOverlay('sampled_blink_transitions', 19),
        ),
        (
          name: 'overlay surface paint isolation',
          reason: 'overlay_non_frame_surface_paint_count_nonzero',
          mutate: () => _mutateOverlay('surface_non_frame_paint_count', 1),
        ),
        (
          name: 'surface paint count',
          reason: 'surface_non_frame_paint_count_mismatch',
          mutate: () => _mutateSurface('surface_non_frame_paint_count', 23),
        ),
        (
          name: 'overlay cursor paint count',
          reason: 'overlay_cursor_paint_count_mismatch',
          mutate: () => _mutateOverlay('cursor_paint_count', 23),
        ),
        (
          name: 'cursor paint ratio',
          reason: 'cursor_paint_p95_ratio_exceeded',
          mutate: () => _mutateAllOverlay('p95_cursor_paint_micros', 81),
        ),
        (
          name: 'build ratio',
          reason: 'build_p95_ratio_exceeded',
          mutate: () => _mutateAllOverlay('p95_build_duration_micros', 106),
        ),
        (
          name: 'raster ratio',
          reason: 'raster_p95_ratio_exceeded',
          mutate: () => _mutateAllOverlay('p95_raster_duration_micros', 211),
        ),
        (
          name: 'total span ratio',
          reason: 'total_span_p95_ratio_exceeded',
          mutate: () => _mutateAllOverlay('p95_total_span_micros', 316),
        ),
        (
          name: 'missed vsync',
          reason: 'missed_vsync_regression',
          mutate: () => _mutateOverlay('missed_vsync_count', 1),
        ),
        (
          name: 'additional layer',
          reason: 'overlay_layer_count_exceeded',
          mutate: () => _mutateOverlay('max_overlay_layer_count', 2),
        ),
        (
          name: 'live cursor picture',
          reason: 'cursor_picture_live_count_exceeded',
          mutate: () => _mutateOverlay('max_cursor_picture_live_count', 2),
        ),
        (
          name: 'cursor paint bounds',
          reason: 'cursor_paint_bounds_exceeded',
          mutate: () => _mutateOverlay('max_cursor_paint_bounds_area', 401),
        ),
        (
          name: 'cursor picture bytes',
          reason: 'cursor_picture_estimated_bytes_exceeded',
          mutate: () =>
              _mutateOverlay('max_cursor_picture_estimated_bytes', 6401),
        ),
      ];

  for (final testCase in cases) {
    test('${testCase.name} failure has a stable reason code', () {
      final gate = evaluateTerminalCursorOverlayGate(
        summaries: testCase.mutate(),
        correctnessSuitesPassed: testCase.reason != 'correctness_suites_failed',
      );

      expect(gate['eligible'], isFalse);
      expect(gate['reason_codes'], contains(testCase.reason));
    });
  }

  final invalidMetrics =
      <
        ({
          String name,
          String workload,
          String key,
          Object? value,
          String reason,
        })
      >[
        (
          name: 'surface transitions NaN',
          workload: 'cursor_blink_idle_surface_profile',
          key: 'sampled_blink_transitions',
          value: double.nan,
          reason: 'surface_transition_count_metric_missing',
        ),
        (
          name: 'overlay transitions infinity',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'sampled_blink_transitions',
          value: double.infinity,
          reason: 'overlay_transition_count_metric_missing',
        ),
        (
          name: 'surface paint count missing',
          workload: 'cursor_blink_idle_surface_profile',
          key: 'surface_non_frame_paint_count',
          value: null,
          reason: 'surface_paint_count_metric_missing',
        ),
        (
          name: 'overlay surface paint count missing',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'surface_non_frame_paint_count',
          value: null,
          reason: 'overlay_surface_paint_count_metric_missing',
        ),
        (
          name: 'overlay cursor paint count negative',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'cursor_paint_count',
          value: -1,
          reason: 'overlay_cursor_paint_count_metric_missing',
        ),
        (
          name: 'surface missed vsync missing',
          workload: 'cursor_blink_idle_surface_profile',
          key: 'missed_vsync_count',
          value: null,
          reason: 'surface_missed_vsync_metric_missing',
        ),
        (
          name: 'overlay missed vsync NaN',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'missed_vsync_count',
          value: double.nan,
          reason: 'overlay_missed_vsync_metric_missing',
        ),
        (
          name: 'surface layer count missing',
          workload: 'cursor_blink_idle_surface_profile',
          key: 'max_overlay_layer_count',
          value: null,
          reason: 'surface_overlay_layer_count_metric_missing',
        ),
        (
          name: 'overlay layer count infinity',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'max_overlay_layer_count',
          value: double.infinity,
          reason: 'overlay_overlay_layer_count_metric_missing',
        ),
        (
          name: 'live picture count missing',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'max_cursor_picture_live_count',
          value: null,
          reason: 'cursor_picture_live_count_metric_missing',
        ),
        (
          name: 'paint bounds NaN',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'max_cursor_paint_bounds_area',
          value: double.nan,
          reason: 'cursor_paint_bounds_metric_missing',
        ),
        (
          name: 'cell width zero',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'max_cursor_cell_width_px',
          value: 0,
          reason: 'cursor_cell_width_metric_missing',
        ),
        (
          name: 'cell height missing',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'max_cursor_cell_height_px',
          value: null,
          reason: 'cursor_cell_height_metric_missing',
        ),
        (
          name: 'device pixel ratio infinity',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'max_cursor_device_pixel_ratio',
          value: double.infinity,
          reason: 'cursor_device_pixel_ratio_metric_missing',
        ),
        (
          name: 'picture bytes negative',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'max_cursor_picture_estimated_bytes',
          value: -1,
          reason: 'cursor_picture_estimated_bytes_metric_missing',
        ),
        (
          name: 'cursor paint p95 negative',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'p95_cursor_paint_micros',
          value: -1,
          reason: 'cursor_paint_p95_metric_missing',
        ),
        (
          name: 'surface paint p95 unavailable',
          workload: 'cursor_blink_idle_surface_profile',
          key: 'p95_surface_paint_micros',
          value: 'N/A',
          reason: 'cursor_paint_p95_metric_missing',
        ),
        (
          name: 'build p95 negative',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'p95_build_duration_micros',
          value: -1,
          reason: 'build_p95_metric_missing',
        ),
        (
          name: 'raster p95 negative',
          workload: 'cursor_blink_idle_surface_profile',
          key: 'p95_raster_duration_micros',
          value: -1,
          reason: 'raster_p95_metric_missing',
        ),
        (
          name: 'total span p95 negative',
          workload: 'cursor_blink_idle_overlay_profile',
          key: 'p95_total_span_micros',
          value: -1,
          reason: 'total_span_p95_metric_missing',
        ),
      ];

  for (final testCase in invalidMetrics) {
    test('${testCase.name} fails closed with JSON-safe observations', () {
      final summaries = testCase.value == null
          ? _removeVariantKey(testCase.workload, testCase.key)
          : _mutateVariant(testCase.workload, testCase.key, testCase.value!);
      final gate = evaluateTerminalCursorOverlayGate(
        summaries: summaries,
        correctnessSuitesPassed: true,
      );

      expect(gate['eligible'], isFalse);
      expect(gate['reason_codes'], contains(testCase.reason));
      expect(() => jsonEncode(gate), returnsNormally);
    });
  }

  test('non-finite p50 observations serialize as null', () {
    final gate = evaluateTerminalCursorOverlayGate(
      summaries: _mutateOverlay('p50_cursor_paint_micros', double.nan),
      correctnessSuitesPassed: true,
    );

    expect(() => jsonEncode(gate), returnsNormally);
    final observed = gate['observed']! as Map<String, Object?>;
    final overlay = observed['overlay']! as Map<String, Object?>;
    expect(overlay['p50_cursor_paint_micros_median'], isNull);
  });

  test('even repeat medians remain finite and JSON safe', () {
    final summaries =
        <Map<String, Object?>>[
              ..._eligibleSummaries(),
              _summary(
                workload: 'cursor_blink_idle_surface_profile',
                repeat: 6,
                surfacePaints: 24,
                cursorPaints: 0,
                surfaceP95: 100,
                cursorP95: 'N/A',
                overlayLayers: 0,
              ),
              _summary(
                workload: 'cursor_blink_idle_overlay_profile',
                repeat: 6,
                surfacePaints: 0,
                cursorPaints: 24,
                surfaceP95: 'N/A',
                cursorP95: 80,
                overlayLayers: 1,
              ),
            ]
            .map((summary) {
              if (summary['workload'] == 'cursor_blink_idle_overlay_profile') {
                return <String, Object?>{
                  ...summary,
                  'p50_cursor_paint_micros': double.maxFinite,
                };
              }
              return summary;
            })
            .toList(growable: false);

    final gate = evaluateTerminalCursorOverlayGate(
      summaries: summaries,
      correctnessSuitesPassed: true,
    );

    expect(() => jsonEncode(gate), returnsNormally);
    final observed = gate['observed']! as Map<String, Object?>;
    final overlay = observed['overlay']! as Map<String, Object?>;
    expect(overlay['p50_cursor_paint_micros_median'], double.maxFinite);
  });

  test('finite aggregate overflow fails closed and remains JSON safe', () {
    final summaries = _eligibleSummaries()
        .map((summary) {
          return <String, Object?>{
            ...summary,
            'sampled_blink_transitions': double.maxFinite,
            'surface_non_frame_paint_count':
                summary['workload'] == 'cursor_blink_idle_surface_profile'
                ? double.maxFinite
                : 0,
            'cursor_paint_count':
                summary['workload'] == 'cursor_blink_idle_overlay_profile'
                ? double.maxFinite
                : 0,
            'missed_vsync_count': double.maxFinite,
            if (summary['workload'] == 'cursor_blink_idle_overlay_profile')
              'cursor_paint_bounds_violation_count': double.maxFinite,
          };
        })
        .toList(growable: false);

    final gate = evaluateTerminalCursorOverlayGate(
      summaries: summaries,
      correctnessSuitesPassed: true,
    );

    expect(gate['eligible'], isFalse);
    expect(
      gate['reason_codes'],
      containsAll(<String>[
        'surface_paint_count_metric_missing',
        'overlay_cursor_paint_count_metric_missing',
        'surface_missed_vsync_metric_missing',
        'overlay_missed_vsync_metric_missing',
        'cursor_paint_bounds_metric_missing',
      ]),
    );
    expect(() => jsonEncode(gate), returnsNormally);
  });

  test(
    'derived cursor picture limit overflow fails closed and is JSON safe',
    () {
      var summaries = _mutateAllOverlay(
        'max_cursor_cell_width_px',
        double.maxFinite,
      );
      summaries = summaries
          .map((summary) {
            if (summary['workload'] == 'cursor_blink_idle_overlay_profile') {
              return <String, Object?>{
                ...summary,
                'max_cursor_cell_height_px': double.maxFinite,
                'max_cursor_device_pixel_ratio': double.maxFinite,
              };
            }
            return summary;
          })
          .toList(growable: false);

      final gate = evaluateTerminalCursorOverlayGate(
        summaries: summaries,
        correctnessSuitesPassed: true,
      );

      expect(gate['eligible'], isFalse);
      expect(
        gate['reason_codes'],
        contains('cursor_picture_estimated_bytes_metric_missing'),
      );
      expect(() => jsonEncode(gate), returnsNormally);
    },
  );
}

List<Map<String, Object?>> _eligibleSummaries() {
  return <Map<String, Object?>>[
    for (var repeat = 1; repeat <= 5; repeat += 1)
      _summary(
        workload: 'cursor_blink_idle_surface_profile',
        repeat: repeat,
        surfacePaints: 24,
        cursorPaints: 0,
        surfaceP95: 100,
        cursorP95: 'N/A',
        overlayLayers: 0,
      ),
    for (var repeat = 1; repeat <= 5; repeat += 1)
      _summary(
        workload: 'cursor_blink_idle_overlay_profile',
        repeat: repeat,
        surfacePaints: 0,
        cursorPaints: 24,
        surfaceP95: 'N/A',
        cursorP95: 80,
        overlayLayers: 1,
      ),
  ];
}

Map<String, Object?> _summary({
  required String workload,
  required int repeat,
  required int surfacePaints,
  required int cursorPaints,
  required Object surfaceP95,
  required Object cursorP95,
  required int overlayLayers,
}) {
  return <String, Object?>{
    'workload': workload,
    'repeat': repeat,
    'hash_match': true,
    'sampled_blink_transitions': 24,
    'surface_non_frame_paint_count': surfacePaints,
    'cursor_paint_count': cursorPaints,
    'p50_surface_paint_micros': surfaceP95 is num ? 60 : 'N/A',
    'p95_surface_paint_micros': surfaceP95,
    'p50_cursor_paint_micros': cursorP95 is num ? 48 : 'N/A',
    'p95_cursor_paint_micros': cursorP95,
    'p50_build_duration_micros': 60,
    'p95_build_duration_micros': 100,
    'p50_raster_duration_micros': 120,
    'p95_raster_duration_micros': 200,
    'p50_total_span_micros': 180,
    'p95_total_span_micros': 300,
    'missed_vsync_count': 0,
    'max_cursor_paint_bounds_area': cursorPaints == 0 ? 0 : 400,
    'max_cursor_cell_width_px': 10,
    'max_cursor_cell_height_px': 20,
    'max_cursor_device_pixel_ratio': 2,
    'max_cursor_picture_live_count': cursorPaints == 0 ? 0 : 1,
    'max_cursor_picture_estimated_bytes': cursorPaints == 0 ? 0 : 6400,
    'max_overlay_layer_count': overlayLayers,
    'missed_vsync_metric_valid': true,
    'overlay_layer_count_metric_valid': true,
    'cursor_paint_bounds_metric_valid': true,
    'cursor_cell_width_metric_valid': true,
    'cursor_cell_height_metric_valid': true,
    'cursor_device_pixel_ratio_metric_valid': true,
    'cursor_picture_live_count_metric_valid': true,
    'cursor_picture_estimated_bytes_metric_valid': true,
    'cursor_paint_bounds_violation_count': 0,
    'cursor_picture_estimated_bytes_violation_count': 0,
  };
}

List<Map<String, Object?>> _duplicateRepeatIndices(String workload) {
  return _eligibleSummaries()
      .map(
        (summary) => summary['workload'] == workload
            ? <String, Object?>{...summary, 'repeat': 1}
            : summary,
      )
      .toList(growable: false);
}

List<Map<String, Object?>> _removeVariantKey(String workload, String key) {
  final summaries = _eligibleSummaries();
  final index = summaries.indexWhere((entry) => entry['workload'] == workload);
  summaries[index] = <String, Object?>{...summaries[index]}..remove(key);
  return summaries;
}

List<Map<String, Object?>> _mutateSurface(String key, Object value) {
  return _mutateVariant('cursor_blink_idle_surface_profile', key, value);
}

List<Map<String, Object?>> _mutateOverlay(String key, Object value) {
  return _mutateVariant('cursor_blink_idle_overlay_profile', key, value);
}

List<Map<String, Object?>> _mutateAllOverlay(String key, Object value) {
  return _eligibleSummaries()
      .map(
        (summary) => summary['workload'] == 'cursor_blink_idle_overlay_profile'
            ? <String, Object?>{...summary, key: value}
            : summary,
      )
      .toList(growable: false);
}

List<Map<String, Object?>> _mutateVariant(
  String workload,
  String key,
  Object value,
) {
  final summaries = _eligibleSummaries();
  final index = summaries.indexWhere((entry) => entry['workload'] == workload);
  summaries[index] = <String, Object?>{...summaries[index], key: value};
  return summaries;
}
