import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Blocks preference waits for capability and never automatically restores after SSH',
    () {
      final mode = TerminalModeController(
        preferredMode: TerminalViewMode.blocks,
      );
      addTearDown(mode.dispose);
      mode.updateAvailability(BlockUnavailableReason.unsupportedShell);
      expect(mode.state.mode, TerminalViewMode.normal);
      mode.updateAvailability(null);
      expect(mode.state.mode, TerminalViewMode.blocks);
      mode.updateAvailability(BlockUnavailableReason.remoteShell);
      expect(mode.state.mode, TerminalViewMode.normal);
      expect(mode.state.notice, TerminalModeNotice.normalFallback);
      expect(mode.select(TerminalViewMode.blocks), isFalse);
      mode.updateAvailability(null);
      expect(mode.state.mode, TerminalViewMode.normal);
      expect(mode.state.notice, TerminalModeNotice.blocksRestored);
      mode.updateAvailability(null);
      expect(mode.state.mode, TerminalViewMode.normal);
      expect(mode.select(TerminalViewMode.blocks), isTrue);
      expect(mode.state.notice, isNull);
    },
  );

  test(
    'manual Normal overrides the preference even before the initial handshake',
    () {
      final mode = TerminalModeController(
        preferredMode: TerminalViewMode.blocks,
      );
      addTearDown(mode.dispose);
      mode.select(TerminalViewMode.normal);
      mode.updateAvailability(null);
      expect(mode.state.mode, TerminalViewMode.normal);
      expect(mode.state.notice, isNull);
    },
  );

  test(
    'sessions keep independent manual choices and only publish changed states',
    () {
      final first = TerminalModeController();
      final second = TerminalModeController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var notifications = 0;
      first.addListener(() => notifications++);
      first.updateAvailability(null);
      second.updateAvailability(null);
      expect(first.state.notice, TerminalModeNotice.blocksAvailable);
      first.updateAvailability(null);
      expect(notifications, 1);
      first.select(TerminalViewMode.blocks);
      expect(second.state.mode, TerminalViewMode.normal);
      first.updateAvailability(BlockUnavailableReason.fullScreen);
      first.updateAvailability(null);
      expect(first.state.notice, TerminalModeNotice.blocksRestored);
      first.select(TerminalViewMode.normal);
      first.updateAvailability(null);
      expect(first.state.notice, isNull);
    },
  );
}
