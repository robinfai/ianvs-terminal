import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../config/terminal_config.dart';
import '../runtime/terminal_benchmarking.dart';

const Key terminalCursorOverlayKey = Key('terminal-cursor-overlay');

class TerminalCursorVisualKey {
  TerminalCursorVisualKey({
    required this.frameVersion,
    required this.cursorRow,
    required this.cursorCol,
    required this.cursorVisible,
    required this.cursorShape,
    required this.resolvedForeground,
    required this.resolvedBackground,
    required this.resolvedCursor,
    required this.cellSize,
    required this.devicePixelRatio,
    required this.fontFamily,
    required List<String> fontFallback,
    required this.fontSize,
    required this.lineHeight,
    required this.glyphText,
    required this.glyphUsesCustomGeometry,
    required this.glyphCustomGeometryKind,
    required this.glyphColumn,
    required this.glyphColumnSpan,
    required this.glyphPlacementRect,
    required this.glyphDrawOffset,
    required this.glyphScaleX,
    required this.glyphScaleY,
    required this.glyphFontWeight,
    required this.glyphFontStyle,
    required this.glyphDecoration,
    required this.glyphIsContinuation,
    required this.cursorEnabled,
    required this.cursorBlinkEnabled,
  }) : fontFallback = List<String>.unmodifiable(fontFallback);

  final int frameVersion;
  final int cursorRow;
  final int cursorCol;
  final bool cursorVisible;
  final TerminalCursorShape cursorShape;
  final Color resolvedForeground;
  final Color resolvedBackground;
  final Color resolvedCursor;
  final Size cellSize;
  final double devicePixelRatio;
  final String fontFamily;
  final List<String> fontFallback;
  final double fontSize;
  final double lineHeight;
  final String glyphText;
  final bool glyphUsesCustomGeometry;
  final String glyphCustomGeometryKind;
  final int glyphColumn;
  final int glyphColumnSpan;
  final Rect glyphPlacementRect;
  final Offset glyphDrawOffset;
  final double glyphScaleX;
  final double glyphScaleY;
  final FontWeight glyphFontWeight;
  final FontStyle glyphFontStyle;
  final TextDecoration glyphDecoration;
  final bool glyphIsContinuation;
  final bool cursorEnabled;
  final bool cursorBlinkEnabled;

  TerminalCursorVisualKey copyWith({
    int? frameVersion,
    int? cursorRow,
    int? cursorCol,
    bool? cursorVisible,
    TerminalCursorShape? cursorShape,
    Color? resolvedForeground,
    Color? resolvedBackground,
    Color? resolvedCursor,
    Size? cellSize,
    double? devicePixelRatio,
    String? fontFamily,
    List<String>? fontFallback,
    double? fontSize,
    double? lineHeight,
    String? glyphText,
    bool? glyphUsesCustomGeometry,
    String? glyphCustomGeometryKind,
    int? glyphColumn,
    int? glyphColumnSpan,
    Rect? glyphPlacementRect,
    Offset? glyphDrawOffset,
    double? glyphScaleX,
    double? glyphScaleY,
    FontWeight? glyphFontWeight,
    FontStyle? glyphFontStyle,
    TextDecoration? glyphDecoration,
    bool? glyphIsContinuation,
    bool? cursorEnabled,
    bool? cursorBlinkEnabled,
  }) {
    return TerminalCursorVisualKey(
      frameVersion: frameVersion ?? this.frameVersion,
      cursorRow: cursorRow ?? this.cursorRow,
      cursorCol: cursorCol ?? this.cursorCol,
      cursorVisible: cursorVisible ?? this.cursorVisible,
      cursorShape: cursorShape ?? this.cursorShape,
      resolvedForeground: resolvedForeground ?? this.resolvedForeground,
      resolvedBackground: resolvedBackground ?? this.resolvedBackground,
      resolvedCursor: resolvedCursor ?? this.resolvedCursor,
      cellSize: cellSize ?? this.cellSize,
      devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
      fontFamily: fontFamily ?? this.fontFamily,
      fontFallback: fontFallback ?? this.fontFallback,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      glyphText: glyphText ?? this.glyphText,
      glyphUsesCustomGeometry:
          glyphUsesCustomGeometry ?? this.glyphUsesCustomGeometry,
      glyphCustomGeometryKind:
          glyphCustomGeometryKind ?? this.glyphCustomGeometryKind,
      glyphColumn: glyphColumn ?? this.glyphColumn,
      glyphColumnSpan: glyphColumnSpan ?? this.glyphColumnSpan,
      glyphPlacementRect: glyphPlacementRect ?? this.glyphPlacementRect,
      glyphDrawOffset: glyphDrawOffset ?? this.glyphDrawOffset,
      glyphScaleX: glyphScaleX ?? this.glyphScaleX,
      glyphScaleY: glyphScaleY ?? this.glyphScaleY,
      glyphFontWeight: glyphFontWeight ?? this.glyphFontWeight,
      glyphFontStyle: glyphFontStyle ?? this.glyphFontStyle,
      glyphDecoration: glyphDecoration ?? this.glyphDecoration,
      glyphIsContinuation: glyphIsContinuation ?? this.glyphIsContinuation,
      cursorEnabled: cursorEnabled ?? this.cursorEnabled,
      cursorBlinkEnabled: cursorBlinkEnabled ?? this.cursorBlinkEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TerminalCursorVisualKey &&
            other.frameVersion == frameVersion &&
            other.cursorRow == cursorRow &&
            other.cursorCol == cursorCol &&
            other.cursorVisible == cursorVisible &&
            other.cursorShape == cursorShape &&
            other.resolvedForeground == resolvedForeground &&
            other.resolvedBackground == resolvedBackground &&
            other.resolvedCursor == resolvedCursor &&
            other.cellSize == cellSize &&
            other.devicePixelRatio == devicePixelRatio &&
            other.fontFamily == fontFamily &&
            listEquals(other.fontFallback, fontFallback) &&
            other.fontSize == fontSize &&
            other.lineHeight == lineHeight &&
            other.glyphText == glyphText &&
            other.glyphUsesCustomGeometry == glyphUsesCustomGeometry &&
            other.glyphCustomGeometryKind == glyphCustomGeometryKind &&
            other.glyphColumn == glyphColumn &&
            other.glyphColumnSpan == glyphColumnSpan &&
            other.glyphPlacementRect == glyphPlacementRect &&
            other.glyphDrawOffset == glyphDrawOffset &&
            other.glyphScaleX == glyphScaleX &&
            other.glyphScaleY == glyphScaleY &&
            other.glyphFontWeight == glyphFontWeight &&
            other.glyphFontStyle == glyphFontStyle &&
            other.glyphDecoration == glyphDecoration &&
            other.glyphIsContinuation == glyphIsContinuation &&
            other.cursorEnabled == cursorEnabled &&
            other.cursorBlinkEnabled == cursorBlinkEnabled;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    frameVersion,
    cursorRow,
    cursorCol,
    cursorVisible,
    cursorShape,
    resolvedForeground,
    resolvedBackground,
    resolvedCursor,
    cellSize,
    devicePixelRatio,
    fontFamily,
    Object.hashAll(fontFallback),
    fontSize,
    lineHeight,
    glyphText,
    glyphUsesCustomGeometry,
    glyphCustomGeometryKind,
    glyphColumn,
    glyphColumnSpan,
    glyphPlacementRect,
    glyphDrawOffset,
    glyphScaleX,
    glyphScaleY,
    glyphFontWeight,
    glyphFontStyle,
    glyphDecoration,
    glyphIsContinuation,
    cursorEnabled,
    cursorBlinkEnabled,
  ]);
}

class TerminalCursorVisualSnapshot {
  TerminalCursorVisualSnapshot({
    required this.key,
    required this.picture,
    required this.rect,
    required this.color,
  });

  final TerminalCursorVisualKey key;
  final ui.Picture picture;
  final Rect rect;
  final Color color;
  bool _disposed = false;

  int get estimatedBytes {
    final dpr = key.devicePixelRatio.isFinite && key.devicePixelRatio > 0
        ? key.devicePixelRatio
        : 1.0;
    final pixelWidth = math.max(0, (rect.width * dpr).ceil()).toInt();
    final pixelHeight = math.max(0, (rect.height * dpr).ceil()).toInt();
    return pixelWidth * pixelHeight * 4;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    picture.dispose();
  }
}

class TerminalCursorVisualSnapshotCache {
  TerminalCursorVisualSnapshot? _snapshot;

  TerminalCursorVisualSnapshot? get snapshot => _snapshot;
  int get livePictureCount => _snapshot == null ? 0 : 1;

  TerminalCursorVisualSnapshot resolve({
    required TerminalCursorVisualKey key,
    required TerminalCursorVisualSnapshot Function(TerminalCursorVisualKey key)
    build,
  }) {
    final current = _snapshot;
    if (current != null && current.key == key) {
      return current;
    }
    current?.dispose();
    _snapshot = null;
    final next = build(key);
    _snapshot = next;
    return next;
  }

  void clear() {
    _snapshot?.dispose();
    _snapshot = null;
  }

  void dispose() => clear();
}

final Expando<_TerminalCursorSurfaceState> _terminalCursorSurfaceStates =
    Expando<_TerminalCursorSurfaceState>('terminal-cursor-surface-state');

class _TerminalCursorSurfaceState {
  bool paintCursorOnSurface = true;
  ValueGetter<bool>? blinkVisibility;
  final TerminalCursorVisualSnapshotCache snapshotCache =
      TerminalCursorVisualSnapshotCache();
}

_TerminalCursorSurfaceState _terminalCursorSurfaceStateFor(
  RenderObject renderObject,
) {
  return _terminalCursorSurfaceStates[renderObject] ??=
      _TerminalCursorSurfaceState();
}

void configureTerminalCursorSurface(
  RenderObject renderObject, {
  required bool paintCursorOnSurface,
  required ValueGetter<bool>? blinkVisibility,
}) {
  final state = _terminalCursorSurfaceStateFor(renderObject);
  final modeChanged = state.paintCursorOnSurface != paintCursorOnSurface;
  state.paintCursorOnSurface = paintCursorOnSurface;
  state.blinkVisibility = blinkVisibility;
  if (modeChanged) {
    state.snapshotCache.clear();
    renderObject.markNeedsPaint();
  }
}

bool terminalCursorPaintsOnSurface(RenderObject renderObject) {
  return _terminalCursorSurfaceStateFor(renderObject).paintCursorOnSurface;
}

bool terminalCursorBlinkIsVisible(RenderObject renderObject) {
  return _terminalCursorSurfaceStateFor(renderObject).blinkVisibility?.call() ??
      true;
}

TerminalCursorVisualSnapshotCache terminalCursorSnapshotCacheFor(
  RenderObject renderObject,
) {
  return _terminalCursorSurfaceStateFor(renderObject).snapshotCache;
}

TerminalCursorVisualSnapshot? terminalCursorVisualSnapshotFor(
  RenderObject renderObject,
) {
  return _terminalCursorSurfaceStates[renderObject]?.snapshotCache.snapshot;
}

void disposeTerminalCursorSurface(RenderObject renderObject) {
  _terminalCursorSurfaceStates[renderObject]?.snapshotCache.dispose();
  _terminalCursorSurfaceStates[renderObject] = null;
}

class TerminalCursorOverlay extends LeafRenderObjectWidget {
  const TerminalCursorOverlay({
    super.key,
    required this.visualChanges,
    required this.frameVersion,
    required this.blinkVisibility,
    required this.snapshotProvider,
    this.benchmarkEventSink,
  });

  final Listenable visualChanges;
  final ValueGetter<int> frameVersion;
  final ValueListenable<bool> blinkVisibility;
  final TerminalCursorVisualSnapshot? Function() snapshotProvider;
  final TerminalBenchmarkEventSink? benchmarkEventSink;

  @override
  RenderTerminalCursorOverlay createRenderObject(BuildContext context) {
    return RenderTerminalCursorOverlay(
      visualChanges: visualChanges,
      frameVersion: frameVersion,
      blinkVisibility: blinkVisibility,
      snapshotProvider: snapshotProvider,
      benchmarkEventSink: benchmarkEventSink,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTerminalCursorOverlay renderObject,
  ) {
    renderObject
      ..visualChanges = visualChanges
      ..frameVersion = frameVersion
      ..blinkVisibility = blinkVisibility
      ..snapshotProvider = snapshotProvider
      ..benchmarkEventSink = benchmarkEventSink;
  }
}

class RenderTerminalCursorOverlay extends RenderBox {
  RenderTerminalCursorOverlay({
    required Listenable visualChanges,
    required ValueGetter<int> frameVersion,
    required ValueListenable<bool> blinkVisibility,
    required TerminalCursorVisualSnapshot? Function() snapshotProvider,
    TerminalBenchmarkEventSink? benchmarkEventSink,
  }) : _visualChanges = visualChanges,
       _frameVersion = frameVersion,
       _blinkVisibility = blinkVisibility,
       _snapshotProvider = snapshotProvider,
       _benchmarkEventSink = benchmarkEventSink;

  Listenable _visualChanges;
  ValueGetter<int> _frameVersion;
  ValueListenable<bool> _blinkVisibility;
  TerminalCursorVisualSnapshot? Function() _snapshotProvider;
  TerminalBenchmarkEventSink? _benchmarkEventSink;

  set visualChanges(Listenable value) {
    if (identical(value, _visualChanges)) {
      return;
    }
    if (attached) {
      _visualChanges.removeListener(markNeedsPaint);
    }
    _visualChanges = value;
    if (attached) {
      _visualChanges.addListener(markNeedsPaint);
    }
    markNeedsPaint();
  }

  set frameVersion(ValueGetter<int> value) {
    _frameVersion = value;
  }

  set blinkVisibility(ValueListenable<bool> value) {
    if (identical(value, _blinkVisibility)) {
      return;
    }
    if (attached) {
      _blinkVisibility.removeListener(markNeedsPaint);
    }
    _blinkVisibility = value;
    if (attached) {
      _blinkVisibility.addListener(markNeedsPaint);
    }
    markNeedsPaint();
  }

  set snapshotProvider(TerminalCursorVisualSnapshot? Function() value) {
    _snapshotProvider = value;
  }

  set benchmarkEventSink(TerminalBenchmarkEventSink? value) {
    _benchmarkEventSink = value;
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  Rect get paintBounds => _snapshotProvider()?.rect ?? Rect.zero;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _visualChanges.addListener(markNeedsPaint);
    _blinkVisibility.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _visualChanges.removeListener(markNeedsPaint);
    _blinkVisibility.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.biggest.isFinite ? constraints.biggest : Size.zero;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final snapshot = _snapshotProvider();
    final sink = _benchmarkEventSink;
    final watch = sink == null ? null : (Stopwatch()..start());
    if (snapshot != null && _blinkVisibility.value) {
      context.canvas.save();
      context.canvas.translate(offset.dx, offset.dy);
      context.canvas.drawPicture(snapshot.picture);
      context.canvas.restore();
    }
    watch?.stop();
    if (sink == null) {
      return;
    }
    final key = snapshot?.key;
    sink(<String, Object?>{
      'schema_version': 'ianvs-bench-flutter-cursor-v1',
      'timestamp_micros': DateTime.now().microsecondsSinceEpoch,
      'session_id': 'cursor',
      'frame_version': key?.frameVersion ?? _frameVersion(),
      'paint_kind': 'non_frame',
      'paint_micros': watch?.elapsedMicroseconds ?? 0,
      'paint_bounds_area': snapshot == null
          ? 0
          : snapshot.rect.width * snapshot.rect.height,
      'cell_width_px': key?.cellSize.width ?? 0,
      'cell_height_px': key?.cellSize.height ?? 0,
      'device_pixel_ratio': key?.devicePixelRatio ?? 1,
      'cursor_picture_live_count': snapshot == null ? 0 : 1,
      'cursor_picture_estimated_bytes': snapshot?.estimatedBytes ?? 0,
      'overlay_layer_count': 1,
      'cursor_visible': snapshot != null && _blinkVisibility.value,
    });
  }
}
