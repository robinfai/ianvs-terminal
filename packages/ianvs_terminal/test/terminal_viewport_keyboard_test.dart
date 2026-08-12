import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  testWidgets(
    'terminal handles command-q before an unhandled event bubbles to the host',
    (tester) async {
      final calls = <String>[];
      final runtime = TerminalRuntimeController(
        backend: _NoopPtyBackend(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final controller = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = _RecordingTerminalInputController(
        runtime: runtime,
        onHandle: (event) => calls.add('terminal:${event.logicalKey.keyLabel}'),
      );
      addTearDown(runtime.dispose);
      addTearDown(controller.dispose);
      addTearDown(selectionController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 200,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              onHostKeyEvent: (event) {
                calls.add('host:${event.logicalKey.keyLabel}');
                return KeyEventResult.handled;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      calls.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ, platform: 'macos');
      expect(calls, <String>['terminal:Q', 'host:Q']);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ, platform: 'macos');

      calls.clear();
      inputController.result = KeyEventResult.handled;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ, platform: 'macos');
      expect(calls, <String>['terminal:Q']);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
    },
  );
}

class _RecordingTerminalInputController extends TerminalInputController {
  _RecordingTerminalInputController({
    required super.runtime,
    required this.onHandle,
  }) : super(
         sessionId: '1',
         readSelection: () => '',
         copySelection: (_) async {},
         readClipboard: () async => '',
       );

  final ValueChanged<KeyEvent> onHandle;
  KeyEventResult result = KeyEventResult.ignored;

  @override
  KeyEventResult handle(KeyEvent event) {
    onHandle(event);
    return result;
  }
}

class _NoopPtyBackend implements PtySessionBackend {
  @override
  void closeSession(String sessionId) {}

  @override
  int ping() => 42;

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
  void writeInput(String sessionId, List<int> bytes) {}
}
