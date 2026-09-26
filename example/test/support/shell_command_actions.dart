import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Follow the production gear -> command palette route to a shell action.
Future<void> openShellCommand(WidgetTester tester, String actionKey) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await tester.pumpAndSettle();
  final action = find.byKey(Key(actionKey));
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
}
