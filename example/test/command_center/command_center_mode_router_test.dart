import 'package:app/features/command_center/command_center_mode_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandCenterModeRouter', () {
    test('defaults to terminal and passes ordinary text to the shell', () {
      final router = CommandCenterModeRouter();

      expect(router.state.mode, CommandCenterMode.terminal);
      expect(router.state.inputOwner, InputOwner.terminalPty);
      expect(router.state.appInputMode, AppInputMode.terminal);

      final decision = router.route(
        const CommandCenterModeRequest.textInput('git status'),
      );

      expect(decision.disposition, CommandCenterRouteDisposition.passThrough);
      expect(decision.passesThroughToTerminal, isTrue);
      expect(decision.consumedByCommandCenter, isFalse);
      expect(decision.inputOwner, InputOwner.terminalPty);
      expect(router.state.mode, CommandCenterMode.terminal);
    });

    test('enters enhanced modes only from explicit shortcuts or entries', () {
      final router = CommandCenterModeRouter();

      final typed = router.route(
        const CommandCenterModeRequest.textInput('/search history'),
      );
      expect(typed.disposition, CommandCenterRouteDisposition.passThrough);
      expect(router.state.mode, CommandCenterMode.terminal);

      final search = router.route(
        const CommandCenterModeRequest.shortcut(
          CommandCenterModeShortcut.commandSearch,
        ),
      );
      expect(search.disposition, CommandCenterRouteDisposition.consumed);
      expect(search.transitioned, isTrue);
      expect(search.inputOwner, InputOwner.commandSearchOverlay);
      expect(router.state.mode, CommandCenterMode.commandSearch);

      final actionSearch = router.route(
        const CommandCenterModeRequest.open(
          CommandCenterMode.actionSearch,
          source: CommandCenterModeRequestSource.explicitEntry,
        ),
      );
      expect(actionSearch.disposition, CommandCenterRouteDisposition.consumed);
      expect(actionSearch.inputOwner, InputOwner.actionSearchOverlay);
      expect(router.state.mode, CommandCenterMode.actionSearch);

      final commandBar = router.route(
        const CommandCenterModeRequest.open(
          CommandCenterMode.commandBar,
          source: CommandCenterModeRequestSource.explicitEntry,
        ),
      );
      expect(commandBar.inputOwner, InputOwner.terminalCommandBar);
      expect(router.state.mode, CommandCenterMode.commandBar);
    });

    test('escape returns active enhanced modes to terminal', () {
      final router = CommandCenterModeRouter(
        state: const CommandCenterModeState(
          mode: CommandCenterMode.savedCommand,
        ),
      );

      final decision = router.route(const CommandCenterModeRequest.cancel());

      expect(decision.disposition, CommandCenterRouteDisposition.consumed);
      expect(decision.reason, CommandCenterRouteReason.cancelledToTerminal);
      expect(decision.previousMode, CommandCenterMode.savedCommand);
      expect(decision.mode, CommandCenterMode.terminal);
      expect(router.state.mode, CommandCenterMode.terminal);
    });

    test('opens agent conversation as a first-class mode', () {
      final router = CommandCenterModeRouter();

      final decision = router.route(
        const CommandCenterModeRequest.shortcut(
          CommandCenterModeShortcut.agentConversation,
        ),
      );

      expect(decision.disposition, CommandCenterRouteDisposition.consumed);
      expect(decision.inputOwner, InputOwner.agentConversationComposer);
      expect(decision.consumedByCommandCenter, isTrue);
      expect(decision.passesThroughToTerminal, isFalse);
      expect(router.state.mode, CommandCenterMode.agentConversation);
      expect(router.state.appInputMode, AppInputMode.agentConversation);
    });

    test('ordinary terminal text never silently becomes an agent prompt', () {
      final router = CommandCenterModeRouter();

      final decision = router.route(
        const CommandCenterModeRequest.textInput(
          'please summarize the last command',
        ),
      );

      expect(decision.disposition, CommandCenterRouteDisposition.passThrough);
      expect(decision.reason, CommandCenterRouteReason.terminalFirst);
      expect(router.state.mode, CommandCenterMode.terminal);
    });

    test(
      'represents active terminal session and agent conversation together',
      () {
        const state = CommandCenterModeState(
          mode: CommandCenterMode.agentConversation,
          activeTerminalSessionId: 'terminal-1',
          activeAgentConversationId: 'agent-1',
          autoDetectionEnabled: true,
        );

        expect(state.inputOwner, InputOwner.agentConversationComposer);
        expect(state.inputRoutingState.activeTerminalSessionId, 'terminal-1');
        expect(state.inputRoutingState.activeAgentConversationId, 'agent-1');
        expect(state.inputRoutingState.autoDetectionEnabled, isTrue);
      },
    );

    test('cancel from command review returns to agent conversation', () {
      final router = CommandCenterModeRouter(
        state: const CommandCenterModeState(
          mode: CommandCenterMode.agentCommandReview,
          activeAgentConversationId: 'agent-1',
        ),
      );

      final decision = router.route(const CommandCenterModeRequest.cancel());

      expect(decision.disposition, CommandCenterRouteDisposition.consumed);
      expect(
        decision.reason,
        CommandCenterRouteReason.commandReviewCancelledToAgent,
      );
      expect(decision.previousMode, CommandCenterMode.agentCommandReview);
      expect(decision.mode, CommandCenterMode.agentConversation);
      expect(decision.inputOwner, InputOwner.agentConversationComposer);
      expect(router.state.mode, CommandCenterMode.agentConversation);
    });

    test('active mode owns input until cancelled', () {
      final router = CommandCenterModeRouter(
        state: const CommandCenterModeState(
          mode: CommandCenterMode.commandSearch,
        ),
      );

      final text = router.route(
        const CommandCenterModeRequest.textInput('flutter'),
      );

      expect(text.disposition, CommandCenterRouteDisposition.consumed);
      expect(text.reason, CommandCenterRouteReason.activeModeOwnsInput);
      expect(text.inputOwner, InputOwner.commandSearchOverlay);
      expect(text.passesThroughToTerminal, isFalse);

      final unknown = router.route(
        const CommandCenterModeRequest.shortcut(
          CommandCenterModeShortcut.unknown,
        ),
      );

      expect(unknown.disposition, CommandCenterRouteDisposition.consumed);
      expect(unknown.reason, CommandCenterRouteReason.activeModeOwnsInput);
      expect(router.state.mode, CommandCenterMode.commandSearch);
    });
  });
}
