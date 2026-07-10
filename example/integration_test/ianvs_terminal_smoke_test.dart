import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';

import '../test/support/fake_pty_backend.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_profile_repository.dart';

Future<void> _pumpSmokeApp(
  WidgetTester tester, {
  required TerminalProfilesDocument profiles,
}) async {
  // The macOS integration-test runner can attach while LaunchServices still
  // reports the app as hidden. Hidden bindings disable frames, so pumpWidget
  // would otherwise wait forever for a frame that cannot be scheduled.
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  expect(
    binding.framesEnabled,
    isTrue,
    reason:
        'The smoke-test binding must be able to schedule frames; '
        'lifecycle=${binding.lifecycleState}.',
  );

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

void _expectSelectedTab(WidgetTester tester, String sessionId) {
  expect(
    tester.getSemantics(find.bySemanticsIdentifier('shell-tab-$sessionId')),
    matchesSemantics(hasSelectedState: true, isSelected: true, isButton: true),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('startup renders the hyper shell and opens another tab', (
    WidgetTester tester,
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

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    _expectSelectedTab(tester, '2');
  });

  testWidgets('command-shift-p opens tools and defaults can close cleanly', (
    WidgetTester tester,
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

    expect(find.text('Top actions'), findsOneWidget);
    expect(find.text('Defaults & appearance'), findsOneWidget);

    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);

    await tester.tap(find.byTooltip('Close defaults'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaults-dialog')), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);
  });

  testWidgets('profiles sheet can open another profile as a new tab', (
    WidgetTester tester,
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

    expect(find.byKey(const Key('profiles-sheet')), findsOneWidget);
    await tester.tap(find.text('Shell B').last);
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    _expectSelectedTab(tester, '2');
  });

  testWidgets('closing tabs reaches the empty state and recovers via New Tab', (
    WidgetTester tester,
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

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);
  });
}
