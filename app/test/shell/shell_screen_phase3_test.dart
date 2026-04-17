import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
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
    'shell screen shows fallback defaults honestly when preferences are absent',
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

      expect(find.text('Fallback default • SSH'), findsWidgets);
      expect(find.text('Theme • System'), findsWidgets);
      expect(find.text('Set as default'), findsNothing);
    },
  );

  testWidgets(
    'defaults dialog shows the effective fallback profile during the legacy compatibility window',
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

      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Fallback • new tabs use SSH until you configure a default.',
        ),
        findsOneWidget,
      );
      expect(find.text('Fallback default • SSH'), findsWidgets);
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

      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();

      expect(find.text('Defaults & appearance'), findsNWidgets(2));
      expect(find.text('Use the first available profile'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

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

      expect(find.text('Configured default • SSH'), findsWidgets);
      expect(find.text('Theme • Dark'), findsWidgets);
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

      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();
      expect(find.text('Defaults & appearance'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Close defaults'));
      await tester.pumpAndSettle();

      expect(find.text('Defaults & appearance'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.pump();

      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, 'v'.codeUnits);
    },
  );
}
