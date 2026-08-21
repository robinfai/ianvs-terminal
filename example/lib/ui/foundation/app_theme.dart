import 'package:flutter/material.dart';

import 'app_theme_tokens.dart';

ThemeData buildIanvsTerminalTheme(
  Brightness brightness, {
  TargetPlatform? platform,
}) {
  final tokens = AppThemeTokens.fallbackFor(brightness);
  final controls = tokens.controls;
  final resolvedPlatform = platform ?? TargetPlatform.macOS;
  final usesTouchControlDensity = switch (resolvedPlatform) {
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS => true,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
  final denseControlHeight = usesTouchControlDensity ? 48.0 : controls.dense;
  final compactControlHeight = usesTouchControlDensity
      ? 48.0
      : controls.compact;
  final regularControlHeight = usesTouchControlDensity
      ? 48.0
      : controls.regular;
  final inputIconConstraints = BoxConstraints(
    minWidth: regularControlHeight,
    minHeight: regularControlHeight,
  );
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

  final typography = Typography.material2021(
    platform: resolvedPlatform,
    colorScheme: colorScheme,
  );
  final baseTextTheme = brightness == Brightness.dark
      ? typography.white
      : typography.black;
  final textTheme = baseTextTheme
      .copyWith(
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          height: 1.18,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontSize: usesTouchControlDensity ? 17 : 14,
          height: 1.24,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontSize: usesTouchControlDensity ? 15 : 12.5,
          height: 1.28,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          fontSize: usesTouchControlDensity ? 17 : 13,
          height: 1.4,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: usesTouchControlDensity ? 15 : 12.5,
          height: 1.36,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          fontSize: usesTouchControlDensity ? 13 : 11,
          height: 1.32,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontSize: usesTouchControlDensity ? 15 : 11.5,
          height: 1.2,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          fontSize: usesTouchControlDensity ? 13 : 10.5,
          height: 1.2,
          fontWeight: FontWeight.w500,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontSize: usesTouchControlDensity ? 11 : 9.5,
          height: 1.2,
          fontWeight: FontWeight.w500,
        ),
      )
      .apply(bodyColor: tokens.textPrimary, displayColor: tokens.textPrimary);

  return ThemeData(
    useMaterial3: true,
    platform: resolvedPlatform,
    typography: typography,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: usesTouchControlDensity
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap,
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
        minimumHeight: regularControlHeight,
        horizontalPadding: tokens.spacing.xl,
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buttonStyle(
        tokens: tokens,
        background: Colors.transparent,
        foreground: tokens.textPrimary,
        minimumHeight: regularControlHeight,
        horizontalPadding: tokens.spacing.xl,
        side: BorderSide(color: tokens.borderStrong),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _buttonStyle(
        tokens: tokens,
        background: Colors.transparent,
        foreground: tokens.textPrimary,
        minimumHeight: compactControlHeight,
        horizontalPadding: tokens.spacing.lg,
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: tokens.textMuted,
        hoverColor: tokens.accent.withValues(alpha: 0.12),
        focusColor: tokens.focusRing.withValues(alpha: 0.22),
        iconSize: 15,
        padding: EdgeInsets.all(tokens.spacing.sm),
        minimumSize: Size.square(denseControlHeight),
        tapTargetSize: usesTouchControlDensity
            ? MaterialTapTargetSize.padded
            : MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: tokens.chrome,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: tokens.focusRing, width: 2),
      ),
      errorBorder: outline.copyWith(
        borderSide: BorderSide(color: tokens.danger),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: tokens.danger, width: 2),
      ),
      constraints: BoxConstraints(minHeight: regularControlHeight),
      prefixIconConstraints: inputIconConstraints,
      suffixIconConstraints: inputIconConstraints,
      contentPadding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.sm,
      ),
      labelStyle: textTheme.labelMedium?.copyWith(
        color: tokens.textMuted,
        fontSize: usesTouchControlDensity ? 13 : 11.5,
        height: 1.1,
      ),
      helperStyle: textTheme.bodySmall?.copyWith(
        color: tokens.textSubtle,
        fontSize: usesTouchControlDensity ? 13 : 11,
        height: 1.25,
      ),
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: tokens.textSubtle,
        fontSize: usesTouchControlDensity ? 13 : 11.5,
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
      materialTapTargetSize: usesTouchControlDensity
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
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
  required TextStyle? textStyle,
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
              return BorderSide(color: tokens.focusRing, width: 2);
            }
            return side;
          }),
    textStyle: WidgetStatePropertyAll(textStyle),
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
