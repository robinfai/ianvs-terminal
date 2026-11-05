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
  if (compactMobile) await openAiMobileTaskMenu(tester);
  if (compactMobile &&
      find.byKey(const Key('ai-history-actions')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('ai-history-actions')));
    await tester.pumpAndSettle();
  }
  if (!compactMobile &&
      find.byKey(const Key('ai-header-more')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('ai-header-more')));
    await tester.pumpAndSettle();
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
