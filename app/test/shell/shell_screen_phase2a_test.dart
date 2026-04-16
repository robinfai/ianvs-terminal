import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
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

bool isTabSelected(WidgetTester tester, String label) {
  return tester
      .widget<InputChip>(find.widgetWithText(InputChip, label))
      .selected;
}

void main() {
  testWidgets('shell screen opens and closes the top actions launcher', (
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

    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Top actions'), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);

    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();

    expect(find.text('Top actions'), findsOneWidget);
    expect(find.text('New tab'), findsOneWidget);
    expect(find.text('Copy selection'), findsOneWidget);
    expect(find.text('Paste clipboard'), findsOneWidget);

    await tester.tap(find.byTooltip('Close actions'));
    await tester.pumpAndSettle();

    expect(find.text('Top actions'), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Local Shell'), findsOneWidget);
    expect(isTabSelected(tester, 'Local Shell'), isTrue);
  });

  testWidgets('shell screen launcher can create another tab', (tester) async {
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

    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('1 open'), findsOneWidget);

    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tab'));
    await tester.pumpAndSettle();

    expect(find.text('Top actions'), findsNothing);
    expect(find.byType(InputChip), findsNWidgets(2));
    expect(find.text('2 open'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);
  });
}
