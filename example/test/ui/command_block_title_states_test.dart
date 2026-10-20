import 'dart:ui' as ui;

import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../../packages/ianvs_terminal/test/composer/composer_theme_test.dart'
    show contrast;
import '../../../packages/ianvs_terminal/test/terminal/command_blocks_test.dart'
    show block;

class _Fixture {
  final GlobalKey boundary = GlobalKey();
  final reinputs = <String>[];
  late final blocks = CommandBlockController(
    request: (_) => {
      'blocks': [block('first'), block('second')],
    },
  )..refresh();
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  bool highContrast = false,
  bool selected = false,
  bool summary = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = summary
      ? const Size(700, 180)
      : const Size(900, 900);
  addTearDown(tester.view.reset);
  final fixture = _Fixture();
  if (selected) fixture.blocks.select('first');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.blocks.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
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
        body: RepaintBoundary(
          key: fixture.boundary,
          child: TerminalCommandBlocksView(
            controller: fixture.blocks,
            showToolbar: false,
            onReinput: fixture.reinputs.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Finder _title(String id) => find
    .ancestor(of: find.text('echo $id'), matching: find.byType(InkWell))
    .first;

Future<Color> _paintedPixel(
  WidgetTester tester,
  GlobalKey boundary,
  Offset point,
) async => (await tester.runAsync(() async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final local = render.globalToLocal(point);
  final image = await render.toImage(pixelRatio: 1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (local.dy.floor() * image.width + local.dx.floor()) * 4;
    return Color.fromARGB(
      data.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  } finally {
    image.dispose();
  }
}))!;

bool _titleFocused(WidgetTester tester, String id) =>
    Focus.of(tester.element(find.text('echo $id'))).hasPrimaryFocus;

Future<void> _tabTo(WidgetTester tester, String id) async {
  for (var count = 0; count < 16 && !_titleFocused(tester, id); count++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  expect(_titleFocused(tester, id), isTrue);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      for (final selected in [false, true]) {
        testWidgets(
          'Block title paints hover and press above its opaque block: '
          '${brightness.name}/contrast=$highContrast/selected=$selected',
          (tester) async {
            final fixture = await _mount(
              tester,
              brightness: brightness,
              highContrast: highContrast,
              selected: selected,
            );
            final title = _title('first');
            final bounds = tester.getRect(title);
            final sample = Offset(bounds.right - 12, bounds.center.dy);
            final baseline = await _paintedPixel(
              tester,
              fixture.boundary,
              sample,
            );
            final selectionBefore = Set<String>.of(fixture.blocks.selected);
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            try {
              await mouse.moveTo(sample);
              await tester.pumpAndSettle();
              final hover = await _paintedPixel(
                tester,
                fixture.boundary,
                sample,
              );
              expect(
                hover,
                isNot(baseline),
                reason:
                    'hover ink must be visibly painted, not hidden below Container',
              );
              expect(fixture.blocks.selected, selectionBefore);
              await mouse.down(sample);
              await tester.pump(const Duration(milliseconds: 240));
              await tester.pumpAndSettle();
              final pressed = await _paintedPixel(
                tester,
                fixture.boundary,
                sample,
              );
              expect(pressed, isNot(hover));
              expect(pressed, isNot(baseline));
              expect(
                fixture.blocks.selected,
                selectionBefore,
                reason: 'pointer down only presents pressed state',
              );
              final tokens = ComposerTheme.of(tester.element(title));
              expect(
                contrast(tokens.foreground, hover),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                contrast(tokens.foreground, pressed),
                greaterThanOrEqualTo(4.5),
              );
              await mouse.up();
              await tester.pumpAndSettle();
              expect(fixture.blocks.selected, {'first'});
              expect(fixture.reinputs, isEmpty);
            } finally {
              await mouse.removePointer();
            }
          },
          variant: TargetPlatformVariant.only(TargetPlatform.macOS),
        );
      }

      testWidgets('Block keyboard focus is visible with 3 to 1 contrast: '
          '${brightness.name}/contrast=$highContrast', (tester) async {
        final fixture = await _mount(
          tester,
          brightness: brightness,
          highContrast: highContrast,
        );
        final title = _title('first');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        try {
          await mouse.moveTo(tester.getCenter(title));
          await tester.pumpAndSettle();
          final bounds = tester.getRect(title);
          final ringPoint = Offset(bounds.center.dx, bounds.top + .5);
          final hover = await _paintedPixel(
            tester,
            fixture.boundary,
            ringPoint,
          );
          await _tabTo(tester, 'first');
          final focusedBounds = tester.getRect(title);
          final focused = await _paintedPixel(
            tester,
            fixture.boundary,
            Offset(focusedBounds.center.dx, focusedBounds.top + 1.5),
          );
          expect(focused, isNot(hover));
          final adjacent = await _paintedPixel(
            tester,
            fixture.boundary,
            Offset(focusedBounds.right - 12, focusedBounds.center.dy),
          );
          expect(
            contrast(focused, adjacent),
            greaterThanOrEqualTo(3),
            reason:
                'before=$bounds, now=$focusedBounds, ring=$focused, fill=$adjacent, token=${ComposerTheme.of(tester.element(title)).focus}',
          );
          expect(fixture.blocks.selected, isEmpty);
          expect(fixture.reinputs, isEmpty);
          fixture.blocks.select('first');
          await tester.pumpAndSettle();
          final selectedBounds = tester.getRect(title);
          final selectedRing = await _paintedPixel(
            tester,
            fixture.boundary,
            Offset(selectedBounds.center.dx, selectedBounds.top + 1.5),
          );
          final selectedFill = await _paintedPixel(
            tester,
            fixture.boundary,
            Offset(selectedBounds.right - 12, selectedBounds.center.dy),
          );
          expect(contrast(selectedRing, selectedFill), greaterThanOrEqualTo(3));
          expect(_titleFocused(tester, 'first'), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(fixture.blocks.selected, {'first'});
          expect(fixture.reinputs, isEmpty);
        } finally {
          await mouse.removePointer();
        }
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }

  for (final summary in [false, true]) {
    testWidgets(
      'cancelled pointer press on ${summary ? 'summary' : 'full'} title '
      'does not select or re-input',
      (tester) async {
        final fixture = await _mount(tester, summary: summary);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        try {
          await mouse.down(tester.getCenter(_title('first')));
          await tester.pump(const Duration(milliseconds: 240));
          await tester.pumpAndSettle();
          expect(fixture.blocks.selected, isEmpty);
          await mouse.moveTo(const Offset(850, 450));
          await mouse.up();
          await tester.pumpAndSettle();
          expect(fixture.blocks.selected, isEmpty);
          expect(fixture.reinputs, isEmpty);
        } finally {
          await mouse.removePointer();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'focused ${summary ? 'summary' : 'full'} title Enter selects that '
      'block instead of re-inputting the previous selection',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final fixture = await _mount(
            tester,
            selected: true,
            summary: summary,
          );
          await _tabTo(tester, 'second');
          expect(fixture.blocks.selected, {'first'});
          expect(fixture.reinputs, isEmpty);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(fixture.blocks.selected, {'second'});
          expect(fixture.reinputs, isEmpty);
          final selectedNode = tester.getSemantics(
            find.byKey(const ValueKey('command-block-second')),
          );
          expect(
            selectedNode.getSemanticsData().flagsCollection.isSelected,
            ui.Tristate.isTrue,
          );
          // Existing list-focus Enter still means put the selected command into
          // the Composer. Title activation itself must never re-input a command.
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(fixture.reinputs, ['echo second']);
        } finally {
          semantics.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
