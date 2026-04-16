import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
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
  ffi.Pointer<Utf8> sessionTakeFrameDiffJson(int sessionId) =>
      _delegate.sessionTakeFrameDiffJson(sessionId);

  @override
  int sessionWrite(int sessionId, ffi.Pointer<ffi.Uint8> bytes, int length) =>
      _delegate.sessionWrite(sessionId, bytes, length);

  @override
  void stringFree(ffi.Pointer<Utf8> value) => malloc.free(value);
}

void main() {
  bool isTabSelected(WidgetTester tester, String label) {
    return tester
        .widget<InputChip>(find.widgetWithText(InputChip, label))
        .selected;
  }

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

  testWidgets('shell screen can open tabs from profiles', (tester) async {
    final fakeBindings = FakeCoreBindings();
    final repository = MemoryProfileRepository(
      TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultTerminalProfile()],
      ),
    );

    await pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      repository: repository,
    );

    expect(find.text('Local Shell'), findsWidgets);
    await tester.tap(find.text('Local Shell').first);
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsWidgets);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets(
    'shell screen Paste button sends clipboard text to the active session',
    (tester) async {
      const clipboardText = '你好, 世界🌟';
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );

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

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );

      expect(find.text('Paste'), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, utf8.encode(clipboardText));
    },
  );

  testWidgets('shell screen Paste button preserves multiline clipboard text', (
    tester,
  ) async {
    const clipboardText = 'line one\nline two\nline three';
    final fakeBindings = FakeCoreBindings();
    final repository = MemoryProfileRepository(
      TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultTerminalProfile()],
      ),
    );

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

    await pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      repository: repository,
    );

    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, utf8.encode(clipboardText));
  });

  testWidgets('shell screen Paste button ignores empty clipboard text', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();
    final repository = MemoryProfileRepository(
      TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultTerminalProfile()],
      ),
    );

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': ''};
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

    await pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      repository: repository,
    );

    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'shell screen Copy button writes the selected text to the clipboard',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );
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

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byType(TerminalViewport), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(copiedText, isNull);

      final viewportTopLeft = tester.getTopLeft(find.byType(TerminalViewport));
      final selectionStart = viewportTopLeft + const Offset(1, 9);
      await tester.dragFrom(selectionStart, const Offset(300, 0));
      await tester.pump();

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copiedText, 'flutterm ready');
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets('shell screen Copy button ignores an empty selection', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();
    final repository = MemoryProfileRepository(
      TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultTerminalProfile()],
      ),
    );
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

    await pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      repository: repository,
    );

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copiedText, isNull);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('shell screen Copy button preserves multiline selection text', (
    tester,
  ) async {
    final fakeBindings = FakeCoreBindings();
    final repository = MemoryProfileRepository(
      TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultTerminalProfile()],
      ),
    );
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

    await pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      repository: repository,
    );

    final container = tester
        .widget<UncontrolledProviderScope>(
          find.byType(UncontrolledProviderScope).first,
        )
        .container;
    final sessionState = container.read(sessionControllerProvider);
    final sessionId = sessionState.activeSessionId!;

    fakeBindings.setFrame(int.parse(sessionId), {
      'rows': const [
        {'index': 0, 'text': 'alpha', 'style_runs': []},
        {'index': 1, 'text': 'beta', 'style_runs': []},
        {'index': 2, 'text': 'gamma', 'style_runs': []},
      ],
      'cursor': const {'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': const [
        {'start': 0, 'end': 3},
      ],
      'scrollback_offset': 0,
    });
    await tester.pumpAndSettle();

    final viewportTopLeft = tester.getTopLeft(find.byType(TerminalViewport));
    final selectionStart = viewportTopLeft + const Offset(10, 9);
    final selectionEnd = viewportTopLeft + const Offset(18, 45);
    final gesture = await tester.startGesture(selectionStart);
    await tester.pump();
    await gesture.moveTo(selectionEnd);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copiedText, 'alpha\nbeta\ng');
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'shell screen Copy button preserves reverse multiline selection text',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );
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

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final sessionState = container.read(sessionControllerProvider);
      final sessionId = sessionState.activeSessionId!;

      fakeBindings.setFrame(int.parse(sessionId), {
        'rows': const [
          {'index': 0, 'text': 'alpha', 'style_runs': []},
          {'index': 1, 'text': 'beta', 'style_runs': []},
          {'index': 2, 'text': 'gamma', 'style_runs': []},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const [
          {'start': 0, 'end': 3},
        ],
        'scrollback_offset': 0,
      });
      await tester.pumpAndSettle();

      final viewportTopLeft = tester.getTopLeft(find.byType(TerminalViewport));
      final selectionStart = viewportTopLeft + const Offset(18, 45);
      final selectionEnd = viewportTopLeft + const Offset(10, 9);
      final gesture = await tester.startGesture(selectionStart);
      await tester.pump();
      await gesture.moveTo(selectionEnd);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copiedText, 'alpha\nbeta\ng');
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets(
    'shell screen Copy button clamps a multiline selection past row ends',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );
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

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final sessionState = container.read(sessionControllerProvider);
      final sessionId = sessionState.activeSessionId!;

      fakeBindings.setFrame(int.parse(sessionId), {
        'rows': const [
          {'index': 0, 'text': 'abc', 'style_runs': []},
          {'index': 1, 'text': 'xy', 'style_runs': []},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const [
          {'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
      });
      await tester.pumpAndSettle();

      final viewportTopLeft = tester.getTopLeft(find.byType(TerminalViewport));
      final selectionStart = viewportTopLeft + const Offset(18, 9);
      final selectionEnd = viewportTopLeft + const Offset(220, 27);
      final gesture = await tester.startGesture(selectionStart);
      await tester.pump();
      await gesture.moveTo(selectionEnd);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copiedText, 'bc\nxy');
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets(
    'shell screen Copy button preserves asymmetric multiline column ranges',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );
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

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final sessionState = container.read(sessionControllerProvider);
      final sessionId = sessionState.activeSessionId!;

      fakeBindings.setFrame(int.parse(sessionId), {
        'rows': const [
          {'index': 0, 'text': 'abcde', 'style_runs': []},
          {'index': 1, 'text': 'vwxyz', 'style_runs': []},
          {'index': 2, 'text': 'mnopq', 'style_runs': []},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const [
          {'start': 0, 'end': 3},
        ],
        'scrollback_offset': 0,
      });
      await tester.pumpAndSettle();

      final viewportTopLeft = tester.getTopLeft(find.byType(TerminalViewport));
      final selectionStart = viewportTopLeft + const Offset(42, 9);
      final selectionEnd = viewportTopLeft + const Offset(34, 45);
      final gesture = await tester.startGesture(selectionStart);
      await tester.pump();
      await gesture.moveTo(selectionEnd);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copiedText, 'de\nvwxyz\nmn');
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets(
    'shell screen Copy button copies block selections from Alt-drag',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );
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

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final sessionState = container.read(sessionControllerProvider);
      final sessionId = sessionState.activeSessionId!;

      fakeBindings.setFrame(int.parse(sessionId), {
        'rows': const [
          {'index': 0, 'text': 'abc', 'style_runs': []},
          {'index': 1, 'text': 'vwxyz', 'style_runs': []},
          {'index': 2, 'text': 'mn', 'style_runs': []},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const [
          {'start': 0, 'end': 3},
        ],
        'scrollback_offset': 0,
      });
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);

      final viewportTopLeft = tester.getTopLeft(find.byType(TerminalViewport));
      final selectionStart = viewportTopLeft + const Offset(18, 9);
      final selectionEnd = viewportTopLeft + const Offset(50, 45);
      final gesture = await tester.startGesture(selectionStart);
      await tester.pump();
      await gesture.moveTo(selectionEnd);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copiedText, 'bc\nwx\nn');
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets(
    'shell screen forwards scroll wheel deltas to the active session',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );

      final viewport = find.byType(TerminalViewport);
      expect(viewport, findsOneWidget);
      expect(fakeBindings.scrollCalls, isEmpty);

      final center = tester.getCenter(viewport);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, -40)),
      );
      await tester.pump();

      expect(fakeBindings.scrollCalls, isNotEmpty);
      expect(fakeBindings.scrollCalls.single[1], isNot(0));
    },
  );

  testWidgets(
    'shell screen repaints visible rows after scrollback frame updates',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      fakeBindings.setFrame(int.parse(sessionId), {
        'rows': const [
          {'index': 0, 'text': 'visible line 1', 'style_runs': []},
          {'index': 1, 'text': 'visible line 2', 'style_runs': []},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const [
          {'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .single;
      expect(
        renderObject.debugLastPaintedRowTexts,
        equals(['visible line 1', 'visible line 2']),
      );

      final center = tester.getCenter(find.byType(TerminalViewport));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, -40)),
      );

      fakeBindings.setFrame(int.parse(sessionId), {
        'rows': const [
          {'index': 0, 'text': 'scrolled line 9', 'style_runs': []},
          {'index': 1, 'text': 'scrolled line 10', 'style_runs': []},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const [
          {'start': 0, 'end': 2},
        ],
        'scrollback_offset': 8,
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(fakeBindings.scrollCalls, isNotEmpty);
      expect(
        renderObject.debugLastPaintedRowTexts,
        equals(['scrolled line 9', 'scrolled line 10']),
      );
    },
  );

  testWidgets(
    'shell screen forwards layout resize changes to the active session',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );

      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );

      expect(fakeBindings.resizeCalls, isNotEmpty);
      final initialCall = List<int>.from(fakeBindings.resizeCalls.last);

      await tester.binding.setSurfaceSize(const Size(1100, 760));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(fakeBindings.resizeCalls.length, greaterThan(1));
      final resizedCall = fakeBindings.resizeCalls.last;
      expect(resizedCall[0], equals(initialCall[0]));
      expect(resizedCall, isNot(equals(initialCall)));
    },
  );

  testWidgets(
    'shell screen repaints visible rows after layout resize frame updates',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );

      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: repository,
      );

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      fakeBindings.setFrame(int.parse(sessionId), {
        'rows': const [
          {'index': 0, 'text': 'before resize 1', 'style_runs': []},
          {'index': 1, 'text': 'before resize 2', 'style_runs': []},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const [
          {'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .single;
      expect(
        renderObject.debugLastPaintedRowTexts,
        equals(['before resize 1', 'before resize 2']),
      );

      final initialResizeCallCount = fakeBindings.resizeCalls.length;

      await tester.binding.setSurfaceSize(const Size(1100, 760));
      await tester.pump();

      fakeBindings.setFrame(int.parse(sessionId), {
        'rows': const [
          {'index': 0, 'text': 'after resize 1', 'style_runs': []},
          {'index': 1, 'text': 'after resize 2', 'style_runs': []},
          {'index': 2, 'text': 'after resize 3', 'style_runs': []},
        ],
        'cursor': const {'row': 1, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 30,
        'viewport_cols': 100,
        'dirty_ranges': const [
          {'start': 0, 'end': 3},
        ],
        'scrollback_offset': 0,
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(
        fakeBindings.resizeCalls.length,
        greaterThan(initialResizeCallCount),
      );
      expect(
        renderObject.debugLastPaintedRowTexts,
        equals(['after resize 1', 'after resize 2', 'after resize 3']),
      );
    },
  );

  testWidgets(
    'shell screen returns to the empty state after the last session exits',
    (tester) async {
      final fakeDelegate = FakeCoreBindings();
      final bindings = _EventfulCoreBindings(fakeDelegate);
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
              TerminalCoreClient(bindings),
            ),
            profileRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: ShellScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      bindings.enqueueExit(sessionId, code: 0);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNothing);
      expect(find.text('Create a shell to get started'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Paste'), findsNothing);
      expect(find.text('New Tab'), findsOneWidget);
    },
  );

  testWidgets(
    'shell screen can recover from empty state after the last session exits',
    (tester) async {
      final fakeDelegate = FakeCoreBindings();
      final bindings = _EventfulCoreBindings(fakeDelegate);
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
              TerminalCoreClient(bindings),
            ),
            profileRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: ShellScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      bindings.enqueueExit(sessionId, code: 0);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNothing);
      expect(find.text('Create a shell to get started'), findsOneWidget);
      expect(find.text('New Tab'), findsOneWidget);

      await tester.tap(find.text('New Tab'));
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Local Shell'), findsOneWidget);
      expect(find.text('Create a shell to get started'), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
    },
  );

  testWidgets(
    'shell screen keeps the active tab focused when another session exits',
    (tester) async {
      final fakeDelegate = FakeCoreBindings();
      final bindings = _EventfulCoreBindings(fakeDelegate);
      final primaryProfile = defaultTerminalProfile().copyWith(name: 'Shell A');
      final secondaryProfile = defaultTerminalProfile().copyWith(
        id: 'shell-b',
        name: 'Shell B',
      );
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: primaryProfile.id,
          profiles: [primaryProfile, secondaryProfile],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            terminalCoreClientProvider.overrideWithValue(
              TerminalCoreClient(bindings),
            ),
            profileRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: ShellScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final firstSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      await tester.tap(find.widgetWithText(ListTile, 'Shell B'));
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNWidgets(2));
      expect(isTabSelected(tester, 'Shell B'), isTrue);

      bindings.enqueueExit(firstSessionId, code: 0);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, 'Shell A'), findsNothing);
      expect(find.widgetWithText(InputChip, 'Shell B'), findsOneWidget);
      expect(isTabSelected(tester, 'Shell B'), isTrue);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
    },
  );

  testWidgets(
    'shell screen focuses the remaining tab when the active session exits',
    (tester) async {
      final fakeDelegate = FakeCoreBindings();
      final bindings = _EventfulCoreBindings(fakeDelegate);
      final primaryProfile = defaultTerminalProfile().copyWith(name: 'Shell A');
      final secondaryProfile = defaultTerminalProfile().copyWith(
        id: 'shell-b',
        name: 'Shell B',
      );
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: primaryProfile.id,
          profiles: [primaryProfile, secondaryProfile],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            terminalCoreClientProvider.overrideWithValue(
              TerminalCoreClient(bindings),
            ),
            profileRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: ShellScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Shell B'));
      await tester.pumpAndSettle();

      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      final activeSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      expect(find.byType(InputChip), findsNWidgets(2));
      expect(isTabSelected(tester, 'Shell B'), isTrue);

      bindings.enqueueExit(activeSessionId, code: 0);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, 'Shell B'), findsNothing);
      expect(find.widgetWithText(InputChip, 'Shell A'), findsOneWidget);
      expect(isTabSelected(tester, 'Shell A'), isTrue);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
    },
  );
}
