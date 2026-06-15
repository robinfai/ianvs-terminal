import 'dart:ui' show Size;

import '../terminal/terminal.dart' as terminal;

class InstantReplayFrame {
  const InstantReplayFrame({
    required this.sessionId,
    required this.capturedAt,
    required this.frame,
    required this.snapshot,
    this.viewportLogicalSize,
    this.viewportPixelSize,
    this.devicePixelRatio,
    this.windowContentSize,
    this.windowFrameSize,
  });

  final String sessionId;
  final DateTime capturedAt;
  final terminal.TerminalFrameDiff frame;
  final terminal.TerminalFrameDiff snapshot;
  final Size? viewportLogicalSize;
  final Size? viewportPixelSize;
  final double? devicePixelRatio;
  final Size? windowContentSize;
  final Size? windowFrameSize;

  String get text => _textForFrame(snapshot);

  bool snapshotIntersectsRows({
    required int startRow,
    required int endRowExclusive,
  }) {
    if (endRowExclusive <= startRow) {
      return false;
    }
    for (final row in snapshot.rows) {
      if (row.index >= startRow && row.index < endRowExclusive) {
        return true;
      }
    }
    return false;
  }
}

class InstantReplayStore {
  InstantReplayStore({this.frameLimit = 60, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final int frameLimit;
  final DateTime Function() _now;
  final Map<String, List<InstantReplayFrame>> _framesBySession =
      <String, List<InstantReplayFrame>>{};
  final Map<String, terminal.TerminalViewportState> _stateBySession =
      <String, terminal.TerminalViewportState>{};

  List<InstantReplayFrame> framesFor(String sessionId) {
    return List<InstantReplayFrame>.unmodifiable(
      _framesBySession[sessionId] ?? const <InstantReplayFrame>[],
    );
  }

  List<InstantReplayFrame> framesForReplay(String sessionId) {
    return List<InstantReplayFrame>.unmodifiable(framesFor(sessionId).reversed);
  }

  InstantReplayFrame? frameForRows(
    String sessionId, {
    required int startRow,
    required int endRowExclusive,
  }) {
    if (endRowExclusive <= startRow) {
      return null;
    }
    for (final frame in framesFor(sessionId)) {
      if (frame.snapshotIntersectsRows(
        startRow: startRow,
        endRowExclusive: endRowExclusive,
      )) {
        return frame;
      }
    }
    return null;
  }

  void record(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    Size? viewportLogicalSize,
    Size? viewportPixelSize,
    double? devicePixelRatio,
    Size? windowContentSize,
    Size? windowFrameSize,
  }) {
    if (!_isRecordableFrame(frame)) {
      return;
    }
    if (frameLimit <= 0) {
      _framesBySession.remove(sessionId);
      _stateBySession.remove(sessionId);
      return;
    }
    final capturedAt = _now();
    final restoredState =
        (_stateBySession[sessionId] ?? terminal.TerminalViewportState.empty)
            .applyFrame(frame, capturedAt: capturedAt);
    _stateBySession[sessionId] = restoredState;
    final snapshot = restoredState
        .applySnapshot(restoredState.frame, capturedAt: capturedAt)
        .frame;
    final frames = _framesBySession.putIfAbsent(
      sessionId,
      () => <InstantReplayFrame>[],
    );
    if (frames.isNotEmpty &&
        _frameSignature(frames.first.frame) == _frameSignature(frame)) {
      frames[0] = _mergeFrameMetadata(
        frames.first,
        viewportLogicalSize: viewportLogicalSize,
        viewportPixelSize: viewportPixelSize,
        devicePixelRatio: devicePixelRatio,
        windowContentSize: windowContentSize,
        windowFrameSize: windowFrameSize,
      );
      return;
    }
    frames.insert(
      0,
      InstantReplayFrame(
        sessionId: sessionId,
        capturedAt: capturedAt,
        frame: frame,
        snapshot: snapshot,
        viewportLogicalSize: viewportLogicalSize,
        viewportPixelSize: viewportPixelSize,
        devicePixelRatio: devicePixelRatio,
        windowContentSize: windowContentSize,
        windowFrameSize: windowFrameSize,
      ),
    );
    if (frames.length > frameLimit) {
      frames.removeRange(frameLimit, frames.length);
    }
  }

  void clear(String sessionId) {
    _framesBySession.remove(sessionId);
    _stateBySession.remove(sessionId);
  }

  void enrichSessionMetadata(
    String sessionId, {
    Size? viewportLogicalSize,
    Size? viewportPixelSize,
    double? devicePixelRatio,
    Size? windowContentSize,
    Size? windowFrameSize,
  }) {
    final frames = _framesBySession[sessionId];
    if (frames == null || frames.isEmpty) {
      return;
    }
    for (var index = 0; index < frames.length; index += 1) {
      final existing = frames[index];
      final existingViewportSize = existing.viewportLogicalSize;
      if (viewportLogicalSize == null && existingViewportSize != null) {
        continue;
      }
      if (existingViewportSize != null &&
          viewportLogicalSize != null &&
          existingViewportSize != viewportLogicalSize) {
        continue;
      }
      frames[index] = _mergeFrameMetadata(
        existing,
        viewportLogicalSize: viewportLogicalSize,
        viewportPixelSize: viewportPixelSize,
        devicePixelRatio: devicePixelRatio,
        windowContentSize: windowContentSize,
        windowFrameSize: windowFrameSize,
      );
    }
  }

  bool _isRecordableFrame(terminal.TerminalFrameDiff frame) {
    return frame.viewportRows > 0 &&
        frame.viewportCols > 0 &&
        frame.rows.isNotEmpty;
  }

  String _frameSignature(terminal.TerminalFrameDiff frame) {
    final buffer = StringBuffer()
      ..write(frame.viewportRows)
      ..write('x')
      ..write(frame.viewportCols)
      ..write('|')
      ..write(frame.cursor.row)
      ..write(':')
      ..write(frame.cursor.col)
      ..write(':')
      ..write(frame.cursor.visible)
      ..write('|');
    final rows = frame.rows.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final row in rows) {
      buffer
        ..write(row.index)
        ..write('=')
        ..write(row.text)
        ..write('\n');
    }
    return buffer.toString();
  }

  InstantReplayFrame _mergeFrameMetadata(
    InstantReplayFrame existing, {
    Size? viewportLogicalSize,
    Size? viewportPixelSize,
    double? devicePixelRatio,
    Size? windowContentSize,
    Size? windowFrameSize,
  }) {
    return InstantReplayFrame(
      sessionId: existing.sessionId,
      capturedAt: existing.capturedAt,
      frame: existing.frame,
      snapshot: existing.snapshot,
      viewportLogicalSize: viewportLogicalSize ?? existing.viewportLogicalSize,
      viewportPixelSize: viewportPixelSize ?? existing.viewportPixelSize,
      devicePixelRatio: devicePixelRatio ?? existing.devicePixelRatio,
      windowContentSize: windowContentSize ?? existing.windowContentSize,
      windowFrameSize: windowFrameSize ?? existing.windowFrameSize,
    );
  }
}

String _textForFrame(terminal.TerminalFrameDiff frame) {
  final rows = frame.rows.toList()..sort((a, b) => a.index.compareTo(b.index));
  final lines = rows.map((row) => row.text.trimRight()).toList();
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n').trimRight();
}
