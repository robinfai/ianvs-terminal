import 'dart:io';

import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/composer_preview_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'configuration_capture_binding.dart';
import 'visual_capture_fonts.dart';

void main() {
  if (!Platform.isMacOS) {
    test('Composer captures require macOS rendering', () {}, skip: true);
    return;
  }
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);

  for (final variant in [
    (name: 'dark', brightness: Brightness.dark, size: const Size(820, 440)),
    (name: 'light', brightness: Brightness.light, size: const Size(820, 440)),
    (name: 'compact', brightness: Brightness.dark, size: const Size(360, 600)),
  ]) {
    for (final scenario in ComposerPreviewScenario.values) {
      testWidgets('Composer ${variant.name} ${scenario.name}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = variant.size;
        addTearDown(tester.view.reset);
        final controller = createComposerPreviewController(scenario);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('composer-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: withVisualCaptureFonts(
                buildIanvsTerminalTheme(
                  variant.brightness,
                  platform: TargetPlatform.macOS,
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    variant.name == 'compact' ? 2 : 1,
                  ),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TerminalComposerView(
                      controller: controller,
                      targetLabel: 'Local · zsh',
                      autofocus: true,
                      onUseTerminal: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        if (scenario == ComposerPreviewScenario.completion) {
          controller.requestCompletions();
          await tester.pumpAndSettle();
          controller.selectNext(1);
        } else if (scenario == ComposerPreviewScenario.history) {
          controller.openHistory();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const Key('composer-capture')),
          matchesGoldenFile(
            'goldens/composer/${variant.name}${scenario == ComposerPreviewScenario.completion ? '' : '-${scenario.name}'}.png',
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
