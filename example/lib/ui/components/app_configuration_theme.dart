import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

/// A quiet, platform-sized theme scope for configuration surfaces.
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

  // macOS form content uses a compact 20-point outer margin.
  static const _macSpacing = AppThemeSpacing(
    xs: 4,
    sm: 6,
    md: 8,
    lg: 12,
    xl: 16,
    xxl: 20,
  );

  static const _radius = AppThemeRadius(sm: 4, md: 6, lg: 8, xl: 12);
  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final baseTokens = context.appTheme;
    final isMacOS = baseTheme.platform == TargetPlatform.macOS;
    final touch =
        baseTheme.materialTapTargetSize == MaterialTapTargetSize.padded;
    final controls = touch
        ? const AppThemeControls(dense: 48, compact: 48, regular: 48)
        : isMacOS
        ? const AppThemeControls(dense: 24, compact: 28, regular: 28)
        : const AppThemeControls(dense: 28, compact: 34, regular: 38);
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
      spacing: isMacOS ? _macSpacing : _spacing,
      radius: _radius,
      controls: controls,
      elevation: AppThemeElevation(
        floating: [
          BoxShadow(
            color: baseTheme.colorScheme.shadow.withValues(
              alpha: dark ? 0.34 : 0.12,
            ),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
        dialog: [
          BoxShadow(
            color: baseTheme.colorScheme.shadow.withValues(
              alpha: dark ? 0.42 : 0.15,
            ),
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
    final textTheme = baseTheme.textTheme.copyWith(
      titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
        fontSize: isMacOS ? 17 : 22,
        height: isMacOS ? 22 / 17 : null,
        fontWeight: FontWeight.w600,
        letterSpacing: isMacOS ? 0 : null,
      ),
      titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
        fontSize: isMacOS
            ? 13
            : touch
            ? 17
            : 15,
        height: isMacOS ? 16 / 13 : null,
        fontWeight: FontWeight.w600,
        letterSpacing: isMacOS ? 0 : null,
      ),
      titleSmall: baseTheme.textTheme.titleSmall?.copyWith(
        fontSize: isMacOS
            ? 13
            : touch
            ? 15
            : 14,
        height: isMacOS ? 16 / 13 : null,
        fontWeight: isMacOS ? null : FontWeight.w600,
        letterSpacing: isMacOS ? 0 : null,
      ),
      bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
        fontSize: isMacOS
            ? 13
            : touch
            ? 17
            : 14,
        height: isMacOS ? 16 / 13 : null,
        letterSpacing: isMacOS ? 0 : null,
      ),
      bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
        fontSize: isMacOS
            ? 13
            : touch
            ? 15
            : 14,
        height: isMacOS ? 16 / 13 : null,
        letterSpacing: isMacOS ? 0 : null,
      ),
      bodySmall: baseTheme.textTheme.bodySmall?.copyWith(
        fontSize: isMacOS
            ? 12
            : touch
            ? 13
            : 12,
        height: isMacOS ? 15 / 12 : null,
        letterSpacing: isMacOS ? 0 : null,
      ),
      labelLarge: baseTheme.textTheme.labelLarge?.copyWith(
        fontSize: isMacOS
            ? 13
            : touch
            ? 15
            : 14,
        height: isMacOS ? 16 / 13 : null,
        letterSpacing: isMacOS ? 0 : null,
      ),
    );
    return Theme(
      data: baseTheme.copyWith(
        textTheme: textTheme,
        iconTheme: isMacOS
            ? baseTheme.iconTheme.copyWith(size: 16)
            : baseTheme.iconTheme,
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
          fillColor: tokens.panel,
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
          prefixIconConstraints: BoxConstraints(
            minWidth: tokens.controls.regular,
            minHeight: tokens.controls.regular,
          ),
          suffixIconConstraints: BoxConstraints(
            minWidth: tokens.controls.regular,
            minHeight: tokens.controls.regular,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: isMacOS
                ? 5
                : touch
                ? 12
                : 9,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: baseTheme.filledButtonTheme.style?.copyWith(
            shape: buttonShape,
            minimumSize: WidgetStatePropertyAll(
              Size(0, tokens.controls.regular),
            ),
            textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: baseTheme.outlinedButtonTheme.style?.copyWith(
            shape: buttonShape,
            side: WidgetStatePropertyAll(BorderSide(color: borderStrong)),
            minimumSize: WidgetStatePropertyAll(
              Size(0, tokens.controls.regular),
            ),
            textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: baseTheme.textButtonTheme.style?.copyWith(
            shape: buttonShape,
            textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          ),
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
