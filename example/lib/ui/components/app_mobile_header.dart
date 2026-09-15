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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            ?leading,
            Expanded(
              child:
                  titleWidget ??
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
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
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: context.appTheme.textSubtle),
                          ),
                      ],
                    ),
                  ),
            ),
            ...actions,
          ],
        ),
      ),
    ),
  );
}
