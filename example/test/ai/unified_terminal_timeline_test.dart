import 'package:app/features/ai/unified_terminal_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  testWidgets('native history and late receipts share one ordered timeline', (
    tester,
  ) async {
    var ids = ['old'];
    final controller = CommandBlockController(
      request: (_) => {
        'blocks': [
          for (final id in ids) {'id': id, 'command': 'echo $id'},
        ],
      },
    );
    addTearDown(controller.dispose);
    controller.refresh();
    List<CommandBlockTimelineItem> rendered = [];
    Future<void> show(
      List<CommandBlockTimelineItem> items, {
      String task = 'one',
    }) => tester.pumpWidget(
      MaterialApp(
        home: UnifiedTerminalTimeline(
          controller: controller,
          taskId: task,
          sourceSessionId: 'session',
          items: items,
          builder: (items) {
            rendered = items;
            return Text(items.map((item) => item.id).join(','));
          },
        ),
      ),
    );
    const reply = CommandBlockTimelineItem.content('reply', null);
    await show([reply]);
    expect(rendered.map((item) => item.id), ['native-session-old', 'reply']);
    ids = ['old', 'new'];
    controller.refresh();
    await tester.pump();
    expect(rendered.map((item) => item.id), [
      'native-session-old',
      'reply',
      'native-session-new',
    ]);
    await show([
      reply,
      const CommandBlockTimelineItem.block(
        'new',
        id: 'accepted',
        sourceSessionId: 'session',
      ),
    ]);
    expect(rendered.map((item) => item.id), [
      'native-session-old',
      'reply',
      'accepted',
    ]);
    expect(rendered.where((item) => item.blockId == 'new'), hasLength(1));
    await show([
      const CommandBlockTimelineItem.content('empty', null),
    ], task: 'two');
    expect(rendered.map((item) => item.id), [
      'native-session-old',
      'native-session-new',
    ]);
  });

  testWidgets(
    'first live block stays after prose when initial history is empty',
    (tester) async {
      var ids = <String>[];
      final controller = CommandBlockController(
        request: (_) => {
          'blocks': [
            for (final id in ids) {'id': id, 'command': 'echo live'},
          ],
        },
      );
      addTearDown(controller.dispose);
      controller.refresh();
      late List<CommandBlockTimelineItem> rendered;
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedTerminalTimeline(
            controller: controller,
            taskId: 'task',
            sourceSessionId: 'session',
            items: const [CommandBlockTimelineItem.content('prose', null)],
            builder: (items) {
              rendered = items;
              return const SizedBox();
            },
          ),
        ),
      );
      ids = ['live'];
      controller.refresh();
      await tester.pump();
      expect(rendered.map((item) => item.id), ['prose', 'native-session-live']);
    },
  );

  testWidgets('same block ID in another source cannot hide current history', (
    tester,
  ) async {
    final controller = CommandBlockController(
      request: (_) => {
        'blocks': [
          {'id': '1', 'command': 'pwd'},
        ],
      },
    );
    addTearDown(controller.dispose);
    controller.refresh();
    late List<CommandBlockTimelineItem> rendered;
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedTerminalTimeline(
          controller: controller,
          taskId: 'one',
          sourceSessionId: 'current',
          items: const [
            CommandBlockTimelineItem.block('1', sourceSessionId: 'old'),
          ],
          builder: (items) {
            rendered = items;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(rendered, hasLength(2));
    expect(rendered.first.sourceSessionId, 'current');
    expect(rendered.last.sourceSessionId, 'old');
  });

  testWidgets('reconnected global IDs retain both sources without duplicates', (
    tester,
  ) async {
    final controller = CommandBlockController(
      request: (_) => {
        'blocks': [
          {'id': 'old/1', 'command': 'pwd'},
          {'id': 'new/1', 'command': 'ls'},
        ],
      },
    );
    addTearDown(controller.dispose);
    controller.refresh();
    late List<CommandBlockTimelineItem> rendered;
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedTerminalTimeline(
          controller: controller,
          taskId: 'one',
          sourceSessionId: 'new',
          globalBlockIds: true,
          items: const [
            CommandBlockTimelineItem.block('old/1', sourceSessionId: 'old'),
          ],
          builder: (items) {
            rendered = items;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(rendered.map((item) => item.blockId), ['new/1', 'old/1']);
  });
}
