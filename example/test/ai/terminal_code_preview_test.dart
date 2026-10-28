import 'package:app/features/ai/terminal_ai_message.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 800.0]) {
      testWidgets('code preview scrolls literal content $brightness $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final text = [
          '```',
          '[literal link](https://example.com)',
          '````',
          'echo ${'long-path/' * 40}',
          for (var i = 0; i < 40; i++) 'echo line $i',
        ].join('\n');
        await tester.pumpWidget(
          MaterialApp(
            theme: buildIanvsTerminalTheme(brightness),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width - 48,
                  height: 200,
                  child: SingleChildScrollView(
                    child: TerminalCodePreview(text: text),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SelectableText), findsOneWidget);
        final rendered = tester
            .widget<SelectableText>(find.byType(SelectableText))
            .data;
        expect(rendered, contains(text));
        final scrollables = tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        );
        expect(
          scrollables.any(
            (state) =>
                axisDirectionToAxis(state.axisDirection) == Axis.horizontal &&
                state.position.maxScrollExtent > 0,
          ),
          isTrue,
        );
        final vertical = scrollables.firstWhere(
          (state) => axisDirectionToAxis(state.axisDirection) == Axis.vertical,
        );
        expect(vertical.position.maxScrollExtent, greaterThan(0));
        vertical.position.jumpTo(vertical.position.maxScrollExtent);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
