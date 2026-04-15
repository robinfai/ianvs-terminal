import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ffi/flutterm_core.dart';

import 'support/fake_core_bindings.dart';
import 'support/memory_profile_repository.dart';

void main() {
  testWidgets('shell screen can open tabs from profiles', (tester) async {
    final fakeBindings = FakeCoreBindings();
    final repository = MemoryProfileRepository(
      TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultTerminalProfile()],
      ),
    );

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

    expect(find.text('Local Shell'), findsWidgets);
    await tester.tap(find.text('Local Shell').first);
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsWidgets);
    expect(find.text('Copy'), findsOneWidget);
  });
}
