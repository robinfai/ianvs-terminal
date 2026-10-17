import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openAiMobileTaskMenu(WidgetTester tester) async {
  final menu = find.byKey(const Key('ai-mobile-task-menu'));
  expect(menu.hitTestable(), findsOneWidget);
  await tester.tap(menu);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> observeAiTerminal(
  WidgetTester tester, {
  bool compactMobile = true,
}) async {
  if (compactMobile) await openAiMobileTaskMenu(tester);
  final action = find.byKey(
    Key(compactMobile ? 'ai-observe-terminal' : 'ai-close'),
  );
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action);
}
