import 'dart:io';

import '../policies/local_terminal_notification_dispatcher.dart';
import '../policies/local_terminal_paste_decision.dart';
import '../policies/local_terminal_policy_action_reducer.dart';
import '../policies/local_terminal_policy_models.dart';
import '../productivity/shell_productivity_models.dart';
import '../visual/local_terminal_layout_template_applier.dart';
import '../visual/local_terminal_scrollback_exporter.dart';
import '../visual/local_terminal_visual_models.dart';
import '../layout/local_terminal_layout_models.dart';
import 'shell_action_dispatcher.dart';
import 'shell_action_pipeline.dart';
import 'shell_action_registry.dart';
import 'shell_action_side_effect_executor.dart';
import 'shell_action_side_effect_plan.dart';

const Object _copyWithUnset = Object();

class ShellActionRuntimeState {
  const ShellActionRuntimeState({
    this.layout = const TerminalLayout(),
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

  final TerminalLayout layout;
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
    TerminalLayout? layout,
    ShellProductivityState? productivity,
    LocalTerminalPolicyBundle? policies,
    Object? lastPlan = _copyWithUnset,
    Object? lastScrollbackExportPath = _copyWithUnset,
    Object? lastPasteDecision = _copyWithUnset,
    Object? lastNotificationIntent = _copyWithUnset,
    Object? lastPromptTarget = _copyWithUnset,
    Object? lastCommandOutputRange = _copyWithUnset,
    Object? lastRecentDirectory = _copyWithUnset,
    bool? themePickerRequested,
    Object? lastExternalExecutorError = _copyWithUnset,
  }) {
    return ShellActionRuntimeState(
      layout: layout ?? this.layout,
      productivity: productivity ?? this.productivity,
      policies: policies ?? this.policies,
      lastPlan: identical(lastPlan, _copyWithUnset)
          ? this.lastPlan
          : lastPlan as ShellActionSideEffectPlan?,
      lastScrollbackExportPath:
          identical(lastScrollbackExportPath, _copyWithUnset)
          ? this.lastScrollbackExportPath
          : lastScrollbackExportPath as String?,
      lastPasteDecision: identical(lastPasteDecision, _copyWithUnset)
          ? this.lastPasteDecision
          : lastPasteDecision as LocalTerminalPasteDecision?,
      lastNotificationIntent: identical(lastNotificationIntent, _copyWithUnset)
          ? this.lastNotificationIntent
          : lastNotificationIntent as LocalTerminalNotificationIntent?,
      lastPromptTarget: identical(lastPromptTarget, _copyWithUnset)
          ? this.lastPromptTarget
          : lastPromptTarget as ShellPromptMark?,
      lastCommandOutputRange: identical(lastCommandOutputRange, _copyWithUnset)
          ? this.lastCommandOutputRange
          : lastCommandOutputRange as ShellCommandOutputRange?,
      lastRecentDirectory: identical(lastRecentDirectory, _copyWithUnset)
          ? this.lastRecentDirectory
          : lastRecentDirectory as String?,
      themePickerRequested: themePickerRequested ?? this.themePickerRequested,
      lastExternalExecutorError:
          identical(lastExternalExecutorError, _copyWithUnset)
          ? this.lastExternalExecutorError
          : lastExternalExecutorError,
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
    Future<void> Function(TerminalLayout layout)? persistLayout,
    ShellActionSideEffectExecutor? externalExecutor,
  }) async {
    late final ShellActionSideEffectPlan planned;
    final pipeline = ShellActionPipeline(
      executor: ShellActionSideEffectExecutor(
        ShellActionSideEffectHandlers(
          updateLayout: (payload) async {
            if (payload is TerminalLayout) {
              _state = _state.copyWith(layout: payload);
              await persistLayout?.call(payload);
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
            final layout = LocalTerminalLayoutTemplateApplier.apply(
              template: payload,
              context: layoutTemplateApplyContext,
            );
            if (layout != null) {
              _state = _state.copyWith(layout: layout);
              await persistLayout?.call(layout);
            }
          },
        ),
      ),
    );

    final result = await pipeline.run(
      actionId: actionId,
      state: ShellActionDispatchState(
        layout: _state.layout,
        productivity: _state.productivity,
        policies: _state.policies,
      ),
      context: context,
    );
    planned = result.plan;
    _state = _state.copyWith(lastExternalExecutorError: null);
    try {
      await externalExecutor?.execute(planned);
    } on Object catch (error) {
      _state = _state.copyWith(lastExternalExecutorError: error);
    }
    _state = _state.copyWith(lastPlan: planned);
    return result;
  }
}
