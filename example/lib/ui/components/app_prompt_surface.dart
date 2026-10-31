import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

/// Presentation only: the caller retains its editor, focus and all actions.
class AppPromptSurface extends StatelessWidget {
  const AppPromptSurface({
    super.key,
    required this.editor,
    required this.actions,
    required this.maxWidth,
    this.header,
    this.contextStrip,
    this.footer,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget editor;
  final Widget actions;
  final double maxWidth;
  final Widget? header;
  final Widget? contextStrip;
  final Widget? footer;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: context.appTheme.panelElevated,
          borderRadius: BorderRadius.circular(context.appTheme.radius.md),
          border: Border.all(color: context.appTheme.borderStrong),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?header,
            ?contextStrip,
            KeyedSubtree(
              key: const ValueKey('hosted-prompt-editor'),
              child: editor,
            ),
            KeyedSubtree(
              key: const ValueKey('hosted-prompt-actions'),
              child: actions,
            ),
            ?footer,
          ],
        ),
      ),
    ),
  );
}
