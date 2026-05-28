import 'dart:io';

import 'package:app/features/policies/local_terminal_notification_dispatcher.dart';
import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/policies/local_terminal_paste_decision.dart';
import 'package:app/features/policies/local_terminal_policy_models.dart';
import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_dispatcher.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_controller.dart';
import 'package:app/features/shell/shell_action_side_effect_executor.dart';
import 'package:app/features/shell/shell_action_side_effect_plan.dart';
import 'package:app/features/shell/shell_action_test_harness.dart';
import 'package:app/features/visual/local_terminal_layout_template_applier.dart';
import 'package:app/features/visual/local_terminal_visual_models.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action runtime controller', () {
    test('updates workspace state for workspace actions', () async {
      final controller = ShellActionRuntimeController();
      final persisted = <TerminalWorkspace>[];

      await controller.run(
        actionId: TerminalActionId.newTab,
        context: _context(),
        persistWorkspace: (workspace) async => persisted.add(workspace),
      );

      expect(controller.state.workspace.activeTabId, 'tab-next');
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.updateWorkspace,
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

    test('updates hotkey window state for hotkey action', () async {
      final controller = ShellActionRuntimeController(
        initialState: const ShellActionRuntimeState(
          policies: LocalTerminalPolicyBundle(
            hotkeyWindow: LocalTerminalHotkeyWindowPolicy(enabled: true),
          ),
        ),
      );

      await controller.run(
        actionId: TerminalActionId.hotkeyWindow,
        context: _context(),
      );

      expect(controller.state.policies.hotkeyWindowState.visible, isTrue);
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.updateHotkeyWindowState,
      );
    });

    test('applies layout template visual action to workspace state', () async {
      final controller = ShellActionRuntimeController();
      final persisted = <TerminalWorkspace>[];

      await controller.run(
        actionId: TerminalActionId.applyLayoutTemplate,
        context: _context(
          layoutTemplate: const LocalTerminalLayoutTemplate(
            id: 'two-pane',
            name: 'Two Pane',
            paneCount: 2,
            localOnly: true,
          ),
        ),
        layoutTemplateApplyContext:
            const LocalTerminalLayoutTemplateApplyContext(
              tabId: 'tab-template',
              firstPaneId: 'pane-1',
              secondPaneId: 'pane-2',
              splitNodeId: 'split-1',
              sessionIntent: TerminalPaneSessionIntent(profileId: 'default'),
            ),
        persistWorkspace: (workspace) async => persisted.add(workspace),
      );

      expect(controller.state.workspace.activeTabId, 'tab-template');
      expect(
        controller.state.workspace.activeTab!.root.containsPane('pane-2'),
        isTrue,
      );
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.applyLayoutTemplate,
      );
      expect(persisted.single.activeTabId, 'tab-template');
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

    test('records notification intent for notification action', () async {
      final controller = ShellActionRuntimeController();

      await controller.run(
        actionId: TerminalActionId.toggleBellNotify,
        context: _context(),
      );

      expect(
        controller.state.lastNotificationIntent!.type,
        LocalTerminalNotificationEventType.bell,
      );
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.showNotification,
      );
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
        ShellActionSideEffectKind.selectCommandOutput,
      );
    });

    test('records recent directory for recent directory action', () async {
      final controller = ShellActionRuntimeController(
        initialState: const ShellActionRuntimeState(
          productivity: ShellProductivityState(recentDirectories: ['/repo']),
        ),
      );

      await controller.run(
        actionId: TerminalActionId.openRecentDirectory,
        context: _context(),
      );

      expect(controller.state.lastRecentDirectory, '/repo');
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.openRecentDirectory,
      );
    });

    test('records theme picker request for theme picker action', () async {
      final controller = ShellActionRuntimeController();

      await controller.run(
        actionId: TerminalActionId.openThemePicker,
        context: _context(),
      );

      expect(controller.state.themePickerRequested, isTrue);
      expect(
        controller.state.lastPlan!.kind,
        ShellActionSideEffectKind.openThemePicker,
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
  });
}

ShellActionDispatchContext _context({
  String pasteText = '',
  LocalTerminalLayoutTemplate? layoutTemplate,
  String scrollbackText = '',
  int currentRow = 0,
}) {
  return ShellActionDispatchContext(
    workspace: const LocalWorkspaceActionContext(
      nextTabId: 'tab-next',
      nextPaneId: 'pane-next',
      nextSplitId: 'split-next',
      fallbackIntent: TerminalPaneSessionIntent(profileId: 'default'),
    ),
    productivity: ShellProductivityActionContext(
      currentRow: currentRow,
      search: const ShellSearchState(),
    ),
    policy: LocalTerminalPolicyActionContext(pasteText: pasteText),
    visual: LocalTerminalVisualActionContext(
      layoutTemplate: layoutTemplate,
      scrollbackText: scrollbackText,
    ),
  );
}
