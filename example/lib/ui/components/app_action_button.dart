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
    this.autofocus = false,
  }) : assert(
         icon != null || label != null,
         'AppActionButton requires an icon, a label, or both.',
       );

  final Key? buttonKey;
  final AppActionTone tone;
  final AppActionSize size;
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconSize = Theme.of(context).iconTheme.size ?? 20.0;
    if (label == null) {
      return IconButton(
        key: buttonKey ?? key,
        tooltip: tooltip,
        autofocus: autofocus,
        onPressed: onPressed,
        style: tone == AppActionTone.danger
            ? IconButton.styleFrom(foregroundColor: colors.error)
            : null,
        icon: Icon(icon, size: iconSize),
      );
    }
    final content = icon == null
        ? Text(label!)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize),
              SizedBox(width: context.appTheme.spacing.sm),
              Flexible(child: Text(label!)),
            ],
          );
    final button = switch (tone) {
      AppActionTone.primary || AppActionTone.danger => FilledButton(
        key: buttonKey ?? key,
        autofocus: autofocus,
        onPressed: onPressed,
        style: tone == AppActionTone.danger
            ? FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              )
            : null,
        child: content,
      ),
      AppActionTone.secondary => OutlinedButton(
        key: buttonKey ?? key,
        autofocus: autofocus,
        onPressed: onPressed,
        child: content,
      ),
      AppActionTone.ghost => TextButton(
        key: buttonKey ?? key,
        autofocus: autofocus,
        onPressed: onPressed,
        child: content,
      ),
    };
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
