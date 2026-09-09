import '../shell/shell_action_registry.dart';
import 'local_terminal_paste_decision.dart';
import 'local_terminal_policy_models.dart';

sealed class LocalTerminalPolicyActionResult {
  const LocalTerminalPolicyActionResult();
}

class LocalTerminalPasteActionResult extends LocalTerminalPolicyActionResult {
  const LocalTerminalPasteActionResult(this.decision);

  final LocalTerminalPasteDecision decision;
}

class LocalTerminalPolicyNoopResult extends LocalTerminalPolicyActionResult {
  const LocalTerminalPolicyNoopResult();
}

class LocalTerminalPolicyActionContext {
  const LocalTerminalPolicyActionContext({
    this.pasteText = '',
    this.readOnly = false,
  });

  final String pasteText;
  final bool readOnly;
}

class LocalTerminalPolicyBundle {
  const LocalTerminalPolicyBundle({
    this.paste = const LocalTerminalPastePolicy(),
    this.pasteHistory = const LocalTerminalPasteHistoryPolicy(),
  });

  final LocalTerminalPastePolicy paste;
  final LocalTerminalPasteHistoryPolicy pasteHistory;
}

class LocalTerminalPolicyActionReducer {
  const LocalTerminalPolicyActionReducer._();

  static LocalTerminalPolicyActionResult reduce({
    required TerminalActionId actionId,
    required LocalTerminalPolicyBundle policies,
    required LocalTerminalPolicyActionContext context,
  }) {
    return switch (actionId) {
      TerminalActionId.paste => LocalTerminalPasteActionResult(
        LocalTerminalPasteDecisionResolver.resolve(
          text: context.pasteText,
          readOnly: context.readOnly,
          pastePolicy: policies.paste,
          historyPolicy: policies.pasteHistory,
        ),
      ),
      _ => const LocalTerminalPolicyNoopResult(),
    };
  }
}
