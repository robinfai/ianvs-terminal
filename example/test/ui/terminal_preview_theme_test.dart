import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/command_blocks_preview.dart';
import 'package:app/ui/previews/composer_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  for (final preview in [
    (
      name: 'Composer light',
      build: composerRedesignLightPreview,
      brightness: Brightness.light,
      highContrast: false,
    ),
    (
      name: 'Composer dark',
      build: composerRedesignDarkPreview,
      brightness: Brightness.dark,
      highContrast: false,
    ),
    (
      name: 'Composer high contrast',
      build: composerRedesignContrastPreview,
      brightness: Brightness.light,
      highContrast: true,
    ),
    for (final brightness in Brightness.values)
      for (final highContrast in [false, true])
        (
          name: 'Blocks ${brightness.name} contrast=$highContrast',
          build: () => CommandBlocksPreview(
            brightness: brightness,
            highContrast: highContrast,
          ),
          brightness: brightness,
          highContrast: highContrast,
        ),
  ]) {
    testWidgets(
      '${preview.name} uses the production palette',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 850);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(preview.build());
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(TerminalComposerView));
        final actual = Theme.of(context);
        final expected = buildIanvsTerminalTheme(
          preview.brightness,
          platform: TargetPlatform.macOS,
          highContrast: preview.highContrast,
        );
        final composer = expected.extension<ComposerTheme>()!;
        expect(MediaQuery.highContrastOf(context), preview.highContrast);
        expect(actual.colorScheme.outline, expected.colorScheme.outline);
        expect(
          actual.colorScheme.onSurfaceVariant,
          expected.colorScheme.onSurfaceVariant,
        );
        expect(
          actual.extension<AppThemeTokens>()!.border,
          expected.extension<AppThemeTokens>()!.border,
        );

        // Inspect colors actually handed to the production painting widgets,
        // not only the MediaQuery/ComposerTheme highContrast flags.
        final surface = tester.widget<Material>(
          find.byKey(const Key('composer-surface')),
        );
        expect(surface.color, composer.surface);
        expect(
          (surface.shape! as RoundedRectangleBorder).side.color,
          composer.border,
        );
        for (final viewport in tester.widgetList<TerminalViewport>(
          find.byType(TerminalViewport),
        )) {
          expect(viewport.colors!.scrollbarThumb, composer.border);
          expect(viewport.colors!.foreground, composer.foreground);
        }
        if (preview.highContrast) {
          final normal = buildIanvsTerminalTheme(preview.brightness);
          expect(actual.colorScheme.outline, isNot(normal.colorScheme.outline));
          expect(
            actual.colorScheme.onSurfaceVariant,
            isNot(normal.colorScheme.onSurfaceVariant),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }
}
