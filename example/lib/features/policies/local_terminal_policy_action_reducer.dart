import '../shell/shell_action_registry.dart';
import 'local_terminal_notification_dispatcher.dart';
import 'local_terminal_paste_decision.dart';
import 'local_terminal_policy_models.dart';

sealed class LocalTerminalPolicyActionResult {
  const LocalTerminalPolicyActionResult();
}

class LocalTerminalPasteActionResult extends LocalTerminalPolicyActionResult {
  const LocalTerminalPasteActionResult(this.decision);

  final LocalTerminalPasteDecision decision;
}

class LocalTerminalNotificationActionResult
    extends LocalTerminalPolicyActionResult {
  const LocalTerminalNotificationActionResult(this.intent);

  final LocalTerminalNotificationIntent? intent;
}

class LocalTerminalHotkeyActionResult extends LocalTerminalPolicyActionResult {
  const LocalTerminalHotkeyActionResult(this.state);

  final LocalTerminalHotkeyWindowState state;
}

class LocalTerminalPolicyNoopResult extends LocalTerminalPolicyActionResult {
  const LocalTerminalPolicyNoopResult();
}

class LocalTerminalPolicyActionContext {
  const LocalTerminalPolicyActionContext({
    this.pasteText = '',
    this.readOnly = false,
    this.focused = false,
    this.observedDuration,
  });

  final String pasteText;
  final bool readOnly;
  final bool focused;
  final Duration? observedDuration;
}

class LocalTerminalPolicyBundle {
  const LocalTerminalPolicyBundle({
    this.paste = const LocalTerminalPastePolicy(),
    this.pasteHistory = const LocalTerminalPasteHistoryPolicy(),
    this.notifications = const LocalTerminalNotificationPolicy(),
    this.hotkeyWindow = const LocalTerminalHotkeyWindowPolicy(),
    this.hotkeyWindowState = const LocalTerminalHotkeyWindowState(),
  });

  final LocalTerminalPastePolicy paste;
  final LocalTerminalPasteHistoryPolicy pasteHistory;
  final LocalTerminalNotificationPolicy notifications;
  final LocalTerminalHotkeyWindowPolicy hotkeyWindow;
  final LocalTerminalHotkeyWindowState hotkeyWindowState;
}

class LocalTerminalPolicyActionReducer {
  const LocalTerminalPolicyActionReducer._();

  static LocalTerminalPolicyActionResult reduce({
    required TerminalActionId actionId,
    required LocalTerminalPolicyBundle policies,
    required LocalTerminalPolicyActionContext context,
  }) {
    return switch (actionId) {
      TerminalActionId.paste ||
      TerminalActionId.advancedPaste ||
      TerminalActionId.pasteHistory => LocalTerminalPasteActionResult(
        LocalTerminalPasteDecisionResolver.resolve(
          text: context.pasteText,
          readOnly: context.readOnly,
          pastePolicy: policies.paste,
          historyPolicy: policies.pasteHistory,
        ),
      ),
      TerminalActionId.toggleBellNotify =>
        LocalTerminalNotificationActionResult(
          LocalTerminalNotificationDispatcher.resolve(
            policy: policies.notifications,
            type: LocalTerminalNotificationEventType.bell,
            focused: context.focused,
            observedDuration: context.observedDuration,
          ),
        ),
      TerminalActionId.toggleCommandFinishedNotify =>
        LocalTerminalNotificationActionResult(
          LocalTerminalNotificationDispatcher.resolve(
            policy: policies.notifications,
            type: LocalTerminalNotificationEventType.commandFinished,
            focused: context.focused,
            observedDuration: context.observedDuration,
          ),
        ),
      TerminalActionId.toggleActivityMonitor =>
        LocalTerminalNotificationActionResult(
          LocalTerminalNotificationDispatcher.resolve(
            policy: policies.notifications,
            type: LocalTerminalNotificationEventType.activity,
            focused: context.focused,
            observedDuration: context.observedDuration,
          ),
        ),
      TerminalActionId.hotkeyWindow => LocalTerminalHotkeyActionResult(
        policies.hotkeyWindow.enabled && policies.hotkeyWindow.hasUsableSize
            ? policies.hotkeyWindowState.toggled()
            : policies.hotkeyWindowState.failed(
                const LocalTerminalHotkeyWindowFailure(
                  kind:
                      LocalTerminalHotkeyWindowFailureKind.platformUnavailable,
                  message: 'Hotkey window is disabled or misconfigured.',
                ),
              ),
      ),
      _ => const LocalTerminalPolicyNoopResult(),
    };
  }
}
