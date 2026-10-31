import 'package:app/features/profiles/profile_models.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_design/ianvs_design.dart';

void main() {
  double contrastRatio(Color foreground, Color background) {
    final foregroundLuminance = foreground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance
        ? backgroundLuminance
        : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  test('terminal presets keep readable scrollbars across app themes', () {
    for (final brightness in Brightness.values) {
      for (final preset in terminalThemePresets) {
        final colors = resolveTerminalColorsForScheme(
          buildIanvsTerminalTheme(brightness).colorScheme,
          profileAppearance: TerminalProfileAppearance(colors: preset.palette),
          highContrast: true,
        ).viewport;
        expect(
          colors.canvasBackground.toARGB32(),
          int.parse(
            'FF${preset.palette.special.background!.substring(1)}',
            radix: 16,
          ),
          reason: '${preset.name} on $brightness',
        );
        expect(
          colors.foreground.toARGB32(),
          int.parse(
            'FF${preset.palette.special.foreground!.substring(1)}',
            radix: 16,
          ),
        );
        final track = Color.alphaBlend(
          colors.scrollbarTrack,
          colors.canvasBackground,
        );
        final thumb = Color.alphaBlend(colors.scrollbarThumb, track);
        expect(contrastRatio(thumb, track), greaterThanOrEqualTo(3));
        expect(colors.preserveExplicitForegroundColors, isFalse);
        expect(colors.minimumContrastRatio, 4.5);
      }
    }
  });

  test(
    'IDE presentation preserves shared control metrics and terminal surfaces',
    () {
      for (final brightness in Brightness.values) {
        for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
          final theme = buildIanvsTerminalTheme(brightness, platform: platform);
          final shared = IanvsTheme.build(
            brightness: brightness,
            platform: platform,
            density: platform == TargetPlatform.iOS
                ? IanvsDensity.touch
                : IanvsDensity.compact,
            touchVisualDensity: platform == TargetPlatform.iOS
                ? IanvsTouchVisualDensity.compact
                : IanvsTouchVisualDensity.standard,
          );
          final tokens = theme.extension<AppThemeTokens>()!;
          final design = theme.extension<IanvsTokens>()!;
          expect(theme.extension<IanvsTypography>(), isNotNull);
          // Presentation changes colors and headings, not editing metrics,
          // platform font fallback, or touch target geometry.
          for (final pair in [
            (theme.textTheme.bodyMedium, shared.textTheme.bodyMedium),
            (theme.textTheme.bodyLarge, shared.textTheme.bodyLarge),
            (theme.textTheme.bodySmall, shared.textTheme.bodySmall),
          ]) {
            expect(pair.$1?.fontSize, pair.$2?.fontSize);
            expect(pair.$1?.fontFamily, pair.$2?.fontFamily);
            expect(pair.$1?.fontFamilyFallback, pair.$2?.fontFamilyFallback);
            expect(pair.$1?.height, pair.$2?.height);
          }
          expect(
            theme.textTheme.titleMedium?.fontSize,
            platform == TargetPlatform.macOS ? 14 : 16,
          );
          expect(
            theme.inputDecorationTheme.contentPadding,
            shared.inputDecorationTheme.contentPadding,
          );
          expect(
            theme.inputDecorationTheme.constraints,
            shared.inputDecorationTheme.constraints,
          );
          expect(
            theme.filledButtonTheme.style?.minimumSize?.resolve({}),
            shared.filledButtonTheme.style?.minimumSize?.resolve({}),
          );
          final primaryStyle = theme.filledButtonTheme.style!;
          expect(
            contrastRatio(
              primaryStyle.foregroundColor!.resolve({}) ??
                  theme.colorScheme.onPrimary,
              primaryStyle.backgroundColor!.resolve({}) ??
                  theme.colorScheme.primary,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(design.controlRadius, 4);
          expect(design.dialogRadius, 8);
          expect(theme.inputDecorationTheme.fillColor, design.field);
          expect(tokens.canvas, design.canvas);
          expect(tokens.panel, design.field);
          expect(tokens.textPrimary, design.text);
          expect(tokens.controls.regular, design.controlHeight);
          expect(tokens.spacing.lg, IanvsSpacing.lg);
          expect(
            tokens.terminalSurface,
            AppThemeTokens.fallbackFor(brightness).terminalSurface,
          );
          expect(
            contrastRatio(tokens.textPrimary, tokens.panel),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(tokens.textSubtle, tokens.chrome),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(
              tokens.shellChrome.tabTextPrimary,
              tokens.shellChrome.tabActiveBackground,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  test('iOS uses compact touch visuals while retaining padded targets', () {
    final theme = buildIanvsTerminalTheme(
      Brightness.light,
      platform: TargetPlatform.iOS,
    );

    expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
    expect(theme.extension<IanvsTokens>()!.density, IanvsDensity.touch);
    expect(theme.extension<IanvsTokens>()!.isCompactTouch, isTrue);
    expect(theme.textTheme.bodyMedium?.fontSize, 16);
    expect(theme.textTheme.bodySmall?.fontSize, 13);
    expect(theme.textTheme.labelSmall?.fontSize, 12);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'CupertinoSystemText');
    expect(
      theme.inputDecorationTheme.prefixIconConstraints,
      const BoxConstraints(minWidth: 48, minHeight: 48),
    );
    expect(
      theme.inputDecorationTheme.suffixIconConstraints,
      const BoxConstraints(minWidth: 48, minHeight: 48),
    );
    expect(theme.inputDecorationTheme.labelStyle?.fontSize, 16);
    expect(theme.inputDecorationTheme.helperStyle?.fontSize, 13);
    expect(theme.inputDecorationTheme.hintStyle?.fontSize, 16);
    expect(
      theme.iconButtonTheme.style?.minimumSize?.resolve({}),
      const Size.square(44),
    );
    expect(
      theme.filledButtonTheme.style?.minimumSize?.resolve({}),
      const Size(44, 44),
    );
  });

  test(
    'high contrast distinguishes boundaries and focus without resizing text',
    () {
      for (final brightness in Brightness.values) {
        for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
          final normal = buildIanvsTerminalTheme(
            brightness,
            platform: platform,
          );
          final theme = buildIanvsTerminalTheme(
            brightness,
            platform: platform,
            highContrast: true,
          );
          final tokens = theme.extension<AppThemeTokens>()!;
          final surfaces = [
            tokens.canvas,
            tokens.chrome,
            tokens.panel,
            tokens.panelElevated,
          ];
          final focus = theme.inputDecorationTheme.focusedBorder!.borderSide;
          for (final surface in surfaces) {
            for (final boundary in [
              tokens.border,
              tokens.borderStrong,
              focus.color,
            ]) {
              expect(
                contrastRatio(boundary, surface),
                greaterThanOrEqualTo(3),
                reason: '$brightness / $platform / $boundary on $surface',
              );
            }
            for (final text in [
              tokens.textPrimary,
              tokens.textMuted,
              tokens.textSubtle,
            ]) {
              expect(contrastRatio(text, surface), greaterThanOrEqualTo(4.5));
            }
          }
          expect(
            tokens.border,
            isNot(normal.extension<AppThemeTokens>()!.border),
          );
          expect(
            focus.width,
            greaterThan(
              theme.inputDecorationTheme.enabledBorder!.borderSide.width,
            ),
          );
          final button = theme.outlinedButtonTheme.style!;
          expect(
            button.side!.resolve({WidgetState.focused})!.width,
            greaterThan(button.side!.resolve({})!.width),
          );
          expect(
            theme
                .dropdownMenuTheme
                .inputDecorationTheme!
                .enabledBorder!
                .borderSide
                .width,
            greaterThan(
              normal
                  .dropdownMenuTheme
                  .inputDecorationTheme!
                  .enabledBorder!
                  .borderSide
                  .width,
            ),
          );
          for (final shape in [
            theme.dialogTheme.shape,
            theme.popupMenuTheme.shape,
          ]) {
            final outlined = shape! as OutlinedBorder;
            expect(outlined.side.width, greaterThanOrEqualTo(1.5));
            expect(
              contrastRatio(outlined.side.color, tokens.panelElevated),
              greaterThanOrEqualTo(3),
            );
          }
          expect(
            theme.textTheme.bodyMedium!.fontSize,
            normal.textTheme.bodyMedium!.fontSize,
          );
          expect(
            theme.textTheme.bodySmall!.fontSize,
            normal.textTheme.bodySmall!.fontSize,
          );
          expect(
            theme.textTheme.labelSmall!.fontSize,
            normal.textTheme.labelSmall!.fontSize,
          );
          expect(
            tokens.controls.regular,
            normal.extension<AppThemeTokens>()!.controls.regular,
          );
        }
      }
    },
  );

  testWidgets(
    'terminal color bridge follows the app theme unless a profile overrides it',
    (tester) async {
      await tester.pumpWidget(
        Theme(
          data: buildIanvsTerminalTheme(Brightness.light),
          child: const SizedBox(key: Key('light-terminal-probe')),
        ),
      );

      final lightContext = tester.element(
        find.byKey(const Key('light-terminal-probe')),
      );
      final lightDefaults = resolveTerminalColors(lightContext).viewport;
      expect(
        lightDefaults.canvasBackground.toARGB32(),
        Theme.of(lightContext).colorScheme.surfaceContainerLowest.toARGB32(),
      );
      expect(
        lightDefaults.foreground.toARGB32(),
        Theme.of(lightContext).colorScheme.onSurface.toARGB32(),
      );
      expect(lightDefaults.minimumContrastRatio, 4.5);
      expect(lightDefaults.preserveExplicitForegroundColors, isTrue);
      expect(lightDefaults.smartCursorColor, isTrue);

      final overridden = resolveTerminalColors(
        lightContext,
        profileAppearance: const TerminalProfileAppearance(
          colors: TerminalProfileColors(
            special: TerminalSpecialColors(
              foreground: '#112233',
              background: '#445566',
              cursor: '#778899',
              selection: '#AABBCC',
            ),
          ),
        ),
      ).viewport;
      expect(
        overridden.canvasBackground.toARGB32(),
        const Color(0xFF445566).toARGB32(),
      );
      expect(
        overridden.foreground.toARGB32(),
        const Color(0xFF112233).toARGB32(),
      );
      expect(overridden.cursor.toARGB32(), const Color(0xFF778899).toARGB32());
      expect(
        overridden.selection.toARGB32(),
        const Color(0xFFAABBCC).toARGB32(),
      );

      await tester.pumpWidget(
        Theme(
          data: buildIanvsTerminalTheme(Brightness.dark),
          child: const SizedBox(key: Key('dark-terminal-probe')),
        ),
      );

      final darkContext = tester.element(
        find.byKey(const Key('dark-terminal-probe')),
      );
      final darkDefaults = resolveTerminalColors(darkContext).viewport;
      expect(darkDefaults.minimumContrastRatio, 4.5);
      expect(darkDefaults.preserveExplicitForegroundColors, isTrue);
      expect(
        darkDefaults.canvasBackground.toARGB32(),
        Theme.of(darkContext).colorScheme.surfaceContainerLowest.toARGB32(),
      );
      expect(
        darkDefaults.foreground.toARGB32(),
        Theme.of(darkContext).colorScheme.onSurface.toARGB32(),
      );
    },
  );
}
