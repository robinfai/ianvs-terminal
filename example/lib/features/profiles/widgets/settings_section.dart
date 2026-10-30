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
      child: AppSectionHeader(title: title, description: description),
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
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: theme.spacing.sm),
              child: content,
            )
          : content,
    );
  }
}
