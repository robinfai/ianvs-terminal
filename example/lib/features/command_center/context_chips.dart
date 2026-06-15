import 'package:flutter/material.dart';

import 'context_chip_models.dart';

class ContextChips extends StatelessWidget {
  const ContextChips({required this.chips, this.onIntent, super.key});

  final List<ContextChipModel> chips;
  final ValueChanged<ContextChipClickIntent>? onIntent;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final chip in chips)
          _ContextChip(
            key: Key('context-chip-${chip.kind.name}'),
            chip: chip,
            onIntent: onIntent,
          ),
      ],
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.chip, required this.onIntent, super.key});

  final ContextChipModel chip;
  final ValueChanged<ContextChipClickIntent>? onIntent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = _chipColors(colorScheme, chip.tone);
    final canPress =
        chip.enabled &&
        chip.intent.kind != ContextChipIntentKind.none &&
        onIntent != null;

    return ActionChip(
      tooltip: chip.semanticLabel,
      avatar: Icon(_iconFor(chip.kind), size: 18, color: colors.foreground),
      label: Text(
        '${chip.label} ${chip.value}',
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: canPress ? () => onIntent?.call(chip.intent) : null,
      backgroundColor: colors.background,
      side: BorderSide(color: colors.outline),
      visualDensity: VisualDensity.compact,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: colors.foreground),
    );
  }
}

IconData _iconFor(ContextChipKind kind) {
  return switch (kind) {
    ContextChipKind.cwd => Icons.folder_open,
    ContextChipKind.profile => Icons.person_outline,
    ContextChipKind.shellHook => Icons.cable,
    ContextChipKind.lastExit => Icons.error_outline,
    ContextChipKind.selectedBlock => Icons.segment,
    ContextChipKind.readOnly => Icons.lock,
  };
}

_ChipColors _chipColors(ColorScheme colorScheme, ContextChipTone tone) {
  return switch (tone) {
    ContextChipTone.normal => _ChipColors(
      background: colorScheme.surfaceContainerHigh,
      foreground: colorScheme.onSurface,
      outline: colorScheme.outlineVariant,
    ),
    ContextChipTone.success => _ChipColors(
      background: colorScheme.tertiaryContainer,
      foreground: colorScheme.onTertiaryContainer,
      outline: colorScheme.outlineVariant,
    ),
    ContextChipTone.warning => _ChipColors(
      background: colorScheme.secondaryContainer,
      foreground: colorScheme.onSecondaryContainer,
      outline: colorScheme.outlineVariant,
    ),
    ContextChipTone.danger => _ChipColors(
      background: colorScheme.errorContainer,
      foreground: colorScheme.onErrorContainer,
      outline: colorScheme.outlineVariant,
    ),
    ContextChipTone.disabled => _ChipColors(
      background: colorScheme.surfaceContainerHighest,
      foreground: colorScheme.onSurfaceVariant,
      outline: colorScheme.outlineVariant,
    ),
  };
}

class _ChipColors {
  const _ChipColors({
    required this.background,
    required this.foreground,
    required this.outline,
  });

  final Color background;
  final Color foreground;
  final Color outline;
}
