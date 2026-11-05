import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openAiMobileTaskMenu(WidgetTester tester) async {
  final menu = find.byKey(const Key('ai-mobile-task-menu'));
  expect(menu.hitTestable(), findsOneWidget);
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

Future<void> observeAiTerminal(
  WidgetTester tester, {
  bool compactMobile = true,
}) async {
  if (!compactMobile &&
      find.byKey(const Key('ai-mode-terminal')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('ai-mode-terminal')));
    return;
  }
  if (compactMobile) await openAiMobileTaskMenu(tester);
  if (compactMobile &&
      find.byKey(const Key('ai-history-actions')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('ai-history-actions')));
    await tester.pumpAndSettle();
  }
  if (!compactMobile &&
      find.byKey(const Key('ai-header-more')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('ai-header-more')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  final action = find.byKey(
    Key(compactMobile ? 'ai-observe-terminal' : 'ai-close'),
  );
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action);
}

Future<void> openAiDesktopMore(WidgetTester tester) async {
  final more = find.byKey(const Key('ai-header-more'));
  if (more.evaluate().isNotEmpty) {
    await tester.tap(more);
    await tester.pumpAndSettle();
  }
}

Future<void> returnToAiWorkspace(WidgetTester tester) async {
  final back = find.byKey(const Key('ai-observer-back'));
  if (back.evaluate().isNotEmpty) {
    await tester.tap(back);
  } else {
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextButton &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'terminal-ai-open-',
            ),
      ),
    );
  }
}
