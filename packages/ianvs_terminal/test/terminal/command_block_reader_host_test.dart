import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  late CommandBlockController blocks;
  late CommandBlockReaderHostController host;
  late ValueNotifier<bool> active;
  late ValueNotifier<bool> tui;
  late TextEditingController neighbor;
  late FocusNode originFocus;
  final measured = <Size>[];
  final reads = <Map<String, Object?>>[];

  setUp(() {
    reads.clear();
    measured.clear();
    host = CommandBlockReaderHostController();
    active = ValueNotifier(true);
    tui = ValueNotifier(false);
    neighbor = TextEditingController();
    originFocus = FocusNode();
    blocks = CommandBlockController(
      request: (args) {
        reads.add(Map.of(args));
        final offset = args['offset'] as int? ?? 0;
        final limit = args['limit'] as int? ?? 6;
        final page = <String, Object?>{
          'id': 'log',
          'command': 'read original log',
          'cwd': '/original',
          'exitCode': 0,
          'totalLines': 600,
          'columns': 80,
          'offset': offset,
          'nextOffset': offset + limit < 600 ? offset + limit : null,
          'lines': [
            for (var i = offset; i < offset + limit && i < 600; i++)
              {
                'index': i,
                'source_row': 1000 + i,
                'text': 'original evidence $i',
              },
          ],
        };
        return args['id'] == null
            ? {
                'blocks': [page],
              }
            : {'block': page};
      },
    )..refresh();
  });

  tearDown(() {
    blocks.dispose();
    host.dispose();
    active.dispose();
    tui.dispose();
    neighbor.dispose();
    originFocus.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: active,
                  builder: (context, selected, _) => CommandBlockReaderHost(
                    controller: host,
                    sourceLabel: 'Original session',
                    active: selected,
                    geometryChanges: tui,
                    geometryIsFixed: () => tui.value,
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        if (measured.lastOrNull != bounds.biggest) {
                          measured.add(bounds.biggest);
                        }
                        return Column(
                          children: [
                            TextField(
                              key: const Key('origin-field'),
                              focusNode: originFocus,
                            ),
                            TextButton(
                              key: const Key('read-original'),
                              onPressed: () => showCommandBlockReader(
                                context,
                                controller: blocks,
                                id: 'log',
                                initialRow: 120,
                              ),
                              child: const Text('Read original evidence'),
                            ),
                            const Expanded(
                              child: ColoredBox(color: Colors.transparent),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 300,
                child: Column(
                  children: [
                    TextButton(
                      key: const Key('select-neighbor'),
                      onPressed: () => active.value = false,
                      child: const Text('Other pane'),
                    ),
                    TextField(key: const Key('neighbor'), controller: neighbor),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('read-original')));
    await tester.pumpAndSettle();
  }

  ScrollController scroll(WidgetTester tester) => tester
      .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
      .controller!;

  testWidgets(
    'reader stays local and preserves native reading across side and narrow layouts',
    (tester) async {
      await mount(tester);
      await open(tester);
      final reader = find.byKey(const Key('block-reader'));
      final state = tester.state(reader);
      final offset = scroll(tester).offset;
      expect(offset, greaterThan(0));
      expect(
        tester.getRect(find.byKey(const Key('pane-evidence-reader'))).right,
        1200,
      );
      expect(host.blocksInput, isTrue);
      expect(find.byKey(const Key('neighbor')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('pane-evidence-beside')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('pane-evidence-reader'))).width,
        360,
      );
      expect(measured.last.width, 840);
      expect(host.blocksInput, isFalse);
      expect(tester.state(reader), same(state));
      expect(scroll(tester).offset, closeTo(offset, 1));
      expect(find.text('Original session'), findsOneWidget);
      expect(find.byTooltip('Original session\nlog'), findsOneWidget);
      tester.view.physicalSize = const Size(1100, 700);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('pane-evidence-reader'))).width,
        800,
      );
      expect(host.blocksInput, isTrue);
      expect(tester.state(reader), same(state));
      expect(scroll(tester).offset, closeTo(offset, 1));
      expect(find.byKey(const Key('pane-evidence-beside')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(host.isOpen, isFalse);
      expect(find.byKey(const Key('pane-evidence-reader')), findsNothing);
      expect(blocks.readingStates['log'], isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('TUI inspector overlays without changing the native geometry', (
    tester,
  ) async {
    tui.value = true;
    await mount(tester);
    final originalSizes = List.of(measured);
    await open(tester);
    await tester.tap(find.byKey(const Key('pane-evidence-beside')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('pane-evidence-reader'))).width,
      360,
    );
    expect(measured, originalSizes);
    final terminals = tester.widgetList<CommandBlockTerminal>(
      find.byType(CommandBlockTerminal),
    );
    expect(terminals, isNotEmpty);
    expect(terminals.every((terminal) => terminal.liveInput == null), isTrue);
    await tester.tap(find.byKey(const Key('block-reader-close')));
    await tester.pumpAndSettle();
    expect(measured, originalSizes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pane Reader keeps find and Escape keyboard priority', (
    tester,
  ) async {
    await mount(tester);
    await open(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-reader-find-query')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-reader-find-query')), findsNothing);
    expect(host.isOpen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(host.isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inactive pane retains the source and rejects a captured close callback',
    (tester) async {
      await mount(tester);
      await open(tester);
      final close = tester
          .widget<BackButton>(find.byKey(const Key('block-reader-close')))
          .onPressed!;
      final state = tester.state(find.byKey(const Key('block-reader')));
      await tester.tap(find.byKey(const Key('select-neighbor')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('neighbor')),
        'Independent work',
      );
      close();
      await tester.pump();
      expect(host.isOpen, isTrue);
      expect(find.text('Original session'), findsOneWidget);
      expect(tester.state(find.byKey(const Key('block-reader'))), same(state));
      active.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-reader-close')));
      await tester.pumpAndSettle();
      expect(host.isOpen, isFalse);
      expect(neighbor.text, 'Independent work');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replaced reader rejects old actions before its element is unmounted',
    (tester) async {
      await mount(tester);
      await open(tester);
      final oldState = tester.state(find.byKey(const Key('block-reader')));
      final oldAction = tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const Key('block-reader-actions')),
          )
          .onSelected!;
      final replacement = showCommandBlockReader(
        tester.element(find.byKey(const Key('read-original'))),
        controller: blocks,
        id: 'log',
        sourceLabel: 'Replacement source',
      );
      await tester.idle();
      expect(oldState.mounted, isTrue);
      oldAction('filter');
      expect(blocks.filtering, isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('Replacement source'), findsOneWidget);
      await tester.tap(find.byKey(const Key('block-reader-close')));
      await tester.pumpAndSettle();
      expect(await replacement, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final newOwner in ['neighbor', 'dialog']) {
    testWidgets('closing reader cannot steal focus from $newOwner', (
      tester,
    ) async {
      await mount(tester);
      originFocus.requestFocus();
      await tester.pump();
      final reading = showCommandBlockReader(
        tester.element(find.byKey(const Key('read-original'))),
        controller: blocks,
        id: 'log',
      );
      await tester.pumpAndSettle();
      final close = tester
          .widget<BackButton>(find.byKey(const Key('block-reader-close')))
          .onPressed!;
      close();
      if (newOwner == 'neighbor') {
        final editable = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('neighbor')),
            matching: find.byType(EditableText),
          ),
        );
        editable.focusNode.requestFocus();
      } else {
        unawaited(
          showDialog<void>(
            context: tester.element(find.byKey(const Key('neighbor'))),
            builder: (_) => const AlertDialog(
              content: TextField(key: Key('new-modal-editor'), autofocus: true),
            ),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(await reading, isNull);
      expect(originFocus.hasFocus, isFalse);
      final owner = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(
            newOwner == 'neighbor'
                ? const Key('neighbor')
                : const Key('new-modal-editor'),
          ),
          matching: find.byType(EditableText),
        ),
      );
      expect(owner.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'opening delayed by keyboard dismissal cannot jump back from another pane',
    (tester) async {
      await mount(tester);
      final hide = Completer<Object?>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async => call.method == 'TextInput.hide' ? hide.future : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          null,
        ),
      );
      await tester.tap(find.byKey(const Key('read-original')));
      await tester.pump();
      active.value = false;
      await tester.pump();
      active.value = true;
      await tester.pump();
      hide.complete(null);
      await tester.pumpAndSettle();
      expect(host.isOpen, isFalse);
      expect(find.byKey(const Key('block-reader')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
