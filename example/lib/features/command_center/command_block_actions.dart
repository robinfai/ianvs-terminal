import 'command_block_models.dart';
import 'command_search_intents.dart';

enum CommandBlockAction {
  copyCommand,
  copyOutput,
  copyBoth,
  reInput,
  rerun,
  searchWithinBlock,
  saveOutput,
  openReviewEntrypoint,
}

enum CommandBlockActionIntentKind {
  none,
  clipboardText,
  copyOutputRange,
  clipboardCommandAndOutput,
  terminalWrite,
  scopedSearch,
  saveOutput,
  reviewEntrypoint,
}

enum CommandBlockActionDisabledReason {
  emptyCommand,
  missingOutputRange,
  missingTerminalFrame,
  readOnly,
  requiresPastePolicy,
}

class CommandBlockActionIntent {
  const CommandBlockActionIntent._({
    required this.kind,
    this.scope,
    this.blockId,
    this.text,
    this.outputRange,
    this.terminalIntent,
    this.explicitExecution = false,
    this.usesGlobalSearch = false,
  });

  const CommandBlockActionIntent.none()
    : this._(kind: CommandBlockActionIntentKind.none);

  const CommandBlockActionIntent.clipboardText({
    required String text,
    required CommandBlockScope scope,
    required String blockId,
  }) : this._(
         kind: CommandBlockActionIntentKind.clipboardText,
         text: text,
         scope: scope,
         blockId: blockId,
       );

  const CommandBlockActionIntent.copyOutputRange({
    required CommandBlockScope scope,
    required String blockId,
    required CommandBlockRowRange outputRange,
  }) : this._(
         kind: CommandBlockActionIntentKind.copyOutputRange,
         scope: scope,
         blockId: blockId,
         outputRange: outputRange,
       );

  const CommandBlockActionIntent.clipboardCommandAndOutput({
    required String text,
    required CommandBlockScope scope,
    required String blockId,
    required CommandBlockRowRange outputRange,
  }) : this._(
         kind: CommandBlockActionIntentKind.clipboardCommandAndOutput,
         text: text,
         scope: scope,
         blockId: blockId,
         outputRange: outputRange,
       );

  const CommandBlockActionIntent.terminalWrite({
    required CommandSearchTerminalIntent terminalIntent,
    required CommandBlockScope scope,
    required String blockId,
    bool explicitExecution = false,
  }) : this._(
         kind: CommandBlockActionIntentKind.terminalWrite,
         scope: scope,
         blockId: blockId,
         terminalIntent: terminalIntent,
         explicitExecution: explicitExecution,
       );

  const CommandBlockActionIntent.scopedSearch({
    required CommandBlockScope scope,
    required String blockId,
    required CommandBlockRowRange outputRange,
  }) : this._(
         kind: CommandBlockActionIntentKind.scopedSearch,
         scope: scope,
         blockId: blockId,
         outputRange: outputRange,
       );

  const CommandBlockActionIntent.saveOutput({
    required CommandBlockScope scope,
    required String blockId,
    required CommandBlockRowRange outputRange,
  }) : this._(
         kind: CommandBlockActionIntentKind.saveOutput,
         scope: scope,
         blockId: blockId,
         outputRange: outputRange,
       );

  const CommandBlockActionIntent.reviewEntrypoint({
    required CommandBlockScope scope,
    required String blockId,
    required CommandBlockRowRange outputRange,
  }) : this._(
         kind: CommandBlockActionIntentKind.reviewEntrypoint,
         scope: scope,
         blockId: blockId,
         outputRange: outputRange,
       );

  final CommandBlockActionIntentKind kind;
  final CommandBlockScope? scope;
  final String? blockId;
  final String? text;
  final CommandBlockRowRange? outputRange;
  final CommandSearchTerminalIntent? terminalIntent;
  final bool explicitExecution;
  final bool usesGlobalSearch;

  bool get writesToTerminal => terminalIntent?.writesToShell ?? false;
}

class CommandBlockActionResult {
  const CommandBlockActionResult._({required this.intent, this.disabledReason});

  const CommandBlockActionResult.enabled(CommandBlockActionIntent intent)
    : this._(intent: intent);

  const CommandBlockActionResult.disabled(
    CommandBlockActionDisabledReason reason, {
    CommandBlockActionIntent intent = const CommandBlockActionIntent.none(),
  }) : this._(intent: intent, disabledReason: reason);

  final CommandBlockActionIntent intent;
  final CommandBlockActionDisabledReason? disabledReason;

  bool get enabled => disabledReason == null;
}
