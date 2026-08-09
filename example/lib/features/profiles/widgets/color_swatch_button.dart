import 'package:flutter/material.dart';

import '../../../ui/app_ui.dart';
import '../utils/hex_color_utils.dart';

class ColorSwatchButton extends StatelessWidget {
  static const double _size = 30;

  const ColorSwatchButton({
    super.key,
    required this.label,
    required this.value,
    required this.onPressed,
    this.enabled = true,
    this.tooltip,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;
  final bool enabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final targetSize = context.adaptiveControlHeight(_size);
    final parsedColor = _tryParseOptionalHexColor(value);
    final backgroundColor = parsedColor ?? theme.chrome;

    return Semantics(
      button: true,
      label: 'Pick $label color',
      enabled: enabled,
      child: Tooltip(
        message: tooltip ?? 'Pick $label color',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(theme.radius.md),
            child: SizedBox.square(
              dimension: targetSize,
              child: Center(
                child: Ink(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(theme.radius.md),
                    border: Border.all(
                      color: enabled ? theme.border : theme.textSubtle,
                    ),
                  ),
                  child: parsedColor == null
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                theme.radius.sm,
                              ),
                              border: Border.all(
                                color: enabled
                                    ? theme.textMuted.withValues(alpha: 0.7)
                                    : theme.textSubtle.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color? _tryParseOptionalHexColor(String rawValue) {
    try {
      return parseOptionalHexColor(rawValue);
    } on FormatException {
      return null;
    }
  }
}
