import 'dart:io';

import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/terminal_layout_action_reducer.dart';
import 'package:app/features/policies/local_terminal_paste_decision.dart';
import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_dispatcher.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_controller.dart';
import 'package:app/features/shell/shell_action_side_effect_executor.dart';
import 'package:app/features/shell/shell_action_side_effect_plan.dart';
import 'package:app/features/shell/shell_action_test_harness.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action runtime controller', () {
    test('state copyWith can clear nullable results', () {
      const plan = ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.none,
      );
      const pasteDecision = LocalTerminalPasteDecision(
        kind: LocalTerminalPasteDecisionKind.sendImmediately,
        captureHistory: true,
        text: 'hello',
      );
      const promptTarget = ShellPromptMark(id: 'prompt', row: 1);
      const outputRange = ShellCommandOutputRange(
        commandId: 'cmd',
        startRow: 1,
        endRow: 2,
      );
      final error = Object();
      final state = ShellActionRuntimeState(
        lastPlan: plan,
        lastScrollbackExportPath: '/tmp/scrollback.txt',
        lastPasteDecision: pasteDecision,
        lastPromptTarget: promptTarget,
        lastCommandOutputRange: outputRange,
        lastExternalExecutorError: error,
      );

      final unchanged = state.copyWith();
      final cleared = state.copyWith(
        lastPlan: null,
        lastScrollbackExportPath: null,
        lastPasteDecision: null,
        lastPromptTarget: null,
        lastCommandOutputRange: null,
        lastExternalExecutorError: null,
      );

      expect(unchanged.lastPlan, plan);
      expect(unchanged.lastScrollbackExportPath, '/tmp/scrollback.txt');
      expect(unchanged.lastPasteDecision, pasteDecision);
      expect(unchanged.lastPromptTarget, promptTarget);
      expect(unchanged.lastCommandOutputRange, outputRange);
      expect(unchanged.lastExternalExecutorError, error);
      expect(cleared.lastPlan, isNull);
      expect(cleared.lastScrollbackExportPath, isNull);
      expect(cleared.lastPasteDecision, isNull);
      expect(cleared.lastPromptTarget, isNull);
      expect(cleared.lastCommandOutputRange, isNull);
      expect(cleared.lastExternalExecutorError, isNull);
    });

    test('updates layout state for layout actions', () async {
      final controller = ShellActionRuntimeController();
      final persisted = <TerminalLayout>[];

      await controller.run(
        actionId: TerminalActionId.newTab,
        context: _context(),
        persistLayout: (layout) async => persisted.add(layout),
      );

      expect(controller.state.layout.activeTabId, 'tab-next');
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.updateLayout,
      );
      expect(persisted.single.activeTabId, 'tab-next');
    });

    test('updates productivity state for productivity actions', () async {
      final controller = ShellActionRuntimeController();

      await controller.run(
        actionId: TerminalActionId.toggleReadOnly,
        context: _context(),
      );

      expect(controller.state.productivity.readOnly, isTrue);
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.updateProductivityState,
      );
    });

    test('exports scrollback visual action and records file path', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-runtime-scrollback-export',
      );
      final controller = ShellActionRuntimeController();

      await controller.run(
        actionId: TerminalActionId.exportScrollback,
        context: _context(scrollbackText: 'hello'),
        scrollbackExportDirectory: directory,
        scrollbackExportBasename: 'session',
      );

      expect(
        controller.state.lastScrollbackExportPath,
        contains('session.txt'),
      );
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.exportScrollback,
      );
    });

    test('records paste decision for paste action', () async {
      final controller = ShellActionRuntimeController();
      final history = <String>[];

      await controller.run(
        actionId: TerminalActionId.paste,
        context: _context(pasteText: 'hello'),
        recordPasteHistory: (text) async => history.add(text),
      );

      expect(
        controller.state.lastPasteDecision!.kind,
        LocalTerminalPasteDecisionKind.sendImmediately,
      );
      expect(controller.state.lastPasteDecision!.text, 'hello');
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.sendPaste,
      );
      expect(history, ['hello']);
    });

    test('records prompt navigation target for prompt action', () async {
      final controller = ShellActionRuntimeController(
        initialState: const ShellActionRuntimeState(
          productivity: ShellProductivityState(
            promptMarks: [
              ShellPromptMark(id: 'p1', row: 1),
              ShellPromptMark(id: 'p2', row: 4),
            ],
          ),
        ),
      );

      await controller.run(
        actionId: TerminalActionId.nextPrompt,
        context: _context(currentRow: 2),
      );

      expect(controller.state.lastPromptTarget!.id, 'p2');
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.scrollToPrompt,
      );
    });

    test('records command output range for command output action', () async {
      final controller = ShellActionRuntimeController(
        initialState: const ShellActionRuntimeState(
          productivity: ShellProductivityState(
            commandOutputRanges: [
              ShellCommandOutputRange(commandId: 'cmd', startRow: 1, endRow: 3),
            ],
          ),
        ),
      );

      await controller.run(
        actionId: TerminalActionId.copyCommandOutput,
        context: _context(),
      );

      expect(controller.state.lastCommandOutputRange!.commandId, 'cmd');
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.copyCommandOutput,
      );
    });

    test('can mirror side-effect plan to an external executor', () async {
      final controller = ShellActionRuntimeController();
      final harness = ShellActionTestHarness();

      await controller.run(
        actionId: TerminalActionId.paste,
        context: _context(pasteText: 'hello'),
        externalExecutor: harness.executor(),
      );

      expect(harness.calls.single.kind, ShellActionSideEffectKind.sendPaste);
      expect(controller.state.lastPasteDecision!.text, 'hello');
    });

    test('records external executor errors without throwing', () async {
      final controller = ShellActionRuntimeController();
      final executor = ShellActionSideEffectExecutor(
        ShellActionSideEffectHandlers(
          sendPaste: (_) async => throw StateError('paste failed'),
        ),
      );

      await controller.run(
        actionId: TerminalActionId.paste,
        context: _context(pasteText: 'hello'),
        externalExecutor: executor,
      );

      expect(controller.state.lastExternalExecutorError, isA<StateError>());
      expect(controller.state.lastPasteDecision!.text, 'hello');
    });

    test(
      'clears external executor errors after a later successful run',
      () async {
        final controller = ShellActionRuntimeController();
        final failingExecutor = ShellActionSideEffectExecutor(
          ShellActionSideEffectHandlers(
            sendPaste: (_) async => throw StateError('paste failed'),
          ),
        );
        final harness = ShellActionTestHarness();

        await controller.run(
          actionId: TerminalActionId.paste,
          context: _context(pasteText: 'first'),
          externalExecutor: failingExecutor,
        );
        expect(controller.state.lastExternalExecutorError, isA<StateError>());

        await controller.run(
          actionId: TerminalActionId.paste,
          context: _context(pasteText: 'second'),
          externalExecutor: harness.executor(),
        );

        expect(controller.state.lastExternalExecutorError, isNull);
        expect(harness.calls.single.kind, ShellActionSideEffectKind.sendPaste);
        expect(controller.state.lastPasteDecision!.text, 'second');
      },
    );
  });
}

ShellActionDispatchContext _context({
  String pasteText = '',
  String scrollbackText = '',
  int currentRow = 0,
}) {
  return ShellActionDispatchContext(
    layout: const TerminalLayoutActionContext(
      nextTabId: 'tab-next',
      nextPaneId: 'pane-next',
      nextSplitId: 'split-next',
      fallbackIntent: TerminalRelaunchSpec(profileId: 'default'),
    ),
    productivity: ShellProductivityActionContext(
      currentRow: currentRow,
      search: const ShellSearchState(),
    ),
    policy: LocalTerminalPolicyActionContext(pasteText: pasteText),
    visual: LocalTerminalVisualActionContext(scrollbackText: scrollbackText),
  );
}
