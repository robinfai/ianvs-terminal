import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/reference_demo.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';

Future<void> pumpShellScreen(
  WidgetTester tester, {
  required FakePtyBackend fakeBindings,
  required MemoryProfileRepository repository,
  bool referenceDemoMode = false,
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
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
        sessionDemoFixtureProvider.overrideWithValue(
          referenceDemoMode ? referenceDemoFixture : null,
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

Future<void> _pumpUntilCondition(
  WidgetTester tester, {
  required bool Function() condition,
  required String description,
  int maxTicks = 20,
}) async {
  for (var tick = 0; tick < maxTicks; tick += 1) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 33));
  }
  expect(condition(), isTrue, reason: 'Timed out waiting for $description.');
}

Future<void> sendMetaShortcut(
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

Future<void> openNewShellTab(WidgetTester tester) async {
  final newTabButton = find.byKey(const Key('shell-chrome-new-tab'));
  if (newTabButton.evaluate().isNotEmpty) {
    await tester.tap(newTabButton);
    await tester.pumpAndSettle();
  } else {
    await sendMetaShortcut(tester, LogicalKeyboardKey.keyT);
  }

  expect(find.byKey(const Key('new-session-launcher')), findsOneWidget);
  await tester.tap(find.byKey(const Key('new-local-session-default')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shell screen exposes a selected tab in the hyper-style strip', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.byKey(const Key('shell-tab-strip')), findsOneWidget);
    expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('shell-tab-1')),
      matchesSemantics(
        label: 'Local Shell tab, Command 1',
        hasSelectedState: true,
        isButton: true,
        isSelected: true,
      ),
    );
    expect(find.bySemanticsLabel('New tab'), findsOneWidget);
    expect(find.bySemanticsLabel('Open command palette'), findsOneWidget);
  });

  testWidgets(
    'shell screen keeps tab hierarchy clear after opening a second tab',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await openNewShellTab(tester);

      expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('shell-tab-2')),
        matchesSemantics(
          hasSelectedState: true,
          isButton: true,
          isSelected: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('shell-tab-1')),
        matchesSemantics(hasSelectedState: true, isButton: true),
      );
    },
  );

  testWidgets('shell tabs share the available strip width before overflow', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    final stripWidth = tester
        .getSize(find.byKey(const Key('shell-tab-strip')))
        .width;
    final singleTabWidth = tester
        .getSize(find.byKey(const Key('shell-tab-1')))
        .width;
    expect(singleTabWidth, closeTo(stripWidth - 40, 1));

    await openNewShellTab(tester);

    final firstTabWidth = tester
        .getSize(find.byKey(const Key('shell-tab-1')))
        .width;
    final secondTabWidth = tester
        .getSize(find.byKey(const Key('shell-tab-2')))
        .width;
    expect(firstTabWidth, closeTo(secondTabWidth, 1));
    expect(firstTabWidth, closeTo((stripWidth - 40) / 2, 1));
    expect(find.byKey(const Key('shell-tab-overflow-button')), findsNothing);

    await openNewShellTab(tester);

    final threeTabWidths = [
      tester.getSize(find.byKey(const Key('shell-tab-1'))).width,
      tester.getSize(find.byKey(const Key('shell-tab-2'))).width,
      tester.getSize(find.byKey(const Key('shell-tab-3'))).width,
    ];
    expect(threeTabWidths[0], closeTo(threeTabWidths[1], 1));
    expect(threeTabWidths[1], closeTo(threeTabWidths[2], 1));
    expect(threeTabWidths[0], closeTo((stripWidth - 40) / 3, 1));
    expect(
      tester.getRect(find.byKey(const Key('shell-chrome-new-tab'))).right,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('shell-tab-strip'))).right + 0.1,
      ),
    );
    expect(find.byKey(const Key('shell-tab-overflow-button')), findsNothing);
  });

  testWidgets('shell chrome background follows the application theme', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(
          profiles: [_profileWithTerminalBackground('#11141A')],
        ),
      ),
    );

    final activeBackground = _tabButtonBackground(
      tester,
      const Key('shell-tab-1'),
      const <WidgetState>{},
    );
    expect(activeBackground, isNot(const Color(0xFF11141A)));
    expect(_channelSpread(activeBackground), lessThanOrEqualTo(18));
    expect(
      activeBackground.computeLuminance(),
      greaterThan(const Color(0xFF11141A).computeLuminance()),
    );
    expect(
      _tabButtonOverlay(tester, const Key('shell-tab-1'), {
        WidgetState.hovered,
      }),
      Colors.transparent,
    );
    expect(
      _iconButtonOverlay(tester, const Key('shell-chrome-new-tab'), {
        WidgetState.hovered,
      }),
      Colors.transparent,
    );
    final newTabHoverBackground = _iconButtonBackground(
      tester,
      const Key('shell-chrome-new-tab'),
      const <WidgetState>{WidgetState.hovered},
    )!;
    expect(_channelSpread(newTabHoverBackground), lessThanOrEqualTo(18));
    expect(
      _decoratedBoxColor(tester, const Key('shell-chrome-bar')),
      const Color(0xFFF5F5F7),
    );
    expect(
      _decoratedBoxColor(tester, const Key('shell-chrome-title-surface')),
      const Color(0xFFF9FAFB),
    );
    expect(
      _decoratedBoxColor(tester, const Key('shell-chrome-tab-rail-surface')),
      const Color(0xFFEDEEF2),
    );
    expect(
      _decoratedBoxColor(tester, const Key('shell-chrome-tab-track')),
      const Color(0xB3D9DBE1),
    );
    expect(find.byKey(const Key('shell-status-bar')), findsNothing);

    await openNewShellTab(tester);

    final inactiveBackground = _tabButtonBackground(
      tester,
      const Key('shell-tab-1'),
      const <WidgetState>{},
    );
    expect(inactiveBackground, Colors.transparent);
    final inactiveBorder = _decoratedBoxBorder(
      tester,
      const Key('shell-tab-border-1'),
    );
    expect(inactiveBorder, isNull);
    final hoverBackground = _tabButtonBackground(
      tester,
      const Key('shell-tab-1'),
      const <WidgetState>{WidgetState.hovered},
    );
    expect(_channelSpread(hoverBackground), lessThanOrEqualTo(18));
    expect(
      hoverBackground.computeLuminance(),
      greaterThan(inactiveBackground.computeLuminance()),
    );
  });

  testWidgets('shell tabs overflow into a selector at readable widths', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    for (var index = 0; index < 11; index += 1) {
      await openNewShellTab(tester);
    }

    expect(find.byKey(const Key('shell-tab-overflow-button')), findsOneWidget);
    expect(
      find.byKey(const Key('shell-tab-overflow-ellipsis')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell-chrome-new-tab')), findsNothing);
    expect(find.bySemanticsIdentifier('shell-tab-12'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('shell-tab-1'))).width,
      greaterThanOrEqualTo(180),
    );

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-tab-overflow-panel')), findsOneWidget);
    expect(find.byKey(const Key('shell-tab-overflow-item-12')), findsOneWidget);
  });

  testWidgets(
    'shell tabs keep compact overflow controls inside narrow chrome',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      for (var index = 0; index < 7; index += 1) {
        await openNewShellTab(tester);
      }

      expect(tester.takeException(), isNull);
      final stripRect = tester.getRect(
        find.byKey(const Key('shell-tab-strip')),
      );
      final overflowRect = tester.getRect(
        find.byKey(const Key('shell-tab-overflow-button')),
      );

      expect(overflowRect.left, greaterThanOrEqualTo(stripRect.left - 0.1));
      expect(overflowRect.right, lessThanOrEqualTo(stripRect.right + 0.1));
      expect(overflowRect.width, lessThanOrEqualTo(40));
      expect(find.byKey(const Key('shell-chrome-new-tab')), findsNothing);

      await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('shell-tab-overflow-item-8')),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('inactive tabs mark and clear new output activity', (
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

    await openNewShellTab(tester);

    expect(find.byTooltip('New output'), findsNothing);

    fakeBindings.setFrame(1, _terminalFrame('background build done'));
    await _pumpUntilCondition(
      tester,
      description: 'inactive tab output marker',
      condition: () =>
          find.byKey(const Key('shell-tab-new-output-1')).evaluate().isNotEmpty,
    );

    expect(find.byKey(const Key('shell-tab-new-output-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-tab-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-tab-new-output-1')), findsNothing);
  });

  testWidgets('active split tab marks new output from inactive panes', (
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    container
        .read(sessionControllerProvider.notifier)
        .splitActiveSession(
          defaultTerminalProfile(),
          TerminalSplitAxis.horizontal,
        );
    await tester.pumpAndSettle();

    final splitState = container.read(sessionControllerProvider);
    final tab = splitState.tabs.single;
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = tab.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;

    expect(
      find.byKey(Key('shell-tab-new-output-${tab.sessionId}')),
      findsNothing,
    );

    fakeBindings.setFrame(inactiveSessionId, _terminalFrame('pane output'));
    await _pumpUntilCondition(
      tester,
      description: 'inactive pane output frame',
      condition: () => container
          .read(terminalRuntimeControllerProvider)
          .viewportFor(inactiveSessionId)
          .frame
          .rows
          .any((row) => row.text.contains('pane output')),
    );

    expect(
      find.byKey(Key('shell-tab-new-output-${tab.sessionId}')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(Key('shell-tab-new-output-${tab.sessionId}')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.contains('New output in a split pane.') == true &&
              widget.message?.contains('Pane:') == true &&
              widget.message?.contains('inactive pane') == true &&
              widget.message?.contains('Click to focus this pane.') == true,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('shell-tab-new-output-${tab.sessionId}')));
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).activeSessionId,
      inactiveSessionId,
    );
    expect(
      find.byKey(Key('shell-tab-new-output-${tab.sessionId}')),
      findsNothing,
    );
  });

  testWidgets(
    'focusing one split pane only clears that pane new output marker',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.horizontal,
      );
      await tester.pumpAndSettle();
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.vertical,
      );
      await tester.pumpAndSettle();

      final splitState = container.read(sessionControllerProvider);
      final tab = splitState.tabs.single;
      final activeSessionId = splitState.activeSessionId!;
      final inactiveSessionIds = tab.effectivePanes
          .where((pane) => pane.sessionId != activeSessionId)
          .map((pane) => pane.sessionId)
          .toList(growable: false);
      expect(inactiveSessionIds, hasLength(2));

      fakeBindings.setFrame(inactiveSessionIds[0], _terminalFrame('pane one'));
      await _pumpUntilCondition(
        tester,
        description: 'first inactive pane output frame',
        condition: () => container
            .read(terminalRuntimeControllerProvider)
            .viewportFor(inactiveSessionIds[0])
            .frame
            .rows
            .any((row) => row.text.contains('pane one')),
      );
      fakeBindings.setFrame(inactiveSessionIds[1], _terminalFrame('pane two'));
      await _pumpUntilCondition(
        tester,
        description: 'second inactive pane output frame',
        condition: () => container
            .read(terminalRuntimeControllerProvider)
            .viewportFor(inactiveSessionIds[1])
            .frame
            .rows
            .any((row) => row.text.contains('pane two')),
      );

      final tabDot = find.byKey(Key('shell-tab-new-output-${tab.sessionId}'));
      expect(tabDot, findsOneWidget);
      expect(
        find.descendant(
          of: tabDot,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains('New output in 2 split panes.') ==
                    true &&
                widget.message?.contains(inactiveSessionIds[0]) == true &&
                widget.message?.contains(inactiveSessionIds[1]) == true &&
                widget.message?.contains(
                      'Click to focus the first pane with new output.',
                    ) ==
                    true,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(tabDot);
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveSessionIds[0],
      );
      expect(tabDot, findsOneWidget);
      expect(
        find.descendant(
          of: tabDot,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.contains('New output in a split pane.') ==
                    true &&
                widget.message?.contains(inactiveSessionIds[0]) == false &&
                widget.message?.contains(inactiveSessionIds[1]) == true &&
                widget.message?.contains('Click to focus this pane.') == true,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(tabDot);
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveSessionIds[1],
      );
      expect(tabDot, findsNothing);
    },
  );

  testWidgets(
    'visible split tab new output prioritizes inactive pane over active marker',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      await pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.horizontal,
      );
      await tester.pumpAndSettle();

      final splitState = container.read(sessionControllerProvider);
      final tab = splitState.tabs.single;
      final originalActiveSessionId = splitState.activeSessionId!;
      final originalInactiveSessionId = tab.effectivePanes
          .firstWhere((pane) => pane.sessionId != originalActiveSessionId)
          .sessionId;

      fakeBindings.setFrame(
        originalInactiveSessionId,
        _terminalFrame('active marker output'),
      );
      await _pumpUntilCondition(
        tester,
        description: 'first split marker output frame',
        condition: () => container
            .read(terminalRuntimeControllerProvider)
            .viewportFor(originalInactiveSessionId)
            .frame
            .rows
            .any((row) => row.text.contains('active marker output')),
      );

      controller.activateSession(originalInactiveSessionId);
      await tester.pumpAndSettle();

      fakeBindings.setFrame(
        originalActiveSessionId,
        _terminalFrame('inactive marker output'),
      );
      await _pumpUntilCondition(
        tester,
        description: 'second split marker output frame',
        condition: () => container
            .read(terminalRuntimeControllerProvider)
            .viewportFor(originalActiveSessionId)
            .frame
            .rows
            .any((row) => row.text.contains('inactive marker output')),
      );

      final tabDot = find.byKey(Key('shell-tab-new-output-${tab.sessionId}'));
      expect(tabDot, findsOneWidget);
      expect(
        find.descendant(
          of: tabDot,
          matching: find.byWidgetPredicate((widget) {
            if (widget is! Tooltip || widget.message == null) {
              return false;
            }
            final message = widget.message!;
            final inactiveIndex = message.indexOf(
              '($originalActiveSessionId) · inactive pane',
            );
            final activeIndex = message.indexOf(
              '($originalInactiveSessionId) · active pane',
            );
            return message.contains('New output in 2 split panes.') &&
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

      await tester.tap(tabDot);
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        originalActiveSessionId,
      );
    },
  );

  testWidgets('overflow menu only dots hidden tabs with new output', (
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

    for (var index = 0; index < 11; index += 1) {
      await openNewShellTab(tester);
    }
    await tester.tap(find.byKey(const Key('shell-tab-1')));
    await tester.pumpAndSettle();

    fakeBindings.setFrame(12, _terminalFrame('hidden tab output'));
    await tester.pump(const Duration(milliseconds: 40));

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('shell-tab-overflow-new-output')),
      findsNothing,
    );
    expect(find.byKey(const Key('shell-tab-new-output-12')), findsOneWidget);
    expect(find.byKey(const Key('shell-tab-new-output-11')), findsNothing);
  });

  testWidgets(
    'shell chrome leaves window drag dispatch to the native macOS event',
    (tester) async {
      const channel = MethodChannel('app/window_bridge');
      final methodCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        methodCalls.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      final dragHandle = find.byKey(const Key('shell-window-drag-leading'));
      expect(dragHandle, findsOneWidget);
      final dragHandleRect = tester.getRect(dragHandle);
      methodCalls.clear();

      final gesture = await tester.startGesture(
        dragHandleRect.centerLeft + const Offset(100, 0),
      );
      await tester.pump();
      expect(methodCalls, isNot(contains('beginWindowDrag')));

      await gesture.moveBy(const Offset(28, 0));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pump();

      expect(methodCalls, isNot(contains('beginWindowDrag')));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell chrome titlebar uses the default cursor without drag tooltip',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      final dragHandle = find.byKey(const Key('shell-window-drag-leading'));
      expect(dragHandle, findsOneWidget);
      expect(find.byTooltip('Drag window'), findsNothing);

      final dragHandleRect = tester.getRect(dragHandle);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 21,
      );
      await gesture.addPointer(location: const Offset(1000, 1000));

      await gesture.moveTo(dragHandleRect.topLeft + const Offset(24, 22));
      await tester.pump();

      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );

      await gesture.moveTo(dragHandleRect.topLeft + const Offset(100, 22));
      await tester.pump();

      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell screen reorders tabs through a direct drag gesture',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      for (var index = 0; index < 2; index += 1) {
        await openNewShellTab(tester);
      }

      final tabOne = find.byKey(const Key('shell-tab-drag-1'));
      final tabTwo = find.byKey(const Key('shell-tab-drag-2'));
      final tabThree = find.byKey(const Key('shell-tab-drag-3'));
      expect(tabOne, findsOneWidget);
      expect(tabTwo, findsOneWidget);
      expect(tabThree, findsOneWidget);
      expect(
        tester.getCenter(tabOne).dx,
        lessThan(tester.getCenter(tabTwo).dx),
      );
      expect(
        tester.getCenter(tabTwo).dx,
        lessThan(tester.getCenter(tabThree).dx),
      );

      final stripRect = tester.getRect(
        find.byKey(const Key('shell-tab-strip')),
      );
      final gesture = await tester.startGesture(tester.getCenter(tabOne));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveBy(Offset(stripRect.width * 1.18, 0));
      await tester.pump(const Duration(milliseconds: 360));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(tabTwo).dx,
        lessThan(tester.getCenter(tabThree).dx),
      );
      expect(
        tester.getCenter(tabThree).dx,
        lessThan(tester.getCenter(tabOne).dx),
      );
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('shell-tab-3')),
        matchesSemantics(
          hasSelectedState: true,
          isButton: true,
          isSelected: true,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'dragging a standalone tab onto a pane creates a split',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      await openNewShellTab(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final initialState = container.read(sessionControllerProvider);
      final sourceSessionId = initialState.tabs.first.sessionId;
      final targetSessionId = initialState.tabs.last.sessionId;
      final sourceTab = find.byKey(Key('shell-tab-drag-$sourceSessionId'));
      final targetPane = find.byKey(Key('shell-pane-$targetSessionId'));
      final targetRect = tester.getRect(targetPane);

      final gesture = await tester.startGesture(tester.getCenter(sourceTab));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveTo(Offset(targetRect.right - 16, targetRect.center.dy));
      await tester.pump(const Duration(milliseconds: 180));

      expect(
        find.byKey(Key('shell-pane-drop-right-$targetSessionId')),
        findsOneWidget,
      );

      await gesture.up();
      expect(container.read(sessionControllerProvider).tabs, hasLength(2));
      await tester.pumpAndSettle();

      final splitState = container.read(sessionControllerProvider);
      expect(splitState.tabs, hasLength(1));
      expect(splitState.tabs.single.effectivePanes, hasLength(2));
      expect(splitState.activeSessionId, sourceSessionId);
      expect(
        splitState.tabs.single.effectivePanes.map((pane) => pane.sessionId),
        [targetSessionId, sourceSessionId],
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'dragging the active tab previews a sibling target without rebuilding tabs',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      await openNewShellTab(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final initialState = container.read(sessionControllerProvider);
      final targetSessionId = initialState.tabs.first.sessionId;
      final sourceSessionId = initialState.tabs.last.sessionId;
      expect(initialState.activeSessionId, sourceSessionId);

      final sourceTab = find.byKey(Key('shell-tab-drag-$sourceSessionId'));
      final tabStripRect = tester.getRect(
        find.byKey(const Key('shell-tab-strip')),
      );
      final gesture = await tester.startGesture(tester.getCenter(sourceTab));
      await gesture.moveTo(
        Offset(tester.getCenter(sourceTab).dx, tabStripRect.bottom + 80),
      );
      await tester.pump(const Duration(milliseconds: 360));

      final floatingTab = find.byKey(
        Key('shell-external-tab-drag-feedback-$sourceSessionId'),
      );
      expect(floatingTab, findsOneWidget);
      expect(
        tester.getCenter(floatingTab).dy,
        greaterThan(tabStripRect.bottom),
      );
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        sourceSessionId,
      );

      final previewPane = find.byKey(Key('shell-pane-$sourceSessionId'));
      expect(previewPane, findsOneWidget);
      final targetRect = tester.getRect(previewPane);
      await gesture.moveTo(Offset(targetRect.left + 16, targetRect.center.dy));
      await tester.pump(const Duration(milliseconds: 180));

      expect(
        find.byKey(Key('shell-pane-drop-left-$targetSessionId')),
        findsOneWidget,
      );

      await gesture.up();
      expect(container.read(sessionControllerProvider).tabs, hasLength(2));
      await tester.pumpAndSettle();

      final splitState = container.read(sessionControllerProvider);
      expect(splitState.tabs, hasLength(1));
      expect(splitState.tabs.single.effectivePanes, hasLength(2));
      expect(splitState.activeSessionId, sourceSessionId);
      expect(
        splitState.tabs.single.effectivePanes.map((pane) => pane.sessionId),
        [sourceSessionId, targetSessionId],
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a quick active tab pane drop disposes its feedback safely',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      await openNewShellTab(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final sourceSessionId = container
          .read(sessionControllerProvider)
          .tabs
          .last
          .sessionId;
      final sourceTab = find.byKey(Key('shell-tab-drag-$sourceSessionId'));
      final sourcePaneRect = tester.getRect(
        find.byKey(Key('shell-pane-$sourceSessionId')),
      );

      final gesture = await tester.startGesture(tester.getCenter(sourceTab));
      await gesture.moveTo(
        Offset(sourcePaneRect.left + 16, sourcePaneRect.center.dy),
      );
      await gesture.up();
      await tester.pumpAndSettle();

      final state = container.read(sessionControllerProvider);
      expect(state.tabs, hasLength(1));
      expect(state.tabs.single.effectivePanes, hasLength(2));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'cancelling an active tab pane drag keeps the source tab active',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      await openNewShellTab(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final initialState = container.read(sessionControllerProvider);
      final sourceSessionId = initialState.tabs.last.sessionId;
      final sourceTab = find.byKey(Key('shell-tab-drag-$sourceSessionId'));
      final tabStripRect = tester.getRect(
        find.byKey(const Key('shell-tab-strip')),
      );

      final gesture = await tester.startGesture(tester.getCenter(sourceTab));
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        sourceSessionId,
      );

      await gesture.moveTo(
        Offset(tester.getCenter(sourceTab).dx, tabStripRect.bottom + 80),
      );
      await tester.pump(const Duration(milliseconds: 360));
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        sourceSessionId,
      );

      await gesture.cancel();
      await tester.pumpAndSettle();

      final restoredState = container.read(sessionControllerProvider);
      expect(restoredState.tabs, hasLength(2));
      expect(restoredState.activeSessionId, sourceSessionId);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'dragging a split pane header to the tab strip restores a tab',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.horizontal,
      );
      await tester.pumpAndSettle();

      final splitState = container.read(sessionControllerProvider);
      final detachedSessionId = splitState.tabs.single.sessionId;
      final retainedSessionId = splitState.tabs.single.effectivePanes
          .firstWhere((pane) => pane.sessionId != detachedSessionId)
          .sessionId;
      final paneDrag = find.byKey(Key('shell-pane-drag-$detachedSessionId'));
      final tabStripRect = tester.getRect(
        find.byKey(const Key('shell-tab-strip')),
      );

      final gesture = await tester.startGesture(tester.getCenter(paneDrag));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.moveTo(tabStripRect.centerRight - const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 160));

      expect(
        find.byKey(const Key('shell-tab-drop-insertion-1')),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pumpAndSettle();

      final detachedState = container.read(sessionControllerProvider);
      expect(detachedState.tabs, hasLength(2));
      expect(
        detachedState.tabs.first.effectivePanes.single.sessionId,
        retainedSessionId,
      );
      expect(
        detachedState.tabs.last.effectivePanes.single.sessionId,
        detachedSessionId,
      );
      expect(detachedState.activeSessionId, detachedSessionId);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'dragging a split pane header onto another pane repositions it',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.horizontal,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('shell-pane-divider-line-horizontal')),
        findsOneWidget,
      );

      final splitState = container.read(sessionControllerProvider);
      final movingSessionId = splitState.activeSessionId!;
      final targetSessionId = splitState.tabs.single.effectivePanes
          .firstWhere((pane) => pane.sessionId != movingSessionId)
          .sessionId;
      final paneDrag = find.byKey(Key('shell-pane-drag-$movingSessionId'));
      final targetRect = tester.getRect(
        find.byKey(Key('shell-pane-$targetSessionId')),
      );

      final gesture = await tester.startGesture(tester.getCenter(paneDrag));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.moveTo(
        Offset(targetRect.center.dx, targetRect.bottom - 16),
      );
      await tester.pump(const Duration(milliseconds: 160));

      expect(
        find.byKey(Key('shell-pane-drop-bottom-$targetSessionId')),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pump();
      expect(
        find.byKey(const Key('shell-pane-divider-line-vertical')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 45));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      final movedLayout = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .effectivePaneLayout;
      expect(movedLayout.splitAxis, TerminalSplitAxis.vertical);
      expect(movedLayout.first!.pane!.sessionId, targetSessionId);
      expect(movedLayout.second!.pane!.sessionId, movingSessionId);
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        movingSessionId,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell tab full-width body is draggable while hover close stays left',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      for (var index = 0; index < 2; index += 1) {
        await openNewShellTab(tester);
      }

      final tabOne = find.byKey(const Key('shell-tab-1'));
      final tabTwo = find.byKey(const Key('shell-tab-2'));
      final tabThree = find.byKey(const Key('shell-tab-3'));
      final tabOneTitle = find.byKey(const Key('shell-tab-title-1'));
      final tabOneClose = find.byKey(const Key('shell-tab-close-1'));

      expect(tabOneTitle, findsOneWidget);
      expect(tabOneClose, findsOneWidget);

      final tabOneRect = tester.getRect(tabOne);
      final stripRect = tester.getRect(
        find.byKey(const Key('shell-tab-strip')),
      );
      final titleRect = tester.getRect(tabOneTitle);
      await _hoverShellTab(tester, '1');
      final closeRect = tester.getRect(tabOneClose);
      expect(titleRect.center.dx, closeTo(tabOneRect.center.dx, 1));
      expect(closeRect.left, greaterThan(tabOneRect.left + 4));
      expect(closeRect.right, lessThan(tabOneRect.left + 32));

      final tabOneBodyDragStart = Offset(
        tabOneRect.left + tabOneRect.width * 0.18,
        tabOneRect.center.dy,
      );
      final gesture = await tester.startGesture(tabOneBodyDragStart);
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveBy(Offset(stripRect.width * 1.18, 0));
      await tester.pump(const Duration(milliseconds: 360));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(tabTwo).dx,
        lessThan(tester.getCenter(tabThree).dx),
      );
      expect(
        tester.getCenter(tabThree).dx,
        lessThan(tester.getCenter(tabOne).dx),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('shell screen uses the same dark empty-state language everywhere', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _hoverShellTab(tester, '1');
    await tester.tap(find.byTooltip('Close Local Shell'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.text('Shell layout is idle'), findsOneWidget);
    expect(
      find.text(
        'The last session has closed. Open a new tab to keep working in the shell layout.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reference demo mode keeps the middle Shell tab selected', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      referenceDemoMode: true,
    );

    final tabStrip = find.byKey(const Key('shell-tab-strip'));
    expect(
      find.descendant(of: tabStrip, matching: find.text('⌘1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tabStrip, matching: find.text('⌘2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tabStrip, matching: find.text('⌘3')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('shell-tab-demo-2')),
      matchesSemantics(
        label: 'Shell tab, Command 2',
        hasSelectedState: true,
        isButton: true,
        isSelected: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('shell-tab-demo-1')),
      matchesSemantics(hasSelectedState: true, isButton: true),
    );
  });

  testWidgets(
    'reference demo mode supports command-number tab selection',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        referenceDemoMode: true,
      );

      await sendMetaShortcut(tester, LogicalKeyboardKey.digit1);

      expect(
        tester.getSemantics(find.bySemanticsIdentifier('shell-tab-demo-1')),
        matchesSemantics(
          hasSelectedState: true,
          isButton: true,
          isSelected: true,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

Future<void> _hoverShellTab(WidgetTester tester, String sessionId) async {
  final pointer = TestPointer(98, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.hover(tester.getCenter(find.byKey(Key('shell-tab-$sessionId')))),
  );
  await tester.pump();
}

Color _tabButtonBackground(
  WidgetTester tester,
  Key key,
  Set<WidgetState> states,
) {
  final button = tester.widget<TextButton>(find.byKey(key));
  return button.style!.backgroundColor!.resolve(states)!;
}

Color? _tabButtonOverlay(
  WidgetTester tester,
  Key key,
  Set<WidgetState> states,
) {
  final button = tester.widget<TextButton>(find.byKey(key));
  return button.style!.overlayColor!.resolve(states);
}

Color? _iconButtonBackground(
  WidgetTester tester,
  Key key,
  Set<WidgetState> states,
) {
  final button = tester.widget<IconButton>(find.byKey(key));
  return button.style!.backgroundColor!.resolve(states);
}

Color? _iconButtonOverlay(
  WidgetTester tester,
  Key key,
  Set<WidgetState> states,
) {
  final button = tester.widget<IconButton>(find.byKey(key));
  return button.style!.overlayColor!.resolve(states);
}

Color? _decoratedBoxColor(WidgetTester tester, Key key) {
  final decoratedBox = tester.widget<DecoratedBox>(find.byKey(key));
  return (decoratedBox.decoration as BoxDecoration).color;
}

Border? _decoratedBoxBorder(WidgetTester tester, Key key) {
  final decoratedBox = tester.widget<DecoratedBox>(find.byKey(key));
  return (decoratedBox.decoration as BoxDecoration).border as Border?;
}

int _channelSpread(Color color) {
  final argb = color.toARGB32();
  final red = (argb >> 16) & 0xff;
  final green = (argb >> 8) & 0xff;
  final blue = argb & 0xff;
  return [
    (red - green).abs(),
    (red - blue).abs(),
    (green - blue).abs(),
  ].reduce(math.max);
}

TerminalProfile _profileWithTerminalBackground(String background) {
  final base = defaultTerminalProfile();
  return base.copyWith(
    appearance: TerminalProfileAppearance(
      colors: TerminalProfileColors(
        special: TerminalSpecialColors(background: background),
      ),
    ),
  );
}

Map<String, Object?> _terminalFrame(String text) {
  return {
    'rows': [
      {'index': 0, 'text': text, 'style_runs': const <Object?>[]},
    ],
    'cursor': {'row': 0, 'col': text.length, 'visible': true},
    'selection': null,
    'viewport_rows': 24,
    'viewport_cols': 80,
    'dirty_ranges': [
      {'start': 0, 'end': 1},
    ],
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
  };
}
