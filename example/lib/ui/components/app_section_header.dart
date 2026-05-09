import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (description != null) ...[
          SizedBox(height: theme.spacing.xs),
          Text(
            description!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
          ),
        ],
      ],
    );
  }
}
