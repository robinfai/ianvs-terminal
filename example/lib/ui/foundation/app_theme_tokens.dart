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
    required this.chromeElevated,
    required this.panel,
    required this.panelElevated,
    required this.overlay,
    required this.terminalSurface,
    required this.terminalFrame,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textMuted,
    required this.textSubtle,
    required this.accent,
    required this.focus,
    required this.focusRing,
    required this.selected,
    required this.inactiveScrim,
    required this.danger,
    required this.warning,
    required this.success,
    required this.dangerContainer,
    required this.warningContainer,
    required this.successContainer,
    required this.spacing,
    required this.radius,
    required this.elevation,
    required this.controls,
  });

  static const light = AppThemeTokens(
    canvas: Color(0xFFF3F6F8),
    chrome: Color(0xFFE7EDF2),
    chromeElevated: Color(0xFFF8FAFC),
    panel: Color(0xFFFFFFFF),
    panelElevated: Color(0xFFFFFFFF),
    overlay: Color(0xFFFFFFFF),
    terminalSurface: Color(0xFFEAF0F4),
    terminalFrame: Color(0xFFCBD5E1),
    border: Color(0xFFC7D0DA),
    borderStrong: Color(0xFF8EA0B4),
    textPrimary: Color(0xFF111827),
    textMuted: Color(0xFF5B6777),
    textSubtle: Color(0xFF6B7280),
    accent: Color(0xFF0E7490),
    focus: Color(0xFF0E7490),
    focusRing: Color(0xFF0E7490),
    selected: Color(0xFFE0F2FE),
    inactiveScrim: Color(0x660F172A),
    danger: Color(0xFFB42318),
    warning: Color(0xFFB65E16),
    success: Color(0xFF166534),
    dangerContainer: Color(0xFFFEE4E2),
    warningContainer: Color(0xFFFFF1D6),
    successContainer: Color(0xFFDCFCE7),
    spacing: AppThemeSpacing(xs: 4, sm: 6, md: 10, lg: 14, xl: 18, xxl: 24),
    radius: AppThemeRadius(sm: 6, md: 8, lg: 12, xl: 14),
    controls: AppThemeControls(dense: 34, compact: 38, regular: 42),
    elevation: AppThemeElevation(
      floating: [
        BoxShadow(
          color: Color(0x1A0F172A),
          blurRadius: 14,
          offset: Offset(0, 8),
        ),
      ],
      dialog: [
        BoxShadow(
          color: Color(0x260F172A),
          blurRadius: 28,
          offset: Offset(0, 16),
        ),
      ],
    ),
  );

  static const dark = AppThemeTokens(
    canvas: Color(0xFF0F131A),
    chrome: Color(0xFF161A22),
    chromeElevated: Color(0xFF1A202B),
    panel: Color(0xFF1B202A),
    panelElevated: Color(0xFF222936),
    overlay: Color(0xFF222936),
    terminalSurface: Color(0xFF070A0F),
    terminalFrame: Color(0xFF2C3442),
    border: Color(0xFF303746),
    borderStrong: Color(0xFF455064),
    textPrimary: Color(0xFFF2F5F8),
    textMuted: Color(0xFFB8C1CC),
    textSubtle: Color(0xFF7F8A99),
    accent: Color(0xFF7DD3FC),
    focus: Color(0xFF7DD3FC),
    focusRing: Color(0xFF7DD3FC),
    selected: Color(0xFF0B3551),
    inactiveScrim: Color(0x8A000000),
    danger: Color(0xFFF97066),
    warning: Color(0xFFF5A524),
    success: Color(0xFF6CE9A6),
    dangerContainer: Color(0xFF4A1718),
    warningContainer: Color(0xFF3B2A0A),
    successContainer: Color(0xFF123524),
    spacing: AppThemeSpacing(xs: 4, sm: 6, md: 10, lg: 14, xl: 18, xxl: 24),
    radius: AppThemeRadius(sm: 6, md: 8, lg: 12, xl: 14),
    controls: AppThemeControls(dense: 34, compact: 38, regular: 42),
    elevation: AppThemeElevation(
      floating: [
        BoxShadow(
          color: Color(0x59000000),
          blurRadius: 18,
          offset: Offset(0, 10),
        ),
      ],
      dialog: [
        BoxShadow(
          color: Color(0x73000000),
          blurRadius: 34,
          offset: Offset(0, 18),
        ),
      ],
    ),
  );

  final Color canvas;
  final Color chrome;
  final Color chromeElevated;
  final Color panel;
  final Color panelElevated;
  final Color overlay;
  final Color terminalSurface;
  final Color terminalFrame;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textMuted;
  final Color textSubtle;
  final Color accent;
  final Color focus;
  final Color focusRing;
  final Color selected;
  final Color inactiveScrim;
  final Color danger;
  final Color warning;
  final Color success;
  final Color dangerContainer;
  final Color warningContainer;
  final Color successContainer;
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
    Color? chromeElevated,
    Color? panel,
    Color? panelElevated,
    Color? overlay,
    Color? terminalSurface,
    Color? terminalFrame,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textMuted,
    Color? textSubtle,
    Color? accent,
    Color? focus,
    Color? focusRing,
    Color? selected,
    Color? inactiveScrim,
    Color? danger,
    Color? warning,
    Color? success,
    Color? dangerContainer,
    Color? warningContainer,
    Color? successContainer,
    AppThemeSpacing? spacing,
    AppThemeRadius? radius,
    AppThemeElevation? elevation,
    AppThemeControls? controls,
  }) {
    return AppThemeTokens(
      canvas: canvas ?? this.canvas,
      chrome: chrome ?? this.chrome,
      chromeElevated: chromeElevated ?? this.chromeElevated,
      panel: panel ?? this.panel,
      panelElevated: panelElevated ?? this.panelElevated,
      overlay: overlay ?? this.overlay,
      terminalSurface: terminalSurface ?? this.terminalSurface,
      terminalFrame: terminalFrame ?? this.terminalFrame,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      textSubtle: textSubtle ?? this.textSubtle,
      accent: accent ?? this.accent,
      focus: focus ?? this.focus,
      focusRing: focusRing ?? this.focusRing,
      selected: selected ?? this.selected,
      inactiveScrim: inactiveScrim ?? this.inactiveScrim,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      successContainer: successContainer ?? this.successContainer,
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
      chromeElevated: Color.lerp(chromeElevated, other.chromeElevated, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelElevated: Color.lerp(panelElevated, other.panelElevated, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      terminalSurface: Color.lerp(terminalSurface, other.terminalSurface, t)!,
      terminalFrame: Color.lerp(terminalFrame, other.terminalFrame, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSubtle: Color.lerp(textSubtle, other.textSubtle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      inactiveScrim: Color.lerp(inactiveScrim, other.inactiveScrim, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
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
