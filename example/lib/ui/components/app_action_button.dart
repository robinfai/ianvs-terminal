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
        style: _iconButtonStyle(context, theme),
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
                style: _buttonStyle(context, theme),
                child: iconWidget!,
              )
            : FilledButton.icon(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(context, theme),
                icon: iconWidget ?? const SizedBox.shrink(),
                label: Text(label!),
              ),
      AppActionTone.secondary =>
        label == null
            ? OutlinedButton(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(context, theme),
                child: iconWidget!,
              )
            : OutlinedButton.icon(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(context, theme),
                icon: iconWidget ?? const SizedBox.shrink(),
                label: Text(label!),
              ),
      AppActionTone.ghost =>
        label == null
            ? TextButton(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(context, theme),
                child: iconWidget!,
              )
            : TextButton.icon(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(context, theme),
                icon: iconWidget ?? const SizedBox.shrink(),
                label: Text(label!),
              ),
      AppActionTone.danger =>
        label == null
            ? FilledButton(
                key: buttonKey ?? key,
                onPressed: onPressed,
                style: _buttonStyle(
                  context,
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
                  context,
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
    BuildContext context,
    AppThemeTokens theme, {
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final height = _height(theme);
    final isOutlinedTone = tone == AppActionTone.secondary;
    final isGhostTone = tone == AppActionTone.ghost;
    final baseBackground = backgroundColor;
    final baseForeground =
        foregroundColor ??
        switch (tone) {
          AppActionTone.danger => theme.danger,
          AppActionTone.primary => Colors.white,
          _ => theme.textPrimary,
        };
    final baseStyle = switch (tone) {
      AppActionTone.primary || AppActionTone.danger =>
        FilledButtonTheme.of(context).style,
      AppActionTone.secondary => OutlinedButtonTheme.of(context).style,
      AppActionTone.ghost => TextButtonTheme.of(context).style,
    };

    return baseStyle?.merge(
          ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return theme.chrome.withValues(alpha: 0.50);
              }
              if (baseBackground != null) {
                return states.contains(WidgetState.pressed)
                    ? Color.alphaBlend(
                        Colors.black.withValues(alpha: 0.14),
                        baseBackground,
                      )
                    : baseBackground;
              }
              if (states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.hovered)) {
                return theme.selected.withValues(
                  alpha: isGhostTone ? 0.34 : 0.46,
                );
              }
              return null;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return theme.textSubtle;
              }
              return baseForeground;
            }),
            overlayColor: WidgetStatePropertyAll(
              theme.focusRing.withValues(alpha: 0.12),
            ),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(color: theme.focusRing, width: 1.5);
              }
              if (isOutlinedTone) {
                return BorderSide(color: theme.borderStrong);
              }
              return BorderSide.none;
            }),
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
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ) ??
        ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return theme.chrome.withValues(alpha: 0.50);
        }
        if (baseBackground != null) {
          return states.contains(WidgetState.pressed)
              ? Color.alphaBlend(
                  Colors.black.withValues(alpha: 0.14),
                  baseBackground,
                )
              : baseBackground;
        }
        if (states.contains(WidgetState.focused) ||
            states.contains(WidgetState.hovered)) {
          return theme.selected.withValues(alpha: isGhostTone ? 0.34 : 0.46);
        }
        return null;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return theme.textSubtle;
        }
        return baseForeground;
      }),
      overlayColor: WidgetStatePropertyAll(
        theme.focusRing.withValues(alpha: 0.12),
      ),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: theme.focusRing, width: 1.5);
        }
        if (isOutlinedTone) {
          return BorderSide(color: theme.borderStrong);
        }
        return BorderSide.none;
      }),
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
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  ButtonStyle _iconButtonStyle(BuildContext context, AppThemeTokens theme) {
    final buttonSize = _height(theme);
    return IconButtonTheme.of(context).style?.merge(
          IconButton.styleFrom(
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
                ? BorderSide(color: theme.borderStrong)
                : null,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ) ??
        IconButton.styleFrom(
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
              ? BorderSide(color: theme.borderStrong)
              : null,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
  }
}
