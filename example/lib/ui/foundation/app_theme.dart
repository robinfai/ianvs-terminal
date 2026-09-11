import 'package:ianvs_design/ianvs_design.dart';

import 'app_theme_tokens.dart';

/// Shared Ianvs components and typography, plus Trail's terminal surfaces.
ThemeData buildIanvsTerminalTheme(
  Brightness brightness, {
  TargetPlatform? platform,
}) {
  final resolvedPlatform = platform ?? TargetPlatform.macOS;
  final touch = switch (resolvedPlatform) {
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS => true,
    _ => false,
  };
  final shared = IanvsTheme.build(
    brightness: brightness,
    platform: resolvedPlatform,
    density: touch ? IanvsDensity.touch : IanvsDensity.compact,
    touchVisualDensity: resolvedPlatform == TargetPlatform.iOS
        ? IanvsTouchVisualDensity.compact
        : IanvsTouchVisualDensity.standard,
  );
  final design = shared.extension<IanvsTokens>()!;
  // The legacy names are an adapter for terminal/business surfaces. General
  // colors, spacing and control metrics all come from the shared design system.
  final terminal = AppThemeTokens.fallbackFor(brightness).copyWith(
    canvas: design.canvas,
    chrome: design.chrome,
    chromeElevated: design.raised,
    panel: design.field,
    panelElevated: design.raised,
    overlay: design.raised,
    border: design.separator,
    borderStrong: design.border,
    textPrimary: design.text,
    textMuted: design.muted,
    textSubtle: design.subtle,
    accent: design.accent,
    focus: design.focus,
    focusRing: design.focus,
    selected: design.selected,
    danger: design.danger,
    warning: design.warning,
    success: design.success,
    dangerContainer: shared.colorScheme.errorContainer,
    warningContainer: Color.alphaBlend(
      design.warning.withValues(alpha: .12),
      design.field,
    ),
    successContainer: Color.alphaBlend(
      design.success.withValues(alpha: .12),
      design.field,
    ),
    spacing: const AppThemeSpacing(
      xs: IanvsSpacing.xs,
      sm: IanvsSpacing.sm,
      md: IanvsSpacing.md,
      lg: IanvsSpacing.lg,
      xl: IanvsSpacing.xl,
      xxl: IanvsSpacing.xxl,
    ),
    radius: AppThemeRadius(
      sm: design.controlRadius,
      md: design.controlRadius,
      lg: design.panelRadius,
      xl: design.panelRadius,
    ),
    controls: AppThemeControls(
      dense: design.controlHeight,
      compact: design.controlHeight,
      regular: design.controlHeight,
    ),
  );
  return shared.copyWith(extensions: [...shared.extensions.values, terminal]);
}
