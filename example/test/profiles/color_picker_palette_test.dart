import 'dart:ui' show SemanticsAction;

import 'package:app/features/profiles/widgets/color_picker_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Color picker palette controls', () {
    testWidgets('color palette falls back from invalid aspect ratios', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 120,
              child: ColorPickerPalette(
                aspectRatio: double.nan,
                color: HSVColor.fromColor(Colors.red),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ColorPickerPalette), findsOneWidget);
    });

    testWidgets('color palette ignores zero-sized gestures', (tester) async {
      var changed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 0,
              height: 24,
              child: ColorPickerPalette(
                color: HSVColor.fromColor(Colors.red),
                onChanged: (_) => changed = true,
              ),
            ),
          ),
        ),
      );

      final gestureDetector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      gestureDetector.onTapDown?.call(
        TapDownDetails(localPosition: Offset.zero),
      );

      expect(changed, isFalse);
    });

    testWidgets('hue slider ignores zero-width gestures', (tester) async {
      var changed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 0,
              child: HueSlider(
                color: HSVColor.fromColor(Colors.red),
                onChanged: (_) => changed = true,
              ),
            ),
          ),
        ),
      );

      final gestureDetector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      gestureDetector.onTapDown?.call(
        TapDownDetails(localPosition: Offset.zero),
      );

      expect(changed, isFalse);
    });

    testWidgets('hue slider exposes adjustable semantics and arrow keys', (
      tester,
    ) async {
      var color = const HSVColor.fromAHSV(1, 120, 1, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Center(
              child: SizedBox(
                width: 240,
                child: HueSlider(
                  color: color,
                  onChanged: (value) => setState(() => color = value),
                ),
              ),
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.bySemanticsLabel('Hue'));
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );

      await tester.tap(find.byType(HueSlider));
      await tester.pump();
      final hueAfterTap = color.hue;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(color.hue, (hueAfterTap + 1) % 360);
    });
  });
}
