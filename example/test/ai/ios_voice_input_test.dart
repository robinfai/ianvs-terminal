import 'dart:async';

import 'package:app/features/ai/ios_voice_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('app/voice_input');
  late TextEditingController controller;
  late Completer<String?> result;
  late FocusNode focus;
  late List<String> calls;
  setUp(() {
    focus = FocusNode();
    controller = TextEditingController(text: 'echo old')
      ..selection = const TextSelection(baseOffset: 5, extentOffset: 8);
    result = Completer<String?>();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'start') return result.future;
          return null;
        });
  });
  tearDown(() {
    controller.dispose();
    focus.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> mount(WidgetTester tester, {bool enabled = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: IosVoiceInput(
                controller: controller,
                focusNode: focus,
                enabled: enabled,
                chinese: true,
                child: TextField(controller: controller, focusNode: focus),
              ),
            ),
          ),
        ),
      );
  testWidgets('tap edits without requesting speech permission', (tester) async {
    await mount(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(calls, isEmpty);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'focused text keeps native caret and selection gestures without voice',
    (tester) async {
      await mount(tester);
      focus.requestFocus();
      await tester.pumpAndSettle();
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.longPressAt(
        tester.getTopLeft(find.byType(TextField)) + const Offset(20, 24),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(controller.selection.extentOffset, greaterThan(0));
      final word =
          tester.getTopLeft(find.byType(TextField)) + const Offset(20, 24);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(word);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(word);
      await tester.pumpAndSettle();
      expect(controller.selection.isCollapsed, isFalse);
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'unfocused hold preserves selection; release inserts at selection',
    (tester) async {
      await mount(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(calls, ['start']);
      expect(find.text('松开转文字'), findsOneWidget);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 5, extentOffset: 8),
      );
      await gesture.up();
      await tester.pump();
      expect(calls, ['start', 'stop']);
      expect(
        controller.value,
        const TextEditingValue(
          text: 'echo old',
          selection: TextSelection(baseOffset: 5, extentOffset: 8),
        ),
      );
      await tester.runAsync(() async {
        result.complete('hello');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(controller.text, 'echo hello');
    },
  );
  testWidgets('unfocus restores voice gesture after text editing', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    focus.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    expect(focus.hasFocus, isFalse);
    await tester.longPress(find.byType(TextField));
    expect(calls, ['start', 'stop']);
    await tester.runAsync(() async {
      result.complete('hello');
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  });
  for (final slideBack in [false, true]) {
    testWidgets('slide up cancel, return to recording: $slideBack', (
      tester,
    ) async {
      await mount(tester);
      final origin = tester.getCenter(find.byType(TextField));
      final gesture = await tester.startGesture(origin);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('voice-cancel-zone'))),
      );
      await tester.pump();
      expect(find.text('松开取消'), findsOneWidget);
      final cancelBounds = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('voice-cancel-zone')),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final panelBounds = tester.getRect(
        find.byKey(const Key('voice-recording-panel')),
      );
      expect(cancelBounds.left, 0);
      expect(
        cancelBounds.right,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );
      expect(cancelBounds.top, 0);
      expect(cancelBounds.bottom, panelBounds.top);
      // The whole upper area cancels, including far from the label.
      for (final point in [
        cancelBounds.topLeft + const Offset(8, 8),
        cancelBounds.topRight + const Offset(-8, 8),
        cancelBounds.bottomLeft + const Offset(8, -8),
      ]) {
        await gesture.moveTo(point);
        await tester.pump();
        expect(find.text('松开取消'), findsOneWidget);
      }
      // Even an early native final result must wait for the user's release.
      await tester.runAsync(() async {
        result.complete('hello');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(controller.text, 'echo old');
      if (slideBack) {
        await gesture.moveTo(origin);
        await tester.pump();
        expect(find.text('松开转文字'), findsOneWidget);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, ['start', if (slideBack) 'stop' else 'cancel']);
      expect(controller.text, slideBack ? 'echo hello' : 'echo old');
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const Key('voice-recording-panel')), findsNothing);
    });
  }
  testWidgets('late recognition cannot overwrite a changed draft', (
    tester,
  ) async {
    await mount(tester);
    await tester.longPress(find.byType(TextField));
    controller.text = 'new draft';
    await tester.runAsync(() async {
      result.complete('stale speech');
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(controller.text, 'new draft');
  });
  testWidgets('losing ownership cancels and ignores late results', (
    tester,
  ) async {
    await mount(tester);
    await tester.longPress(find.byType(TextField));
    await mount(tester, enabled: false);
    await tester.pump();
    expect(calls, contains('cancel'));
    await tester.runAsync(() async {
      result.complete('stale speech');
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(controller.text, 'echo old');
  });
  testWidgets('permission denial preserves draft and shows recovery', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'start') {
            throw PlatformException(code: 'permission_denied');
          }
          return null;
        });
    await mount(tester);
    await tester.longPress(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(controller.text, 'echo old');
    expect(find.text('请在系统设置中允许麦克风和语音识别权限。'), findsOneWidget);
  });
}
