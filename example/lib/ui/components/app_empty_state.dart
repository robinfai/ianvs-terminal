import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.supportingText,
    this.action,
  });

  final String title;
  final String message;
  final String? supportingText;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: theme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: theme.spacing.sm),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: theme.textMuted,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          if (supportingText != null) ...[
            SizedBox(height: theme.spacing.lg),
            Text(
              supportingText!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: theme.textSubtle,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[SizedBox(height: theme.spacing.lg), action!],
        ],
      ),
    );
  }
}
