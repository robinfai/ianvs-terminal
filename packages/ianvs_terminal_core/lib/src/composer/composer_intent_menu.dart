import 'package:flutter/material.dart';

import 'composer_theme.dart';
import 'input_intent.dart';

/// Shared phone intent selector; opening it does not dismiss the editor's IME.
class ComposerIntentMenu extends StatelessWidget {
  const ComposerIntentMenu({
    required this.buttonKey,
    required this.choice,
    required this.command,
    required this.chinese,
    required this.onSelected,
    this.enabled = true,
    this.commandEnabled = true,
    this.commandLabel,
    super.key,
  });

  static const slotWidth = 108.0;
  final Key buttonKey;
  final InputIntentChoice choice;
  final bool command;
  final bool chinese;
  final ValueChanged<InputIntentChoice> onSelected;
  final bool enabled;
  final bool commandEnabled;
  final String? commandLabel;

  String _t(String en, String zh) => chinese ? zh : en;

  @override
  Widget build(BuildContext context) {
    final tokens = ComposerTheme.of(context);
    final label =
        '${choice == InputIntentChoice.automatic ? _t('Auto · ', '自动 · ') : ''}${command ? _t('Command', '命令') : 'AI'}';
    return MenuAnchor(
      consumeOutsideTap: true,
      // The layout anchor follows the button after keyboard and compact-row
      // changes. A popup route only samples that position during route layout.
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomStart,
        backgroundColor: WidgetStatePropertyAll(tokens.popover),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shadowColor: WidgetStatePropertyAll(tokens.shadow),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: tokens.border, width: tokens.borderWidth),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(176, 0)),
        maximumSize: const WidgetStatePropertyAll(Size(280, double.infinity)),
      ),
      menuChildren: [
        for (final item in InputIntentChoice.values)
          MenuItemButton(
            key: ValueKey('composer-intent-option-${item.name}'),
            onPressed: item == InputIntentChoice.command && !commandEnabled
                ? null
                : () => onSelected(item),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(176, 48)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
              textStyle: WidgetStatePropertyAll(
                tokens.metadataStyle.copyWith(fontSize: 14),
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? tokens.disabledForeground
                    : tokens.foreground,
              ),
            ),
            leadingIcon: SizedBox(
              width: 20,
              child: choice == item ? const Icon(Icons.check, size: 18) : null,
            ),
            child: Semantics(
              selected: choice == item,
              child: Text(switch (item) {
                InputIntentChoice.automatic => _t('Automatic', '自动识别'),
                InputIntentChoice.command =>
                  commandLabel ?? _t('Command', '命令'),
                InputIntentChoice.ai => _t('Ask AI', 'AI 提问'),
              }),
            ),
          ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: _t('Input intent', '输入意图'),
        child: InkWell(
          key: buttonKey,
          // Browsing the choices must not steal focus from the draft editor.
          canRequestFocus: false,
          onTap: !enabled
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          borderRadius: BorderRadius.circular(8),
          child: child,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.chip,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.metadataStyle.copyWith(
                      fontSize: 12,
                      height: 1.25,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 14, color: tokens.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
