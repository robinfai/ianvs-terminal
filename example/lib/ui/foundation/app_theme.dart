import 'package:flutter/material.dart';

import 'app_theme_tokens.dart';

ThemeData buildFluttermTheme(Brightness brightness) {
  final tokens = AppThemeTokens.fallbackFor(brightness);
  final controls = tokens.controls;
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: tokens.accent,
        brightness: brightness,
      ).copyWith(
        surface: tokens.panel,
        outline: tokens.border,
        primary: tokens.accent,
        onPrimary: Colors.black,
        onSurface: tokens.textPrimary,
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
          fontSize: 15,
          height: 1.14,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontSize: 13.5,
          height: 1.16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          fontSize: 13.5,
          height: 1.32,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 13,
          height: 1.3,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          fontSize: 11.5,
          height: 1.28,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontSize: 12.5,
          height: 1.12,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          fontSize: 11.5,
          height: 1.1,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontSize: 10.5,
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
    splashFactory: InkSparkle.splashFactory,
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.xl),
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[tokens],
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: Colors.black,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        minimumSize: Size(0, controls.regular),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.lg,
          vertical: tokens.spacing.sm + 1,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        side: BorderSide(color: tokens.border),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        minimumSize: Size(0, controls.regular),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.lg,
          vertical: tokens.spacing.sm + 1,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        minimumSize: Size(0, controls.compact),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.sm,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: tokens.textMuted,
        hoverColor: tokens.accent.withValues(alpha: 0.12),
        focusColor: tokens.focus.withValues(alpha: 0.18),
        iconSize: 16,
        padding: EdgeInsets.all(tokens.spacing.sm),
        minimumSize: Size.square(controls.dense),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: tokens.focus, width: 1.4),
      ),
      errorBorder: outline.copyWith(
        borderSide: BorderSide(color: tokens.danger),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: tokens.danger, width: 1.4),
      ),
      constraints: const BoxConstraints(minHeight: 48),
      contentPadding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.md,
      ),
      labelStyle: TextStyle(
        color: tokens.textMuted,
        fontSize: 12.5,
        height: 1.1,
      ),
      helperStyle: TextStyle(
        color: tokens.textSubtle,
        fontSize: 11.5,
        height: 1.25,
      ),
      hintStyle: TextStyle(
        color: tokens.textSubtle,
        fontSize: 12.5,
        height: 1.18,
      ),
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
