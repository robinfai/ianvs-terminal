import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_pty_backend.dart';
import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_profile_repository.dart';

Future<void> _pumpSmokeApp(
  WidgetTester tester, {
  required TerminalProfilesDocument profiles,
}) async {
  ensureMacosIntegrationTestFramesEnabled(tester.binding);

  final fakeBindings = FakePtyBackend();
  final repository = MemoryProfileRepository(profiles);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(fakeBindings),
        profileRepositoryProvider.overrideWithValue(repository),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
      ],
      child: const IanvsTerminalApp(),
    ),
  );

  // Bootstrap includes asynchronous platform persistence even with fake PTY
  // and profile repositories. No scheduled animation does not mean it is done.
  await _waitForTab(tester, '1');
  await tester.pumpAndSettle();
}

Future<void> _openCommandMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await _waitForWidget(
    tester,
    find.byKey(const Key('shell-command-menu-overlay')),
    description: 'the command menu to open',
  );
  await tester.pumpAndSettle();
}

Future<void> _waitForCondition(
  WidgetTester tester, {
  required bool Function() condition,
  required String description,
  String Function()? onTimeout,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for $description. ${onTimeout?.call() ?? ''}');
}

Future<void> _waitForWidget(
  WidgetTester tester,
  Finder finder, {
  required String description,
}) async {
  await _waitForCondition(
    tester,
    condition: () => finder.evaluate().length == 1,
    description: description,
  );
  expect(finder, findsOneWidget);
}

Future<void> _waitForTab(
  WidgetTester tester,
  String sessionId, {
  bool selected = false,
}) async {
  final tab = find.bySemanticsIdentifier('shell-tab-$sessionId');
  await _waitForCondition(
    tester,
    condition: () =>
        tab.evaluate().length == 1 &&
        find.byType(TerminalViewport).evaluate().length == 1 &&
        (!selected ||
            tester
                    .getSemantics(tab)
                    .getSemanticsData()
                    .flagsCollection
                    .isSelected
                    .toBoolOrNull() ==
                true),
    description:
        'tab $sessionId and its terminal viewport (selected=$selected)',
    onTimeout: () =>
        'tabs=${tab.evaluate().length}, '
        'viewports=${find.byType(TerminalViewport).evaluate().length}, '
        'semantics=${tab.evaluate().isEmpty ? null : tester.getSemantics(tab).getSemanticsData()}, '
        'launcher=${find.byKey(const Key('new-session-launcher')).evaluate().length}',
  );
}

void _expectSelectedTab(WidgetTester tester, String sessionId) {
  expect(
    tester.getSemantics(find.bySemanticsIdentifier('shell-tab-$sessionId')),
    matchesSemantics(hasSelectedState: true, isSelected: true, isButton: true),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('startup renders the hyper shell and opens another tab', (
    tester,
  ) async {
    await _pumpSmokeApp(
      tester,
      profiles: TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    );

    expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
    expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);

    await _openCommandMenu(tester);
    await tester.tap(find.byKey(const Key('shell-top-new-tab')));
    await tester.pumpAndSettle();
    await _waitForTab(tester, '2', selected: true);

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    _expectSelectedTab(tester, '2');
  });

  testWidgets('command-shift-p opens tools and defaults can close cleanly', (
    tester,
  ) async {
    await _pumpSmokeApp(
      tester,
      profiles: TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    );

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP, platform: 'macos');
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP, platform: 'macos');
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await _waitForWidget(
      tester,
      find.byKey(const Key('shell-command-defaults')).hitTestable(),
      description: 'the command palette defaults action',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-command-menu-overlay')), findsOneWidget);
    expect(find.byKey(const Key('shell-command-search-field')), findsOneWidget);
    expect(find.byKey(const Key('shell-command-defaults')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-command-defaults')));
    await _waitForWidget(
      tester,
      find.byKey(const Key('defaults-cancel')).hitTestable(),
      description: 'the defaults dialog controls',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);
    expect(find.byKey(const Key('defaults-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('defaults-cancel')));
    await tester.pumpAndSettle();
    await _waitForCondition(
      tester,
      condition: () =>
          find.byKey(const Key('defaults-dialog')).evaluate().isEmpty,
      description: 'the defaults dialog to close',
    );
    await _waitForTab(tester, '1');

    expect(find.byKey(const Key('defaults-dialog')), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);
  });

  testWidgets('profiles sheet can open another profile as a new tab', (
    tester,
  ) async {
    final primaryProfile = defaultTerminalProfile().copyWith(name: 'Shell A');
    final secondaryProfile = defaultTerminalProfile().copyWith(
      id: 'shell-b',
      name: 'Shell B',
    );

    await _pumpSmokeApp(
      tester,
      profiles: TerminalProfilesDocument(
        profiles: [primaryProfile, secondaryProfile],
      ),
    );

    await _openCommandMenu(tester);
    final profilesAction = find.byKey(const Key('shell-command-profiles'));
    await tester.ensureVisible(profilesAction);
    await tester.pumpAndSettle();
    await tester.tap(profilesAction);
    await tester.pumpAndSettle();

    await _waitForWidget(
      tester,
      find.byKey(const Key('profiles-sheet')),
      description: 'the profiles sheet to open',
    );
    await _waitForWidget(
      tester,
      find.byKey(const Key('profile-entry-shell-b')).hitTestable(),
      description: 'the second profile entry to become available',
    );
    await tester.tap(find.byKey(const Key('profile-entry-shell-b')));
    await tester.pumpAndSettle();

    await _waitForTab(tester, '2', selected: true);
    _expectSelectedTab(tester, '2');
  });

  testWidgets('closing tabs reaches the empty state and recovers via New Tab', (
    tester,
  ) async {
    await _pumpSmokeApp(
      tester,
      profiles: TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    );

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, platform: 'macos');
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pumpAndSettle();

    await _waitForCondition(
      tester,
      condition: () =>
          find.byKey(const Key('shell-empty-state')).evaluate().length == 1 &&
          find.byType(TerminalViewport).evaluate().isEmpty &&
          find
                  .byKey(const Key('shell-empty-new-tab'))
                  .hitTestable()
                  .evaluate()
                  .length ==
              1,
      description: 'the empty state after closing the last tab',
    );
    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);
    expect(find.byKey(const Key('shell-empty-new-tab')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-empty-new-tab')));
    // The empty-state action opens the launcher; the top-bar action uses the
    // default profile directly. Wait for the actual launcher before choosing.
    await _waitForWidget(
      tester,
      find.byKey(const Key('new-session-launcher')),
      description: 'the new-session launcher after leaving the empty state',
    );
    await tester.pumpAndSettle();
    final defaultSession = find.byKey(const Key('new-local-session-default'));
    await _waitForWidget(
      tester,
      defaultSession.hitTestable(),
      description: 'the default local profile in the launcher',
    );
    await tester.tap(defaultSession);
    await tester.pumpAndSettle();
    await _waitForTab(tester, '2');

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);
  });
}
