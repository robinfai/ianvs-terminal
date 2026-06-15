import 'package:app/features/command_center/command_action_search_controller.dart';
import 'package:app/features/command_center/command_action_search_index.dart';
import 'package:app/features/command_center/command_action_search_overlay.dart';
import 'package:app/features/command_center/saved_command_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandActionSearchOverlay', () {
    final baseTime = DateTime.utc(2026, 6, 15, 10);

    testWidgets('renders action and saved command metadata', (tester) async {
      await tester.pumpWidget(_app(_overlay(baseTime)));

      expect(
        find.byKey(const Key('command-action-search-overlay')),
        findsOneWidget,
      );
      expect(find.text('Open history search'), findsOneWidget);
      expect(find.text('Action'), findsWidgets);
      expect(find.text('Build release'), findsOneWidget);
      expect(find.text('flutter build macos --release'), findsOneWidget);
      expect(find.text('Saved command'), findsOneWidget);
      expect(find.text('release'), findsOneWidget);
    });

    testWidgets('updates results from text input', (tester) async {
      final controller = _controller(baseTime);
      await tester.pumpWidget(_app(_overlay(baseTime, controller: controller)));

      await tester.enterText(
        find.byKey(const Key('command-action-search-overlay-field')),
        'read only',
      );
      await tester.pump();

      expect(controller.state.query, 'read only');
      expect(find.text('Toggle read only'), findsOneWidget);
      expect(find.text('Build release'), findsNothing);
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
        find.byKey(const Key('command-action-search-result-0-selected')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(
        find.byKey(const Key('command-action-search-result-1-selected')),
        findsOneWidget,
      );
      expect(parentKeyEvents, 0);
    });

    testWidgets('enter emits action and saved command outputs', (tester) async {
      final openedActions = <String>[];
      final insertedCommands = <String>[];
      final insertedItems = <CommandActionSearchItem>[];
      final controller = _controller(baseTime);
      await tester.pumpWidget(
        _app(
          _overlay(
            baseTime,
            controller: controller,
            onOpenAction: openedActions.add,
            onInsertSavedCommand: insertedCommands.add,
            onInsertSavedCommandItem: insertedItems.add,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('command-action-search-overlay-field')),
        'release',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(openedActions, ['open-history']);
      expect(insertedCommands, ['flutter build macos --release']);
      expect(insertedItems.single.id, 'release-build');
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
      expect(
        find.byKey(const Key('command-action-search-overlay')),
        findsNothing,
      );
      expect(parentKeyEvents, 0);
    });

    testWidgets('shows empty, loading, and unavailable states', (tester) async {
      final controller = CommandActionSearchController(
        index: CommandActionSearchIndex(),
      );

      await tester.pumpWidget(_app(_overlay(baseTime, controller: controller)));
      expect(find.text('No actions or saved commands match'), findsOneWidget);

      await tester.pumpWidget(
        _app(_overlay(baseTime, controller: controller, loading: true)),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.pumpWidget(
        _app(
          _overlay(
            baseTime,
            controller: controller,
            unavailableReason: 'Saved commands unavailable',
          ),
        ),
      );
      expect(find.text('Saved commands unavailable'), findsOneWidget);
    });
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: Center(child: child)),
  );
}

CommandActionSearchOverlay _overlay(
  DateTime baseTime, {
  CommandActionSearchController? controller,
  ValueChanged<String>? onOpenAction,
  ValueChanged<String>? onInsertSavedCommand,
  ValueChanged<CommandActionSearchItem>? onInsertSavedCommandItem,
  VoidCallback? onClose,
  bool loading = false,
  String? unavailableReason,
}) {
  return CommandActionSearchOverlay(
    controller: controller ?? _controller(baseTime),
    onOpenAction: onOpenAction,
    onInsertSavedCommand: onInsertSavedCommand,
    onInsertSavedCommandItem: onInsertSavedCommandItem,
    onClose: onClose,
    loading: loading,
    unavailableReason: unavailableReason,
  );
}

CommandActionSearchController _controller(DateTime baseTime) {
  return CommandActionSearchController(
    index: CommandActionSearchIndex(
      actions: const [
        CommandActionSearchItem.appAction(
          id: 'open-history',
          title: 'Open history search',
          subtitle: 'Search previous commands',
          keywords: ['search commands'],
        ),
        CommandActionSearchItem.appAction(
          id: 'toggle-read-only',
          title: 'Toggle read only',
          subtitle: 'Protect terminal input',
          keywords: ['read only'],
        ),
      ],
      savedCommands: [
        SavedCommandEntry(
          id: 'release-build',
          title: 'Build release',
          command: 'flutter build macos --release',
          tags: const ['release'],
          createdAt: baseTime.subtract(const Duration(days: 1)),
          updatedAt: baseTime,
        ),
      ],
    ),
  );
}
