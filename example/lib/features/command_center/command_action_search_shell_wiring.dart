import 'command_action_search_controller.dart';
import 'command_action_search_index.dart';
import 'command_search_intents.dart';
import 'command_search_overlay_controller.dart';
import 'saved_command_repository.dart';

class CommandActionSearchShellWiring {
  const CommandActionSearchShellWiring({
    this.policy = const CommandSearchInsertExecutePolicy(),
  });

  final CommandSearchInsertExecutePolicy policy;

  CommandActionSearchController controllerFor({
    required Iterable<CommandActionSearchItem> actions,
    SavedCommandDocument savedCommands = const SavedCommandDocument(),
  }) {
    return CommandActionSearchController(
      index: CommandActionSearchIndex(
        actions: actions,
        savedCommands: savedCommands.entries,
      ),
    );
  }

  CommandSearchTerminalIntent terminalIntentFor(
    CommandActionSearchOutput output, {
    required bool readOnly,
  }) {
    switch (output.kind) {
      case CommandActionSearchOutputKind.insertSavedCommand:
        final command = output.command;
        return policy.resolve(
          CommandSearchOverlayOutput.insert(command ?? ''),
          readOnly: readOnly,
        );
      case CommandActionSearchOutputKind.openAction:
        return const CommandSearchTerminalIntent.none();
      case CommandActionSearchOutputKind.none:
        return const CommandSearchTerminalIntent.none(
          CommandSearchTerminalIntentReason.emptySelection,
        );
    }
  }
}
