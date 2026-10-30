import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_agent_chat/ianvs_agent_chat.dart';

import '../helpers/pump_app.dart';

void main() {
  for (final width in [375.0, 390.0]) {
    testWidgets('shared chat keeps 100-item markers intact at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);
      await tester.pumpApp(
        SingleChildScrollView(
          child: ChatMessageBody(
            text: List.generate(
              100,
              (i) =>
                  '${i + 1}. Apples can be eaten fresh, cooked, dried or fermented.',
            ).join('\n'),
          ),
        ),
        platform: TargetPlatform.iOS,
      );
      final columns = <double>[];
      for (final number in [9, 10, 99, 100]) {
        final marker = find.text('$number.');
        final rich = find.descendant(
          of: marker,
          matching: find.byType(RichText),
        );
        final paragraph = tester.renderObject<RenderParagraph>(rich);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: '$number.'.length),
        );
        expect(
          boxes,
          hasLength(1),
          reason: 'The number and period must remain on one line.',
        );
        final row = tester.widget<Row>(
          find.ancestor(of: marker, matching: find.byType(Row)).first,
        );
        final bodyLeft = tester.getRect(find.byWidget(row.children.last)).left;
        expect(
          tester.getRect(rich).left + boxes.single.right,
          lessThanOrEqualTo(bodyLeft),
        );
        columns.add(bodyLeft);
      }
      for (final column in columns) {
        expect(column, closeTo(columns.first, .01));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
