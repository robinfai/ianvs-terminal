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

  test('Trail retains the shared design theme and terminal surfaces', () {
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
        expect(theme.textTheme, shared.textTheme);
        expect(
          theme.inputDecorationTheme,
          platform == TargetPlatform.macOS
              ? shared.inputDecorationTheme.copyWith(
                  hoverColor: theme.inputDecorationTheme.hoverColor,
                  focusedBorder: theme.inputDecorationTheme.focusedBorder,
                )
              : shared.inputDecorationTheme,
        );
        expect(
          theme.filledButtonTheme.style?.minimumSize?.resolve({}),
          shared.filledButtonTheme.style?.minimumSize?.resolve({}),
        );
        expect(
          theme.filledButtonTheme.style?.foregroundColor?.resolve({}),
          shared.filledButtonTheme.style?.foregroundColor?.resolve({}),
        );
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
  });

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
    expect(theme.textTheme.labelSmall?.fontSize, 13);
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

  testWidgets(
    'terminal color bridge follows the app theme and keeps interaction overrides',
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
        lightDefaults.canvasBackground.toARGB32(),
      );
      expect(
        overridden.foreground.toARGB32(),
        lightDefaults.foreground.toARGB32(),
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
