import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/instant_replay_store.dart';
import 'package:app/features/shell/paste_history_repository.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ui/app_ui.dart';
import 'support/fake_pty_backend.dart';
import 'support/memory_app_preferences_repository.dart';
import 'support/memory_local_terminal_config_repository.dart';
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

class _DelayedNewTabPtyBackend extends FakePtyBackend {
  bool releaseNewTabFrame = false;
  bool emitPlaceholderFrame = false;
  final Set<String> _placeholderFramesEmitted = <String>{};

  @override
  String? takeFrameDiffJson(String sessionId) {
    if (sessionId == '2' &&
        emitPlaceholderFrame &&
        _placeholderFramesEmitted.add(sessionId)) {
      return jsonEncode(<String, Object?>{
        'rows': <Object?>[],
        'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 24},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'window_title': null,
        'window_icon_name': null,
      });
    }
    if (sessionId == '2' && !releaseNewTabFrame) {
      return null;
    }
    return super.takeFrameDiffJson(sessionId);
  }
}

class _DelayedProfileRepository extends MemoryProfileRepository {
  _DelayedProfileRepository(super.document, this.ready);

  final Future<void> ready;

  @override
  Future<TerminalProfilesDocument> load() async {
    await ready;
    return super.load();
  }
}

class _FailingOnceProfileRepository extends MemoryProfileRepository {
  _FailingOnceProfileRepository(super.document);

  int loadAttempts = 0;

  @override
  Future<TerminalProfilesDocument> load() async {
    loadAttempts += 1;
    if (loadAttempts == 1) {
      throw const FileSystemException('profiles unavailable');
    }
    return super.load();
  }
}

Future<void> _pumpShellScreen(
  WidgetTester tester, {
  required PtySessionBackend bindings,
  required MemoryProfileRepository repository,
  PasteHistoryRepository? pasteHistoryRepository,
  InstantReplayStore? instantReplayStore,
  ShellNotificationSender? notificationSender,
  bool showHiddenRedesignEntryPointsForTesting = false,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(repository),
        pasteHistoryRepositoryProvider.overrideWithValue(
          pasteHistoryRepository ?? MemoryPasteHistoryRepository(),
        ),
        if (instantReplayStore != null)
          instantReplayStoreProvider.overrideWithValue(instantReplayStore),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(null),
        ),
        if (notificationSender != null)
          shellNotificationSenderProvider.overrideWithValue(notificationSender),
        if (showHiddenRedesignEntryPointsForTesting)
          shellHiddenRedesignEntryPointsProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.light),
        darkTheme: buildIanvsTerminalTheme(Brightness.dark),
        home: const ShellScreen(),
      ),
    ),
  );
  if (settle) {
    await tester.pump();
    await tester.pumpAndSettle();
  }
}

Future<void> _openCommandMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await tester.pumpAndSettle();
}

Future<void> _openToolbelt(WidgetTester tester) async {
  await _openCommandMenu(tester);
  await tester.tap(find.byKey(const Key('shell-top-toolbelt')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('shell-toolbelt-panel')), findsOneWidget);
}

Future<void> _tapToolbeltAction(WidgetTester tester, Key actionKey) async {
  await _openToolbelt(tester);
  final action = find.byKey(actionKey);
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _openToolbeltSource(
  WidgetTester tester, {
  required Key tabKey,
  required Key actionKey,
}) async {
  await _openToolbelt(tester);
  await tester.tap(find.byKey(tabKey));
  await tester.pumpAndSettle();
  final action = find.byKey(actionKey);
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _hoverShellTab(WidgetTester tester, String sessionId) async {
  final pointer = TestPointer(99, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.hover(tester.getCenter(find.byKey(Key('shell-tab-$sessionId')))),
  );
  await tester.pump();
}

Color _decoratedBoxColor(WidgetTester tester, Key key) {
  final decoration = tester.widget<DecoratedBox>(find.byKey(key)).decoration;
  return (decoration as BoxDecoration).color!;
}

Future<void> _openShellSearch(WidgetTester tester) async {
  await tester.tap(find.byType(TerminalViewport).last);
  await tester.pump();
  await _sendMetaShortcut(tester, LogicalKeyboardKey.keyF);
}

Map<String, Object?> _terminalFrameWithTitle(String title) {
  return <String, Object?>{
    'rows': <Object?>[
      <String, Object?>{
        'index': 0,
        'text': title,
        'style_runs': const <Object?>[],
      },
    ],
    'cursor': <String, Object?>{'row': 0, 'col': title.length, 'visible': true},
    'selection': null,
    'viewport_rows': 24,
    'viewport_cols': 80,
    'dirty_ranges': <Object?>[
      <String, Object?>{'start': 0, 'end': 1},
    ],
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
    'window_title': title,
    'window_icon_name': null,
  };
}

Future<void> _invokeNativeWindowBridge(
  WidgetTester tester,
  MethodCall call,
) async {
  await _dispatchNativeWindowBridge(tester, call);
  await tester.pumpAndSettle();
}

Future<void> _dispatchNativeWindowBridge(WidgetTester tester, MethodCall call) {
  final codec = const StandardMethodCodec();
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'app/window_bridge',
    codec.encodeMethodCall(call),
    (_) {},
  );
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

Future<void> _openTabCountWithShortcut(
  WidgetTester tester,
  int tabCount,
) async {
  assert(tabCount >= 1);
  for (var index = 1; index < tabCount; index += 1) {
    await _sendMetaShortcut(tester, LogicalKeyboardKey.keyT);
  }
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

Future<void> _sendMetaAltShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft, platform: 'macos');
  await tester.sendKeyDownEvent(key, platform: 'macos');
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(key, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'macos');
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

Future<void> _selectSearchMode(WidgetTester tester, String modeWireName) async {
  await tester.tap(find.byKey(const Key('terminal-search-mode')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('terminal-search-mode-$modeWireName')));
  await tester.pumpAndSettle();
}

Future<void> _selectSearchScope(
  WidgetTester tester,
  String scopeWireName,
) async {
  await tester.tap(find.byKey(const Key('terminal-search-scope')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('terminal-search-scope-$scopeWireName')));
  await tester.pumpAndSettle();
}

RenderTerminalViewport _terminalRenderObject(WidgetTester tester) {
  return tester.allRenderObjects.whereType<RenderTerminalViewport>().last;
}

RenderTerminalViewport _terminalRenderObjectForPane(
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

void _expectRectClose(Rect actual, Rect expected) {
  expect(actual.left, moreOrLessEquals(expected.left, epsilon: 0.001));
  expect(actual.top, moreOrLessEquals(expected.top, epsilon: 0.001));
  expect(actual.width, moreOrLessEquals(expected.width, epsilon: 0.001));
  expect(actual.height, moreOrLessEquals(expected.height, epsilon: 0.001));
}

void _expectSelectedTab(WidgetTester tester, String sessionId) {
  expect(
    tester.getSemantics(find.bySemanticsIdentifier('shell-tab-$sessionId')),
    matchesSemantics(hasSelectedState: true, isSelected: true, isButton: true),
  );
}

void main() {
  testWidgets('shell startup waits silently for bootstrap content', (
    tester,
  ) async {
    final ready = Completer<void>();

    await _pumpShellScreen(
      tester,
      bindings: FakePtyBackend(),
      repository: _DelayedProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ready.future,
      ),
      settle: false,
    );

    expect(find.byKey(const Key('shell-empty-state')), findsNothing);
    expect(find.byType(TerminalViewport), findsNothing);

    ready.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-empty-state')), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);
  });

  testWidgets('shell startup failure presents a retry action', (tester) async {
    final repository = _FailingOnceProfileRepository(
      TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    );

    await _pumpShellScreen(
      tester,
      bindings: FakePtyBackend(),
      repository: repository,
      settle: false,
    );
    await _pumpUntilCondition(
      tester,
      condition: () =>
          find.byKey(const Key('shell-startup-error')).evaluate().isNotEmpty,
      description: 'startup error surface',
    );

    expect(find.text('Terminal could not start'), findsOneWidget);
    expect(find.byKey(const Key('shell-startup-retry')), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);

    await tester.tap(find.byKey(const Key('shell-startup-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-startup-error')), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(repository.loadAttempts, 2);
  });

  testWidgets('shell screen keeps line timestamp overlays hidden by default', (
    tester,
  ) async {
    await _pumpShellScreen(
      tester,
      bindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('terminal-line-timestamp-0')), findsNothing);
  });

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

    expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('shell-chrome-menu'))),
      const Size(26, 20),
    );
    expect(
      tester.getSize(find.byKey(const Key('shell-chrome-new-tab'))),
      const Size(26, 20),
    );
    await _openCommandMenu(tester);
    await tester.tap(find.text('New tab'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    _expectSelectedTab(tester, '2');
  });

  testWidgets(
    'tab strip uses compact tabs before overflowing',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1100, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpShellScreen(
        tester,
        bindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabCountWithShortcut(tester, 8);

      for (var sessionId = 1; sessionId <= 8; sessionId += 1) {
        expect(
          find.bySemanticsIdentifier('shell-tab-$sessionId'),
          findsOneWidget,
        );
      }
      expect(find.byKey(const Key('shell-tab-overflow-button')), findsNothing);

      final compactTabWidth = tester
          .getSize(find.byKey(const Key('shell-tab-8')))
          .width;
      expect(compactTabWidth, greaterThanOrEqualTo(104));
      expect(compactTabWidth, lessThan(140));
      expect(find.text('⌘8'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'profile tab color renders in the active tab and overflow selector',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(560, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const tabColor = Color(0xFF336699);
      final baseProfile = defaultTerminalProfile();
      final profile = baseProfile.copyWith(
        name: 'Prod Shell',
        appearance: baseProfile.appearance.copyWith(
          colors: baseProfile.appearance.colors.copyWith(
            special: baseProfile.appearance.colors.special.copyWith(
              background: '#11141A',
              tab: '#336699',
            ),
          ),
        ),
      );

      await _pumpShellScreen(
        tester,
        bindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [profile]),
        ),
      );

      expect(find.byKey(const Key('shell-tab-color-1')), findsOneWidget);
      expect(
        _decoratedBoxColor(tester, const Key('shell-tab-color-1')),
        tabColor,
      );

      await _openTabCountWithShortcut(tester, 8);
      expect(
        find.byKey(const Key('shell-tab-overflow-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('shell-tab-overflow-color-8')),
        findsOneWidget,
      );
      expect(
        _decoratedBoxColor(tester, const Key('shell-tab-overflow-color-8')),
        tabColor,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'OSC 6 tab color components render incrementally and restore the profile color',
    (tester) async {
      const profileColor = Color(0xFF102030);
      const redStage = Color(0xFFFF2030);
      const greenStage = Color(0xFFFF8030);
      const blueStage = Color(0xFFFF8040);
      final baseProfile = defaultTerminalProfile();
      final profile = baseProfile.copyWith(
        appearance: baseProfile.appearance.copyWith(
          colors: baseProfile.appearance.colors.copyWith(
            special: baseProfile.appearance.colors.special.copyWith(
              tab: '#102030',
            ),
          ),
        ),
      );
      final fakeBindings = FakePtyBackend();
      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [profile]),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );

      fakeBindings.setFrame(1, <String, Object?>{
        ..._terminalFrameWithTitle('OSC 6 Red'),
        'window_title': null,
        'tab_color': '#ff2030',
      });
      container.read(terminalRuntimeControllerProvider).refreshSession('1');
      await tester.pump();
      expect(
        _decoratedBoxColor(tester, const Key('shell-tab-color-1')),
        redStage,
      );

      fakeBindings.setFrame(1, <String, Object?>{
        ..._terminalFrameWithTitle('OSC 6 Green'),
        'window_title': null,
        'tab_color': '#ff8030',
      });
      container.read(terminalRuntimeControllerProvider).refreshSession('1');
      await tester.pump();
      expect(
        _decoratedBoxColor(tester, const Key('shell-tab-color-1')),
        greenStage,
      );

      fakeBindings.setFrame(1, <String, Object?>{
        ..._terminalFrameWithTitle('OSC 6 Blue'),
        'window_title': null,
        'tab_color': '#ff8040',
      });
      container.read(terminalRuntimeControllerProvider).refreshSession('1');
      await tester.pump();
      expect(
        _decoratedBoxColor(tester, const Key('shell-tab-color-1')),
        blueStage,
      );

      fakeBindings.setFrame(1, <String, Object?>{
        ..._terminalFrameWithTitle('Restored Tab'),
        'window_title': null,
      });
      container.read(terminalRuntimeControllerProvider).refreshSession('1');
      await tester.pump();
      expect(
        _decoratedBoxColor(tester, const Key('shell-tab-color-1')),
        profileColor,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tab overflow menu activates hidden tabs',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(560, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpShellScreen(
        tester,
        bindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabCountWithShortcut(tester, 8);

      expect(
        find.byKey(const Key('shell-tab-overflow-button')),
        findsOneWidget,
      );
      expect(find.bySemanticsIdentifier('shell-tab-8'), findsNothing);

      await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-tab-overflow-panel')), findsOneWidget);
      expect(
        find.byKey(const Key('shell-tab-overflow-item-8')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-tab-overflow-item-8')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-pane-8')), findsOneWidget);
      expect(find.byKey(const Key('shell-tab-overflow-panel')), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tab overflow badge can focus an inactive split pane',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeBindings = FakePtyBackend();
      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabCountWithShortcut(tester, 8);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final sessionController = container.read(
        sessionControllerProvider.notifier,
      );
      sessionController.activateSession('8');
      sessionController.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.horizontal,
      );
      await tester.pumpAndSettle();

      final splitState = container.read(sessionControllerProvider);
      final hiddenTab = splitState.tabs.singleWhere(
        (tab) => tab.sessionId == '8',
      );
      final activeSessionId = splitState.activeSessionId!;
      final inactiveSessionId = hiddenTab.effectivePanes
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
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump();

      tester.view.physicalSize = const Size(560, 700);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('shell-tab-overflow-button')),
        findsOneWidget,
      );
      expect(find.bySemanticsIdentifier('shell-tab-8'), findsNothing);

      await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
      await tester.pumpAndSettle();

      final overflowBadge = find.byKey(const Key('shell-tab-overflow-badge-8'));
      expect(overflowBadge, findsOneWidget);
      expect(
        find.descendant(of: overflowBadge, matching: find.text('DEPLOY')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: overflowBadge,
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

      await tester.tap(overflowBadge);
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveSessionId,
      );
      expect(find.byKey(const Key('shell-tab-overflow-panel')), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('new tab keeps current terminal visible until its first frame', (
    tester,
  ) async {
    final fakeBindings = _DelayedNewTabPtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);

    await _openCommandMenu(tester);
    await tester.tap(find.text('New tab'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    _expectSelectedTab(tester, '2');
    expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-2')), findsNothing);

    fakeBindings.releaseNewTabFrame = true;
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-2')), findsOneWidget);
  });

  testWidgets('new tab ignores placeholder frames before terminal content', (
    tester,
  ) async {
    final fakeBindings = _DelayedNewTabPtyBackend()
      ..emitPlaceholderFrame = true;

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

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    _expectSelectedTab(tester, '2');
    expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-2')), findsNothing);

    fakeBindings.releaseNewTabFrame = true;
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-2')), findsOneWidget);
  });

  testWidgets(
    'tab context menu split right opens a second pane in the active tab',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell-tab-2'), findsNothing);
      expect(find.byType(TerminalViewport), findsOneWidget);

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell-tab-2'), findsNothing);
      expect(find.byType(TerminalViewport), findsNWidgets(2));
      expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);
      expect(find.byKey(const Key('shell-pane-2')), findsOneWidget);
      expect(find.byKey(const Key('shell-pane-dim-1')), findsOneWidget);
      expect(find.byKey(const Key('shell-pane-dim-2')), findsNothing);
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets('tab context menu allows splitting down after splitting right', (
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

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(find.byType(TerminalViewport), findsNWidgets(2));

    await _openTabContextMenu(tester);
    expect(find.text('Split down'), findsOneWidget);
    expect(
      find.textContaining('Mixed pane layouts are not supported yet.'),
      findsNothing,
    );

    await tester.tap(find.text('Split down'));
    await tester.pumpAndSettle();

    expect(find.byType(TerminalViewport), findsNWidgets(3));
    expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-2')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-3')), findsOneWidget);
  });

  testWidgets(
    'tab context menu explains unavailable split and layout actions',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabContextMenu(tester);
      expect(find.text('Reopen closed pane'), findsOneWidget);
      expect(
        find.textContaining(
          'No recently closed pane is available for this tab.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Unavailable: Add another pane to use this action.'),
        findsNWidgets(2),
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();

      await _openTabContextMenu(tester);
      expect(
        find.textContaining('Mixed pane layouts are not supported yet.'),
        findsNothing,
      );
      expect(find.text('Split down'), findsOneWidget);
      expect(
        find.text(
          'Unavailable: Another pane would become narrower than 24 columns.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Unavailable: This tab already has multiple panes.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tab context menu stops growing a pane before a sibling becomes too small',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      var foundLimitReason = false;
      for (var attempt = 0; attempt < 10; attempt++) {
        await _openTabContextMenu(tester);
        final limitReason = find.textContaining(
          'Unavailable: Another pane would become narrower than 24 columns.',
        );
        if (limitReason.evaluate().isNotEmpty) {
          foundLimitReason = true;
          break;
        }
        await tester.tap(find.text('Grow active pane'));
        await tester.pumpAndSettle();
      }

      expect(foundLimitReason, isTrue);
    },
  );

  testWidgets(
    'tab context menu disables pane management actions while zoomed',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shell-pane-action-zoom-2')));
      await tester.pumpAndSettle();

      await _openTabContextMenu(tester);
      expect(
        find.text('Unavailable: Unzoom the active pane to manage other panes.'),
        findsNWidgets(4),
      );
      expect(find.text('Zoom active pane'), findsNothing);
      expect(find.text('Unzoom active pane'), findsNothing);
    },
  );

  testWidgets('hovering a split pane does not activate it, but clicking does', (
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

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-dim-1')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-dim-2')), findsNothing);

    final pointer = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byKey(const Key('shell-pane-1')))),
    );
    await tester.pump();

    expect(find.byKey(const Key('shell-pane-dim-1')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-dim-2')), findsNothing);

    await tester.tap(find.byKey(const Key('shell-pane-1')));
    await tester.pump();

    expect(find.byKey(const Key('shell-pane-dim-1')), findsNothing);
    expect(find.byKey(const Key('shell-pane-dim-2')), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'clicking an inactive split pane with mouse reporting activates and reports to that pane',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      fakeBindings.setFrame(1, <String, Object?>{
        ..._terminalFrameWithTitle('Mouse Pane'),
        'modes': <String, Object?>{
          'mouse_mode': 'normal',
          'mouse_encoding': 'sgr',
        },
      });
      container.read(terminalRuntimeControllerProvider).refreshSession('1');
      await tester.pump();

      fakeBindings.writes.clear();
      fakeBindings.writesBySession.clear();

      final inactiveViewport = find.descendant(
        of: find.byKey(const Key('shell-pane-1')),
        matching: find.byType(TerminalViewport),
      );
      await tester.tap(inactiveViewport);
      await tester.pump();

      expect(container.read(sessionControllerProvider).activeSessionId, '1');
      expect(fakeBindings.writesBySession.map((entry) => entry.key).toList(), [
        '1',
        '1',
      ]);
      expect(
        ascii.decode(fakeBindings.writesBySession.first.value),
        startsWith('\x1B[<0;'),
      );
      expect(
        ascii.decode(fakeBindings.writesBySession.last.value),
        endsWith('m'),
      );
    },
  );

  testWidgets(
    'switching split panes routes focus reports to the pane gaining or losing focus',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      for (final sessionId in const ['1', '2']) {
        fakeBindings.setFrame(sessionId, <String, Object?>{
          ..._terminalFrameWithTitle('Focus Pane $sessionId'),
          'modes': const <String, Object?>{'focus_tracking': true},
        });
        container
            .read(terminalRuntimeControllerProvider)
            .refreshSession(sessionId);
      }
      await tester.pump();

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('shell-pane-2')),
          matching: find.byType(TerminalViewport),
        ),
      );
      await tester.pump();
      fakeBindings.writes.clear();
      fakeBindings.writesBySession.clear();

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('shell-pane-1')),
          matching: find.byType(TerminalViewport),
        ),
      );
      await tester.pump();

      expect(container.read(sessionControllerProvider).activeSessionId, '1');
      expect(
        fakeBindings.writesBySession
            .map((entry) => '${entry.key}:${ascii.decode(entry.value)}')
            .toList(),
        ['2:\x1B[O', '1:\x1B[I'],
      );
    },
  );

  testWidgets(
    'terminal focus updates refresh policy without backgrounding it',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('shell-pane-1')),
          matching: find.byType(TerminalViewport),
        ),
      );
      await tester.pump();

      expect(
        runtime.refreshPolicySnapshotFor('1').refreshClass,
        TerminalRefreshClass.interactive,
      );

      await _openCommandMenu(tester);
      await _pumpUntilCondition(
        tester,
        description: 'focus-loss interactive grace expiry',
        maxTicks: 25,
        condition: () =>
            runtime.refreshPolicySnapshotFor('1').refreshClass !=
            TerminalRefreshClass.interactive,
      );

      expect(
        runtime.refreshPolicySnapshotFor('1').refreshClass,
        isNot(TerminalRefreshClass.background),
        reason: 'focus loss must not background the still-active session',
      );
    },
  );

  testWidgets('disabling focus tracking stops split pane focus reports', (
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

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    for (final sessionId in const ['1', '2']) {
      fakeBindings.setFrame(sessionId, <String, Object?>{
        ..._terminalFrameWithTitle('Focus Pane $sessionId'),
        'modes': const <String, Object?>{'focus_tracking': true},
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
    }
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('shell-pane-2')),
        matching: find.byType(TerminalViewport),
      ),
    );
    await tester.pump();

    for (final sessionId in const ['1', '2']) {
      fakeBindings.setFrame(sessionId, <String, Object?>{
        ..._terminalFrameWithTitle('Focus Pane $sessionId'),
        'modes': const <String, Object?>{'focus_tracking': false},
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
    }
    await tester.pump();
    fakeBindings.writes.clear();
    fakeBindings.writesBySession.clear();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('shell-pane-1')),
        matching: find.byType(TerminalViewport),
      ),
    );
    await tester.pump();

    expect(container.read(sessionControllerProvider).activeSessionId, '1');
    expect(fakeBindings.writesBySession, isEmpty);
  });

  testWidgets('active split pane header exposes split affordances', (
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

    expect(find.byKey(const Key('shell-pane-header-1')), findsNothing);
    expect(
      find.byKey(const Key('shell-pane-action-split-right-1')),
      findsNothing,
    );

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-header-2')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-header-1')), findsOneWidget);
    expect(find.text('Pane 2/2'), findsOneWidget);
    expect(
      find.byKey(const Key('shell-pane-action-split-right-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shell-pane-action-split-down-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shell-pane-action-split-right-1')),
      findsNothing,
    );

    final secondPaneTop = tester
        .getTopLeft(find.byKey(const Key('shell-pane-2')))
        .dy;
    final secondHeaderTop = tester
        .getTopLeft(find.byKey(const Key('shell-pane-header-2')))
        .dy;
    expect(secondHeaderTop, closeTo(secondPaneTop, 0.5));

    await tester.tap(find.byKey(const Key('shell-pane-action-split-down-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-2')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-3')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-header-3')), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'tab title follows active pane title when tab has multiple panes',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      fakeBindings.setFrame(1, _terminalFrameWithTitle('Left Pane Title'));
      fakeBindings.setFrame(2, _terminalFrameWithTitle('Right Pane Title'));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-title-1')),
          matching: find.text('Right Pane Title'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('shell-chrome-window-title')))
            .data,
        'Ianvs Terminal',
      );

      await tester.tap(find.byKey(const Key('shell-pane-1')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('shell-tab-title-1')),
          matching: find.text('Left Pane Title'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('shell-chrome-window-title')))
            .data,
        'Ianvs Terminal',
      );
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets(
    'collapsed split tab keeps remaining pane title and badge after closing root pane',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      Map<String, Object?> frameWithTitle(String output, String title) {
        return <String, Object?>{
          'rows': <Object?>[
            <String, Object?>{
              'index': 0,
              'text': output,
              'style_runs': const <Object?>[],
            },
          ],
          'cursor': <String, Object?>{
            'row': 0,
            'col': output.length,
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
          'window_title': title,
          'window_icon_name': null,
        };
      }

      fakeBindings.setFrame(
        1,
        frameWithTitle('left output', 'Left Pane Title'),
      );
      fakeBindings.setFrame(
        2,
        frameWithTitle('right output', 'Right Pane Title'),
      );
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      fakeBindings.enqueueEvent(
        2,
        const PtyEvent(
          kind: 'session_badge',
          sessionId: '2',
          payload: <String, Object?>{'text': 'Deploy'},
        ),
      );
      container.read(terminalRuntimeControllerProvider).refreshSession('2');
      await tester.pump();

      await tester.tap(find.byKey(const Key('shell-pane-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shell-pane-action-close-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-pane-1')), findsNothing);
      expect(find.byKey(const Key('shell-pane-2')), findsOneWidget);
      expect(find.byKey(const Key('shell-pane-header-2')), findsNothing);
      expect(find.text('Left Pane Title'), findsNothing);
      expect(find.text('Right Pane Title'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('shell-chrome-window-title')))
            .data,
        'Ianvs Terminal',
      );
      expect(find.byKey(const Key('shell-status-badge')), findsNothing);
      expect(find.text('DEPLOY'), findsOneWidget);
      expect(container.read(sessionControllerProvider).activeSessionId, '2');

      await _hoverShellTab(tester, '1');
      await tester.tap(find.byKey(const Key('shell-tab-close-1')));
      await tester.pumpAndSettle();

      expect(container.read(sessionControllerProvider).tabs, isEmpty);
      expect(find.byKey(const Key('shell-pane-2')), findsNothing);
      expect(find.byKey(const Key('shell-status-badge')), findsNothing);
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets('active split pane header zooms and closes the pane', (
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

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-header-2')), findsOneWidget);

    await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyC);

    expect(find.text('Copy mode'), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-header-2')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape, platform: 'macos');
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape, platform: 'macos');
    await tester.pump();

    expect(find.text('Copy mode'), findsNothing);
    expect(find.byKey(const Key('shell-pane-header-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-pane-action-zoom-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-1')), findsNothing);
    expect(find.byKey(const Key('shell-pane-2')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-header-2')), findsOneWidget);
    expect(
      find.byKey(const Key('shell-pane-action-split-right-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shell-pane-action-split-down-2')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shell-pane-action-split-right-2')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shell-pane-action-split-down-2')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shell-pane-action-split-right-2')),
          )
          .tooltip,
      'Split right unavailable: Unzoom the active pane to manage other panes.',
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shell-pane-action-split-down-2')),
          )
          .tooltip,
      'Split down unavailable: Unzoom the active pane to manage other panes.',
    );

    await tester.tap(find.byKey(const Key('shell-pane-action-split-right-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-3')), findsNothing);

    await tester.tap(find.byKey(const Key('shell-pane-action-zoom-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-pane-action-close-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('shell-pane-2')), findsNothing);
    expect(find.byKey(const Key('shell-pane-header-1')), findsNothing);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('dragging a split pane divider resizes adjacent panes', (
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

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    final firstPane = find.byKey(const Key('shell-pane-1'));
    final secondPane = find.byKey(const Key('shell-pane-2'));
    final divider = find.byKey(const Key('shell-pane-divider-1-2'));
    expect(divider, findsOneWidget);

    final firstWidthBefore = tester.getSize(firstPane).width;
    final secondWidthBefore = tester.getSize(secondPane).width;

    await tester.drag(divider, const Offset(120, 0));
    await tester.pump();

    expect(tester.getSize(firstPane).width, greaterThan(firstWidthBefore));
    expect(tester.getSize(secondPane).width, lessThan(secondWidthBefore));
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('dragging a split pane divider respects minimum pane width', (
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

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    final secondPane = find.byKey(const Key('shell-pane-2'));
    final divider = find.byKey(const Key('shell-pane-divider-1-2'));
    expect(divider, findsOneWidget);

    final secondRenderObject = _terminalRenderObjectForPane(tester, '2');
    final minimumPaneWidth = 24 * secondRenderObject.debugCellSize.width;

    await tester.drag(divider, const Offset(2000, 0));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(secondPane).width,
      greaterThanOrEqualTo(minimumPaneWidth),
    );
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('native paste sends clipboard text to the active session', (
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

    await _invokeNativeWindowBridge(tester, const MethodCall('nativePaste'));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, utf8.encode(clipboardText));
  });

  testWidgets('command menu keeps advanced paste hidden', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _openCommandMenu(tester);

    expect(find.byKey(const Key('shell-advanced-paste')), findsNothing);
    expect(find.text('Advanced paste'), findsNothing);
    expect(fakeBindings.writes, isEmpty);
  });

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
    'native paste records text for paste history reuse and persistence',
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

      await _invokeNativeWindowBridge(tester, const MethodCall('nativePaste'));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, hasLength(1));
      expect(fakeBindings.writes.last, utf8.encode(clipboardText));
      expect(pasteHistoryRepository.document, isNull);

      await _openToolbeltSource(
        tester,
        tabKey: const Key('toolbelt-tab-paste-history'),
        actionKey: const Key('toolbelt-paste-history'),
      );

      expect(find.byKey(const Key('paste-history-sheet')), findsOneWidget);
      expect(find.text(clipboardText), findsOneWidget);
      final persistToggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('paste-history-persist')),
      );
      expect(persistToggle.contentPadding, EdgeInsets.zero);
      expect(
        tester
            .widget<Text>(find.text('Save History to Disk'))
            .style
            ?.fontWeight,
        FontWeight.w600,
      );

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

  testWidgets('empty paste history disables clear action', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      pasteHistoryRepository: MemoryPasteHistoryRepository(),
    );

    await _openToolbeltSource(
      tester,
      tabKey: const Key('toolbelt-tab-paste-history'),
      actionKey: const Key('toolbelt-paste-history'),
    );

    expect(find.text('0 recent items'), findsOneWidget);
    expect(find.text('No copied or pasted text yet.'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('paste-history-clear')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('native paste confirms carriage-return multiline text', (
    tester,
  ) async {
    const clipboardText = 'first command\rsecond command';
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

    final pasteFuture = _dispatchNativeWindowBridge(
      tester,
      const MethodCall('nativePaste'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('paste-confirmation-dialog')), findsOneWidget);
    expect(find.text('Paste 28 characters across 2 lines?'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    final preview = tester.widget<Text>(
      find.byKey(const Key('paste-confirmation-preview')),
    );
    expect(preview.data, 'first command\nsecond command');
    expect(fakeBindings.writes, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await pasteFuture;
  });

  testWidgets(
    'command-shift-h opens saved paste history without leaking input',
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
      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyH);

      expect(find.byKey(const Key('paste-history-sheet')), findsOneWidget);
      expect(find.text(savedText), findsOneWidget);
      final savedPasteTile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const Key('paste-history-entry-0')),
          matching: find.byType(ListTile),
        ),
      );
      expect(savedPasteTile.contentPadding, EdgeInsets.zero);
      expect(fakeBindings.writes, isEmpty);

      await tester.tap(find.byKey(const Key('paste-history-entry-0')));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, hasLength(1));
      expect(fakeBindings.writes.last, utf8.encode(savedText));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('paste history confirms multiline entries before sending', (
    tester,
  ) async {
    const savedText = 'history line one\nhistory line two';
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

    await _openToolbeltSource(
      tester,
      tabKey: const Key('toolbelt-tab-paste-history'),
      actionKey: const Key('toolbelt-paste-history'),
    );

    await tester.tap(find.byKey(const Key('paste-history-entry-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('paste-confirmation-dialog')), findsOneWidget);
    expect(find.text('Paste 33 characters across 2 lines?'), findsOneWidget);
    final preview = tester.widget<Text>(
      find.byKey(const Key('paste-confirmation-preview')),
    );
    expect(preview.data, savedText);
    expect(fakeBindings.writes, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'command-option-b opens instant replay workspace backed by terminal viewport',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      String? copiedText;
      final windowBridgeCalls = <MethodCall>[];
      var windowMetricsCalls = 0;
      const windowBridgeChannel = MethodChannel('app/window_bridge');
      var replayNow = DateTime(2026, 1, 1, 12);
      final instantReplayStore = InstantReplayStore(now: () => replayNow);

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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowBridgeChannel,
        (methodCall) async {
          windowBridgeCalls.add(methodCall);
          if (methodCall.method == 'windowMetrics') {
            windowMetricsCalls += 1;
            final contentSize = windowMetricsCalls == 1
                ? const Size(900, 600)
                : const Size(760, 540);
            return <String, Object?>{
              'contentWidth': contentSize.width,
              'contentHeight': contentSize.height,
              'frameWidth': contentSize.width + 40,
              'frameHeight': contentSize.height + 60,
              'devicePixelRatio': 2.0,
            };
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowBridgeChannel,
          null,
        );
      });

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        instantReplayStore: instantReplayStore,
      );

      fakeBindings.enqueueFrame(1, {
        'rows': [
          {
            'index': 0,
            'text': '󰀵ab important output important',
            'style_runs': const [],
          },
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
      replayNow = replayNow.add(const Duration(milliseconds: 100));
      fakeBindings.setFrame(1, {
        'rows': [
          {
            'index': 0,
            'text': '󰀵ab important output important',
            'style_runs': const [],
          },
          {
            'index': 1,
            'text': 'another part of the frame changed',
            'style_runs': const [],
          },
        ],
        'cursor': {'row': 1, 'col': 0, 'visible': true},
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
      replayNow = replayNow.add(const Duration(milliseconds: 3100));
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
      await _sendMetaAltShortcut(tester, LogicalKeyboardKey.keyB);

      final semantics = tester.ensureSemantics();
      expect(find.byKey(const Key('instant-replay-sheet')), findsNothing);
      expect(find.byKey(const Key('instant-replay-layout')), findsOneWidget);
      expect(
        find.bySemanticsLabel('Replay recent activity layout'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Replay controls for recent activity'),
        findsOneWidget,
      );
      expect(find.text('Replay'), findsOneWidget);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('instant-replay-layout')),
          matching: find.byKey(const Key('instant-replay-viewport')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('instant-replay-controls')), findsOneWidget);
      expect(find.byKey(const Key('instant-replay-stage')), findsOneWidget);
      expect(find.byKey(const Key('instant-replay-fit')), findsOneWidget);
      expect(
        find.byKey(const Key('instant-replay-floating-dock')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('instant-replay-dock-drag-handle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('replay-semantic-segment-0')),
        findsOneWidget,
      );
      expect(find.text('Activity'), findsWidgets);
      final instantReplayStageRect = tester.getRect(
        find.byKey(const Key('instant-replay-stage')),
      );
      final instantReplayDockRect = tester.getRect(
        find.byKey(const Key('instant-replay-floating-dock')),
      );
      expect(
        instantReplayStageRect.contains(instantReplayDockRect.topLeft),
        isTrue,
      );
      expect(
        instantReplayStageRect.contains(instantReplayDockRect.bottomRight),
        isTrue,
      );
      expect(
        instantReplayDockRect.top,
        lessThan(
          tester
              .getBottomLeft(find.byKey(const Key('instant-replay-viewport')))
              .dy,
        ),
      );
      expect(find.textContaining('Recorded at 80x24'), findsOneWidget);
      expect(
        find.byKey(const Key('instant-replay-retention-policy')),
        findsOneWidget,
      );
      expect(find.text('Retains latest 60 frames'), findsOneWidget);
      expect(find.byKey(const Key('instant-replay-speed')), findsOneWidget);
      expect(find.byKey(const Key('instant-replay-time-mode')), findsOneWidget);
      expect(find.byTooltip('Replay timing'), findsOneWidget);
      expect(find.byTooltip('Step back in replay'), findsOneWidget);
      expect(find.byTooltip('Step forward in replay'), findsOneWidget);
      expect(find.byTooltip('Copy visible'), findsOneWidget);
      expect(find.byTooltip('Copy selection'), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);
      expect(
        windowBridgeCalls.where((call) => call.method == 'windowMetrics'),
        hasLength(1),
      );
      expect(
        windowBridgeCalls.where((call) => call.method == 'resizeBy'),
        isEmpty,
      );
      final timelineFinder = find.byKey(const Key('instant-replay-timeline'));
      var timeline = tester.widget<Slider>(timelineFinder);
      final startingTimelineValue = timeline.value;
      expect(startingTimelineValue, lessThan(timeline.max));
      expect(timeline.max, greaterThanOrEqualTo(2000.0));
      expect(timeline.max, lessThan(2200.0));
      expect(
        find.byKey(const Key('instant-replay-quiet-track')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('instant-replay-change-marker')),
        findsWidgets,
      );
      expect(
        find.byKey(const Key('instant-replay-idle-marker')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Tooltip>(
              find.byKey(const Key('instant-replay-idle-marker')),
            )
            .message,
        startsWith('Idle gap: '),
      );

      await tester.tap(find.byKey(const Key('instant-replay-time-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Real time · preserve all gaps'));
      await tester.pumpAndSettle();
      timeline = tester.widget<Slider>(timelineFinder);
      expect(timeline.max, greaterThanOrEqualTo(3200.0));
      expect(timeline.max, lessThan(3300.0));

      await tester.tap(find.byKey(const Key('instant-replay-time-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smart · skip long idle gaps'));
      await tester.pumpAndSettle();
      timeline = tester.widget<Slider>(timelineFinder);
      expect(timeline.max, greaterThanOrEqualTo(2000.0));
      expect(timeline.max, lessThan(2200.0));

      final idleMarkerHover = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await idleMarkerHover.addPointer(
        location: tester.getCenter(
          find.byKey(const Key('instant-replay-idle-marker')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.textContaining('Idle gap: '), findsOneWidget);
      await idleMarkerHover.removePointer();

      await tester.tap(
        find.byKey(const Key('instant-replay-fit-recorded-size')),
      );
      await tester.pumpAndSettle();

      final replayResizeCalls = windowBridgeCalls
          .where((call) => call.method == 'resizeBy')
          .toList();
      expect(replayResizeCalls, hasLength(1));
      final replayResizeArguments =
          replayResizeCalls.single.arguments! as Map<Object?, Object?>;
      expect(
        replayResizeArguments['widthDelta']! as double,
        greaterThanOrEqualTo(0),
      );
      expect(
        replayResizeArguments['heightDelta']! as double,
        greaterThanOrEqualTo(0),
      );
      expect(
        windowBridgeCalls.where((call) => call.method == 'windowMetrics'),
        hasLength(1),
      );

      await tester.tap(find.byTooltip('Play replay'));
      await tester.pump(const Duration(milliseconds: 32));

      final instantReplayDockDrag = await tester.startGesture(
        tester.getCenter(
          find.byKey(const Key('instant-replay-dock-drag-handle')),
        ),
      );
      await instantReplayDockDrag.moveBy(const Offset(0, -24));
      await tester.pump();
      final timelineValueBeforeDockDrag = tester
          .widget<Slider>(timelineFinder)
          .value;
      await tester.pump(const Duration(milliseconds: 120));

      timeline = tester.widget<Slider>(timelineFinder);
      expect(timeline.value, greaterThan(timelineValueBeforeDockDrag));
      expect(timeline.value, lessThan(timeline.max));
      expect(find.byTooltip('Pause replay'), findsOneWidget);
      await instantReplayDockDrag.up();
      await tester.pump();

      timeline.onChanged!(startingTimelineValue);
      await tester.pumpAndSettle();

      timeline = tester.widget<Slider>(timelineFinder);
      expect(timeline.value, startingTimelineValue);

      await tester.enterText(
        find.byKey(const Key('instant-replay-search')),
        'important',
      );
      await tester.pumpAndSettle();

      expect(find.text('2 unique matches in replay'), findsOneWidget);
      final replayRenderObject = _terminalRenderObject(tester);
      final replayCellSize = replayRenderObject.debugCellSize;
      final replaySearchRects = replayRenderObject.debugSearchHighlightRects;
      expect(replaySearchRects, hasLength(2));
      _expectRectClose(
        replaySearchRects.first,
        Rect.fromLTWH(
          replayCellSize.width * 4,
          0,
          replayCellSize.width * 9,
          replayCellSize.height,
        ),
      );
      expect(
        tester
            .widget<TerminalViewport>(
              find.byKey(const Key('instant-replay-viewport')),
            )
            .activeSearchMatchIndex,
        0,
      );

      await tester.tap(find.byKey(const Key('instant-replay-search-next')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TerminalViewport>(
              find.byKey(const Key('instant-replay-viewport')),
            )
            .activeSearchMatchIndex,
        1,
      );

      await tester.tap(find.byKey(const Key('instant-replay-search-previous')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TerminalViewport>(
              find.byKey(const Key('instant-replay-viewport')),
            )
            .activeSearchMatchIndex,
        0,
      );

      await tester.tap(find.byKey(const Key('instant-replay-search')));
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.enter,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter, platform: 'macos');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TerminalViewport>(
              find.byKey(const Key('instant-replay-viewport')),
            )
            .activeSearchMatchIndex,
        1,
      );

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.shiftLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.enter,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.shiftLeft,
        platform: 'macos',
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TerminalViewport>(
              find.byKey(const Key('instant-replay-viewport')),
            )
            .activeSearchMatchIndex,
        0,
      );

      await tester.tap(find.byKey(const Key('instant-replay-copy-visible')));
      await tester.pumpAndSettle();

      expect(copiedText, '󰀵ab important output important');
      expect(fakeBindings.writes, isEmpty);

      await tester.tap(find.byKey(const Key('instant-replay-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Clear recent replay history?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('instant-replay-layout')), findsOneWidget);

      await tester.tap(find.byKey(const Key('instant-replay-search')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('instant-replay-layout')), findsNothing);
      expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Start recording for Replay (keystrokes redacted; command metadata included when available)',
        ),
        findsOneWidget,
      );
      semantics.dispose();
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
      showHiddenRedesignEntryPointsForTesting: true,
    );

    await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

    expect(find.byKey(const Key('password-manager-sheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('password-manager-label-field')),
      'staging sudo',
    );
    await tester.enterText(
      find.byKey(const Key('password-manager-password-field')),
      's3cr3t!',
    );
    await tester.pump();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Password')),
      matchesSemantics(
        label: 'Password',
        value: 'Password entered',
        isTextField: true,
        isObscured: true,
        hasTapAction: true,
        hasSetTextAction: true,
      ),
    );
    await tester.tap(find.byKey(const Key('password-manager-add')));
    await tester.pumpAndSettle();
    final passwordEntryTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('password-manager-entry-0')),
        matching: find.byType(ListTile),
      ),
    );
    expect(passwordEntryTile.contentPadding, EdgeInsets.zero);

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

    await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

    await tester.tap(find.byKey(const Key('password-manager-send-0')));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes.single, utf8.encode('s3cr3t!\n'));
  });

  testWidgets('password manager can remove a saved password entry', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      showHiddenRedesignEntryPointsForTesting: true,
    );

    await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

    await tester.enterText(
      find.byKey(const Key('password-manager-label-field')),
      'staging sudo',
    );
    await tester.enterText(
      find.byKey(const Key('password-manager-password-field')),
      's3cr3t!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('password-manager-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('password-manager-entry-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('password-manager-remove-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('password-manager-entry-0')), findsNothing);
    expect(
      find.text(
        'No saved passwords in this session. Add one above, then open a password prompt before sending.',
      ),
      findsOneWidget,
    );
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('password manager disables add until a password is entered', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      showHiddenRedesignEntryPointsForTesting: true,
    );

    await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('password-manager-add')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('password-manager-label-field')),
      'staging sudo',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('password-manager-add')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('password-manager-password-field')),
      's3cr3t!',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('password-manager-add')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('password manager rechecks the prompt before sending', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      showHiddenRedesignEntryPointsForTesting: true,
    );

    await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

    await tester.enterText(
      find.byKey(const Key('password-manager-label-field')),
      'staging sudo',
    );
    await tester.enterText(
      find.byKey(const Key('password-manager-password-field')),
      's3cr3t!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('password-manager-add')));
    await tester.pumpAndSettle();
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

    await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

    fakeBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': r'dev $ ', 'style_runs': const []},
      ],
      'cursor': {'row': 0, 'col': 6, 'visible': true},
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

    await tester.tap(find.byKey(const Key('password-manager-send-0')));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes, isEmpty);
    expect(
      find.text('Password send blocked: no password prompt is active.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'password manager recognizes capitalized password prompts before sending',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        showHiddenRedesignEntryPointsForTesting: true,
      );

      await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

      await tester.enterText(
        find.byKey(const Key('password-manager-label-field')),
        'remote login',
      );
      await tester.enterText(
        find.byKey(const Key('password-manager-password-field')),
        's3cr3t!',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('password-manager-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close password manager'));
      await tester.pumpAndSettle();

      fakeBindings.setFrame(1, {
        'rows': [
          {'index': 0, 'text': 'Password:', 'style_runs': const []},
        ],
        'cursor': {'row': 0, 'col': 9, 'visible': true},
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

      await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

      await tester.tap(find.byKey(const Key('password-manager-send-0')));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes.single, utf8.encode('s3cr3t!\n'));
    },
  );

  testWidgets(
    'password manager recognizes wrapped password prompts before sending',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        showHiddenRedesignEntryPointsForTesting: true,
      );

      await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

      await tester.enterText(
        find.byKey(const Key('password-manager-label-field')),
        'remote login',
      );
      await tester.enterText(
        find.byKey(const Key('password-manager-password-field')),
        's3cr3t!',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('password-manager-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close password manager'));
      await tester.pumpAndSettle();

      fakeBindings.setFrame(1, {
        'rows': [
          {
            'index': 0,
            'text': '[sudo] password for development-',
            'wrapped': true,
            'style_runs': const [],
          },
          {'index': 1, 'text': 'host:', 'style_runs': const []},
        ],
        'cursor': {'row': 1, 'col': 5, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 32,
        'dirty_ranges': [
          {'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      await tester.pump(const Duration(milliseconds: 40));

      await _tapToolbeltAction(tester, const Key('toolbelt-password-manager'));

      await tester.tap(find.byKey(const Key('password-manager-send-0')));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes.single, utf8.encode('s3cr3t!\n'));
    },
  );

  testWidgets('copy shortcut writes the selection to the clipboard', (
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

    await _sendMetaShortcut(tester, LogicalKeyboardKey.keyC);

    expect(copiedText, 'ianvs terminal ready');
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'OSC 1337 inline buttons route custom activation and explicit copy through product bridges',
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
      fakeBindings.inlineButtonActivationResponses.addAll(
        <int, Map<String, Object?>>{
          7001: <String, Object?>{'activated': true, 'kind': 'custom'},
          7002: <String, Object?>{
            'activated': true,
            'kind': 'copy',
            'text': 'copy-exact',
          },
        },
      );

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      fakeBindings.setFrame(1, <String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': '        ',
            'style_runs': <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 0, 'col': 8, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'inline_buttons': <Object?>[
          <String, Object?>{
            'id': 7001,
            'kind': 'custom',
            'row': 0,
            'col': 0,
            'code': 42,
            'icon': 'star.fill',
            'valid': true,
            'width_cells': 4,
          },
          <String, Object?>{
            'id': 7002,
            'kind': 'copy',
            'row': 0,
            'col': 4,
            'block_id': 'copy-1',
            'valid': true,
            'width_cells': 4,
          },
        ],
      });
      await tester.pump(const Duration(milliseconds: 80));

      await tester.tap(find.byKey(terminalInlineButtonKey(7001)));
      await tester.tap(find.byKey(terminalInlineButtonKey(7002)));
      await tester.pump();
      expect(
        fakeBindings.jsonRequests.where(
          (request) => request['kind'] == 'terminal.activate_iterm_button',
        ),
        <Map<String, Object?>>[
          <String, Object?>{
            'kind': 'terminal.activate_iterm_button',
            'id': 7001,
          },
          <String, Object?>{
            'kind': 'terminal.activate_iterm_button',
            'id': 7002,
          },
        ],
      );
      expect(copiedText, 'copy-exact');
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets('annotations empty state guides setup before selected text', (
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

    await _tapToolbeltAction(tester, const Key('toolbelt-annotations'));

    expect(find.byKey(const Key('annotations-sheet')), findsOneWidget);
    expect(find.byKey(const Key('annotations-empty-state')), findsOneWidget);
    expect(find.text('Select output before annotating'), findsOneWidget);
    expect(find.text('Select terminal output in the pane.'), findsOneWidget);
    expect(find.text('Open Annotations again.'), findsOneWidget);
    expect(find.text('Enter a note and save it.'), findsOneWidget);
    expect(find.byKey(const Key('annotations-empty-step-0')), findsOneWidget);

    final saveButton = tester.widget<FilledButton>(
      find.byKey(const Key('annotation-save')),
    );
    expect(saveButton.onPressed, isNull);
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

    await _tapToolbeltAction(tester, const Key('toolbelt-annotations'));

    expect(find.byKey(const Key('annotations-sheet')), findsOneWidget);
    expect(find.text('ianvs terminal ready'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('annotation-note-field')),
      'Check startup output',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('annotation-save')));
    await tester.pumpAndSettle();

    expect(find.text('Check startup output'), findsOneWidget);
    expect(find.byKey(const Key('annotation-entry-0')), findsOneWidget);
    final annotationTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('annotation-entry-0')),
        matching: find.byType(ListTile),
      ),
    );
    expect(annotationTile.contentPadding, EdgeInsets.zero);

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

  testWidgets('hidden OSC 1337 annotation adds a badge without opening UI', (
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    fakeBindings.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'session_annotation',
        sessionId: sessionId,
        payload: const <String, Object?>{
          'source': 'iterm1337',
          'message': 'Hidden protocol note',
          'selectedText': 'ready',
          'visible': false,
          'startRow': 0,
          'startCol': 15,
          'endRow': 0,
          'endCol': 20,
        },
      ),
    );
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('annotations-sheet')), findsNothing);
    expect(
      find.byKey(Key('terminal-annotation-badge-$sessionId')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('terminal-annotation-badge-$sessionId')));
    await tester.pumpAndSettle();

    expect(find.text('Hidden protocol note'), findsOneWidget);
    expect(find.text('ready'), findsOneWidget);
    expect(find.byKey(const Key('annotation-entry-0')), findsOneWidget);
  });

  testWidgets('visible OSC 1337 annotation opens once for the active pane', (
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    void enqueueVisible(String note) => fakeBindings.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'session_annotation',
        sessionId: sessionId,
        payload: <String, Object?>{
          'source': 'iterm1337',
          'message': note,
          'selectedText': 'terminal',
          'visible': true,
          'startRow': 0,
          'startCol': 6,
          'endRow': 0,
          'endCol': 14,
        },
      ),
    );

    enqueueVisible('Visible protocol note');
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('annotations-sheet')), findsOneWidget);
    expect(find.text('Visible protocol note'), findsOneWidget);

    enqueueVisible('Second protocol note');
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('annotations-sheet')), findsOneWidget);
    expect(find.text('Second protocol note'), findsOneWidget);
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
    'switching split panes exits copy mode for the previous pane',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyC);
      expect(find.text('Copy mode'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shell-pane-1')));
      await tester.pumpAndSettle();

      expect(find.text('Copy mode'), findsNothing);

      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyC);
      expect(find.text('Copy mode'), findsOneWidget);
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

      expect(find.text('Command palette'), findsOneWidget);
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

      expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);

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

      expect(find.text('Command palette'), findsNothing);
      expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shortcut proof matrix covers planned mac shortcuts',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      final windowBridgeCalls = <MethodCall>[];
      const windowBridgeChannel = MethodChannel('app/window_bridge');
      final pasteHistoryRepository = MemoryPasteHistoryRepository(
        PasteHistoryDocument(
          entries: [
            PasteHistoryEntry(
              text: 'matrix paste',
              kind: PasteHistoryKind.paste,
              createdAt: DateTime.utc(2026, 6, 25),
            ),
          ],
        ),
      );

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowBridgeChannel,
        (call) async {
          windowBridgeCalls.add(call);
          if (call.method == 'windowMetrics') {
            return <String, Object?>{
              'contentWidth': 900.0,
              'contentHeight': 600.0,
              'frameWidth': 940.0,
              'frameHeight': 660.0,
              'devicePixelRatio': 2.0,
            };
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowBridgeChannel,
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
        instantReplayStore: InstantReplayStore(
          now: () => DateTime.utc(2026, 6, 25, 12),
        ),
      );

      await tester.tap(find.byType(TerminalViewport).last);
      await tester.pump();

      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyK);
      expect(
        fakeBindings.jsonRequests,
        contains(
          predicate<Map<String, Object?>>(
            (request) => request['kind'] == 'terminal.clear_buffer',
          ),
        ),
      );
      expect(fakeBindings.writes, isEmpty);

      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyT);
      expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
      _expectSelectedTab(tester, '2');
      expect(fakeBindings.writes, isEmpty);

      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyD);
      expect(find.byKey(const Key('shell-pane-3')), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);

      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyD);
      expect(find.byKey(const Key('shell-pane-4')), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);

      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyF);
      expect(find.byKey(const Key('terminal-search-bar')), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);
      await tester.tap(find.byKey(const Key('terminal-search-close')));
      await tester.pumpAndSettle();

      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyP);
      expect(
        find.byKey(const Key('shell-command-menu-overlay')),
        findsOneWidget,
      );
      expect(fakeBindings.writes, isEmpty);
      await tester.tap(find.byTooltip('Close command palette'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TerminalViewport).last);
      await tester.pump();
      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.keyH);
      expect(find.byKey(const Key('paste-history-sheet')), findsOneWidget);
      expect(find.text('matrix paste'), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TerminalViewport).last);
      await tester.pump();
      await _sendMetaAltShortcut(tester, LogicalKeyboardKey.keyB);
      expect(find.byKey(const Key('instant-replay-layout')), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);
      await tester.tap(find.byTooltip('Close replay'));
      await tester.pumpAndSettle();

      await _sendMetaAltShortcut(tester, LogicalKeyboardKey.space);
      expect(
        windowBridgeCalls.map((call) => call.method),
        contains('toggleHotkeyWindow'),
      );
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

      expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell-tab-3'), findsNothing);
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

      expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell-tab-2'), findsNothing);

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendControlShortcut(
        tester,
        LogicalKeyboardKey.keyT,
        platform: 'macos',
      );

      expect(find.bySemanticsIdentifier('shell-tab-2'), findsNothing);
      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, equals(const [0x14]));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('command menu explains disabled actions inline', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _openCommandMenu(tester);

    expect(find.textContaining('No recently closed tab'), findsOneWidget);
    expect(find.text('Terminal color presets'), findsOneWidget);
    expect(find.text('Theme picker'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('shell-export-scrollback')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Save retained text as a .txt file for sharing or later review',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('shell-clear-buffer')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Clear visible output and history; keep the current command line',
      ),
      findsOneWidget,
    );

    expect(find.byKey(const Key('shell-select-command-output')), findsNothing);
  });

  testWidgets('clear buffer reports its successful effect', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-clear-buffer')));
    await tester.tap(find.byKey(const Key('shell-clear-buffer')));
    await tester.pumpAndSettle();

    expect(
      fakeBindings.jsonRequests,
      contains(
        predicate<Map<String, Object?>>(
          (request) => request['kind'] == 'terminal.clear_buffer',
        ),
      ),
    );
    expect(
      find.text('Buffer cleared. The current command line was kept.'),
      findsOneWidget,
    );
  });

  testWidgets('export diagnostics explains when no bundle is available', (
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
    await tester.ensureVisible(
      find.byKey(const Key('shell-export-diagnostics')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shell-export-diagnostics')));
    await tester.pumpAndSettle();

    expect(
      find.text('Diagnostics export is unavailable for the active sessions.'),
      findsOneWidget,
    );
  });

  testWidgets('command menu notification toggles update labels and feedback', (
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

    final toggles = [
      (
        key: const Key('shell-toggle-command-finished-notify'),
        disableLabel: 'Disable command-finished notifications',
        disabledFeedback: 'Command-finished notifications disabled and saved.',
        enableLabel: 'Enable command-finished notifications',
        enabledFeedback: 'Command-finished notifications enabled and saved.',
      ),
      (
        key: const Key('shell-toggle-activity-monitor'),
        disableLabel: 'Disable activity monitor',
        disabledFeedback: 'Activity monitor disabled and saved.',
        enableLabel: 'Enable activity monitor',
        enabledFeedback: 'Activity monitor enabled and saved.',
      ),
    ];

    for (final toggle in toggles) {
      await _openCommandMenu(tester);
      await tester.ensureVisible(find.byKey(toggle.key));
      await tester.pumpAndSettle();

      expect(find.text(toggle.disableLabel), findsOneWidget);

      await tester.tap(find.byKey(toggle.key));
      await tester.pumpAndSettle();

      expect(find.text(toggle.disabledFeedback), findsOneWidget);

      await _openCommandMenu(tester);
      await tester.ensureVisible(find.byKey(toggle.key));
      await tester.pumpAndSettle();

      expect(find.text(toggle.enableLabel), findsOneWidget);

      await tester.tap(find.byKey(toggle.key));
      await tester.pumpAndSettle();

      expect(find.text(toggle.enabledFeedback), findsOneWidget);
    }
  });

  testWidgets('command menu omits clipboard paste and folder-specific tabs', (
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
    expect(find.byKey(const Key('shell-top-paste-clipboard')), findsNothing);
    expect(find.byKey(const Key('shell-new-tab-at-folder')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      'paste',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('No action matches "paste".'), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'read-only mode blocks shortcut and native paste before clipboard read',
    (tester) async {
      const clipboardText = 'shortcut blocked paste';
      final fakeBindings = FakePtyBackend();
      var clipboardReads = 0;

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

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openCommandMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('shell-toggle-read-only')),
      );
      await tester.tap(find.byKey(const Key('shell-toggle-read-only')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyV);

      expect(fakeBindings.writes, isEmpty);
      expect(clipboardReads, 0);

      await _invokeNativeWindowBridge(tester, const MethodCall('nativePaste'));

      expect(fakeBindings.writes, isEmpty);
      expect(clipboardReads, 0);

      await _openCommandMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('shell-toggle-read-only')),
      );
      await tester.tap(find.byKey(const Key('shell-toggle-read-only')));
      await tester.pumpAndSettle();

      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyV);

      expect(clipboardReads, 1);
      expect(fakeBindings.writes.single, utf8.encode(clipboardText));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('command menu accepts hyphenated read-only query', (
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
    expect(find.bySemanticsLabel('Search actions'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      'read-only',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Read-only mode enabled. Input is blocked'),
      findsOneWidget,
    );

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-toggle-read-only')));
    await tester.pumpAndSettle();

    expect(find.text('Disable read-only mode'), findsOneWidget);
  });

  testWidgets(
    'focused shell semantics expose command search and selected tab',
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
            'command': 'pwd',
            'pwd': '/tmp/project',
            'exit_code': 0,
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        tester.getSemantics(find.bySemanticsIdentifier('shell-tab-1')),
        matchesSemantics(
          hasSelectedState: true,
          isSelected: true,
          isButton: true,
        ),
      );
      await _openCommandMenu(tester);

      final searchSemantics = tester.getSemantics(
        find.bySemanticsLabel('Search actions'),
      );
      expect(searchSemantics.flagsCollection.isTextField, isTrue);
    },
  );

  testWidgets(
    'command menu supports keyboard-only focus traversal to actions',
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

      final searchEditable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('shell-command-search-field')),
          matching: find.byType(EditableText),
        ),
      );
      expect(searchEditable.focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('terminal-search-bar')), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);
    },
  );

  testWidgets('tab strip supports keyboard-only focus traversal between tabs', (
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

    await _sendMetaShortcut(tester, LogicalKeyboardKey.keyT);
    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    _expectSelectedTab(tester, '2');

    await tester.tap(find.byKey(const Key('shell-tab-1')));
    await tester.pumpAndSettle();
    _expectSelectedTab(tester, '1');

    tester
        .widget<TextButton>(find.byKey(const Key('shell-tab-1')))
        .focusNode!
        .requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    _expectSelectedTab(tester, '2');
    expect(fakeBindings.writes, isEmpty);
  });

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

      expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);

      await _sendControlShortcut(
        tester,
        LogicalKeyboardKey.keyT,
        platform: 'linux',
      );

      expect(find.text('Command palette'), findsNothing);
      expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
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
    'native find menu opens search without leaking input',
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

      await _invokeNativeWindowBridge(
        tester,
        const MethodCall('nativeFind', <String, Object?>{'tag': 1}),
      );

      expect(find.byKey(const Key('terminal-search-bar')), findsOneWidget);
      expect(find.byKey(const Key('terminal-search-field')), findsOneWidget);
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
      notificationSender:
          ({required title, body, identifier, expiresAfterMs}) async {
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
    await _pumpUntilCondition(
      tester,
      description: 'inactive session activity notification',
      condition: () => notifications.isNotEmpty,
    );

    expect(notifications, hasLength(1));
    expect(notifications.single['title'], startsWith('Activity in '));
    expect(notifications.single['body'], 'background build done');
    expect(notifications.single['identifier'], 'ianvs-terminal.activity.1');
  });

  testWidgets(
    'notification authorization failures surface actionable feedback once',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        notificationSender:
            ({required title, body, identifier, expiresAfterMs}) async {
              throw PlatformException(
                code: 'notification_authorization_failed',
                message: 'Denied by system',
              );
            },
      );

      fakeBindings.setFrame(1, <String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'pwd',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 1,
            'text': '/tmp/project',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 2,
            'text': 'dev@host %',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 3,
            'text': '',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 3, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 4},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 3,
        'window_title': null,
        'window_icon_name': null,
      });

      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: '1',
          payload: const <String, Object?>{
            'hook': 'command_finished',
            'command': 'echo ok',
            'exit_code': 0,
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'macOS notifications are blocked for Ianvs Terminal. Enable them in System Settings > Notifications.',
        ),
        findsOneWidget,
      );

      await _openCommandMenu(tester);
      expect(
        find.textContaining(
          'macOS notifications are currently blocked in System Settings.',
        ),
        findsNWidgets(2),
      );
      await tester.tap(find.byTooltip('Close command palette'));
      await tester.pumpAndSettle();

      fakeBindings.enqueueEvent(1, PtyEvent(kind: 'bell', sessionId: '1'));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'macOS notifications are blocked for Ianvs Terminal. Enable them in System Settings > Notifications.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'notification warning clears from the command menu after a successful send',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      var shouldFail = true;

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        notificationSender:
            ({required title, body, identifier, expiresAfterMs}) async {
              if (shouldFail) {
                throw PlatformException(
                  code: 'notification_authorization_failed',
                  message: 'Denied by system',
                );
              }
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
            'exit_code': 0,
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();

      await _openCommandMenu(tester);
      expect(
        find.textContaining(
          'macOS notifications are currently blocked in System Settings.',
        ),
        findsNWidgets(2),
      );
      await tester.tap(find.byTooltip('Close command palette'));
      await tester.pumpAndSettle();

      shouldFail = false;
      fakeBindings.enqueueEvent(1, PtyEvent(kind: 'bell', sessionId: '1'));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();

      await _openCommandMenu(tester);
      expect(
        find.textContaining(
          'macOS notifications are currently blocked in System Settings.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'inactive session activity notification uses wrapped logical rows as its preview',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      final notifications = <Map<String, String?>>[];

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        notificationSender:
            ({required title, body, identifier, expiresAfterMs}) async {
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
          {'index': 0, 'text': 'ianvs terminal ready', 'style_runs': const []},
          {
            'index': 1,
            'text': 'background build',
            'wrapped': true,
            'style_runs': const [],
          },
          {'index': 2, 'text': ' done', 'style_runs': const []},
        ],
        'cursor': {'row': 2, 'col': 4, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 16,
        'dirty_ranges': [
          {'start': 1, 'end': 3},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      await _pumpUntilCondition(
        tester,
        description: 'wrapped inactive session activity notification',
        condition: () => notifications.isNotEmpty,
      );

      expect(notifications, hasLength(1));
      expect(notifications.single['title'], startsWith('Activity in '));
      expect(notifications.single['body'], 'background build done');
      expect(notifications.single['identifier'], 'ianvs-terminal.activity.1');

      fakeBindings.setFrame(1, {
        'rows': [
          {'index': 0, 'text': 'ianvs terminal ready', 'style_runs': const []},
          {
            'index': 1,
            'text': 'background build done: ERROR 42 failed',
            'style_runs': const [],
          },
        ],
        'cursor': {'row': 1, 'col': 38, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 1, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      await _pumpUntilCondition(
        tester,
        description: 'trailing inactive session activity notification',
        condition: () => notifications.length == 2,
      );

      expect(notifications.last['body'], contains('ERROR 42 failed'));
      expect(notifications.last['identifier'], 'ianvs-terminal.activity.1');
    },
  );

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
      notificationSender:
          ({required title, body, identifier, expiresAfterMs}) async {
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

  testWidgets('profile triggers fire for repeated delta output', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final profile = defaultTerminalProfile().copyWith(
      triggers: const [
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
    );

    Map<String, Object?> passwordDeltaFrame() {
      return {
        'frame_kind': 'delta',
        'rows': [
          {'index': 0, 'text': 'Password:', 'style_runs': const []},
        ],
        'cursor': {'row': 0, 'col': 9, 'visible': true},
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

    fakeBindings.enqueueFrame(1, passwordDeltaFrame());
    await tester.pump(const Duration(milliseconds: 40));
    fakeBindings.enqueueFrame(1, passwordDeltaFrame());
    await tester.pump(const Duration(milliseconds: 40));

    expect(fakeBindings.writes.map(utf8.decode).toList(), [
      'secret\n',
      'secret\n',
    ]);
  });

  testWidgets(
    'profile triggers match wrapped logical rows for notifications and send-text actions',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      final notifications = <Map<String, String?>>[];
      final profile = defaultTerminalProfile().copyWith(
        triggers: const [
          TerminalProfileTrigger(pattern: 'ERROR [0-9]+ failed'),
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
        notificationSender:
            ({required title, body, identifier, expiresAfterMs}) async {
              notifications.add({
                'title': title,
                'body': body,
                'identifier': identifier,
              });
            },
      );

      fakeBindings.setFrame(1, {
        'rows': [
          {'index': 0, 'text': 'Pass', 'wrapped': true, 'style_runs': const []},
          {'index': 1, 'text': 'word:', 'style_runs': const []},
          {
            'index': 2,
            'text': 'ERROR 42 fa',
            'wrapped': true,
            'style_runs': const [],
          },
          {'index': 3, 'text': 'iled', 'style_runs': const []},
        ],
        'cursor': {'row': 3, 'col': 4, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 32,
        'dirty_ranges': [
          {'start': 0, 'end': 4},
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
    },
  );

  testWidgets('captured output empty state guides trigger setup', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      notificationSender:
          ({required title, body, identifier, expiresAfterMs}) async {},
    );

    await _openToolbeltSource(
      tester,
      tabKey: const Key('toolbelt-tab-captured-output'),
      actionKey: const Key('toolbelt-captured-output'),
    );

    expect(find.byKey(const Key('captured-output-sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('captured-output-empty-state')),
      findsOneWidget,
    );
    expect(find.text('Start capturing matching output'), findsOneWidget);
    expect(
      find.text('Open Profiles and add a trigger pattern.'),
      findsOneWidget,
    );
    expect(find.text('Run a command that prints the pattern.'), findsOneWidget);
    expect(
      find.text('Reopen Captured Output to review and copy matches.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('captured-output-empty-step-0')),
      findsOneWidget,
    );
  });

  testWidgets('captured output lists trigger-matched terminal rows', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final profile = defaultTerminalProfile().copyWith(
      triggers: const [TerminalProfileTrigger(pattern: 'ERROR [0-9]+')],
    );
    String? copiedText;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          copiedText =
              (methodCall.arguments as Map<Object?, Object?>)['text']
                  as String?;
        }
        return null;
      },
    );

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [profile]),
      ),
      notificationSender:
          ({required title, body, identifier, expiresAfterMs}) async {},
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

    await _openToolbeltSource(
      tester,
      tabKey: const Key('toolbelt-tab-captured-output'),
      actionKey: const Key('toolbelt-captured-output'),
    );

    expect(find.byKey(const Key('captured-output-sheet')), findsOneWidget);
    expect(find.byKey(const Key('captured-output-entry-0')), findsOneWidget);
    expect(find.text('ERROR 42 failed'), findsOneWidget);
    expect(find.textContaining('Pattern ERROR [0-9]+'), findsOneWidget);
    await tester.tap(find.byKey(const Key('captured-output-copy-0')));
    await tester.pumpAndSettle();
    expect(copiedText, 'ERROR 42 failed');

    await tester.tap(find.byKey(const Key('captured-output-clear')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('captured-output-entry-0')), findsNothing);
    expect(
      find.byKey(const Key('captured-output-empty-state')),
      findsOneWidget,
    );
    expect(find.text('Start capturing matching output'), findsOneWidget);
  });

  testWidgets('captured output stores wrapped logical trigger matches', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final profile = defaultTerminalProfile().copyWith(
      triggers: const [TerminalProfileTrigger(pattern: 'ERROR [0-9]+ failed')],
    );

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [profile]),
      ),
      notificationSender:
          ({required title, body, identifier, expiresAfterMs}) async {},
    );

    fakeBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': 'INFO ready', 'style_runs': const []},
        {
          'index': 1,
          'text': 'ERROR 42 fa',
          'wrapped': true,
          'style_runs': const [],
        },
        {'index': 2, 'text': 'iled', 'style_runs': const []},
      ],
      'cursor': {'row': 2, 'col': 4, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 32,
      'dirty_ranges': [
        {'start': 0, 'end': 3},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    await tester.pump(const Duration(milliseconds: 40));

    await _openToolbeltSource(
      tester,
      tabKey: const Key('toolbelt-tab-captured-output'),
      actionKey: const Key('toolbelt-captured-output'),
    );

    expect(find.byKey(const Key('captured-output-sheet')), findsOneWidget);
    expect(find.text('ERROR 42 failed'), findsOneWidget);
    expect(find.textContaining('Pattern ERROR [0-9]+ failed'), findsOneWidget);
  });

  testWidgets(
    'OSC 1337 ClearCapturedOutput clears only the originating open sheet',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      final profile = defaultTerminalProfile().copyWith(
        triggers: const [TerminalProfileTrigger(pattern: 'CAPTURE-ME')],
      );

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [profile]),
        ),
        notificationSender:
            ({required title, body, identifier, expiresAfterMs}) async {},
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final sessionController = container.read(
        sessionControllerProvider.notifier,
      );
      sessionController.splitActiveSession(
        profile,
        TerminalSplitAxis.horizontal,
      );
      sessionController.activateSession('1');
      await tester.pumpAndSettle();

      fakeBindings.setFrame(1, {
        'rows': [
          {
            'index': 0,
            'text': 'CAPTURE-ME phase35 origin',
            'style_runs': const [],
          },
        ],
        'cursor': {'row': 0, 'col': 25, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      fakeBindings.enqueueFrame(2, {
        'rows': [
          {
            'index': 0,
            'text': 'CAPTURE-ME phase35 neighbor',
            'style_runs': const [],
          },
        ],
        'cursor': {'row': 0, 'col': 27, 'visible': true},
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

      await _openToolbeltSource(
        tester,
        tabKey: const Key('toolbelt-tab-captured-output'),
        actionKey: const Key('toolbelt-captured-output'),
      );
      expect(find.text('CAPTURE-ME phase35 origin'), findsOneWidget);
      expect(find.text('CAPTURE-ME phase35 neighbor'), findsNothing);
      expect(find.byKey(const Key('captured-output-entry-0')), findsOneWidget);

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'clear_captured_output',
          sessionId: '1',
          payload: <String, Object?>{'source': 'unknown'},
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('CAPTURE-ME phase35 origin'), findsOneWidget);

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'clear_captured_output',
          sessionId: '1',
          payload: <String, Object?>{'source': 'iterm1337'},
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byKey(const Key('captured-output-sheet')), findsOneWidget);
      expect(find.text('CAPTURE-ME phase35 origin'), findsNothing);
      expect(find.text('0 captured lines'), findsOneWidget);
      expect(
        find.byKey(const Key('captured-output-empty-state')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Close captured output'));
      await tester.pumpAndSettle();
      sessionController.activateSession('2');
      await tester.pumpAndSettle();
      await _openToolbeltSource(
        tester,
        tabKey: const Key('toolbelt-tab-captured-output'),
        actionKey: const Key('toolbelt-captured-output'),
      );

      expect(find.text('CAPTURE-ME phase35 neighbor'), findsOneWidget);
      expect(find.text('CAPTURE-ME phase35 origin'), findsNothing);
      expect(find.byKey(const Key('captured-output-entry-0')), findsOneWidget);
    },
  );

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
      notificationSender:
          ({required title, body, identifier, expiresAfterMs}) async {},
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
    await tester.ensureVisible(find.byKey(const Key('shell-top-toolbelt')));
    await tester.tap(find.byKey(const Key('shell-top-toolbelt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-toolbelt-panel')), findsOneWidget);
    expect(find.text('Toolbelt'), findsOneWidget);
    expect(
      find.byKey(const Key('toolbelt-panel-command-history')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('toolbelt-tab-captured-output')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('toolbelt-tab-captured-output')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('toolbelt-panel-captured-output')),
      findsOneWidget,
    );
    expect(find.text('1 captured line'), findsOneWidget);
    expect(find.text('ERROR 42 failed'), findsOneWidget);
    expect(find.byKey(const Key('toolbelt-captured-output')), findsOneWidget);
    expect(
      find.byKey(const Key('toolbelt-completion-diagnostics')),
      findsOneWidget,
    );
    expect(find.text('Local terminal objective is complete'), findsOneWidget);
    expect(find.text('Milestones: 0'), findsOneWidget);
    expect(find.text('Backlog: 0'), findsOneWidget);
    expect(find.text('Verification: 0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toolbelt-captured-output')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-toolbelt-panel')), findsNothing);
    expect(find.byKey(const Key('captured-output-sheet')), findsOneWidget);
    expect(find.text('ERROR 42 failed'), findsOneWidget);
  });

  testWidgets('toolbelt exposes focused semantics and keyboard tab traversal', (
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
    await tester.ensureVisible(find.byKey(const Key('shell-top-toolbelt')));
    await tester.tap(find.byKey(const Key('shell-top-toolbelt')));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('toolbelt-panel'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('toolbelt-panel')),
      matchesSemantics(label: 'Toolbelt terminal tools'),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsIdentifier('toolbelt-tab-command-history'),
      ),
      matchesSemantics(
        label: 'Commands toolbelt panel',
        hasSelectedState: true,
        isSelected: true,
        isButton: true,
        hasTapAction: true,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('toolbelt-panel-recent-directories')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsIdentifier('toolbelt-tab-recent-directories'),
      ),
      matchesSemantics(
        label: 'Dirs toolbelt panel',
        hasSelectedState: true,
        isSelected: true,
        isButton: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('toolbelt previews shell history and paste sources', (
    tester,
  ) async {
    const clipboardText = 'toolbelt paste item';
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
      pasteHistoryRepository: MemoryPasteHistoryRepository(),
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
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    await _invokeNativeWindowBridge(tester, const MethodCall('nativePaste'));
    await tester.pumpAndSettle();

    expect(fakeBindings.writes.last, utf8.encode(clipboardText));

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-top-toolbelt')));
    await tester.tap(find.byKey(const Key('shell-top-toolbelt')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('toolbelt-panel-command-history')),
      findsOneWidget,
    );
    expect(find.text('git status'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toolbelt-command-history-entry-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-toolbelt-panel')), findsNothing);
    expect(fakeBindings.writes.last, utf8.encode('git status'));

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-top-toolbelt')));
    await tester.tap(find.byKey(const Key('shell-top-toolbelt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toolbelt-tab-recent-directories')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('toolbelt-panel-recent-directories')),
      findsOneWidget,
    );
    expect(find.text('/tmp/project'), findsAtLeastNWidgets(1));

    await tester.tap(
      find.byKey(const Key('toolbelt-recent-directory-entry-0')),
    );
    await tester.pumpAndSettle();

    expect(fakeBindings.writes.last, utf8.encode('cd /tmp/project'));

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-top-toolbelt')));
    await tester.tap(find.byKey(const Key('shell-top-toolbelt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toolbelt-tab-paste-history')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('toolbelt-panel-paste-history')),
      findsOneWidget,
    );
    expect(find.text(clipboardText), findsOneWidget);

    await tester.tap(find.byKey(const Key('toolbelt-paste-history')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-toolbelt-panel')), findsNothing);
    expect(find.byKey(const Key('paste-history-sheet')), findsOneWidget);
    expect(find.text(clipboardText), findsOneWidget);
  });

  testWidgets('switching panes does not show the return-to-shell cue', (
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

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(find.text('Back in shell'), findsNothing);

    await tester.tap(find.byKey(const Key('shell-pane-1')));
    await tester.pump();

    expect(find.text('Back in shell'), findsNothing);
  });

  testWidgets('clicking another pane updates focus without a legacy cue', (
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

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shell-pane-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shell-pane-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-dim-1')), findsNothing);
    expect(find.byKey(const Key('shell-pane-dim-2')), findsOneWidget);
    expect(find.text('Pane 1 of 2'), findsNothing);
    expect(find.text('Back in shell'), findsNothing);
  });

  testWidgets('command menu keeps pane focus traversal hidden', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shell-pane-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-pane-dim-1')), findsNothing);
    expect(find.byKey(const Key('shell-pane-dim-2')), findsOneWidget);

    await _openCommandMenu(tester);
    expect(find.text('Focus next pane'), findsNothing);
    expect(find.text('Focus previous pane'), findsNothing);
    expect(find.byKey(const Key('shell-pane-dim-1')), findsNothing);
    expect(find.byKey(const Key('shell-pane-dim-2')), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);
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
      expect(
        tester.getSemantics(
          find.byKey(const Key('terminal-autocomplete-suggestion-checkout')),
        ),
        matchesSemantics(
          label: 'checkout',
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );

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

  testWidgets(
    'switching split panes closes autocomplete for the previous pane',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openTabContextMenu(tester);
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      fakeBindings.setFrame(2, {
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

      await tester.tap(find.byKey(const Key('shell-pane-2')));
      await tester.pump();
      await _sendMetaShortcut(tester, LogicalKeyboardKey.semicolon);

      expect(
        find.byKey(const Key('terminal-autocomplete-menu')),
        findsOneWidget,
      );
      expect(find.text('checkout'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shell-pane-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('terminal-autocomplete-menu')), findsNothing);
      expect(find.byKey(const Key('shell-pane-dim-1')), findsNothing);
      expect(find.byKey(const Key('shell-pane-dim-2')), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('redesign features stay hidden from product entry points', (
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
    expect(find.byKey(const Key('shell-auto-composer')), findsNothing);
    expect(find.byKey(const Key('terminal-auto-composer')), findsNothing);
    expect(find.text('Auto Composer'), findsNothing);
    expect(find.text('Password manager'), findsNothing);

    await tester.tap(find.byKey(const Key('shell-top-toolbelt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-toolbelt-panel')), findsOneWidget);
    expect(find.byKey(const Key('toolbelt-password-manager')), findsNothing);
    expect(find.text('Password manager'), findsNothing);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('split panes keep auto composer hidden', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _openTabContextMenu(tester);
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    await _openCommandMenu(tester);
    expect(find.byKey(const Key('shell-auto-composer')), findsNothing);
    expect(find.byKey(const Key('terminal-auto-composer')), findsNothing);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets(
    'shift-command arrows track global prompt marks through new output and caps',
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
        'rows': const <Object?>[],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const <Object?>[],
        'scrollback_offset': 0,
        'scrollback_max_offset': 40,
        'global_bottom_row': 100,
      });
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_command',
          sessionId: '1',
          payload: const <String, Object?>{
            'source': 'osc133',
            'eventType': 'prompt_start',
            'cursorLine': 91,
          },
        ),
      );
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_command',
          sessionId: '1',
          payload: const <String, Object?>{
            'source': 'osc133',
            'eventType': 'prompt_start',
            'cursorLine': 73,
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
        'scrollback_offset': 40,
        'scrollback_max_offset': 40,
        'global_bottom_row': 120,
      });
      await tester.pump(const Duration(milliseconds: 40));

      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.arrowDown);

      expect(fakeBindings.scrollToCalls.last, [1, 29]);

      fakeBindings.setFrame(1, {
        'rows': const <Object?>[],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const <Object?>[],
        'scrollback_offset': 0,
        'scrollback_max_offset': 40,
        'global_bottom_row': 200,
      });
      await tester.pump(const Duration(milliseconds: 40));

      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.arrowUp);

      expect(fakeBindings.scrollToCalls.last, [1, 40]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'global row zero prompt mark jumps in a one-row terminal',
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
        'rows': const <Object?>[],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'viewport_rows': 1,
        'viewport_cols': 1,
        'dirty_ranges': const <Object?>[],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'global_bottom_row': 0,
      });
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_command',
          sessionId: '1',
          payload: const <String, Object?>{
            'source': 'osc133',
            'eventType': 'prompt_start',
            'cursorLine': 0,
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await _sendMetaShiftShortcut(tester, LogicalKeyboardKey.arrowUp);

      expect(fakeBindings.scrollToCalls.last, [1, 0]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell integration utilities synthesize a visible prompt mark from shell context',
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
        'rows': const <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'ianvs terminal ready',
            'style_runs': <Object?>[],
          },
        ],
        'cursor': const {'row': 0, 'col': 4, 'visible': true},
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const <Object?>[
          <String, Object?>{'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'global_bottom_row': 23,
      });
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: '1',
          payload: const <String, Object?>{
            'hook': 'command_finished',
            'command': 'pwd',
            'pwd': '/tmp/project',
            'shell': 'zsh',
            'host': 'host',
            'user': 'dev',
            'exit_code': 0,
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      await _tapToolbeltAction(tester, const Key('toolbelt-prompt-marks'));

      expect(find.text('Prompt Marks'), findsOneWidget);
      expect(find.text('1 mark'), findsOneWidget);
      expect(find.byKey(const Key('shell-prompt-mark-0')), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell integration utilities jump prompt marks using the latest frame',
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
        'rows': const <Object?>[],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const <Object?>[],
        'scrollback_offset': 0,
        'scrollback_max_offset': 40,
        'global_bottom_row': 100,
      });
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
        await _tapToolbeltAction(tester, const Key('toolbelt-prompt-marks'));
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
      fakeBindings.setFrame(1, {
        'rows': const <Object?>[],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': const <Object?>[],
        'scrollback_offset': 0,
        'scrollback_max_offset': 40,
        'global_bottom_row': 120,
      });
      await tester.pump(const Duration(milliseconds: 40));
      await tester.ensureVisible(find.byKey(const Key('shell-prompt-mark-0')));
      await tester.tap(find.byKey(const Key('shell-prompt-mark-0')));
      await tester.pumpAndSettle();

      expect(fakeBindings.scrollToCalls.last, [1, 32]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('command menu keeps command selection hidden', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _openCommandMenu(tester);
    expect(find.byKey(const Key('shell-select-command-output')), findsNothing);
    expect(find.text('Select command output'), findsNothing);
    expect(fakeBindings.writes, isEmpty);
  });

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
      await _tapToolbeltAction(tester, const Key('toolbelt-tmux-integration'));
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
    final tmuxField = tester.widget<TextField>(
      find.byKey(const Key('tmux-command-field')),
    );
    expect(tmuxField.decoration?.fillColor, isNull);
    expect(tmuxField.decoration?.filled, isNull);
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
      await _tapToolbeltAction(tester, const Key('toolbelt-coprocess'));
    }

    await openCoprocess();

    expect(find.byKey(const Key('coprocess-sheet')), findsOneWidget);
    expect(find.text('Run Coprocess'), findsOneWidget);
    final coprocessField = tester.widget<TextField>(
      find.byKey(const Key('coprocess-command-field')),
    );
    expect(coprocessField.decoration?.fillColor, isNull);
    expect(coprocessField.decoration?.filled, isNull);

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

  testWidgets('coprocess replies to repeated delta output', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _tapToolbeltAction(tester, const Key('toolbelt-coprocess'));

    await tester.enterText(
      find.byKey(const Key('coprocess-command-field')),
      'presence bot',
    );
    await tester.tap(find.byKey(const Key('coprocess-start')));
    await tester.pumpAndSettle();

    Map<String, Object?> promptDeltaFrame() {
      return {
        'frame_kind': 'delta',
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
      };
    }

    fakeBindings.enqueueFrame(1, promptDeltaFrame());
    await tester.pump(const Duration(milliseconds: 40));
    fakeBindings.enqueueFrame(1, promptDeltaFrame());
    await tester.pump(const Duration(milliseconds: 40));

    expect(fakeBindings.writes.map(utf8.decode).toList(), ['Yes\n', 'Yes\n']);
  });

  testWidgets('coprocess replies to wrapped logical output', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _tapToolbeltAction(tester, const Key('toolbelt-coprocess'));

    await tester.enterText(
      find.byKey(const Key('coprocess-command-field')),
      'presence bot',
    );
    await tester.tap(find.byKey(const Key('coprocess-start')));
    await tester.pumpAndSettle();

    fakeBindings.setFrame(1, {
      'rows': [
        {
          'index': 0,
          'text': 'Are you ',
          'wrapped': true,
          'style_runs': const [],
        },
        {'index': 1, 'text': 'there?', 'style_runs': const []},
      ],
      'cursor': {'row': 1, 'col': 6, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 16,
      'dirty_ranges': [
        {'start': 0, 'end': 2},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    await tester.pump(const Duration(milliseconds: 40));

    expect(fakeBindings.writes.last, utf8.encode('Yes\n'));
  });

  testWidgets('command menu keeps dynamic profiles hidden', (tester) async {
    final fakeBindings = FakePtyBackend();

    await _pumpShellScreen(
      tester,
      bindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _openCommandMenu(tester);
    expect(find.byKey(const Key('shell-dynamic-profiles')), findsNothing);
    expect(find.text('Dynamic profiles'), findsNothing);
    expect(find.byKey(const Key('dynamic-profiles-sheet')), findsNothing);
    expect(fakeBindings.writes, isEmpty);
  });

  testWidgets('command menu keeps hotkey window hidden', (tester) async {
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
    expect(find.text('Hotkey window'), findsNothing);
    expect(find.textContaining('Hide this window. Reopen with'), findsNothing);
    expect(
      windowBridgeCalls.map((call) => call.method),
      isNot(contains(anyOf('hotkeyStatus', 'toggleHotkeyWindow'))),
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
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Defaults & appearance dialog'),
        findsOneWidget,
      );
      semantics.dispose();
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

  testWidgets('native Settings menu opens defaults', (tester) async {
    await _pumpShellScreen(
      tester,
      bindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _invokeNativeWindowBridge(
      tester,
      const MethodCall('nativeAppAction', <String, Object?>{
        'action': 'settings',
      }),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('Defaults & appearance dialog'),
      findsOneWidget,
    );
    semantics.dispose();
  });

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

    await _hoverShellTab(tester, '1');
    await tester.tap(find.byTooltip('Close Local Shell'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);
    expect(find.text('Shell layout is idle'), findsOneWidget);
    expect(
      find.text(
        'The last session has closed. Open a new tab to keep working in the shell layout.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('New Tab'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.text('Back in shell'), findsOneWidget);
  });

  testWidgets('closing the last tab can recover via Reopen closed tab', (
    tester,
  ) async {
    await _pumpShellScreen(
      tester,
      bindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await _hoverShellTab(tester, '1');
    await tester.tap(find.byTooltip('Close Local Shell'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);

    await _openCommandMenu(tester);
    await tester.tap(find.byKey(const Key('shell-reopen-closed-tab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-empty-state')), findsNothing);
    expect(find.byType(TerminalViewport), findsOneWidget);
    expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
    expect(find.byKey(const Key('shell-status-bar')), findsNothing);
  });

  testWidgets('terminal exit returns the shell to the empty state', (
    tester,
  ) async {
    final eventfulBindings = _EventfulPtyBackend();
    final instantReplayStore = InstantReplayStore();

    await _pumpShellScreen(
      tester,
      bindings: eventfulBindings,
      instantReplayStore: instantReplayStore,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.byType(TerminalViewport), findsOneWidget);

    eventfulBindings.setFrame(1, {
      'rows': [
        {'index': 0, 'text': 'replay before exit', 'style_runs': const []},
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
    expect(instantReplayStore.framesFor('1'), isNotEmpty);

    eventfulBindings.enqueueExit('1');
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();

    expect(instantReplayStore.framesFor('1'), isEmpty);
    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.byType(TerminalViewport), findsNothing);
    expect(find.text('Shell layout is idle'), findsOneWidget);
    expect(
      find.text(
        'The last session has closed. Open a new tab to keep working in the shell layout.',
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
        {'index': 0, 'text': 'ianvs terminal ready', 'style_runs': const []},
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
    'shell search opens and scrolls to matches',
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

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();

      expect(find.text('2/2'), findsOneWidget);
      expect(fakeBindings.searchCalls.last, [
        1,
        'needle',
        'smart_case_substring',
      ]);
      expect(fakeBindings.scrollToCalls.last, [1, 3]);
      expect(
        tester.getSize(find.byKey(const Key('terminal-search-close'))),
        const Size(26, 30),
      );
      final inputRect = tester.getRect(
        find.byKey(const Key('terminal-search-input')),
      );
      final clearRect = tester.getRect(
        find.byKey(const Key('terminal-search-clear')),
      );
      expect(inputRect.width, greaterThanOrEqualTo(300));
      expect(clearRect.left, greaterThanOrEqualTo(inputRect.left));
      expect(clearRect.right, lessThanOrEqualTo(inputRect.right));
      expect(
        find.descendant(
          of: find.byKey(const Key('terminal-search-input')),
          matching: find.byIcon(Icons.close_rounded),
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
      expect(find.byKey(const Key('terminal-search-close')), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('terminal-search-field')),
      );
      expect(field.decoration?.isCollapsed, isTrue);
      expect(field.decoration?.filled, isFalse);
      expect(field.decoration?.fillColor, Colors.transparent);
      expect(field.decoration?.contentPadding, EdgeInsets.zero);
      expect(field.decoration?.hintText, 'Search');
      expect(field.decoration?.border, InputBorder.none);
      expect(field.decoration?.enabledBorder, InputBorder.none);
      expect(field.decoration?.focusedBorder, InputBorder.none);
      expect(find.textContaining('Type to search'), findsNothing);

      await tester.tap(find.byKey(const Key('terminal-search-next')));
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget);
      expect(fakeBindings.scrollToCalls.last, [1, 42]);

      await tester.tap(find.byKey(const Key('terminal-search-close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('terminal-search-bar')), findsNothing);
      expect(fakeBindings.scrollToCalls.last, [1, 42]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search closes on Escape without terminal input',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('terminal-search-bar')), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.escape,
        platform: 'macos',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape, platform: 'macos');
      await tester.pump();

      expect(find.byKey(const Key('terminal-search-bar')), findsNothing);
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search keeps vertical padding balanced',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openShellSearch(tester);

      final barRect = tester.getRect(
        find.byKey(const Key('terminal-search-bar')),
      );
      final inputRect = tester.getRect(
        find.byKey(const Key('terminal-search-input')),
      );
      final fieldRect = tester.getRect(
        find.byKey(const Key('terminal-search-field')),
      );
      final modeRect = tester.getRect(
        find.byKey(const Key('terminal-search-mode')),
      );

      expect(barRect.height, 38);
      expect(modeRect.size, const Size(32, 30));
      expect(inputRect.height, 30);
      expect(fieldRect.height, 20);
      expect(inputRect.top - barRect.top, moreOrLessEquals(4));
      expect(barRect.bottom - inputRect.bottom, moreOrLessEquals(4));
      expect(fieldRect.center.dy, moreOrLessEquals(inputRect.center.dy));

      await tester.tap(find.byKey(const Key('terminal-search-mode')));
      await tester.pumpAndSettle();

      expect(find.text('Filter'), findsOneWidget);
      expect(
        find.byKey(const Key('terminal-search-mode-smart_case_substring')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const Key('terminal-search-mode-smart_case_substring'),
          ),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search compacts inside a narrow terminal pane',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 420);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'missing',
      );
      await tester.pumpAndSettle();

      final barRect = tester.getRect(
        find.byKey(const Key('terminal-search-bar')),
      );
      final fieldRect = tester.getRect(
        find.byKey(const Key('terminal-search-field')),
      );
      final statusRect = tester.getRect(
        find.byKey(const Key('terminal-search-status')),
      );

      expect(barRect.left, greaterThanOrEqualTo(12));
      expect(barRect.right, lessThanOrEqualTo(346));
      expect(barRect.height, 38);
      expect(fieldRect.width, greaterThan(100));
      expect(statusRect.left, greaterThanOrEqualTo(barRect.left));
      expect(statusRect.right, lessThanOrEqualTo(barRect.right));
      expect(find.text('No matches'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'cmd-f opens shell search without writing to terminal',
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
      await _sendMetaShortcut(tester, LogicalKeyboardKey.keyF);

      expect(find.byKey(const Key('terminal-search-bar')), findsOneWidget);
      expect(find.byKey(const Key('terminal-search-field')), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);

      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, isEmpty);
      expect(fakeBindings.searchCalls.last, [
        1,
        'needle',
        'smart_case_substring',
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search opening and clearing keeps input focused',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openShellSearch(tester);

      var field = tester.widget<TextField>(
        find.byKey(const Key('terminal-search-field')),
      );
      expect(field.focusNode?.hasFocus, isTrue);

      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();

      field = tester.widget<TextField>(
        find.byKey(const Key('terminal-search-field')),
      );
      expect(field.focusNode?.hasFocus, isTrue);

      await tester.tap(find.byKey(const Key('terminal-search-clear')));
      await tester.pumpAndSettle();

      field = tester.widget<TextField>(
        find.byKey(const Key('terminal-search-field')),
      );
      expect(field.controller?.text, isEmpty);
      expect(field.focusNode?.hasFocus, isTrue);
      expect(
        field.controller?.selection,
        const TextSelection.collapsed(offset: 0),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search mode and navigation do not force input focus',
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
        {
          'row': 2,
          'start_col': 0,
          'end_col': 6,
          'text': 'needle',
          'scrollback_offset': 2,
        },
        {
          'row': 3,
          'start_col': 0,
          'end_col': 6,
          'text': 'needle',
          'scrollback_offset': 3,
        },
      ]);

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();

      final focusNode = tester
          .widget<TextField>(find.byKey(const Key('terminal-search-field')))
          .focusNode!;
      focusNode.unfocus();
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);

      await tester.tap(find.byKey(const Key('terminal-search-next')));
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isFalse);

      await _selectSearchMode(tester, 'case_sensitive_substring');
      expect(focusNode.hasFocus, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search scope searches current tab panes and jumps between panes',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _tapTabContextMenuAction(tester, 'Split right');

      fakeBindings.setSearchMatches(1, 'needle', [
        {
          'row': 3,
          'start_col': 0,
          'end_col': 6,
          'text': 'left pane needle',
          'scrollback_offset': 3,
        },
      ]);
      fakeBindings.setSearchMatches(2, 'needle', [
        {
          'row': 7,
          'start_col': 2,
          'end_col': 8,
          'text': 'right pane needle',
          'scrollback_offset': 7,
        },
      ]);

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();

      expect(find.text('Pane'), findsOneWidget);
      expect(fakeBindings.searchCalls.last, [
        2,
        'needle',
        'smart_case_substring',
      ]);
      expect(find.text('1/1'), findsOneWidget);

      await _selectSearchScope(tester, 'current_tab');

      expect(find.text('Tab'), findsOneWidget);
      expect(
        fakeBindings.searchCalls,
        contains(equals([1, 'needle', 'smart_case_substring'])),
      );
      expect(
        fakeBindings.searchCalls,
        contains(equals([2, 'needle', 'smart_case_substring'])),
      );
      expect(find.text('2/2'), findsOneWidget);
      expect(fakeBindings.scrollToCalls.last, [2, 7]);

      final viewportMatches = tester
          .widgetList<TerminalViewport>(find.byType(TerminalViewport))
          .map((viewport) => viewport.searchMatches.length)
          .toList();
      expect(viewportMatches, containsAll(<int>[1, 1]));

      await tester.tap(find.byKey(const Key('terminal-search-next')));
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget);
      expect(fakeBindings.scrollToCalls.last, [1, 3]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search overlay stays inside active split pane',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _tapTabContextMenuAction(tester, 'Split right');
      final activePaneRect = tester.getRect(
        find.byKey(const Key('shell-pane-2')),
      );

      await _openShellSearch(tester);
      final searchRect = tester.getRect(
        find.byKey(const Key('terminal-search-bar')),
      );

      expect(searchRect.left, greaterThanOrEqualTo(activePaneRect.left));
      expect(searchRect.right, lessThanOrEqualTo(activePaneRect.right));
      expect(searchRect.top, greaterThanOrEqualTo(activePaneRect.top));
      expect(searchRect.bottom, lessThanOrEqualTo(activePaneRect.bottom));
      expect(fakeBindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search jump clears inactive pane new output marker',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _tapTabContextMenuAction(tester, 'Split right');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final tab = container.read(sessionControllerProvider).tabs.single;
      final activeSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      final inactiveSessionId = tab.effectivePanes
          .firstWhere((pane) => pane.sessionId != activeSessionId)
          .sessionId;

      Map<String, Object?> frame(String text) {
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

      fakeBindings.setFrame(inactiveSessionId, frame('first background line'));
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump(const Duration(milliseconds: 40));
      fakeBindings.setFrame(inactiveSessionId, frame('needle background line'));
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        find.byKey(Key('shell-tab-new-output-${tab.sessionId}')),
        findsOneWidget,
      );

      fakeBindings.setSearchMatches(activeSessionId, 'needle', [
        <String, Object?>{
          'row': 2,
          'start_col': 0,
          'end_col': 6,
          'text': 'active pane needle',
          'scrollback_offset': 2,
        },
      ]);
      fakeBindings.setSearchMatches(inactiveSessionId, 'needle', [
        <String, Object?>{
          'row': 7,
          'start_col': 0,
          'end_col': 6,
          'text': 'inactive pane needle',
          'scrollback_offset': 7,
        },
      ]);

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();
      await _selectSearchScope(tester, 'current_tab');
      await tester.tap(find.byKey(const Key('terminal-search-next')));
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        inactiveSessionId,
      );
      expect(fakeBindings.scrollToCalls.last, [
        int.parse(inactiveSessionId),
        7,
      ]);
      expect(
        find.byKey(Key('shell-tab-new-output-${tab.sessionId}')),
        findsNothing,
      );
      final searchField = tester.widget<TextField>(
        find.byKey(const Key('terminal-search-field')),
      );
      expect(searchField.focusNode?.hasFocus, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search drops closed split pane matches',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _tapTabContextMenuAction(tester, 'Split right');

      fakeBindings.setSearchMatches(1, 'needle', [
        {
          'row': 3,
          'start_col': 0,
          'end_col': 6,
          'text': 'left pane needle',
          'scrollback_offset': 3,
        },
      ]);
      fakeBindings.setSearchMatches(2, 'needle', [
        {
          'row': 7,
          'start_col': 2,
          'end_col': 8,
          'text': 'right pane needle',
          'scrollback_offset': 7,
        },
      ]);

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();
      await _selectSearchScope(tester, 'current_tab');

      expect(find.text('2/2'), findsOneWidget);
      expect(fakeBindings.scrollToCalls.last, [2, 7]);

      await tester.tap(find.byKey(const Key('shell-pane-action-close-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-pane-1')), findsOneWidget);
      expect(find.byKey(const Key('shell-pane-2')), findsNothing);
      expect(find.text('1/1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('terminal-search-next')));
      await tester.pumpAndSettle();

      expect(fakeBindings.scrollToCalls.last, [1, 3]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search pane scope refreshes after activating another pane',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _tapTabContextMenuAction(tester, 'Split right');

      fakeBindings.setSearchMatches(1, 'needle', [
        {
          'row': 3,
          'start_col': 0,
          'end_col': 6,
          'text': 'left pane first needle',
          'scrollback_offset': 3,
        },
        {
          'row': 6,
          'start_col': 1,
          'end_col': 7,
          'text': 'left pane second needle',
          'scrollback_offset': 6,
        },
      ]);
      fakeBindings.setSearchMatches(2, 'needle', [
        {
          'row': 9,
          'start_col': 4,
          'end_col': 10,
          'text': 'right pane needle',
          'scrollback_offset': 9,
        },
      ]);

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();

      expect(find.text('Pane'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      expect(fakeBindings.searchCalls.last, [
        2,
        'needle',
        'smart_case_substring',
      ]);

      await tester.tap(find.byKey(const Key('shell-pane-1')));
      await tester.pumpAndSettle();

      expect(fakeBindings.searchCalls.last, [
        1,
        'needle',
        'smart_case_substring',
      ]);
      expect(
        find.descendant(
          of: find.byKey(const Key('terminal-search-status')),
          matching: find.text('1/2'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('terminal-search-next')));
      await tester.pumpAndSettle();

      expect(fakeBindings.scrollToCalls.last[0], 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search scope searches all tabs and jumps across tabs',
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
      await tester.tap(find.byKey(const Key('shell-top-new-tab')));
      await tester.pumpAndSettle();

      fakeBindings.setSearchMatches(1, 'needle', [
        {
          'row': 5,
          'start_col': 0,
          'end_col': 6,
          'text': 'first tab needle',
          'scrollback_offset': 5,
        },
      ]);
      fakeBindings.setSearchMatches(2, 'needle', [
        {
          'row': 9,
          'start_col': 4,
          'end_col': 10,
          'text': 'second tab needle',
          'scrollback_offset': 9,
        },
      ]);

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();

      expect(find.text('Pane'), findsOneWidget);
      expect(fakeBindings.searchCalls.last, [
        2,
        'needle',
        'smart_case_substring',
      ]);
      expect(find.text('1/1'), findsOneWidget);

      await _selectSearchScope(tester, 'all_tabs');

      expect(find.text('All'), findsOneWidget);
      expect(
        fakeBindings.searchCalls,
        contains(equals([1, 'needle', 'smart_case_substring'])),
      );
      expect(
        fakeBindings.searchCalls,
        contains(equals([2, 'needle', 'smart_case_substring'])),
      );
      expect(find.text('2/2'), findsOneWidget);
      expect(fakeBindings.scrollToCalls.last, [2, 9]);

      await tester.tap(find.byKey(const Key('terminal-search-next')));
      await tester.pumpAndSettle();

      _expectSelectedTab(tester, '1');
      expect(find.text('1/2'), findsOneWidget);
      expect(fakeBindings.scrollToCalls.last, [1, 5]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search highlights visible matches',
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
          {'index': 0, 'text': 'alpha', 'style_runs': const []},
          {'index': 1, 'text': '  ERR one', 'style_runs': const []},
          {'index': 2, 'text': 'middle', 'style_runs': const []},
          {'index': 3, 'text': 'xxERR two', 'style_runs': const []},
          {'index': 4, 'text': 'omega', 'style_runs': const []},
        ],
        'cursor': {'row': 4, 'col': 5, 'visible': true},
        'selection': null,
        'viewport_rows': 5,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 5},
        ],
        'viewport_start_row': 10,
        'scrollback_offset': 0,
        'scrollback_max_offset': 20,
      });
      fakeBindings.setSearchMatches(1, 'ERR', [
        {
          'row': 11,
          'start_col': 2,
          'end_col': 5,
          'text': 'ERR',
          'scrollback_offset': 9,
        },
        {
          'row': 13,
          'start_col': 2,
          'end_col': 5,
          'text': 'ERR',
          'scrollback_offset': 7,
        },
        {
          'row': 20,
          'start_col': 0,
          'end_col': 3,
          'text': 'ERR',
          'scrollback_offset': 0,
        },
      ]);
      await tester.pump(const Duration(milliseconds: 40));

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'ERR',
      );
      await tester.pumpAndSettle();

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      final rects = renderObject.debugSearchHighlightRects;

      expect(rects, hasLength(2));
      _expectRectClose(
        rects[0],
        Rect.fromLTWH(
          cellSize.width * 2,
          cellSize.height,
          cellSize.width * 3,
          cellSize.height,
        ),
      );
      _expectRectClose(
        rects[1],
        Rect.fromLTWH(
          cellSize.width * 2,
          cellSize.height * 3,
          cellSize.width * 3,
          cellSize.height,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search recomputes selected highlight geometry after resize',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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
          {'index': 0, 'text': 'alpha', 'style_runs': const []},
          {'index': 1, 'text': '  ERR one', 'style_runs': const []},
          {'index': 2, 'text': 'middle', 'style_runs': const []},
          {'index': 3, 'text': 'xxxxxxERR two', 'style_runs': const []},
          {'index': 4, 'text': 'omega', 'style_runs': const []},
        ],
        'cursor': {'row': 4, 'col': 5, 'visible': true},
        'selection': null,
        'viewport_rows': 5,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 5},
        ],
        'viewport_start_row': 10,
        'scrollback_offset': 0,
        'scrollback_max_offset': 20,
      });
      fakeBindings.setSearchMatches(1, 'ERR', [
        {
          'row': 11,
          'start_col': 2,
          'end_col': 5,
          'text': 'ERR',
          'scrollback_offset': 9,
        },
        {
          'row': 13,
          'start_col': 6,
          'end_col': 9,
          'text': 'ERR',
          'scrollback_offset': 7,
        },
      ]);
      await tester.pump(const Duration(milliseconds: 40));

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'ERR',
      );
      await tester.pumpAndSettle();

      expect(find.text('2/2'), findsOneWidget);
      expect(
        tester
            .widget<TerminalViewport>(find.byType(TerminalViewport))
            .activeSearchMatchIndex,
        1,
      );
      final searchCallCountBeforeResize = fakeBindings.searchCalls.length;

      fakeBindings.setSearchMatches(1, 'ERR', [
        {
          'row': 10,
          'start_col': 1,
          'end_col': 4,
          'text': 'ERR',
          'scrollback_offset': 9,
        },
        {
          'row': 12,
          'start_col': 9,
          'end_col': 12,
          'text': 'ERR',
          'scrollback_offset': 7,
        },
      ]);
      tester.view.physicalSize = const Size(980, 900);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();

      expect(
        fakeBindings.searchCalls.length,
        greaterThanOrEqualTo(searchCallCountBeforeResize + 1),
      );
      expect(fakeBindings.searchCalls.last, [1, 'ERR', 'smart_case_substring']);
      expect(find.text('2/2'), findsOneWidget);
      expect(
        tester
            .widget<TerminalViewport>(find.byType(TerminalViewport))
            .activeSearchMatchIndex,
        1,
      );

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      final rects = renderObject.debugSearchHighlightRects;

      expect(rects, hasLength(2));
      _expectRectClose(
        rects[0],
        Rect.fromLTWH(
          1 * cellSize.width,
          0,
          3 * cellSize.width,
          cellSize.height,
        ),
      );
      _expectRectClose(
        rects[1],
        Rect.fromLTWH(
          9 * cellSize.width,
          2 * cellSize.height,
          3 * cellSize.width,
          cellSize.height,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search recomputes selected highlight geometry after output updates',
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
          {'index': 0, 'text': 'alpha', 'style_runs': const []},
          {'index': 1, 'text': '  ERR one', 'style_runs': const []},
          {'index': 2, 'text': 'middle', 'style_runs': const []},
          {'index': 3, 'text': 'xxxxxxERR two', 'style_runs': const []},
          {'index': 4, 'text': 'omega', 'style_runs': const []},
        ],
        'cursor': {'row': 4, 'col': 5, 'visible': true},
        'selection': null,
        'viewport_rows': 5,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 5},
        ],
        'viewport_start_row': 10,
        'scrollback_offset': 0,
        'scrollback_max_offset': 20,
      });
      fakeBindings.setSearchMatches(1, 'ERR', [
        {
          'row': 11,
          'start_col': 2,
          'end_col': 5,
          'text': 'ERR',
          'scrollback_offset': 9,
        },
        {
          'row': 13,
          'start_col': 6,
          'end_col': 9,
          'text': 'ERR',
          'scrollback_offset': 7,
        },
      ]);
      await tester.pump(const Duration(milliseconds: 40));

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'ERR',
      );
      await tester.pumpAndSettle();

      expect(find.text('2/2'), findsOneWidget);
      expect(
        tester
            .widget<TerminalViewport>(find.byType(TerminalViewport))
            .activeSearchMatchIndex,
        1,
      );
      final searchCallCountBeforeOutput = fakeBindings.searchCalls.length;

      fakeBindings.setFrame(1, {
        'rows': [
          {'index': 0, 'text': 'alpha', 'style_runs': const []},
          {'index': 1, 'text': '  ERR one', 'style_runs': const []},
          {
            'index': 2,
            'text': 'output shifted ERR two',
            'style_runs': const [],
          },
          {'index': 3, 'text': 'middle', 'style_runs': const []},
          {'index': 4, 'text': 'omega', 'style_runs': const []},
        ],
        'cursor': {'row': 4, 'col': 5, 'visible': true},
        'selection': null,
        'viewport_rows': 5,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 5},
        ],
        'viewport_start_row': 10,
        'scrollback_offset': 0,
        'scrollback_max_offset': 21,
      });
      fakeBindings.setSearchMatches(1, 'ERR', [
        {
          'row': 11,
          'start_col': 2,
          'end_col': 5,
          'text': 'ERR',
          'scrollback_offset': 9,
        },
        {
          'row': 12,
          'start_col': 15,
          'end_col': 18,
          'text': 'ERR',
          'scrollback_offset': 7,
        },
      ]);
      await tester.pump(const Duration(milliseconds: 80));

      expect(fakeBindings.searchCalls.length, searchCallCountBeforeOutput + 1);
      expect(fakeBindings.searchCalls.last, [1, 'ERR', 'smart_case_substring']);
      expect(find.text('2/2'), findsOneWidget);
      expect(
        tester
            .widget<TerminalViewport>(find.byType(TerminalViewport))
            .activeSearchMatchIndex,
        1,
      );

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      final rects = renderObject.debugSearchHighlightRects;

      expect(rects, hasLength(2));
      _expectRectClose(
        rects[0],
        Rect.fromLTWH(
          2 * cellSize.width,
          1 * cellSize.height,
          3 * cellSize.width,
          cellSize.height,
        ),
      );
      _expectRectClose(
        rects[1],
        Rect.fromLTWH(
          15 * cellSize.width,
          2 * cellSize.height,
          3 * cellSize.width,
          cellSize.height,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search regex mode matches visible terminal output',
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
          {'index': 0, 'text': 'alpha', 'style_runs': const []},
          {'index': 1, 'text': 'ERR 100 one', 'style_runs': const []},
          {'index': 2, 'text': 'WARN two', 'style_runs': const []},
          {'index': 3, 'text': 'ERR 200 three', 'style_runs': const []},
        ],
        'cursor': {'row': 3, 'col': 13, 'visible': true},
        'selection': null,
        'viewport_rows': 4,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 4},
        ],
        'viewport_start_row': 10,
        'scrollback_offset': 0,
        'scrollback_max_offset': 20,
      });
      fakeBindings.setSearchMatches(1, r'ERR \d+', [
        {
          'row': 11,
          'start_col': 0,
          'end_col': 7,
          'text': 'ERR 100',
          'scrollback_offset': 9,
        },
        {
          'row': 13,
          'start_col': 0,
          'end_col': 7,
          'text': 'ERR 200',
          'scrollback_offset': 7,
        },
      ], mode: 'case_sensitive_regex');
      await tester.pump(const Duration(milliseconds: 40));

      await _openShellSearch(tester);
      await _selectSearchMode(tester, 'case_sensitive_regex');
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        r'ERR \d+',
      );
      await tester.pumpAndSettle();

      expect(fakeBindings.searchCalls.last, [
        1,
        r'ERR \d+',
        'case_sensitive_regex',
      ]);
      expect(find.text('2/2'), findsOneWidget);
      expect(fakeBindings.scrollToCalls.last, [1, 7]);

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      final rects = renderObject.debugSearchHighlightRects;

      expect(rects, hasLength(2));
      _expectRectClose(
        rects[0],
        Rect.fromLTWH(0, cellSize.height, cellSize.width * 7, cellSize.height),
      );
      _expectRectClose(
        rects[1],
        Rect.fromLTWH(
          0,
          cellSize.height * 3,
          cellSize.width * 7,
          cellSize.height,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell search regex mode keeps text editable and reports errors',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await _openShellSearch(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'ERR',
      );
      await tester.pumpAndSettle();
      await _selectSearchMode(tester, 'case_sensitive_regex');

      final field = tester.widget<TextField>(
        find.byKey(const Key('terminal-search-field')),
      );
      expect(field.controller?.text, 'ERR');

      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        r'ERR \d+(',
      );
      await tester.pumpAndSettle();

      expect(find.text('Invalid regular expression'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
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

    expect(find.text('Searching across 2 sessions'), findsOneWidget);
    expect(find.textContaining('Type to search'), findsNothing);
    expect(find.byTooltip('Close global search'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('terminal-global-search-close'))),
      const Size.square(28),
    );

    await tester.enterText(
      find.byKey(const Key('terminal-global-search-field')),
      'needle',
    );
    await tester.pump();

    expect(
      fakeBindings.searchCalls,
      contains(equals([1, 'needle', 'smart_case_substring'])),
    );
    expect(
      fakeBindings.searchCalls,
      contains(equals([2, 'needle', 'smart_case_substring'])),
    );
    expect(find.text('first tab needle'), findsOneWidget);
    expect(find.text('second tab needle'), findsOneWidget);
    final globalSearchResultTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('terminal-global-search-result-2-1')),
        matching: find.byType(ListTile),
      ),
    );
    expect(globalSearchResultTile.contentPadding, EdgeInsets.zero);
    final globalSearchDivider = tester.widget<Divider>(
      find
          .descendant(
            of: find.byKey(const Key('terminal-global-search-sheet')),
            matching: find.byType(Divider),
          )
          .first,
    );
    expect(globalSearchDivider.color, isNull);

    await tester.tap(
      find.byKey(const Key('terminal-global-search-result-2-1')),
    );
    await tester.pumpAndSettle();

    _expectSelectedTab(tester, '2');
    expect(fakeBindings.scrollToCalls.last, [2, 13]);
  });
}
