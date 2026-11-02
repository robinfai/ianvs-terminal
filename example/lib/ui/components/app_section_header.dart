import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';
import 'app_setting_help.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.compactDescription = false,
  });

  final String title;
  final String? description;
  final bool compactDescription;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (compactDescription && description != null)
              AppSettingHelp(message: description!, label: title),
          ],
        ),
        if (description != null && !compactDescription) ...[
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
