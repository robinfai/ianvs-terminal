import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const String terminalCursorOverlayGateSchema = 'ianvs-cursor-overlay-gate-v1';

abstract final class TerminalCursorOverlayGateThresholds {
  static const int minRepeatsPerVariant = 5;
  static const int minBlinkTransitionsPerRepeat = 20;
  static const double maxCursorPaintP95Ratio = 0.80;
  static const double maxFrameTimingP95Ratio = 1.05;
  static const int maxAdditionalOverlayLayers = 1;
  static const int maxLiveCursorPictures = 1;
}

Map<String, Object?> writeTerminalCursorOverlayGate({
  required Directory outputDir,
  required List<Map<String, Object?>> summaries,
  required bool correctnessSuitesPassed,
}) {
  final gate = evaluateTerminalCursorOverlayGate(
    summaries: summaries,
    correctnessSuitesPassed: correctnessSuitesPassed,
  );
  outputDir.createSync(recursive: true);
  File(
    '${outputDir.path}/cursor_overlay_gate.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(gate)}\n');
  return gate;
}

Map<String, Object?> evaluateTerminalCursorOverlayGate({
  required List<Map<String, Object?>> summaries,
  required bool correctnessSuitesPassed,
}) {
  final surface = summaries
      .where(
        (summary) => summary['workload'] == 'cursor_blink_idle_surface_profile',
      )
      .toList(growable: false);
  final overlay = summaries
      .where(
        (summary) => summary['workload'] == 'cursor_blink_idle_overlay_profile',
      )
      .toList(growable: false);
  final reasons = <String>[];

  void failWhen(bool condition, String reason) {
    if (condition && !reasons.contains(reason)) {
      reasons.add(reason);
    }
  }

  final surfaceRepeatIndices = _uniquePositiveRepeatIndices(surface);
  final overlayRepeatIndices = _uniquePositiveRepeatIndices(overlay);
  final surfaceTransitionsValid = _allValidMetrics(
    surface,
    'sampled_blink_transitions',
    nonNegative: true,
    integer: true,
  );
  final overlayTransitionsValid = _allValidMetrics(
    overlay,
    'sampled_blink_transitions',
    nonNegative: true,
    integer: true,
  );
  final surfacePaintCountValid =
      _allValidMetrics(
        surface,
        'surface_non_frame_paint_count',
        nonNegative: true,
        integer: true,
      ) &&
      _finiteSum(surface, 'surface_non_frame_paint_count') != null;
  final overlaySurfacePaintCountValid =
      _allValidMetrics(
        overlay,
        'surface_non_frame_paint_count',
        nonNegative: true,
        integer: true,
      ) &&
      _finiteSum(overlay, 'surface_non_frame_paint_count') != null;
  final overlayCursorPaintCountValid =
      _allValidMetrics(
        overlay,
        'cursor_paint_count',
        nonNegative: true,
        integer: true,
      ) &&
      _finiteSum(overlay, 'cursor_paint_count') != null;

  failWhen(!correctnessSuitesPassed, 'correctness_suites_failed');
  failWhen(
    [...surface, ...overlay].any((summary) => summary['hash_match'] != true),
    'correctness_hash_mismatch',
  );
  failWhen(surfaceRepeatIndices == null, 'surface_repeat_indices_invalid');
  failWhen(overlayRepeatIndices == null, 'overlay_repeat_indices_invalid');
  failWhen(
    (surfaceRepeatIndices?.length ?? 0) <
        TerminalCursorOverlayGateThresholds.minRepeatsPerVariant,
    'surface_repeat_count_below_minimum',
  );
  failWhen(
    (overlayRepeatIndices?.length ?? 0) <
        TerminalCursorOverlayGateThresholds.minRepeatsPerVariant,
    'overlay_repeat_count_below_minimum',
  );
  failWhen(!surfaceTransitionsValid, 'surface_transition_count_metric_missing');
  failWhen(!overlayTransitionsValid, 'overlay_transition_count_metric_missing');
  failWhen(
    surfaceTransitionsValid &&
        surface.any(
          (summary) =>
              _number(summary, 'sampled_blink_transitions') <
              TerminalCursorOverlayGateThresholds.minBlinkTransitionsPerRepeat,
        ),
    'surface_transition_count_below_minimum',
  );
  failWhen(
    overlayTransitionsValid &&
        overlay.any(
          (summary) =>
              _number(summary, 'sampled_blink_transitions') <
              TerminalCursorOverlayGateThresholds.minBlinkTransitionsPerRepeat,
        ),
    'overlay_transition_count_below_minimum',
  );
  failWhen(!surfacePaintCountValid, 'surface_paint_count_metric_missing');
  failWhen(
    !overlaySurfacePaintCountValid,
    'overlay_surface_paint_count_metric_missing',
  );
  failWhen(
    !overlayCursorPaintCountValid,
    'overlay_cursor_paint_count_metric_missing',
  );
  failWhen(
    overlaySurfacePaintCountValid &&
        overlay.any(
          (summary) => _number(summary, 'surface_non_frame_paint_count') != 0,
        ),
    'overlay_non_frame_surface_paint_count_nonzero',
  );
  failWhen(
    surfacePaintCountValid &&
        surfaceTransitionsValid &&
        surface.any(
          (summary) =>
              _number(summary, 'surface_non_frame_paint_count') !=
              _number(summary, 'sampled_blink_transitions'),
        ),
    'surface_non_frame_paint_count_mismatch',
  );
  failWhen(
    overlayCursorPaintCountValid &&
        overlayTransitionsValid &&
        overlay.any(
          (summary) =>
              _number(summary, 'cursor_paint_count') !=
              _number(summary, 'sampled_blink_transitions'),
        ),
    'overlay_cursor_paint_count_mismatch',
  );

  final surfaceCursorPaintP95 = _median(surface, 'p95_surface_paint_micros');
  final overlayCursorPaintP95 = _median(overlay, 'p95_cursor_paint_micros');
  _ratioGate(
    baseline: surfaceCursorPaintP95,
    candidate: overlayCursorPaintP95,
    maximum: TerminalCursorOverlayGateThresholds.maxCursorPaintP95Ratio,
    missingReason: 'cursor_paint_p95_metric_missing',
    exceededReason: 'cursor_paint_p95_ratio_exceeded',
    reasons: reasons,
  );

  final timingRatios = <String, double?>{};
  for (final timing in const <(String, String)>[
    ('build', 'p95_build_duration_micros'),
    ('raster', 'p95_raster_duration_micros'),
    ('total_span', 'p95_total_span_micros'),
  ]) {
    final baseline = _median(surface, timing.$2);
    final candidate = _median(overlay, timing.$2);
    timingRatios[timing.$1] = _ratio(candidate, baseline);
    _ratioGate(
      baseline: baseline,
      candidate: candidate,
      maximum: TerminalCursorOverlayGateThresholds.maxFrameTimingP95Ratio,
      missingReason: '${timing.$1}_p95_metric_missing',
      exceededReason: '${timing.$1}_p95_ratio_exceeded',
      reasons: reasons,
    );
  }

  final surfaceMissedVsyncValid =
      _allValidMetrics(
        surface,
        'missed_vsync_count',
        nonNegative: true,
        integer: true,
        validityFlag: 'missed_vsync_metric_valid',
      ) &&
      _finiteSum(surface, 'missed_vsync_count') != null;
  final overlayMissedVsyncValid =
      _allValidMetrics(
        overlay,
        'missed_vsync_count',
        nonNegative: true,
        integer: true,
        validityFlag: 'missed_vsync_metric_valid',
      ) &&
      _finiteSum(overlay, 'missed_vsync_count') != null;
  failWhen(!surfaceMissedVsyncValid, 'surface_missed_vsync_metric_missing');
  failWhen(!overlayMissedVsyncValid, 'overlay_missed_vsync_metric_missing');
  final surfaceMissedVsync = _finiteSum(surface, 'missed_vsync_count') ?? 0;
  final overlayMissedVsync = _finiteSum(overlay, 'missed_vsync_count') ?? 0;
  failWhen(
    surfaceMissedVsyncValid &&
        overlayMissedVsyncValid &&
        overlayMissedVsync > surfaceMissedVsync,
    'missed_vsync_regression',
  );

  final surfaceLayersValid = _allValidMetrics(
    surface,
    'max_overlay_layer_count',
    nonNegative: true,
    integer: true,
    validityFlag: 'overlay_layer_count_metric_valid',
  );
  final overlayLayersValid = _allValidMetrics(
    overlay,
    'max_overlay_layer_count',
    nonNegative: true,
    integer: true,
    validityFlag: 'overlay_layer_count_metric_valid',
  );
  failWhen(!surfaceLayersValid, 'surface_overlay_layer_count_metric_missing');
  failWhen(!overlayLayersValid, 'overlay_overlay_layer_count_metric_missing');
  final surfaceLayers = _maximum(surface, 'max_overlay_layer_count');
  final overlayLayers = _maximum(overlay, 'max_overlay_layer_count');
  failWhen(
    surfaceLayersValid &&
        overlayLayersValid &&
        overlayLayers - surfaceLayers >
            TerminalCursorOverlayGateThresholds.maxAdditionalOverlayLayers,
    'overlay_layer_count_exceeded',
  );
  final livePicturesValid = _allValidMetrics(
    overlay,
    'max_cursor_picture_live_count',
    nonNegative: true,
    integer: true,
    validityFlag: 'cursor_picture_live_count_metric_valid',
  );
  failWhen(!livePicturesValid, 'cursor_picture_live_count_metric_missing');
  final maxLivePictures = _maximum(overlay, 'max_cursor_picture_live_count');
  failWhen(
    livePicturesValid &&
        maxLivePictures >
            TerminalCursorOverlayGateThresholds.maxLiveCursorPictures,
    'cursor_picture_live_count_exceeded',
  );

  final paintBoundsValid = _allValidMetrics(
    overlay,
    'max_cursor_paint_bounds_area',
    nonNegative: true,
    validityFlag: 'cursor_paint_bounds_metric_valid',
  );
  final cellWidthValid = _allValidMetrics(
    overlay,
    'max_cursor_cell_width_px',
    positive: true,
    validityFlag: 'cursor_cell_width_metric_valid',
  );
  final cellHeightValid = _allValidMetrics(
    overlay,
    'max_cursor_cell_height_px',
    positive: true,
    validityFlag: 'cursor_cell_height_metric_valid',
  );
  final devicePixelRatioValid = _allValidMetrics(
    overlay,
    'max_cursor_device_pixel_ratio',
    positive: true,
    validityFlag: 'cursor_device_pixel_ratio_metric_valid',
  );
  final pictureBytesValid = _allValidMetrics(
    overlay,
    'max_cursor_picture_estimated_bytes',
    nonNegative: true,
    validityFlag: 'cursor_picture_estimated_bytes_metric_valid',
  );
  final paintBoundsViolationsValid =
      _allValidMetrics(
        overlay,
        'cursor_paint_bounds_violation_count',
        nonNegative: true,
        integer: true,
      ) &&
      _finiteSum(overlay, 'cursor_paint_bounds_violation_count') != null;
  final pictureBytesViolationsValid =
      _allValidMetrics(
        overlay,
        'cursor_picture_estimated_bytes_violation_count',
        nonNegative: true,
        integer: true,
      ) &&
      _finiteSum(overlay, 'cursor_picture_estimated_bytes_violation_count') !=
          null;
  final paintAreaLimitsValid =
      cellWidthValid &&
      cellHeightValid &&
      overlay.every(
        (summary) =>
            _safePaintAreaLimit(
              _number(summary, 'max_cursor_cell_width_px'),
              _number(summary, 'max_cursor_cell_height_px'),
            ) !=
            null,
      );
  final pictureByteLimitsValid =
      cellWidthValid &&
      cellHeightValid &&
      devicePixelRatioValid &&
      overlay.every(
        (summary) =>
            _safePictureByteLimit(
              _number(summary, 'max_cursor_cell_width_px'),
              _number(summary, 'max_cursor_cell_height_px'),
              _number(summary, 'max_cursor_device_pixel_ratio'),
            ) !=
            null,
      );
  failWhen(
    !paintBoundsValid || !paintAreaLimitsValid,
    'cursor_paint_bounds_metric_missing',
  );
  failWhen(!cellWidthValid, 'cursor_cell_width_metric_missing');
  failWhen(!cellHeightValid, 'cursor_cell_height_metric_missing');
  failWhen(!devicePixelRatioValid, 'cursor_device_pixel_ratio_metric_missing');
  failWhen(
    !pictureBytesValid || !pictureByteLimitsValid,
    'cursor_picture_estimated_bytes_metric_missing',
  );
  failWhen(!paintBoundsViolationsValid, 'cursor_paint_bounds_metric_missing');
  failWhen(
    !pictureBytesViolationsValid,
    'cursor_picture_estimated_bytes_metric_missing',
  );

  final paintBoundsViolationCount =
      _finiteSum(overlay, 'cursor_paint_bounds_violation_count') ?? 0;
  final pictureBytesViolationCount =
      _finiteSum(overlay, 'cursor_picture_estimated_bytes_violation_count') ??
      0;
  failWhen(
    paintBoundsViolationsValid && paintBoundsViolationCount > 0,
    'cursor_paint_bounds_exceeded',
  );
  failWhen(
    pictureBytesViolationsValid && pictureBytesViolationCount > 0,
    'cursor_picture_estimated_bytes_exceeded',
  );

  var maxPaintBoundsArea = 0.0;
  var maxPictureBytes = 0.0;
  var maxPictureByteLimit = 0.0;
  for (final summary in overlay) {
    final boundsArea = _number(summary, 'max_cursor_paint_bounds_area');
    final cellWidth = _number(summary, 'max_cursor_cell_width_px');
    final cellHeight = _number(summary, 'max_cursor_cell_height_px');
    final dpr = _number(summary, 'max_cursor_device_pixel_ratio');
    final pictureBytes = _number(summary, 'max_cursor_picture_estimated_bytes');
    final paintAreaLimit = _safePaintAreaLimit(cellWidth, cellHeight);
    final pictureByteLimit = _safePictureByteLimit(cellWidth, cellHeight, dpr);
    maxPaintBoundsArea = math.max(maxPaintBoundsArea, boundsArea);
    maxPictureBytes = math.max(maxPictureBytes, pictureBytes);
    if (pictureByteLimit != null) {
      maxPictureByteLimit = math.max(maxPictureByteLimit, pictureByteLimit);
    }
    failWhen(
      paintBoundsValid &&
          cellWidthValid &&
          cellHeightValid &&
          paintAreaLimit != null &&
          boundsArea > paintAreaLimit,
      'cursor_paint_bounds_exceeded',
    );
    failWhen(
      pictureBytesValid &&
          cellWidthValid &&
          cellHeightValid &&
          devicePixelRatioValid &&
          pictureByteLimit != null &&
          pictureBytes > pictureByteLimit,
      'cursor_picture_estimated_bytes_exceeded',
    );
  }

  final observed = <String, Object?>{
    'surface': _variantObservations(surface),
    'overlay': _variantObservations(overlay),
    'ratios': <String, Object?>{
      'cursor_paint_p95': _ratio(overlayCursorPaintP95, surfaceCursorPaintP95),
      'build_p95': timingRatios['build'],
      'raster_p95': timingRatios['raster'],
      'total_span_p95': timingRatios['total_span'],
    },
    'surface_missed_vsync_total': surfaceMissedVsync,
    'overlay_missed_vsync_total': overlayMissedVsync,
    'additional_overlay_layers': overlayLayers - surfaceLayers,
    'max_cursor_picture_live_count': maxLivePictures,
    'max_cursor_paint_bounds_area': maxPaintBoundsArea,
    'max_cursor_picture_estimated_bytes': maxPictureBytes,
    'max_cursor_picture_estimated_byte_limit': maxPictureByteLimit,
    'cursor_paint_bounds_violation_count_total': paintBoundsViolationCount,
    'cursor_picture_estimated_bytes_violation_count_total':
        pictureBytesViolationCount,
  };

  return <String, Object?>{
    'schema_version': terminalCursorOverlayGateSchema,
    'eligible': reasons.isEmpty,
    'reason_codes': reasons,
    'correctness_suites_passed': correctnessSuitesPassed,
    'thresholds': const <String, Object?>{
      'min_repeats_per_variant':
          TerminalCursorOverlayGateThresholds.minRepeatsPerVariant,
      'min_blink_transitions_per_repeat':
          TerminalCursorOverlayGateThresholds.minBlinkTransitionsPerRepeat,
      'max_cursor_paint_p95_ratio':
          TerminalCursorOverlayGateThresholds.maxCursorPaintP95Ratio,
      'max_frame_timing_p95_ratio':
          TerminalCursorOverlayGateThresholds.maxFrameTimingP95Ratio,
      'max_additional_overlay_layers':
          TerminalCursorOverlayGateThresholds.maxAdditionalOverlayLayers,
      'max_live_cursor_pictures':
          TerminalCursorOverlayGateThresholds.maxLiveCursorPictures,
    },
    'observed': observed,
  };
}

Map<String, Object?> _variantObservations(
  List<Map<String, Object?>> summaries,
) {
  return <String, Object?>{
    'repeat_count': summaries.length,
    'min_blink_transitions': summaries.isEmpty
        ? 0
        : summaries
              .map((summary) => _number(summary, 'sampled_blink_transitions'))
              .reduce(math.min),
    for (final metric in const <String>[
      'p50_surface_paint_micros',
      'p95_surface_paint_micros',
      'p50_cursor_paint_micros',
      'p95_cursor_paint_micros',
      'p50_build_duration_micros',
      'p95_build_duration_micros',
      'p50_raster_duration_micros',
      'p95_raster_duration_micros',
      'p50_total_span_micros',
      'p95_total_span_micros',
    ])
      '${metric}_median': _median(summaries, metric),
    'surface_non_frame_paint_count_total': _finiteSum(
      summaries,
      'surface_non_frame_paint_count',
    ),
    'cursor_paint_count_total': _finiteSum(summaries, 'cursor_paint_count'),
    'max_overlay_layer_count': _maximum(summaries, 'max_overlay_layer_count'),
    'max_cursor_picture_live_count': _maximum(
      summaries,
      'max_cursor_picture_live_count',
    ),
    'max_cursor_picture_estimated_bytes': _maximum(
      summaries,
      'max_cursor_picture_estimated_bytes',
    ),
  };
}

void _ratioGate({
  required double? baseline,
  required double? candidate,
  required double maximum,
  required String missingReason,
  required String exceededReason,
  required List<String> reasons,
}) {
  final ratio = _ratio(candidate, baseline);
  if (ratio == null) {
    if (!reasons.contains(missingReason)) {
      reasons.add(missingReason);
    }
    return;
  }
  if (ratio > maximum && !reasons.contains(exceededReason)) {
    reasons.add(exceededReason);
  }
}

double? _ratio(double? candidate, double? baseline) {
  if (candidate == null ||
      baseline == null ||
      !candidate.isFinite ||
      !baseline.isFinite ||
      baseline <= 0) {
    return null;
  }
  final ratio = candidate / baseline;
  return ratio.isFinite ? ratio : null;
}

double? _median(List<Map<String, Object?>> summaries, String key) {
  final values = <double>[];
  for (final summary in summaries) {
    final value = summary[key];
    if (value is! num || !value.isFinite || value < 0) {
      return null;
    }
    values.add(value.toDouble());
  }
  if (values.isEmpty) {
    return null;
  }
  values.sort();
  final middle = values.length ~/ 2;
  if (values.length.isOdd) {
    return values[middle];
  }
  final median = values[middle - 1] / 2 + values[middle] / 2;
  return median.isFinite ? median : null;
}

double _number(Map<String, Object?> summary, String key) {
  final value = summary[key];
  return value is num && value.isFinite ? value.toDouble() : 0;
}

double? _finiteSum(List<Map<String, Object?>> summaries, String key) {
  var total = 0.0;
  for (final summary in summaries) {
    final value = summary[key];
    if (value is! num || !value.isFinite) {
      return null;
    }
    total += value.toDouble();
    if (!total.isFinite) {
      return null;
    }
  }
  return total;
}

double _maximum(List<Map<String, Object?>> summaries, String key) {
  var maximum = 0.0;
  for (final summary in summaries) {
    maximum = math.max(maximum, _number(summary, key));
  }
  return maximum;
}

Set<int>? _uniquePositiveRepeatIndices(List<Map<String, Object?>> summaries) {
  final indices = <int>{};
  for (final summary in summaries) {
    final value = summary['repeat'];
    if (value is! num ||
        !value.isFinite ||
        value <= 0 ||
        value.toDouble() != value.truncateToDouble()) {
      return null;
    }
    if (!indices.add(value.toInt())) {
      return null;
    }
  }
  return indices;
}

bool _allValidMetrics(
  List<Map<String, Object?>> summaries,
  String key, {
  bool positive = false,
  bool nonNegative = false,
  bool integer = false,
  String? validityFlag,
}) {
  if (summaries.isEmpty) {
    return false;
  }
  return summaries.every((summary) {
    if (validityFlag != null && summary[validityFlag] != true) {
      return false;
    }
    final value = summary[key];
    if (value is! num || !value.isFinite) {
      return false;
    }
    final number = value.toDouble();
    if (positive && number <= 0) {
      return false;
    }
    if (nonNegative && number < 0) {
      return false;
    }
    return !integer || number == number.truncateToDouble();
  });
}

double? _safePaintAreaLimit(double width, double height) {
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    return null;
  }
  final limit = 2 * width * height;
  return limit.isFinite ? limit : null;
}

double? _safePictureByteLimit(double width, double height, double dpr) {
  if (!width.isFinite ||
      !height.isFinite ||
      !dpr.isFinite ||
      width <= 0 ||
      height <= 0 ||
      dpr <= 0) {
    return null;
  }
  final physicalWidth = 2 * width * dpr;
  final physicalHeight = height * dpr;
  if (!physicalWidth.isFinite || !physicalHeight.isFinite) {
    return null;
  }
  final limit = (physicalWidth.ceil() * physicalHeight.ceil() * 4).toDouble();
  return limit.isFinite ? limit : null;
}
