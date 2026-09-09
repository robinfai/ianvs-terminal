import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

/// Keeps configuration labels aligned while allowing compact and enlarged-text
/// layouts to use the full width for their controls.
class AppConfigurationField extends StatelessWidget {
  const AppConfigurationField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.labelWidth = 120,
  });

  final String label;
  final Widget child;
  final String? helper;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final textTheme = Theme.of(context).textTheme;
    final labelWidget = Text(label, style: textTheme.bodyMedium);
    final control = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(label: label, child: child),
        if (helper != null) ...[
          SizedBox(height: theme.spacing.xs),
          Text(
            helper!,
            style: textTheme.bodySmall?.copyWith(color: theme.textSubtle),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 520 || scale > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(child: labelWidget),
              SizedBox(height: theme.spacing.sm),
              control,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ExcludeSemantics(child: labelWidget),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: control),
          ],
        );
      },
    );
  }
}
