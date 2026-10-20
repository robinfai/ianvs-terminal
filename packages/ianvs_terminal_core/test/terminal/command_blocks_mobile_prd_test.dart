import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

void main() {
  testWidgets(
    'failed mobile blocks expose diagnosis with original source; unknown is not success',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final source = [
        for (final (id, exit, running) in [
          ('failed', 2, false),
          ('success', 0, false),
          ('unknown', null, false),
          ('running', 2, true),
        ])
          <String, Object?>{
            'id': id,
            'command': 'trail-fixture $id --directory /srv/public/fixture',
            'cwd': '/srv/public',
            'exitCode': exit,
            'running': running,
            'columns': 40,
            'totalLines': 1,
            'matchingLines': 1,
            'offset': 0,
            'lines': [
              {'index': 0, 'source_row': 100, 'text': '$id-output'},
            ],
          },
      ];
      final blocks = CommandBlockController(request: (_) => {'blocks': source})
        ..refresh();
      final attached = <CommandBlock>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: TerminalCommandBlocksView(
              controller: blocks,
              chinese: true,
              onReinput: (_) => fail('Diagnosis must not reinput a command'),
              onAskAi: attached.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('block-ai-diagnose-failed'));
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
      for (final id in ['success', 'unknown', 'running']) {
        expect(find.byKey(ValueKey('block-ai-diagnose-$id')), findsNothing);
      }
      final unknown = find.byKey(const ValueKey('command-block-unknown'));
      expect(
        find.descendant(of: unknown, matching: find.byIcon(Icons.check)),
        findsNothing,
      );
      expect(
        find.descendant(of: unknown, matching: find.byIcon(Icons.help_outline)),
        findsOneWidget,
      );
      final title = tester.widget<Text>(
        find.text('trail-fixture failed --directory /srv/public/fixture'),
      );
      expect(title.maxLines, 2);
      await tester.tap(action);
      expect(attached, hasLength(1));
      expect(attached.single.id, 'failed');
      expect(attached.single.exitCode, 2);
      expect(attached.single.lines.single.text, 'failed-output');
      expect(blocks.blocks, hasLength(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      blocks.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
