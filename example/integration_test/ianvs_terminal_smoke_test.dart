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

  await tester.pumpAndSettle();
}

Future<void> _openCommandMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await tester.pumpAndSettle();
}

Future<void> _chooseDefaultLocalSession(WidgetTester tester) async {
  expect(find.byKey(const Key('new-session-launcher')), findsOneWidget);
  await tester.tap(find.byKey(const Key('new-local-session-default')));
  await tester.pumpAndSettle();
}

Future<void> _waitForWidget(
  WidgetTester tester,
  Finder finder, {
  required String description,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) {
      expect(finder, findsOneWidget);
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for $description.');
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
    await tester.tap(find.text('New tab'));
    await tester.pumpAndSettle();
    await _chooseDefaultLocalSession(tester);

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
    await tester.pump();

    expect(find.text('Command palette'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.byKey(const Key('shell-command-defaults')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-command-defaults')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);

    await tester.tap(find.byTooltip('Close defaults'));
    await tester.pumpAndSettle();

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
    await tester.ensureVisible(find.text('Profiles…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profiles…'));
    await tester.pumpAndSettle();

    await _waitForWidget(
      tester,
      find.byKey(const Key('profiles-sheet')),
      description: 'the profiles sheet to open',
    );
    await tester.tap(find.text('Shell B').last);
    await tester.pumpAndSettle();

    await _waitForWidget(
      tester,
      find.bySemanticsIdentifier('shell-tab-2'),
      description: 'the second profile tab to open',
    );
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

    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);
    expect(find.text('New Tab'), findsOneWidget);

    await tester.tap(find.text('New Tab'));
    await tester.pumpAndSettle();
    await _chooseDefaultLocalSession(tester);

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);
  });
}
