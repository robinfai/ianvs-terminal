import 'package:app/ui/components/app_mobile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('centers title with asymmetric controls at ${scale}x', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 667);
      addTearDown(tester.view.reset);
      await tester.pumpApp(
        Align(
          alignment: Alignment.topCenter,
          child: AppMobileHeader(
            title: '连接',
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.play_arrow)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
            ],
          ),
        ),
        platform: TargetPlatform.iOS,
        textScale: scale,
      );
      final title = tester.getRect(find.text('连接'));
      expect(title.center.dx, closeTo(375 / 2, 1));
      expect(
        title.right,
        lessThan(tester.getRect(find.byType(IconButton).first).left),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
