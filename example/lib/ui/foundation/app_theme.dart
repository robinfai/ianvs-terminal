import 'package:flutter/material.dart';

import 'app_theme_tokens.dart';

ThemeData buildIanvsTerminalTheme(Brightness brightness) {
  final tokens = AppThemeTokens.fallbackFor(brightness);
  final controls = tokens.controls;
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: tokens.accent,
        brightness: brightness,
      ).copyWith(
        surfaceContainerLowest: tokens.canvas,
        surfaceContainerLow: tokens.chrome,
        surfaceContainer: tokens.panel,
        surfaceContainerHigh: tokens.panelElevated,
        surfaceContainerHighest: tokens.overlay,
        surface: tokens.panel,
        outline: tokens.border,
        outlineVariant: tokens.borderStrong,
        primary: tokens.accent,
        onPrimary: brightness == Brightness.dark ? Colors.black : Colors.white,
        primaryContainer: tokens.selected,
        onPrimaryContainer: tokens.textPrimary,
        error: tokens.danger,
        errorContainer: tokens.dangerContainer,
        onSurface: tokens.textPrimary,
        onSurfaceVariant: tokens.textMuted,
      );

  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(tokens.radius.md),
    borderSide: BorderSide(color: tokens.border),
  );

  final baseTextTheme = brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;
  final textTheme = baseTextTheme
      .copyWith(
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          height: 1.12,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          height: 1.12,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontSize: 14,
          height: 1.14,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontSize: 12.5,
          height: 1.16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          fontSize: 13,
          height: 1.32,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 12.5,
          height: 1.3,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          fontSize: 11,
          height: 1.28,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontSize: 11.5,
          height: 1.12,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          fontSize: 10.5,
          height: 1.1,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontSize: 9.5,
          height: 1.08,
          fontWeight: FontWeight.w600,
        ),
      )
      .apply(bodyColor: tokens.textPrimary, displayColor: tokens.textPrimary);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.canvas,
    dividerColor: tokens.border,
    splashFactory: NoSplash.splashFactory,
    focusColor: tokens.focusRing.withValues(alpha: 0.22),
    hoverColor: tokens.accent.withValues(alpha: 0.10),
    highlightColor: tokens.accent.withValues(alpha: 0.12),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.xl),
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[tokens],
    filledButtonTheme: FilledButtonThemeData(
      style: _buttonStyle(
        tokens: tokens,
        background: tokens.accent,
        foreground: colorScheme.onPrimary,
        minimumHeight: controls.regular,
        horizontalPadding: tokens.spacing.xl,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buttonStyle(
        tokens: tokens,
        background: Colors.transparent,
        foreground: tokens.textPrimary,
        minimumHeight: controls.regular,
        horizontalPadding: tokens.spacing.xl,
        side: BorderSide(color: tokens.borderStrong),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _buttonStyle(
        tokens: tokens,
        background: Colors.transparent,
        foreground: tokens.textPrimary,
        minimumHeight: controls.compact,
        horizontalPadding: tokens.spacing.lg,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: tokens.textMuted,
        hoverColor: tokens.accent.withValues(alpha: 0.12),
        focusColor: tokens.focusRing.withValues(alpha: 0.22),
        iconSize: 15,
        padding: EdgeInsets.all(tokens.spacing.sm),
        minimumSize: Size.square(controls.dense),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
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
        borderSide: BorderSide(color: tokens.danger, width: 1.4),
      ),
      constraints: const BoxConstraints(minHeight: 36),
      contentPadding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.sm,
      ),
      labelStyle: TextStyle(
        color: tokens.textMuted,
        fontSize: 11.5,
        height: 1.1,
      ),
      helperStyle: TextStyle(
        color: tokens.textSubtle,
        fontSize: 11,
        height: 1.25,
      ),
      hintStyle: TextStyle(
        color: tokens.textSubtle,
        fontSize: 11.5,
        height: 1.18,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.border,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      iconColor: tokens.textMuted,
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return tokens.accent;
        }
        return tokens.textPrimary;
      }),
    ),
    switchTheme: SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.black;
        }
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return tokens.accent;
        }
        return null;
      }),
    ),
    textTheme: textTheme,
  );
}

ButtonStyle _buttonStyle({
  required AppThemeTokens tokens,
  required Color background,
  required Color foreground,
  required double minimumHeight,
  required double horizontalPadding,
  BorderSide? side,
}) {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return tokens.chrome.withValues(alpha: 0.54);
      }
      if (background == Colors.transparent) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return tokens.selected.withValues(alpha: 0.44);
        }
        return Colors.transparent;
      }
      if (states.contains(WidgetState.pressed)) {
        return Color.alphaBlend(
          Colors.black.withValues(alpha: 0.14),
          background,
        );
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return Color.alphaBlend(
          Colors.white.withValues(alpha: 0.12),
          background,
        );
      }
      return background;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return tokens.textSubtle;
      }
      return foreground;
    }),
    overlayColor: WidgetStatePropertyAll(
      tokens.focusRing.withValues(alpha: 0.12),
    ),
    side: side == null
        ? null
        : WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: tokens.focusRing, width: 1.5);
            }
            return side;
          }),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontWeight: FontWeight.w700),
    ),
    minimumSize: WidgetStatePropertyAll(Size(0, minimumHeight)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: tokens.spacing.xs + 1,
      ),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
    ),
  );
}
