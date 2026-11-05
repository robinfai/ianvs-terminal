import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

/// Presentation only: the caller retains its editor, focus and all actions.
class AppPromptSurface extends StatefulWidget {
  const AppPromptSurface({
    super.key,
    required this.editor,
    required this.actions,
    required this.maxWidth,
    this.header,
    this.contextStrip,
    this.footer,
    this.padding = const EdgeInsets.all(12),
    this.quiet = false,
    this.focused = false,
  });

  final Widget editor;
  final Widget actions;
  final double maxWidth;
  final Widget? header;
  final Widget? contextStrip;
  final Widget? footer;
  final EdgeInsetsGeometry padding;
  final bool quiet;
  final bool focused;

  @override
  State<AppPromptSurface> createState() => _AppPromptSurfaceState();
}

class _AppPromptSurfaceState extends State<AppPromptSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Align(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: context.appTheme.panelElevated,
            borderRadius: BorderRadius.circular(
              widget.quiet
                  ? context.appTheme.radius.xl
                  : context.appTheme.radius.md,
            ),
            border: Border.all(
              color: MediaQuery.highContrastOf(context)
                  ? context.appTheme.borderStrong
                  : widget.quiet
                  ? widget.focused || _hovered
                        ? context.appTheme.border
                        : Color.lerp(
                            context.appTheme.border,
                            context.appTheme.panelElevated,
                            .35,
                          )!
                  : context.appTheme.borderStrong,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?widget.header,
              ?widget.contextStrip,
              KeyedSubtree(
                key: const ValueKey('hosted-prompt-editor'),
                child: widget.editor,
              ),
              KeyedSubtree(
                key: const ValueKey('hosted-prompt-actions'),
                child: widget.actions,
              ),
              ?widget.footer,
            ],
          ),
        ),
      ),
    ),
  );
}
