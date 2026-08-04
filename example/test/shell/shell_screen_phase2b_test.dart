import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ui/app_ui.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
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
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(null),
        ),
      ],
      child: MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.light),
        darkTheme: buildIanvsTerminalTheme(Brightness.dark),
        home: const ShellScreen(),
      ),
    ),
  );
  await tester.pump();
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

      expect(find.text('Command palette'), findsOneWidget);
      expect(find.text('App actions'), findsOneWidget);
      expect(find.text('Session actions'), findsOneWidget);
      expect(find.text('Defaults & appearance'), findsOneWidget);
      expect(find.text('Profiles…'), findsOneWidget);
      expect(find.byKey(const Key('shell-top-new-tab')), findsOneWidget);
      expect(find.textContaining('Copy the current selection.'), findsNothing);
      expect(find.byKey(const Key('shell-clear-scrollback')), findsOneWidget);
      expect(find.byKey(const Key('shell-top-paste-clipboard')), findsNothing);
      expect(find.byKey(const Key('shell-new-tab-at-folder')), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('command menu groups top actions and sections by purpose', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('shell-search-scrollback-top')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell-top-paste-clipboard')), findsNothing);
    expect(find.byKey(const Key('shell-top-new-tab')), findsOneWidget);
    expect(find.byKey(const Key('shell-top-toolbelt')), findsOneWidget);
    expect(find.byKey(const Key('shell-split-right')), findsNothing);
    expect(find.text('Pane actions'), findsNothing);

    final appTop = tester.getTopLeft(find.text('App actions')).dy;
    final sessionTop = tester.getTopLeft(find.text('Session actions')).dy;
    final toolsTop = tester.getTopLeft(find.text('Shell tools')).dy;

    expect(appTop, lessThan(sessionTop));
    expect(sessionTop, lessThan(toolsTop));
  });

  testWidgets('command menu does not repeat pinned top actions in sections', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('shell-search-scrollback-top')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell-top-paste-clipboard')), findsNothing);
    expect(find.byKey(const Key('shell-top-new-tab')), findsOneWidget);
    expect(find.byKey(const Key('shell-top-toolbelt')), findsOneWidget);
    expect(find.byKey(const Key('shell-split-right')), findsNothing);

    expect(find.text('Search terminal output'), findsOneWidget);
    expect(find.byKey(const Key('shell-paste-clipboard')), findsNothing);
    expect(find.byKey(const Key('shell-new-tab')), findsNothing);
    expect(find.byKey(const Key('shell-toolbelt')), findsNothing);
  });

  testWidgets('command menu hides deferred and tab-context actions', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();

    for (final hiddenLabel in <String>[
      'Enable bell notifications',
      'Hotkey window',
      'Dynamic profiles',
      'Zoom active pane',
      'Focus next pane',
      'Focus previous pane',
      'Copy selection',
      'Copy mode',
      'Annotations',
      'Captured output',
      'Advanced paste',
      'Paste history',
      'Shell integration',
      'Select command output',
      'Autocomplete',
      'Auto Composer',
      'tmux integration',
      'Coprocess',
      'Password manager',
      'Reopen closed pane',
      'Split right',
      'Split down',
    ]) {
      expect(find.text(hiddenLabel), findsNothing);
    }
  });

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
    expect(find.text('Command palette'), findsOneWidget);

    await tester.tap(find.byTooltip('Close command palette'));
    await tester.pumpAndSettle();

    expect(find.text('Command palette'), findsNothing);
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

      expect(find.text('Command palette'), findsOneWidget);
      expect(find.text('App actions'), findsOneWidget);
      expect(find.text('Session actions'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
