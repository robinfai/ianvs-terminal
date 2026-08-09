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
class AppShellChromeColors {
  const AppShellChromeColors({
    required this.base,
    required this.surface,
    required this.rail,
    required this.tabActiveBackground,
    required this.tabTrackBackground,
    required this.tabHoverBackground,
    required this.tabBorder,
    required this.tabTextPrimary,
    required this.tabTextMuted,
    required this.tabTextSubtle,
  });

  final Color base;
  final Color surface;
  final Color rail;
  final Color tabActiveBackground;
  final Color tabTrackBackground;
  final Color tabHoverBackground;
  final Color tabBorder;
  final Color tabTextPrimary;
  final Color tabTextMuted;
  final Color tabTextSubtle;

  AppShellChromeColors copyWith({
    Color? base,
    Color? surface,
    Color? rail,
    Color? tabActiveBackground,
    Color? tabTrackBackground,
    Color? tabHoverBackground,
    Color? tabBorder,
    Color? tabTextPrimary,
    Color? tabTextMuted,
    Color? tabTextSubtle,
  }) {
    return AppShellChromeColors(
      base: base ?? this.base,
      surface: surface ?? this.surface,
      rail: rail ?? this.rail,
      tabActiveBackground: tabActiveBackground ?? this.tabActiveBackground,
      tabTrackBackground: tabTrackBackground ?? this.tabTrackBackground,
      tabHoverBackground: tabHoverBackground ?? this.tabHoverBackground,
      tabBorder: tabBorder ?? this.tabBorder,
      tabTextPrimary: tabTextPrimary ?? this.tabTextPrimary,
      tabTextMuted: tabTextMuted ?? this.tabTextMuted,
      tabTextSubtle: tabTextSubtle ?? this.tabTextSubtle,
    );
  }

  AppShellChromeColors lerp(AppShellChromeColors other, double t) {
    return AppShellChromeColors(
      base: Color.lerp(base, other.base, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      rail: Color.lerp(rail, other.rail, t)!,
      tabActiveBackground: Color.lerp(
        tabActiveBackground,
        other.tabActiveBackground,
        t,
      )!,
      tabTrackBackground: Color.lerp(
        tabTrackBackground,
        other.tabTrackBackground,
        t,
      )!,
      tabHoverBackground: Color.lerp(
        tabHoverBackground,
        other.tabHoverBackground,
        t,
      )!,
      tabBorder: Color.lerp(tabBorder, other.tabBorder, t)!,
      tabTextPrimary: Color.lerp(tabTextPrimary, other.tabTextPrimary, t)!,
      tabTextMuted: Color.lerp(tabTextMuted, other.tabTextMuted, t)!,
      tabTextSubtle: Color.lerp(tabTextSubtle, other.tabTextSubtle, t)!,
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
    required this.shellChrome,
  });

  static const _lightShellChrome = AppShellChromeColors(
    base: Color(0xFFF5F5F7),
    surface: Color(0xFFF9FAFB),
    rail: Color(0xFFEDEEF2),
    tabActiveBackground: Color(0xFFFFFFFF),
    tabTrackBackground: Color(0xB3D9DBE1),
    tabHoverBackground: Color(0xFFE1E3E8),
    tabBorder: Color(0xFFA7A7AD),
    tabTextPrimary: Color(0xFF1D1D1F),
    tabTextMuted: Color(0xFF55565A),
    tabTextSubtle: Color(0xFF6E6E73),
  );

  static const _darkShellChrome = AppShellChromeColors(
    base: Color(0xFF151A1E),
    surface: Color(0xFF202528),
    rail: Color(0xFF171C20),
    tabActiveBackground: Color(0xFF4A5356),
    tabTrackBackground: Color(0xD12A2D2F),
    tabHoverBackground: Color(0xFF2F3032),
    tabBorder: Color(0xFF778286),
    tabTextPrimary: Color(0xFFF3F5F6),
    tabTextMuted: Color(0xFF8D9699),
    tabTextSubtle: Color(0xFF7F888B),
  );

  static const light = AppThemeTokens(
    canvas: Color(0xFFF5F5F7),
    chrome: Color(0xFFEDEEF2),
    chromeElevated: Color(0xFFF9FAFB),
    panel: Color(0xFFFFFFFF),
    panelElevated: Color(0xFFFDFDFE),
    overlay: Color(0xFFFFFFFF),
    terminalSurface: Color(0xFFF6F6F8),
    terminalFrame: Color(0xFFD1D1D6),
    border: Color(0xFFD1D1D6),
    borderStrong: Color(0xFFA7A7AD),
    textPrimary: Color(0xFF1D1D1F),
    textMuted: Color(0xFF55565A),
    textSubtle: Color(0xFF6B6B70),
    accent: Color(0xFF007AFF),
    focus: Color(0xFF007AFF),
    focusRing: Color(0xFF007AFF),
    selected: Color(0xFFD9ECFF),
    inactiveScrim: Color(0x66000000),
    danger: Color(0xFFD70015),
    warning: Color(0xFFB56B00),
    success: Color(0xFF248A3D),
    dangerContainer: Color(0xFFFFE5E8),
    warningContainer: Color(0xFFFFF2D8),
    successContainer: Color(0xFFE1F8E8),
    spacing: AppThemeSpacing(xs: 3, sm: 5, md: 7, lg: 10, xl: 14, xxl: 20),
    radius: AppThemeRadius(sm: 4, md: 6, lg: 8, xl: 10),
    controls: AppThemeControls(dense: 28, compact: 32, regular: 36),
    shellChrome: _lightShellChrome,
    elevation: AppThemeElevation(
      floating: [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 18,
          offset: Offset(0, 10),
        ),
      ],
      dialog: [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 32,
          offset: Offset(0, 18),
        ),
      ],
    ),
  );

  static const dark = AppThemeTokens(
    canvas: Color(0xFF1D1D1F),
    chrome: Color(0xFF252528),
    chromeElevated: Color(0xFF2C2C2E),
    panel: Color(0xFF2C2C2E),
    panelElevated: Color(0xFF343437),
    overlay: Color(0xFF3A3A3C),
    terminalSurface: Color(0xFF0B0C0F),
    terminalFrame: Color(0xFF3A3A3C),
    border: Color(0xFF3A3A3C),
    borderStrong: Color(0xFF636366),
    textPrimary: Color(0xFFF5F5F7),
    textMuted: Color(0xFFD1D1D6),
    textSubtle: Color(0xFF98989D),
    accent: Color(0xFF0A84FF),
    focus: Color(0xFF0A84FF),
    focusRing: Color(0xFF0A84FF),
    selected: Color(0xFF123A5F),
    inactiveScrim: Color(0x8A000000),
    danger: Color(0xFFFF453A),
    warning: Color(0xFFFF9F0A),
    success: Color(0xFF32D74B),
    dangerContainer: Color(0xFF4A171A),
    warningContainer: Color(0xFF3F2E08),
    successContainer: Color(0xFF10361A),
    spacing: AppThemeSpacing(xs: 3, sm: 5, md: 7, lg: 10, xl: 14, xxl: 20),
    radius: AppThemeRadius(sm: 4, md: 6, lg: 8, xl: 10),
    controls: AppThemeControls(dense: 28, compact: 32, regular: 36),
    shellChrome: _darkShellChrome,
    elevation: AppThemeElevation(
      floating: [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 20,
          offset: Offset(0, 12),
        ),
      ],
      dialog: [
        BoxShadow(
          color: Color(0x80000000),
          blurRadius: 36,
          offset: Offset(0, 20),
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
  final AppShellChromeColors shellChrome;

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
    AppShellChromeColors? shellChrome,
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
      shellChrome: shellChrome ?? this.shellChrome,
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
      shellChrome: shellChrome.lerp(other.shellChrome, t),
    );
  }
}

extension AppThemeBuildContext on BuildContext {
  AppThemeTokens get appTheme => AppThemeTokens.of(this);

  bool get usesTouchControlDensity =>
      Theme.of(this).materialTapTargetSize == MaterialTapTargetSize.padded;

  double get minimumInteractiveDimension =>
      usesTouchControlDensity ? 48 : appTheme.controls.dense;

  double adaptiveControlHeight(double compactHeight) =>
      usesTouchControlDensity && compactHeight < 48 ? 48 : compactHeight;
}
