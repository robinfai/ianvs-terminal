import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'explicit first check preserves Normal even with a Blocks preference',
    () {
      final mode = TerminalModeController(
        preferredMode: TerminalViewMode.blocks,
      );
      addTearDown(mode.dispose);
      mode.updateAvailability(null, rechecked: true);
      expect(mode.state.mode, TerminalViewMode.normal);
      expect(mode.state.canUseBlocks, true);
      expect(mode.state.notice, TerminalModeNotice.supportChecked);
      mode.updateAvailability(null);
      expect(mode.state.mode, TerminalViewMode.normal);
      expect(mode.state.notice, TerminalModeNotice.supportChecked);
      mode.select(TerminalViewMode.blocks);
      expect(mode.state.notice, isNull);
    },
  );

  test(
    'checked reason persists until capability changes and restoration is manual',
    () {
      final mode = TerminalModeController(
        preferredMode: TerminalViewMode.blocks,
      );
      addTearDown(mode.dispose);
      mode.updateAvailability(null);
      mode.updateAvailability(
        BlockUnavailableReason.remoteShell,
        rechecked: true,
      );
      expect(mode.state.mode, TerminalViewMode.normal);
      var notifications = 0;
      mode.addListener(() => notifications++);
      mode.updateAvailability(BlockUnavailableReason.remoteShell);
      expect(notifications, 0);
      expect(mode.state.notice, TerminalModeNotice.supportChecked);
      mode.updateAvailability(null);
      expect(mode.state.mode, TerminalViewMode.normal);
      expect(mode.state.notice, TerminalModeNotice.blocksRestored);
      mode.updateAvailability(null, rechecked: true);
      expect(mode.state.mode, TerminalViewMode.normal);
      expect(mode.state.notice, TerminalModeNotice.supportChecked);
    },
  );
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
