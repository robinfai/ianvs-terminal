import '../command_center/command_action_search_controller.dart';
import '../command_center/command_action_search_index.dart';
import '../productivity/shell_productivity_models.dart';
import 'shell_action_registry.dart';
import 'shell_action_view_models.dart';

class ShellCommandActionSearchAdapter {
  const ShellCommandActionSearchAdapter();

  List<CommandActionSearchItem> itemsFor({
    required bool hasActiveSession,
    required ShellProductivityState productivity,
  }) {
    final items = <CommandActionSearchItem>[];
    for (final entry in ShellActionRegistry.actions.entries) {
      final descriptor = entry.value;
      if (!descriptor.commandPaletteVisible) {
        continue;
      }
      final viewModel = ShellActionViewModelBuilder.forDescriptor(
        descriptor: descriptor,
        hasActiveSession: hasActiveSession,
        productivity: productivity,
      );
      items.add(_itemFor(descriptor: descriptor, viewModel: viewModel));
    }
    return List<CommandActionSearchItem>.unmodifiable(items);
  }

  TerminalActionId? actionIdFor(CommandActionSearchOutput output) {
    if (output.kind != CommandActionSearchOutputKind.openAction) {
      return null;
    }
    final actionId = output.actionId;
    if (actionId == null) {
      return null;
    }
    for (final id in TerminalActionId.values) {
      if (id.name == actionId) {
        return id;
      }
    }
    return null;
  }

  CommandActionSearchItem _itemFor({
    required TerminalActionDescriptor descriptor,
    required ShellActionMenuItemViewModel viewModel,
  }) {
    final categoryLabel = _categoryLabel(descriptor.category);
    return CommandActionSearchItem.appAction(
      id: descriptor.id.name,
      title: _humanizeLabel(descriptor.label),
      subtitle: _subtitleFor(
        categoryLabel: categoryLabel,
        shortcutHint: viewModel.shortcutHint,
        disabledTitle: viewModel.enabled ? null : viewModel.disabledTitle,
      ),
      keywords: _keywordsFor(
        descriptor: descriptor,
        viewModel: viewModel,
        categoryLabel: categoryLabel,
      ),
    );
  }
}

String _subtitleFor({
  required String categoryLabel,
  required String? shortcutHint,
  required String? disabledTitle,
}) {
  return [
    categoryLabel,
    if (shortcutHint != null && shortcutHint.isNotEmpty) shortcutHint,
    if (disabledTitle != null && disabledTitle.isNotEmpty) disabledTitle,
  ].join(' • ');
}

List<String> _keywordsFor({
  required TerminalActionDescriptor descriptor,
  required ShellActionMenuItemViewModel viewModel,
  required String categoryLabel,
}) {
  final values = <String>[
    descriptor.label,
    descriptor.id.name,
    descriptor.category.name,
    categoryLabel,
    ..._actionSearchAliasesFor(descriptor.id),
    if (viewModel.shortcutHint case final shortcut? when shortcut.isNotEmpty)
      shortcut,
    if (viewModel.disabledTitle case final title? when title.isNotEmpty) title,
    if (viewModel.disabledDescription case final description?
        when description.isNotEmpty)
      description,
  ];
  final seen = <String>{};
  return [
    for (final value in values)
      if (seen.add(value)) value,
  ];
}

List<String> _actionSearchAliasesFor(TerminalActionId actionId) {
  return switch (actionId) {
    TerminalActionId.copy => const ['copy selection'],
    TerminalActionId.toggleCommandFinishedNotify => const [
      'command finished notifications',
      'command-finished notifications',
      'shell hook completion alerts',
    ],
    _ => const <String>[],
  };
}

String _categoryLabel(TerminalActionCategory category) {
  return '${_humanizeLabel(category.name)} action';
}

String _humanizeLabel(String value) {
  final words = value
      .trim()
      .split(RegExp(r'[_\-\s]+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return value;
  }
  return [
    _capitalize(words.first),
    for (final word in words.skip(1)) word.toLowerCase(),
  ].join(' ');
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
}
