import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

enum AppPanelTone { canvas, chrome, panel, overlay, terminal, warning }

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
      border: border ?? Border.all(color: theme.border),
      boxShadow: shadow ? theme.elevation.floating : const [],
    );

    return DecoratedBox(
      key: key,
      decoration: decoration,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }

  Color _backgroundFor(AppThemeTokens theme) {
    return switch (tone) {
      AppPanelTone.canvas => theme.canvas,
      AppPanelTone.chrome => theme.chrome,
      AppPanelTone.panel => theme.panel,
      AppPanelTone.overlay => theme.overlay,
      AppPanelTone.terminal => theme.terminalSurface,
      AppPanelTone.warning => theme.warning.withValues(alpha: 0.10),
    };
  }
}
