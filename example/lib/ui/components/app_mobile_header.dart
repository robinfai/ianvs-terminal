import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

/// Shared phone page chrome, matching the active terminal header.
class AppMobileHeader extends StatelessWidget {
  const AppMobileHeader({
    super.key,
    required this.title,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Material(
    color: context.appTheme.panel,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SizedBox(
        height:
            (MediaQuery.textScalerOf(context).scale(
                          Theme.of(context).textTheme.titleMedium?.fontSize ??
                              18,
                        ) *
                        (Theme.of(context).textTheme.titleMedium?.height ??
                            1.5) +
                    8 +
                    (subtitle == null
                        ? 0
                        : MediaQuery.textScalerOf(context).scale(
                                Theme.of(
                                      context,
                                    ).textTheme.labelSmall?.fontSize ??
                                    12,
                              ) *
                              (Theme.of(context).textTheme.labelSmall?.height ??
                                  1.5)))
                .clamp(44.0, double.infinity),
        child: NavigationToolbar(
          centerMiddle: true,
          middleSpacing: 8,
          leading: leading,
          trailing: actions.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: actions),
          middle:
              titleWidget ??
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.appTheme.textSubtle,
                      ),
                    ),
                ],
              ),
        ),
      ),
    ),
  );
}
