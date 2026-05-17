import 'dart:io';

import '../policies/local_terminal_notification_dispatcher.dart';
import '../policies/local_terminal_paste_decision.dart';
import '../policies/local_terminal_policy_action_reducer.dart';
import '../policies/local_terminal_policy_models.dart';
import '../productivity/shell_productivity_models.dart';
import '../visual/local_terminal_layout_template_applier.dart';
import '../visual/local_terminal_scrollback_exporter.dart';
import '../visual/local_terminal_visual_models.dart';
import '../workspace/local_workspace_models.dart';
import 'shell_action_dispatcher.dart';
import 'shell_action_pipeline.dart';
import 'shell_action_registry.dart';
import 'shell_action_side_effect_executor.dart';
import 'shell_action_side_effect_plan.dart';

class ShellActionRuntimeState {
  const ShellActionRuntimeState({
    this.workspace = const TerminalWorkspace(),
    this.productivity = const ShellProductivityState(),
    this.policies = const LocalTerminalPolicyBundle(),
    this.lastPlan,
    this.lastScrollbackExportPath,
    this.lastPasteDecision,
    this.lastNotificationIntent,
    this.lastPromptTarget,
    this.lastCommandOutputRange,
    this.lastRecentDirectory,
    this.themePickerRequested = false,
    this.lastExternalExecutorError,
  });

  final TerminalWorkspace workspace;
  final ShellProductivityState productivity;
  final LocalTerminalPolicyBundle policies;
  final ShellActionSideEffectPlan? lastPlan;
  final String? lastScrollbackExportPath;
  final LocalTerminalPasteDecision? lastPasteDecision;
  final LocalTerminalNotificationIntent? lastNotificationIntent;
  final ShellPromptMark? lastPromptTarget;
  final ShellCommandOutputRange? lastCommandOutputRange;
  final String? lastRecentDirectory;
  final bool themePickerRequested;
  final Object? lastExternalExecutorError;

  ShellActionRuntimeState copyWith({
    TerminalWorkspace? workspace,
    ShellProductivityState? productivity,
    LocalTerminalPolicyBundle? policies,
    ShellActionSideEffectPlan? lastPlan,
    String? lastScrollbackExportPath,
    LocalTerminalPasteDecision? lastPasteDecision,
    LocalTerminalNotificationIntent? lastNotificationIntent,
    ShellPromptMark? lastPromptTarget,
    ShellCommandOutputRange? lastCommandOutputRange,
    String? lastRecentDirectory,
    bool? themePickerRequested,
    Object? lastExternalExecutorError,
  }) {
    return ShellActionRuntimeState(
      workspace: workspace ?? this.workspace,
      productivity: productivity ?? this.productivity,
      policies: policies ?? this.policies,
      lastPlan: lastPlan ?? this.lastPlan,
      lastScrollbackExportPath:
          lastScrollbackExportPath ?? this.lastScrollbackExportPath,
      lastPasteDecision: lastPasteDecision ?? this.lastPasteDecision,
      lastNotificationIntent:
          lastNotificationIntent ?? this.lastNotificationIntent,
      lastPromptTarget: lastPromptTarget ?? this.lastPromptTarget,
      lastCommandOutputRange:
          lastCommandOutputRange ?? this.lastCommandOutputRange,
      lastRecentDirectory: lastRecentDirectory ?? this.lastRecentDirectory,
      themePickerRequested: themePickerRequested ?? this.themePickerRequested,
      lastExternalExecutorError:
          lastExternalExecutorError ?? this.lastExternalExecutorError,
    );
  }
}

class ShellActionRuntimeController {
  ShellActionRuntimeController({
    ShellActionRuntimeState initialState = const ShellActionRuntimeState(),
  }) : _state = initialState;

  ShellActionRuntimeState _state;

  ShellActionRuntimeState get state => _state;

  Future<ShellActionPipelineResult> run({
    required TerminalActionId actionId,
    required ShellActionDispatchContext context,
    LocalTerminalLayoutTemplateApplyContext? layoutTemplateApplyContext,
    Directory? scrollbackExportDirectory,
    String scrollbackExportBasename = 'scrollback',
    LocalTerminalScrollbackExportPolicy scrollbackExportPolicy =
        const LocalTerminalScrollbackExportPolicy(),
    Future<void> Function(String text)? recordPasteHistory,
    Future<void> Function(TerminalWorkspace workspace)? persistWorkspace,
    ShellActionSideEffectExecutor? externalExecutor,
  }) async {
    late final ShellActionSideEffectPlan planned;
    final pipeline = ShellActionPipeline(
      executor: ShellActionSideEffectExecutor(
        ShellActionSideEffectHandlers(
          updateWorkspace: (payload) async {
            if (payload is TerminalWorkspace) {
              _state = _state.copyWith(workspace: payload);
              await persistWorkspace?.call(payload);
            }
          },
          updateProductivityState: (payload) async {
            if (payload is ShellProductivityState) {
              _state = _state.copyWith(productivity: payload);
            }
          },
          scrollToPrompt: (payload) async {
            if (payload is ShellPromptMark) {
              _state = _state.copyWith(lastPromptTarget: payload);
            }
          },
          selectCommandOutput: (payload) async {
            if (payload is ShellCommandOutputRange) {
              _state = _state.copyWith(lastCommandOutputRange: payload);
            }
          },
          openRecentDirectory: (payload) async {
            if (payload is String) {
              _state = _state.copyWith(lastRecentDirectory: payload);
            }
          },
          updateHotkeyWindowState: (payload) async {
            if (payload is LocalTerminalHotkeyWindowState) {
              _state = _state.copyWith(
                policies: LocalTerminalPolicyBundle(
                  paste: _state.policies.paste,
                  pasteHistory: _state.policies.pasteHistory,
                  notifications: _state.policies.notifications,
                  hotkeyWindow: _state.policies.hotkeyWindow,
                  hotkeyWindowState: payload,
                ),
              );
            }
          },
          sendPaste: (payload) async {
            if (payload is LocalTerminalPasteDecision) {
              _state = _state.copyWith(lastPasteDecision: payload);
              if (payload.captureHistory) {
                await recordPasteHistory?.call(payload.text);
              }
            }
          },
          confirmPaste: (payload) async {
            if (payload is LocalTerminalPasteDecision) {
              _state = _state.copyWith(lastPasteDecision: payload);
              if (payload.captureHistory) {
                await recordPasteHistory?.call(payload.text);
              }
            }
          },
          blockPaste: (payload) async {
            if (payload is LocalTerminalPasteDecision) {
              _state = _state.copyWith(lastPasteDecision: payload);
            }
          },
          showNotification: (payload) async {
            if (payload is LocalTerminalNotificationIntent) {
              _state = _state.copyWith(lastNotificationIntent: payload);
            }
          },
          openThemePicker: (_) async {
            _state = _state.copyWith(themePickerRequested: true);
          },
          exportScrollback: (payload) async {
            if (payload is! LocalTerminalScrollbackExport ||
                scrollbackExportDirectory == null) {
              return;
            }
            final file = await LocalTerminalScrollbackExporter.write(
              directory: scrollbackExportDirectory,
              basename: scrollbackExportBasename,
              export: payload,
              policy: scrollbackExportPolicy,
            );
            _state = _state.copyWith(lastScrollbackExportPath: file.path);
          },
          applyLayoutTemplate: (payload) async {
            if (payload is! LocalTerminalLayoutTemplate ||
                layoutTemplateApplyContext == null) {
              return;
            }
            final workspace = LocalTerminalLayoutTemplateApplier.apply(
              template: payload,
              context: layoutTemplateApplyContext,
            );
            if (workspace != null) {
              _state = _state.copyWith(workspace: workspace);
              await persistWorkspace?.call(workspace);
            }
          },
        ),
      ),
    );

    final result = await pipeline.run(
      actionId: actionId,
      state: ShellActionDispatchState(
        workspace: _state.workspace,
        productivity: _state.productivity,
        policies: _state.policies,
      ),
      context: context,
    );
    planned = result.plan;
    try {
      await externalExecutor?.execute(planned);
    } on Object catch (error) {
      _state = _state.copyWith(lastExternalExecutorError: error);
    }
    _state = _state.copyWith(lastPlan: planned);
    return result;
  }
}
