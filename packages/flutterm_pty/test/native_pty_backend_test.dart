import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:test/test.dart';

void main() {
  test('native pty backend exposes the planned low-level API', () {
    final backend = NativePtyBackend.fromBindings(_NoopPtyBindings());

    expect(backend.ping(), 42);
    expect(
      backend.createSession('{"launch":{"program":"/bin/sh"}}'),
      '1',
    );
    backend.resizeSession(
      '1',
      cols: 80,
      rows: 24,
      pixelWidth: 800,
      pixelHeight: 600,
    );
    backend.writeInput('1', const [0x41]);
    backend.scrollViewport('1', 3);
    backend.scrollViewportTo('1', 4);
    expect(backend.takeFrameDiffJson('1'), '{"rows":[]}');
    expect(backend.pollEvents('1'), isEmpty);
    backend.closeSession('1');
  });

  test('native pty backend can bridge to the real Rust core', () {
    final backend = NativePtyBackend.load();
    expect(backend.ping(), 42);
  });
}

class _NoopPtyBindings implements PtyBindings {
  @override
  int ping() => 42;

  @override
  int sessionCreateJson(String sessionConfigJson) => 1;

  @override
  int sessionClose(int sessionId) => 0;

  @override
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight,
  ) => 0;

  @override
  int sessionWrite(int sessionId, List<int> bytes) => 0;

  @override
  int sessionScroll(int sessionId, int deltaLines) => 0;

  @override
  int sessionScrollTo(int sessionId, int offset) => 0;

  @override
  String? sessionSearchJson(int sessionId, String query) => '[]';

  @override
  String? sessionSelectionText(int sessionId, String requestJson) => '';

  @override
  String? sessionTakeFrameDiffJson(int sessionId) => '{"rows":[]}';

  @override
  List<PtyEvent> sessionPollEvents(int sessionId) => const [];
}
