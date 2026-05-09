import 'package:flutter/material.dart';

import '../../../ui/app_ui.dart';

class ToggleSettingRow extends StatelessWidget {
  const ToggleSettingRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return MergeSemantics(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          borderRadius: BorderRadius.circular(theme.radius.md),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: theme.controls.compact),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: theme.spacing.xs + 1),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: enabled
                                    ? theme.textPrimary
                                    : theme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (description != null) ...[
                          SizedBox(height: theme.spacing.xs),
                          Text(
                            description!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: theme.textSubtle),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: theme.spacing.md),
                  SizedBox(
                    width: 44,
                    height: 28,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Switch(
                        value: value,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        onChanged: enabled ? onChanged : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
