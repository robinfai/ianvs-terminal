import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    expect(find.text('Command Center'), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Command Center'), findsOneWidget);
    expect(find.byKey(const Key('shell-command-menu-overlay')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('shell-command-menu-overlay'))).width,
      greaterThanOrEqualTo(400),
    );
    expect(find.text('New tab'), findsOneWidget);
    expect(find.text('Search terminal output'), findsWidgets);
    expect(find.text('Search scrollback'), findsNothing);
    expect(find.text('Copy selection'), findsOneWidget);
    expect(find.text('Paste clipboard'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Close actions'));
    await tester.pumpAndSettle();

    expect(find.text('Command Center'), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
    expect(shellAcceptanceProbe.current.commandMenuOpen, isFalse);
    expect(shellAcceptanceProbe.current.visibleOverlay, 'none');
    expect(
      shellAcceptanceProbe.current.snapshotVersion,
      greaterThan(openVersion),
    );
  });

  testWidgets('command menu close button works through semantics tap', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();

    final closeNode = tester.getSemantics(find.byTooltip('Close actions'));
    RendererBinding.instance.renderViews.single.owner!.semanticsOwner!
        .performAction(closeNode.id, SemanticsAction.tap);
    await tester.pumpAndSettle();

    expect(find.text('Command Center'), findsNothing);
    expect(shellAcceptanceProbe.current.commandMenuOpen, isFalse);
    semantics.dispose();
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

    expect(find.text('New tab'), findsOneWidget);
    expect(find.text('Paste history'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      'paste history',
    );
    await tester.pump();

    expect(find.text('Paste history'), findsOneWidget);
    expect(find.text('New tab'), findsNothing);
    expect(find.text('Defaults & appearance'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      'history paste',
    );
    await tester.pump();

    expect(find.text('Paste history'), findsOneWidget);
    expect(find.text('New tab'), findsNothing);
    expect(find.text('Defaults & appearance'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      '',
    );
    await tester.pump();

    expect(find.text('New tab'), findsOneWidget);
    expect(find.text('Paste history'), findsOneWidget);
  });

  testWidgets('command menu surfaces command search wording and query terms', (
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

    expect(find.text('Command search'), findsOneWidget);
    expect(find.text('Command Search'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      'command search',
    );
    await tester.pump();

    expect(find.text('Command search'), findsOneWidget);
  });

  testWidgets('command menu finds universal input by agent language', (
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

    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      'agent',
    );
    await tester.pump();

    expect(find.text('Universal input'), findsOneWidget);
    expect(find.text('New tab'), findsNothing);

    await tester.tap(find.text('Universal input'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-auto-composer')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('terminal-auto-composer')),
        matching: find.text('Auto-detect ready'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('command menu entry opens command search overlay', (
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
    await tester.ensureVisible(find.byKey(const Key('shell-command-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shell-command-search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('command-search-overlay')), findsOneWidget);
  });

  testWidgets(
    'toolbelt command search affordance opens command search overlay',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shell-toolbelt')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-toolbelt-panel')), findsOneWidget);
      expect(find.text('Command search'), findsOneWidget);
      expect(find.text('Command history'), findsNothing);

      await tester.tap(find.byKey(const Key('toolbelt-command-search')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('command-search-overlay')), findsOneWidget);
      expect(find.byKey(const Key('shell-toolbelt-panel')), findsNothing);
    },
  );

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
    await tester.tap(find.text('New tab'));
    await tester.pumpAndSettle();

    expect(find.text('Command Center'), findsNothing);
    expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);
  });
}
