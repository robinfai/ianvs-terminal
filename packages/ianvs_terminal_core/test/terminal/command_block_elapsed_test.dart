import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

class _TimedOutput {
  int? start = DateTime.now().millisecondsSinceEpoch - 62000;
  int? finish;
  bool running = true;
  int requests = 0;

  Map<String, Object?> request(Map<String, Object?> args) {
    requests++;
    final block = {
      'id': 'timed',
      'command': 'tail -f service.log',
      'running': running,
      'exitCode': running ? null : 0,
      'startedAt': start,
      'finishedAt': finish,
      'totalLines': 10,
      'matchingLines': 10,
      'columns': 40,
      'lines': [
        for (var i = 0; i < 10; i++)
          {'index': i, 'source_row': i, 'text': 'output $i'},
      ],
    };
    return args['id'] == null
        ? {
            'blocks': [block],
          }
        : {'block': block};
  }
}

Future<void> _mount(
  WidgetTester tester,
  CommandBlockController controller, {
  required bool phone,
  bool chinese = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(320, 568)
      : const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        platform: phone ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      home: Scaffold(
        body: TerminalCommandBlocksView(
          controller: controller,
          chinese: chinese,
          onReinput: (_) => fail('Elapsed time cannot submit input'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final phone in [false, true]) {
    for (final chinese in [false, true]) {
      testWidgets('elapsed survives refresh and freezes at native finish '
          '(phone $phone, Chinese $chinese)', (tester) async {
        final output = _TimedOutput();
        final controller = CommandBlockController(request: output.request)
          ..refresh();
        addTearDown(controller.dispose);
        await _mount(tester, controller, phone: phone, chinese: chinese);
        final label = find.byKey(const ValueKey('block-elapsed-timed'));
        expect(label, findsOneWidget);
        expect(
          tester.widget<Text>(label).data,
          contains(chinese ? '1分' : '1m '),
        );
        final block = find.byKey(const ValueKey('command-block-timed'));
        final height = tester.getSize(block).height;
        controller.refresh();
        await tester.pumpAndSettle();
        expect(tester.getSize(block).height, height);
        if (phone) {
          expect(
            tester
                .widget<TerminalViewport>(find.byType(TerminalViewport))
                .controller
                .frame
                .rows,
            hasLength(6),
          );
          await tester.tap(find.byKey(const ValueKey('block-expand-timed')));
          await tester.pumpAndSettle();
          expect(label, findsOneWidget);
          expect(
            tester.widget<Text>(label).data,
            contains(chinese ? '1分' : '1m '),
          );
          await tester.tap(find.byKey(const Key('block-reader-close')));
          await tester.pumpAndSettle();
        }
        output.running = false;
        output.finish = output.start! + 64250;
        controller.refresh();
        await tester.pumpAndSettle();
        final completed = chinese ? '1分4秒' : '1m 4s';
        expect(tester.widget<Text>(label).data, completed);
        await tester.pump(const Duration(seconds: 5));
        expect(tester.widget<Text>(label).data, completed);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('silent timer updates only metadata and resumes without input', (
    tester,
  ) async {
    final output = _TimedOutput();
    final controller = CommandBlockController(request: output.request)
      ..refresh();
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester, controller, phone: true);
      final label = find.byKey(const ValueKey('block-elapsed-timed'));
      final initial = tester.widget<Text>(label).data;
      final viewport = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      final frame = viewport.controller.frame;
      final rect = tester.getRect(
        find.byKey(const ValueKey('block-terminal-timed')),
      );
      final reads = output.requests;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<Text>(label).data, initial);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.widget<Text>(label).data, isNot(initial));
      final resumed = tester.widget<Text>(label).data;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(label).data, isNot(resumed));
      expect(viewport.controller.frame, same(frame));
      expect(
        tester.getRect(find.byKey(const ValueKey('block-terminal-timed'))),
        rect,
      );
      expect(output.requests, reads);
      final node = tester.getSemantics(label).getSemanticsData();
      expect(node.label, startsWith('Command elapsed '));
      expect(node.flagsCollection.isLiveRegion, false);
      expect(tester.testTextInput.hasAnyClients, false);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      semantics.dispose();
    }
  });

  testWidgets('missing timestamps do not invent elapsed, future starts clamp', (
    tester,
  ) async {
    final output = _TimedOutput()..start = null;
    final controller = CommandBlockController(request: output.request)
      ..refresh();
    addTearDown(controller.dispose);
    await _mount(tester, controller, phone: true);
    final label = find.byKey(const ValueKey('block-elapsed-timed'));
    expect(label, findsNothing);
    output.start = DateTime.now().millisecondsSinceEpoch + 60000;
    controller.refresh();
    await tester.pump();
    expect(tester.widget<Text>(label).data, '0s');
    output.running = false;
    controller.refresh();
    await tester.pump();
    expect(label, findsNothing);
    output.finish = output.start! + 2500;
    controller.refresh();
    await tester.pump();
    expect(tester.widget<Text>(label).data, '2.5s');
    output.finish = output.start! + 75;
    controller.refresh();
    await tester.pump();
    expect(tester.widget<Text>(label).data, '75ms');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
