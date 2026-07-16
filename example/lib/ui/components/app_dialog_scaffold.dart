import 'package:flutter/material.dart';

import 'app_action_button.dart';
import '../foundation/app_theme_tokens.dart';
import 'app_panel.dart';

class AppDialogScaffold extends StatelessWidget {
  const AppDialogScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.footer,
    this.onClose,
    this.closeTooltip = 'Close dialog',
    this.insetPadding,
    this.constraints,
    this.width,
    this.height,
    this.expandBody = false,
    this.headerPadding,
    this.bodyPadding,
    this.footerPadding,
    this.titleTextStyle,
    this.subtitleTextStyle,
    this.centerInViewport = true,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? footer;
  final VoidCallback? onClose;
  final String closeTooltip;
  final EdgeInsets? insetPadding;
  final BoxConstraints? constraints;
  final double? width;
  final double? height;
  final bool expandBody;
  final EdgeInsetsGeometry? headerPadding;
  final EdgeInsetsGeometry? bodyPadding;
  final EdgeInsetsGeometry? footerPadding;
  final TextStyle? titleTextStyle;
  final TextStyle? subtitleTextStyle;
  final bool centerInViewport;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final header = Padding(
      padding:
          headerPadding ??
          EdgeInsets.fromLTRB(
            theme.spacing.lg,
            theme.spacing.md,
            theme.spacing.lg,
            theme.spacing.sm,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      titleTextStyle ??
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: theme.spacing.xs),
                  Text(
                    subtitle!,
                    style:
                        subtitleTextStyle ??
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: theme.textSubtle,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (onClose != null)
            AppActionButton(
              tooltip: closeTooltip,
              tone: AppActionTone.ghost,
              size: AppActionSize.dense,
              onPressed: onClose,
              icon: Icons.close_rounded,
            ),
        ],
      ),
    );

    final paddedBody = Padding(
      padding:
          bodyPadding ??
          EdgeInsets.fromLTRB(
            theme.spacing.xl,
            theme.spacing.md,
            theme.spacing.xl,
            theme.spacing.md,
          ),
      child: body,
    );

    final paddedFooter = footer == null
        ? null
        : Padding(
            padding:
                footerPadding ??
                EdgeInsets.fromLTRB(
                  theme.spacing.xl,
                  theme.spacing.md,
                  theme.spacing.xl,
                  theme.spacing.md,
                ),
            child: footer!,
          );

    Widget contents = Column(
      mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
      children: [
        header,
        const Divider(height: 1),
        if (expandBody) Expanded(child: paddedBody) else paddedBody,
        if (paddedFooter != null) ...[const Divider(height: 1), paddedFooter],
      ],
    );

    if (width != null || height != null) {
      contents = SizedBox(width: width, height: height, child: contents);
    }

    final panel = Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: constraints ?? const BoxConstraints(maxWidth: 720),
        child: AppPanel(
          tone: AppPanelTone.elevated,
          shadow: true,
          borderRadius: BorderRadius.circular(theme.radius.xl),
          child: contents,
        ),
      ),
    );

    final paddedPanel = Padding(
      padding:
          insetPadding ??
          EdgeInsets.symmetric(
            horizontal: theme.spacing.xxl,
            vertical: theme.spacing.xxl,
          ),
      child: panel,
    );

    if (!centerInViewport) {
      return paddedPanel;
    }

    return FocusTraversalGroup(child: Center(child: paddedPanel));
  }
}
