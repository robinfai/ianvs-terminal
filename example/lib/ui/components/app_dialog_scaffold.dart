import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final closeButtonSize = theme.controls.dense;
    final header = Padding(
      padding:
          headerPadding ??
          EdgeInsets.fromLTRB(
            theme.spacing.xl,
            theme.spacing.xl - 2,
            theme.spacing.xl,
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: theme.spacing.xs),
                  Text(
                    subtitle!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: theme.textSubtle),
                  ),
                ],
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: closeTooltip,
              onPressed: onClose,
              padding: EdgeInsets.zero,
              splashRadius: closeButtonSize / 2,
              constraints: BoxConstraints.tightFor(
                width: closeButtonSize,
                height: closeButtonSize,
              ),
              icon: Icon(Icons.close_rounded, color: theme.textMuted),
            ),
        ],
      ),
    );

    final paddedBody = Padding(
      padding:
          bodyPadding ??
          EdgeInsets.fromLTRB(
            theme.spacing.xl,
            theme.spacing.lg,
            theme.spacing.xl,
            theme.spacing.lg,
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
                  theme.spacing.lg,
                ),
            child: footer!,
          );

    Widget contents = Column(
      mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
      children: [
        header,
        Divider(height: 1, color: theme.border),
        if (expandBody) Expanded(child: paddedBody) else paddedBody,
        if (paddedFooter != null) ...[
          Divider(height: 1, color: theme.border),
          paddedFooter,
        ],
      ],
    );

    if (width != null || height != null) {
      contents = SizedBox(width: width, height: height, child: contents);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          insetPadding ??
          EdgeInsets.symmetric(
            horizontal: theme.spacing.xxl,
            vertical: theme.spacing.xxl,
          ),
      child: ConstrainedBox(
        constraints: constraints ?? const BoxConstraints(maxWidth: 720),
        child: AppPanel(
          tone: AppPanelTone.panel,
          shadow: true,
          borderRadius: BorderRadius.circular(theme.radius.xl),
          child: contents,
        ),
      ),
    );
  }
}
