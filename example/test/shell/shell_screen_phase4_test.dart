import 'dart:convert';

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
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';

Future<void> _pumpShellScreen(
  WidgetTester tester, {
  required FakePtyBackend fakeBindings,
  ThemeMode themeMode = ThemeMode.light,
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
          MemoryAppPreferencesRepository(null),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: themeMode,
        home: const ShellScreen(),
      ),
    ),
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

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.text('Paste clipboard'));
    await tester.tap(find.text('Paste clipboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('paste-confirmation-dialog')), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Paste'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(fakeBindings.writes, hasLength(1));
    expect(utf8.decode(fakeBindings.writes.single), contains(clipboardText));
  });

  testWidgets('zoom active pane hides the split sibling and can unzoom', (
    tester,
  ) async {
    await _pumpShellScreen(tester, fakeBindings: FakePtyBackend());

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.text('Split right'));
    await tester.tap(find.text('Split right'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(TerminalViewport), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.text('Zoom active pane'));
    await tester.tap(find.text('Zoom active pane'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(TerminalViewport), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.text('Unzoom active pane'));
    await tester.tap(find.text('Unzoom active pane'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(TerminalViewport), findsNWidgets(2));
  });

  testWidgets('hotkey window failure is visible when registration is missing', (
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
    await tester.ensureVisible(find.text('Hotkey window'));
    await tester.tap(find.text('Hotkey window'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Hotkey window unavailable'), findsOneWidget);
    expect(find.textContaining('Option+Command+Space'), findsOneWidget);
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

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
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

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
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
