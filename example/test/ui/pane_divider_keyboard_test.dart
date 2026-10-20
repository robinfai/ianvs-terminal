import 'dart:math' as math;
import 'dart:ui' show SemanticsAction;

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shell/shell_screen_phase1b_test.dart' show pumpShellScreen;
import '../support/fake_pty_backend.dart';
import '../support/memory_profile_repository.dart';

class _DividerFixture {
  final before = FocusNode();
  final divider = FocusNode();
  final after = FocusNode();
  final deltas = <double>[];
  final unhandled = <LogicalKeyboardKey>[];
}

Future<_DividerFixture> _mount(
  WidgetTester tester,
  Axis direction, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  bool highContrast = false,
}) async {
  final fixture = _DividerFixture();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.before.dispose();
    fixture.divider.dispose();
    fixture.after.dispose();
  });
  final divider = ShellDividerComponentPreview(
    direction: direction,
    focusNode: fixture.divider,
    onDragUpdate: fixture.deltas.add,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildIanvsTerminalTheme(
        brightness,
        platform: TargetPlatform.macOS,
        highContrast: highContrast,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(highContrast: highContrast),
        child: child!,
      ),
      home: Scaffold(
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) {
              fixture.unhandled.add(event.logicalKey);
            }
            return KeyEventResult.ignored;
          },
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: Column(
              children: [
                Focus(
                  focusNode: fixture.before,
                  autofocus: true,
                  child: const SizedBox(height: 30, child: Text('Before')),
                ),
                SizedBox(
                  width: 300,
                  height: 180,
                  child: direction == Axis.horizontal
                      ? Row(children: [divider])
                      : Column(children: [divider]),
                ),
                Focus(
                  focusNode: fixture.after,
                  child: const SizedBox(height: 30, child: Text('After')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Finder _line(Axis direction) =>
    find.byKey(Key('shell-pane-divider-line-${direction.name}'));

Finder _semantics(Axis direction) =>
    find.byKey(Key('shell-pane-divider-semantics-${direction.name}'));

void main() {
  for (final direction in Axis.values) {
    final positive = direction == Axis.horizontal
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowDown;
    final negative = direction == Axis.horizontal
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowUp;
    final otherAxis = direction == Axis.horizontal
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;

    testWidgets('${direction.name} divider is in Tab order and only handles '
        'unmodified focused axis keys', (tester) async {
      final fixture = await _mount(tester, direction);
      expect(fixture.before.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(positive);
      expect(fixture.deltas, isEmpty);

      fixture.before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(fixture.divider.hasPrimaryFocus, isTrue);
      fixture.unhandled.clear();
      await tester.sendKeyDownEvent(positive);
      await tester.sendKeyRepeatEvent(positive);
      await tester.sendKeyUpEvent(positive);
      await tester.sendKeyEvent(negative);
      await tester.pumpAndSettle();
      expect(fixture.deltas, [10, 10, -10]);
      expect(fixture.unhandled, isEmpty);

      await tester.sendKeyEvent(otherAxis);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      for (final modifier in [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        fixture.divider.requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(positive);
        await tester.sendKeyUpEvent(modifier);
      }
      expect(fixture.deltas, [10, 10, -10]);
      expect(
        fixture.unhandled,
        containsAll([otherAxis, LogicalKeyboardKey.keyA]),
      );
      expect(fixture.unhandled.where((key) => key == positive), hasLength(4));

      // An ignored cross-axis key may invoke the enclosing app's directional
      // traversal. Start this independent Tab-exit assertion on the divider.
      fixture.divider.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(fixture.after.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(positive);
      expect(fixture.deltas, [10, 10, -10]);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    for (final language in ['en', 'zh']) {
      testWidgets('${direction.name} $language divider exposes adjustable '
          'semantics without moving keyboard focus', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final fixture = await _mount(
            tester,
            direction,
            locale: Locale(language),
          );
          final node = tester.getSemantics(_semantics(direction));
          final horizontal = direction == Axis.horizontal;
          final hint = language == 'zh'
              ? (horizontal ? '使用左右方向键调整宽度。' : '使用上下方向键调整高度。')
              : (horizontal
                    ? 'Use the left and right arrow keys to adjust width.'
                    : 'Use the up and down arrow keys to adjust height.');
          expect(
            node,
            matchesSemantics(
              label: language == 'zh' ? '调整窗格大小' : 'Resize pane',
              hint: hint,
              isFocusable: true,
              isSlider: true,
              hasIncreaseAction: true,
              hasDecreaseAction: true,
            ),
          );
          final owner =
              tester.binding.renderViews.single.owner!.semanticsOwner!;
          owner.performAction(node.id, SemanticsAction.increase);
          owner.performAction(node.id, SemanticsAction.decrease);
          await tester.pumpAndSettle();
          expect(fixture.deltas, [10, -10]);
          expect(fixture.before.hasPrimaryFocus, isTrue);
        } finally {
          semantics.dispose();
        }
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }

    testWidgets(
      '${direction.name} pointer resizing keeps keyboard owner',
      (tester) async {
        final fixture = await _mount(tester, direction);
        await tester.drag(
          find.byType(ShellDividerComponentPreview),
          direction == Axis.horizontal
              ? const Offset(60, 0)
              : const Offset(0, 60),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(fixture.deltas, isNotEmpty);
        expect(fixture.deltas.reduce((a, b) => a + b), greaterThan(0));
        expect(fixture.before.hasPrimaryFocus, isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      testWidgets('divider paints a distinct focus ring while hovered: '
          '${brightness.name}, contrast=$highContrast', (tester) async {
        final fixture = await _mount(
          tester,
          Axis.horizontal,
          brightness: brightness,
          highContrast: highContrast,
        );
        final preview = find.byType(ShellDividerComponentPreview);
        final palette = Theme.of(
          tester.element(preview),
        ).extension<AppThemeTokens>()!;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(preview));
        await tester.pumpAndSettle();
        Color lineColor() =>
            (tester
                        .widget<AnimatedContainer>(_line(Axis.horizontal))
                        .decoration!
                    as BoxDecoration)
                .color!;
        final hoverColor = lineColor();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(fixture.divider.hasPrimaryFocus, isTrue);
        expect(lineColor(), palette.focusRing);
        expect(lineColor(), isNot(hoverColor));
        expect(tester.getSize(_line(Axis.horizontal)).width, 2);
        final surface = Color.alphaBlend(
          palette.accent.withValues(alpha: .09),
          palette.panel,
        );
        final a = lineColor().computeLuminance();
        final b = surface.computeLuminance();
        expect(
          (math.max(a, b) + .05) / (math.min(a, b) + .05),
          greaterThanOrEqualTo(3),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(lineColor(), hoverColor);
        expect(fixture.deltas, isEmpty);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }

  testWidgets(
    'divider responds to reduced motion changes at runtime',
    (tester) async {
      final fixture = await _mount(tester, Axis.vertical);
      final animations = find.descendant(
        of: find.byType(ShellDividerComponentPreview),
        matching: find.byType(AnimatedContainer),
      );
      expect(animations, findsNWidgets(2));
      expect(
        tester
            .widgetList<AnimatedContainer>(animations)
            .map((widget) => widget.duration),
        everyElement(const Duration(milliseconds: 90)),
      );
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<AnimatedContainer>(animations)
            .map((widget) => widget.duration),
        everyElement(Duration.zero),
      );
      expect(fixture.before.hasPrimaryFocus, isTrue);
      expect(fixture.deltas, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('real 2 by 2 outer divider resizes its own split with keyboard '
      'and keeps pane, focus, PTY writes and size constraints', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakePtyBackend();
      await pumpShellScreen(
        tester,
        fakeBindings: backend,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final original = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.horizontal,
      );
      await tester.pumpAndSettle();
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.vertical,
      );
      await tester.pumpAndSettle();
      controller.activateSession(original);
      await tester.pumpAndSettle();
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.vertical,
      );
      await tester.pumpAndSettle();

      TerminalPaneLayoutNode layout() => container
          .read(sessionControllerProvider)
          .tabs
          .single
          .effectivePaneLayout;
      final initial = layout();
      expect(initial.panes, hasLength(4));
      expect(initial.splitAxis, TerminalSplitAxis.horizontal);
      expect(initial.first!.splitAxis, TerminalSplitAxis.vertical);
      expect(initial.second!.splitAxis, TerminalSplitAxis.vertical);
      final active = container.read(sessionControllerProvider).activeSessionId;
      final writes = backend.writes.length;
      final owner = Focus.of(tester.element(_semantics(Axis.horizontal)));
      String spokenRatio() =>
          'Left panes: ${(layout().ratio * 100).toStringAsFixed(1)}%';
      final initialSemantics = tester
          .getSemantics(_semantics(Axis.horizontal))
          .getSemanticsData();
      expect(initialSemantics.value, spokenRatio());
      expect(initialSemantics.increasedValue, isNot(initialSemantics.value));
      owner.requestFocus();
      await tester.pumpAndSettle();
      expect(owner.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(layout().ratio, greaterThan(initial.ratio));
      expect(
        tester
            .getSemantics(_semantics(Axis.horizontal))
            .getSemanticsData()
            .value,
        initialSemantics.increasedValue,
      );
      expect(layout().first!.ratio, initial.first!.ratio);
      expect(layout().second!.ratio, initial.second!.ratio);
      expect(container.read(sessionControllerProvider).activeSessionId, active);
      expect(owner.hasPrimaryFocus, isTrue);
      expect(backend.writes, hasLength(writes));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 100; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final maximum = layout().ratio;
      expect(maximum, greaterThan(initial.ratio));
      expect(maximum, lessThan(1));
      final atMaximum = tester
          .getSemantics(_semantics(Axis.horizontal))
          .getSemanticsData();
      expect(atMaximum.value, spokenRatio());
      expect(atMaximum.hasAction(SemanticsAction.increase), isFalse);
      expect(atMaximum.hasAction(SemanticsAction.decrease), isTrue);
      expect(atMaximum.hint, contains('Maximum size reached.'));
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: _semantics(Axis.horizontal),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        contains('Maximum size reached.'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        layout().ratio,
        maximum,
        reason: 'the existing pane minimum clamps resize',
      );
      final semanticsOwner =
          tester.binding.renderViews.single.owner!.semanticsOwner!;
      semanticsOwner.performAction(
        tester.getSemantics(_semantics(Axis.horizontal)).id,
        SemanticsAction.decrease,
      );
      await tester.pumpAndSettle();
      expect(layout().ratio, lessThan(maximum));
      expect(
        tester
            .getSemantics(_semantics(Axis.horizontal))
            .getSemanticsData()
            .value,
        atMaximum.decreasedValue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      for (var i = 0; i < 150; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      final minimum = layout().ratio;
      expect(minimum, greaterThan(0));
      expect(minimum, lessThan(initial.ratio));
      final atMinimum = tester
          .getSemantics(_semantics(Axis.horizontal))
          .getSemanticsData();
      expect(atMinimum.value, spokenRatio());
      expect(atMinimum.hasAction(SemanticsAction.decrease), isFalse);
      expect(atMinimum.hasAction(SemanticsAction.increase), isTrue);
      expect(atMinimum.hint, contains('Minimum size reached.'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(layout().ratio, minimum);
      expect(container.read(sessionControllerProvider).activeSessionId, active);
      expect(layout().first!.ratio, initial.first!.ratio);
      expect(layout().second!.ratio, initial.second!.ratio);
      expect(owner.hasPrimaryFocus, isTrue);
      expect(backend.writes, hasLength(writes));
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
