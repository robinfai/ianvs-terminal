import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../test/support/fake_core_bindings.dart';
import '../test/support/memory_profile_repository.dart';

Future<void> _pumpSmokeApp(
  WidgetTester tester, {
  required TerminalProfilesDocument profiles,
}) async {
  final fakeBindings = FakeCoreBindings();
  final repository = MemoryProfileRepository(profiles);

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
}

bool _isTabSelected(WidgetTester tester, String label) {
  return tester
      .widget<InputChip>(find.widgetWithText(InputChip, label))
      .selected;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('startup renders a terminal tab and can open another tab', (
    WidgetTester tester,
  ) async {
    await _pumpSmokeApp(
      tester,
      profiles: TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultTerminalProfile()],
      ),
    );

    expect(find.byType(InputChip), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('New Tab'), findsOneWidget);

    await tester.tap(find.text('New Tab'));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNWidgets(2));
    expect(find.text('Local Shell'), findsWidgets);
  });

  testWidgets(
    'top actions launcher opens predictably and can create another tab',
    (WidgetTester tester) async {
      await _pumpSmokeApp(
        tester,
        profiles: TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );

      expect(find.text('Actions'), findsOneWidget);
      expect(find.byType(InputChip), findsOneWidget);
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
      expect(find.byType(InputChip), findsOneWidget);
      expect(find.byType(TerminalViewport), findsOneWidget);

      await tester.tap(find.text('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New tab'));
      await tester.pumpAndSettle();

      expect(find.text('Top actions'), findsNothing);
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.byType(TerminalViewport), findsOneWidget);
      expect(find.text('Local Shell'), findsWidgets);
    },
  );

  testWidgets('closing an inactive tab keeps the active tab focused', (
    WidgetTester tester,
  ) async {
    final primaryProfile = defaultTerminalProfile().copyWith(name: 'Shell A');
    final secondaryProfile = defaultTerminalProfile().copyWith(
      id: 'shell-b',
      name: 'Shell B',
    );
    final tertiaryProfile = defaultTerminalProfile().copyWith(
      id: 'shell-c',
      name: 'Shell C',
    );

    await _pumpSmokeApp(
      tester,
      profiles: TerminalProfilesDocument(
        defaultProfileId: primaryProfile.id,
        profiles: [primaryProfile, secondaryProfile, tertiaryProfile],
      ),
    );

    await tester.tap(find.widgetWithText(ListTile, 'Shell B'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Shell C'));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNWidgets(3));
    expect(_isTabSelected(tester, 'Shell C'), isTrue);

    await tester.tap(find.widgetWithText(InputChip, 'Shell B'));
    await tester.pumpAndSettle();

    expect(_isTabSelected(tester, 'Shell A'), isFalse);
    expect(_isTabSelected(tester, 'Shell B'), isTrue);
    expect(_isTabSelected(tester, 'Shell C'), isFalse);

    tester
        .widget<InputChip>(find.widgetWithText(InputChip, 'Shell A'))
        .onDeleted!();
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNWidgets(2));
    expect(find.widgetWithText(InputChip, 'Shell A'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Shell B'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Shell C'), findsOneWidget);
    expect(_isTabSelected(tester, 'Shell B'), isTrue);
    expect(_isTabSelected(tester, 'Shell C'), isFalse);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
  });

  testWidgets('closing the active tab focuses the remaining tab', (
    WidgetTester tester,
  ) async {
    final primaryProfile = defaultTerminalProfile().copyWith(name: 'Shell A');
    final secondaryProfile = defaultTerminalProfile().copyWith(
      id: 'shell-b',
      name: 'Shell B',
    );

    await _pumpSmokeApp(
      tester,
      profiles: TerminalProfilesDocument(
        defaultProfileId: primaryProfile.id,
        profiles: [primaryProfile, secondaryProfile],
      ),
    );

    expect(find.byType(InputChip), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Shell A'), findsOneWidget);
    expect(_isTabSelected(tester, 'Shell A'), isTrue);

    await tester.tap(find.widgetWithText(ListTile, 'Shell B'));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNWidgets(2));
    expect(find.widgetWithText(InputChip, 'Shell A'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Shell B'), findsOneWidget);
    expect(_isTabSelected(tester, 'Shell A'), isFalse);
    expect(_isTabSelected(tester, 'Shell B'), isTrue);

    await tester.tap(find.widgetWithText(InputChip, 'Shell A'));
    await tester.pumpAndSettle();

    expect(_isTabSelected(tester, 'Shell A'), isTrue);
    expect(_isTabSelected(tester, 'Shell B'), isFalse);

    tester
        .widget<InputChip>(find.widgetWithText(InputChip, 'Shell A'))
        .onDeleted!();
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Shell A'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Shell B'), findsOneWidget);
    expect(_isTabSelected(tester, 'Shell B'), isTrue);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
  });

  testWidgets(
    'closing the last tab can recover from the empty state via New Tab',
    (WidgetTester tester) async {
      await _pumpSmokeApp(
        tester,
        profiles: TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );

      expect(find.byType(InputChip), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Local Shell'), findsOneWidget);
      expect(_isTabSelected(tester, 'Local Shell'), isTrue);
      expect(find.text('Create a shell to get started'), findsNothing);
      expect(find.byType(TerminalViewport), findsOneWidget);

      tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'Local Shell'))
          .onDeleted!();
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNothing);
      expect(find.text('Create a shell to get started'), findsOneWidget);
      expect(find.byType(TerminalViewport), findsNothing);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Paste'), findsNothing);
      expect(find.text('New Tab'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Local Shell'), findsOneWidget);

      await tester.tap(find.text('New Tab'));
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Local Shell'), findsOneWidget);
      expect(_isTabSelected(tester, 'Local Shell'), isTrue);
      expect(find.text('Create a shell to get started'), findsNothing);
      expect(find.byType(TerminalViewport), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
    },
  );

  testWidgets('a recovered tab can be closed back to the empty state again', (
    WidgetTester tester,
  ) async {
    await _pumpSmokeApp(
      tester,
      profiles: TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultTerminalProfile()],
      ),
    );

    tester
        .widget<InputChip>(find.widgetWithText(InputChip, 'Local Shell'))
        .onDeleted!();
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);
    expect(find.text('Create a shell to get started'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);
    expect(find.text('New Tab'), findsOneWidget);

    await tester.tap(find.text('New Tab'));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Local Shell'), findsOneWidget);
    expect(_isTabSelected(tester, 'Local Shell'), isTrue);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);

    tester
        .widget<InputChip>(find.widgetWithText(InputChip, 'Local Shell'))
        .onDeleted!();
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);
    expect(find.text('Create a shell to get started'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('New Tab'), findsOneWidget);
  });
}
