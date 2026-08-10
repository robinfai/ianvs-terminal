import 'dart:math' as math;
import 'dart:ui';

import '../config/terminal_defaults.dart';

final class TerminalResizeCoordinator {
  TerminalResizeCoordinator({this.maxDimension = maxTerminalDimension})
    : assert(maxDimension > 0, 'maxDimension must be positive.');

  final int maxDimension;
  final Map<String, TerminalResizeMetric> _lastMetrics =
      <String, TerminalResizeMetric>{};

  TerminalResizeMetric? metricFor(String sessionId) => _lastMetrics[sessionId];

  TerminalResizePlan? planViewportResize(
    String sessionId, {
    required Size viewportSize,
    required double devicePixelRatio,
    required Size cellSize,
  }) {
    if (!_isPositiveFiniteSize(viewportSize) ||
        !_isPositiveFiniteDouble(devicePixelRatio) ||
        !_isPositiveFiniteSize(cellSize)) {
      return null;
    }

    final cols = _boundedDimension(
      math.max(20, (viewportSize.width / cellSize.width).floor()),
    );
    final rows = _boundedDimension(
      math.max(8, (viewportSize.height / cellSize.height).floor()),
    );
    final metric = _metricFor(
      cols: cols,
      rows: rows,
      logicalWidth: viewportSize.width,
      logicalHeight: viewportSize.height,
      devicePixelRatio: devicePixelRatio,
      cellSize: cellSize,
    );
    return _planFor(sessionId, metric: metric, viewportSize: viewportSize);
  }

  TerminalResizePlan planCellResize(
    String sessionId, {
    required int cols,
    required int rows,
    double devicePixelRatio = 1,
    required Size cellSize,
  }) {
    if (cols <= 0 || rows <= 0 || !_isPositiveFiniteDouble(devicePixelRatio)) {
      throw RangeError(
        'Terminal dimensions and devicePixelRatio must be positive.',
      );
    }
    if (!_isPositiveFiniteSize(cellSize)) {
      throw RangeError('Cell size must be positive and finite.');
    }

    final boundedCols = _boundedDimension(cols);
    final boundedRows = _boundedDimension(rows);
    final logicalWidth = boundedCols * cellSize.width;
    final logicalHeight = boundedRows * cellSize.height;
    final metric = _metricFor(
      cols: boundedCols,
      rows: boundedRows,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      devicePixelRatio: devicePixelRatio,
      cellSize: cellSize,
    );
    return _planFor(
      sessionId,
      metric: metric,
      viewportSize: Size(logicalWidth, logicalHeight),
    );
  }

  TerminalResizePlan? planNativeResizeEvent(
    String sessionId, {
    required int cols,
    required int rows,
    required Size cellSize,
  }) {
    final previous = _lastMetrics[sessionId];
    if (cols <= 0 ||
        rows <= 0 ||
        previous == null ||
        !_isPositiveFiniteSize(cellSize)) {
      return null;
    }

    final boundedCols = _boundedDimension(cols);
    final boundedRows = _boundedDimension(rows);
    final logicalWidth = boundedCols * cellSize.width;
    final logicalHeight = boundedRows * cellSize.height;
    final metric = _metricFor(
      cols: boundedCols,
      rows: boundedRows,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      devicePixelRatio: previous.devicePixelRatio,
      cellSize: cellSize,
    );
    return _planFor(
      sessionId,
      metric: metric,
      viewportSize: Size(logicalWidth, logicalHeight),
      widthDelta: logicalWidth - previous.logicalWidth,
      heightDelta: logicalHeight - previous.logicalHeight,
    );
  }

  void commit(String sessionId, TerminalResizeMetric metric) {
    _lastMetrics[sessionId] = metric;
  }

  void remove(String sessionId) {
    _lastMetrics.remove(sessionId);
  }

  TerminalResizePlan _planFor(
    String sessionId, {
    required TerminalResizeMetric metric,
    required Size viewportSize,
    double widthDelta = 0,
    double heightDelta = 0,
  }) {
    return TerminalResizePlan(
      metric: metric,
      viewportSize: viewportSize,
      isDuplicate: _lastMetrics[sessionId]?.sameNativeResize(metric) ?? false,
      widthDelta: widthDelta,
      heightDelta: heightDelta,
    );
  }

  TerminalResizeMetric _metricFor({
    required int cols,
    required int rows,
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
    required Size cellSize,
  }) {
    return TerminalResizeMetric(
      cols: cols,
      rows: rows,
      pixelWidth: _boundedPixelDimension(logicalWidth * devicePixelRatio),
      pixelHeight: _boundedPixelDimension(logicalHeight * devicePixelRatio),
      cellWidth: _boundedPixelDimension(cellSize.width * devicePixelRatio),
      cellHeight: _boundedPixelDimension(cellSize.height * devicePixelRatio),
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      logicalCellWidth: cellSize.width,
      logicalCellHeight: cellSize.height,
      devicePixelRatio: devicePixelRatio,
    );
  }

  int _boundedDimension(int value) {
    return value.clamp(1, maxDimension);
  }

  int _boundedPixelDimension(double value) {
    if (!value.isFinite || value <= 0) {
      return 1;
    }
    return value.round().clamp(1, maxDimension);
  }

  static bool _isPositiveFiniteSize(Size size) {
    return _isPositiveFiniteDouble(size.width) &&
        _isPositiveFiniteDouble(size.height);
  }

  static bool _isPositiveFiniteDouble(double value) {
    return value.isFinite && value > 0;
  }
}

final class TerminalResizePlan {
  const TerminalResizePlan({
    required this.metric,
    required this.viewportSize,
    required this.isDuplicate,
    this.widthDelta = 0,
    this.heightDelta = 0,
  });

  final TerminalResizeMetric metric;
  final Size viewportSize;
  final bool isDuplicate;
  final double widthDelta;
  final double heightDelta;
}

final class TerminalResizeMetric {
  const TerminalResizeMetric({
    required this.cols,
    required this.rows,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.cellWidth,
    required this.cellHeight,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.logicalCellWidth,
    required this.logicalCellHeight,
    required this.devicePixelRatio,
  });

  final int cols;
  final int rows;
  final int pixelWidth;
  final int pixelHeight;
  final int cellWidth;
  final int cellHeight;
  final double logicalWidth;
  final double logicalHeight;
  final double logicalCellWidth;
  final double logicalCellHeight;
  final double devicePixelRatio;

  bool sameNativeResize(TerminalResizeMetric other) {
    return cols == other.cols &&
        rows == other.rows &&
        pixelWidth == other.pixelWidth &&
        pixelHeight == other.pixelHeight &&
        cellWidth == other.cellWidth &&
        cellHeight == other.cellHeight &&
        logicalWidth == other.logicalWidth &&
        logicalHeight == other.logicalHeight &&
        logicalCellWidth == other.logicalCellWidth &&
        logicalCellHeight == other.logicalCellHeight &&
        devicePixelRatio == other.devicePixelRatio;
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalResizeMetric &&
        cols == other.cols &&
        rows == other.rows &&
        pixelWidth == other.pixelWidth &&
        pixelHeight == other.pixelHeight &&
        cellWidth == other.cellWidth &&
        cellHeight == other.cellHeight &&
        logicalWidth == other.logicalWidth &&
        logicalHeight == other.logicalHeight &&
        logicalCellWidth == other.logicalCellWidth &&
        logicalCellHeight == other.logicalCellHeight &&
        devicePixelRatio == other.devicePixelRatio;
  }

  @override
  int get hashCode => Object.hash(
    cols,
    rows,
    pixelWidth,
    pixelHeight,
    cellWidth,
    cellHeight,
    logicalWidth,
    logicalHeight,
    logicalCellWidth,
    logicalCellHeight,
    devicePixelRatio,
  );
}
