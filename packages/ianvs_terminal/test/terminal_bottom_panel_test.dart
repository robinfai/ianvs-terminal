import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  group('TerminalPanelController', () {
    test('owns every tab session and closes it with the host lifecycle', () {
      final backend = _RecordingPtyBackend();
      final runtime = _runtimeFor(backend);
      final controller = TerminalPanelController(
        runtime: runtime,
        initiallyOpen: true,
        defaultTabFactory: _tabDefinition,
      );

      expect(controller.tabs, hasLength(1));
      expect(backend.createdSessionIds, ['session-1']);

      final firstTab = controller.tabs.single;
      final secondTab = controller.addTerminal();
      expect(controller.activeTabId, secondTab.id);
      expect(backend.createdSessionIds, ['session-1', 'session-2']);

      controller.setOpen(false);
      expect(backend.closedSessionIds, isEmpty);

      controller.closeTab(firstTab.id);
      expect(backend.closedSessionIds, ['session-1']);

      controller.dispose();
      expect(backend.closedSessionIds, ['session-1', 'session-2']);
      runtime.dispose();
    });

    test('default local tab always resolves an executable program', () {
      final definition = defaultLocalTerminalPanelTab(1);

      expect(definition.title, 'Local Terminal');
      expect(definition.sessionConfig.launch.program, isNotEmpty);
    });
  });

  testWidgets(
    'toggle, plus, custom viewport, and host disposal form one lifecycle',
    (tester) async {
      final backend = _RecordingPtyBackend();
      final runtime = _runtimeFor(backend);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: _TerminalHostHarness(runtime: runtime),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('custom-session-1')), findsOneWidget);
      expect(backend.createdSessionIds, ['session-1']);

      await tester.tap(find.byKey(const Key('terminal-panel-add')));
      await tester.pump();
      expect(find.byKey(const Key('custom-session-2')), findsOneWidget);
      expect(backend.createdSessionIds, ['session-1', 'session-2']);

      await tester.tap(find.byKey(const Key('terminal-panel-toggle')));
      await tester.pump();
      expect(find.byKey(const Key('custom-session-1')), findsNothing);
      expect(backend.closedSessionIds, isEmpty);

      await tester.tap(find.byKey(const Key('terminal-panel-toggle')));
      await tester.pump();
      expect(find.byKey(const Key('custom-session-2')), findsOneWidget);
      expect(backend.createdSessionIds, ['session-1', 'session-2']);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(backend.closedSessionIds, containsAll(['session-1', 'session-2']));
    },
  );

  testWidgets('tab close releases only that tab session', (tester) async {
    final backend = _RecordingPtyBackend();
    final runtime = _runtimeFor(backend);
    final controller = TerminalPanelController(
      runtime: runtime,
      initiallyOpen: true,
      defaultTabFactory: _tabDefinition,
    )..addTerminal();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              TerminalBottomPanel(controller: controller),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('terminal-panel-tab-close-terminal-1')),
    );
    await tester.pump();

    expect(controller.tabs.map((tab) => tab.id), ['terminal-2']);
    expect(backend.closedSessionIds, ['session-1']);
    expect(backend.activeSessionIds, contains('session-2'));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    runtime.dispose();
  });
}

TerminalPanelTabDefinition _tabDefinition(int index) {
  return TerminalPanelTabDefinition(
    title: 'ianvs-terminal $index',
    sessionConfig: TerminalSessionConfig(
      launch: TerminalLaunchConfig(program: 'fake-shell-$index'),
    ),
  );
}

TerminalRuntimeController _runtimeFor(_RecordingPtyBackend backend) {
  return TerminalRuntimeController(
    backend: backend,
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: false,
  );
}

class _TerminalHostHarness extends StatefulWidget {
  const _TerminalHostHarness({required this.runtime});

  final TerminalRuntimeController runtime;

  @override
  State<_TerminalHostHarness> createState() => _TerminalHostHarnessState();
}

class _TerminalHostHarnessState extends State<_TerminalHostHarness> {
  late final TerminalPanelController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TerminalPanelController(
      runtime: widget.runtime,
      initiallyOpen: true,
      defaultTabFactory: _tabDefinition,
      disposeRuntime: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: TerminalPanelToggleButton(controller: _controller),
          ),
          const Expanded(child: SizedBox()),
          TerminalBottomPanel(
            controller: _controller,
            viewportBuilder: (context, terminal, viewport) {
              return DecoratedBox(
                key: Key('custom-${terminal.sessionId}'),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                child: viewport,
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _RecordingPtyBackend implements PtySessionBackend {
  final List<String> createdSessionIds = <String>[];
  final List<String> closedSessionIds = <String>[];
  final Set<String> activeSessionIds = <String>{};
  int _nextSessionId = 0;

  @override
  int ping() => 1;

  @override
  String createSession(String sessionConfigJson) {
    final sessionId = 'session-${++_nextSessionId}';
    createdSessionIds.add(sessionId);
    activeSessionIds.add(sessionId);
    return sessionId;
  }

  @override
  void closeSession(String sessionId) {
    closedSessionIds.add(sessionId);
    activeSessionIds.remove(sessionId);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

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
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? takeFrameDiffJson(String sessionId) => null;

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}
