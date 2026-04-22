import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/reference_demo.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

Future<void> pumpShellScreen(
  WidgetTester tester, {
  required FakeCoreBindings fakeBindings,
  required MemoryProfileRepository repository,
  bool referenceDemoMode = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(fakeBindings),
        ),
        profileRepositoryProvider.overrideWithValue(repository),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        referenceDemoModeProvider.overrideWithValue(referenceDemoMode),
      ],
      child: const MaterialApp(home: ShellScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shell screen renders a hyper-first chrome around the terminal', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakeCoreBindings(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      ),
    );

    expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
    expect(find.byKey(const Key('shell-tab-strip')), findsOneWidget);
    expect(find.byKey(const Key('shell-terminal-surface')), findsOneWidget);
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
        fakeBindings: FakeCoreBindings(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(
            defaultProfileId: 'default',
            profiles: [defaultTerminalProfile()],
          ),
        ),
      );

      expect(find.bySemanticsLabel('shell-tab-1'), findsOneWidget);

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
    },
  );

  testWidgets(
    'reference demo mode boots with three Shell tabs and no menu button',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakeCoreBindings(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(
            defaultProfileId: 'default',
            profiles: [defaultTerminalProfile()],
          ),
        ),
        referenceDemoMode: true,
      );

      expect(find.byKey(const Key('shell-chrome-menu')), findsNothing);
      expect(find.text('Shell'), findsNWidgets(3));
      expect(find.bySemanticsLabel('shell-tab-demo-1'), findsOneWidget);
      expect(find.bySemanticsLabel('shell-tab-demo-2'), findsOneWidget);
      expect(find.bySemanticsLabel('shell-tab-demo-3'), findsOneWidget);
      expect(find.byType(TerminalViewport), findsOneWidget);
    },
  );
}
