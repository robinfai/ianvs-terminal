import 'local_terminal_policy_models.dart';

enum LocalTerminalPasteDecisionKind {
  sendImmediately,
  requireConfirmation,
  blockedReadOnly,
}

class LocalTerminalPasteDecision {
  const LocalTerminalPasteDecision({
    required this.kind,
    required this.captureHistory,
    this.text = '',
  });

  final LocalTerminalPasteDecisionKind kind;
  final bool captureHistory;
  final String text;
}

class LocalTerminalPasteDecisionResolver {
  const LocalTerminalPasteDecisionResolver._();

  static LocalTerminalPasteDecision resolve({
    required String text,
    required bool readOnly,
    required LocalTerminalPastePolicy pastePolicy,
    required LocalTerminalPasteHistoryPolicy historyPolicy,
  }) {
    final largePaste = text.length >= pastePolicy.largePasteThreshold;
    final captureHistory = historyPolicy.shouldCapture(
      text: text,
      largePaste: largePaste,
    );

    if (!pastePolicy.canPaste(readOnly: readOnly)) {
      return LocalTerminalPasteDecision(
        kind: LocalTerminalPasteDecisionKind.blockedReadOnly,
        captureHistory: false,
        text: text,
      );
    }

    if (pastePolicy.requiresConfirmation(text)) {
      return LocalTerminalPasteDecision(
        kind: LocalTerminalPasteDecisionKind.requireConfirmation,
        captureHistory: captureHistory,
        text: text,
      );
    }

    return LocalTerminalPasteDecision(
      kind: LocalTerminalPasteDecisionKind.sendImmediately,
      captureHistory: captureHistory,
      text: text,
    );
  }
}
