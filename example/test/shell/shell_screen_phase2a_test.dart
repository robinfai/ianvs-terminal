import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_acceptance.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ui/app_ui.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';

Future<void> pumpShellScreen(
  WidgetTester tester, {
  required FakePtyBackend fakeBindings,
  required MemoryProfileRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shellAcceptanceProbeProvider.overrideWithValue(shellAcceptanceProbe),
        ptySessionBackendProvider.overrideWithValue(fakeBindings),
        profileRepositoryProvider.overrideWithValue(repository),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(null),
        ),
      ],
      child: MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.light),
        darkTheme: buildIanvsTerminalTheme(Brightness.dark),
        home: const ShellScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

bool isTabSelected(WidgetTester tester, String label) {
  return tester
      .widget<InputChip>(find.widgetWithText(InputChip, label))
      .selected;
}

void main() {
  testWidgets('shell screen opens and closes the hyper command menu', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.byKey(const Key('shell-chrome-menu')), findsOneWidget);
    expect(find.text('Command palette'), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Command palette'), findsOneWidget);
    expect(find.byKey(const Key('shell-command-menu-overlay')), findsOneWidget);
    expect(find.byKey(const Key('shell-top-new-tab')), findsOneWidget);
    expect(find.text('Search terminal output'), findsOneWidget);
    expect(find.text('Search scrollback'), findsNothing);
    expect(find.text('Copy selection'), findsNothing);
    expect(find.byKey(const Key('shell-top-paste-clipboard')), findsNothing);
    expect(find.byKey(const Key('shell-new-tab-at-folder')), findsNothing);
    expect(find.text('Defaults & appearance'), findsOneWidget);
    expect(find.text('Profiles…'), findsOneWidget);
    expect(find.byKey(const Key('shell-command-defaults')), findsOneWidget);
    expect(find.byKey(const Key('shell-command-profiles')), findsOneWidget);
    expect(shellAcceptanceProbe.current.commandMenuOpen, isTrue);
    expect(shellAcceptanceProbe.current.visibleOverlay, 'commandMenu');
    expect(shellAcceptanceProbe.current.terminalHasVisibleContent, isTrue);
    expect(shellAcceptanceProbe.current.terminalPreview, isNotNull);
    expect(shellAcceptanceProbe.current.activeTabCount, 1);
    expect(shellAcceptanceProbe.current.activeSessionId, '1');
    final openVersion = shellAcceptanceProbe.current.snapshotVersion;

    await tester.tap(find.byTooltip('Close command palette'));
    await tester.pumpAndSettle();

    expect(find.text('Command palette'), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
    expect(shellAcceptanceProbe.current.commandMenuOpen, isFalse);
    expect(shellAcceptanceProbe.current.visibleOverlay, 'none');
    expect(
      shellAcceptanceProbe.current.snapshotVersion,
      greaterThan(openVersion),
    );
  });

  testWidgets('shell screen command menu filters actions while typing', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-top-new-tab')), findsOneWidget);
    expect(find.byKey(const Key('shell-global-search')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      'global search',
    );
    await tester.pump();

    expect(find.text('Global search'), findsOneWidget);
    expect(find.byKey(const Key('shell-top-new-tab')), findsNothing);
    expect(find.text('Defaults & appearance'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      'search global',
    );
    await tester.pump();

    expect(find.text('Global search'), findsOneWidget);
    expect(find.byKey(const Key('shell-top-new-tab')), findsNothing);
    expect(find.text('Defaults & appearance'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      '',
    );
    await tester.pump();

    expect(find.byKey(const Key('shell-top-new-tab')), findsOneWidget);
    expect(find.byKey(const Key('shell-global-search')), findsOneWidget);
  });

  testWidgets('shell screen command menu can create another tab', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
    expect(find.bySemanticsIdentifier('shell-tab-2'), findsNothing);

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shell-top-new-tab')));
    await tester.pumpAndSettle();

    expect(find.text('Command palette'), findsNothing);
    expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);
  });
}
