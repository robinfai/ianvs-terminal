import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _pumpHost(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  Brightness brightness = Brightness.light,
  Size size = const Size(1000, 700),
  double textScale = 1,
  bool accessibleNavigation = false,
  FocusNode? inputFocus,
  VoidCallback? onTapBackground,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  late BuildContext noticeContext;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(brightness, platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          accessibleNavigation: accessibleNavigation,
        ),
        child: AppNotificationHost(topInset: 82, child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            noticeContext = context;
            return Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onTapBackground,
                    child: const Text('Background'),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: TextField(
                    key: const Key('command-line'),
                    focusNode: inputFocus,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  return noticeContext;
}

AppNotificationController _show(
  BuildContext context,
  String text, {
  Duration duration = const Duration(seconds: 3),
  VoidCallback? action,
}) => AppNotifications.show(
  context,
  SnackBar(
    content: Text(text),
    duration: duration,
    action: action == null
        ? null
        : SnackBarAction(label: 'Save', onPressed: action),
  ),
);

void main() {
  testWidgets('desktop notices stay above readline without taking focus', (
    tester,
  ) async {
    final inputFocus = FocusNode();
    addTearDown(inputFocus.dispose);
    var backgroundTaps = 0;
    final context = await _pumpHost(
      tester,
      inputFocus: inputFocus,
      onTapBackground: () => backgroundTaps++,
    );
    inputFocus.requestFocus();
    await tester.pump();
    final inputRect = tester.getRect(find.byKey(const Key('command-line')));
    _show(context, 'Copied');
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(inputFocus.hasFocus, isTrue);
    final noticeRect = tester.getRect(find.byType(AppPanel));
    expect(noticeRect.left, greaterThan(600));
    expect(noticeRect.top, greaterThanOrEqualTo(82));
    expect(noticeRect.top, lessThan(110));
    expect(noticeRect.bottom, lessThan(inputRect.top));
    expect(tester.getRect(find.byKey(const Key('command-line'))), inputRect);
    await tester.enterText(find.byType(TextField), 'git status');
    await tester.tap(find.text('Background'));
    expect(backgroundTaps, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('newest first, at most three, each expires independently', (
    tester,
  ) async {
    final context = await _pumpHost(tester);
    final oldest = _show(context, 'First');
    await tester.pump(const Duration(seconds: 1));
    _show(context, 'Second');
    _show(context, 'Third');
    _show(context, 'Fourth');
    await tester.pumpAndSettle();
    expect(await oldest.closed, SnackBarClosedReason.remove);
    expect(find.text('First'), findsNothing);
    expect(find.byType(AppPanel), findsNWidgets(3));
    expect(
      tester.getTopLeft(find.text('Fourth')).dy,
      lessThan(tester.getTopLeft(find.text('Third')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Third')).dy,
      lessThan(tester.getTopLeft(find.text('Second')).dy),
    );
    await tester.pump(const Duration(seconds: 2));
    _show(context, 'Newest');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Second'), findsNothing);
    expect(find.text('Newest'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(AppPanel), findsNothing);
  });

  testWidgets('repeated messages coalesce and get a fresh timeout', (
    tester,
  ) async {
    final context = await _pumpHost(tester);
    _show(context, 'Copied', duration: const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    _show(context, 'Copied', duration: const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('hover pauses timeout and close reports dismissal', (
    tester,
  ) async {
    final context = await _pumpHost(tester);
    final controller = _show(context, 'Copied');
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Copied')));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Copied'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(await controller.closed, SnackBarClosedReason.dismiss);
    await mouse.removePointer();
  });

  testWidgets('actionable notices survive bursts and preserve close results', (
    tester,
  ) async {
    final context = await _pumpHost(tester);
    var saves = 0;
    final download = _show(context, 'File received', action: () => saves++);
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      _show(context, 'Status $i');
    }
    await tester.pumpAndSettle();
    expect(find.text('File received'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('File received'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(await download.closed, SnackBarClosedReason.action);
    expect(find.text('File received'), findsNothing);
  });

  testWidgets('keyboard focus pauses expiry without intercepting typing', (
    tester,
  ) async {
    final context = await _pumpHost(tester);
    var saves = 0;
    final controller = _show(context, 'File received', action: () => saves++);
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Save'),
    );
    expect(button.autofocus, isFalse);
    final buttonContext = tester.element(find.text('Save'));
    Focus.of(buttonContext).requestFocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('File received'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(await controller.closed, SnackBarClosedReason.action);
  });

  testWidgets('screen reader notices wait for dismissal; disposal cleans up', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final context = await _pumpHost(tester, accessibleNavigation: true);
    final controller = _show(context, 'Copied');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Copied'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(await controller.closed, SnackBarClosedReason.remove);
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('small $brightness window supports large text and scrolling', (
      tester,
    ) async {
      final context = await _pumpHost(
        tester,
        size: const Size(320, 320),
        brightness: brightness,
        textScale: 2,
      );
      _show(context, 'Could not copy this selection. Please try again.');
      _show(context, 'A file was saved to a folder with a very long name.');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(viewport.right, lessThanOrEqualTo(320));
      expect(viewport.left, greaterThanOrEqualTo(0));
      expect(viewport.bottom, lessThanOrEqualTo(160));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('iOS keeps the native mobile snack bar placement', (
    tester,
  ) async {
    final context = await _pumpHost(tester, platform: TargetPlatform.iOS);
    final controller = _show(context, 'Copied');
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(AppPanel), findsNothing);
    expect(tester.getTopLeft(find.text('Copied')).dy, greaterThan(600));
    controller.close();
    await tester.pumpAndSettle();
  });
}
