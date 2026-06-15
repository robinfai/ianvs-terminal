import 'package:app/features/command_center/command_center_mode_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandCenterModeRouter', () {
    test('defaults to terminal and passes ordinary text to the shell', () {
      final router = CommandCenterModeRouter();

      expect(router.state.mode, CommandCenterMode.terminal);
      expect(router.state.inputOwner, CommandCenterInputOwner.terminal);

      final decision = router.route(
        const CommandCenterModeRequest.textInput('git status'),
      );

      expect(decision.disposition, CommandCenterRouteDisposition.passThrough);
      expect(decision.passesThroughToTerminal, isTrue);
      expect(decision.consumedByCommandCenter, isFalse);
      expect(decision.inputOwner, CommandCenterInputOwner.terminal);
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
      expect(search.inputOwner, CommandCenterInputOwner.commandSearch);
      expect(router.state.mode, CommandCenterMode.commandSearch);

      final actionSearch = router.route(
        const CommandCenterModeRequest.open(
          CommandCenterMode.actionSearch,
          source: CommandCenterModeRequestSource.explicitEntry,
        ),
      );
      expect(actionSearch.disposition, CommandCenterRouteDisposition.consumed);
      expect(actionSearch.inputOwner, CommandCenterInputOwner.actionSearch);
      expect(router.state.mode, CommandCenterMode.actionSearch);

      final commandBar = router.route(
        const CommandCenterModeRequest.open(
          CommandCenterMode.commandBar,
          source: CommandCenterModeRequestSource.explicitEntry,
        ),
      );
      expect(commandBar.inputOwner, CommandCenterInputOwner.commandBar);
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

    test('future agent is a disabled extension point', () {
      final router = CommandCenterModeRouter();

      final decision = router.route(
        const CommandCenterModeRequest.shortcut(
          CommandCenterModeShortcut.futureAgent,
        ),
      );

      expect(decision.disposition, CommandCenterRouteDisposition.disabled);
      expect(decision.disabledReason, CommandCenterModeDisabledReason.disabled);
      expect(decision.consumedByCommandCenter, isTrue);
      expect(decision.passesThroughToTerminal, isFalse);
      expect(router.state.mode, CommandCenterMode.terminal);
    });

    test('ordinary text never becomes an agent prompt', () {
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
      expect(text.inputOwner, CommandCenterInputOwner.commandSearch);
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
