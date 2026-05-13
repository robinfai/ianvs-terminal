import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/paste_history_repository.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'support/fake_pty_backend.dart';
import 'support/memory_app_preferences_repository.dart';
import 'support/memory_paste_history_repository.dart';
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
  PasteHistoryRepository? pasteHistoryRepository,
  ShellNotificationSender? notificationSender,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(repository),
        pasteHistoryRepositoryProvider.overrideWithValue(
          pasteHistoryRepository ?? MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        if (notificationSender != null)
          shellNotificationSenderProvider.overrideWithValue(notificationSender),
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

  testWidgets('hovering a split pane activates it without a click', (
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

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.text('Split right'));
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-dim-1')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-dim-2')), findsNothing);

    final pointer = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byKey(const Key('shell-pane-1')))),
    );
    await tester.pump();

    expect(find.byKey(const Key('shell-pane-dim-1')), findsNothing);
    expect(find.byKey(const Key('shell-pane-dim-2')), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);
  });

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

  testWidgets(
    'advanced paste transforms edited clipboard text before sending',
    (tester) async {
      const clipboardText = 'line 1\nline 2\t✓';
      const editedText = 'deploy\npath\t✓';
      const escapedText = r'deploy\npath\t✓';
      final expectedText = '${base64.encode(utf8.encode(escapedText))}\n';
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
      await tester.ensureVisible(find.byKey(const Key('shell-advanced-paste')));
      await tester.tap(find.byKey(const Key('shell-advanced-paste')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('advanced-paste-sheet')), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('advanced-paste-text-field')),
      );
      expect(field.controller?.text, clipboardText);

      await tester.enterText(
        find.byKey(const Key('advanced-paste-text-field')),
        editedText,
      );
      await tester.ensureVisible(
        find.byKey(const Key('advanced-paste-escape')),
      );
      await tester.tap(find.byKey(const Key('advanced-paste-escape')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('advanced-paste-base64')),
      );
      await tester.tap(find.byKey(const Key('advanced-paste-base64')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('advanced-paste-newline')),
      );
      await tester.tap(find.byKey(const Key('advanced-paste-newline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('advanced-paste-send')));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, hasLength(1));
      expect(fakeBindings.writes.single, utf8.encode(expectedText));
    },
  );

  testWidgets('middle click pastes the clipboard when mouse reporting is off', (
    tester,
  ) async {
    const clipboardText = 'middle paste';
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

    final pointer = TestPointer(8, PointerDeviceKind.mouse);
    final center = tester.getCenter(find.byType(TerminalViewport));
    await tester.sendEventToBinding(
      pointer.down(center, buttons: kMiddleMouseButton),
    );
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, utf8.encode(clipboardText));
  });

  testWidgets(
    'command menu paste records text for paste history reuse and persistence',
    (tester) async {
      const clipboardText = 'from clipboard history';
      final fakeBindings = FakePtyBackend();
      final pasteHistoryRepository = MemoryPasteHistoryRepository();

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
        pasteHistoryRepository: pasteHistoryRepository,
      );

      await _openCommandMenu(tester);
      await tester.ensureVisible(find.text('Paste clipboard'));
      await tester.tap(find.text('Paste clipboard'));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, hasLength(1));
      expect(fakeBindings.writes.last, utf8.encode(clipboardText));
      expect(pasteHistoryRepository.document, isNull);

      await _openCommandMenu(tester);
      await tester.ensureVisible(find.text('Paste history'));
      await tester.tap(find.text('Paste history'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('paste-history-sheet')), findsOneWidget);
      expect(find.text(clipboardText), findsOneWidget);

      await tester.tap(find.byKey(const Key('paste-history-persist')));
      await tester.pumpAndSettle();

      expect(pasteHistoryRepository.document?.entries, hasLength(1));
      expect(
        pasteHistoryRepository.document?.entries.single.text,
        clipboardText,
      );

      await tester.tap(find.byKey(const Key('paste-history-entry-0')));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, hasLength(2));
      expect(fakeBindings.writes.last, utf8.encode(clipboardText));
    },
  );

  testWidgets(
    'command-shift-v opens saved paste history without leaking input',
    (tester) async {
      const savedText = 'saved paste';
      final fakeBindings = FakePtyBackend();
      final pasteHistoryRepository = MemoryPasteHistoryRepository(
        PasteHistoryDocument(
          entries: [
            PasteHistoryEntry(
              text: savedText,
              kind: PasteHistoryKind.paste,
              createdAt: DateTime.utc(2026, 5, 14),
            ),
          ],
        ),
      );

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        pasteHistoryRepository: pasteHistoryRepository,
      );

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyV);

      expect(find.byKey(const Key('paste-history-sheet')), findsOneWidget);
      expect(find.text(savedText), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);

      await tester.tap(find.byKey(const Key('paste-history-entry-0')));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, hasLength(1));
      expect(fakeBindings.writes.last, utf8.encode(savedText));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'command-shift-r copies erased text from instant replay',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      String? copiedText;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copiedText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          if (methodCall.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': copiedText};
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
          {'index': 0, 'text': 'important output', 'style_runs': const []},
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
      fakeBindings.setFrame(1, {
        'rows': [
          {'index': 0, 'text': '', 'style_runs': const []},
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
      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyR);

      expect(find.byKey(const Key('instant-replay-sheet')), findsOneWidget);
      expect(find.text('important output'), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);

      await tester.tap(find.byKey(const Key('instant-replay-copy')));
      await tester.pumpAndSettle();

      expect(copiedText, 'important output');
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('password manager sends saved passwords only at prompts', (
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

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.text('Password manager'));
    await tester.tap(find.text('Password manager'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('password-manager-sheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('password-manager-label-field')),
      'staging sudo',
    );
    await tester.enterText(
      find.byKey(const Key('password-manager-password-field')),
      's3cr3t!',
    );
    await tester.tap(find.byKey(const Key('password-manager-add')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('password-manager-send-0')));
    await tester.pumpAndSettle();
    expect(fakeBindings.writes, isEmpty);

    await tester.tap(find.byTooltip('Close password manager'));
    await tester.pumpAndSettle();

    fakeBindings.setFrame(1, {
      'rows': [
        {
          'index': 0,
          'text': '[sudo] password for dev:',
          'style_runs': const [],
        },
      ],
      'cursor': {'row': 0, 'col': 24, 'visible': true},
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

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.text('Password manager'));
    await tester.tap(find.text('Password manager'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('password-manager-send-0')));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes.single, utf8.encode('s3cr3t!\n'));
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
    await tester.ensureVisible(find.text('Copy selection'));
    await tester.tap(find.text('Copy selection'));
    await tester.pumpAndSettle();

    expect(copiedText, 'flutterm ready');
    expect(fakeBindings.writes, isEmpty);

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.text('Paste history'));
    await tester.tap(find.text('Paste history'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('paste-history-sheet')), findsOneWidget);
    expect(find.text('flutterm ready'), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('annotations attach notes to selected terminal text', (
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
    await tester.pump(const Duration(milliseconds: 40));

    final renderViewport = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final selectionStart = renderViewport.localToGlobal(const Offset(1, 9));
    await tester.dragFrom(selectionStart, const Offset(300, 0));
    await tester.pump();

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-annotations')));
    await tester.tap(find.byKey(const Key('shell-annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('annotations-sheet')), findsOneWidget);
    expect(find.text('flutterm ready'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('annotation-note-field')),
      'Check startup output',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('annotation-save')));
    await tester.pumpAndSettle();

    expect(find.text('Check startup output'), findsOneWidget);
    expect(find.byKey(const Key('annotation-entry-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('annotations-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('terminal-annotation-badge-1')),
      findsOneWidget,
    );
    expect(find.text('1 annotation'), findsOneWidget);

    await tester.tap(find.byKey(const Key('terminal-annotation-badge-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('annotation-remove-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('annotations-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-annotation-badge-1')), findsNothing);
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

  testWidgets('shell posts notifications for command completion and bells', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final notifications = <Map<String, String?>>[];

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      notificationSender: ({required title, body, identifier}) async {
        notifications.add({
          'title': title,
          'body': body,
          'identifier': identifier,
        });
      },
    );

    fakeBindings.enqueueEvent(
      1,
      PtyEvent(
        kind: 'shell_hook',
        sessionId: '1',
        payload: const <String, Object?>{
          'hook': 'command_finished',
          'command': 'echo ok',
          'exit_code': 7,
        },
      ),
    );
    fakeBindings.enqueueEvent(1, PtyEvent(kind: 'bell', sessionId: '1'));
    await tester.pump(const Duration(milliseconds: 40));

    expect(notifications, hasLength(2));
    expect(notifications[0]['title'], 'Command finished');
    expect(notifications[0]['body'], contains('echo ok'));
    expect(notifications[0]['body'], contains('Exit code 7'));
    expect(notifications[1]['title'], startsWith('Bell in '));
    expect(notifications[1]['body'], 'The terminal requested attention.');
  });

  testWidgets('inactive session activity posts a notification', (tester) async {
    final fakeBindings = FakePtyBackend();
    final notifications = <Map<String, String?>>[];

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      notificationSender: ({required title, body, identifier}) async {
        notifications.add({
          'title': title,
          'body': body,
          'identifier': identifier,
        });
      },
    );

    await _openCommandMenu(tester);
    await tester.tap(find.text('New tab'));
    await tester.pumpAndSettle();

    fakeBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': 'background build done', 'style_runs': const []},
      ],
      'cursor': {'row': 0, 'col': 21, 'visible': true},
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

    expect(notifications, hasLength(1));
    expect(notifications.single['title'], startsWith('Activity in '));
    expect(notifications.single['body'], 'background build done');
    expect(notifications.single['identifier'], 'flutterm.activity.1');
  });

  testWidgets('profile triggers notify and send text for matching output', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final notifications = <Map<String, String?>>[];
    final profile = defaultTerminalProfile().copyWith(
      triggers: const [
        TerminalProfileTrigger(pattern: 'ERROR [0-9]+'),
        TerminalProfileTrigger(
          pattern: 'Password:',
          action: TerminalProfileTriggerAction.sendText,
          value: 'secret\n',
        ),
      ],
    );

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [profile]),
      ),
      notificationSender: ({required title, body, identifier}) async {
        notifications.add({
          'title': title,
          'body': body,
          'identifier': identifier,
        });
      },
    );

    fakeBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': 'Password:', 'style_runs': const []},
        {'index': 1, 'text': 'ERROR 42 failed', 'style_runs': const []},
      ],
      'cursor': {'row': 1, 'col': 15, 'visible': true},
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

    expect(fakeBindings.writes, hasLength(1));
    expect(fakeBindings.writes.single, utf8.encode('secret\n'));
    expect(notifications, hasLength(1));
    expect(notifications.single['title'], startsWith('Trigger matched in '));
    expect(notifications.single['body'], 'ERROR 42 failed');

    fakeBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': 'Password:', 'style_runs': const []},
        {'index': 1, 'text': 'ERROR 42 failed', 'style_runs': const []},
      ],
      'cursor': {'row': 1, 'col': 15, 'visible': true},
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

    expect(fakeBindings.writes, hasLength(1));
    expect(notifications, hasLength(1));
  });

  testWidgets('captured output lists trigger-matched terminal rows', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final profile = defaultTerminalProfile().copyWith(
      triggers: const [TerminalProfileTrigger(pattern: 'ERROR [0-9]+')],
    );

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [profile]),
      ),
      notificationSender: ({required title, body, identifier}) async {},
    );

    fakeBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': 'INFO ready', 'style_runs': const []},
        {'index': 1, 'text': 'ERROR 42 failed', 'style_runs': const []},
      ],
      'cursor': {'row': 1, 'col': 15, 'visible': true},
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

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-captured-output')));
    await tester.tap(find.byKey(const Key('shell-captured-output')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('captured-output-sheet')), findsOneWidget);
    expect(find.byKey(const Key('captured-output-entry-0')), findsOneWidget);
    expect(find.text('ERROR 42 failed'), findsOneWidget);
    expect(find.textContaining('Pattern ERROR [0-9]+'), findsOneWidget);

    await tester.tap(find.byKey(const Key('captured-output-clear')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('captured-output-entry-0')), findsNothing);
    expect(find.text('No trigger output captured yet.'), findsOneWidget);
  });

  testWidgets('toolbelt opens a sidebar with terminal tool shortcuts', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final profile = defaultTerminalProfile().copyWith(
      triggers: const [TerminalProfileTrigger(pattern: 'ERROR [0-9]+')],
    );

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [profile]),
      ),
      notificationSender: ({required title, body, identifier}) async {},
    );

    fakeBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': 'ERROR 42 failed', 'style_runs': const []},
      ],
      'cursor': {'row': 0, 'col': 15, 'visible': true},
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

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-toolbelt')));
    await tester.tap(find.byKey(const Key('shell-toolbelt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-toolbelt-panel')), findsOneWidget);
    expect(find.text('Toolbelt'), findsOneWidget);
    expect(find.text('1 captured line'), findsOneWidget);
    expect(find.byKey(const Key('toolbelt-captured-output')), findsOneWidget);

    await tester.tap(find.byKey(const Key('toolbelt-captured-output')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('captured-output-sheet')), findsOneWidget);
    expect(find.text('ERROR 42 failed'), findsOneWidget);
  });

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

  testWidgets(
    'command-semicolon autocompletes from shell integration command history',
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
          {'index': 0, 'text': 'git che', 'style_runs': const []},
        ],
        'cursor': {'row': 0, 'col': 7, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: '1',
          payload: const <String, Object?>{
            'hook': 'command_finished',
            'command': 'git checkout feature/login',
            'pwd': '/Users/dev/project',
          },
        ),
      );
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
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('auto composer edits a command with shell history completion', (
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

    fakeBindings.enqueueEvent(
      1,
      PtyEvent(
        kind: 'shell_hook',
        sessionId: '1',
        payload: const <String, Object?>{
          'hook': 'command_finished',
          'command': 'git checkout feature/login',
          'pwd': '/Users/dev/project',
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-auto-composer')));
    await tester.tap(find.byKey(const Key('shell-auto-composer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-auto-composer')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('terminal-auto-composer-field')),
      'git checkout f',
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('terminal-auto-composer-suggestion-feature/login')),
    );
    await tester.pump();

    final composerField = tester.widget<TextField>(
      find.byKey(const Key('terminal-auto-composer-field')),
    );
    expect(composerField.controller?.text, 'git checkout feature/login');

    await tester.tap(find.byKey(const Key('terminal-auto-composer-send')));
    await tester.pumpAndSettle();

    expect(
      fakeBindings.writes.last,
      utf8.encode('git checkout feature/login\n'),
    );
    expect(find.byKey(const Key('terminal-auto-composer')), findsNothing);
  });

  testWidgets('shell integration badge shows current session context', (
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

    fakeBindings.enqueueEvent(
      1,
      PtyEvent(
        kind: 'shell_hook',
        sessionId: '1',
        payload: const <String, Object?>{
          'hook': 'command_finished',
          'command': 'git status',
          'pwd': '/tmp/project',
          'shell': 'zsh',
          'host': 'workstation.local',
          'user': 'dev',
          'exit_code': 0,
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('terminal-session-badge-1')), findsOneWidget);
    expect(find.text('dev@workstation.local'), findsOneWidget);
    expect(find.text('/tmp/project'), findsOneWidget);
    expect(find.text('git status ok'), findsOneWidget);
  });

  testWidgets(
    'shift-command arrows navigate shell integration prompt marks',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: '1',
          payload: const <String, Object?>{
            'hook': 'prompt_started',
            'prompt_scrollback_offset': 9,
            'pwd': '/Users/dev/project',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: '1',
          payload: const <String, Object?>{
            'hook': 'prompt_started',
            'prompt_scrollback_offset': 27,
            'pwd': '/Users/dev/project',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.arrowUp);

      expect(fakeBindings.scrollToCalls.last, [1, 9]);

      fakeBindings.setFrame(1, {
        'rows': [
          {'index': 0, 'text': 'old prompt', 'style_runs': const []},
        ],
        'cursor': {'row': 0, 'col': 10, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 27,
        'scrollback_max_offset': 40,
      });
      await tester.pump(const Duration(milliseconds: 40));

      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.arrowDown);

      expect(fakeBindings.scrollToCalls.last, [1, 9]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell integration utilities expose history directories and prompt marks',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: '1',
          payload: const <String, Object?>{
            'hook': 'command_finished',
            'command': 'git status',
            'pwd': '/tmp/project',
            'shell': 'zsh',
            'host': 'workstation.local',
            'user': 'dev',
            'exit_code': 0,
          },
        ),
      );
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: '1',
          payload: const <String, Object?>{
            'hook': 'prompt_started',
            'prompt_scrollback_offset': 12,
            'pwd': '/tmp/project',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      Future<void> openUtilities() async {
        await _openCommandMenu(tester);
        await tester.ensureVisible(
          find.byKey(const Key('shell-integration-utilities')),
        );
        await tester.tap(find.byKey(const Key('shell-integration-utilities')));
        await tester.pumpAndSettle();
      }

      await openUtilities();

      expect(
        find.byKey(const Key('shell-integration-utilities-sheet')),
        findsOneWidget,
      );
      expect(find.text('Shell Integration'), findsOneWidget);
      expect(find.text('Command History'), findsOneWidget);
      expect(find.text('Recent Directories'), findsOneWidget);
      expect(find.text('Prompt Marks'), findsOneWidget);
      expect(find.text('dev@workstation.local'), findsWidgets);
      expect(find.text('git status'), findsWidgets);
      expect(find.text('/tmp/project'), findsWidgets);
      expect(find.text('Offset 12'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shell-command-history-entry-0')));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes.last, utf8.encode('git status'));

      await openUtilities();
      await tester.tap(find.byKey(const Key('shell-recent-directory-0')));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes.last, utf8.encode('cd /tmp/project'));

      await openUtilities();
      await tester.ensureVisible(find.byKey(const Key('shell-prompt-mark-0')));
      await tester.tap(find.byKey(const Key('shell-prompt-mark-0')));
      await tester.pumpAndSettle();

      expect(fakeBindings.scrollToCalls.last, [1, 12]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('tmux integration starts and drives control mode', (
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

    Future<void> openTmuxIntegration() async {
      await _openCommandMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('shell-tmux-integration')),
      );
      await tester.tap(find.byKey(const Key('shell-tmux-integration')));
      await tester.pumpAndSettle();
    }

    await openTmuxIntegration();

    expect(find.byKey(const Key('tmux-integration-sheet')), findsOneWidget);
    expect(find.text('No tmux control mode detected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tmux-attach-control-mode')));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes.last, utf8.encode('tmux -CC attach\n'));

    Future<void> showTmuxControlMenuFrame() async {
      fakeBindings.setFrame(1, {
        'rows': [
          {
            'index': 0,
            'text': '** tmux mode started **',
            'style_runs': const [],
          },
          {'index': 1, 'text': 'Command Menu', 'style_runs': const []},
          {
            'index': 2,
            'text': 'esc    Detach cleanly.',
            'style_runs': const [],
          },
        ],
        'cursor': {'row': 2, 'col': 22, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 3},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      await tester.pump(const Duration(milliseconds: 40));
    }

    await showTmuxControlMenuFrame();

    await openTmuxIntegration();

    expect(find.text('Control mode detected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tmux-split-right')));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes.last, utf8.encode('split-window -h\n'));

    await showTmuxControlMenuFrame();
    await openTmuxIntegration();
    await tester.ensureVisible(find.byKey(const Key('tmux-command-field')));
    await tester.enterText(
      find.byKey(const Key('tmux-command-field')),
      'list-windows',
    );
    await tester.ensureVisible(find.byKey(const Key('tmux-send-command')));
    await tester.tap(find.byKey(const Key('tmux-send-command')));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes.last, utf8.encode('list-windows\n'));
  });

  testWidgets('coprocess replies to matching terminal output', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    Future<void> openCoprocess() async {
      await _openCommandMenu(tester);
      await tester.ensureVisible(find.byKey(const Key('shell-coprocess')));
      await tester.tap(find.byKey(const Key('shell-coprocess')));
      await tester.pumpAndSettle();
    }

    await openCoprocess();

    expect(find.byKey(const Key('coprocess-sheet')), findsOneWidget);
    expect(find.text('Run Coprocess'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('coprocess-command-field')),
      'presence bot',
    );
    await tester.tap(find.byKey(const Key('coprocess-start')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('terminal-coprocess-indicator-1')),
      findsOneWidget,
    );

    fakeBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': 'Are you there?', 'style_runs': const []},
      ],
      'cursor': {'row': 0, 'col': 14, 'visible': true},
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

    expect(fakeBindings.writes.last, utf8.encode('Yes\n'));

    await openCoprocess();

    expect(find.byKey(const Key('coprocess-active-summary')), findsOneWidget);
    expect(find.text('presence bot'), findsWidgets);
    expect(find.textContaining('lines'), findsOneWidget);
    expect(find.text('Are you there?'), findsWidgets);

    await tester.tap(find.byKey(const Key('coprocess-stop')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('terminal-coprocess-indicator-1')),
      findsNothing,
    );
  });

  testWidgets('dynamic profiles imports iTerm profile JSON', (tester) async {
    final fakeBindings = FakePtyBackend();
    final repository = MemoryProfileRepository(
      TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    );

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: repository,
    );

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-dynamic-profiles')));
    await tester.tap(find.byKey(const Key('shell-dynamic-profiles')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dynamic-profiles-sheet')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('dynamic-profiles-json-field')),
      jsonEncode({
        'Profiles': [
          {
            'Name': 'prod.example.com',
            'Guid': 'prod-host',
            'Custom Command': 'Yes',
            'Command': 'ssh prod.example.com',
            'Tags': ['ssh'],
          },
        ],
      }),
    );
    await tester.tap(find.byKey(const Key('dynamic-profiles-import')));
    await tester.pumpAndSettle();

    final document = await repository.load();
    final imported = document.profiles.singleWhere(
      (profile) => profile.id == 'prod-host',
    );

    expect(find.text('Imported 1 dynamic profile'), findsOneWidget);
    expect(imported.name, 'prod.example.com');
    expect(imported.tags, const ['ssh', 'Dynamic']);
    expect(imported.shell, '/bin/sh');
    expect(imported.args, const ['-lc', 'ssh prod.example.com']);
  });

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

  testWidgets('global search searches all tabs and jumps to a match', (
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

    await _openCommandMenu(tester);
    await tester.tap(find.text('New tab'));
    await tester.pumpAndSettle();

    fakeBindings.setSearchMatches(1, 'needle', [
      {
        'row': 3,
        'start_col': 0,
        'end_col': 6,
        'text': 'first tab needle',
        'scrollback_offset': 8,
      },
    ]);
    fakeBindings.setSearchMatches(2, 'needle', [
      {
        'row': 5,
        'start_col': 2,
        'end_col': 8,
        'text': 'second tab needle',
        'scrollback_offset': 13,
      },
    ]);

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-global-search')));
    await tester.tap(find.byKey(const Key('shell-global-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('terminal-global-search-field')),
      'needle',
    );
    await tester.pump();

    expect(fakeBindings.searchCalls, contains(equals([1, 'needle'])));
    expect(fakeBindings.searchCalls, contains(equals([2, 'needle'])));
    expect(find.text('first tab needle'), findsOneWidget);
    expect(find.text('second tab needle'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('terminal-global-search-result-2-1')),
    );
    await tester.pumpAndSettle();

    _expectSelectedTab(tester, '2');
    expect(fakeBindings.scrollToCalls.last, [2, 13]);
  });
}
