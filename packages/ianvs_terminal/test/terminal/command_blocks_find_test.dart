import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class _SearchOutput {
  final queriedIds = <String>[];
  final text = const {
    'first': 'needle from the first task',
    'second': 'needle from the second task',
  };

  Map<String, Object?> _block(String id, {String query = ''}) {
    final matches = text[id]!.contains(query);
    return {
      'id': id,
      'command': 'echo $id',
      'cwd': '/tmp',
      'running': false,
      'exitCode': 0,
      'columns': 80,
      'offset': 0,
      'totalLines': 1,
      'matchingLines': matches ? 1 : 0,
      'nextOffset': null,
      'lines': [
        if (matches)
          {'index': 0, 'source_row': 100, 'text': text[id], 'wrapped': false},
      ],
    };
  }

  Map<String, Object?> request(Map<String, Object?> request) {
    final id = request['id'] as String?;
    if (id == null) {
      return {
        'blocks': [for (final id in text.keys) _block(id)],
      };
    }
    final query = request['query'] as String? ?? '';
    if (query.isNotEmpty) queriedIds.add(id);
    return {'block': _block(id, query: query)};
  }
}

Future<void> _pumpBlocks(
  WidgetTester tester,
  CommandBlockController controller, {
  List<CommandBlockTimelineItem>? timeline,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(platform: TargetPlatform.macOS),
    home: Scaffold(
      body: TerminalCommandBlocksView(
        controller: controller,
        timeline: timeline,
        showToolbar: false,
        onReinput: (_) => fail('Finding output must not re-input commands'),
      ),
    ),
  ),
);

Future<void> _findNeedle(
  WidgetTester tester,
  CommandBlockController controller, {
  String? activeId,
}) async {
  await tester.tap(find.text('echo first'));
  if (activeId == null) {
    controller.clearSelection();
  } else {
    controller.select(activeId);
  }
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
  await tester.enterText(find.byType(TextField), 'needle');
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  group('$TerminalCommandBlocksView find', () {
    late _SearchOutput output;
    late CommandBlockController controller;

    setUp(() {
      output = _SearchOutput();
      controller = CommandBlockController(request: output.request)..refresh();
    });

    tearDown(() => controller.dispose());

    for (final scoped in [true, false]) {
      testWidgets(
        scoped
            ? 'finds and opens only blocks in the current task timeline'
            : 'finds and opens all session blocks when timeline is null',
        (tester) async {
          await _pumpBlocks(
            tester,
            controller,
            timeline: scoped
                ? const [CommandBlockTimelineItem.block('first')]
                : null,
          );
          await tester.pumpAndSettle();
          await _findNeedle(tester, controller);

          expect(output.queriedIds, scoped ? ['first'] : ['second', 'first']);
          expect(find.text(output.text['first']!), findsOneWidget);
          expect(
            find.text(output.text['second']!),
            scoped ? findsNothing : findsOneWidget,
          );
          final target = scoped ? 'first' : 'second';
          await tester.tap(find.text(output.text[target]!));
          await tester.pumpAndSettle();
          expect(controller.activeId, target);
          expect(
            find.byKey(ValueKey('command-block-$target')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('ignores an active block outside the current task timeline', (
      tester,
    ) async {
      await _pumpBlocks(
        tester,
        controller,
        timeline: const [CommandBlockTimelineItem.block('first')],
      );
      await tester.pumpAndSettle();
      await _findNeedle(tester, controller, activeId: 'second');

      expect(output.queriedIds, ['first']);
      expect(find.text(output.text['first']!), findsOneWidget);
      expect(find.text(output.text['second']!), findsNothing);
      expect(find.text('This block'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('replaces find results when the task timeline changes', (
      tester,
    ) async {
      await _pumpBlocks(
        tester,
        controller,
        timeline: const [CommandBlockTimelineItem.block('first')],
      );
      await tester.pumpAndSettle();
      await _findNeedle(tester, controller);
      expect(find.text(output.text['first']!), findsOneWidget);
      output.queriedIds.clear();

      await _pumpBlocks(
        tester,
        controller,
        timeline: const [CommandBlockTimelineItem.block('second')],
      );
      expect(find.text(output.text['first']!), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(output.queriedIds, ['second']);
      expect(find.text(output.text['first']!), findsNothing);
      expect(find.text(output.text['second']!), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
