import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

enum AppActionTone { primary, secondary, ghost, danger }

enum AppActionSize { dense, compact, regular }

class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    this.buttonKey,
    this.tone = AppActionTone.primary,
    this.size = AppActionSize.regular,
    this.icon,
    this.label,
    this.tooltip,
    this.onPressed,
  }) : assert(icon != null || label != null);

  final Key? buttonKey;
  final AppActionTone tone;
  final AppActionSize size;
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    if (label == null && icon != null) {
      return IconButton(
        key: buttonKey ?? key,
        tooltip: tooltip,
        onPressed: onPressed,
        style: _iconButtonStyle(theme),
        icon: Icon(icon, size: _iconSize),
      );
    }

    final iconWidget = icon == null ? null : Icon(icon, size: _iconSize);

    return switch (tone) {
      AppActionTone.primary =>
        label == null
            ? FilledButton(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(theme),
                child: iconWidget!,
              )
            : FilledButton.icon(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(theme),
                icon: iconWidget ?? const SizedBox.shrink(),
                label: Text(label!),
              ),
      AppActionTone.secondary =>
        label == null
            ? OutlinedButton(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(theme),
                child: iconWidget!,
              )
            : OutlinedButton.icon(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(theme),
                icon: iconWidget ?? const SizedBox.shrink(),
                label: Text(label!),
              ),
      AppActionTone.ghost =>
        label == null
            ? TextButton(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(theme),
                child: iconWidget!,
              )
            : TextButton.icon(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(theme),
                icon: iconWidget ?? const SizedBox.shrink(),
                label: Text(label!),
              ),
      AppActionTone.danger =>
        label == null
            ? FilledButton(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(
                  theme,
                  backgroundColor: theme.danger,
                  foregroundColor: Colors.white,
                ),
                child: iconWidget!,
              )
            : FilledButton.icon(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(
                  theme,
                  backgroundColor: theme.danger,
                  foregroundColor: Colors.white,
                ),
                icon: iconWidget ?? const SizedBox.shrink(),
                label: Text(label!),
              ),
    };
  }

  double get _iconSize => switch (size) {
    AppActionSize.dense => 16,
    AppActionSize.compact => 16,
    AppActionSize.regular => 18,
  };

  double _height(AppThemeTokens theme) => switch (size) {
    AppActionSize.dense => theme.controls.dense,
    AppActionSize.compact => theme.controls.compact,
    AppActionSize.regular => theme.controls.regular,
  };

  ButtonStyle _buttonStyle(
    AppThemeTokens theme, {
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final height = _height(theme);
    return ButtonStyle(
      backgroundColor: backgroundColor == null
          ? null
          : WidgetStatePropertyAll(backgroundColor),
      foregroundColor: foregroundColor == null
          ? null
          : WidgetStatePropertyAll(foregroundColor),
      minimumSize: WidgetStatePropertyAll(Size(0, height)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: switch (size) {
            AppActionSize.dense => theme.spacing.sm + 1,
            AppActionSize.compact => theme.spacing.md,
            AppActionSize.regular => theme.spacing.lg,
          },
          vertical: switch (size) {
            AppActionSize.dense => theme.spacing.xs + 1,
            AppActionSize.compact => theme.spacing.sm,
            AppActionSize.regular => theme.spacing.sm + 1,
          },
        ),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  ButtonStyle _iconButtonStyle(AppThemeTokens theme) {
    final buttonSize = _height(theme);
    return IconButton.styleFrom(
      foregroundColor: tone == AppActionTone.danger
          ? theme.danger
          : theme.textMuted,
      minimumSize: Size.square(buttonSize),
      padding: EdgeInsets.all(switch (size) {
        AppActionSize.dense => theme.spacing.sm - 1,
        AppActionSize.compact => theme.spacing.sm,
        AppActionSize.regular => theme.spacing.md,
      }),
      side: tone == AppActionTone.secondary
          ? BorderSide(color: theme.border)
          : null,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
