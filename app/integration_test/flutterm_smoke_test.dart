import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../test/support/fake_core_bindings.dart';
import '../test/support/memory_profile_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('startup renders a terminal tab and can open another tab', (
    WidgetTester tester,
  ) async {
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
        child: const FluttermApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('New Tab'), findsOneWidget);

    await tester.tap(find.text('New Tab'));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNWidgets(2));
    expect(find.text('Local Shell'), findsWidgets);
  });
}
