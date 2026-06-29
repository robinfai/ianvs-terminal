import 'dart:convert';
import 'dart:math' as math;

import 'bench_policy.dart';
import 'workloads.dart';

final class BenchRunData {
  const BenchRunData({
    required this.workload,
    required this.framePolicy,
    this.renderPolicy = BenchRenderPolicy.headlessStateOnly,
    this.repeatIndex = 1,
    this.viewportCols = 0,
    this.viewportRows = 0,
    this.traceBytes = const <int>[],
    this.finalViewportHash = '',
    this.finalScrollbackHash = '',
    this.semanticGenerations = 0,
    this.rustFrameEvents = const <Map<String, Object?>>[],
    this.dartRuntimeEvents = const <Map<String, Object?>>[],
    this.flutterRenderEvents = const <Map<String, Object?>>[],
    this.flutterFrameTimingEvents = const <Map<String, Object?>>[],
  });

  final String workload;
  final BenchFramePolicy framePolicy;
  final BenchRenderPolicy renderPolicy;
  final int repeatIndex;
  final int viewportCols;
  final int viewportRows;
  final List<int> traceBytes;
  final String finalViewportHash;
  final String finalScrollbackHash;
  final int semanticGenerations;
  final List<Map<String, Object?>> rustFrameEvents;
  final List<Map<String, Object?>> dartRuntimeEvents;
  final List<Map<String, Object?>> flutterRenderEvents;
  final List<Map<String, Object?>> flutterFrameTimingEvents;
}

final class ReplayTerminalEngine {
  const ReplayTerminalEngine({this.coalesceEvery = 32});

  final int coalesceEvery;

  BenchRunData run({
    required BenchWorkload workload,
    required BenchFramePolicy framePolicy,
    required BenchRenderPolicy renderPolicy,
    required int cols,
    required int rows,
    required int repeatIndex,
  }) {
    var currentCols = cols;
    var currentRows = rows;
    final scrollback = <String>[];
    var visibleRows = _visibleRows(scrollback, currentRows);
    var lastEmittedVisibleRows = visibleRows;
    var lastViewportStartRow = 0;
    var semanticGeneration = 0;
    var damageGeneration = 0;
    var frameId = 0;
    var pendingSinceLastFrame = 0;
    var bytesSinceLastFrame = 0;
    var lastFrameWasSnapshot = false;
    var nextResizeIndex = 0;

    final rustEvents = <Map<String, Object?>>[];
    final dartEvents = <Map<String, Object?>>[];
    final flutterEvents = <Map<String, Object?>>[];
    final timingEvents = <Map<String, Object?>>[];
    final lines = const LineSplitter()
        .convert(utf8.decode(workload.traceBytes))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final resizeEvery = workload.resizeSteps.isEmpty
        ? 0
        : math.max(1, lines.length ~/ workload.resizeSteps.length);

    void emitFrame({required String reason, required bool forceSnapshot}) {
      if (semanticGeneration == 0 && rustEvents.isNotEmpty) {
        return;
      }
      final frameKind =
          forceSnapshot || framePolicy == BenchFramePolicy.snapshotOnly
          ? 'snapshot'
          : rustEvents.isEmpty
          ? 'snapshot'
          : 'delta';
      final snapshotReason = frameKind == 'snapshot'
          ? (reason == 'resize'
                ? 'resize'
                : rustEvents.isEmpty
                ? 'first_frame'
                : reason)
          : null;
      final viewportStartRow = math.max(0, scrollback.length - currentRows);
      final rowShift = frameKind == 'delta'
          ? (viewportStartRow - lastViewportStartRow).clamp(
              -currentRows,
              currentRows,
            )
          : 0;
      final viewportHash = _hashRows(visibleRows, currentCols, currentRows);
      final rowsEmitted = frameKind == 'snapshot'
          ? currentRows
          : _changedRows(lastEmittedVisibleRows, visibleRows);
      final rowsScanned = frameKind == 'snapshot'
          ? currentRows
          : math.min(currentRows, math.max(rowsEmitted, rowShift.abs()));
      frameId += 1;
      damageGeneration += 1;
      final frameBuildMicros = 80 + rowsScanned * 3 + rowsEmitted * 5;
      final frameExtractMicros = 30 + rowsScanned * 2;
      final jsonEncodeMicros = 20 + rowsEmitted * 2;
      final timestampMicros = frameId * 16666;
      final sessionId = '${workload.name}#${framePolicy.wireName}#$repeatIndex';

      rustEvents.add(<String, Object?>{
        'schema_version': 'ianvs-bench-rust-frame-v1',
        'timestamp_micros': timestampMicros,
        'session_id': sessionId,
        'frame_id': frameId,
        'semantic_generation': semanticGeneration,
        'damage_generation': damageGeneration,
        'frame_kind': frameKind,
        'snapshot_fallback_reason': snapshotReason,
        'viewport_rows': currentRows,
        'viewport_cols': currentCols,
        'viewport_start_row': viewportStartRow,
        'viewport_row_shift': rowShift,
        'dirty_ranges_count': rowsEmitted == 0 ? 0 : 1,
        'rows_scanned': rowsScanned,
        'rows_emitted': rowsEmitted,
        'candidate_rows': rowsScanned,
        'bytes_processed_since_last_frame': bytesSinceLastFrame,
        'terminal_process_micros': 40 + pendingSinceLastFrame,
        'damage_merge_micros': 5 + rowsEmitted,
        'frame_extract_micros': frameExtractMicros,
        'frame_build_micros': frameBuildMicros,
        'json_encode_micros': jsonEncodeMicros,
        'active_graphics_count': 0,
        'graphic_placements_count': 0,
        'viewport_hash': viewportHash,
      });
      dartEvents.add(<String, Object?>{
        'schema_version': 'ianvs-bench-dart-runtime-v1',
        'timestamp_micros': timestampMicros + 250,
        'session_id': sessionId,
        'frame_id': frameId,
        'raw_frame_bytes': 180 + rowsEmitted * math.max(1, currentCols ~/ 4),
        'frame_kind': frameKind,
        'json_decode_micros': 18 + rowsEmitted,
        'apply_frame_micros': 22 + rowsScanned,
        'pending_frames_before': framePolicy == BenchFramePolicy.deltaCoalesced
            ? math.max(0, pendingSinceLastFrame - 1)
            : 0,
        'pending_frames_after': 0,
        'queued_refresh_count': framePolicy == BenchFramePolicy.deltaCoalesced
            ? math.max(0, pendingSinceLastFrame - 1)
            : 0,
        'events_processed': 0,
        'viewport_hash_after_apply': viewportHash,
      });
      if (renderPolicy == BenchRenderPolicy.normalRender) {
        final cacheMisses = frameKind == 'snapshot' ? currentRows : rowsEmitted;
        final cacheHits = math.max(0, currentRows - cacheMisses);
        flutterEvents.add(<String, Object?>{
          'schema_version': 'ianvs-bench-flutter-render-v1',
          'timestamp_micros': timestampMicros + 500,
          'session_id': sessionId,
          'frame_version': frameId,
          'frame_kind': frameKind,
          'viewport_row_shift': rowShift,
          'viewport_rows': currentRows,
          'dirty_row_count': rowsEmitted,
          'row_visual_rebuild_count': cacheMisses,
          'row_cache_hits': cacheHits,
          'row_cache_misses': cacheMisses,
          'paragraph_build_count': cacheMisses,
          'paint_micros': 120 + cacheMisses * 9,
        });
        timingEvents.add(<String, Object?>{
          'schema_version': 'ianvs-bench-flutter-frame-timing-v1',
          'timestamp_micros': timestampMicros + 750,
          'build_duration_micros': 300 + cacheMisses * 8,
          'raster_duration_micros': 600 + cacheMisses * 12,
          'total_span_micros': 1200 + cacheMisses * 24,
          'missed_vsync': false,
        });
      }

      lastEmittedVisibleRows = List<String>.from(visibleRows);
      lastViewportStartRow = viewportStartRow;
      pendingSinceLastFrame = 0;
      bytesSinceLastFrame = 0;
      lastFrameWasSnapshot = frameKind == 'snapshot';
    }

    for (var index = 0; index < lines.length; index += 1) {
      if (resizeEvery > 0 &&
          nextResizeIndex < workload.resizeSteps.length &&
          index == nextResizeIndex * resizeEvery) {
        final step = workload.resizeSteps[nextResizeIndex];
        currentCols = step.cols;
        currentRows = step.rows;
        visibleRows = _visibleRows(scrollback, currentRows);
        if (scrollback.isNotEmpty) {
          emitFrame(reason: 'resize', forceSnapshot: true);
        }
        nextResizeIndex += 1;
      }

      final clipped = _clipLine(lines[index], currentCols);
      scrollback.add(clipped);
      semanticGeneration += 1;
      pendingSinceLastFrame += 1;
      bytesSinceLastFrame += utf8.encode(lines[index]).length + 1;
      visibleRows = _visibleRows(scrollback, currentRows);

      final shouldEmit = switch (framePolicy) {
        BenchFramePolicy.snapshotOnly => true,
        BenchFramePolicy.deltaNoCoalesce => true,
        BenchFramePolicy.deltaCoalesced =>
          pendingSinceLastFrame >= math.max(1, coalesceEvery),
      };
      if (shouldEmit) {
        emitFrame(
          reason: lastFrameWasSnapshot ? 'delta' : 'first_frame',
          forceSnapshot: false,
        );
      }
    }

    if (pendingSinceLastFrame > 0 || rustEvents.isEmpty) {
      emitFrame(
        reason: rustEvents.isEmpty ? 'first_frame' : 'delta',
        forceSnapshot: false,
      );
    }

    final finalViewportHash = _hashRows(visibleRows, currentCols, currentRows);
    final finalScrollbackHash = _hashRows(
      scrollback,
      currentCols,
      scrollback.length,
    );
    return BenchRunData(
      workload: workload.name,
      framePolicy: framePolicy,
      renderPolicy: renderPolicy,
      repeatIndex: repeatIndex,
      viewportCols: currentCols,
      viewportRows: currentRows,
      traceBytes: workload.traceBytes,
      finalViewportHash: finalViewportHash,
      finalScrollbackHash: finalScrollbackHash,
      semanticGenerations: semanticGeneration,
      rustFrameEvents: List<Map<String, Object?>>.unmodifiable(rustEvents),
      dartRuntimeEvents: List<Map<String, Object?>>.unmodifiable(dartEvents),
      flutterRenderEvents: List<Map<String, Object?>>.unmodifiable(
        flutterEvents,
      ),
      flutterFrameTimingEvents: List<Map<String, Object?>>.unmodifiable(
        timingEvents,
      ),
    );
  }
}

List<String> _visibleRows(List<String> scrollback, int rows) {
  final visible = scrollback.length <= rows
      ? scrollback
      : scrollback.sublist(scrollback.length - rows);
  if (visible.length == rows) {
    return List<String>.from(visible);
  }
  return <String>[
    ...List<String>.filled(rows - visible.length, ''),
    ...visible,
  ];
}

String _clipLine(String line, int cols) {
  if (cols <= 0 || line.length <= cols) {
    return line;
  }
  return line.substring(0, cols);
}

int _changedRows(List<String> previous, List<String> next) {
  final length = math.max(previous.length, next.length);
  var changed = 0;
  for (var index = 0; index < length; index += 1) {
    final before = index < previous.length ? previous[index] : null;
    final after = index < next.length ? next[index] : null;
    if (before != after) {
      changed += 1;
    }
  }
  return changed;
}

String _hashRows(List<String> rows, int cols, int viewportRows) {
  var hash = 0x811c9dc5;
  void addCodeUnit(int codeUnit) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }

  for (final codeUnit in 'cols=$cols;rows=$viewportRows\n'.codeUnits) {
    addCodeUnit(codeUnit);
  }
  for (final row in rows) {
    for (final codeUnit in row.codeUnits) {
      addCodeUnit(codeUnit);
    }
    addCodeUnit(0x0a);
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
