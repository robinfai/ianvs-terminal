import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

/// A deliberately quieter, roomier theme scope for configuration surfaces.
///
/// Settings and profile editors share this scope so their navigation, forms,
/// panels, and fixed actions use one visual rhythm without changing the denser
/// terminal chrome outside the dialogs.
class AppConfigurationTheme extends StatelessWidget {
  const AppConfigurationTheme({super.key, required this.child});

  final Widget child;

  static const _spacing = AppThemeSpacing(
    xs: 4,
    sm: 6,
    md: 8,
    lg: 12,
    xl: 16,
    xxl: 24,
  );

  static const _radius = AppThemeRadius(sm: 6, md: 8, lg: 10, xl: 14);
  static const _controls = AppThemeControls(
    dense: 28,
    compact: 34,
    regular: 40,
  );

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final baseTokens = context.appTheme;
    final dark = baseTheme.brightness == Brightness.dark;
    final panel = baseTokens.panel;

    Color blend(Color foreground, double opacity, Color background) {
      return Color.alphaBlend(
        foreground.withValues(alpha: opacity),
        background,
      );
    }

    final quietChrome = blend(
      baseTokens.accent,
      dark ? 0.035 : 0.018,
      Color.lerp(panel, baseTokens.canvas, dark ? 0.22 : 0.36)!,
    );
    final quietSurface = blend(baseTokens.accent, dark ? 0.028 : 0.012, panel);
    final border = blend(baseTokens.textPrimary, dark ? 0.16 : 0.13, panel);
    final borderStrong = blend(
      baseTokens.textPrimary,
      dark ? 0.30 : 0.24,
      panel,
    );
    final selected = blend(baseTokens.accent, dark ? 0.20 : 0.10, panel);
    final tokens = baseTokens.copyWith(
      chrome: quietChrome,
      chromeElevated: quietSurface,
      panelElevated: quietSurface,
      overlay: quietSurface,
      border: border,
      borderStrong: borderStrong,
      selected: selected,
      spacing: _spacing,
      radius: _radius,
      controls: _controls,
      elevation: AppThemeElevation(
        floating: [
          BoxShadow(
            color: baseTokens.textPrimary.withValues(alpha: dark ? 0.34 : 0.12),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
        dialog: [
          BoxShadow(
            color: baseTokens.textPrimary.withValues(alpha: dark ? 0.42 : 0.15),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
    );
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      borderSide: BorderSide(color: tokens.border),
    );
    final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
    );
    return Theme(
      data: baseTheme.copyWith(
        scaffoldBackgroundColor: tokens.canvas,
        dividerColor: tokens.border,
        focusColor: tokens.focusRing.withValues(alpha: 0.20),
        hoverColor: tokens.accent.withValues(alpha: 0.07),
        highlightColor: tokens.accent.withValues(alpha: 0.09),
        extensions: <ThemeExtension<dynamic>>[tokens],
        dialogTheme: baseTheme.dialogTheme.copyWith(
          backgroundColor: tokens.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius.xl),
          ),
        ),
        dividerTheme: baseTheme.dividerTheme.copyWith(
          color: tokens.border,
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: tokens.chrome,
          border: outline,
          enabledBorder: outline,
          focusedBorder: outline.copyWith(
            borderSide: BorderSide(color: tokens.focusRing, width: 1.6),
          ),
          errorBorder: outline.copyWith(
            borderSide: BorderSide(color: tokens.danger),
          ),
          focusedErrorBorder: outline.copyWith(
            borderSide: BorderSide(color: tokens.danger, width: 1.6),
          ),
          constraints: BoxConstraints(minHeight: tokens.controls.regular),
          contentPadding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.lg,
            vertical: tokens.spacing.sm,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: baseTheme.filledButtonTheme.style?.copyWith(
            shape: buttonShape,
            minimumSize: WidgetStatePropertyAll(
              Size(0, tokens.controls.regular),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: baseTheme.outlinedButtonTheme.style?.copyWith(
            shape: buttonShape,
            side: WidgetStatePropertyAll(BorderSide(color: borderStrong)),
            minimumSize: WidgetStatePropertyAll(
              Size(0, tokens.controls.regular),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: baseTheme.textButtonTheme.style?.copyWith(shape: buttonShape),
        ),
        listTileTheme: baseTheme.listTileTheme.copyWith(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius.lg),
          ),
          iconColor: tokens.textMuted,
        ),
      ),
      child: child,
    );
  }
}
