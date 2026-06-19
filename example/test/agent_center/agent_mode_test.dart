import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InputRoutingState', () {
    test('defaults to terminal PTY ownership', () {
      const state = InputRoutingState();

      expect(state.mode, AppInputMode.terminal);
      expect(state.owner, InputOwner.terminalPty);
      expect(state.terminalOwnsInput, isTrue);
      expect(state.agentOwnsInput, isFalse);
    });

    test('maps each app input mode to one input owner', () {
      expect(
        inputOwnerForMode(AppInputMode.terminalCommandBar),
        InputOwner.terminalCommandBar,
      );
      expect(
        inputOwnerForMode(AppInputMode.commandSearch),
        InputOwner.commandSearchOverlay,
      );
      expect(
        inputOwnerForMode(AppInputMode.actionSearch),
        InputOwner.actionSearchOverlay,
      );
      expect(
        inputOwnerForMode(AppInputMode.savedCommandSearch),
        InputOwner.savedCommandSearchOverlay,
      );
      expect(
        inputOwnerForMode(AppInputMode.agentConversation),
        InputOwner.agentConversationComposer,
      );
      expect(
        inputOwnerForMode(AppInputMode.agentInlineAsk),
        InputOwner.agentConversationComposer,
      );
      expect(
        inputOwnerForMode(AppInputMode.agentCommandReview),
        InputOwner.agentCommandReview,
      );
    });

    test('can represent terminal and agent conversation context together', () {
      const state = InputRoutingState(
        mode: AppInputMode.agentConversation,
        activeTerminalSessionId: 'terminal-1',
        activeAgentConversationId: 'agent-1',
        autoDetectionEnabled: true,
        lastIntentDecision: InputIntentDecision(
          kind: InputIntentKind.naturalLanguageQuestion,
          confidence: 0.93,
          reason: 'natural-language-score',
        ),
      );

      expect(state.owner, InputOwner.agentConversationComposer);
      expect(state.activeTerminalSessionId, 'terminal-1');
      expect(state.activeAgentConversationId, 'agent-1');
      expect(state.autoDetectionEnabled, isTrue);
      expect(state.lastIntentDecision?.visible, isTrue);
      expect(state.lastIntentDecision?.ambiguous, isFalse);
    });

    test('copyWith remaps owner when mode changes', () {
      const state = InputRoutingState(
        mode: AppInputMode.agentConversation,
        activeAgentConversationId: 'agent-1',
      );

      final next = state.copyWith(mode: AppInputMode.agentCommandReview);

      expect(next.mode, AppInputMode.agentCommandReview);
      expect(next.owner, InputOwner.agentCommandReview);
      expect(next.activeAgentConversationId, 'agent-1');
    });
  });
}
