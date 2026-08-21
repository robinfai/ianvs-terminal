import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';
import 'app_panel.dart';

class AppToolbar extends StatelessWidget {
  const AppToolbar({
    super.key,
    this.tone = AppPanelTone.chrome,
    this.leading,
    this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.padding,
    this.height = 36,
  });

  final AppPanelTone tone;
  final Widget? leading;
  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final EdgeInsetsGeometry? padding;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return AppPanel(
      tone: tone,
      borderRadius: BorderRadius.zero,
      border: Border(bottom: BorderSide(color: theme.borderStrong)),
      padding: padding ?? EdgeInsets.symmetric(horizontal: theme.spacing.lg),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (leading case final Widget leadingWidget) leadingWidget,
            if (title != null || subtitle != null)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: theme.textSubtle,
                        ),
                      ),
                  ],
                ),
              )
            else
              const Spacer(),
            ...actions,
          ],
        ),
      ),
    );
  }
}
