import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

@immutable
class AppThemeSpacing {
  const AppThemeSpacing({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;

  AppThemeSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) {
    return AppThemeSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
    );
  }

  AppThemeSpacing lerp(AppThemeSpacing other, double t) {
    return AppThemeSpacing(
      xs: lerpDouble(xs, other.xs, t)!,
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xl: lerpDouble(xl, other.xl, t)!,
      xxl: lerpDouble(xxl, other.xxl, t)!,
    );
  }
}

@immutable
class AppThemeRadius {
  const AppThemeRadius({
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });

  final double sm;
  final double md;
  final double lg;
  final double xl;

  AppThemeRadius copyWith({double? sm, double? md, double? lg, double? xl}) {
    return AppThemeRadius(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
    );
  }

  AppThemeRadius lerp(AppThemeRadius other, double t) {
    return AppThemeRadius(
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xl: lerpDouble(xl, other.xl, t)!,
    );
  }
}

@immutable
class AppThemeElevation {
  const AppThemeElevation({required this.floating, required this.dialog});

  final List<BoxShadow> floating;
  final List<BoxShadow> dialog;

  AppThemeElevation copyWith({
    List<BoxShadow>? floating,
    List<BoxShadow>? dialog,
  }) {
    return AppThemeElevation(
      floating: floating ?? this.floating,
      dialog: dialog ?? this.dialog,
    );
  }

  AppThemeElevation lerp(AppThemeElevation other, double t) {
    return AppThemeElevation(
      floating: BoxShadow.lerpList(floating, other.floating, t) ?? const [],
      dialog: BoxShadow.lerpList(dialog, other.dialog, t) ?? const [],
    );
  }
}

@immutable
class AppThemeControls {
  const AppThemeControls({
    required this.dense,
    required this.compact,
    required this.regular,
  });

  final double dense;
  final double compact;
  final double regular;

  AppThemeControls copyWith({double? dense, double? compact, double? regular}) {
    return AppThemeControls(
      dense: dense ?? this.dense,
      compact: compact ?? this.compact,
      regular: regular ?? this.regular,
    );
  }

  AppThemeControls lerp(AppThemeControls other, double t) {
    return AppThemeControls(
      dense: lerpDouble(dense, other.dense, t)!,
      compact: lerpDouble(compact, other.compact, t)!,
      regular: lerpDouble(regular, other.regular, t)!,
    );
  }
}

@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.canvas,
    required this.chrome,
    required this.panel,
    required this.overlay,
    required this.terminalSurface,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.textSubtle,
    required this.accent,
    required this.focus,
    required this.danger,
    required this.warning,
    required this.success,
    required this.spacing,
    required this.radius,
    required this.elevation,
    required this.controls,
  });

  static const light = AppThemeTokens(
    canvas: Color(0xFFF4F4F4),
    chrome: Color(0xFFEDEDED),
    panel: Color(0xFFFFFFFF),
    overlay: Color(0xFFFFFFFF),
    terminalSurface: Color(0xFFEDEDED),
    border: Color(0xFFD2D2D2),
    textPrimary: Color(0xFF111111),
    textMuted: Color(0xFF4A4A4A),
    textSubtle: Color(0xFF747474),
    accent: Color(0xFFF6C344),
    focus: Color(0xFFF6C344),
    danger: Color(0xFFB42318),
    warning: Color(0xFFB65E16),
    success: Color(0xFF166534),
    spacing: AppThemeSpacing(xs: 3, sm: 6, md: 10, lg: 12, xl: 16, xxl: 20),
    radius: AppThemeRadius(sm: 6, md: 8, lg: 10, xl: 12),
    controls: AppThemeControls(dense: 32, compact: 36, regular: 40),
    elevation: AppThemeElevation(
      floating: [
        BoxShadow(
          color: Color(0x16000000),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
      dialog: [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 16,
          offset: Offset(0, 8),
        ),
      ],
    ),
  );

  static const dark = AppThemeTokens(
    canvas: Color(0xFF17161D),
    chrome: Color(0xFF17161D),
    panel: Color(0xFF201E28),
    overlay: Color(0xFF201E28),
    terminalSurface: Color(0xFF17161D),
    border: Color(0xFF2D2938),
    textPrimary: Color(0xFFF1EFF7),
    textMuted: Color(0xFFC4BED3),
    textSubtle: Color(0xFF918AA3),
    accent: Color(0xFFF6C344),
    focus: Color(0xFFF6C344),
    danger: Color(0xFFF97066),
    warning: Color(0xFFF5A524),
    success: Color(0xFF6CE9A6),
    spacing: AppThemeSpacing(xs: 3, sm: 6, md: 10, lg: 12, xl: 16, xxl: 20),
    radius: AppThemeRadius(sm: 6, md: 8, lg: 10, xl: 12),
    controls: AppThemeControls(dense: 32, compact: 36, regular: 40),
    elevation: AppThemeElevation(
      floating: [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
      dialog: [
        BoxShadow(
          color: Color(0x47000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
  );

  final Color canvas;
  final Color chrome;
  final Color panel;
  final Color overlay;
  final Color terminalSurface;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color textSubtle;
  final Color accent;
  final Color focus;
  final Color danger;
  final Color warning;
  final Color success;
  final AppThemeSpacing spacing;
  final AppThemeRadius radius;
  final AppThemeElevation elevation;
  final AppThemeControls controls;

  static AppThemeTokens fallbackFor(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  static AppThemeTokens? maybeOf(BuildContext context) {
    return Theme.of(context).extension<AppThemeTokens>();
  }

  static AppThemeTokens of(BuildContext context) {
    return maybeOf(context) ?? fallbackFor(Theme.of(context).brightness);
  }

  @override
  AppThemeTokens copyWith({
    Color? canvas,
    Color? chrome,
    Color? panel,
    Color? overlay,
    Color? terminalSurface,
    Color? border,
    Color? textPrimary,
    Color? textMuted,
    Color? textSubtle,
    Color? accent,
    Color? focus,
    Color? danger,
    Color? warning,
    Color? success,
    AppThemeSpacing? spacing,
    AppThemeRadius? radius,
    AppThemeElevation? elevation,
    AppThemeControls? controls,
  }) {
    return AppThemeTokens(
      canvas: canvas ?? this.canvas,
      chrome: chrome ?? this.chrome,
      panel: panel ?? this.panel,
      overlay: overlay ?? this.overlay,
      terminalSurface: terminalSurface ?? this.terminalSurface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      textSubtle: textSubtle ?? this.textSubtle,
      accent: accent ?? this.accent,
      focus: focus ?? this.focus,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      spacing: spacing ?? this.spacing,
      radius: radius ?? this.radius,
      elevation: elevation ?? this.elevation,
      controls: controls ?? this.controls,
    );
  }

  @override
  AppThemeTokens lerp(
    covariant ThemeExtension<AppThemeTokens>? other,
    double t,
  ) {
    if (other is! AppThemeTokens) {
      return this;
    }
    return AppThemeTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      chrome: Color.lerp(chrome, other.chrome, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      terminalSurface: Color.lerp(terminalSurface, other.terminalSurface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSubtle: Color.lerp(textSubtle, other.textSubtle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      spacing: spacing.lerp(other.spacing, t),
      radius: radius.lerp(other.radius, t),
      elevation: elevation.lerp(other.elevation, t),
      controls: controls.lerp(other.controls, t),
    );
  }
}

extension AppThemeBuildContext on BuildContext {
  AppThemeTokens get appTheme => AppThemeTokens.of(this);
}
