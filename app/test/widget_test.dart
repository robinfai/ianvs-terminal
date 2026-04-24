import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/render_terminal_viewport.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ffi/flutterm_core.dart';

import 'support/fake_core_bindings.dart';
import 'support/memory_app_preferences_repository.dart';
import 'support/memory_profile_repository.dart';

class _EventfulCoreBindings implements CoreBindings {
  _EventfulCoreBindings(this._delegate);

  final FakeCoreBindings _delegate;
  final Map<int, List<Map<String, Object?>>> _queuedEvents = {};

  void enqueueExit(String sessionId, {int? code}) {
    _queuedEvents.putIfAbsent(int.parse(sessionId), () => []).add({
      'kind': 'exit',
      'session_id': int.parse(sessionId),
      'payload': code == null ? null : {'code': code},
    });
  }

  @override
  int ping() => _delegate.ping();

  @override
  int sessionCreate(ffi.Pointer<Utf8> profileJson) =>
      _delegate.sessionCreate(profileJson);

  @override
  int sessionClose(int sessionId) => _delegate.sessionClose(sessionId);

  @override
  ffi.Pointer<Utf8> sessionPollEventsJson(int sessionId) {
    final delegatePointer = _delegate.sessionPollEventsJson(sessionId);
    if (delegatePointer == ffi.nullptr) {
      final queued = _queuedEvents.remove(sessionId);
      if (queued == null) {
        return ffi.nullptr;
      }
      return jsonEncode(queued).toNativeUtf8();
    }

    try {
      final events =
          (jsonDecode(delegatePointer.toDartString()) as List<dynamic>)
              .cast<Map<String, Object?>>();
      final queued = _queuedEvents.remove(sessionId);
      if (queued != null) {
        events.addAll(queued);
      }
      return jsonEncode(events).toNativeUtf8();
    } finally {
      _delegate.stringFree(delegatePointer);
    }
  }

  @override
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight,
  ) => _delegate.sessionResize(sessionId, cols, rows, pixelWidth, pixelHeight);

  @override
  int sessionScroll(int sessionId, int deltaLines) =>
      _delegate.sessionScroll(sessionId, deltaLines);

  @override
  int sessionScrollTo(int sessionId, int offset) =>
      _delegate.sessionScrollTo(sessionId, offset);

  @override
  ffi.Pointer<Utf8> sessionSearchJson(int sessionId, ffi.Pointer<Utf8> query) =>
      _delegate.sessionSearchJson(sessionId, query);

  @override
  ffi.Pointer<Utf8> sessionTakeFrameDiffJson(int sessionId) =>
      _delegate.sessionTakeFrameDiffJson(sessionId);

  @override
  int sessionWrite(int sessionId, ffi.Pointer<ffi.Uint8> bytes, int length) =>
      _delegate.sessionWrite(sessionId, bytes, length);

  @override
  void stringFree(ffi.Pointer<Utf8> value) => malloc.free(value);
}

Future<void> _pumpShellScreen(
  WidgetTester tester, {
  required CoreBindings bindings,
  required MemoryProfileRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(bindings),
        ),
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
      bindings: FakeCoreBindings(),
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

  testWidgets('command menu paste sends clipboard text to the active session', (
    tester,
  ) async {
    const clipboardText = '你好, 世界🌟';
    final fakeBindings = FakeCoreBindings();

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
    final fakeBindings = FakeCoreBindings();
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

  testWidgets('command-shift-p opens the command menu without leaking input', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();

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
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();

    expect(find.text('Top actions'), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('command-t opens another tab without opening the command menu', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();

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
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();

    expect(find.text('Top actions'), findsNothing);
    expect(find.bySemanticsLabel('shell-tab-2'), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('command-q requests quit confirmation without leaking input', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();
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
  });

  testWidgets('command-w closes the active tab without leaking input', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();

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
  });

  testWidgets('command-comma opens defaults and returns keyboard to terminal', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();

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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.pump();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, utf8.encode('v'));
  });

  testWidgets('closing the last tab can recover from the empty state', (
    tester,
  ) async {
    await _pumpShellScreen(
      tester,
      bindings: FakeCoreBindings(),
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
    final fakeBindings = FakeCoreBindings();
    final eventfulBindings = _EventfulCoreBindings(fakeBindings);

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
    final fakeBindings = FakeCoreBindings();

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
      final fakeBindings = FakeCoreBindings();

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
