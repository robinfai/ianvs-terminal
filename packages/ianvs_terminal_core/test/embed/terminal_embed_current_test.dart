import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

import '../support/terminal_frame_from_json.dart';

void main() {
  testWidgets(
    'session handle exposes only ordered signals from its concrete epoch',
    (tester) async {
      final backend = _CurrentPtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final first = TerminalSessionHandle(
        runtime: runtime,
        sessionConfig: _sessionConfig('first'),
      )..open();
      final second = TerminalSessionHandle(
        runtime: runtime,
        sessionConfig: _sessionConfig('second'),
      )..open();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final firstId = first.sessionId!;

      final signals = <TerminalRuntimeSignal>[];
      final subscription = first.runtimeSignals.listen(signals.add);
      addTearDown(subscription.cancel);

      backend
        ..queueFrame(firstId, title: 'first title')
        ..queueFrame(second.sessionId!, title: 'second title');
      runtime
        ..refreshSession(firstId)
        ..refreshSession(second.sessionId!);
      await tester.pump();

      expect(signals, isNotEmpty);
      expect(
        signals,
        everyElement(
          isA<TerminalRuntimeSignal>()
              .having(
                (signal) => signal.sessionId,
                'sessionId',
                first.sessionId,
              )
              .having(
                (signal) => signal.sessionEpoch,
                'sessionEpoch',
                first.sessionEpoch,
              ),
        ),
      );
      expect(first.frame.windowTitle, 'first title');

      backend.queueExit(firstId, 17);
      runtime.refreshSession(firstId);
      await tester.pump();

      expect(
        signals
            .whereType<TerminalRuntimeSessionEventSignal>()
            .map((signal) => signal.payload)
            .whereType<TerminalSessionExitEvent>()
            .single
            .exitCode,
        17,
      );
      expect(first.isOpen, isFalse);
      expect(backend.closedSessionIds, contains(firstId));
    },
  );

  testWidgets('panel tracks title, exit, and exact tab disposal', (
    tester,
  ) async {
    final backend = _CurrentPtyBackend();
    final runtime = _runtimeFor(backend);
    final controller = TerminalPanelController(
      runtime: runtime,
      initiallyOpen: true,
      defaultTabFactory: (index) => TerminalPanelTabDefinition(
        title: 'Terminal $index',
        sessionConfig: _sessionConfig('panel-$index'),
      ),
    );
    addTearDown(() {
      controller.dispose();
      runtime.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalBottomPanel(
            controller: controller,
            viewportBuilder: (context, session, viewport) => SizedBox(
              key: Key('viewport-${session.sessionId}'),
              child: viewport,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final first = controller.tabs.single;
    backend.queueFrame(first.session.sessionId!, title: 'Build shell');
    runtime.refreshSession(first.session.sessionId!);
    await tester.pump();

    expect(first.title, 'Build shell');
    expect(
      find.byKey(Key('viewport-${first.session.sessionId}')),
      findsOneWidget,
    );

    final second = controller.addTerminal();
    final secondId = second.session.sessionId!;
    await tester.pump();
    controller.closeTab(second.id);
    expect(backend.closedSessionIds, contains(secondId));
    expect(controller.tabs, <TerminalPanelTab>[first]);

    backend.queueExit(first.session.sessionId!, 0);
    runtime.refreshSession(first.session.sessionId!);
    await tester.pump();

    expect(first.exited, isTrue);
    expect(first.exitCode, 0);
    expect(
      backend.closedSessionIds.where((id) => id == first.session.sessionId),
      hasLength(1),
    );
  });

  testWidgets(
    'shutdown freezes product disposal while infrastructure keeps PTY ownership',
    (tester) async {
      final backend = _CurrentPtyBackend();
      final runtime = _runtimeFor(backend);
      final session = TerminalSessionHandle(
        runtime: runtime,
        sessionConfig: _sessionConfig('shutdown'),
      )..open();
      final sessionId = session.sessionId!;

      runtime.beginShutdown();
      session.dispose();
      await tester.pump(const Duration(milliseconds: 100));

      expect(session.disposed, isTrue);
      expect(backend.closedSessionIds, isEmpty);

      runtime.dispose();
      expect(backend.closedSessionIds, <String>[sessionId]);
    },
  );

  testWidgets(
    'an owned panel delegates a busy close only to runtime infrastructure',
    (tester) async {
      final backend = _CurrentPtyBackend()..closeBusy = true;
      final runtime = _runtimeFor(backend);
      final controller = TerminalPanelController(
        runtime: runtime,
        disposeRuntime: true,
        initiallyOpen: true,
        defaultTabFactory: (index) => TerminalPanelTabDefinition(
          title: 'Terminal $index',
          sessionConfig: _sessionConfig('owned-$index'),
        ),
      );
      final tab = controller.tabs.single;

      controller.dispose();

      expect(tab.session.disposed, isTrue);
      expect(runtime.shutdownHasStarted, isTrue);
      expect(runtime.disposed, isFalse);
      expect(backend.closeAttempts, 1);

      backend.closeBusy = false;
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.disposed, isTrue);
      expect(backend.closedSessionIds, <String>['1']);
      expect(backend.closeAttempts, 2);
    },
  );
}

TerminalSessionConfig _sessionConfig(String program) =>
    TerminalSessionConfig(launch: TerminalLaunchConfig(program: program));

TerminalRuntimeController _runtimeFor(_CurrentPtyBackend backend) {
  return TerminalRuntimeController(
    backend: backend,
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: false,
  );
}

final class _CurrentPtyBackend
    implements
        PtySessionBackend,
        PtySessionConfigV1Backend,
        PtySessionFramePacketV1Backend {
  final List<String> closedSessionIds = <String>[];
  final Map<String, List<Uint8List>> _frames = <String, List<Uint8List>>{};
  final Map<String, List<PtyEvent>> _events = <String, List<PtyEvent>>{};
  final Map<String, int> _sequences = <String, int>{};
  bool closeBusy = false;
  int closeAttempts = 0;
  int _nextSessionId = 0;

  @override
  int ping() => 1;

  @override
  String createSessionV1(String sessionConfigV1Json) {
    final id = '${++_nextSessionId}';
    _frames[id] = <Uint8List>[];
    _events[id] = <PtyEvent>[];
    return id;
  }

  void queueFrame(String sessionId, {required String title}) {
    final sequence = (_sequences[sessionId] ?? -1) + 1;
    _sequences[sessionId] = sequence;
    _frames[sessionId]!.add(
      terminalFramePacketBytes(
        sessionId: sessionId,
        sequence: sequence,
        frame: TerminalFrameDiff(
          rows: const <TerminalRow>[TerminalRow(index: 0, text: 'ready')],
          cursor: const TerminalCursor(row: 0, col: 5, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: const <TerminalDirtyRange>[
            TerminalDirtyRange(start: 0, end: 1),
          ],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          windowTitle: title,
        ),
      ),
    );
  }

  void queueExit(String sessionId, int exitCode) {
    _events[sessionId]!.add(
      PtyEvent(
        kind: 'exit',
        sessionId: sessionId,
        payload: <String, Object?>{'code': exitCode},
      ),
    );
  }

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) {
    final frames = _frames[sessionId];
    return frames == null || frames.isEmpty ? null : frames.removeAt(0);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    final events = _events[sessionId];
    if (events == null || events.isEmpty) {
      return const <PtyEvent>[];
    }
    final result = List<PtyEvent>.of(events);
    events.clear();
    return result;
  }

  @override
  void closeSession(String sessionId) {
    closeAttempts += 1;
    if (closeBusy) {
      throw PtyNativeCallException(
        operation: 'closeSession',
        sessionId: sessionId,
        statusCode: -2,
      );
    }
    closedSessionIds.add(sessionId);
    _frames.remove(sessionId);
    _events.remove(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {}

  @override
  void writeInput(String sessionId, List<int> bytes) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}
}
