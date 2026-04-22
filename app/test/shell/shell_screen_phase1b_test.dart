import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/reference_demo.dart';
import 'package:app/features/shell/shell_screen.dart';
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
  testWidgets('shell screen exposes a selected tab in the hyper-style strip', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakeCoreBindings(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.byKey(const Key('shell-tab-strip')), findsOneWidget);
    expect(find.bySemanticsLabel('shell-tab-1'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('shell-tab-1')),
      matchesSemantics(
        label: 'shell-tab-1',
        hasSelectedState: true,
        isButton: true,
        isSelected: true,
      ),
    );
  });

  testWidgets(
    'shell screen keeps tab hierarchy clear after opening a second tab',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakeCoreBindings(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New tab'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('shell-tab-1'), findsOneWidget);
      expect(find.bySemanticsLabel('shell-tab-2'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('shell-tab-2')),
        matchesSemantics(
          label: 'shell-tab-2',
          hasSelectedState: true,
          isButton: true,
          isSelected: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('shell-tab-1')),
        matchesSemantics(
          label: 'shell-tab-1',
          hasSelectedState: true,
          isButton: true,
        ),
      );
    },
  );

  testWidgets('shell screen uses the same dark empty-state language everywhere', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakeCoreBindings(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byTooltip('Close Local Shell'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.text('Shell workspace is idle'), findsOneWidget);
    expect(
      find.text(
        'The last session has closed. Open a new tab to keep working in the shell workspace.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reference demo mode keeps the middle Shell tab selected', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakeCoreBindings(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      referenceDemoMode: true,
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('shell-tab-demo-2')),
      matchesSemantics(
        label: 'shell-tab-demo-2',
        hasSelectedState: true,
        isButton: true,
        isSelected: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('shell-tab-demo-1')),
      matchesSemantics(
        label: 'shell-tab-demo-1',
        hasSelectedState: true,
        isButton: true,
      ),
    );
  });
}
