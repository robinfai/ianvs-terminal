import 'package:flutter/material.dart';

import '../../../ui/app_ui.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.anchorKey,
    required this.title,
    this.description,
    this.contained = false,
    required this.children,
  });

  final Key? anchorKey;
  final String title;
  final String? description;
  final bool contained;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final header = KeyedSubtree(
      key: anchorKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
              ).textTheme.bodyMedium?.copyWith(color: theme.textSubtle),
            ),
          ],
        ],
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(height: contained ? theme.spacing.xl : theme.spacing.lg),
        ...children,
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: theme.spacing.xl),
      child: contained
          ? AppPanel(
              tone: AppPanelTone.elevated,
              padding: EdgeInsets.all(theme.spacing.xxl),
              borderRadius: BorderRadius.circular(theme.radius.xl),
              border: Border.all(color: theme.border),
              child: content,
            )
          : content,
    );
  }
}
