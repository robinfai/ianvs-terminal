import 'package:flutter/material.dart';

import '../../../ui/app_ui.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: theme.spacing.xl),
      child: AppPanel(
        tone: AppPanelTone.panel,
        padding: EdgeInsets.all(theme.spacing.lg),
        borderRadius: BorderRadius.circular(theme.radius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w800,
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
            SizedBox(height: theme.spacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}
