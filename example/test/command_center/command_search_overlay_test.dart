import 'package:app/features/command_center/command_search_index.dart';
import 'package:app/features/command_center/command_search_overlay.dart';
import 'package:app/features/command_center/command_search_overlay_controller.dart';
import 'package:app/features/command_center/global_command_history_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandSearchOverlay', () {
    final baseTime = DateTime.utc(2026, 6, 15, 10);

    testWidgets('renders command result metadata', (tester) async {
      await tester.pumpWidget(_app(_overlay(baseTime)));

      expect(find.byKey(const Key('command-search-overlay')), findsOneWidget);
      expect(find.text('flutter test'), findsOneWidget);
      expect(find.text('/repo'), findsWidgets);
      expect(find.text('Succeeded'), findsOneWidget);
      expect(find.text('Last run 2026-06-15 10:00'), findsOneWidget);
    });

    testWidgets('host opens overlay from Ctrl-R and consumes shortcut', (
      tester,
    ) async {
      var leakedSearchShortcutEvents = 0;
      await tester.pumpWidget(
        _app(
          Focus(
            onKeyEvent: (_, event) {
              if (event.logicalKey == LogicalKeyboardKey.keyR) {
                leakedSearchShortcutEvents += 1;
              }
              return KeyEventResult.ignored;
            },
            child: CommandSearchOverlayHost(
              controller: _controller(baseTime),
              child: const SizedBox(key: Key('terminal-surface')),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('command-search-overlay')), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(find.byKey(const Key('command-search-overlay')), findsOneWidget);
      expect(leakedSearchShortcutEvents, 0);
    });

    testWidgets('updates results from IME text input', (tester) async {
      final controller = _controller(baseTime);
      await tester.pumpWidget(_app(_overlay(baseTime, controller: controller)));

      await tester.enterText(
        find.byKey(const Key('command-search-overlay-field')),
        '构建',
      );
      await tester.pump();

      expect(controller.state.query, '构建');
      expect(find.text('构建项目'), findsOneWidget);
      expect(find.text('flutter test'), findsNothing);
    });

    testWidgets('search field receives focus when the overlay opens', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_overlay(baseTime)));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const Key('command-search-overlay-field')),
      );
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets('arrow keys move selected result and are consumed', (
      tester,
    ) async {
      var parentKeyEvents = 0;
      await tester.pumpWidget(
        _app(
          Focus(
            onKeyEvent: (_, _) {
              parentKeyEvents += 1;
              return KeyEventResult.ignored;
            },
            child: _overlay(baseTime),
          ),
        ),
      );

      expect(
        find.byKey(const Key('command-search-result-0-selected')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(
        find.byKey(const Key('command-search-result-1-selected')),
        findsOneWidget,
      );
      expect(parentKeyEvents, 0);
    });

    testWidgets('enter emits insert and modified enter emits execute', (
      tester,
    ) async {
      final inserted = <String>[];
      final executed = <String>[];
      await tester.pumpWidget(
        _app(
          _overlay(
            baseTime,
            onInsert: inserted.add,
            onExplicitExecute: executed.add,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      expect(inserted, ['flutter test']);
      expect(executed, ['flutter test']);
    });

    testWidgets('search field submit accepts the selected result', (
      tester,
    ) async {
      final inserted = <String>[];
      await tester.pumpWidget(_app(_overlay(baseTime, onInsert: inserted.add)));

      await tester.enterText(
        find.byKey(const Key('command-search-overlay-field')),
        '构建',
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(inserted, ['构建项目']);
    });

    testWidgets('clicking a result accepts it immediately', (tester) async {
      final inserted = <String>[];
      await tester.pumpWidget(_app(_overlay(baseTime, onInsert: inserted.add)));

      await tester.tap(
        find.byKey(const Key('command-search-result-0-selected')),
      );
      await tester.pump();

      expect(inserted, ['flutter test']);
    });

    testWidgets('view block output dispatches through onViewBlock', (
      tester,
    ) async {
      final viewedInvocationIds = <String>[];
      final controller = _controller(baseTime)
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch);

      await tester.pumpWidget(
        _app(
          _overlay(
            baseTime,
            controller: controller,
            onViewBlock: viewedInvocationIds.add,
          ),
        ),
      );

      final output = controller.viewSelectedBlock();
      final state = tester.state(find.byType(CommandSearchOverlay)) as dynamic;
      state.debugDispatchOutput(output);

      expect(viewedInvocationIds, ['inv-1']);
    });

    testWidgets('escape closes overlay and consumes the key', (tester) async {
      var closed = false;
      var parentKeyEvents = 0;
      await tester.pumpWidget(
        _app(
          Focus(
            onKeyEvent: (_, _) {
              parentKeyEvents += 1;
              return KeyEventResult.ignored;
            },
            child: _overlay(baseTime, onClose: () => closed = true),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(closed, isTrue);
      expect(find.byKey(const Key('command-search-overlay')), findsNothing);
      expect(parentKeyEvents, 0);
    });

    testWidgets('shows empty, loading, and unavailable states', (tester) async {
      final controller = CommandSearchOverlayController(
        index: CommandSearchIndex(const []),
      );

      await tester.pumpWidget(_app(_overlay(baseTime, controller: controller)));
      expect(find.text('No command history matches'), findsOneWidget);

      await tester.pumpWidget(
        _app(_overlay(baseTime, controller: controller, loading: true)),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.pumpWidget(
        _app(
          _overlay(
            baseTime,
            controller: controller,
            unavailableReason: 'Shell integration unavailable',
          ),
        ),
      );
      expect(find.text('Shell integration unavailable'), findsOneWidget);
    });
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: Center(child: child)),
  );
}

CommandSearchOverlay _overlay(
  DateTime baseTime, {
  CommandSearchOverlayController? controller,
  ValueChanged<String>? onInsert,
  ValueChanged<String>? onExplicitExecute,
  ValueChanged<String>? onViewBlock,
  VoidCallback? onClose,
  bool loading = false,
  String? unavailableReason,
}) {
  return CommandSearchOverlay(
    controller: controller ?? _controller(baseTime),
    onInsert: onInsert,
    onExplicitExecute: onExplicitExecute,
    onViewBlock: onViewBlock,
    onClose: onClose,
    loading: loading,
    unavailableReason: unavailableReason,
  );
}

CommandSearchOverlayController _controller(DateTime baseTime) {
  return CommandSearchOverlayController(
    index: CommandSearchIndex([
      GlobalCommandHistoryEntry(
        command: 'flutter test',
        cwd: '/repo',
        exitCode: 0,
        finishedAt: baseTime,
        invocationId: 'inv-1',
        sessionId: 'session-a',
      ),
      GlobalCommandHistoryEntry(
        command: 'npm test',
        cwd: '/repo',
        exitCode: 1,
        finishedAt: baseTime.subtract(const Duration(minutes: 2)),
        invocationId: 'inv-2',
        sessionId: 'session-a',
      ),
      GlobalCommandHistoryEntry(
        command: '构建项目',
        cwd: '/repo',
        exitCode: null,
        finishedAt: baseTime.subtract(const Duration(minutes: 4)),
        invocationId: 'inv-3',
        sessionId: 'session-a',
      ),
    ]),
    currentCwd: '/repo',
    currentSessionId: 'session-a',
  );
}
