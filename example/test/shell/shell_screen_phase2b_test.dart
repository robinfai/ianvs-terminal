import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

Future<void> pumpShellScreen(
  WidgetTester tester, {
  required FakePtyBackend fakeBindings,
  required MemoryProfileRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(fakeBindings),
        profileRepositoryProvider.overrideWithValue(repository),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
      ],
      child: const MaterialApp(home: ShellScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> sendControlShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  required String platform,
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    platform: platform,
  );
  if (shift) {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: platform,
    );
  }
  await tester.sendKeyDownEvent(key, platform: platform);
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(key, platform: platform);
  if (shift) {
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: platform,
    );
  }
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    platform: platform,
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'command-shift-p opens the hyper command menu with secondary tools',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
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
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();

      expect(find.text('Top actions'), findsOneWidget);
      expect(find.text('App actions'), findsOneWidget);
      expect(find.text('Session actions'), findsOneWidget);
      expect(find.text('Defaults & appearance'), findsOneWidget);
      expect(find.text('Profiles…'), findsOneWidget);
      expect(
        find.textContaining('Open the default shell profile.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Copy the current selection.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Paste clipboard into the shell.'),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('launcher close restores terminal viewport focus', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Top actions'), findsOneWidget);

    await tester.tap(find.byTooltip('Close actions'));
    await tester.pumpAndSettle();

    expect(find.text('Top actions'), findsNothing);
    expect(find.byKey(const Key('shell-terminal-surface')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.pump();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, 'v'.codeUnits);
  });

  testWidgets(
    'control-shift-p opens the launcher on non-macOS',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await sendControlShortcut(
        tester,
        LogicalKeyboardKey.keyP,
        platform: 'linux',
        shift: true,
      );

      expect(find.text('Top actions'), findsOneWidget);
      expect(find.text('App actions'), findsOneWidget);
      expect(find.text('Session actions'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
