import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/composer_preview_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../../packages/ianvs_terminal/test/composer/composer_theme_test.dart'
    show contrast;

void main() {
  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      final mode = '${brightness.name}/contrast=$highContrast';
      final theme = buildIanvsTerminalTheme(
        brightness,
        platform: TargetPlatform.macOS,
        highContrast: highContrast,
      );
      Widget app(Widget child) => MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(highContrast: highContrast),
          child: child!,
        ),
        home: Scaffold(body: child),
      );

      testWidgets('enabled action text survives state overlays: $mode', (
        tester,
      ) async {
        final controller = createComposerPreviewController(
          ComposerPreviewScenario.suggestion,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          app(
            Column(
              children: [
                FilledButton(
                  key: const Key('host-filled-action'),
                  onPressed: () {},
                  child: const Text('Execute once'),
                ),
                FilledButton.tonal(
                  key: const Key('host-tonal-action'),
                  onPressed: () {},
                  child: const Text('Review'),
                ),
                TerminalComposerView(
                  controller: controller,
                  targetLabel: 'Contrast fixture',
                ),
              ],
            ),
          ),
        );
        for (final key in [
          const Key('host-filled-action'),
          const Key('host-tonal-action'),
          const Key('composer-primary-action'),
        ]) {
          final button = find.byKey(key);
          for (final state in <WidgetState?>[
            null,
            WidgetState.hovered,
            WidgetState.focused,
            WidgetState.pressed,
          ]) {
            final states = <WidgetState>{?state};
            final ink = tester.widget<InkWell>(
              find.descendant(of: button, matching: find.byType(InkWell)),
            );
            ink.statesController!.value = states;
            await tester.pumpAndSettle();
            final material = tester.widget<Material>(
              find.descendant(of: button, matching: find.byType(Material)),
            );
            final currentInk = tester.widget<InkWell>(
              find.descendant(of: button, matching: find.byType(InkWell)),
            );
            final overlay = currentInk.overlayColor?.resolve(states);
            final fill = overlay == null
                ? material.color!
                : Color.alphaBlend(overlay, material.color!);
            final ratio = contrast(material.textStyle!.color!, fill);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$mode / $key / $state: $ratio:1 after the ink overlay',
            );
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('terminal thumb remains distinct from its track: $mode', (
        tester,
      ) async {
        late TerminalViewportColors colors;
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) {
                colors = resolveTerminalColors(context).viewport;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        // The production terminal draws the translucent track first, then the
        // thumb on top. Comparing uncomposited RGB would hide the failure.
        final track = Color.alphaBlend(
          colors.scrollbarTrack,
          colors.canvasBackground,
        );
        final thumb = Color.alphaBlend(colors.scrollbarThumb, track);
        expect(contrast(thumb, track), greaterThanOrEqualTo(3));
      });

      testWidgets('selected block keeps its bookmark distinguishable: $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(900, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final blocks =
            CommandBlockController(
                request: (_) => {
                  'blocks': [
                    {
                      'id': 'marked',
                      'command': 'pwd',
                      'cwd': '/fixture',
                      'running': false,
                      'exitCode': 0,
                      'columns': 80,
                      'totalLines': 1,
                      'matchingLines': 1,
                      'lines': [
                        {'index': 0, 'text': '/fixture'},
                      ],
                    },
                  ],
                },
              )
              ..refresh()
              ..toggleBookmark('marked')
              ..select('marked');
        addTearDown(blocks.dispose);
        await tester.pumpWidget(
          app(
            TerminalCommandBlocksView(
              controller: blocks,
              onReinput: (_) {},
              showToolbar: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final block = find.byKey(const ValueKey('command-block-marked'));
        final container = tester.widget<Container>(block);
        final icon = tester.widget<Icon>(
          find.descendant(
            of: block,
            matching: find.byIcon(Icons.bookmark_outline),
          ),
        );
        final background = (container.decoration! as BoxDecoration).color!;
        expect(contrast(icon.color!, background), greaterThanOrEqualTo(3));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
