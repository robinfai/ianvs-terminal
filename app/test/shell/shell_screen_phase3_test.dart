import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_acceptance.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

Future<void> _pumpShellScreen(
  WidgetTester tester, {
  required FakeCoreBindings fakeBindings,
  required MemoryProfileRepository profileRepository,
  required MemoryAppPreferencesRepository preferencesRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(fakeBindings),
        ),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        appPreferencesRepositoryProvider.overrideWithValue(
          preferencesRepository,
        ),
      ],
      child: const MaterialApp(home: ShellScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'defaults remain hidden from the shell workspace until the user opens tools',
    (tester) async {
      final profileRepository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'ssh',
          profiles: [
            defaultTerminalProfile(),
            const TerminalProfile(
              id: 'ssh',
              name: 'SSH',
              shell: '/usr/bin/ssh',
            ),
          ],
        ),
      );

      await _pumpShellScreen(
        tester,
        fakeBindings: FakeCoreBindings(),
        profileRepository: profileRepository,
        preferencesRepository: MemoryAppPreferencesRepository(null),
      );

      expect(find.byKey(const Key('shell-empty-state')), findsNothing);
      expect(find.text('Current new-tab profile • SSH'), findsNothing);
      expect(find.text('Theme • System'), findsNothing);
    },
  );

  testWidgets(
    'defaults dialog shows the current new-tab profile when no default is configured',
    (tester) async {
      final profileRepository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'ssh',
          profiles: [
            defaultTerminalProfile(),
            const TerminalProfile(
              id: 'ssh',
              name: 'SSH',
              shell: '/usr/bin/ssh',
            ),
          ],
        ),
      );

      await _pumpShellScreen(
        tester,
        fakeBindings: FakeCoreBindings(),
        profileRepository: profileRepository,
        preferencesRepository: MemoryAppPreferencesRepository(null),
      );

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);
      expect(shellAcceptanceProbe.current.defaultsOpen, isTrue);
      expect(shellAcceptanceProbe.current.commandMenuOpen, isFalse);
      expect(shellAcceptanceProbe.current.visibleOverlay, 'defaults');
      expect(shellAcceptanceProbe.current.themeMode, 'system');
      expect(shellAcceptanceProbe.current.terminalHasVisibleContent, isTrue);
      expect(shellAcceptanceProbe.current.terminalPreview, isNotNull);
      expect(
        find.text('New tabs use SSH until you choose a default.'),
        findsOneWidget,
      );
      expect(find.text('Current new-tab profile • SSH'), findsWidgets);
    },
  );

  testWidgets(
    'defaults and appearance modal is the only place that mutates default profile and theme',
    (tester) async {
      final preferencesRepository = MemoryAppPreferencesRepository(null);
      final profileRepository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [
            defaultTerminalProfile(),
            const TerminalProfile(
              id: 'ssh',
              name: 'SSH',
              shell: '/usr/bin/ssh',
            ),
          ],
        ),
      );

      await _pumpShellScreen(
        tester,
        fakeBindings: FakeCoreBindings(),
        profileRepository: profileRepository,
        preferencesRepository: preferencesRepository,
      );

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();

      final defaultsVersion = shellAcceptanceProbe.current.snapshotVersion;
      expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);
      expect(find.text('No configured default'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.byKey(const Key('defaults-save')), findsOneWidget);

      await tester.tap(find.widgetWithText(RadioListTile<String?>, 'SSH'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dark'));
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final savedPreferences = await preferencesRepository.load();
      expect(savedPreferences, isNotNull);
      expect(savedPreferences!.defaults.defaultProfileId, 'ssh');
      expect(savedPreferences.appearance.themeMode, TerminalThemeMode.dark);

      expect(find.byKey(const Key('shell-chrome-menu')), findsOneWidget);
      expect(shellAcceptanceProbe.current.visibleOverlay, 'none');
      expect(
        shellAcceptanceProbe.current.snapshotVersion,
        greaterThan(defaultsVersion),
      );
    },
  );

  testWidgets(
    'closing defaults and appearance restores terminal viewport focus',
    (tester) async {
      final fakeBindings = FakeCoreBindings();

      await _pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        profileRepository: MemoryProfileRepository(
          TerminalProfilesDocument(
            defaultProfileId: 'default',
            profiles: [defaultTerminalProfile()],
          ),
        ),
        preferencesRepository: MemoryAppPreferencesRepository(null),
      );

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);

      await tester.tap(find.byTooltip('Close defaults'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('defaults-dialog')), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.pump();

      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, 'v'.codeUnits);
    },
  );

  testWidgets('profiles sheet opens from the command menu and lists profiles', (
    tester,
  ) async {
    final profileRepository = MemoryProfileRepository(
      TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [
          defaultTerminalProfile(),
          const TerminalProfile(id: 'ssh', name: 'SSH', shell: '/usr/bin/ssh'),
        ],
      ),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: FakeCoreBindings(),
      profileRepository: profileRepository,
      preferencesRepository: MemoryAppPreferencesRepository(null),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profiles…'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profiles-sheet')), findsOneWidget);
    expect(shellAcceptanceProbe.current.profilesOpen, isTrue);
    expect(shellAcceptanceProbe.current.commandMenuOpen, isFalse);
    expect(shellAcceptanceProbe.current.visibleOverlay, 'profiles');
    expect(find.text('Profiles'), findsOneWidget);
    expect(find.byKey(const Key('profile-entry-default')), findsOneWidget);
    expect(find.byKey(const Key('profile-entry-ssh')), findsOneWidget);
    expect(find.text('Local Shell'), findsWidgets);
    expect(find.text('SSH'), findsOneWidget);
  });

  test(
    'driver acceptance probe returns the latest shell snapshot as json',
    () async {
      shellAcceptanceProbe.update(
        const ShellAcceptanceSnapshot(
          commandMenuOpen: true,
          defaultsOpen: false,
          profilesOpen: true,
          visibleOverlay: 'profiles',
          terminalHasVisibleContent: true,
          terminalPreview: 'driver ready',
          activeTabCount: 2,
          activeSessionId: '2',
          themeMode: 'dark',
          snapshotVersion: 4,
        ),
      );

      final response = await shellAcceptanceProbe.handleDriverRequest(
        'shell.acceptance',
      );

      expect(response, contains('"commandMenuOpen":true'));
      expect(response, contains('"profilesOpen":true'));
      expect(response, contains('"visibleOverlay":"profiles"'));
      expect(response, contains('"terminalHasVisibleContent":true'));
      expect(response, contains('"terminalPreview":"driver ready"'));
      expect(response, contains('"activeTabCount":2'));
      expect(response, contains('"activeSessionId":"2"'));
      expect(response, contains('"themeMode":"dark"'));
      expect(response, contains('"snapshotVersion":'));
    },
  );
}
