import 'package:app/component_preview.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/components/app_action_button.dart';
import 'package:app/ui/components/app_confirmation.dart';
import 'package:app/ui/components/app_dropdown_form_field.dart';
import 'package:app/ui/components/app_menu.dart';
import 'package:app/ui/components/app_text_form_field.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {
    TargetPlatform platform = TargetPlatform.macOS,
    Size size = const Size(800, 600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildIanvsTerminalTheme(Brightness.light, platform: platform),
      home: Scaffold(body: Center(child: child)),
    ));
  }

  testWidgets('loading action cannot submit twice and touch target is padded', (tester) async {
    var count = 0;
    await pump(tester, AppActionButton(label: 'Connect', loading: true,
      onPressed: () => count++), platform: TargetPlatform.iOS);
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(count, 0);
    expect(tester.getSize(find.byType(FilledButton)).height, greaterThanOrEqualTo(44));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('password reveal retains value and Form validation', (tester) async {
    final controller = TextEditingController(text: 'fictional');
    addTearDown(controller.dispose);
    final form = GlobalKey<FormState>();
    await pump(tester, SizedBox(width: 300, child: Form(key: form,
      child: AppTextFormField(controller: controller, password: true,
        revealLabel: 'Show password', concealLabel: 'Hide password',
        validator: (value) => value!.isEmpty ? 'Required' : null))));
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
    expect(controller.text, 'fictional');
    await tester.enterText(find.byType(TextFormField), '');
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('dropdown validates and reset restores initial selection', (tester) async {
    final form = GlobalKey<FormState>();
    await pump(tester, SizedBox(width: 260, child: Form(key: form,
      child: AppDropdownFormField<String>(
        decoration: const InputDecoration(labelText: 'Environment'),
        items: const [DropdownMenuItem(value: 'dev', child: Text('Development'))],
        onChanged: (_) {}, validator: (value) => value == null ? 'Choose one' : null,
      ))));
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Choose one'), findsOneWidget);
    await tester.tap(find.byType(AppDropdownFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Development').last);
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), isTrue);
    form.currentState!.reset();
    expect(form.currentState!.validate(), isFalse);
  });

  testWidgets('desktop submenu selection executes once and restores trigger focus', (tester) async {
    var count = 0;
    await pump(tester, AppMenuButton(tooltip: 'Actions', entries: [
      AppMenuEntry(label: 'Split', children: [
        AppMenuEntry(label: 'Horizontally', onSelected: () => count++),
        const AppMenuEntry(label: 'Unavailable', enabled: false),
      ]),
    ]));
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Horizontally'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(count, 1);
    expect(find.text('Horizontally'), findsNothing);
    expect(tester.widget<IconButton>(find.byType(IconButton)).focusNode!.hasFocus, isTrue);
  });

  testWidgets('Escape and outside tap cancel without executing', (tester) async {
    var count = 0;
    await pump(tester, AppMenuButton(tooltip: 'Actions', entries: [
      AppMenuEntry(label: 'Execute', onSelected: () => count++),
    ]));
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Execute'), findsNothing);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Execute'), findsNothing);
    expect(count, 0);
  });

  testWidgets('mobile drill-down supports back and disabled entries', (tester) async {
    var count = 0;
    await pump(tester, AppMenuButton(tooltip: 'Actions', entries: [
      AppMenuEntry(label: 'Split', children: [
        const AppMenuEntry(label: 'Unavailable', enabled: false),
        AppMenuEntry(label: 'Horizontally', onSelected: () => count++),
      ]),
    ]), platform: TargetPlatform.iOS, size: const Size(375, 667));
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(find.text('Horizontally'), findsOneWidget);
    await tester.tap(find.text('Unavailable'));
    await tester.pump();
    expect(count, 0);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Horizontally'), findsNothing);
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Horizontally'));
    await tester.pumpAndSettle();
    expect(count, 1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edge anchored submenu remains in viewport', (tester) async {
    await pump(tester, Align(alignment: Alignment.bottomRight,
      child: AppMenuButton(tooltip: 'Actions', entries: [
        AppMenuEntry(label: 'Split', children: [
          AppMenuEntry(label: 'Horizontally', onSelected: () {}),
          AppMenuEntry(label: 'Vertically', onSelected: () {}),
        ]),
      ])), size: const Size(640, 320));
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.text('Horizontally'));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(640));
    expect(rect.bottom, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('destructive confirmation defaults to cancel', (tester) async {
    bool? result;
    await pump(tester, Builder(builder: (context) => TextButton(
      onPressed: () async { result = await showAppConfirmation(context,
        title: 'Close session?', message: 'Demo only', confirmLabel: 'Close',
        cancelLabel: 'Keep', destructive: true); }, child: const Text('Open'))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('showcase fits phone and desktop and switches themes', (tester) async {
    for (final size in [const Size(375, 667), const Size(1280, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const ComponentPreview());
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Dark'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
