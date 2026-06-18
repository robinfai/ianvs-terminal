import 'command_search_overlay_controller.dart';

enum CommandSearchTerminalIntentKind {
  none,
  insertText,
  executeText,
  requiresPastePolicy,
  disabled,
}

enum CommandSearchTerminalIntentReason {
  readOnly,
  emptySelection,
  multilineRequiresPastePolicy,
}

class CommandSearchTerminalIntent {
  const CommandSearchTerminalIntent._({
    required this.kind,
    this.text,
    this.reason,
  });

  const CommandSearchTerminalIntent.none([
    CommandSearchTerminalIntentReason? reason,
  ]) : this._(kind: CommandSearchTerminalIntentKind.none, reason: reason);

  const CommandSearchTerminalIntent.insertText(String text)
    : this._(kind: CommandSearchTerminalIntentKind.insertText, text: text);

  const CommandSearchTerminalIntent.executeText(String text)
    : this._(kind: CommandSearchTerminalIntentKind.executeText, text: text);

  const CommandSearchTerminalIntent.requiresPastePolicy({
    required String text,
    required CommandSearchTerminalIntentReason reason,
  }) : this._(
         kind: CommandSearchTerminalIntentKind.requiresPastePolicy,
         text: text,
         reason: reason,
       );

  const CommandSearchTerminalIntent.disabled(
    CommandSearchTerminalIntentReason reason,
  ) : this._(kind: CommandSearchTerminalIntentKind.disabled, reason: reason);

  final CommandSearchTerminalIntentKind kind;
  final String? text;
  final CommandSearchTerminalIntentReason? reason;

  bool get writesToShell {
    return kind == CommandSearchTerminalIntentKind.insertText ||
        kind == CommandSearchTerminalIntentKind.executeText;
  }
}

class CommandSearchInsertExecutePolicy {
  const CommandSearchInsertExecutePolicy();

  CommandSearchTerminalIntent resolve(
    CommandSearchOverlayOutput output, {
    required bool readOnly,
  }) {
    if (output.kind == CommandSearchOverlayOutputKind.viewBlock) {
      return const CommandSearchTerminalIntent.none();
    }
    final command = output.command?.trim();
    if (command == null || command.isEmpty) {
      return const CommandSearchTerminalIntent.none(
        CommandSearchTerminalIntentReason.emptySelection,
      );
    }
    if (readOnly) {
      return const CommandSearchTerminalIntent.disabled(
        CommandSearchTerminalIntentReason.readOnly,
      );
    }
    if (_isMultiline(command)) {
      return CommandSearchTerminalIntent.requiresPastePolicy(
        text: command,
        reason: CommandSearchTerminalIntentReason.multilineRequiresPastePolicy,
      );
    }
    return switch (output.kind) {
      CommandSearchOverlayOutputKind.insert =>
        CommandSearchTerminalIntent.insertText(command),
      CommandSearchOverlayOutputKind.explicitExecute =>
        CommandSearchTerminalIntent.executeText('$command\n'),
      CommandSearchOverlayOutputKind.viewBlock =>
        const CommandSearchTerminalIntent.none(),
      CommandSearchOverlayOutputKind.none =>
        const CommandSearchTerminalIntent.none(
          CommandSearchTerminalIntentReason.emptySelection,
        ),
    };
  }
}

bool _isMultiline(String value) {
  return value.contains('\n') || value.contains('\r');
}
