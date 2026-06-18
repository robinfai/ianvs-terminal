import 'package:app/features/command_center/command_block_action_reducer.dart';
import 'package:app/features/command_center/command_block_actions.dart';
import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/command_search_intents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandBlockActionReducer', () {
    test(
      'copies command text and describes copy both without platform access',
      () {
        final reducer = const CommandBlockActionReducer();
        final block = _block(command: 'flutter test');

        final command = reducer.reduce(CommandBlockAction.copyCommand, block);
        final both = reducer.reduce(CommandBlockAction.copyBoth, block);

        expect(command.enabled, isTrue);
        expect(command.intent.kind, CommandBlockActionIntentKind.clipboardText);
        expect(command.intent.text, 'flutter test');
        expect(command.intent.writesToTerminal, isFalse);
        expect(both.enabled, isTrue);
        expect(
          both.intent.kind,
          CommandBlockActionIntentKind.clipboardCommandAndOutput,
        );
        expect(both.intent.text, 'flutter test');
        expect(both.intent.outputRange, _outputRange);
      },
    );

    test('copy output requires a valid output range', () {
      final reducer = const CommandBlockActionReducer();
      final enabled = reducer.reduce(CommandBlockAction.copyOutput, _block());
      final missing = reducer.reduce(
        CommandBlockAction.copyOutput,
        _block(hasOutputRange: false),
      );

      expect(enabled.enabled, isTrue);
      expect(enabled.intent.kind, CommandBlockActionIntentKind.copyOutputRange);
      expect(enabled.intent.outputRange, _outputRange);
      expect(missing.enabled, isFalse);
      expect(
        missing.disabledReason,
        CommandBlockActionDisabledReason.missingOutputRange,
      );
    });

    test('re-input inserts text while rerun explicitly executes', () {
      final reducer = const CommandBlockActionReducer();
      final block = _block(command: 'dart test');

      final reinput = reducer.reduce(CommandBlockAction.reInput, block);
      final rerun = reducer.reduce(CommandBlockAction.rerun, block);

      expect(reinput.enabled, isTrue);
      expect(
        reinput.intent.terminalIntent!.kind,
        CommandSearchTerminalIntentKind.insertText,
      );
      expect(reinput.intent.terminalIntent!.text, 'dart test');
      expect(reinput.intent.explicitExecution, isFalse);
      expect(rerun.enabled, isTrue);
      expect(
        rerun.intent.terminalIntent!.kind,
        CommandSearchTerminalIntentKind.executeText,
      );
      expect(rerun.intent.terminalIntent!.text, 'dart test\n');
      expect(rerun.intent.explicitExecution, isTrue);
    });

    test('read only disables terminal writing actions', () {
      final reducer = const CommandBlockActionReducer();
      final block = _block(command: 'dart test');

      final reinput = reducer.reduce(
        CommandBlockAction.reInput,
        block,
        readOnly: true,
      );
      final rerun = reducer.reduce(
        CommandBlockAction.rerun,
        block,
        readOnly: true,
      );

      expect(reinput.enabled, isFalse);
      expect(reinput.disabledReason, CommandBlockActionDisabledReason.readOnly);
      expect(rerun.enabled, isFalse);
      expect(rerun.disabledReason, CommandBlockActionDisabledReason.readOnly);
    });

    test(
      'multiline terminal actions stay enabled and require paste policy',
      () {
        final reducer = const CommandBlockActionReducer();
        final block = _block(command: 'printf one\nprintf two');

        final result = reducer.reduce(CommandBlockAction.rerun, block);

        expect(result.enabled, isTrue);
        expect(result.disabledReason, isNull);
        expect(
          result.intent.terminalIntent!.kind,
          CommandSearchTerminalIntentKind.requiresPastePolicy,
        );
        expect(result.intent.terminalIntent!.text, 'printf one\nprintf two');
      },
    );

    test(
      'search within block stays scoped and does not touch global search',
      () {
        final reducer = const CommandBlockActionReducer();
        final result = reducer.reduce(
          CommandBlockAction.searchWithinBlock,
          _block(),
        );

        expect(result.enabled, isTrue);
        expect(result.intent.kind, CommandBlockActionIntentKind.scopedSearch);
        expect(result.intent.usesGlobalSearch, isFalse);
        expect(result.intent.scope, _scope);
        expect(result.intent.outputRange, _outputRange);
      },
    );

    test('save output and review require output range and terminal frame', () {
      final reducer = const CommandBlockActionReducer();
      final missingRange = reducer.reduce(
        CommandBlockAction.saveOutput,
        _block(hasOutputRange: false),
      );
      final missingFrame = reducer.reduce(
        CommandBlockAction.openReviewEntrypoint,
        _block(),
        hasTerminalFrame: false,
      );
      final save = reducer.reduce(CommandBlockAction.saveOutput, _block());
      final review = reducer.reduce(
        CommandBlockAction.openReviewEntrypoint,
        _block(),
      );

      expect(missingRange.enabled, isFalse);
      expect(
        missingRange.disabledReason,
        CommandBlockActionDisabledReason.missingOutputRange,
      );
      expect(missingFrame.enabled, isFalse);
      expect(
        missingFrame.disabledReason,
        CommandBlockActionDisabledReason.missingTerminalFrame,
      );
      expect(save.intent.kind, CommandBlockActionIntentKind.saveOutput);
      expect(review.intent.kind, CommandBlockActionIntentKind.reviewEntrypoint);
    });
  });
}

const _scope = CommandBlockScope('session-a', paneId: 'pane-a');
const _inputRange = CommandBlockRowRange(startRow: 4, endRowExclusive: 5);
const _outputRange = CommandBlockRowRange(startRow: 5, endRowExclusive: 8);
final _startedAt = DateTime.utc(2026, 6, 15, 10);

CommandBlock _block({
  String command = 'flutter test',
  bool hasOutputRange = true,
}) {
  return CommandBlock(
    id: 'cmd-1',
    sessionId: _scope.sessionId,
    paneId: _scope.paneId,
    command: command,
    startedAt: _startedAt,
    status: CommandInvocationStatus.succeeded,
    inputRange: _inputRange,
    outputRange: hasOutputRange ? _outputRange : null,
  );
}
