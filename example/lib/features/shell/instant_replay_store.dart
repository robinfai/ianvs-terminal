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
}

class InstantReplaySemanticEvent {
  const InstantReplaySemanticEvent({
    required this.sessionId,
    required this.capturedAt,
    required this.kind,
    this.command,
    this.cwd,
    this.hostname,
    this.exitCode,
    this.remote = false,
  });

  final String sessionId;
  final DateTime capturedAt;
  final terminal.TerminalRecordingSemanticKind kind;
  final String? command;
  final String? cwd;
  final String? hostname;
  final int? exitCode;
  final bool remote;
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
  final Map<String, List<InstantReplaySemanticEvent>> _semanticsBySession =
      <String, List<InstantReplaySemanticEvent>>{};

  List<InstantReplayFrame> framesFor(String sessionId) {
    return List<InstantReplayFrame>.unmodifiable(
      _framesBySession[sessionId] ?? const <InstantReplayFrame>[],
    );
  }

  List<InstantReplayFrame> framesForReplay(String sessionId) {
    return List<InstantReplayFrame>.unmodifiable(framesFor(sessionId).reversed);
  }

  List<InstantReplaySemanticEvent> semanticsForReplay(String sessionId) {
    final frames = _framesBySession[sessionId];
    final semantics = _semanticsBySession[sessionId];
    if (frames == null ||
        frames.isEmpty ||
        semantics == null ||
        semantics.isEmpty) {
      return const <InstantReplaySemanticEvent>[];
    }
    final oldest = frames.last.capturedAt;
    final newest = frames.first.capturedAt;
    return List<InstantReplaySemanticEvent>.unmodifiable(
      semantics.where(
        (event) =>
            !event.capturedAt.isBefore(oldest) &&
            !event.capturedAt.isAfter(newest),
      ),
    );
  }

  void recordSemantic(
    String sessionId, {
    required terminal.TerminalRecordingSemanticKind kind,
    String? command,
    String? cwd,
    String? hostname,
    int? exitCode,
    bool remote = false,
  }) {
    if (frameLimit <= 0) {
      _semanticsBySession.remove(sessionId);
      return;
    }
    final events = _semanticsBySession.putIfAbsent(
      sessionId,
      () => <InstantReplaySemanticEvent>[],
    );
    final candidate = InstantReplaySemanticEvent(
      sessionId: sessionId,
      capturedAt: _now(),
      kind: kind,
      command: command,
      cwd: cwd,
      hostname: hostname,
      exitCode: exitCode,
      remote: remote,
    );
    if (events.isNotEmpty) {
      final previous = events.last;
      final sameCommand =
          previous.command == candidate.command ||
          previous.command == null ||
          candidate.command == null;
      if (previous.kind == candidate.kind &&
          sameCommand &&
          previous.remote == candidate.remote &&
          candidate.capturedAt.difference(previous.capturedAt) <
              const Duration(milliseconds: 80)) {
        events[events.length - 1] = InstantReplaySemanticEvent(
          sessionId: sessionId,
          capturedAt: previous.capturedAt,
          kind: candidate.kind,
          command: candidate.command ?? previous.command,
          cwd: candidate.cwd ?? previous.cwd,
          hostname: candidate.hostname ?? previous.hostname,
          exitCode: candidate.exitCode ?? previous.exitCode,
          remote: candidate.remote,
        );
        return;
      }
    }
    events.add(candidate);
    final maximumSemanticEvents = frameLimit * 4;
    if (events.length > maximumSemanticEvents) {
      events.removeRange(0, events.length - maximumSemanticEvents);
    }
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
      _semanticsBySession.remove(sessionId);
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
    final semantics = _semanticsBySession[sessionId];
    if (semantics != null && frames.isNotEmpty) {
      final oldest = frames.last.capturedAt;
      semantics.removeWhere((event) => event.capturedAt.isBefore(oldest));
    }
  }

  void clear(String sessionId) {
    _framesBySession.remove(sessionId);
    _stateBySession.remove(sessionId);
    _semanticsBySession.remove(sessionId);
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
