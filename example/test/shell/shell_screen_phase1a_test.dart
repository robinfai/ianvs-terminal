import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/shell/reference_demo.dart';
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
  bool referenceDemoMode = false,
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
        sessionDemoFixtureProvider.overrideWithValue(
          referenceDemoMode ? referenceDemoFixture : null,
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

void main() {
  testWidgets('shell screen renders a hyper-first chrome around the terminal', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
    expect(find.byKey(const Key('shell-tab-strip')), findsOneWidget);
    expect(find.byKey(const Key('shell-chrome-new-tab')), findsOneWidget);
    expect(find.byKey(const Key('shell-terminal-surface')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-bar')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('shell-chrome-bar'))).height,
      88,
    );
    expect(find.byKey(const Key('shell-chrome-window-title')), findsOneWidget);
    expect(find.byKey(const Key('shell-chrome-window-shortcut')), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(InputChip), findsNothing);
    expect(find.text('Shell workspace'), findsNothing);
    expect(find.text('Session tabs'), findsNothing);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Paste'), findsNothing);
  });

  testWidgets(
    'shell screen collapses into a dark empty state after closing the last tab',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);

      await _hoverShellTab(tester, '1');
      await tester.tap(find.byTooltip('Close Local Shell'));
      await tester.pumpAndSettle();

      expect(find.byType(TerminalViewport), findsNothing);
      expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
      expect(find.text('Shell workspace is idle'), findsOneWidget);
      expect(
        find.text('Current new-tab profile • Local Shell'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The last session has closed. Open a new tab to keep working in the shell workspace.',
        ),
        findsOneWidget,
      );
      expect(find.text('New Tab'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('shell-empty-state'))).width,
        greaterThan(200),
      );
    },
  );

  testWidgets(
    'reference demo mode boots with three Shell tabs and no menu button',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        referenceDemoMode: true,
      );

      expect(find.byKey(const Key('shell-chrome-menu')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-strip')),
          matching: find.text('Shell'),
        ),
        findsNWidgets(3),
      );
      expect(
        find.byKey(const Key('shell-chrome-window-title')),
        findsOneWidget,
      );
      expect(find.bySemanticsIdentifier('shell-tab-demo-1'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell-tab-demo-2'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell-tab-demo-3'), findsOneWidget);
      expect(find.byType(TerminalViewport), findsOneWidget);
    },
  );
}

Future<void> _hoverShellTab(WidgetTester tester, String sessionId) async {
  final pointer = TestPointer(97, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.hover(tester.getCenter(find.byKey(Key('shell-tab-$sessionId')))),
  );
  await tester.pump();
}
