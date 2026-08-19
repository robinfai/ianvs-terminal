import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws a crisp, theme-adaptive boundary around a recorded viewport.
///
/// The frame is painted over the content, so it does not change the recorded
/// viewport's fitted size. Light and dark themes supply the border color
/// through [ColorScheme.outlineVariant].
class ReplayViewportFrame extends StatelessWidget {
  const ReplayViewportFrame({
    super.key,
    required this.backgroundColor,
    required this.borderRadius,
    required this.child,
  });

  final Color backgroundColor;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return ClipRRect(
      borderRadius: borderRadius,
      child: ColoredBox(
        color: backgroundColor,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: outline),
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Fits a recorded viewport into the currently available Replay area.
///
/// The recording is never enlarged, which keeps terminal glyphs and graphics
/// sharp when the current window is larger than the captured viewport.
class ReplayViewportFit extends StatelessWidget {
  const ReplayViewportFit({
    super.key,
    required this.recordedViewportSize,
    required this.child,
    this.contentKey,
  });

  final Size? recordedViewportSize;
  final Widget child;
  final Key? contentKey;

  static double scaleFor({
    required Size availableSize,
    required Size recordedSize,
  }) {
    if (!_isUsableSize(availableSize) || !_isUsableSize(recordedSize)) {
      return 1;
    }
    return math.min(
      1,
      math.min(
        availableSize.width / recordedSize.width,
        availableSize.height / recordedSize.height,
      ),
    );
  }

  static bool _isUsableSize(Size size) {
    return size.width.isFinite &&
        size.height.isFinite &&
        size.width > 0 &&
        size.height > 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableSize = Size(constraints.maxWidth, constraints.maxHeight);
        final requestedSize = recordedViewportSize;
        final recordedSize =
            requestedSize != null && _isUsableSize(requestedSize)
            ? requestedSize
            : availableSize;
        final scale = scaleFor(
          availableSize: availableSize,
          recordedSize: recordedSize,
        );
        final displayedSize = Size(
          recordedSize.width * scale,
          recordedSize.height * scale,
        );
        final percentage = (scale * 100).round();

        return Semantics(
          container: true,
          label: 'Replay viewport fit $percentage percent',
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: displayedSize.width,
              height: displayedSize.height,
              child: FittedBox(
                fit: BoxFit.fill,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  key: contentKey,
                  width: recordedSize.width,
                  height: recordedSize.height,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Places Replay controls above the recorded viewport without consuming its
/// layout height. The controls can be moved from their dedicated drag strip.
class ReplayFloatingStage extends StatefulWidget {
  const ReplayFloatingStage({
    super.key,
    required this.recordedViewportSize,
    required this.viewport,
    required this.dock,
    required this.dragHandleColor,
    this.viewportFitKey,
    this.viewportContentKey,
    this.floatingDockKey,
    this.dragHandleKey,
    this.onAvailableSizeChanged,
    this.onDockDragStateChanged,
    this.maxDockWidth = 1180,
    this.margin = 8,
    this.bottomInset = 0,
  });

  final Size? recordedViewportSize;
  final Widget viewport;
  final Widget dock;
  final Color dragHandleColor;
  final Key? viewportFitKey;
  final Key? viewportContentKey;
  final Key? floatingDockKey;
  final Key? dragHandleKey;
  final ValueChanged<Size>? onAvailableSizeChanged;
  final ValueChanged<bool>? onDockDragStateChanged;
  final double maxDockWidth;
  final double margin;
  final double bottomInset;

  @override
  State<ReplayFloatingStage> createState() => _ReplayFloatingStageState();
}

class _ReplayFloatingStageState extends State<ReplayFloatingStage> {
  static const _dragStripHeight = 22.0;
  static const _snapDistance = 28.0;

  final GlobalKey _dockMeasureKey = GlobalKey();
  final ValueNotifier<_ReplayDockMotion> _dockMotion =
      ValueNotifier<_ReplayDockMotion>(const _ReplayDockMotion());
  Size _dockSize = Size.zero;
  Size? _reportedAvailableSize;
  bool _dockMeasurementPending = false;

  void _setDockMotion(_ReplayDockMotion motion) {
    final wasDragging = _dockMotion.value.dragging;
    _dockMotion.value = motion;
    if (wasDragging != motion.dragging) {
      widget.onDockDragStateChanged?.call(motion.dragging);
    }
  }

  void _measureDock() {
    if (_dockMeasurementPending) {
      return;
    }
    _dockMeasurementPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dockMeasurementPending = false;
      if (!mounted) {
        return;
      }
      final renderBox =
          _dockMeasureKey.currentContext?.findRenderObject() as RenderBox?;
      final size = renderBox?.size;
      if (size != null && size != _dockSize) {
        setState(() {
          _dockSize = size;
        });
      }
    });
  }

  @override
  void dispose() {
    _dockMotion.dispose();
    super.dispose();
  }

  void _reportAvailableSize(Size size) {
    if (_reportedAvailableSize == size) {
      return;
    }
    _reportedAvailableSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reportedAvailableSize == size) {
        widget.onAvailableSizeChanged?.call(size);
      }
    });
  }

  _ReplayDockGeometry _geometryFor(
    Size stageSize,
    double dockWidth,
    Offset dockOffset,
  ) {
    final dockHeight = _dockSize.height;
    final bottomInset = _bottomInsetFor(stageSize);
    final baseLeft = (stageSize.width - dockWidth) / 2;
    final baseTop = math.max(
      widget.margin,
      stageSize.height - widget.margin - bottomInset - dockHeight,
    );
    final maxLeft = math.max(
      widget.margin,
      stageSize.width - widget.margin - dockWidth,
    );
    final maxTop = math.max(
      widget.margin,
      stageSize.height - widget.margin - bottomInset - dockHeight,
    );
    final left = (baseLeft + dockOffset.dx).clamp(widget.margin, maxLeft);
    final top = (baseTop + dockOffset.dy).clamp(widget.margin, maxTop);
    return _ReplayDockGeometry(
      baseLeft: baseLeft,
      baseTop: baseTop,
      left: left,
      top: top,
      maxTop: maxTop,
    );
  }

  double _bottomInsetFor(Size stageSize) {
    return widget.bottomInset.clamp(
      0,
      math.max(0, stageSize.height - widget.margin * 2),
    );
  }

  void _moveDock(DragUpdateDetails details, Size stageSize, double dockWidth) {
    final motion = _dockMotion.value;
    final geometry = _geometryFor(stageSize, dockWidth, motion.offset);
    final maxLeft = math.max(
      widget.margin,
      stageSize.width - widget.margin - dockWidth,
    );
    final nextLeft = (geometry.left + details.delta.dx).clamp(
      widget.margin,
      maxLeft,
    );
    final nextTop = (geometry.top + details.delta.dy).clamp(
      widget.margin,
      geometry.maxTop,
    );
    _setDockMotion(
      _ReplayDockMotion(
        dragging: true,
        offset: Offset(
          nextLeft - geometry.baseLeft,
          nextTop - geometry.baseTop,
        ),
      ),
    );
  }

  void _finishMovingDock(Size stageSize, double dockWidth) {
    final geometry = _geometryFor(
      stageSize,
      dockWidth,
      _dockMotion.value.offset,
    );
    var top = geometry.top;
    if (top - widget.margin <= _snapDistance) {
      top = widget.margin;
    } else if (geometry.maxTop - top <= _snapDistance) {
      top = geometry.maxTop;
    }
    _setDockMotion(
      _ReplayDockMotion(
        offset: Offset(
          geometry.left - geometry.baseLeft,
          top - geometry.baseTop,
        ),
      ),
    );
  }

  void _resetDock() {
    _setDockMotion(const _ReplayDockMotion());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageSize = Size(constraints.maxWidth, constraints.maxHeight);
        _reportAvailableSize(stageSize);
        final availableDockWidth = math.max(
          0.0,
          stageSize.width - widget.margin * 2,
        );
        final dockWidth = math.min(widget.maxDockWidth, availableDockWidth);
        final baseGeometry = _geometryFor(stageSize, dockWidth, Offset.zero);
        _measureDock();

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: ReplayViewportFit(
                  key: widget.viewportFitKey,
                  recordedViewportSize: widget.recordedViewportSize,
                  contentKey: widget.viewportContentKey,
                  child: widget.viewport,
                ),
              ),
              Positioned(
                left: baseGeometry.baseLeft,
                top: baseGeometry.baseTop,
                width: dockWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(
                      0,
                      stageSize.height - widget.margin * 2,
                    ),
                  ),
                  child: ValueListenableBuilder<_ReplayDockMotion>(
                    valueListenable: _dockMotion,
                    child: RepaintBoundary(child: widget.dock),
                    builder: (context, motion, dock) {
                      final geometry = _geometryFor(
                        stageSize,
                        dockWidth,
                        motion.offset,
                      );
                      return Transform.translate(
                        offset: Offset(
                          geometry.left - geometry.baseLeft,
                          geometry.top - geometry.baseTop,
                        ),
                        transformHitTests: true,
                        child: KeyedSubtree(
                          key: widget.floatingDockKey,
                          child: Stack(
                            key: _dockMeasureKey,
                            clipBehavior: Clip.none,
                            children: [
                              dock!,
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: _dragStripHeight,
                                child: Semantics(
                                  label:
                                      'Drag replay controls. Double tap to reset position.',
                                  button: true,
                                  child: MouseRegion(
                                    cursor: motion.dragging
                                        ? SystemMouseCursors.grabbing
                                        : SystemMouseCursors.grab,
                                    child: GestureDetector(
                                      key: widget.dragHandleKey,
                                      behavior: HitTestBehavior.translucent,
                                      onDoubleTap: _resetDock,
                                      onPanStart: (_) {
                                        _setDockMotion(
                                          _ReplayDockMotion(
                                            offset: motion.offset,
                                            dragging: true,
                                          ),
                                        );
                                      },
                                      onPanUpdate: (details) => _moveDock(
                                        details,
                                        stageSize,
                                        dockWidth,
                                      ),
                                      onPanEnd: (_) => _finishMovingDock(
                                        stageSize,
                                        dockWidth,
                                      ),
                                      onPanCancel: () => _finishMovingDock(
                                        stageSize,
                                        dockWidth,
                                      ),
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 7,
                                          ),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: widget.dragHandleColor
                                                  .withValues(
                                                    alpha: motion.dragging
                                                        ? 0.78
                                                        : 0.52,
                                                  ),
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                            child: const SizedBox(
                                              width: 38,
                                              height: 4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReplayDockMotion {
  const _ReplayDockMotion({this.offset = Offset.zero, this.dragging = false});

  final Offset offset;
  final bool dragging;
}

class _ReplayDockGeometry {
  const _ReplayDockGeometry({
    required this.baseLeft,
    required this.baseTop,
    required this.left,
    required this.top,
    required this.maxTop,
  });

  final double baseLeft;
  final double baseTop;
  final double left;
  final double top;
  final double maxTop;
}
