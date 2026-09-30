import 'package:app/app.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';

void main() {
  testWidgets(
    'restored active split pane owns the first keyboard input',
    (tester) async {
      final backend = FakePtyBackend();
      final layout = TerminalLayout(
        activeTabId: 'saved-tab',
        tabs: [
          TerminalLayoutTab(
            id: 'saved-tab',
            activePaneId: 'saved-right',
            root: TerminalPaneNode.split(
              id: 'saved-split',
              direction: TerminalPaneSplitDirection.right,
              first: TerminalPaneNode.leaf(
                id: 'saved-left',
                relaunchSpec: const TerminalRelaunchSpec(profileId: 'default'),
              ),
              second: TerminalPaneNode.leaf(
                id: 'saved-right',
                relaunchSpec: const TerminalRelaunchSpec(profileId: 'default'),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(backend),
            profileRepositoryProvider.overrideWithValue(
              MemoryProfileRepository(
                TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
              ),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(
                const LocalTerminalConfigDocument(
                  layout: LocalTerminalLayoutConfig(restoreLayout: true),
                ),
              ),
            ),
            localTerminalLayoutRepositoryProvider.overrideWithValue(
              _RestoredLayoutRepository(layout),
            ),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              noIoLocalSessionRecordingRepository(),
            ),
            pasteHistoryRepositoryProvider.overrideWithValue(
              MemoryPasteHistoryRepository(),
            ),
            shellAnimationsEnabledProvider.overrideWithValue(false),
          ],
          child: const IanvsTerminalApp(),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final state = container.read(sessionControllerProvider);
      expect(state.isReady, isTrue);
      expect(state.tabs.single.effectivePanes, hasLength(2));
      expect(find.byType(TerminalViewport), findsNWidgets(2));
      final activeId = state.activeSessionId!;
      expect(activeId, state.tabs.single.effectivePanes.last.sessionId);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'shell-terminal-$activeId',
      );

      // No click/focus workaround before the first keystroke: this is the
      // dangerous restart boundary where inactive panes previously received it.
      backend.writesBySession.clear();
      await _sendControlC(tester);
      expect(backend.writesBySession, hasLength(1));
      expect(backend.writesBySession.single.key, activeId);
      expect(backend.writesBySession.single.value, [3]);

      // A stale post-frame focus request must not win a newer activation.
      final controller = container.read(sessionControllerProvider.notifier);
      controller.activateSession(
        state.tabs.single.effectivePanes.first.sessionId,
      );
      controller.activateSession(activeId);
      await tester.pumpAndSettle();
      backend.writesBySession.clear();
      await _sendControlC(tester);
      expect(backend.writesBySession.single.key, activeId);
      expect(backend.writesBySession.single.value, [3]);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }),
  );
}

Future<void> _sendControlC(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

final class _RestoredLayoutRepository extends LocalTerminalLayoutRepository {
  _RestoredLayoutRepository(this.layout);
  final TerminalLayout layout;

  @override
  Future<TerminalLayout?> load() async => layout;

  @override
  Future<void> save(TerminalLayout layout) async {}
}
