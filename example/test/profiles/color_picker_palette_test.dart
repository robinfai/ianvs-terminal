import 'package:app/features/profiles/widgets/color_picker_palette.dart';
import 'package:flutter/material.dart';
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
  });
}
