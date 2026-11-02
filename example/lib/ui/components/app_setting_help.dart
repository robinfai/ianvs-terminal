import 'package:flutter/material.dart';

/// Supplemental help without permanent prose in a configuration form.
class AppSettingHelp extends StatelessWidget {
  const AppSettingHelp({required this.message, required this.label, super.key});
  final String message;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tooltipKey = GlobalKey<TooltipState>();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Tooltip(
      key: tooltipKey,
      message: message,
      child: IconButton(
        icon: Icon(
          Icons.info_outline,
          size: 18,
          semanticLabel: zh ? '$label说明' : 'About $label',
        ),
        onPressed: () => tooltipKey.currentState?.ensureTooltipVisible(),
      ),
    );
  }
}
