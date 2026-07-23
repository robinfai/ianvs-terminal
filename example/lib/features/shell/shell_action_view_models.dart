import '../productivity/shell_productivity_models.dart';
import 'shell_action_availability.dart';
import 'shell_action_registry.dart';

class ShellActionMenuItemViewModel {
  const ShellActionMenuItemViewModel({
    required this.actionId,
    required this.label,
    required this.enabled,
    this.disabledTitle,
    this.disabledDescription,
    this.shortcutHint,
  });

  final TerminalActionId actionId;
  final String label;
  final bool enabled;
  final String? disabledTitle;
  final String? disabledDescription;
  final String? shortcutHint;
}

class ShellActionViewModelBuilder {
  const ShellActionViewModelBuilder._();

  static List<ShellActionMenuItemViewModel> commandPaletteItems({
    required bool hasActiveSession,
    required ShellProductivityState productivity,
  }) {
    return ShellActionRegistry.actions.values
        .where(
          (descriptor) =>
              descriptor.hasUserEntryPoint && descriptor.commandPaletteVisible,
        )
        .map(
          (descriptor) => forDescriptor(
            descriptor: descriptor,
            hasActiveSession: hasActiveSession,
            productivity: productivity,
          ),
        )
        .toList(growable: false);
  }

  static ShellActionMenuItemViewModel forDescriptor({
    required TerminalActionDescriptor descriptor,
    required bool hasActiveSession,
    required ShellProductivityState productivity,
  }) {
    final availability = ShellActionAvailabilityResolver.resolve(
      actionId: descriptor.id,
      hasActiveSession: hasActiveSession,
      productivity: productivity,
    );
    final reason = availability.reason;

    return ShellActionMenuItemViewModel(
      actionId: descriptor.id,
      label: descriptor.label,
      enabled: availability.enabled,
      disabledTitle: reason?.title,
      disabledDescription: reason?.description,
      shortcutHint: descriptor.shortcutHint,
    );
  }
}
