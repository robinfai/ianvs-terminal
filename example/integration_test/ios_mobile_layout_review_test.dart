import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/instant_replay_store.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_pty_backend.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_profile_repository.dart';

class _IosMobileReviewPtyBackend extends FakePtyBackend {
  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson(<String, Object?>{
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
        'recording_schema_versions': <Object?>[],
        'features': <Object?>['session-config.json.v1', 'ssh-session.v1'],
      });
}

terminal.TerminalFrameDiff _frame(String text) {
  return terminal.TerminalFrameDiff(
    rows: <terminal.TerminalRow>[
      terminal.TerminalRow(index: 0, text: text),
      const terminal.TerminalRow(
        index: 1,
        text: r'$ flutter test --device iPhone',
      ),
      const terminal.TerminalRow(
        index: 2,
        text: 'Mobile replay controls are ready.',
      ),
    ],
    cursor: const terminal.TerminalCursor(row: 2, col: 34, visible: true),
    viewportRows: 24,
    viewportCols: 80,
    dirtyRanges: const <terminal.TerminalDirtyRange>[
      terminal.TerminalDirtyRange(start: 0, end: 3),
    ],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
  );
}

Future<void> _waitForWidget(
  WidgetTester tester,
  Finder finder, {
  required String description,
}) async {
  for (var tick = 0; tick < 200; tick += 1) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for $description.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Instant Replay remains usable across iPhone layouts', (
    tester,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final backend = _IosMobileReviewPtyBackend();
    var now = DateTime(2026, 8, 19, 14, 30);
    final replayStore = InstantReplayStore(now: () => now);
    final profile = TerminalProfile(
      id: 'ios-mobile-review',
      name: 'Mobile Review',
      shell: '/usr/bin/ssh',
      connection: const terminal.TerminalConnectionConfig.ssh(
        host: 'review.example.test',
        user: 'reviewer',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(backend),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: <TerminalProfile>[profile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            MemoryAppPreferencesRepository(null),
          ),
          instantReplayStoreProvider.overrideWithValue(replayStore),
        ],
        child: const IanvsTerminalApp(),
      ),
    );
    await tester.pumpAndSettle();

    final profileTile = find.byKey(
      const Key('ios-ssh-empty-profile-ios-mobile-review'),
    );
    await _waitForWidget(
      tester,
      profileTile,
      description: 'the iPhone SSH profile launcher',
    );
    await tester.tap(profileTile);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final sessionId = container.read(sessionControllerProvider).activeSessionId;
    expect(sessionId, isNotNull);
    replayStore.record(sessionId!, _frame('First captured mobile frame'));
    now = now.add(const Duration(seconds: 3));
    replayStore.record(sessionId, _frame('Second captured mobile frame'));

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    final toolbeltAction = find.byKey(const Key('shell-top-toolbelt'));
    await tester.ensureVisible(toolbeltAction);
    await tester.pumpAndSettle();
    await tester.tap(toolbeltAction);
    await tester.pumpAndSettle();
    final replayAction = find.byKey(const Key('toolbelt-instant-replay'));
    await tester.ensureVisible(replayAction);
    await tester.tap(replayAction);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('instant-replay-layout')), findsOneWidget);
    expect(
      find.byKey(const Key('instant-replay-floating-dock')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    if (const bool.fromEnvironment('IANVS_MOBILE_LAYOUT_REVIEW')) {
      await Future<void>.delayed(const Duration(seconds: 45));
    }
  });
}
