import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InputOwnershipRouter', () {
    const router = InputOwnershipRouter();

    test('routes terminal text to PTY in terminal mode', () {
      final decision = router.route(
        const InputRoutingState(),
        const InputOwnershipRequest.textInput('git status'),
      );

      expect(decision.disposition, InputOwnershipDisposition.passThrough);
      expect(decision.owner, InputOwner.terminalPty);
      expect(decision.writesToPty, isTrue);
      expect(decision.mayExecute, isTrue);
      expect(decision.reason, 'terminal-text-to-pty');
    });

    test('routes agent conversation text to the agent composer only', () {
      final decision = router.route(
        const InputRoutingState(mode: AppInputMode.agentConversation),
        const InputOwnershipRequest.textInput('explain the last failure'),
      );

      expect(decision.disposition, InputOwnershipDisposition.consumed);
      expect(decision.owner, InputOwner.agentConversationComposer);
      expect(decision.writesToPty, isFalse);
      expect(decision.mayExecute, isFalse);
      expect(decision.reason, 'active-surface-owns-text');
    });

    test('blocks hidden terminal focus while another surface owns text', () {
      final decision = router.route(
        const InputRoutingState(mode: AppInputMode.commandSearch),
        const InputOwnershipRequest.textInput(
          'leaked text',
          source: InputOwnershipRequestSource.hiddenTerminalFocus,
        ),
      );

      expect(decision.disposition, InputOwnershipDisposition.blocked);
      expect(decision.blocked, isTrue);
      expect(decision.writesToPty, isFalse);
      expect(decision.reason, 'hidden-terminal-focus-blocked');
    });

    test('keeps shortcut routing deterministic', () {
      final search = router.route(
        const InputRoutingState(),
        const InputOwnershipRequest.ctrlR(),
      );
      final actions = router.route(
        const InputRoutingState(),
        const InputOwnershipRequest.commandK(),
      );
      final agent = router.route(
        const InputRoutingState(),
        const InputOwnershipRequest.askAgent(),
      );

      expect(search.nextState.mode, AppInputMode.commandSearch);
      expect(search.owner, InputOwner.commandSearchOverlay);
      expect(actions.nextState.mode, AppInputMode.actionSearch);
      expect(actions.owner, InputOwner.actionSearchOverlay);
      expect(agent.nextState.mode, AppInputMode.agentConversation);
      expect(agent.owner, InputOwner.agentConversationComposer);
    });

    test('command search enter inserts a draft without executing', () {
      final decision = router.route(
        const InputRoutingState(mode: AppInputMode.commandSearch),
        const InputOwnershipRequest.enter(),
      );

      expect(decision.disposition, InputOwnershipDisposition.consumed);
      expect(decision.insertsCommandDraft, isTrue);
      expect(decision.writesToPty, isFalse);
      expect(decision.mayExecute, isFalse);
      expect(decision.routesToSafetyPipeline, isFalse);
    });

    test('explicit execute goes through safety pipeline', () {
      final decision = router.route(
        const InputRoutingState(mode: AppInputMode.commandSearch),
        const InputOwnershipRequest.explicitExecute(),
      );

      expect(decision.disposition, InputOwnershipDisposition.consumed);
      expect(decision.routesToSafetyPipeline, isTrue);
      expect(decision.mayExecute, isTrue);
      expect(decision.writesToPty, isFalse);
    });

    test('read-only blocks execution paths', () {
      final decision = router.route(
        const InputRoutingState(mode: AppInputMode.agentCommandReview),
        const InputOwnershipRequest.executeProposal(),
        readOnly: true,
      );

      expect(decision.disposition, InputOwnershipDisposition.blocked);
      expect(decision.routesToSafetyPipeline, isTrue);
      expect(decision.mayExecute, isFalse);
      expect(decision.writesToPty, isFalse);
      expect(decision.reason, 'read-only-blocks-execution');
    });

    test('proposal insert writes a command draft instead of PTY text', () {
      final decision = router.route(
        const InputRoutingState(mode: AppInputMode.agentCommandReview),
        const InputOwnershipRequest.insertProposal(),
      );

      expect(decision.nextState.mode, AppInputMode.terminalCommandBar);
      expect(decision.owner, InputOwner.terminalCommandBar);
      expect(decision.insertsCommandDraft, isTrue);
      expect(decision.writesToPty, isFalse);
      expect(decision.mayExecute, isFalse);
    });

    test('escape from command review returns to agent conversation', () {
      final decision = router.route(
        const InputRoutingState(mode: AppInputMode.agentCommandReview),
        const InputOwnershipRequest.escape(),
      );

      expect(decision.nextState.mode, AppInputMode.agentConversation);
      expect(decision.owner, InputOwner.agentConversationComposer);
      expect(decision.reason, 'review-cancelled-to-agent');
    });
  });
}
