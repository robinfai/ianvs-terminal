import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';
import '../support/memory_profile_repository.dart';

Future<void> pumpShellScreen(
  WidgetTester tester, {
  required FakeCoreBindings fakeBindings,
  required MemoryProfileRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(fakeBindings),
        ),
        profileRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: ShellScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shell screen shows workspace chrome for the active session', (
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

    expect(find.text('Shell workspace'), findsOneWidget);
    expect(find.text('1 active session'), findsOneWidget);
    expect(find.text('Active session'), findsOneWidget);
  });

  testWidgets(
    'shell screen shows a richer empty state after closing the last tab', (
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

      final chipFinder = find.widgetWithText(InputChip, 'Local Shell');
      expect(chipFinder, findsOneWidget);

      final chip = tester.widget<InputChip>(chipFinder);
      chip.onDeleted!.call();
      await tester.pumpAndSettle();

      expect(find.text('Create a shell to get started'), findsOneWidget);
      expect(find.text('Reopen your default profile in one step.'), findsOneWidget);
      expect(find.text('New Tab'), findsOneWidget);
    },
  );
}
