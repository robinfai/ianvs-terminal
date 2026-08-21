import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

class AppFieldRow extends StatelessWidget {
  const AppFieldRow({
    super.key,
    required this.label,
    required this.control,
    this.hint,
    this.message,
  });

  final String label;
  final String? hint;
  final Widget control;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hint != null) ...[
          SizedBox(height: theme.spacing.xs),
          Text(
            hint!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
          ),
        ],
        SizedBox(height: theme.spacing.sm),
        control,
        if (message != null) ...[
          SizedBox(height: theme.spacing.xs),
          Text(
            message!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
          ),
        ],
      ],
    );
  }
}
