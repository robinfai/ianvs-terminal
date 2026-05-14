import '../terminal/terminal.dart' as terminal;

class InstantReplayFrame {
  const InstantReplayFrame({
    required this.sessionId,
    required this.capturedAt,
    required this.text,
  });

  final String sessionId;
  final DateTime capturedAt;
  final String text;
}

class InstantReplayStore {
  InstantReplayStore({this.frameLimit = 60});

  final int frameLimit;
  final Map<String, List<InstantReplayFrame>> _framesBySession =
      <String, List<InstantReplayFrame>>{};

  List<InstantReplayFrame> framesFor(String sessionId) {
    return List<InstantReplayFrame>.unmodifiable(
      _framesBySession[sessionId] ?? const <InstantReplayFrame>[],
    );
  }

  void record(String sessionId, terminal.TerminalFrameDiff frame) {
    final text = _textForFrame(frame);
    if (text.isEmpty) {
      return;
    }
    final frames = _framesBySession.putIfAbsent(
      sessionId,
      () => <InstantReplayFrame>[],
    );
    if (frames.isNotEmpty && frames.first.text == text) {
      return;
    }
    frames.insert(
      0,
      InstantReplayFrame(
        sessionId: sessionId,
        capturedAt: DateTime.now(),
        text: text,
      ),
    );
    if (frames.length > frameLimit) {
      frames.removeRange(frameLimit, frames.length);
    }
  }

  void clear(String sessionId) {
    _framesBySession.remove(sessionId);
  }

  String _textForFrame(terminal.TerminalFrameDiff frame) {
    final rows = frame.rows.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final lines = rows.map((row) => row.text.trimRight()).toList();
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n').trimRight();
  }
}
