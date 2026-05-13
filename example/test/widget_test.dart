import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'support/fake_pty_backend.dart';
import 'support/memory_app_preferences_repository.dart';
import 'support/memory_profile_repository.dart';

class _EventfulPtyBackend extends FakePtyBackend {
  final Map<String, List<PtyEvent>> _queuedEvents = <String, List<PtyEvent>>{};

  void enqueueExit(String sessionId, {int? code}) {
    _queuedEvents
        .putIfAbsent(sessionId, () => <PtyEvent>[])
        .add(
          PtyEvent(
            kind: 'exit',
            sessionId: sessionId,
            payload: code == null ? null : <String, Object?>{'code': code},
          ),
        );
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    final events = super.pollEvents(sessionId);
    final queued = _queuedEvents.remove(sessionId);
    if (queued == null) {
      return events;
    }
    return <PtyEvent>[...events, ...queued];
  }
}

Future<void> _pumpShellScreen(
  WidgetTester tester, {
  required PtySessionBackend bindings,
  required MemoryProfileRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
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

Future<void> _openCommandMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await tester.pumpAndSettle();
}

Future<void> _sendMetaShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.sendKeyDownEvent(key, platform: 'macos');
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(key, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.pump();
}

Future<void> _sendMetaShiftShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.shiftLeft,
    platform: 'macos',
  );
  await tester.sendKeyDownEvent(key, platform: 'macos');
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(key, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.pump();
}

Future<void> _sendControlShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  required String platform,
}) async {
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    platform: platform,
  );
  await tester.sendKeyDownEvent(key, platform: platform);
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(key, platform: platform);
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    platform: platform,
  );
  await tester.pump();
}

void _expectSelectedTab(WidgetTester tester, String sessionId) {
  expect(
    tester.getSemantics(find.bySemanticsLabel('shell-tab-$sessionId')),
    matchesSemantics(
      label: 'shell-tab-$sessionId',
      hasSelectedState: true,
      isSelected: true,
      isButton: true,
    ),
  );
}

void main() {
  testWidgets('shell screen can open a second tab from the command menu', (
    tester,
  ) async {
    await _pumpShellScreen(
      tester,
      bindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.bySemanticsLabel('shell-tab-1'), findsOneWidget);
    await _openCommandMenu(tester);
    await tester.tap(find.text('New tab'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('shell-tab-2'), findsOneWidget);
    _expectSelectedTab(tester, '2');
  });

  testWidgets(
    'command menu split right opens a second pane in the active tab',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      expect(find.bySemanticsLabel('shell-tab-1'), findsOneWidget);
      expect(find.bySemanticsLabel('shell-tab-2'), findsNothing);
      expect(find.byType(TerminalViewport), findsOneWidget);

      await _openCommandMenu(tester);
      await tester.ensureVisible(find.text('Split right'));
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('shell-tab-1'), findsOneWidget);
      expect(find.bySemanticsLabel('shell-tab-2'), findsNothing);
      expect(find.byType(TerminalViewport), findsNWidgets(2));
      expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);
      expect(find.byKey(const Key('shell-pane-2')), findsOneWidget);
      expect(find.byKey(const Key('shell-pane-dim-1')), findsOneWidget);
      expect(find.byKey(const Key('shell-pane-dim-2')), findsNothing);
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets('command menu paste sends clipboard text to the active session', (
    tester,
  ) async {
    const clipboardText = '你好, 世界🌟';
    final fakeBindings = FakePtyBackend();

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardText};
        }
        if (methodCall.method == 'Clipboard.setData') {
          return null;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.text('Paste clipboard'));
    await tester.tap(find.text('Paste clipboard'));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, utf8.encode(clipboardText));
  });

  testWidgets('command menu copy writes the selection to the clipboard', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    String? copiedText;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': copiedText};
        }
        if (methodCall.method == 'Clipboard.setData') {
          copiedText = (methodCall.arguments as Map)['text'] as String?;
          return null;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    final renderViewport = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final selectionStart = renderViewport.localToGlobal(const Offset(1, 9));
    await tester.dragFrom(selectionStart, const Offset(300, 0));
    await tester.pump();

    await _openCommandMenu(tester);
    await tester.tap(find.text('Copy selection'));
    await tester.pumpAndSettle();

    expect(copiedText, 'flutterm ready');
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'command-shift-c copy mode extends selection and copies with enter',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      String? copiedText;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': copiedText};
          }
          if (methodCall.method == 'Clipboard.setData') {
            copiedText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      fakeBindings.setFrame(1, {
        'rows': [
          {'index': 0, 'text': 'alpha beta', 'style_runs': const []},
        ],
        'cursor': {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      await tester.pump(const Duration(milliseconds: 40));

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyC);

      expect(find.text('Copy mode'), findsOneWidget);

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.arrowRight,
        platform: 'macos',
      );
      await tester.pump();
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.arrowRight,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.enter,
        platform: 'macos',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter, platform: 'macos');
      await tester.pump();

      expect(copiedText, 'al');
      expect(find.text('Copy mode'), findsNothing);
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'command-shift-p opens the command menu without leaking input',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
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
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'command-t opens another tab without opening the command menu',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      expect(find.bySemanticsLabel('shell-tab-1'), findsOneWidget);

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT, platform: 'macos');
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();

      expect(find.text('Top actions'), findsNothing);
      expect(find.bySemanticsLabel('shell-tab-2'), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'repeated command-t is swallowed by the shell shortcut handler',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT, platform: 'macos');
      await tester.pumpAndSettle();
      await tester.sendKeyRepeatEvent(
        LogicalKeyboardKey.keyT,
        platform: 'macos',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();

      expect(find.bySemanticsLabel('shell-tab-2'), findsOneWidget);
      expect(find.bySemanticsLabel('shell-tab-3'), findsNothing);
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'control-t on macOS stays in terminal input instead of opening a new tab',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      expect(find.bySemanticsLabel('shell-tab-1'), findsOneWidget);
      expect(find.bySemanticsLabel('shell-tab-2'), findsNothing);

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendControlShortcut(
        tester,
        LogicalKeyboardKey.keyT,
        platform: 'macos',
      );

      expect(find.bySemanticsLabel('shell-tab-2'), findsNothing);
      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, equals(const [0x14]));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'control-t on non-macOS still opens another tab',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      expect(find.bySemanticsLabel('shell-tab-1'), findsOneWidget);

      await _sendControlShortcut(
        tester,
        LogicalKeyboardKey.keyT,
        platform: 'linux',
      );

      expect(find.text('Top actions'), findsNothing);
      expect(find.bySemanticsLabel('shell-tab-2'), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'command-number activates the matching tab without input leak',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openCommandMenu(tester);
      await tester.tap(find.text('New tab'));
      await tester.pumpAndSettle();
      _expectSelectedTab(tester, '2');

      await _sendMetaShortcut(tester, LogicalKeyboardKey.digit1);

      _expectSelectedTab(tester, '1');
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'command-q requests quit confirmation without leaking input',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      final windowBridgeCalls = <MethodCall>[];
      const channel = MethodChannel('app/window_bridge');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        windowBridgeCalls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyQ);

      expect(
        windowBridgeCalls.map((call) => call.method),
        contains('requestQuitConfirmation'),
      );
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'command-semicolon autocompletes from visible terminal words',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      fakeBindings.setFrame(1, {
        'rows': [
          {
            'index': 0,
            'text': 'git checkout feature/login',
            'style_runs': const [],
          },
          {'index': 1, 'text': 'git che', 'style_runs': const []},
        ],
        'cursor': {'row': 1, 'col': 7, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      await tester.pump(const Duration(milliseconds: 40));

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendMetaShortcut(tester, LogicalKeyboardKey.semicolon);

      expect(
        find.byKey(const Key('terminal-autocomplete-menu')),
        findsOneWidget,
      );
      expect(find.text('checkout'), findsOneWidget);

      await tester.tap(find.text('checkout'));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, utf8.encode('ckout'));
      expect(find.byKey(const Key('terminal-autocomplete-menu')), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('command menu hotkey window invokes the window bridge', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final windowBridgeCalls = <MethodCall>[];
    const channel = MethodChannel('app/window_bridge');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      windowBridgeCalls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.text('Hotkey window'));
    await tester.tap(find.text('Hotkey window'));
    await tester.pumpAndSettle();

    expect(
      windowBridgeCalls.map((call) => call.method),
      contains('toggleHotkeyWindow'),
    );
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'command-w closes the active tab without leaking input',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyW);

      expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
      expect(find.byType(TerminalViewport), findsNothing);
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'command-comma opens defaults and returns keyboard to terminal',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await _sendMetaShortcut(tester, LogicalKeyboardKey.comma);

      expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);

      await tester.tap(find.byTooltip('Close defaults'));
      await tester.pumpAndSettle();

      await _sendControlShortcut(
        tester,
        LogicalKeyboardKey.keyT,
        platform: 'macos',
      );

      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, equals(const [0x14]));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('closing the last tab can recover from the empty state', (
    tester,
  ) async {
    await _pumpShellScreen(
      tester,
      bindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byTooltip('Close Local Shell'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);
    expect(find.text('Shell workspace is idle'), findsOneWidget);
    expect(
      find.text(
        'The last session has closed. Open a new tab to keep working in the shell workspace.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('New Tab'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('shell-tab-2'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.text('Back in shell'), findsOneWidget);
  });

  testWidgets('terminal exit returns the shell to the empty state', (
    tester,
  ) async {
    final eventfulBindings = _EventfulPtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: eventfulBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.byType(TerminalViewport), findsOneWidget);

    eventfulBindings.enqueueExit('1');
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);
    expect(find.text('Shell workspace is idle'), findsOneWidget);
    expect(
      find.text(
        'The last session has closed. Open a new tab to keep working in the shell workspace.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shell terminal scrollbar drag sends absolute scroll requests', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    fakeBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': 'flutterm ready', 'style_runs': const []},
      ],
      'cursor': {'row': 0, 'col': 4, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 120,
    });
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(terminalScrollbarThumbKey), findsOneWidget);

    await tester.drag(
      find.byKey(terminalScrollbarThumbKey),
      const Offset(0, -60),
    );
    await tester.pump();

    expect(fakeBindings.scrollToCalls, isNotEmpty);
    expect(fakeBindings.scrollToCalls.last.first, 1);
    expect(fakeBindings.scrollToCalls.last.last, greaterThan(0));
  });

  testWidgets(
    'shell search opens from the command menu and scrolls to matches',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      fakeBindings.setSearchMatches(1, 'needle', [
        {'row': 42, 'start_col': 5, 'end_col': 11, 'text': 'older needle'},
        {'row': 3, 'start_col': 0, 'end_col': 6, 'text': 'needle visible'},
      ]);

      await _openCommandMenu(tester);
      await tester.ensureVisible(find.text('Search scrollback'));
      await tester.tap(find.text('Search scrollback'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();

      expect(find.text('1 of 2'), findsOneWidget);
      expect(fakeBindings.searchCalls.last, [1, 'needle']);
      expect(fakeBindings.scrollToCalls.last, [1, 42]);

      await tester.tap(find.byKey(const Key('terminal-search-next')));
      await tester.pumpAndSettle();

      expect(find.text('2 of 2'), findsOneWidget);
      expect(fakeBindings.scrollToCalls.last, [1, 3]);

      await tester.tap(find.byKey(const Key('terminal-search-close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('terminal-search-bar')), findsNothing);
      expect(fakeBindings.scrollToCalls.last, [1, 0]);
    },
  );
}
