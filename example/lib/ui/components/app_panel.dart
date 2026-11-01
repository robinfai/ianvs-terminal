import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';
import 'app_grouped_section.dart';

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
    this.clipBehavior = Clip.none,
    required this.child,
  });

  final AppPanelTone tone;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;
  final Border? border;
  final bool shadow;
  final Clip clipBehavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final decoration = BoxDecoration(
      color: context.usesAppleGroups && tone == AppPanelTone.panel
          ? context.groupedSurface
          : _backgroundFor(theme),
      borderRadius:
          borderRadius ??
          BorderRadius.circular(context.usesAppleGroups ? 16 : theme.radius.md),
      border:
          border ??
          (context.usesAppleGroups && tone == AppPanelTone.panel
              ? null
              : Border.all(color: _borderFor(theme))),
      boxShadow: shadow ? theme.elevation.floating : const [],
    );

    return DecoratedBox(
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        borderRadius:
            borderRadius ??
            BorderRadius.circular(
              context.usesAppleGroups ? 16 : theme.radius.md,
            ),
        clipBehavior: clipBehavior,
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
