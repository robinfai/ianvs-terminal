import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/ui/app_ui.dart';

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

  testWidgets('light and dark flutterm themes expose stable brand tokens', (
    tester,
  ) async {
    final lightTheme = buildFluttermTheme(Brightness.light);
    final lightTokens = lightTheme.extension<AppThemeTokens>()!;
    expect(lightTokens.canvas.toARGB32(), const Color(0xFFF5F5F7).toARGB32());
    expect(lightTokens.chrome.toARGB32(), const Color(0xFFEDEEF2).toARGB32());
    expect(lightTokens.panel.toARGB32(), const Color(0xFFFFFFFF).toARGB32());
    expect(
      lightTokens.panelElevated.toARGB32(),
      const Color(0xFFFDFDFE).toARGB32(),
    );
    expect(lightTokens.border.toARGB32(), const Color(0xFFD1D1D6).toARGB32());
    expect(
      lightTokens.borderStrong.toARGB32(),
      const Color(0xFFA7A7AD).toARGB32(),
    );
    expect(
      lightTokens.textPrimary.toARGB32(),
      const Color(0xFF1D1D1F).toARGB32(),
    );
    expect(lightTokens.accent.toARGB32(), const Color(0xFF007AFF).toARGB32());
    expect(lightTokens.selected.toARGB32(), const Color(0xFFD9ECFF).toARGB32());
    expect(
      lightTokens.terminalFrame.toARGB32(),
      const Color(0xFFD1D1D6).toARGB32(),
    );
    expect(
      lightTokens.inactiveScrim.toARGB32(),
      const Color(0x66000000).toARGB32(),
    );
    expect(lightTokens.spacing.xs, 4);
    expect(lightTokens.spacing.sm, 6);
    expect(lightTokens.spacing.md, 8);
    expect(lightTokens.spacing.lg, 12);
    expect(lightTokens.spacing.xl, 16);
    expect(lightTokens.spacing.xxl, 22);
    expect(lightTokens.radius.sm, 5);
    expect(lightTokens.radius.md, 7);
    expect(lightTokens.radius.lg, 10);
    expect(lightTokens.radius.xl, 12);
    expect(lightTokens.controls.dense, 32);
    expect(lightTokens.controls.compact, 36);
    expect(lightTokens.controls.regular, 40);
    expect(lightTheme.textTheme.bodyMedium?.fontSize, 13);
    expect(lightTheme.textTheme.bodySmall?.fontSize, 11.5);
    expect(lightTheme.textTheme.titleMedium?.fontSize, 14.5);
    final lightInputPadding =
        lightTheme.inputDecorationTheme.contentPadding! as EdgeInsets;
    expect(lightInputPadding.top, 8);
    expect(lightInputPadding.bottom, 8);
    expect(lightTheme.inputDecorationTheme.constraints?.minHeight, 42);
    expect(
      lightTheme.scaffoldBackgroundColor.toARGB32(),
      lightTokens.canvas.toARGB32(),
    );
    expect(
      lightTheme.dialogTheme.backgroundColor!.toARGB32(),
      lightTokens.panel.toARGB32(),
    );
    expect(
      lightTheme.iconButtonTheme.style?.minimumSize?.resolve({}),
      const Size.square(32),
    );
    expect(
      lightTheme.filledButtonTheme.style?.minimumSize?.resolve({}),
      const Size(0, 40),
    );
    expect(
      lightTheme.outlinedButtonTheme.style?.minimumSize?.resolve({}),
      const Size(0, 40),
    );
    expect(
      lightTheme.textButtonTheme.style?.minimumSize?.resolve({}),
      const Size(0, 36),
    );
    expect(
      contrastRatio(lightTokens.textPrimary, lightTokens.panel),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(lightTokens.focusRing, lightTokens.panel),
      greaterThanOrEqualTo(3),
    );

    final darkTheme = buildFluttermTheme(Brightness.dark);
    final darkTokens = darkTheme.extension<AppThemeTokens>()!;
    expect(darkTokens.canvas.toARGB32(), const Color(0xFF1D1D1F).toARGB32());
    expect(darkTokens.overlay.toARGB32(), const Color(0xFF3A3A3C).toARGB32());
    expect(
      darkTokens.textPrimary.toARGB32(),
      const Color(0xFFF5F5F7).toARGB32(),
    );
    expect(darkTokens.accent.toARGB32(), const Color(0xFF0A84FF).toARGB32());
    expect(
      darkTokens.borderStrong.toARGB32(),
      const Color(0xFF636366).toARGB32(),
    );
    expect(
      darkTheme.scaffoldBackgroundColor.toARGB32(),
      darkTokens.canvas.toARGB32(),
    );
    expect(
      darkTheme.dialogTheme.backgroundColor!.toARGB32(),
      darkTokens.panel.toARGB32(),
    );
    expect(darkTheme.textTheme.bodyMedium?.fontSize, 13);
    expect(darkTheme.textTheme.bodySmall?.fontSize, 11.5);
    expect(
      contrastRatio(darkTokens.textPrimary, darkTokens.panel),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(darkTokens.focusRing, darkTokens.panel),
      greaterThanOrEqualTo(3),
    );

    await tester.pumpWidget(
      Theme(
        data: lightTheme,
        child: const SizedBox(key: Key('light-theme-probe')),
      ),
    );

    final lightContext = tester.element(
      find.byKey(const Key('light-theme-probe')),
    );
    final hydratedLightTokens = AppThemeTokens.of(lightContext);
    expect(
      hydratedLightTokens.canvas.toARGB32(),
      const Color(0xFFF5F5F7).toARGB32(),
    );
  });

  testWidgets(
    'terminal color bridge keeps theme defaults and applies profile overrides',
    (tester) async {
      await tester.pumpWidget(
        Theme(
          data: buildFluttermTheme(Brightness.light),
          child: const SizedBox(key: Key('light-terminal-probe')),
        ),
      );

      final lightContext = tester.element(
        find.byKey(const Key('light-terminal-probe')),
      );
      final lightDefaults = resolveTerminalColors(lightContext).viewport;
      expect(
        lightDefaults.canvasBackground.toARGB32(),
        const Color(0xFFF8F7F2).toARGB32(),
      );
      expect(
        lightDefaults.foreground.toARGB32(),
        const Color(0xFF111111).toARGB32(),
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
          data: buildFluttermTheme(Brightness.dark),
          child: const SizedBox(key: Key('dark-terminal-probe')),
        ),
      );

      final darkContext = tester.element(
        find.byKey(const Key('dark-terminal-probe')),
      );
      final darkDefaults = resolveTerminalColors(darkContext).viewport;
      expect(
        darkDefaults.canvasBackground.toARGB32(),
        const Color(0xFF050608).toARGB32(),
      );
      expect(
        darkDefaults.foreground.toARGB32(),
        const Color(0xFFF8FAFC).toARGB32(),
      );
    },
  );
}
