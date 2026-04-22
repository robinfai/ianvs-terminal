import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

Future<void> _pumpShellScreen(
  WidgetTester tester, {
  required FakeCoreBindings fakeBindings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(fakeBindings),
        ),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
      ],
      child: const MaterialApp(home: ShellScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('terminal focus shows a visible shell workspace cue', (
    tester,
  ) async {
    await _pumpShellScreen(tester, fakeBindings: FakeCoreBindings());

    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    expect(find.byKey(const Key('shell-workspace-focus-cue')), findsOneWidget);
    expect(find.text('Shell workspace active'), findsOneWidget);
    expect(find.text('Keyboard input goes to this terminal.'), findsOneWidget);
  });

  testWidgets('launcher close restores the workspace cue and keyboard path', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();
    expect(find.text('Shell workspace active'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close actions'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-workspace-focus-cue')), findsOneWidget);
    expect(find.text('Back in shell workspace'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.pump();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, 'v'.codeUnits);
  });

  testWidgets('defaults close restores the workspace cue and keyboard path', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close defaults'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-workspace-focus-cue')), findsOneWidget);
    expect(find.text('Back in shell workspace'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.pump();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, 'v'.codeUnits);
  });
}
