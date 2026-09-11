import 'package:app/ui/components/app_dropdown_form_field.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHarness(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(800, 600),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: TargetPlatform.macOS,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty disabled field shows its hint once and cannot open', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      const SizedBox(
        width: 280,
        child: AppDropdownFormField<String>(
          key: Key('disabled-field'),
          decoration: InputDecoration(hintText: 'Choose an option'),
          items: [DropdownMenuItem(value: 'one', child: Text('One'))],
          onChanged: null,
        ),
      ),
    );
    expect(find.text('Choose an option'), findsOneWidget);
    await tester.tap(find.byKey(const Key('disabled-field')));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('selects a nullable value and ignores a disabled option', (
    tester,
  ) async {
    String? selected = 'English';
    await pumpHarness(
      tester,
      SizedBox(
        width: 280,
        child: AppDropdownFormField<String?>(
          key: const Key('language'),
          initialValue: selected,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: null, child: Text('System default')),
            DropdownMenuItem(value: 'English', child: Text('English')),
            DropdownMenuItem(
              value: 'Unavailable',
              enabled: false,
              child: Text('Unavailable'),
            ),
          ],
          onChanged: (value) => selected = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    final disabled = tester.widget<MenuItemButton>(
      find.widgetWithText(MenuItemButton, 'Unavailable').last,
    );
    expect(disabled.onPressed, isNull);
    await tester.tap(find.text('System default').last);
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.text('System default'), findsOneWidget);
  });

  testWidgets('tracks a new initial value and Form.reset restores it', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    late StateSetter rebuild;
    var initialValue = 'One';
    String? changed;
    await pumpHarness(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return Form(
            key: formKey,
            child: SizedBox(
              width: 260,
              child: AppDropdownFormField<String>(
                key: const Key('reset-dropdown'),
                initialValue: initialValue,
                items: const [
                  DropdownMenuItem(value: 'One', child: Text('One')),
                  DropdownMenuItem(value: 'Two', child: Text('Two')),
                  DropdownMenuItem(value: 'Three', child: Text('Three')),
                ],
                onChanged: (value) => changed = value,
              ),
            ),
          );
        },
      ),
    );

    initialValue = 'Two';
    rebuild(() {});
    await tester.pump();
    expect(find.text('Two'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reset-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Three').last);
    await tester.pumpAndSettle();
    expect(changed, 'Three');

    formKey.currentState!.reset();
    await tester.pump();
    expect(find.text('Two'), findsOneWidget);
  });

  testWidgets('keyboard selection and cancellation return focus to the field', (
    tester,
  ) async {
    String? selected = 'One';
    await pumpHarness(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TextField(key: Key('before-dropdown')),
          SizedBox(
            width: 280,
            child: AppDropdownFormField<String>(
              key: const Key('keyboard-dropdown'),
              initialValue: selected,
              items: const [
                DropdownMenuItem(value: 'One', child: Text('One')),
                DropdownMenuItem(value: 'Two', child: Text('Two')),
                DropdownMenuItem(value: 'Three', child: Text('Three')),
              ],
              onChanged: (value) => selected = value,
            ),
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('before-dropdown')));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'Two');
    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(const Key('keyboard-dropdown')),
              matching: find.byType(InkWell),
            ),
          )
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    expect(find.byType(MenuItemButton), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selected, 'Two');
    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(const Key('keyboard-dropdown')),
              matching: find.byType(InkWell),
            ),
          )
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('menu matches its anchor and rows grow for large text', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      SizedBox(
        width: 320,
        child: AppDropdownFormField<String>(
          key: const Key('sized-dropdown'),
          initialValue: 'Long',
          isExpanded: true,
          selectedItemBuilder: (context) => const [
            Text('Short'),
            Text('A long selected value that must ellipsize without overflow'),
          ],
          items: const [
            DropdownMenuItem(value: 'Short', child: Text('Short')),
            DropdownMenuItem(
              key: Key('two-line-menu-item'),
              value: 'Long',
              child: Text('A menu item\nwith two readable lines'),
            ),
          ],
          onChanged: (_) {},
        ),
      ),
      textScale: 1.8,
    );

    final anchorWidth = tester
        .getSize(find.byKey(const Key('sized-dropdown')))
        .width;
    await tester.tap(find.byKey(const Key('sized-dropdown')));
    await tester.pumpAndSettle();
    final menuItem = find.byKey(const Key('two-line-menu-item')).last;
    expect(tester.getSize(menuItem).width, closeTo(anchorWidth - 8, 1));
    expect(tester.getSize(menuItem).height, greaterThan(32));
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu remains inside a small window', (tester) async {
    await pumpHarness(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 260,
          child: AppDropdownFormField<int>(
            key: const Key('bounded-dropdown'),
            initialValue: 0,
            menuMaxHeight: 180,
            items: [
              for (var index = 0; index < 12; index++)
                DropdownMenuItem(value: index, child: Text('Choice $index')),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
      size: const Size(320, 240),
    );

    await tester.tap(find.byKey(const Key('bounded-dropdown')));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.text('Choice 0').last);
    final lastVisible = tester.getRect(find.text('Choice 3').last);
    expect(first.left, greaterThanOrEqualTo(0));
    expect(first.top, greaterThanOrEqualTo(0));
    expect(lastVisible.right, lessThanOrEqualTo(320));
    expect(lastVisible.bottom, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });
}
