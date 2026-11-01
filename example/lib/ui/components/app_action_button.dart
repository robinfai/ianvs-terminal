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
    this.loading = false,
    this.focusNode,
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
  final bool loading;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final touch = context.usesTouchControlDensity;
    final height = touch ? 48.0 : switch (size) {
      AppActionSize.dense => 28.0,
      AppActionSize.compact => 32.0,
      AppActionSize.regular => 36.0,
    };
    final metrics = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(height, height)),
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero : const Duration(milliseconds: 120),
    );
    final callback = loading ? null : onPressed;
    final spinner = SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2,
        value: MediaQuery.disableAnimationsOf(context) ? .75 : null,
        semanticsLabel: tooltip ?? label),
    );
    final iconSize = Theme.of(context).iconTheme.size ?? 20.0;
    if (label == null) {
      return IconButton(
        key: buttonKey,
        tooltip: tooltip,
        autofocus: autofocus,
        focusNode: focusNode,
        onPressed: callback,
        style: metrics.merge(tone == AppActionTone.danger
            ? IconButton.styleFrom(foregroundColor: colors.error)
            : null),
        icon: loading ? spinner : Icon(icon, size: iconSize),
      );
    }
    final content = icon == null && !loading
        ? Text(label!)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) spinner else Icon(icon, size: iconSize),
              SizedBox(width: context.appTheme.spacing.sm),
              Flexible(child: Text(label!)),
            ],
          );
    final button = switch (tone) {
      AppActionTone.primary || AppActionTone.danger => FilledButton(
        key: buttonKey,
        autofocus: autofocus,
        focusNode: focusNode,
        onPressed: callback,
        style: metrics.merge(tone == AppActionTone.danger
            ? FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              )
            : null),
        child: content,
      ),
      AppActionTone.secondary => OutlinedButton(
        key: buttonKey,
        autofocus: autofocus,
        focusNode: focusNode,
        onPressed: callback,
        style: metrics,
        child: content,
      ),
      AppActionTone.ghost => TextButton(
        key: buttonKey,
        autofocus: autofocus,
        focusNode: focusNode,
        onPressed: callback,
        style: metrics,
        child: content,
      ),
    };
    return Semantics(
      liveRegion: loading,
      child: tooltip == null ? button : Tooltip(message: tooltip, child: button),
    );
  }
}
