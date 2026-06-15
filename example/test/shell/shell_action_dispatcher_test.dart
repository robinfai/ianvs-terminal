import 'package:app/features/command_center/command_block_actions.dart';
import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/command_search_intents.dart';
import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_dispatcher.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action dispatcher', () {
    test('dispatches workspace actions first', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.newTab,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result, isA<ShellWorkspaceDispatchResult>());
      expect(
        (result as ShellWorkspaceDispatchResult).workspace.activeTabId,
        'tab-next',
      );
    });

    test('dispatches productivity actions when workspace is unchanged', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.toggleReadOnly,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result, isA<ShellProductivityDispatchResult>());
      expect(
        (result as ShellProductivityDispatchResult).result,
        isA<ShellProductivityStateResult>(),
      );
    });

    test(
      'dispatches policy actions when workspace and productivity are noop',
      () {
        final result = ShellActionDispatcher.dispatch(
          actionId: TerminalActionId.paste,
          state: const ShellActionDispatchState(),
          context: _context(pasteText: 'hello'),
        );

        expect(result, isA<ShellPolicyDispatchResult>());
        expect(
          (result as ShellPolicyDispatchResult).result,
          isA<LocalTerminalPasteActionResult>(),
        );
      },
    );

    test('dispatches visual actions when other reducers are noop', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.openThemePicker,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result, isA<ShellVisualDispatchResult>());
      expect(
        (result as ShellVisualDispatchResult).result,
        isA<LocalTerminalOpenThemePickerResult>(),
      );
    });

    test('dispatches block copy output through the shell action pipeline', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.copyBlockOutput,
        state: const ShellActionDispatchState(),
        context: _context(commandBlock: _block()),
      );

      expect(result, isA<ShellCommandBlockDispatchResult>());
      final blockResult = (result as ShellCommandBlockDispatchResult).result;
      expect(blockResult.enabled, isTrue);
      expect(
        blockResult.intent.kind,
        CommandBlockActionIntentKind.copyOutputRange,
      );
      expect(blockResult.intent.outputRange, _outputRange);
    });

    test('dispatches block re-input and rerun terminal intents safely', () {
      final reinput = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.reInputBlockCommand,
        state: const ShellActionDispatchState(),
        context: _context(commandBlock: _block(command: 'dart test')),
      );
      final rerun = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.rerunBlockCommand,
        state: const ShellActionDispatchState(
          productivity: ShellProductivityState(readOnly: true),
        ),
        context: _context(commandBlock: _block(command: 'dart test')),
      );

      final reinputResult = (reinput as ShellCommandBlockDispatchResult).result;
      final rerunResult = (rerun as ShellCommandBlockDispatchResult).result;

      expect(
        reinputResult.intent.terminalIntent!.kind,
        CommandSearchTerminalIntentKind.insertText,
      );
      expect(reinputResult.intent.terminalIntent!.text, 'dart test');
      expect(reinputResult.intent.explicitExecution, isFalse);
      expect(rerunResult.enabled, isFalse);
      expect(
        rerunResult.disabledReason,
        CommandBlockActionDisabledReason.readOnly,
      );
    });

    test('ordinary copy is not routed through block actions', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.copy,
        state: const ShellActionDispatchState(),
        context: _context(commandBlock: _block()),
      );

      expect(result, isA<ShellUnhandledDispatchResult>());
    });

    test('returns unhandled for actions without reducer mapping', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.openDefaults,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result, isA<ShellUnhandledDispatchResult>());
    });
  });
}

ShellActionDispatchContext _context({
  String pasteText = '',
  CommandBlock? commandBlock,
}) {
  return ShellActionDispatchContext(
    workspace: const LocalWorkspaceActionContext(
      nextTabId: 'tab-next',
      nextPaneId: 'pane-next',
      nextSplitId: 'split-next',
      fallbackIntent: TerminalPaneSessionIntent(profileId: 'default'),
    ),
    productivity: const ShellProductivityActionContext(
      currentRow: 0,
      search: ShellSearchState(),
    ),
    policy: LocalTerminalPolicyActionContext(pasteText: pasteText),
    visual: const LocalTerminalVisualActionContext(),
    commandBlock: ShellCommandBlockActionContext(activeBlock: commandBlock),
  );
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
