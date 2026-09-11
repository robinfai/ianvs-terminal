import 'package:app/ui/components/app_compact_radio_tile.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('choice rows preserve whole-row and keyboard selection', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => RadioGroup<int>(
              groupValue: selected,
              onChanged: (value) => update(() => selected = value!),
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++)
                    AppCompactRadioTile<int>(
                      tileKey: Key('choice-$i'),
                      grouped: true,
                      value: i,
                      title: Text('Option $i'),
                      subtitle: Text('Description $i'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Description 1'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(selected, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(selected, 0);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('choice-0'))),
      matchesSemantics(
        label: 'Option 0\nDescription 0',
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        isFocusable: true,
        isFocused: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });
}
