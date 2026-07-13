import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';

Future<void> _pumpShellScreen(
  WidgetTester tester, {
  required FakePtyBackend fakeBindings,
  ThemeMode themeMode = ThemeMode.light,
  TerminalAppPreferencesDocument? preferences,
  MemoryAppPreferencesRepository? preferencesRepository,
  LocalTerminalConfigRepository? localConfigRepository,
  Future<String> Function()? clipboardPaste,
  SessionClipboardTextWrite? clipboardTextWrite,
  SessionClipboardMimeWrite? clipboardMimeWrite,
  SessionClipboardMimeRead? clipboardMimeRead,
  SessionClipboardMimeTypeList? clipboardMimeTypeList,
  ShellNotificationSender? notificationSender,
  ShellNotificationCloser? notificationCloser,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(fakeBindings),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          preferencesRepository ?? MemoryAppPreferencesRepository(preferences),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          localConfigRepository ?? _MemoryLocalTerminalConfigRepository(null),
        ),
        if (clipboardPaste != null)
          sessionClipboardPasteProvider.overrideWithValue(clipboardPaste),
        if (clipboardTextWrite != null)
          sessionClipboardTextWriteProvider.overrideWithValue(
            clipboardTextWrite,
          ),
        if (clipboardMimeWrite != null)
          sessionClipboardMimeWriteProvider.overrideWithValue(
            clipboardMimeWrite,
          ),
        if (clipboardMimeRead != null)
          sessionClipboardMimeReadProvider.overrideWithValue(clipboardMimeRead),
        if (clipboardMimeTypeList != null)
          sessionClipboardMimeTypeListProvider.overrideWithValue(
            clipboardMimeTypeList,
          ),
        if (notificationSender != null)
          shellNotificationSenderProvider.overrideWithValue(notificationSender),
        if (notificationCloser != null)
          shellNotificationCloserProvider.overrideWithValue(notificationCloser),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        darkTheme: ThemeData.dark().copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        themeMode: themeMode,
        home: const ShellScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

RenderTerminalViewport _renderTerminalViewportForPane(
  WidgetTester tester,
  String sessionId,
) {
  final paneRect = tester.getRect(find.byKey(Key('shell-pane-$sessionId')));
  return tester.allRenderObjects.whereType<RenderTerminalViewport>().firstWhere(
    (renderObject) {
      final topLeft = renderObject.localToGlobal(Offset.zero);
      return paneRect.contains(topLeft + const Offset(1, 1));
    },
  );
}

class _MemoryLocalTerminalConfigRepository
    extends LocalTerminalConfigRepository {
  _MemoryLocalTerminalConfigRepository(this._document);

  LocalTerminalConfigDocument? _document;
  final List<LocalTerminalConfigDocument> savedDocuments = [];

  @override
  Future<LocalTerminalConfigDocument?> load() async => _document;

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {
    savedDocuments.add(document);
    _document = document;
  }
}

class _RecordingAppPreferencesRepository
    extends MemoryAppPreferencesRepository {
  _RecordingAppPreferencesRepository(super.document);

  final List<TerminalAppPreferencesDocument> savedDocuments = [];

  @override
  Future<void> save(TerminalAppPreferencesDocument document) async {
    savedDocuments.add(document);
    await super.save(document);
  }
}

Future<void> _openCommandMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await tester.pumpAndSettle();
}

Future<void> _tapCommandMenuAction(WidgetTester tester, Key key) async {
  await _openCommandMenu(tester);
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _openTabContextMenu(
  WidgetTester tester, {
  String sessionId = '1',
}) async {
  await tester.tap(
    find.byKey(Key('shell-tab-$sessionId')),
    buttons: kSecondaryButton,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapTabContextMenuAction(
  WidgetTester tester,
  String label, {
  String sessionId = '1',
}) async {
  await _openTabContextMenu(tester, sessionId: sessionId);
  final action = find.text(label);
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _tapActivePaneZoomAction(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  );
  final sessionId = container.read(sessionControllerProvider).activeSessionId!;
  final action = find.byKey(Key('shell-pane-action-zoom-$sessionId'));
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _sendMetaShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.sendKeyDownEvent(key, platform: 'macos');
  await tester.sendKeyUpEvent(key, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.pumpAndSettle();
}

Future<void> _invokeNativeWindowBridge(
  WidgetTester tester,
  MethodCall call,
) async {
  final codec = const StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'app/window_bridge',
    codec.encodeMethodCall(call),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shell resizes the session from the padded terminal viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeBindings = FakePtyBackend();
    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    final renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final viewportSize = renderObject.size;
    final resizeCall = fakeBindings.resizeCalls.last;

    expect(
      resizeCall[1],
      (viewportSize.width / renderObject.debugCellSize.width).floor(),
    );
    expect(
      resizeCall[2],
      (viewportSize.height / renderObject.debugCellSize.height).floor(),
    );
    expect(
      resizeCall[3],
      (viewportSize.width * tester.view.devicePixelRatio).round(),
    );
    expect(
      resizeCall[4],
      (viewportSize.height * tester.view.devicePixelRatio).round(),
    );
    expect(fakeBindings.resizeCalls.length, greaterThanOrEqualTo(2));
  });

  testWidgets('shell applies configured terminal viewport padding', (
    tester,
  ) async {
    const preferences = TerminalAppPreferencesDocument(
      appearance: TerminalAppAppearance(terminalViewportPadding: 20),
    );
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      preferences: preferences,
    );

    final viewport = tester.widget<TerminalViewport>(
      find.byType(TerminalViewport),
    );

    expect(viewport.contentPadding, const EdgeInsets.all(20));
  });

  testWidgets('local clipboard config enables copy on select', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          clipboard: LocalTerminalClipboardConfig(copyOnSelect: true),
        ),
      ),
    );

    final viewport = tester.widget<TerminalViewport>(
      find.byType(TerminalViewport),
    );

    expect(viewport.copyOnSelect, isTrue);
  });

  testWidgets('defaults dialog saves OSC 52 ask policy', (tester) async {
    final fakeBindings = FakePtyBackend();
    final localConfigRepository = _MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: localConfigRepository,
    );

    await _openCommandMenu(tester);
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('default-osc52-policy-ask')),
    );
    await tester.tap(find.byKey(const Key('default-osc52-policy-ask')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(localConfigRepository.savedDocuments, isNotEmpty);
    expect(
      localConfigRepository.savedDocuments.last.clipboard.osc52,
      LocalTerminalOsc52Policy.ask,
    );
  });

  testWidgets('OSC 8 hover shows link target and context menu actions', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    fakeBindings.setFrame(1, const <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'open docs',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'hyperlinks': <Object?>[
        <String, Object?>{
          'row': 0,
          'start_col': 5,
          'end_col': 9,
          'uri': 'https://example.com/docs',
        },
      ],
    });
    await tester.pump(const Duration(milliseconds: 40));

    final renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final cellSize = renderObject.debugCellSize;
    final linkPosition = renderObject.localToGlobal(
      Offset(cellSize.width * 6, cellSize.height / 2),
    );
    final pointer = TestPointer(44, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(linkPosition));
    await tester.pump();

    expect(find.text('LINK CHECK example.com'), findsOneWidget);
    expect(
      find.byTooltip(
        'OSC 8 link text differs from the target\n'
        'Target: https://example.com/docs\n'
        'Text: docs',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Target: https://example.com/docs'),
      findsOneWidget,
    );
    expect(find.byKey(terminalLinkTooltipKey), findsOneWidget);
    expect(find.byKey(const Key('shell-status-link-target')), findsOneWidget);

    await tester.sendEventToBinding(
      pointer.down(linkPosition, buttons: kSecondaryMouseButton),
    );
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();

    expect(find.text('Open link'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Copy link text'), findsOneWidget);
    expect(find.text('Show target'), findsOneWidget);

    await tester.sendEventToBinding(pointer.removePointer());
    await tester.pump();
  });

  testWidgets('OSC 8 hover status can focus an inactive split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    fakeBindings.setFrame(inactiveSessionId, <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'open docs',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'hyperlinks': <Object?>[
        <String, Object?>{
          'row': 0,
          'start_col': 5,
          'end_col': 9,
          'uri': 'https://example.com/docs',
        },
      ],
    });
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    final renderObject = _renderTerminalViewportForPane(
      tester,
      inactiveSessionId,
    );
    final cellSize = renderObject.debugCellSize;
    final linkPosition = renderObject.localToGlobal(
      Offset(cellSize.width * 6, cellSize.height / 2),
    );
    final pointer = TestPointer(54, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(linkPosition));
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      activeSessionId,
    );
    expect(find.byKey(Key('shell-pane-dim-$inactiveSessionId')), findsNothing);
    expect(find.byKey(terminalLinkTooltipKey), findsOneWidget);
    expect(find.byKey(const Key('shell-status-link-target')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.contains('Pane:') == true &&
            widget.message?.contains('inactive pane') == true &&
            widget.message?.contains('Click to focus this pane.') == true &&
            widget.message?.contains('Target: https://example.com/docs') ==
                true,
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('shell-status-link-target')));
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );

    await tester.sendEventToBinding(pointer.removePointer());
    await tester.pump();
  });

  testWidgets('zooming split pane clears hidden OSC 8 hover status', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    fakeBindings.setFrame(inactiveSessionId, <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'open docs',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'hyperlinks': <Object?>[
        <String, Object?>{
          'row': 0,
          'start_col': 5,
          'end_col': 9,
          'uri': 'https://example.com/docs',
        },
      ],
    });
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    final renderObject = _renderTerminalViewportForPane(
      tester,
      inactiveSessionId,
    );
    final cellSize = renderObject.debugCellSize;
    final linkPosition = renderObject.localToGlobal(
      Offset(cellSize.width * 6, cellSize.height / 2),
    );
    final pointer = TestPointer(55, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(linkPosition));
    await tester.pump();

    expect(find.byKey(const Key('shell-status-link-target')), findsOneWidget);

    await _tapActivePaneZoomAction(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(Key('shell-pane-$activeSessionId')), findsOneWidget);
    expect(find.byKey(Key('shell-pane-$inactiveSessionId')), findsNothing);
    expect(find.byKey(const Key('shell-status-link-target')), findsNothing);

    await tester.sendEventToBinding(pointer.removePointer());
    await tester.pump();
  });

  testWidgets('OSC 8 file links ask before opening', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    fakeBindings.setFrame(1, const <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'open file',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'hyperlinks': <Object?>[
        <String, Object?>{
          'row': 0,
          'start_col': 5,
          'end_col': 9,
          'uri': 'file:///tmp/secret.txt',
        },
      ],
    });
    await tester.pump(const Duration(milliseconds: 40));

    final renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final cellSize = renderObject.debugCellSize;
    final linkPosition = renderObject.localToGlobal(
      Offset(cellSize.width * 6, cellSize.height / 2),
    );
    final pointer = TestPointer(45, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.down(linkPosition));
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(find.text('Open local file link?'), findsOneWidget);
    expect(find.textContaining('file:///tmp/secret.txt'), findsOneWidget);

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(find.text('Blocked file link'), findsOneWidget);
  });

  testWidgets('OSC 8 file link prompt identifies source split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    fakeBindings.setFrame(inactiveSessionId, <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'open file',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'hyperlinks': <Object?>[
        <String, Object?>{
          'row': 0,
          'start_col': 5,
          'end_col': 9,
          'uri': 'file:///tmp/source-pane.txt',
        },
      ],
    });
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    final renderObject = _renderTerminalViewportForPane(
      tester,
      inactiveSessionId,
    );
    final cellSize = renderObject.debugCellSize;
    final linkPosition = renderObject.localToGlobal(
      Offset(cellSize.width * 6, cellSize.height / 2),
    );
    final pointer = TestPointer(46, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.down(linkPosition));
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(find.text('Open local file link?'), findsOneWidget);
    expect(find.textContaining('file:///tmp/source-pane.txt'), findsOneWidget);
    expect(find.textContaining('Source: Pane:'), findsOneWidget);
    expect(find.textContaining('($inactiveSessionId)'), findsOneWidget);

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(find.text('Blocked file link'), findsOneWidget);
  });

  testWidgets('OSC 52 blocked copy shows visible status and feedback', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          clipboard: LocalTerminalClipboardConfig(
            osc52: LocalTerminalOsc52Policy.disabled,
          ),
        ),
      ),
    );

    fakeBindings.enqueueEvent(
      1,
      PtyEvent(
        kind: 'clipboard_copy',
        sessionId: '1',
        payload: <String, Object?>{
          'selection': 'c',
          'data': base64.encode(utf8.encode('blocked')),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('OSC52 COPY BLOCKED'), findsOneWidget);
    expect(
      find.text('OSC 52 clipboard copy blocked by policy'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell-status-osc52')), findsOneWidget);
  });

  testWidgets('iTerm2 OSC 1337 copy prompts and preserves named pasteboard', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final writes = <(String, String)>[];

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          clipboard: LocalTerminalClipboardConfig(
            osc52: LocalTerminalOsc52Policy.ask,
          ),
        ),
      ),
      clipboardTextWrite: (text, selection) async {
        writes.add((text, selection));
      },
    );

    fakeBindings.enqueueEvent(
      1,
      PtyEvent(
        kind: 'clipboard_copy',
        sessionId: '1',
        payload: <String, Object?>{
          'protocol': 'iterm1337',
          'mode': 'stream',
          'selection': 'find',
          'data': base64.encode(utf8.encode('Find pasteboard text')),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('Allow iTerm2 OSC 1337 clipboard copy?'), findsOneWidget);
    expect(find.text('Selection: find'), findsOneWidget);
    expect(find.text('Find pasteboard text'), findsOneWidget);

    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    expect(writes, <(String, String)>[('Find pasteboard text', 'find')]);
    expect(find.text('ITERM1337 COPY OK'), findsOneWidget);
    expect(
      find.text('iTerm2 OSC 1337 copied 20 characters to the clipboard'),
      findsOneWidget,
    );
  });

  testWidgets('OSC 52 ask policy prompts before paste read', (tester) async {
    final fakeBindings = FakePtyBackend();
    var clipboardReads = 0;

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          clipboard: LocalTerminalClipboardConfig(
            osc52: LocalTerminalOsc52Policy.ask,
          ),
        ),
      ),
      clipboardPaste: () async {
        clipboardReads += 1;
        return 'paste preview';
      },
    );

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'clipboard_paste_request',
        sessionId: '1',
        payload: <String, Object?>{'selection': 'c'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('Allow OSC 52 paste read?'), findsOneWidget);
    expect(
      find.textContaining(
        'The terminal is requesting clipboard contents and will send them back',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Session:'), findsOneWidget);
    expect(find.textContaining('(1) · active pane'), findsOneWidget);
    expect(find.text('Selection: c'), findsOneWidget);
    expect(find.text('Size: 13 characters / 13 bytes'), findsOneWidget);
    expect(find.text('paste preview'), findsOneWidget);
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(find.text('OSC52 PASTE BLOCKED'), findsOneWidget);
    expect(find.text('OSC 52 paste read blocked by policy'), findsOneWidget);
    expect(clipboardReads, 1);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'OSC 5522 prompt can remember an exact application password for the session',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      var platformWrites = 0;

      await _pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        localConfigRepository: _MemoryLocalTerminalConfigRepository(
          const LocalTerminalConfigDocument(
            clipboard: LocalTerminalClipboardConfig(
              osc52: LocalTerminalOsc52Policy.ask,
            ),
          ),
        ),
        clipboardMimeWrite: (_) async => platformWrites += 1,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      PtyEvent writeEvent(String id) => PtyEvent(
        kind: 'clipboard_mime_write',
        sessionId: sessionId,
        payload: <String, Object?>{
          'location': 'clipboard',
          'id': id,
          'password': 'shared-secret',
          'applicationName': 'Editor',
          'items': <Object?>[
            <String, Object?>{
              'mime': 'text/plain',
              'data': base64.encode(utf8.encode('hello')),
            },
          ],
        },
      );

      fakeBindings.enqueueEvent(sessionId, writeEvent('remember-first'));
      runtime.refreshSession(sessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('Allow OSC 5522 clipboard write?'), findsOneWidget);
      expect(find.text('Application: Editor'), findsOneWidget);
      expect(find.text('Always allow'), findsOneWidget);
      expect(
        find.textContaining('future OSC 5522 clipboard reads and writes'),
        findsOneWidget,
      );
      await tester.tap(find.text('Always allow'));
      await tester.pumpAndSettle();
      expect(platformWrites, 1);

      fakeBindings.enqueueEvent(sessionId, writeEvent('remember-second'));
      runtime.refreshSession(sessionId);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();

      expect(find.text('Allow OSC 5522 clipboard write?'), findsNothing);
      expect(platformWrites, 2);
      expect(
        fakeBindings.writes.map(ascii.decode).join(),
        contains('type=write:status=DONE:id=remember-second'),
      );
    },
  );

  testWidgets('OSC 52 prompt identifies inactive split pane', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          clipboard: LocalTerminalClipboardConfig(
            osc52: LocalTerminalOsc52Policy.ask,
          ),
        ),
      ),
      clipboardPaste: () async => 'pane preview',
    );
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'clipboard_paste_request',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{'selection': 'c'},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump();

    expect(find.text('Allow OSC 52 paste read?'), findsOneWidget);
    expect(
      find.textContaining('($inactiveSessionId) · inactive pane'),
      findsOneWidget,
    );
    expect(find.text('pane preview'), findsOneWidget);
  });

  testWidgets('OSC 52 copy prompt identifies inactive split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          clipboard: LocalTerminalClipboardConfig(
            osc52: LocalTerminalOsc52Policy.ask,
          ),
        ),
      ),
    );
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;
    const clipboardText = 'Deploy clipboard copy';

    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'clipboard_copy',
        sessionId: inactiveSessionId,
        payload: <String, Object?>{
          'selection': 'p',
          'data': base64.encode(utf8.encode(clipboardText)),
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump();

    expect(find.text('Allow OSC 52 clipboard copy?'), findsOneWidget);
    expect(
      find.textContaining(
        'The terminal wants to write the following text to your clipboard.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('($inactiveSessionId) · inactive pane'),
      findsOneWidget,
    );
    expect(find.text('Selection: p'), findsOneWidget);
    expect(find.text('Size: 21 characters / 21 bytes'), findsOneWidget);
    expect(find.text(clipboardText), findsOneWidget);

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(find.text('OSC52 COPY BLOCKED'), findsOneWidget);
    expect(
      find.textContaining('OSC 52 clipboard copy blocked by policy ·'),
      findsOneWidget,
    );
    expect(find.textContaining('inactive pane'), findsOneWidget);
    expect(find.byKey(const Key('shell-status-osc52')), findsOneWidget);
  });

  testWidgets('OSC 52 status can focus the originating split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          clipboard: LocalTerminalClipboardConfig(
            osc52: LocalTerminalOsc52Policy.disabled,
          ),
        ),
      ),
    );
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    await _tapActivePaneZoomAction(tester);
    expect(find.byKey(Key('shell-pane-$activeSessionId')), findsOneWidget);
    expect(find.byKey(Key('shell-pane-$inactiveSessionId')), findsNothing);

    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'clipboard_copy',
        sessionId: inactiveSessionId,
        payload: <String, Object?>{
          'selection': 'c',
          'data': base64.encode(utf8.encode('pane copy')),
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      activeSessionId,
    );
    expect(
      find.textContaining('OSC 52 clipboard copy blocked by policy'),
      findsOneWidget,
    );
    expect(find.textContaining('inactive pane'), findsOneWidget);
    expect(find.byKey(const Key('shell-status-osc52')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-status-osc52')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label?.contains(
                    'OSC 52 clipboard write blocked',
                  ) ==
                  true &&
              widget.properties.label?.contains('inactive pane') == true &&
              widget.properties.label?.contains('Click to focus this pane.') ==
                  true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.contains('OSC 52 clipboard write blocked') ==
                true &&
            widget.message?.contains('inactive pane') == true &&
            widget.message?.contains('Click to focus this pane.') == true,
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('shell-status-osc52')));
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );
    expect(find.byKey(Key('shell-pane-$inactiveSessionId')), findsOneWidget);
    expect(find.byKey(Key('shell-pane-$activeSessionId')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-status-osc52')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('OSC 52 clipboard write blocked') ==
                  true &&
              widget.message?.contains('active pane') == true &&
              widget.message?.contains('inactive pane') == false &&
              widget.message?.contains('Click to focus this pane.') == false,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('closing split pane clears its OSC 52 status affordance', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          clipboard: LocalTerminalClipboardConfig(
            osc52: LocalTerminalOsc52Policy.disabled,
          ),
        ),
      ),
    );
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final closingSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    fakeBindings.enqueueEvent(
      closingSessionId,
      PtyEvent(
        kind: 'clipboard_copy',
        sessionId: closingSessionId,
        payload: <String, Object?>{
          'selection': 'c',
          'data': base64.encode(utf8.encode('closing pane copy')),
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(closingSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('shell-status-osc52')), findsOneWidget);

    await tester.tap(
      find.byKey(Key('shell-pane-action-close-$closingSessionId')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      isNot(closingSessionId),
    );
    expect(find.byKey(const Key('shell-status-osc52')), findsNothing);
    expect(find.textContaining('closing pane copy'), findsNothing);
  });

  testWidgets('closing split pane clears OSC pane metadata affordances', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final tabSessionId = splitState.tabs.single.sessionId;
    final closingSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      closingSessionId,
      PtyEvent(
        kind: 'session_progress',
        sessionId: closingSessionId,
        payload: const <String, Object?>{
          'source': 'osc934',
          'named': true,
          'action': 'set',
          'id': 'build',
          'state': 'normal',
          'percent': 64,
          'label': 'Compile',
        },
      ),
    );
    fakeBindings.enqueueEvent(
      closingSessionId,
      PtyEvent(
        kind: 'session_notification',
        sessionId: closingSessionId,
        payload: const <String, Object?>{
          'source': 'osc777',
          'title': 'Build',
          'message': 'Inactive pane done',
        },
      ),
    );
    fakeBindings.enqueueEvent(
      closingSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: closingSessionId,
        payload: const <String, Object?>{'text': 'Deploy'},
      ),
    );
    fakeBindings.enqueueEvent(
      closingSessionId,
      PtyEvent(
        kind: 'session_tab_status',
        sessionId: closingSessionId,
        payload: const <String, Object?>{
          'source': 'osc21337',
          'indicatorPresent': true,
          'indicator': '#ff9500',
          'statusPresent': true,
          'status': 'Working',
          'statusColorPresent': true,
          'statusColor': '#5f87ff',
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(closingSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      activeSessionId,
    );
    expect(find.byKey(const Key('shell-status-badge')), findsNothing);
    expect(find.byKey(const Key('shell-status-progress')), findsNothing);
    expect(find.byKey(const Key('shell-status-notification')), findsNothing);
    expect(find.byKey(Key('shell-tab-badge-$tabSessionId')), findsOneWidget);
    expect(find.byKey(Key('shell-tab-status-$tabSessionId')), findsNothing);
    expect(
      find.byKey(Key('shell-tab-pane-signal-$tabSessionId')),
      findsOneWidget,
    );
    expect(find.text('DEPLOY'), findsOneWidget);
    expect(find.text('BUILD 64%'), findsOneWidget);
    expect(find.text('NOTIFY Build'), findsOneWidget);
    expect(find.text('BADGE Deploy'), findsOneWidget);
    expect(
      find.byKey(Key('shell-pane-header-indicator-progress-$closingSessionId')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        Key('shell-pane-header-indicator-notification-$closingSessionId'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('shell-pane-header-indicator-badge-$closingSessionId')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('shell-pane-header-$closingSessionId')));
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      closingSessionId,
    );
    expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-progress')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-notification')), findsOneWidget);
    expect(
      find.byKey(Key('shell-tab-status-indicator-$tabSessionId')),
      findsOneWidget,
    );
    expect(find.byKey(Key('shell-tab-status-$tabSessionId')), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    final tabSemantics = tester.getSemantics(
      find.bySemanticsIdentifier('shell-tab-$tabSessionId'),
    );
    expect(tabSemantics.label, contains('status Working from active pane'));
    expect(
      tabSemantics.label,
      contains('status indicator active on active pane'),
    );

    await tester.tap(
      find.byKey(Key('shell-pane-action-close-$closingSessionId')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      activeSessionId,
    );
    expect(find.byKey(const Key('shell-status-badge')), findsNothing);
    expect(find.byKey(const Key('shell-status-progress')), findsNothing);
    expect(find.byKey(const Key('shell-status-notification')), findsNothing);
    expect(find.byKey(Key('shell-tab-badge-$tabSessionId')), findsNothing);
    expect(find.byKey(Key('shell-tab-status-$tabSessionId')), findsNothing);
    expect(
      find.byKey(Key('shell-tab-pane-signal-$tabSessionId')),
      findsNothing,
    );
    expect(
      find.byKey(Key('shell-pane-header-indicator-progress-$closingSessionId')),
      findsNothing,
    );
    expect(
      find.byKey(
        Key('shell-pane-header-indicator-notification-$closingSessionId'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(Key('shell-pane-header-indicator-badge-$closingSessionId')),
      findsNothing,
    );
    expect(find.text('DEPLOY'), findsNothing);
    expect(find.text('BUILD 64%'), findsNothing);
    expect(find.text('NOTIFY Build'), findsNothing);
    expect(find.text('BADGE Deploy'), findsNothing);
  });

  testWidgets('tab badge from inactive split pane focuses originating pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;
    final tabSessionId = splitState.tabs.single.sessionId;

    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{'text': 'Deploy'},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      activeSessionId,
    );
    expect(find.byKey(Key('shell-tab-badge-$tabSessionId')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.startsWith('OSC 1337 badge: Deploy\n') == true &&
            widget.message?.contains('($inactiveSessionId) · inactive pane') ==
                true &&
            widget.message?.contains('Click to focus this pane.') == true,
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('shell-tab-badge-$tabSessionId')));
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );
  });

  testWidgets('visible inactive tab badge focuses originating split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile();

    controller.createSession(profile);
    await tester.pump();
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    await tester.pump();
    controller.activateSession('1');
    await tester.pumpAndSettle();

    final splitState = container.read(sessionControllerProvider);
    final splitTab = splitState.tabs.firstWhere((tab) => tab.sessionId != '1');
    final inactiveSplitSessionId = splitTab.effectivePanes
        .firstWhere((pane) => pane.sessionId != splitTab.activeSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      inactiveSplitSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: inactiveSplitSessionId,
        payload: const <String, Object?>{'text': 'Deploy'},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSplitSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(container.read(sessionControllerProvider).activeSessionId, '1');
    expect(
      find.byKey(Key('shell-tab-badge-${splitTab.sessionId}')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(Key('shell-tab-badge-${splitTab.sessionId}')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('OSC 1337 badge: Deploy') == true &&
              widget.message?.contains('inactive pane') == true &&
              widget.message?.contains('Click to focus this pane.') == true,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('shell-tab-badge-${splitTab.sessionId}')));
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSplitSessionId,
    );
    expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
    expect(find.text('BADGE Deploy'), findsOneWidget);
  });

  testWidgets('closing split pane clears hovered OSC 8 link status', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    fakeBindings.setFrame(inactiveSessionId, <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'open docs',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'hyperlinks': <Object?>[
        <String, Object?>{
          'row': 0,
          'start_col': 5,
          'end_col': 9,
          'uri': 'https://example.com/docs',
        },
      ],
    });
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    final renderObject = _renderTerminalViewportForPane(
      tester,
      inactiveSessionId,
    );
    final cellSize = renderObject.debugCellSize;
    final linkPosition = renderObject.localToGlobal(
      Offset(cellSize.width * 6, cellSize.height / 2),
    );
    final pointer = TestPointer(64, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(linkPosition));
    await tester.pump();

    expect(find.byKey(const Key('shell-status-link-target')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-status-link-target')));
    await tester.pump();
    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );

    await tester.tap(
      find.byKey(Key('shell-pane-action-close-$inactiveSessionId')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      isNot(inactiveSessionId),
    );
    expect(find.byKey(const Key('shell-status-link-target')), findsNothing);

    await tester.sendEventToBinding(pointer.removePointer());
    await tester.pump();
  });

  testWidgets('OSC 52 profile policy prompts before paste read', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      clipboardPaste: () async => 'profile preview',
    );

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'clipboard_paste_request',
        sessionId: '1',
        payload: <String, Object?>{'selection': 'c'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('Allow OSC 52 paste read?'), findsOneWidget);
    expect(find.text('profile preview'), findsOneWidget);
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(find.text('OSC52 PASTE BLOCKED'), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('OSC 52 paste read labels empty clipboard preview', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      clipboardPaste: () async => '',
    );

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'clipboard_paste_request',
        sessionId: '1',
        payload: <String, Object?>{'selection': 'c'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('Allow OSC 52 paste read?'), findsOneWidget);
    expect(find.text('Size: 0 characters / 0 bytes'), findsOneWidget);
    expect(find.text('Clipboard is empty'), findsOneWidget);
  });

  testWidgets('OSC indeterminate progress shows state without fake percent', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'session_progress',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'osc9;4',
          'action': 'set',
          'state': 'indeterminate',
          'label': 'Waiting',
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('shell-status-progress')), findsOneWidget);
    expect(find.text('PROGRESS INDETERMINATE'), findsOneWidget);
    expect(find.text('PROGRESS 0%'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-status-progress')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains(
                    'Terminal progress reported by osc9;4.',
                  ) ==
                  true &&
              widget.message?.contains('Label: Waiting') == true &&
              widget.message?.contains('State: indeterminate') == true &&
              widget.message?.contains('Percent:') == false,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-status-progress')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label?.contains(
                    'Terminal progress status: PROGRESS INDETERMINATE',
                  ) ==
                  true &&
              widget.properties.label?.contains('State: indeterminate') ==
                  true &&
              widget.properties.label?.contains('Percent:') == false,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'OSC shell context progress and badge show status bar affordances',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'shell_context',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc7',
            'cwd': '/srv/app',
            'hostname': 'remote.example',
            'username': 'deploy',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'session_progress',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc934',
            'named': true,
            'action': 'set',
            'id': 'build',
            'state': 'normal',
            'percent': 80,
            'label': 'Compile',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'session_badge',
          sessionId: '1',
          payload: <String, Object?>{'text': 'Deploy'},
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byKey(const Key('shell-status-remote')), findsOneWidget);
      expect(find.byKey(const Key('shell-status-progress')), findsOneWidget);
      expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
      expect(find.byKey(const Key('shell-tab-badge-1')), findsOneWidget);
      expect(find.text('REMOTE remote.example'), findsOneWidget);
      expect(find.text('BUILD 80%'), findsOneWidget);
      expect(find.text('BADGE Deploy'), findsOneWidget);
      expect(find.text('DEPLOY'), findsOneWidget);
      expect(
        find.byTooltip(
          [
            'Remote-reported shell integration path.',
            'Path: /srv/app',
            'Host: remote.example',
            'User: deploy',
            'Local file actions stay disabled for remote paths.',
          ].join('\n'),
        ),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          [
            'Remote context reported by shell integration.',
            'Host: remote.example',
            'User: deploy',
            'Local file actions stay disabled for remote paths.',
          ].join('\n'),
        ),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          [
            'Terminal progress reported by osc934.',
            'Label: Compile',
            'Percent: 80%',
            'State: normal',
            'ID: build',
          ].join('\n'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('OSC 1337 badge: Deploy'), findsNWidgets(2));

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'session_badge',
          sessionId: '1',
          payload: <String, Object?>{'text': 'DeploymentStatusVeryLong'},
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('DEPLOYMEN…'), findsOneWidget);
      expect(
        find.byTooltip('OSC 1337 badge: DeploymentStatusVeryLong'),
        findsNWidgets(2),
      );

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'session_progress',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc934',
            'named': true,
            'action': 'set',
            'id': 'test',
            'state': 'normal',
            'percent': 25,
            'label': 'Verify',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('TEST 25%'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shell-status-progress')));
      await tester.pumpAndSettle();

      expect(find.text('BUILD 80%'), findsOneWidget);
      expect(find.text('TEST 25%'), findsWidgets);
      expect(find.text('Verify · normal · 25% · osc934'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'session_progress',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc934',
            'named': true,
            'action': 'remove',
            'id': 'test',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('TEST 100%'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('TEST 100%'), findsNothing);
      expect(find.text('BUILD 80%'), findsOneWidget);

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'session_progress',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc934',
            'named': true,
            'action': 'remove_all',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('BUILD 100%'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.byKey(const Key('shell-status-progress')), findsNothing);

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'session_badge',
          sessionId: '1',
          payload: <String, Object?>{'text': ''},
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byKey(const Key('shell-status-badge')), findsNothing);
      expect(find.byKey(const Key('shell-tab-badge-1')), findsNothing);
    },
  );

  testWidgets(
    'split pane progress indicators prefer running named progress over completed primary progress',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      await _tapTabContextMenuAction(tester, 'Split right');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final splitState = container.read(sessionControllerProvider);
      final progressSessionId = splitState.activeSessionId!;
      final otherSessionId = splitState.tabs.single.effectivePanes
          .firstWhere((pane) => pane.sessionId != progressSessionId)
          .sessionId;
      final tabSessionId = splitState.tabs.single.sessionId;

      fakeBindings.enqueueEvent(
        progressSessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: progressSessionId,
          payload: const <String, Object?>{
            'source': 'osc9;4',
            'action': 'set',
            'state': 'normal',
            'percent': 20,
            'label': 'Primary',
          },
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(progressSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('PROGRESS 20%'), findsOneWidget);

      fakeBindings.enqueueEvent(
        progressSessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: progressSessionId,
          payload: const <String, Object?>{
            'source': 'osc9;4',
            'action': 'clear',
          },
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(progressSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('PROGRESS 100%'), findsOneWidget);

      fakeBindings.enqueueEvent(
        progressSessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: progressSessionId,
          payload: const <String, Object?>{
            'source': 'osc934',
            'named': true,
            'action': 'set',
            'id': 'build',
            'state': 'normal',
            'percent': 42,
            'label': 'Build',
          },
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(progressSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        find.descendant(
          of: find.byKey(const Key('shell-status-progress')),
          matching: find.text('BUILD 42%'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-status-progress')),
          matching: find.text('PROGRESS 100%'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-status-progress')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label?.contains(
                      'Terminal progress reported by osc934',
                    ) ==
                    true &&
                widget.properties.label?.contains('ID: build') == true,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(Key('shell-tab-pane-signal-$tabSessionId')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains(
                      'Terminal progress reported by osc934',
                    ) ==
                    true,
          ),
        ),
        findsOneWidget,
      );

      controller.activateSession(otherSessionId);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(
            Key('shell-pane-header-indicator-progress-$progressSessionId'),
          ),
          matching: find.text('BUILD 42%'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            Key('shell-pane-header-indicator-progress-$progressSessionId'),
          ),
          matching: find.text('PROGRESS 100%'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'OSC shell context remote cwd disables local duplicate affordance',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'shell_context',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc7',
            'cwd': '/srv/app',
            'hostname': 'remote.example',
            'username': 'deploy',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      await _openTabContextMenu(tester);

      expect(find.text('Duplicate current directory'), findsOneWidget);
      expect(
        find.text(
          'Unavailable: Remote-reported current directories cannot be duplicated as local sessions.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('OSC pane metadata stays visible across split panes', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final tab = splitState.tabs.single;
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = tab.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'shell_context',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{
          'source': 'osc7',
          'cwd': '/srv/app',
          'hostname': 'remote.example',
          'username': 'deploy',
        },
      ),
    );
    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'session_progress',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{
          'source': 'osc934',
          'named': true,
          'action': 'set',
          'id': 'build',
          'state': 'normal',
          'percent': 80,
          'label': 'Compile',
        },
      ),
    );
    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'session_notification',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{
          'source': 'osc777',
          'title': 'Build',
          'message': 'Inactive pane done',
        },
      ),
    );
    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{'text': 'Deploy'},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump();

    expect(
      find.byKey(Key('shell-pane-header-indicator-remote-$inactiveSessionId')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        Key('shell-pane-header-indicator-progress-$inactiveSessionId'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        Key('shell-pane-header-indicator-notification-$inactiveSessionId'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('shell-pane-header-indicator-badge-$inactiveSessionId')),
      findsOneWidget,
    );
    expect(find.text('REMOTE remote.example'), findsOneWidget);
    expect(find.text('BUILD 80%'), findsOneWidget);
    expect(find.text('NOTIFY Build'), findsOneWidget);
    expect(find.text('BADGE Deploy'), findsOneWidget);
    expect(find.byKey(const Key('shell-status-badge')), findsNothing);
    expect(find.byKey(const Key('shell-status-progress')), findsNothing);
    expect(find.byKey(const Key('shell-status-notification')), findsNothing);
    expect(find.byKey(Key('shell-tab-badge-${tab.sessionId}')), findsOneWidget);
    expect(find.text('DEPLOY'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(Key('shell-tab-badge-${tab.sessionId}')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('OSC 1337 badge: Deploy') == true &&
              widget.message?.contains('Pane:') == true &&
              widget.message?.contains('inactive pane') == true &&
              widget.message?.contains('Click to focus this pane.') == true,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('shell-tab-badge-${tab.sessionId}')));
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );
    expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);

    await tester.tap(find.byKey(Key('shell-pane-header-$activeSessionId')));
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      activeSessionId,
    );
    expect(find.byKey(const Key('shell-status-badge')), findsNothing);

    fakeBindings.enqueueEvent(
      activeSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: activeSessionId,
        payload: const <String, Object?>{'text': 'Active'},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(activeSessionId);
    await tester.pump();

    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('DEPLOY'), findsOneWidget);
    expect(
      find.byKey(Key('shell-tab-badge-${tab.sessionId}-$activeSessionId')),
      findsOneWidget,
    );
    expect(find.text('BADGE Active'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(Key('shell-tab-badge-${tab.sessionId}')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('OSC 1337 badge: Deploy') == true &&
              widget.message?.contains('Other pane badges:') == true &&
              widget.message?.contains('Active') == true &&
              widget.message?.contains('inactive pane') == true &&
              widget.message?.contains('Click to focus this pane.') == true,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('shell-tab-badge-${tab.sessionId}')));
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );

    await tester.tap(find.byKey(Key('shell-tab-badge-${tab.sessionId}')));
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      activeSessionId,
    );

    await tester.tap(find.byKey(Key('shell-pane-header-$activeSessionId')));
    await tester.pump();

    fakeBindings.enqueueEvent(
      activeSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: activeSessionId,
        payload: const <String, Object?>{'text': ''},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(activeSessionId);
    await tester.pump();

    expect(find.byKey(const Key('shell-status-badge')), findsNothing);
    expect(find.text('DEPLOY'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.contains('Pane:') == true &&
            widget.message?.contains('inactive pane') == true &&
            widget.message?.contains('Click to focus this pane.') == true,
      ),
      findsWidgets,
    );

    await tester.tap(
      find.byKey(Key('shell-pane-header-indicator-badge-$inactiveSessionId')),
    );
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );
    expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-progress')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-notification')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-status-badge')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label?.contains('OSC 1337 badge: Deploy') ==
                  true &&
              widget.properties.label?.contains('Pane:') == true &&
              widget.properties.label?.contains('active pane') == true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-status-progress')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label?.contains(
                    'Terminal progress reported by osc934',
                  ) ==
                  true &&
              widget.properties.label?.contains('Pane:') == true &&
              widget.properties.label?.contains('active pane') == true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-status-notification')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label?.contains(
                    'Terminal notification reported by osc777',
                  ) ==
                  true &&
              widget.properties.label?.contains('Pane:') == true &&
              widget.properties.label?.contains('active pane') == true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-status-badge')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('OSC 1337 badge: Deploy') == true &&
              widget.message?.contains('Pane:') == true &&
              widget.message?.contains('active pane') == true &&
              widget.message?.contains('Click to focus this pane.') == false,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-status-progress')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains(
                    'Terminal progress reported by osc934',
                  ) ==
                  true &&
              widget.message?.contains('Pane:') == true &&
              widget.message?.contains('active pane') == true &&
              widget.message?.contains('Click to focus this pane.') == false,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('split tab overflow badge focuses the hidden badge pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile();

    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    await tester.pumpAndSettle();
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    await tester.pumpAndSettle();
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    await tester.pumpAndSettle();

    final splitState = container.read(sessionControllerProvider);
    final tab = splitState.tabs.single;
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionIds = tab.effectivePanes
        .where((pane) => pane.sessionId != activeSessionId)
        .map((pane) => pane.sessionId)
        .toList(growable: false);
    expect(inactiveSessionIds, hasLength(3));

    final firstVisibleBadgeSessionId = inactiveSessionIds[0];
    final secondVisibleBadgeSessionId = inactiveSessionIds[1];
    final hiddenBadgeSessionId = inactiveSessionIds[2];
    final badgeTexts = <String, String>{
      activeSessionId: 'Active',
      firstVisibleBadgeSessionId: 'Build',
      secondVisibleBadgeSessionId: 'Test',
      hiddenBadgeSessionId: 'Deploy',
    };
    for (final entry in badgeTexts.entries) {
      fakeBindings.enqueueEvent(
        entry.key,
        PtyEvent(
          kind: 'session_badge',
          sessionId: entry.key,
          payload: <String, Object?>{'text': entry.value},
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(entry.key);
    }
    await tester.pump(const Duration(milliseconds: 40));

    final firstInactiveBadge = find.byKey(
      Key('shell-tab-badge-${tab.sessionId}'),
    );
    final secondInactiveBadge = find.byKey(
      Key('shell-tab-badge-${tab.sessionId}-$secondVisibleBadgeSessionId'),
    );
    final hiddenBadgeOverflow = find.byKey(
      Key('shell-tab-badge-${tab.sessionId}-more'),
    );
    expect(firstInactiveBadge, findsOneWidget);
    expect(secondInactiveBadge, findsOneWidget);
    expect(hiddenBadgeOverflow, findsOneWidget);
    expect(
      find.descendant(of: firstInactiveBadge, matching: find.text('BUILD')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondInactiveBadge, matching: find.text('TEST')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hiddenBadgeOverflow, matching: find.text('+2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hiddenBadgeOverflow,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('Additional OSC 1337 badges') == true &&
              widget.message?.contains('($hiddenBadgeSessionId)') == true &&
              widget.message?.contains('inactive pane') == true &&
              widget.message?.contains(
                    'Click to focus the first remaining badge pane.',
                  ) ==
                  true,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(hiddenBadgeOverflow);
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      hiddenBadgeSessionId,
    );
    expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
    expect(find.text('BADGE Deploy'), findsOneWidget);
  });

  testWidgets(
    'overflow tab badge can focus an inactive pane inside a hidden split tab',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final profile = defaultTerminalProfile();
      for (var index = 0; index < 11; index += 1) {
        controller.createSession(profile);
      }
      controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
      controller.activateSession('1');
      await tester.pumpAndSettle();

      final splitTab = container
          .read(sessionControllerProvider)
          .tabs
          .firstWhere((tab) => tab.sessionId == '12');
      final inactiveSplitSessionId = splitTab.effectivePanes
          .firstWhere((pane) => pane.sessionId != splitTab.activeSessionId)
          .sessionId;

      fakeBindings.enqueueEvent(
        inactiveSplitSessionId,
        PtyEvent(
          kind: 'session_badge',
          sessionId: inactiveSplitSessionId,
          payload: const <String, Object?>{'text': 'Deploy'},
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSplitSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        find.byKey(const Key('shell-tab-overflow-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('shell-tab-badge-12')), findsNothing);
      expect(find.byKey(const Key('shell-tab-overflow-badge')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-overflow-badge')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains('OSC 1337 badge in a hidden tab.') ==
                    true &&
                widget.message?.contains('OSC 1337 badge: Deploy') == true &&
                widget.message?.contains('inactive pane') == true &&
                widget.message?.contains('Click to focus this pane.') == true,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('shell-tab-overflow-item-12')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-tab-overflow-badge-12')),
        findsOneWidget,
      );
      expect(find.text('DEPLOY'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-overflow-badge-12')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains('OSC 1337 badge: Deploy') == true &&
                widget.message?.contains('Pane:') == true &&
                widget.message?.contains('inactive pane') == true &&
                widget.message?.contains('Click to focus this pane.') == true,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-overflow-badge-12')));
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveSplitSessionId,
      );
      expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
    },
  );

  testWidgets('overflow split tab exposes separate pane badges', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile();
    for (var index = 0; index < 11; index += 1) {
      controller.createSession(profile);
    }
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    controller.activateSession('1');
    await tester.pumpAndSettle();

    final splitTab = container
        .read(sessionControllerProvider)
        .tabs
        .firstWhere((tab) => tab.sessionId == '12');
    final activeSplitSessionId = splitTab.activeSessionId;
    final inactiveSplitSessionId = splitTab.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSplitSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      activeSplitSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: activeSplitSessionId,
        payload: const <String, Object?>{'text': 'Active'},
      ),
    );
    fakeBindings.enqueueEvent(
      inactiveSplitSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: inactiveSplitSessionId,
        payload: const <String, Object?>{'text': 'Deploy'},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(activeSplitSessionId);
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSplitSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();

    final inactiveBadge = find.byKey(const Key('shell-tab-overflow-badge-12'));
    final activeBadge = find.byKey(
      Key('shell-tab-overflow-badge-12-$activeSplitSessionId'),
    );
    expect(activeBadge, findsOneWidget);
    expect(inactiveBadge, findsOneWidget);
    expect(
      find.descendant(of: inactiveBadge, matching: find.text('DEPLOY')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: activeBadge, matching: find.text('ACTIVE')),
      findsOneWidget,
    );

    await tester.tap(inactiveBadge);
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSplitSessionId,
    );
    expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
    expect(find.text('BADGE Deploy'), findsOneWidget);
  });

  testWidgets('visible split tab badge does not mark hidden overflow tabs', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile();
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    await tester.pumpAndSettle();

    final visibleSplitTab = container
        .read(sessionControllerProvider)
        .tabs
        .firstWhere((tab) => tab.effectivePanes.length > 1);
    final inactiveSplitSessionId = visibleSplitTab.effectivePanes
        .firstWhere((pane) => pane.sessionId != visibleSplitTab.activeSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      inactiveSplitSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: inactiveSplitSessionId,
        payload: const <String, Object?>{'text': 'Deploy'},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSplitSessionId);

    for (var index = 0; index < 11; index += 1) {
      controller.createSession(profile);
    }
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-tab-overflow-button')), findsOneWidget);
    expect(
      find.byKey(Key('shell-tab-badge-${visibleSplitTab.sessionId}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell-tab-overflow-badge')), findsNothing);
  });

  testWidgets('overflow badge marker can focus a hidden split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile();
    for (var index = 0; index < 11; index += 1) {
      controller.createSession(profile);
    }
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    controller.activateSession('1');
    await tester.pumpAndSettle();

    final splitTab = container
        .read(sessionControllerProvider)
        .tabs
        .firstWhere((tab) => tab.sessionId == '12');
    final inactiveSplitSessionId = splitTab.effectivePanes
        .firstWhere((pane) => pane.sessionId != splitTab.activeSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      inactiveSplitSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: inactiveSplitSessionId,
        payload: const <String, Object?>{'text': 'Deploy'},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSplitSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('shell-tab-overflow-badge')), findsOneWidget);
    expect(
      container.read(sessionControllerProvider).activeSessionId,
      isNot(inactiveSplitSessionId),
    );

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-tab-overflow-panel')), findsOneWidget);
    expect(find.byKey(const Key('shell-tab-overflow-badge')), findsNothing);

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-tab-overflow-panel')), findsNothing);
    expect(find.byKey(const Key('shell-tab-overflow-badge')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-tab-overflow-badge')));
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSplitSessionId,
    );
    expect(find.byKey(const Key('shell-tab-overflow-panel')), findsNothing);
    expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
    expect(find.text('BADGE Deploy'), findsOneWidget);
  });

  testWidgets(
    'hidden overflow badge marker prioritizes inactive pane in active hidden tab',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final profile = defaultTerminalProfile();
      for (var index = 0; index < 11; index += 1) {
        controller.createSession(profile);
      }
      controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
      await tester.pumpAndSettle();

      final splitState = container.read(sessionControllerProvider);
      final activeSplitSessionId = splitState.activeSessionId!;
      final splitTab = splitState.tabs.firstWhere(
        (tab) =>
            tab.effectivePanes.length > 1 &&
            tab.containsSession(activeSplitSessionId),
      );
      final inactiveSplitSessionId = splitTab.effectivePanes
          .firstWhere((pane) => pane.sessionId != activeSplitSessionId)
          .sessionId;

      fakeBindings.enqueueEvent(
        activeSplitSessionId,
        PtyEvent(
          kind: 'session_badge',
          sessionId: activeSplitSessionId,
          payload: const <String, Object?>{'text': 'Active'},
        ),
      );
      fakeBindings.enqueueEvent(
        inactiveSplitSessionId,
        PtyEvent(
          kind: 'session_badge',
          sessionId: inactiveSplitSessionId,
          payload: const <String, Object?>{'text': 'Deploy'},
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(activeSplitSessionId);
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSplitSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byKey(const Key('shell-tab-overflow-badge')), findsOneWidget);
      expect(
        find.byKey(Key('shell-tab-badge-${splitTab.sessionId}')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-overflow-badge')),
          matching: find.byWidgetPredicate((widget) {
            if (widget is! Tooltip) {
              return false;
            }
            final message = widget.message;
            if (message == null) {
              return false;
            }
            return message.contains('OSC 1337 badges in 2 hidden panes.') &&
                message.contains('($inactiveSplitSessionId)') &&
                message.contains('($activeSplitSessionId)') &&
                message.indexOf('($inactiveSplitSessionId)') <
                    message.indexOf('($activeSplitSessionId)') &&
                message.contains('Click to focus the first badge pane.');
          }),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-overflow-badge')));
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveSplitSessionId,
      );
      expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
      expect(find.text('BADGE Deploy'), findsOneWidget);
    },
  );

  testWidgets(
    'hidden overflow badge marker labels active hidden pane as already focused',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final profile = defaultTerminalProfile();
      for (var index = 0; index < 11; index += 1) {
        controller.createSession(profile);
      }
      controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
      await tester.pumpAndSettle();

      final activeSplitSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      fakeBindings.enqueueEvent(
        activeSplitSessionId,
        PtyEvent(
          kind: 'session_badge',
          sessionId: activeSplitSessionId,
          payload: const <String, Object?>{'text': 'Active'},
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(activeSplitSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byKey(const Key('shell-tab-overflow-badge')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-overflow-badge')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains('OSC 1337 badge in a hidden tab.') ==
                    true &&
                widget.message?.contains('OSC 1337 badge: Active') == true &&
                widget.message?.contains('active pane') == true &&
                widget.message?.contains('Pane already focused.') == true &&
                widget.message?.contains('Click to focus this pane') == false,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-overflow-badge')));
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        activeSplitSessionId,
      );
      expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
      expect(find.text('BADGE Active'), findsOneWidget);
    },
  );

  testWidgets(
    'overflow tab new output dot can focus an inactive pane inside a hidden split tab',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final profile = defaultTerminalProfile();
      for (var index = 0; index < 11; index += 1) {
        controller.createSession(profile);
      }
      controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
      controller.activateSession('1');
      await tester.pumpAndSettle();

      final splitTab = container
          .read(sessionControllerProvider)
          .tabs
          .firstWhere((tab) => tab.sessionId == '12');
      final inactiveSplitSessionId = splitTab.effectivePanes
          .firstWhere((pane) => pane.sessionId != splitTab.activeSessionId)
          .sessionId;

      fakeBindings.setFrame(inactiveSplitSessionId, <String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'hidden pane output',
            'style_runs': <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 0, 'col': 18, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSplitSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        find.byKey(const Key('shell-tab-overflow-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('shell-tab-new-output-12')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-overflow-new-output')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains('New output in a hidden tab.') ==
                    true &&
                widget.message?.contains('Pane:') == true &&
                widget.message?.contains('inactive pane') == true &&
                widget.message?.contains('Click to focus this pane.') == true,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
      await tester.pumpAndSettle();

      final overflowDot = find.byKey(const Key('shell-tab-new-output-12'));
      expect(overflowDot, findsOneWidget);
      expect(
        find.descendant(
          of: overflowDot,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains('New output in a split pane.') ==
                    true &&
                widget.message?.contains('Pane:') == true &&
                widget.message?.contains('inactive pane') == true &&
                widget.message?.contains('Click to focus this pane.') == true,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(overflowDot);
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveSplitSessionId,
      );
      expect(find.byKey(const Key('shell-tab-overflow-panel')), findsNothing);
      expect(find.byKey(const Key('shell-tab-new-output-12')), findsNothing);
    },
  );

  testWidgets('overflow new output marker can focus a hidden split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile();
    for (var index = 0; index < 11; index += 1) {
      controller.createSession(profile);
    }
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    controller.activateSession('1');
    await tester.pumpAndSettle();

    final splitTab = container
        .read(sessionControllerProvider)
        .tabs
        .firstWhere((tab) => tab.sessionId == '12');
    final inactiveSplitSessionId = splitTab.effectivePanes
        .firstWhere((pane) => pane.sessionId != splitTab.activeSessionId)
        .sessionId;

    fakeBindings.setFrame(inactiveSplitSessionId, <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'hidden pane output',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 18, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSplitSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(
      find.byKey(const Key('shell-tab-overflow-new-output')),
      findsOneWidget,
    );
    expect(
      container.read(sessionControllerProvider).activeSessionId,
      isNot(inactiveSplitSessionId),
    );

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-tab-overflow-panel')), findsOneWidget);
    expect(
      find.byKey(const Key('shell-tab-overflow-new-output')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-tab-overflow-panel')), findsNothing);
    expect(
      find.byKey(const Key('shell-tab-overflow-new-output')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('shell-tab-overflow-new-output')));
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSplitSessionId,
    );
    expect(find.byKey(const Key('shell-tab-overflow-panel')), findsNothing);
    expect(
      find.byKey(const Key('shell-tab-overflow-new-output')),
      findsNothing,
    );
  });

  testWidgets(
    'hidden overflow new output marker prioritizes inactive pane in active hidden split tab',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final profile = defaultTerminalProfile();
      for (var index = 0; index < 11; index += 1) {
        controller.createSession(profile);
      }
      controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
      controller.activateSession('1');
      await tester.pumpAndSettle();

      final splitTab = container
          .read(sessionControllerProvider)
          .tabs
          .firstWhere((tab) => tab.sessionId == '12');
      final activeHiddenSessionId = splitTab.effectivePanes.first.sessionId;
      final inactiveHiddenSessionId = splitTab.effectivePanes
          .firstWhere((pane) => pane.sessionId != activeHiddenSessionId)
          .sessionId;

      for (final entry in <String, String>{
        activeHiddenSessionId: 'active hidden output',
        inactiveHiddenSessionId: 'inactive hidden output',
      }.entries) {
        fakeBindings.setFrame(entry.key, <String, Object?>{
          'rows': <Object?>[
            <String, Object?>{
              'index': 0,
              'text': entry.value,
              'style_runs': <Object?>[],
            },
          ],
          'cursor': <String, Object?>{
            'row': 0,
            'col': entry.value.length,
            'visible': true,
          },
          'selection': null,
          'viewport_rows': 24,
          'viewport_cols': 80,
          'dirty_ranges': <Object?>[
            <String, Object?>{'start': 0, 'end': 1},
          ],
          'scrollback_offset': 0,
          'scrollback_max_offset': 0,
        });
        container
            .read(terminalRuntimeControllerProvider)
            .refreshSession(entry.key);
        await tester.pump(const Duration(milliseconds: 40));
      }

      controller.activateSession(activeHiddenSessionId);
      await tester.pumpAndSettle();
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        activeHiddenSessionId,
      );
      expect(
        find.byKey(const Key('shell-tab-overflow-new-output')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-overflow-new-output')),
          matching: find.byWidgetPredicate((widget) {
            if (widget is! Tooltip || widget.message == null) {
              return false;
            }
            final message = widget.message!;
            final inactiveIndex = message.indexOf(
              '($inactiveHiddenSessionId) · inactive pane',
            );
            final activeIndex = message.indexOf(
              '($activeHiddenSessionId) · active pane',
            );
            return message.contains('New output in 2 hidden panes.') &&
                message.contains(
                  'Click to focus the first pane with new output.',
                ) &&
                inactiveIndex >= 0 &&
                activeIndex >= 0 &&
                inactiveIndex < activeIndex;
          }),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-overflow-new-output')));
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveHiddenSessionId,
      );
    },
  );

  testWidgets('inactive split pane header exposes active terminal modes', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    final inactiveFrameJson = <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'vim README.md',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 13, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'modes': <String, Object?>{
        'alternate_screen': true,
        'bracketed_paste': true,
        'focus_tracking': true,
        'mouse_mode': 'button_event',
        'mouse_encoding': 'sgr',
        'kitty_keyboard_flags': 10,
        'synchronized_output': true,
      },
    };
    final inactiveFrame = TerminalFrameDiff.fromJson(inactiveFrameJson);
    expect(inactiveFrame.modes.alternateScreen, isTrue);
    final runtime = container.read(terminalRuntimeControllerProvider);
    // Keep background polling from replacing this header-only fixture with the
    // backend's initial frame. Synchronized frames are intentionally skipped
    // by the runtime until their visible flush arrives.
    fakeBindings.setFrame(inactiveSessionId, inactiveFrameJson);
    runtime.viewportFor(inactiveSessionId).updateFrame(inactiveFrame);
    await tester.pump();
    expect(
      runtime.viewportFor(inactiveSessionId).frame.modes.alternateScreen,
      isTrue,
    );

    expect(
      find.byKey(Key('shell-pane-header-indicator-alt-$inactiveSessionId')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('shell-pane-header-indicator-mouse-$inactiveSessionId')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('shell-pane-header-indicator-paste-$inactiveSessionId')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('shell-pane-header-indicator-focus-$inactiveSessionId')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        Key('shell-pane-header-indicator-kitty-keyboard-$inactiveSessionId'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('shell-pane-header-indicator-sync-$inactiveSessionId')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell-status-mode-focus')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(
          Key('shell-pane-header-indicator-focus-$inactiveSessionId'),
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('Focus reporting is active') == true &&
              widget.message?.contains('inactive pane') == true &&
              widget.message?.contains('Click to focus this pane.') == true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          Key('shell-pane-header-indicator-kitty-keyboard-$inactiveSessionId'),
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('Kitty keyboard protocol is active') ==
                  true &&
              widget.message?.contains('repeat and release events') == true &&
              widget.message?.contains('inactive pane') == true &&
              widget.message?.contains('Click to focus this pane.') == true,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        Key('shell-pane-header-indicator-kitty-keyboard-$inactiveSessionId'),
      ),
    );
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );
    expect(find.byKey(const Key('shell-status-mode-alt')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-mode-mouse')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-mode-paste')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-mode-focus')), findsOneWidget);
    expect(
      find.byKey(const Key('shell-status-mode-kitty-keyboard')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell-status-mode-sync')), findsOneWidget);

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-toggle-read-only')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shell-toggle-read-only')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('shell-status-mode-read-only')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('shell-pane-header-$activeSessionId')));
    await tester.pump();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      activeSessionId,
    );
    expect(
      find.byKey(
        Key('shell-pane-header-indicator-read-only-$inactiveSessionId'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          Key('shell-pane-header-indicator-read-only-$inactiveSessionId'),
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('Read-only mode is enabled') == true &&
              widget.message?.contains('inactive pane') == true &&
              widget.message?.contains('Click to focus this pane.') == true,
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell-status-mode-read-only')), findsNothing);
  });

  testWidgets(
    'read-only split pane blocks middle-click paste before clipboard read',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      var clipboardReads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            clipboardReads += 1;
            return <String, dynamic>{'text': 'blocked middle paste'};
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

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      await _tapTabContextMenuAction(tester, 'Split right');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final splitState = container.read(sessionControllerProvider);
      final readOnlySessionId = splitState.activeSessionId!;
      final activeSessionId = splitState.tabs.single.effectivePanes
          .firstWhere((pane) => pane.sessionId != readOnlySessionId)
          .sessionId;

      await _openCommandMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('shell-toggle-read-only')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shell-toggle-read-only')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('shell-pane-header-$activeSessionId')));
      await tester.pump();
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        activeSessionId,
      );
      expect(
        find.byKey(
          Key('shell-pane-header-indicator-read-only-$readOnlySessionId'),
        ),
        findsOneWidget,
      );

      final renderObject = _renderTerminalViewportForPane(
        tester,
        readOnlySessionId,
      );
      final pastePosition = renderObject.localToGlobal(
        Offset(renderObject.size.width / 2, renderObject.size.height / 2),
      );
      final pointer = TestPointer(91, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.down(pastePosition, buttons: kMiddleMouseButton),
      );
      await tester.pump();
      await tester.sendEventToBinding(pointer.up());
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        readOnlySessionId,
      );
      expect(clipboardReads, 0);
      expect(fakeBindings.writesBySession, isEmpty);
      expect(
        find.byKey(const Key('shell-status-mode-read-only')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'OSC notification shows in-window feedback and uses gated system sender',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      final notifications = <Map<String, String?>>[];

      await _pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        notificationSender:
            ({required title, body, identifier, expiresAfterMs}) async {
              notifications.add({
                'title': title,
                'body': body,
                'identifier': identifier,
              });
            },
      );

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'session_notification',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc777',
            'title': 'Build',
            'message': 'Active pane done',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('Build: Active pane done'), findsOneWidget);
      expect(
        find.byKey(const Key('shell-status-notification')),
        findsOneWidget,
      );
      expect(find.text('NOTIFY Build'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shell-status-notification')));
      await tester.pumpAndSettle();
      expect(find.text('Build'), findsOneWidget);
      expect(find.text('Active pane done · osc777'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(notifications, isEmpty);

      await _tapCommandMenuAction(tester, const Key('shell-top-new-tab'));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'shell_context',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc7',
            'cwd': '/srv/app',
            'hostname': 'remote.example',
            'username': 'deploy',
          },
        ),
      );
      container.read(terminalRuntimeControllerProvider).refreshSession('1');
      await tester.pump();

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'session_notification',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc777',
            'title': 'Build',
            'message': 'Inactive pane done',
          },
        ),
      );
      container.read(terminalRuntimeControllerProvider).refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      final paneOne = container
          .read(sessionControllerProvider)
          .tabs
          .first
          .paneFor('1')!;
      expect(paneOne.recentNotifications.first.message, 'Inactive pane done');
      expect(paneOne.recentNotifications.first.remoteHost, 'remote.example');
      expect(paneOne.recentNotifications.first.remoteUser, 'deploy');
      expect(notifications, hasLength(1));
      expect(
        notifications.single['title'],
        startsWith('Build on deploy@remote.example in '),
      );
      expect(notifications.single['body'], 'Inactive pane done');
      expect(
        notifications.single['identifier'],
        startsWith('ianvs-terminal.osc.1.'),
      );
    },
  );

  testWidgets('OSC notification snackbar identifies inactive split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'session_notification',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{
          'source': 'osc777',
          'title': 'Build',
          'message': 'Inactive pane done',
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('Build: Inactive pane done · Pane:'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('($inactiveSessionId) · inactive pane'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('OSC 99 system notification keeps stable ID, expiry and close', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final delivered = <Map<String, Object?>>[];
    final closed = <String>[];

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      notificationSender:
          ({required title, body, identifier, expiresAfterMs}) async {
            delivered.add({
              'title': title,
              'body': body,
              'identifier': identifier,
              'expiresAfterMs': expiresAfterMs,
            });
          },
      notificationCloser: (identifier) async {
        closed.add(identifier);
      },
    );
    await _tapCommandMenuAction(tester, const Key('shell-top-new-tab'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );

    for (final event in <PtyEvent>[
      const PtyEvent(
        kind: 'session_notification',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'osc99',
          'action': 'show',
          'id': 'build',
          'title': 'Build',
          'message': 'Started',
          'expiresAfterMs': 250,
        },
      ),
      const PtyEvent(
        kind: 'session_notification',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'osc99',
          'action': 'update',
          'id': 'build',
          'title': 'Build',
          'message': 'Complete',
          'expiresAfterMs': 500,
        },
      ),
    ]) {
      fakeBindings.enqueueEvent('1', event);
      container.read(terminalRuntimeControllerProvider).refreshSession('1');
      await tester.pump();
    }

    expect(delivered, hasLength(2));
    expect(
      delivered.map((notification) => notification['identifier']).toSet(),
      <Object?>{'ianvs-terminal.osc.1.build'},
    );
    expect(delivered.first['expiresAfterMs'], 250);
    expect(delivered.last['expiresAfterMs'], 500);
    expect(delivered.last['body'], 'Complete');

    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'session_notification',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'osc99',
          'action': 'close',
          'id': 'build',
          'title': '',
          'message': '',
        },
      ),
    );
    container.read(terminalRuntimeControllerProvider).refreshSession('1');
    await tester.pump();

    expect(closed, <String>['ianvs-terminal.osc.1.build']);
    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .first
          .paneFor('1')!
          .recentNotifications,
      isEmpty,
    );
  });

  testWidgets('command finished notification identifies inactive split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final notifications = <Map<String, String?>>[];

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      notificationSender:
          ({required title, body, identifier, expiresAfterMs}) async {
            notifications.add({
              'title': title,
              'body': body,
              'identifier': identifier,
            });
          },
    );

    await _tapTabContextMenuAction(tester, 'Split right');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final paneOneTitle = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .paneFor('1')!
        .title;

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'shell_context',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'osc7',
          'cwd': '/srv/app',
          'hostname': 'remote.example',
          'username': 'deploy',
        },
      ),
    );
    container.read(terminalRuntimeControllerProvider).refreshSession('1');
    await tester.pump();

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: '1',
        payload: <String, Object?>{
          'hook': 'command_finished',
          'command': 'deploy staging',
          'exit_code': 0,
        },
      ),
    );
    container.read(terminalRuntimeControllerProvider).refreshSession('1');
    await tester.pump(const Duration(milliseconds: 40));

    expect(notifications, hasLength(1));
    expect(
      notifications.single['title'],
      'Command finished on deploy@remote.example in $paneOneTitle pane 1 (1)',
    );
    expect(notifications.single['body'], contains('deploy staging'));
    expect(notifications.single['body'], contains('Exit code 0'));
    expect(
      notifications.single['identifier'],
      startsWith('ianvs-terminal.command.1.'),
    );
  });

  testWidgets(
    'activity bell and exit notifications identify inactive split pane',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      final notifications = <Map<String, String?>>[];

      Map<String, Object?> frameWithText(String text) {
        return <String, Object?>{
          'rows': <Object?>[
            <String, Object?>{
              'index': 0,
              'text': text,
              'style_runs': <Object?>[],
            },
          ],
          'cursor': <String, Object?>{'row': 0, 'col': text.length},
          'selection': null,
          'viewport_rows': 24,
          'viewport_cols': 80,
          'dirty_ranges': <Object?>[
            <String, Object?>{'start': 0, 'end': 1},
          ],
          'scrollback_offset': 0,
          'scrollback_max_offset': 0,
        };
      }

      await _pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        notificationSender:
            ({required title, body, identifier, expiresAfterMs}) async {
              notifications.add({
                'title': title,
                'body': body,
                'identifier': identifier,
              });
            },
      );

      await _tapTabContextMenuAction(tester, 'Split right');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final splitState = container.read(sessionControllerProvider);
      final activeSessionId = splitState.activeSessionId!;
      final tab = splitState.tabs.single;
      final inactivePane = tab.effectivePanes.firstWhere(
        (pane) => pane.sessionId != activeSessionId,
      );
      final inactiveSessionId = inactivePane.sessionId;
      final inactivePaneIndex = tab.effectivePanes.indexWhere(
        (pane) => pane.sessionId == inactiveSessionId,
      );
      final inactivePaneLabel =
          '${inactivePane.title} pane ${inactivePaneIndex + 1} '
          '($inactiveSessionId)';

      fakeBindings.setFrame(
        inactiveSessionId,
        frameWithText('inactive output one'),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump(const Duration(milliseconds: 40));
      fakeBindings.setFrame(
        inactiveSessionId,
        frameWithText('inactive output two'),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      fakeBindings.enqueueEvent(
        inactiveSessionId,
        PtyEvent(kind: 'bell', sessionId: inactiveSessionId),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      fakeBindings.enqueueEvent(
        inactiveSessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: inactiveSessionId,
          payload: const <String, Object?>{'code': 7},
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      final activityNotifications = notifications
          .where(
            (notification) =>
                notification['title'] == 'Activity in $inactivePaneLabel' &&
                notification['identifier'] ==
                    'ianvs-terminal.activity.$inactiveSessionId',
          )
          .toList(growable: false);
      expect(activityNotifications, hasLength(1));
      expect(
        activityNotifications.single['body'],
        startsWith('inactive output'),
      );
      expect(
        notifications.where(
          (notification) =>
              notification['title'] == 'Bell in $inactivePaneLabel' &&
              notification['body'] == 'The terminal requested attention.' &&
              notification['identifier'] ==
                  'ianvs-terminal.bell.$inactiveSessionId',
        ),
        hasLength(1),
      );
      expect(
        notifications.where(
          (notification) =>
              notification['title'] == 'Session ended' &&
              notification['body'] ==
                  '$inactivePaneLabel exited with code 7.' &&
              notification['identifier']?.startsWith(
                    'ianvs-terminal.exit.$inactiveSessionId.',
                  ) ==
                  true,
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('OSC notification permission failures stay visible', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      notificationSender:
          ({required title, body, identifier, expiresAfterMs}) async {
            throw PlatformException(
              code: 'notification_authorization_failed',
              message: 'denied',
            );
          },
    );

    await _tapCommandMenuAction(tester, const Key('shell-top-new-tab'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'session_notification',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'osc777',
          'title': 'Deploy',
          'message': 'Needs attention',
        },
      ),
    );
    container.read(terminalRuntimeControllerProvider).refreshSession('1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('NOTIFY BLOCKED'), findsOneWidget);
    expect(
      find.byTooltip(
        'macOS notifications are blocked for Ianvs Terminal. Enable them in System Settings > Notifications.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'macOS notifications are blocked for Ianvs Terminal. Enable them in System Settings > Notifications.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('notification toggles read and write local config when present', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final legacyPreferencesRepository = _RecordingAppPreferencesRepository(
      const TerminalAppPreferencesDocument(
        notifications: TerminalAppNotifications(
          commandFinished: true,
          bell: true,
          activity: true,
        ),
      ),
    );
    final localConfigRepository = _MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        workspace: LocalTerminalWorkspaceConfig(restoreLayout: true),
        notifications: LocalTerminalNotificationsConfig(
          enabled: true,
          commandFinished: false,
          bell: true,
          activity: true,
        ),
      ),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      preferencesRepository: legacyPreferencesRepository,
      localConfigRepository: localConfigRepository,
    );

    await _openCommandMenu(tester);
    await tester.ensureVisible(
      find.byKey(const Key('shell-toggle-command-finished-notify')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enable command-finished notifications'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('shell-toggle-command-finished-notify')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Command-finished notifications enabled and saved.'),
      findsOneWidget,
    );
    expect(legacyPreferencesRepository.savedDocuments, isEmpty);
    expect(localConfigRepository.savedDocuments, hasLength(1));
    final savedConfig = localConfigRepository.savedDocuments.single;
    expect(savedConfig.workspace.restoreLayout, isTrue);
    expect(savedConfig.notifications.enabled, isTrue);
    expect(savedConfig.notifications.commandFinished, isTrue);
    expect(savedConfig.notifications.bell, isTrue);
    expect(savedConfig.notifications.activity, isTrue);
  });

  testWidgets('notification save merges the latest local config document', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final localConfigRepository = _MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        defaultProfileId: 'initial',
        notifications: LocalTerminalNotificationsConfig(
          enabled: true,
          commandFinished: false,
          bell: false,
          activity: true,
        ),
      ),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: localConfigRepository,
    );
    await localConfigRepository.save(
      const LocalTerminalConfigDocument(
        defaultProfileId: 'external',
        paste: LocalTerminalPasteConfig(
          bracketedPaste: LocalTerminalBracketedPastePolicy.force,
          confirmLargePaste: false,
        ),
        notifications: LocalTerminalNotificationsConfig(
          enabled: true,
          commandFinished: false,
          bell: false,
          activity: true,
        ),
      ),
    );
    localConfigRepository.savedDocuments.clear();

    await _tapCommandMenuAction(
      tester,
      const Key('shell-toggle-command-finished-notify'),
    );

    expect(localConfigRepository.savedDocuments, hasLength(1));
    final savedConfig = localConfigRepository.savedDocuments.single;
    expect(savedConfig.defaultProfileId, 'external');
    expect(
      savedConfig.paste.bracketedPaste,
      LocalTerminalBracketedPastePolicy.force,
    );
    expect(savedConfig.paste.confirmLargePaste, isFalse);
    expect(savedConfig.notifications.commandFinished, isTrue);
    expect(savedConfig.notifications.bell, isFalse);
  });

  testWidgets('shell shortcuts honor local config keybinding overrides', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final fakeBindings = FakePtyBackend();
    final localConfigRepository = _MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        keybindings: LocalTerminalKeybindingsConfig(
          overrides: {
            TerminalActionId.openDefaults: LocalTerminalKeyBindingOverride(
              binding: LocalTerminalKeyBinding(
                scope: TerminalKeyBindingScope.focusedApp,
                key: 'Key N',
                meta: true,
              ),
            ),
          },
        ),
      ),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: localConfigRepository,
    );
    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;

    expect(find.byTooltip('Close defaults'), findsOneWidget);
  });

  testWidgets('paste clipboard confirms multiline text before sending', (
    tester,
  ) async {
    const clipboardText = 'one\ntwo';
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

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    await _tapCommandMenuAction(tester, const Key('shell-top-paste-clipboard'));

    expect(find.byKey(const Key('paste-confirmation-dialog')), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Paste'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(fakeBindings.writes, hasLength(1));
    expect(utf8.decode(fakeBindings.writes.single), contains(clipboardText));
  });

  testWidgets(
    'OSC 5522 MIME paste mode advertises types without reading or pasting text',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      var clipboardReads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            clipboardReads += 1;
            return <String, dynamic>{'text': 'must not be pasted'};
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
        fakeBindings: fakeBindings,
        clipboardMimeTypeList: () async => <String>['text/plain', 'image/png'],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      fakeBindings.setFrame(sessionId, <String, Object?>{
        'rows': <Object?>[],
        'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'modes': <String, Object?>{'bracketed_paste': true, 'mime_paste': true},
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();

      expect(
        find.byKey(const Key('shell-status-mode-mime-paste')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('shell-status-mode-paste')), findsNothing);

      await _tapCommandMenuAction(
        tester,
        const Key('shell-top-paste-clipboard'),
      );
      await tester.pump();

      final packets = fakeBindings.writes.map(ascii.decode).toList();
      expect(clipboardReads, 0);
      expect(packets, hasLength(4));
      expect(packets.first, startsWith('\u001b]5522;type=read:status=OK:pw='));
      expect(
        packets,
        contains('\u001b]5522;type=read:status=DATA:mime=aW1hZ2UvcG5n\u001b\\'),
      );
      expect(
        packets,
        contains(
          '\u001b]5522;type=read:status=DATA:mime=dGV4dC9wbGFpbg==\u001b\\',
        ),
      );
      expect(packets.last, '\u001b]5522;type=read:status=DONE\u001b\\');
      expect(packets.join(), isNot(contains('must not be pasted')));
      expect(packets.join(), isNot(contains('\u001b[200~')));
    },
  );

  testWidgets('local paste config can disable multiline confirmation', (
    tester,
  ) async {
    const clipboardText = 'one\ntwo';
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
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          paste: LocalTerminalPasteConfig(confirmMultilinePaste: false),
        ),
      ),
    );

    await _tapCommandMenuAction(tester, const Key('shell-top-paste-clipboard'));

    expect(find.byKey(const Key('paste-confirmation-dialog')), findsNothing);
    expect(fakeBindings.writes, hasLength(1));
    expect(utf8.decode(fakeBindings.writes.single), contains(clipboardText));
  });

  testWidgets('local paste config can force bracketed paste wrapping', (
    tester,
  ) async {
    const clipboardText =
        'safe\x1B[201~echo unsafe\x1B[200~tail\u{009B}200~end\u{009B}201~';
    const sanitizedText = 'safeecho unsafetailend';
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
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          paste: LocalTerminalPasteConfig(
            bracketedPaste: LocalTerminalBracketedPastePolicy.force,
          ),
        ),
      ),
    );

    await _tapCommandMenuAction(tester, const Key('shell-top-paste-clipboard'));

    expect(
      fakeBindings.writes.single,
      ascii.encode('\x1B[200~') +
          utf8.encode(sanitizedText) +
          ascii.encode('\x1B[201~'),
    );
  });

  testWidgets('marker-only forced bracketed paste is ignored', (tester) async {
    const clipboardText = '\x1B[200~\x1B[201~\u{009B}200~\u{009B}201~';
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
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          paste: LocalTerminalPasteConfig(
            bracketedPaste: LocalTerminalBracketedPastePolicy.force,
          ),
        ),
      ),
    );

    await _tapCommandMenuAction(tester, const Key('shell-top-paste-clipboard'));

    expect(fakeBindings.writes, isEmpty);
    expect(fakeBindings.writesBySession, isEmpty);
  });

  testWidgets(
    'local paste config can force plain paste despite terminal mode',
    (tester) async {
      const clipboardText = 'plain paste';
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
        fakeBindings: fakeBindings,
        localConfigRepository: _MemoryLocalTerminalConfigRepository(
          const LocalTerminalConfigDocument(
            paste: LocalTerminalPasteConfig(
              bracketedPaste: LocalTerminalBracketedPastePolicy.plain,
            ),
          ),
        ),
      );
      fakeBindings.setFrame(1, <String, Object?>{
        'rows': <Object?>[],
        'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'modes': <String, Object?>{'bracketed_paste': true},
      });
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      container.read(terminalRuntimeControllerProvider).refreshSession('1');
      await tester.pump();

      await _tapCommandMenuAction(
        tester,
        const Key('shell-top-paste-clipboard'),
      );

      expect(fakeBindings.writes.single, utf8.encode(clipboardText));
    },
  );

  testWidgets('command menu hides advanced paste', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          paste: LocalTerminalPasteConfig(
            bracketedPaste: LocalTerminalBracketedPastePolicy.force,
          ),
        ),
      ),
    );

    await _openCommandMenu(tester);

    expect(find.byKey(const Key('shell-advanced-paste')), findsNothing);
    expect(find.text('Advanced paste'), findsNothing);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'command-v uses paste confirmation before sending multiline text',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      const clipboardText = 'one\ntwo';
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

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pumpAndSettle();

      debugDefaultTargetPlatformOverride = null;

      expect(
        find.byKey(const Key('paste-confirmation-dialog')),
        findsOneWidget,
      );
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets('command-v honors forced bracketed paste wrapping', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const clipboardText =
        'keyboard\x1B[201~paste\x1B[200~\u{009B}200~safe\u{009B}201~';
    const sanitizedText = 'keyboardpastesafe';
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
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          paste: LocalTerminalPasteConfig(
            bracketedPaste: LocalTerminalBracketedPastePolicy.force,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;

    expect(fakeBindings.writes, hasLength(1));
    expect(
      fakeBindings.writes.single,
      ascii.encode('\x1B[200~') +
          utf8.encode(sanitizedText) +
          ascii.encode('\x1B[201~'),
    );
  });

  testWidgets('command-v read-only paste does not read clipboard', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final fakeBindings = FakePtyBackend();
    var clipboardReads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          clipboardReads += 1;
          return <String, dynamic>{'text': 'blocked command-v paste'};
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

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-toggle-read-only')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shell-toggle-read-only')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;

    expect(clipboardReads, 0);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('tab context menu hides pane zoom actions', (tester) async {
    await _pumpShellScreen(tester, fakeBindings: FakePtyBackend());

    await _openTabContextMenu(tester);

    expect(find.text('Zoom active pane'), findsNothing);
    expect(find.text('Unzoom active pane'), findsNothing);
  });

  testWidgets('tab context menu hides focus pane actions while zoomed', (
    tester,
  ) async {
    await _pumpShellScreen(tester, fakeBindings: FakePtyBackend());

    await _tapTabContextMenuAction(tester, 'Split right');
    await _tapActivePaneZoomAction(tester);

    await _openTabContextMenu(tester);

    expect(find.text('Focus next pane'), findsNothing);
    expect(find.text('Focus previous pane'), findsNothing);
    expect(find.text('Zoom active pane'), findsNothing);
    expect(find.text('Unzoom active pane'), findsNothing);
    expect(
      find.textContaining(
        'Unavailable: Unzoom the active pane to manage other panes.',
      ),
      findsNWidgets(4),
    );
  });

  testWidgets(
    'command-v pastes into the open search field instead of the terminal',
    (tester) async {
      const clipboardText = 'needle';
      var clipboardReads = 0;
      final fakeBindings = FakePtyBackend();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            clipboardReads += 1;
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

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyF);

      expect(find.byKey(const Key('terminal-search-field')), findsOneWidget);

      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyV);

      final searchField = tester.widget<TextField>(
        find.byKey(const Key('terminal-search-field')),
      );
      expect(searchField.controller?.text, clipboardText);
      expect(fakeBindings.writes, isEmpty);
      expect(clipboardReads, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'native paste menu pastes into the open search field instead of the terminal',
    (tester) async {
      const clipboardText = 'native needle';
      var clipboardReads = 0;
      final fakeBindings = FakePtyBackend();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            clipboardReads += 1;
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

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyF);

      expect(find.byKey(const Key('terminal-search-field')), findsOneWidget);

      await _invokeNativeWindowBridge(tester, const MethodCall('nativePaste'));

      final searchField = tester.widget<TextField>(
        find.byKey(const Key('terminal-search-field')),
      );
      expect(searchField.controller?.text, clipboardText);
      expect(fakeBindings.writes, isEmpty);
      expect(clipboardReads, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('zoom active pane hides the split sibling and can unzoom', (
    tester,
  ) async {
    await _pumpShellScreen(tester, fakeBindings: FakePtyBackend());

    await _tapTabContextMenuAction(tester, 'Split right');

    expect(find.byType(TerminalViewport), findsNWidgets(2));
    expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-bar')), findsOneWidget);

    await _tapActivePaneZoomAction(tester);

    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-bar')), findsOneWidget);

    await _tapActivePaneZoomAction(tester);

    expect(find.byType(TerminalViewport), findsNWidgets(2));
    expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-bar')), findsOneWidget);
  });

  testWidgets('tab context menu disables split actions while pane is zoomed', (
    tester,
  ) async {
    await _pumpShellScreen(tester, fakeBindings: FakePtyBackend());

    await _tapTabContextMenuAction(tester, 'Split right');
    await _tapActivePaneZoomAction(tester);

    await _openTabContextMenu(tester);

    expect(find.text('Split right'), findsOneWidget);
    expect(find.text('Split down'), findsOneWidget);
    expect(
      find.textContaining(
        'Unavailable: Unzoom the active pane to manage other panes.',
      ),
      findsNWidgets(4),
    );

    expect(find.byType(TerminalViewport), findsOneWidget);
  });

  testWidgets(
    'tab context menu can reopen the most recently closed split pane',
    (tester) async {
      await _pumpShellScreen(tester, fakeBindings: FakePtyBackend());

      await _openTabContextMenu(tester);
      expect(find.text('Reopen closed pane'), findsOneWidget);
      expect(
        find.textContaining(
          'No recently closed pane is available for this tab.',
        ),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await _tapTabContextMenuAction(tester, 'Split right');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final splitState = container.read(sessionControllerProvider);
      final closedSessionId = splitState.activeSessionId!;
      final retainedSessionId = splitState.tabs.single.effectivePanes
          .firstWhere((pane) => pane.sessionId != closedSessionId)
          .sessionId;

      await tester.tap(
        find.byKey(Key('shell-pane-action-close-$closedSessionId')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalViewport), findsOneWidget);
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        retainedSessionId,
      );

      await _tapTabContextMenuAction(tester, 'Reopen closed pane');

      final reopenedState = container.read(sessionControllerProvider);
      final reopenedSessionId = reopenedState.activeSessionId!;
      expect(reopenedSessionId, isNot(closedSessionId));
      expect(reopenedState.tabs.single.effectivePanes, hasLength(2));
      expect(find.byType(TerminalViewport), findsNWidgets(2));
      expect(find.byKey(Key('shell-pane-$retainedSessionId')), findsOneWidget);
      expect(find.byKey(Key('shell-pane-$reopenedSessionId')), findsOneWidget);
      expect(find.byKey(Key('shell-pane-$closedSessionId')), findsNothing);
    },
  );

  testWidgets('tab badge activation keeps zoomed pane visible for the target', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    await _tapActivePaneZoomAction(tester);

    expect(find.byKey(Key('shell-pane-$activeSessionId')), findsOneWidget);
    expect(find.byKey(Key('shell-pane-$inactiveSessionId')), findsNothing);

    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{'text': 'Deploy'},
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('shell-tab-badge-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-tab-badge-1')));
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );
    expect(find.byKey(Key('shell-pane-$inactiveSessionId')), findsOneWidget);
    expect(find.byKey(Key('shell-pane-$activeSessionId')), findsNothing);
    expect(find.byKey(const Key('shell-status-badge')), findsOneWidget);
  });

  testWidgets(
    'tab pane signal focuses zoom-hidden progress and notification pane',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      await _tapTabContextMenuAction(tester, 'Split right');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final splitState = container.read(sessionControllerProvider);
      final activeSessionId = splitState.activeSessionId!;
      final inactiveSessionId = splitState.tabs.single.effectivePanes
          .firstWhere((pane) => pane.sessionId != activeSessionId)
          .sessionId;

      await _tapActivePaneZoomAction(tester);

      expect(find.byKey(Key('shell-pane-$activeSessionId')), findsOneWidget);
      expect(find.byKey(Key('shell-pane-$inactiveSessionId')), findsNothing);

      fakeBindings.enqueueEvent(
        inactiveSessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: inactiveSessionId,
          payload: const <String, Object?>{
            'source': 'osc934',
            'named': true,
            'action': 'set',
            'id': 'build',
            'state': 'normal',
            'percent': 67,
            'label': 'Deploy',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        inactiveSessionId,
        PtyEvent(
          kind: 'session_notification',
          sessionId: inactiveSessionId,
          payload: const <String, Object?>{
            'source': 'osc777',
            'title': 'Deploy',
            'message': 'Inactive pane done',
          },
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byKey(const Key('shell-tab-pane-signal-1')), findsOneWidget);
      expect(find.text('PROG +1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-pane-signal-1')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains('Terminal progress in a split pane') ==
                    true &&
                widget.message?.contains('inactive pane') == true &&
                widget.message?.contains('Other pane signals') == true &&
                widget.message?.contains('NOTE Deploy') == true &&
                widget.message?.contains('Click to focus the first pane') ==
                    true,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-pane-signal-1')));
      await tester.pump();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveSessionId,
      );
      expect(find.byKey(Key('shell-pane-$inactiveSessionId')), findsOneWidget);
      expect(find.byKey(Key('shell-pane-$activeSessionId')), findsNothing);
      expect(find.byKey(const Key('shell-status-progress')), findsOneWidget);
      expect(
        find.byKey(const Key('shell-status-notification')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tab pane signal prioritizes zoom-hidden inactive pane over active pane signal',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      await _tapTabContextMenuAction(tester, 'Split right');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final splitState = container.read(sessionControllerProvider);
      final activeSessionId = splitState.activeSessionId!;
      final inactiveSessionId = splitState.tabs.single.effectivePanes
          .firstWhere((pane) => pane.sessionId != activeSessionId)
          .sessionId;

      await _tapActivePaneZoomAction(tester);

      fakeBindings.enqueueEvent(
        activeSessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: activeSessionId,
          payload: const <String, Object?>{
            'source': 'osc934',
            'named': true,
            'action': 'set',
            'id': 'active',
            'state': 'normal',
            'percent': 12,
            'label': 'Active',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        inactiveSessionId,
        PtyEvent(
          kind: 'session_notification',
          sessionId: inactiveSessionId,
          payload: const <String, Object?>{
            'source': 'osc777',
            'title': 'Deploy',
            'message': 'Zoom-hidden pane done',
          },
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(activeSessionId);
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byKey(Key('shell-pane-$activeSessionId')), findsOneWidget);
      expect(find.byKey(Key('shell-pane-$inactiveSessionId')), findsNothing);
      expect(find.byKey(const Key('shell-status-progress')), findsOneWidget);
      expect(find.byKey(const Key('shell-status-notification')), findsNothing);
      expect(find.byKey(const Key('shell-tab-pane-signal-1')), findsOneWidget);
      expect(find.text('NOTE +1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-pane-signal-1')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains(
                      'Terminal notification in a split pane',
                    ) ==
                    true &&
                widget.message?.contains('inactive pane') == true &&
                widget.message?.contains('Other pane signals') == true &&
                widget.message?.contains('PROG ACTIVE 12%') == true &&
                widget.message?.contains(
                      'Click to focus the first pane with a signal.',
                    ) ==
                    true,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-pane-signal-1')));
      await tester.pump();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveSessionId,
      );
      expect(find.byKey(Key('shell-pane-$inactiveSessionId')), findsOneWidget);
      expect(find.byKey(Key('shell-pane-$activeSessionId')), findsNothing);
      expect(
        find.byKey(const Key('shell-status-notification')),
        findsOneWidget,
      );
    },
  );

  testWidgets('split tab semantics describe pane signals and new output', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final tab = splitState.tabs.single;
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = tab.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'session_badge',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{'text': 'Deploy'},
      ),
    );
    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'session_progress',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{
          'source': 'osc934',
          'named': true,
          'action': 'set',
          'id': 'deploy',
          'state': 'normal',
          'percent': 42,
          'label': 'Deploy',
        },
      ),
    );
    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'session_notification',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{
          'source': 'osc777',
          'title': 'Deploy',
          'message': 'Inactive pane done',
        },
      ),
    );
    fakeBindings.setFrame(inactiveSessionId, <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'inactive pane output',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 20, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    final semantics = tester.getSemantics(
      find.bySemanticsIdentifier('shell-tab-${tab.sessionId}'),
    );
    expect(semantics.label, contains('badge Deploy from inactive pane'));
    expect(
      semantics.label,
      contains('terminal progress: DEPLOY 42% from inactive pane'),
    );
    expect(semantics.label, contains('plus 1 other pane signal'));
    expect(semantics.label, contains('new output in split pane'));
  });

  testWidgets('overflow pane signal can focus a hidden split pane', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile();
    for (var index = 0; index < 11; index += 1) {
      controller.createSession(profile);
    }
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    controller.activateSession('1');
    await tester.pumpAndSettle();

    final splitTab = container
        .read(sessionControllerProvider)
        .tabs
        .firstWhere((tab) => tab.sessionId == '12');
    final inactiveSplitSessionId = splitTab.effectivePanes
        .firstWhere((pane) => pane.sessionId != splitTab.activeSessionId)
        .sessionId;

    fakeBindings.enqueueEvent(
      inactiveSplitSessionId,
      PtyEvent(
        kind: 'session_progress',
        sessionId: inactiveSplitSessionId,
        payload: const <String, Object?>{
          'source': 'osc934',
          'named': true,
          'action': 'set',
          'id': 'deploy',
          'state': 'normal',
          'percent': 42,
          'label': 'Deploy',
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSplitSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('shell-tab-overflow-button')), findsOneWidget);
    expect(
      find.byKey(const Key('shell-tab-overflow-pane-signal')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.contains('Hidden pane signal: 1 pane') == true &&
            widget.message?.contains(
                  'Signal markers can focus their source panes.',
                ) ==
                true,
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('shell-tab-overflow-button')))
          .label,
      contains('1 hidden pane signal'),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-tab-overflow-pane-signal')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('Terminal progress in a hidden tab') ==
                  true &&
              widget.message?.contains('inactive pane') == true &&
              widget.message?.contains('Click to focus this pane') == true,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('shell-tab-overflow-pane-signal')));
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSplitSessionId,
    );
    expect(find.byKey(const Key('shell-status-progress')), findsOneWidget);

    controller.activateSession('1');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('shell-tab-overflow-pane-signal')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-tab-overflow-panel')), findsOneWidget);
    expect(
      find.byKey(const Key('shell-tab-overflow-pane-signal')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shell-tab-overflow-pane-signal-12')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('shell-tab-overflow-pane-signal-12')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSplitSessionId,
    );
    expect(find.byKey(const Key('shell-status-progress')), findsOneWidget);
  });

  testWidgets(
    'hidden overflow pane signal marks active hidden pane as already focused',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final profile = defaultTerminalProfile();
      for (var index = 0; index < 11; index += 1) {
        controller.createSession(profile);
      }
      controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
      await tester.pumpAndSettle();

      final activeSplitSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      fakeBindings.enqueueEvent(
        activeSplitSessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: activeSplitSessionId,
          payload: const <String, Object?>{
            'source': 'osc934',
            'named': true,
            'action': 'set',
            'id': 'deploy',
            'state': 'normal',
            'percent': 42,
            'label': 'Deploy',
          },
        ),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(activeSplitSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        find.byKey(const Key('shell-tab-overflow-pane-signal')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-overflow-pane-signal')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains('Terminal progress in a hidden tab') ==
                    true &&
                widget.message?.contains('active pane') == true &&
                widget.message?.contains('Pane already focused.') == true &&
                widget.message?.contains('Click to focus this pane') == false,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-overflow-pane-signal')));
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        activeSplitSessionId,
      );
      expect(find.byKey(const Key('shell-status-progress')), findsOneWidget);
    },
  );

  testWidgets('close tab shortcut closes every pane in the active tab', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final fakeBindings = FakePtyBackend();
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          clipboard: LocalTerminalClipboardConfig(
            osc52: LocalTerminalOsc52Policy.disabled,
          ),
        ),
      ),
    );
    await _tapTabContextMenuAction(tester, 'Split right');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    expect(
      container.read(sessionControllerProvider).tabs.single.effectivePanes,
      hasLength(2),
    );

    await _tapCommandMenuAction(tester, const Key('shell-top-new-tab'));
    await tester.tap(find.byKey(const Key('shell-tab-1')));
    await tester.pumpAndSettle();

    final splitState = container.read(sessionControllerProvider);
    final splitTab = splitState.tabs.firstWhere((tab) => tab.sessionId == '1');
    final inactiveSplitSessionId = splitTab.effectivePanes
        .firstWhere((pane) => pane.sessionId != splitTab.activeSessionId)
        .sessionId;
    fakeBindings.enqueueEvent(
      inactiveSplitSessionId,
      PtyEvent(
        kind: 'clipboard_copy',
        sessionId: inactiveSplitSessionId,
        payload: <String, Object?>{
          'selection': 'c',
          'data': base64.encode(utf8.encode('closing tab pane copy')),
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSplitSessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('shell-status-osc52')), findsOneWidget);
    expect(find.textContaining('inactive pane'), findsOneWidget);

    await tester.tap(find.byType(TerminalViewport).last);
    await tester.pump();
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(container.read(sessionControllerProvider).tabs, hasLength(1));
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.byKey(const Key('shell-status-osc52')), findsNothing);
    expect(find.textContaining('closing tab pane copy'), findsNothing);
  });

  testWidgets('command menu hides hotkey window registration failures', (
    tester,
  ) async {
    final windowBridgeCalls = <MethodCall>[];
    const channel = MethodChannel('app/window_bridge');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      windowBridgeCalls.add(call);
      if (call.method == 'hotkeyStatus') {
        return <String, Object?>{
          'registered': false,
          'shortcut': 'Option+Command+Space',
          'errorCode': -9876,
        };
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpShellScreen(tester, fakeBindings: FakePtyBackend());

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Hotkey window'), findsNothing);
    expect(find.textContaining('Hotkey window is unavailable.'), findsNothing);
    expect(
      find.textContaining('Shortcut: Option+Command+Space.'),
      findsNothing,
    );
    expect(find.textContaining('Error: -9876.'), findsNothing);
    expect(
      windowBridgeCalls.map((call) => call.method),
      isNot(contains('hotkeyStatus')),
    );
    expect(
      windowBridgeCalls.map((call) => call.method),
      isNot(contains('toggleHotkeyWindow')),
    );
  });

  testWidgets(
    'shell coalesces rapid window-width changes into the final terminal resize',
    (tester) async {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final fakeBindings = FakePtyBackend();
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final initialResizeCount = fakeBindings.resizeCalls.length;

      tester.view.physicalSize = const Size(1480, 1200);
      await tester.pump();
      tester.view.physicalSize = const Size(1320, 1200);
      await tester.pump(const Duration(milliseconds: 120));

      expect(fakeBindings.resizeCalls.length, initialResizeCount);

      await tester.pump(const Duration(milliseconds: 260));

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final resizeCall = fakeBindings.resizeCalls.last;

      expect(fakeBindings.resizeCalls.length, initialResizeCount + 1);
      expect(
        resizeCall[1],
        (renderObject.size.width / renderObject.debugCellSize.width).floor(),
      );
      expect(
        resizeCall[2],
        (renderObject.size.height / renderObject.debugCellSize.height).floor(),
      );
      expect(
        resizeCall[3],
        (renderObject.size.width * tester.view.devicePixelRatio).round(),
      );
      expect(
        resizeCall[4],
        (renderObject.size.height * tester.view.devicePixelRatio).round(),
      );
    },
  );

  testWidgets('split panes each commit their debounced terminal resize', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeBindings = FakePtyBackend();
    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    final initialResizeCount = fakeBindings.resizeCalls.length;

    tester.view.physicalSize = const Size(1480, 1200);
    await tester.pump();
    tester.view.physicalSize = const Size(1320, 1200);
    await tester.pump(const Duration(milliseconds: 120));

    expect(fakeBindings.resizeCalls.length, initialResizeCount);

    await tester.pump(const Duration(milliseconds: 260));

    final resizeCalls = fakeBindings.resizeCalls
        .skip(initialResizeCount)
        .toList(growable: false);
    expect(resizeCalls.map((call) => call[0]), unorderedEquals(<int>[1, 2]));

    for (final sessionId in const <String>['1', '2']) {
      final renderObject = _renderTerminalViewportForPane(tester, sessionId);
      final resizeCall = resizeCalls.singleWhere(
        (call) => call[0] == int.parse(sessionId),
      );
      expect(
        resizeCall[1],
        (renderObject.size.width / renderObject.debugCellSize.width).floor(),
      );
      expect(
        resizeCall[2],
        (renderObject.size.height / renderObject.debugCellSize.height).floor(),
      );
      expect(
        resizeCall[3],
        (renderObject.size.width * tester.view.devicePixelRatio).round(),
      );
      expect(
        resizeCall[4],
        (renderObject.size.height * tester.view.devicePixelRatio).round(),
      );
    }
  });

  testWidgets('terminal focus alone does not show the shell workspace cue', (
    tester,
  ) async {
    await _pumpShellScreen(tester, fakeBindings: FakePtyBackend());

    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    expect(find.byKey(const Key('shell-workspace-focus-cue')), findsNothing);
  });

  testWidgets('shell passes theme-aware terminal colors into the viewport', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      themeMode: ThemeMode.light,
    );

    var renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    expect(
      renderObject.debugColors.canvasBackground.toARGB32(),
      const Color(0xFFF8F7F2).toARGB32(),
    );
    expect(
      renderObject.debugColors.foreground.toARGB32(),
      const Color(0xFF111111).toARGB32(),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      themeMode: ThemeMode.dark,
    );
    renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    expect(
      renderObject.debugColors.canvasBackground.toARGB32(),
      const Color(0xFF050608).toARGB32(),
    );
    expect(
      renderObject.debugColors.foreground.toARGB32(),
      const Color(0xFFF8FAFC).toARGB32(),
    );
  });

  testWidgets(
    'launcher close shows a brief return cue at top right and keeps keyboard path',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      expect(find.byKey(const Key('shell-workspace-focus-cue')), findsNothing);

      await _openCommandMenu(tester);
      await tester.tap(find.byTooltip('Close actions'));
      await tester.pumpAndSettle();

      final cueFinder = find.byKey(const Key('shell-workspace-focus-cue'));
      expect(cueFinder, findsOneWidget);
      expect(find.text('Back in shell'), findsOneWidget);

      final cueRect = tester.getRect(cueFinder);
      final viewportRect = tester.getRect(find.byType(TerminalViewport));
      expect(cueRect.left, greaterThan(viewportRect.center.dx));
      expect(cueRect.top, lessThan(viewportRect.top + 40));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.pump();

      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, 'v'.codeUnits);

      await tester.pump(const Duration(milliseconds: 1600));
      expect(cueFinder, findsNothing);
    },
  );

  testWidgets('defaults close restores the workspace cue and keyboard path', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);

    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await _openCommandMenu(tester);
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close defaults'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-workspace-focus-cue')), findsOneWidget);
    expect(find.text('Back in shell'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.pump();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, 'v'.codeUnits);
  });
}
