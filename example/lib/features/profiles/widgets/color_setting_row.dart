import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/app_ui.dart';
import 'color_swatch_button.dart';

class ColorSettingRow extends StatelessWidget {
  const ColorSettingRow({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBlurNormalize,
    required this.onPick,
    required this.onReset,
    this.errorText,
    this.enabled = true,
    this.inputKey,
    this.pickKey,
    this.resetKey,
    this.swatchKey,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final VoidCallback onBlurNormalize;
  final VoidCallback onPick;
  final VoidCallback onReset;
  final bool enabled;
  final Key? inputKey;
  final Key? pickKey;
  final Key? resetKey;
  final Key? swatchKey;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: theme.textPrimary,
      fontWeight: FontWeight.w700,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final inlineLabel = constraints.maxWidth >= 620;
        final stackedActions = constraints.maxWidth < 460;
        final field = _buildField(context);
        final swatch = ColorSwatchButton(
          key: swatchKey,
          label: label,
          value: controller.text,
          onPressed: onPick,
          enabled: enabled,
        );
        final pickButton = AppActionButton(
          buttonKey: pickKey,
          tone: AppActionTone.secondary,
          size: AppActionSize.compact,
          label: 'Pick',
          tooltip: 'Pick $label color',
          onPressed: enabled ? onPick : null,
        );
        final resetButton = AppActionButton(
          buttonKey: resetKey,
          tone: AppActionTone.secondary,
          size: AppActionSize.compact,
          label: 'Reset',
          tooltip: 'Reset $label color',
          onPressed: enabled ? onReset : null,
        );

        if (inlineLabel) {
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: theme.controls.regular),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: Padding(
                    padding: EdgeInsets.only(top: theme.spacing.sm + 2),
                    child: Text(label, style: labelStyle),
                  ),
                ),
                SizedBox(width: theme.spacing.md),
                Expanded(child: field),
                SizedBox(width: theme.spacing.sm),
                Padding(
                  padding: EdgeInsets.only(top: theme.spacing.xs),
                  child: swatch,
                ),
                SizedBox(width: theme.spacing.sm),
                Padding(
                  padding: EdgeInsets.only(top: theme.spacing.xs),
                  child: pickButton,
                ),
                SizedBox(width: theme.spacing.sm),
                Padding(
                  padding: EdgeInsets.only(top: theme.spacing.xs),
                  child: resetButton,
                ),
              ],
            ),
          );
        }

        if (stackedActions) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle),
              SizedBox(height: theme.spacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: field),
                  SizedBox(width: theme.spacing.sm),
                  Padding(
                    padding: EdgeInsets.only(top: theme.spacing.sm),
                    child: swatch,
                  ),
                ],
              ),
              SizedBox(height: theme.spacing.sm),
              Row(
                children: [
                  pickButton,
                  SizedBox(width: theme.spacing.sm),
                  resetButton,
                ],
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle),
            SizedBox(height: theme.spacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: field),
                SizedBox(width: theme.spacing.sm),
                swatch,
                SizedBox(width: theme.spacing.sm),
                pickButton,
                SizedBox(width: theme.spacing.sm),
                resetButton,
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildField(BuildContext context) {
    final theme = context.appTheme;
    final inputTheme = Theme.of(context).inputDecorationTheme;
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) {
          onBlurNormalize();
        }
      },
      child: TextFormField(
        key: inputKey,
        controller: controller,
        enabled: enabled,
        focusNode: focusNode,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
        ],
        decoration: const InputDecoration()
            .applyDefaults(inputTheme)
            .copyWith(
              hintText: '#RRGGBB or empty',
              errorText: errorText,
              labelText: null,
              helperText: null,
              filled: true,
              fillColor: theme.chrome,
              contentPadding: EdgeInsets.symmetric(
                horizontal: theme.spacing.md,
                vertical: theme.spacing.md,
              ),
            ),
        onChanged: onChanged,
        onEditingComplete: onBlurNormalize,
        onTapOutside: (_) => focusNode.unfocus(),
      ),
    );
  }
}
