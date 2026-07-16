import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

enum AppPanelTone {
  canvas,
  chrome,
  elevated,
  panel,
  overlay,
  terminal,
  selected,
  warning,
  danger,
  success,
}

class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    this.tone = AppPanelTone.panel,
    this.padding,
    this.borderRadius,
    this.border,
    this.shadow = false,
    required this.child,
  });

  final AppPanelTone tone;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;
  final Border? border;
  final bool shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final decoration = BoxDecoration(
      color: _backgroundFor(theme),
      borderRadius: borderRadius ?? BorderRadius.circular(theme.radius.md),
      border: border ?? Border.all(color: _borderFor(theme)),
      boxShadow: shadow || tone == AppPanelTone.elevated
          ? theme.elevation.floating
          : const [],
    );

    return DecoratedBox(
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }

  Color _backgroundFor(AppThemeTokens theme) {
    return switch (tone) {
      AppPanelTone.canvas => theme.canvas,
      AppPanelTone.chrome => theme.chrome,
      AppPanelTone.elevated => theme.panelElevated,
      AppPanelTone.panel => theme.panel,
      AppPanelTone.overlay => theme.overlay,
      AppPanelTone.terminal => theme.terminalSurface,
      AppPanelTone.selected => theme.selected,
      AppPanelTone.warning => theme.warningContainer,
      AppPanelTone.danger => theme.dangerContainer,
      AppPanelTone.success => theme.successContainer,
    };
  }

  Color _borderFor(AppThemeTokens theme) {
    return switch (tone) {
      AppPanelTone.selected => theme.borderStrong,
      AppPanelTone.warning => theme.warning.withValues(alpha: 0.42),
      AppPanelTone.danger => theme.danger.withValues(alpha: 0.42),
      AppPanelTone.success => theme.success.withValues(alpha: 0.42),
      _ => theme.border,
    };
  }
}
