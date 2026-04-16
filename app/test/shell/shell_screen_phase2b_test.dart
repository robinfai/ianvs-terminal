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
  testWidgets('command-shift-p opens launcher with explicit action scopes', (
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

    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP, platform: 'macos');
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP, platform: 'macos');
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();

    expect(find.text('Top actions'), findsOneWidget);
    expect(find.text('App actions'), findsOneWidget);
    expect(find.text('Session actions'), findsOneWidget);
    expect(
      find.textContaining('Open your default shell profile.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Copy the current terminal selection.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Send clipboard text to the active shell.'),
      findsOneWidget,
    );
  });

  testWidgets('launcher close restores terminal viewport focus', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();

    await pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      ),
    );

    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Top actions'), findsOneWidget);

    await tester.tap(find.byTooltip('Close actions'));
    await tester.pumpAndSettle();

    expect(find.text('Top actions'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.pump();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, 'v'.codeUnits);
  });
}
