import 'dart:async';
import 'dart:convert';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/shell/window_bridge.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

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
  ShellFileDownloadWriter? fileDownloadWriter,
  ShellExternalUrlOpener? externalUrlOpener,
  ShellUserAttentionBridge? userAttentionBridge,
  bool? shellAnimationsEnabled,
  ShellClock? clock,
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
        if (fileDownloadWriter != null)
          shellFileDownloadWriterProvider.overrideWithValue(fileDownloadWriter),
        if (externalUrlOpener != null)
          shellExternalUrlOpenerProvider.overrideWithValue(externalUrlOpener),
        if (userAttentionBridge != null)
          shellUserAttentionBridgeProvider.overrideWithValue(
            userAttentionBridge,
          ),
        if (shellAnimationsEnabled != null)
          shellAnimationsEnabledProvider.overrideWithValue(
            shellAnimationsEnabled,
          ),
        if (clock != null) shellClockProvider.overrideWithValue(clock),
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

final class _RecordingUserAttentionBridge implements ShellUserAttentionBridge {
  final List<NativeUserAttentionType> requests = <NativeUserAttentionType>[];
  final List<int> cancellations = <int>[];
  int _nextRequestId = 100;

  @override
  Future<int?> request(NativeUserAttentionType type) async {
    requests.add(type);
    return _nextRequestId++;
  }

  @override
  Future<void> cancel(int requestId) async {
    cancellations.add(requestId);
  }
}

final class _PendingUserAttentionBridge implements ShellUserAttentionBridge {
  final List<NativeUserAttentionType> requests = <NativeUserAttentionType>[];
  final List<Completer<int?>> pendingRequests = <Completer<int?>>[];

  @override
  Future<int?> request(NativeUserAttentionType type) {
    requests.add(type);
    final completer = Completer<int?>();
    pendingRequests.add(completer);
    return completer.future;
  }

  @override
  Future<void> cancel(int requestId) async {}
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

Future<void> _chooseDefaultLocalSession(WidgetTester tester) async {
  expect(find.byKey(const Key('new-session-launcher')), findsOneWidget);
  await tester.tap(find.byKey(const Key('new-local-session-default')));
  await tester.pumpAndSettle();
}

Future<void> _invokeNativeWindowBridge(
  WidgetTester tester,
  MethodCall call,
) async {
  await _dispatchNativeWindowBridge(tester, call);
  await tester.pumpAndSettle();
}

Future<void> _dispatchNativeWindowBridge(WidgetTester tester, MethodCall call) {
  const codec = StandardMethodCodec();
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'app/window_bridge',
    codec.encodeMethodCall(call),
    (_) {},
  );
}

void main() {
  setUp(() {
    WindowBridge.debugZmodemFileDialogPlatformOverride = TargetPlatform.macOS;
    addTearDown(
      () => WindowBridge.debugZmodemFileDialogPlatformOverride = null,
    );
  });

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

  testWidgets('defaults dialog enables layout restore with clear process copy', (
    tester,
  ) async {
    final localConfigRepository = _MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        layout: LocalTerminalLayoutConfig(restoreLayout: false),
      ),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      localConfigRepository: localConfigRepository,
    );

    await _openCommandMenu(tester);
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();
    final restoreToggle = find.byKey(const Key('default-restore-layout'));
    await tester.ensureVisible(restoreToggle);

    expect(find.text('Restore tabs and panes on launch'), findsOneWidget);
    expect(
      find.text(
        'Starts new shell processes and restores their folders. Running processes are not resumed.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<SwitchListTile>(restoreToggle).value, isFalse);

    await tester.tap(restoreToggle);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(restoreToggle).value, isTrue);
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(
      localConfigRepository.savedDocuments.last.layout.restoreLayout,
      isTrue,
    );
  });

  testWidgets('defaults dialog saves OSC 1337 OpenURL deny policy', (
    tester,
  ) async {
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
    final deny = find.byKey(
      const Key('default-osc1337-open-url-policy-disabled'),
    );
    await tester.ensureVisible(deny);
    await tester.tap(deny);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(
      localConfigRepository.savedDocuments.last.hostActions.osc1337OpenUrl,
      LocalTerminalOpenUrlPolicy.disabled,
    );
  });

  testWidgets('defaults dialog explicitly enables OSC 1337 attention', (
    tester,
  ) async {
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
    final allow = find.byKey(
      const Key('default-osc1337-request-attention-policy-allow'),
    );
    await tester.ensureVisible(allow);
    await tester.tap(allow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(
      localConfigRepository
          .savedDocuments
          .last
          .hostActions
          .osc1337RequestAttention,
      LocalTerminalRequestAttentionPolicy.allow,
    );
  });

  testWidgets('defaults dialog forgets OSC 1337 variable decisions on save', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final localConfigRepository = _MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        hostActions: LocalTerminalHostActionsConfig(
          osc1337ReportVariables: <String, LocalTerminalReportVariablePolicy>{
            'session.path': LocalTerminalReportVariablePolicy.allow,
            'user.gitBranch': LocalTerminalReportVariablePolicy.deny,
          },
        ),
      ),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: localConfigRepository,
    );
    await _openCommandMenu(tester);
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();
    final forget = find.byKey(
      const Key('default-osc1337-report-variable-forget-all'),
    );
    await tester.ensureVisible(forget);
    expect(find.text('2 remembered · 1 allowed · 1 denied'), findsOneWidget);
    expect(find.text('session.path'), findsOneWidget);
    expect(find.text('user.gitBranch'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'default-osc1337-report-variable-policy-session.path',
        ),
      ),
      findsOneWidget,
    );
    final forgetUser = find.byKey(
      const ValueKey<String>(
        'default-osc1337-report-variable-forget-user.gitBranch',
      ),
    );
    await tester.tap(forgetUser);
    await tester.pump();
    expect(find.text('1 remembered · 1 allowed · 0 denied'), findsOneWidget);
    expect(find.text('user.gitBranch'), findsNothing);
    await tester.tap(forget);
    await tester.pumpAndSettle();
    expect(find.text('No remembered decisions'), findsOneWidget);
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(
      localConfigRepository
          .savedDocuments
          .last
          .hostActions
          .osc1337ReportVariables,
      isEmpty,
    );
  });

  testWidgets('OSC 1337 attention defaults to deny without host effects', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final attention = _RecordingUserAttentionBridge();
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      userAttentionBridge: attention,
    );
    for (final action in <String>['yes', 'once', 'fireworks']) {
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'attention_request',
          sessionId: '1',
          payload: <String, Object?>{'source': 'iterm1337', 'action': action},
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 40));

    expect(attention.requests, isEmpty);
    expect(attention.cancellations, isEmpty);
    expect(find.byKey(const Key('osc1337-fireworks-1')), findsNothing);
  });

  testWidgets('OSC 1337 once yes and no map to owned AppKit requests', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final attention = _RecordingUserAttentionBridge();
    var now = DateTime.utc(2026, 7, 13, 12);
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          hostActions: LocalTerminalHostActionsConfig(
            osc1337RequestAttention: LocalTerminalRequestAttentionPolicy.allow,
          ),
        ),
      ),
      userAttentionBridge: attention,
      clock: () => now,
    );

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'attention_request',
        sessionId: '1',
        payload: <String, Object?>{'source': 'iterm1337', 'action': 'once'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(attention.requests, <NativeUserAttentionType>[
      NativeUserAttentionType.informational,
    ]);

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'attention_request',
        sessionId: '1',
        payload: <String, Object?>{'source': 'iterm1337', 'action': 'once'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      attention.requests,
      <NativeUserAttentionType>[NativeUserAttentionType.informational],
      reason: 'the per-session cooldown must suppress an immediate burst',
    );

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'attention_request',
        sessionId: '1',
        payload: <String, Object?>{'source': 'iterm1337', 'action': 'no'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(attention.cancellations, <int>[100]);

    now = now.add(const Duration(seconds: 3));
    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'attention_request',
        sessionId: '1',
        payload: <String, Object?>{'source': 'iterm1337', 'action': 'yes'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(attention.requests, <NativeUserAttentionType>[
      NativeUserAttentionType.informational,
      NativeUserAttentionType.critical,
    ]);

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'attention_request',
        sessionId: '1',
        payload: <String, Object?>{'source': 'iterm1337', 'action': 'no'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(attention.cancellations, <int>[100, 101]);
  });

  testWidgets('OSC 1337 pending requests reserve the global attention cap', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final attention = _PendingUserAttentionBridge();
    var now = DateTime.utc(2026, 7, 13, 12);
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          hostActions: LocalTerminalHostActionsConfig(
            osc1337RequestAttention: LocalTerminalRequestAttentionPolicy.allow,
          ),
        ),
      ),
      userAttentionBridge: attention,
      clock: () => now,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile();
    for (var index = 0; index < 8; index += 1) {
      controller.createSession(profile);
    }
    await tester.pumpAndSettle();

    final sessionIds = container
        .read(sessionControllerProvider)
        .tabs
        .map((tab) => tab.sessionId)
        .toList(growable: false);
    expect(sessionIds, hasLength(9));
    final runtime = container.read(terminalRuntimeControllerProvider);
    for (final sessionId in sessionIds) {
      fakeBindings.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'attention_request',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'iterm1337',
            'action': 'once',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump(const Duration(milliseconds: 40));
      now = now.add(const Duration(seconds: 1));
    }

    expect(attention.requests, hasLength(8));
    expect(attention.pendingRequests, hasLength(8));
  });

  testWidgets('OSC 1337 policy disable cancels owned attention immediately', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final attention = _RecordingUserAttentionBridge();
    final localConfigRepository = _MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        hostActions: LocalTerminalHostActionsConfig(
          osc1337RequestAttention: LocalTerminalRequestAttentionPolicy.allow,
        ),
      ),
    );
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: localConfigRepository,
      userAttentionBridge: attention,
    );

    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'attention_request',
        sessionId: '1',
        payload: <String, Object?>{'source': 'iterm1337', 'action': 'once'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(attention.requests, <NativeUserAttentionType>[
      NativeUserAttentionType.informational,
    ]);

    await _openCommandMenu(tester);
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();
    final deny = find.byKey(
      const Key('default-osc1337-request-attention-policy-disabled'),
    );
    await tester.ensureVisible(deny);
    await tester.tap(deny);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(attention.cancellations, <int>[100]);
    expect(
      localConfigRepository
          .savedDocuments
          .last
          .hostActions
          .osc1337RequestAttention,
      LocalTerminalRequestAttentionPolicy.disabled,
    );
  });

  testWidgets('OSC 1337 fireworks is cursor-local and Reduce Motion safe', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final attention = _RecordingUserAttentionBridge();
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          hostActions: LocalTerminalHostActionsConfig(
            osc1337RequestAttention: LocalTerminalRequestAttentionPolicy.allow,
          ),
        ),
      ),
      userAttentionBridge: attention,
      shellAnimationsEnabled: false,
    );
    fakeBindings.setFrame(1, const <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 10,
          'text': 'attention target',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 10, 'col': 20, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 10, 'end': 11},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    await tester.pump(const Duration(milliseconds: 40));
    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'attention_request',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'iterm1337',
          'action': 'fireworks',
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    final burst = find.byKey(const Key('osc1337-fireworks-1'));
    expect(burst, findsOneWidget);
    expect(
      find.bySemanticsLabel('Terminal requested attention'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: burst, matching: find.byType(AnimatedBuilder)),
      findsNothing,
      reason: 'Reduce Motion must use the static fallback',
    );
    final burstRect = tester.getRect(burst);
    final viewportRect = tester.getRect(find.byType(TerminalViewport));
    expect(viewportRect.contains(burstRect.center), isTrue);
    expect(attention.requests, isEmpty);

    await tester.pump(const Duration(milliseconds: 450));
    expect(burst, findsNothing);
  });

  testWidgets('OSC 1337 OpenURL requires active confirmation before opening', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final opened = <String>[];
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      externalUrlOpener: (url) async => opened.add(url),
    );
    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'open_url_request',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'iterm1337',
          'url': 'https://example.test/phase29?prompt=visible',
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('osc1337-open-url-dialog')), findsOneWidget);
    expect(find.text('Open terminal-requested URL?'), findsOneWidget);
    expect(
      find.textContaining('https://example.test/phase29?prompt=visible'),
      findsOneWidget,
    );
    expect(
      opened,
      isEmpty,
      reason: 'terminal output must never auto-open a URL',
    );

    await tester.tap(find.byKey(const Key('osc1337-open-url-approve')));
    await tester.pumpAndSettle();
    expect(opened, <String>['https://example.test/phase29?prompt=visible']);
  });

  testWidgets(
    'OSC 1337 ReportVariable denies first and remembers future allow',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      final localConfigRepository = _MemoryLocalTerminalConfigRepository(null);
      await _pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        localConfigRepository: localConfigRepository,
      );
      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'shell_context',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'osc1337_current_dir',
            'cwd': '/product/report-variable',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'report_variable_request',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'iterm1337',
            'name': 'session.path',
            'value': '/native/stale',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        ascii.decode(fakeBindings.writes.last),
        '\x1b]1337;ReportVariable=\x07',
      );
      expect(
        find.byKey(const Key('osc1337-report-variable-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('osc1337-report-variable-name')),
        findsOneWidget,
      );
      expect(find.text('session.path'), findsOneWidget);
      expect(find.textContaining('current request was denied'), findsOneWidget);

      await tester.tap(find.byKey(const Key('osc1337-report-variable-allow')));
      await tester.pumpAndSettle();
      expect(
        localConfigRepository
            .savedDocuments
            .last
            .hostActions
            .osc1337ReportVariables['session.path'],
        LocalTerminalReportVariablePolicy.allow,
      );

      fakeBindings.enqueueEvent(
        1,
        const PtyEvent(
          kind: 'report_variable_request',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'iterm1337',
            'name': 'session.path',
            'value': '/native/stale',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        ascii.decode(fakeBindings.writes.last),
        '\x1b]1337;ReportVariable=L3Byb2R1Y3QvcmVwb3J0LXZhcmlhYmxl\x07',
      );
      expect(
        find.byKey(const Key('osc1337-report-variable-dialog')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'OSC 1337 ReportVariable remembered deny and unknown names stay silent',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      await _pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        localConfigRepository: _MemoryLocalTerminalConfigRepository(
          const LocalTerminalConfigDocument(
            hostActions: LocalTerminalHostActionsConfig(
              osc1337ReportVariables:
                  <String, LocalTerminalReportVariablePolicy>{
                    'session.hostname': LocalTerminalReportVariablePolicy.deny,
                  },
            ),
          ),
        ),
      );
      for (final name in <String>['session.hostname', 'session.environment']) {
        fakeBindings.enqueueEvent(
          1,
          PtyEvent(
            kind: 'report_variable_request',
            sessionId: '1',
            payload: <String, Object?>{
              'source': 'iterm1337',
              'name': name,
              'value': 'must-not-leak',
            },
          ),
        );
      }
      await tester.pump(const Duration(milliseconds: 40));

      final reportReplies = fakeBindings.writes
          .map(ascii.decode)
          .where((value) => value.contains('ReportVariable='))
          .toList(growable: false);
      expect(reportReplies, hasLength(2));
      expect(reportReplies, everyElement('\x1b]1337;ReportVariable=\x07'));
      expect(
        find.byKey(const Key('osc1337-report-variable-dialog')),
        findsNothing,
      );
    },
  );

  testWidgets('OSC 1337 ReportVariable prompt cooldown prevents modal spam', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    var now = DateTime.utc(2026, 7, 13, 12);
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      clock: () => now,
    );

    void request(String name) {
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'report_variable_request',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'iterm1337',
            'name': name,
            'value': 'private-value',
          },
        ),
      );
    }

    request('session.path');
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      find.byKey(const Key('osc1337-report-variable-dialog')),
      findsOneWidget,
    );
    final denyButton = tester.widget<FilledButton>(
      find.byKey(const Key('osc1337-report-variable-deny')),
    );
    expect(denyButton.autofocus, isTrue);
    await tester.tap(find.byKey(const Key('osc1337-report-variable-not-now')));
    await tester.pumpAndSettle();

    request('session.hostname');
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      find.byKey(const Key('osc1337-report-variable-dialog')),
      findsNothing,
    );
    expect(
      ascii.decode(fakeBindings.writes.last),
      '\x1b]1337;ReportVariable=\x07',
    );

    now = now.add(const Duration(seconds: 31));
    request('session.hostname');
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      find.byKey(const Key('osc1337-report-variable-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('OSC 1337 OpenURL denial and bursts never invoke the opener', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final opened = <String>[];
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      externalUrlOpener: (url) async => opened.add(url),
    );
    for (final suffix in <String>['first', 'second']) {
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'open_url_request',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'iterm1337',
            'url': 'https://example.test/$suffix',
          },
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('osc1337-open-url-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('osc1337-open-url-deny')));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('OSC 1337 Open URL blocked'), findsOneWidget);
  });

  testWidgets('OSC 1337 OpenURL deny policy blocks without a dialog', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final opened = <String>[];
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      localConfigRepository: _MemoryLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          hostActions: LocalTerminalHostActionsConfig(
            osc1337OpenUrl: LocalTerminalOpenUrlPolicy.disabled,
          ),
        ),
      ),
      externalUrlOpener: (url) async => opened.add(url),
    );
    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'open_url_request',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'iterm1337',
          'url': 'https://example.test/blocked',
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('osc1337-open-url-dialog')), findsNothing);
    expect(opened, isEmpty);
    expect(find.text('OSC 1337 Open URL blocked by policy'), findsOneWidget);
  });

  testWidgets('OSC 1337 OpenURL ignores inactive and unsafe requests', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final opened = <String>[];
    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      externalUrlOpener: (url) async => opened.add(url),
    );
    await _tapTabContextMenuAction(tester, 'Split right');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final state = container.read(sessionControllerProvider);
    final inactiveSessionId = state.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != state.activeSessionId)
        .sessionId;
    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'open_url_request',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{
          'source': 'iterm1337',
          'url': 'https://example.test/inactive',
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    fakeBindings.enqueueEvent(
      state.activeSessionId!,
      PtyEvent(
        kind: 'open_url_request',
        sessionId: state.activeSessionId!,
        payload: const <String, Object?>{
          'source': 'iterm1337',
          'url': 'javascript:alert(1)',
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(state.activeSessionId!);
    fakeBindings.enqueueEvent(
      state.activeSessionId!,
      PtyEvent(
        kind: 'open_url_request',
        sessionId: state.activeSessionId!,
        payload: const <String, Object?>{
          'source': 'iterm1337',
          'url': 'file://remote.example/path',
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(state.activeSessionId!);
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('osc1337-open-url-dialog')), findsNothing);
    expect(opened, isEmpty);
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

  testWidgets('OSC 1337 download requires Save before writing bytes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fakeBindings = FakePtyBackend();
    const selectedPath = '/chosen/saved-report.txt';
    final savedFiles = <String, Uint8List>{};
    const channel = MethodChannel('app/window_bridge');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'chooseFileDownloadLocation' ? selectedPath : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      fileDownloadWriter: (path, bytes) async {
        savedFiles[path] = Uint8List.fromList(bytes);
      },
    );
    fakeBindings.fileDownloads[('1', 7)] = Uint8List.fromList(
      utf8.encode('hello'),
    );
    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'file_download',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'iterm1337',
          'transferId': '7',
          'filename': 'report.txt',
          'size': 5,
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Received report.txt (5 B)'), findsOneWidget);
    expect(savedFiles, isEmpty);
    await tester.tap(find.byKey(const Key('osc1337-file-download-save-7')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(utf8.decode(savedFiles[selectedPath]!), 'hello');
    expect(fakeBindings.takenFileDownloads, <(String, int)>[('1', 7)]);
    expect(fakeBindings.discardedFileDownloads, isEmpty);
    expect(
      calls
          .where((call) => call.method == 'chooseFileDownloadLocation')
          .single
          .arguments,
      <String, Object?>{'suggestedName': 'report.txt'},
    );
    expect(find.text('Saved report.txt'), findsOneWidget);
  });

  testWidgets('ZMODEM receive requires a folder and exposes progress/cancel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fakeBindings = FakePtyBackend();
    const channel = MethodChannel('app/window_bridge');
    final bridgeCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      bridgeCalls.add(call);
      return call.method == 'chooseZmodemReceiveDirectory'
          ? '/chosen/downloads'
          : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final runtime = container.read(terminalRuntimeControllerProvider);
    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_detected',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '41',
          'direction': 'receive',
        },
      ),
    );
    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_file_offer',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '41',
          'direction': 'receive',
          'filename': 'report.bin',
          'size': null,
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      bridgeCalls.where(
        (call) => call.method == 'chooseZmodemReceiveDirectory',
      ),
      hasLength(1),
    );
    expect(fakeBindings.jsonRequests.last, <String, Object?>{
      'kind': 'terminal.zmodem.accept_receive',
      'transferId': '41',
      'destination': '/chosen/downloads',
    });
    expect(
      find.byKey(const Key('shell-zmodem-transfer-detail')),
      findsOneWidget,
    );
    expect(find.textContaining('unknown size'), findsOneWidget);
    final writesBeforeBlockedInput = fakeBindings.writes.length;
    runtime.sendInput('1', Uint8List.fromList(const <int>[0x41]));
    expect(fakeBindings.writes, hasLength(writesBeforeBlockedInput));

    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_progress',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '41',
          'direction': 'receive',
          'bytesTransferred': 512,
          'totalBytes': 1024,
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('512 B / 1.0 KB'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('shell-zmodem-transfer-progress')),
          )
          .value,
      0.5,
    );
    final progressSemantics = tester.getSemantics(
      find.byKey(const Key('shell-zmodem-transfer-progress')),
    );
    expect(progressSemantics.label, 'ZMODEM progress');
    expect(progressSemantics.value, '50 percent');
    expect(progressSemantics.flagsCollection.isLiveRegion, isFalse);

    await tester.tap(find.byKey(const Key('shell-zmodem-transfer-cancel')));
    await tester.pump();
    expect(fakeBindings.jsonRequests.last, <String, Object?>{
      'kind': 'terminal.zmodem.cancel',
      'transferId': '41',
    });
    expect(find.text('Cancelling…'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('shell-zmodem-transfer-cancel')),
          )
          .onPressed,
      isNull,
    );
    final requestsAfterFirstCancel = fakeBindings.jsonRequests.length;
    await tester.tap(
      find.byKey(const Key('shell-zmodem-transfer-cancel')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(fakeBindings.jsonRequests, hasLength(requestsAfterFirstCancel));
    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_cancelled',
        sessionId: '1',
        payload: <String, Object?>{'source': 'zmodem', 'transferId': '41'},
      ),
    );
    runtime.refreshSession('1');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('shell-zmodem-transfer-detail')), findsNothing);
    expect(find.text('ZMODEM transfer cancelled'), findsOneWidget);
  });

  testWidgets(
    'ZMODEM does not open a picker for a transfer ended in the same poll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();
      const channel = MethodChannel('app/window_bridge');
      final bridgeCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        bridgeCalls.add(call);
        return call.method == 'chooseZmodemReceiveDirectory'
            ? '/chosen/downloads'
            : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.jsonRequests.clear();
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '42',
            'direction': 'receive',
            'filename': 'already-ended.bin',
            'size': 8,
          },
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: '1',
          payload: <String, Object?>{'source': 'zmodem', 'transferId': '42'},
        ),
      );

      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.isZmodemTransferActive('1'), isFalse);
      expect(
        bridgeCalls.where(
          (call) => call.method == 'chooseZmodemReceiveDirectory',
        ),
        isEmpty,
      );
      expect(
        fakeBindings.jsonRequests.where(
          (request) => request['kind'] == 'terminal.zmodem.accept_receive',
        ),
        isEmpty,
      );
      expect(
        find.byKey(const Key('shell-zmodem-transfer-detail')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'ZMODEM deferred write failure persists and suppresses same-poll success',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_detected',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '43',
            'direction': 'receive',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_deferred_write_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'reason': 'io_error',
            'queuedChunks': 3,
            'queuedBytes': 12,
            'completedChunks': 1,
            'completedBytes': 4,
          },
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_completed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '43',
            'direction': 'receive',
          },
        ),
      );

      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('shell-runtime-error')), findsOneWidget);
      expect(
        find.textContaining('8 bytes in 2 queued writes were not confirmed'),
        findsOneWidget,
      );
      expect(find.text('ZMODEM receive completed'), findsNothing);
      expect(
        container.read(sessionControllerProvider).lastError,
        contains('The terminal connection was closed'),
      );

      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('shell-runtime-error')), findsOneWidget);
    },
  );

  testWidgets(
    'ZMODEM ignores an ended picker request before authorizing a new transfer',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();
      const channel = MethodChannel('app/window_bridge');
      final firstPicker = Completer<String?>();
      var pickerCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) {
        if (call.method != 'chooseZmodemReceiveDirectory') {
          return Future<Object?>.value();
        }
        pickerCalls += 1;
        return pickerCalls == 1
            ? firstPicker.future
            : Future<Object?>.value('/current/downloads');
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.jsonRequests.clear();
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '44',
            'direction': 'receive',
            'filename': 'ended.bin',
            'size': 8,
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      expect(pickerCalls, 1);

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: '1',
          payload: <String, Object?>{'source': 'zmodem', 'transferId': '44'},
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '45',
            'direction': 'receive',
            'filename': 'current.bin',
            'size': 16,
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(pickerCalls, 1);
      expect(
        find.textContaining('previous ZMODEM file picker is still open'),
        findsWidgets,
      );
      expect(
        find.byKey(const Key('shell-zmodem-transfer-retry')),
        findsOneWidget,
      );

      firstPicker.complete('/stale/downloads');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        fakeBindings.jsonRequests.where(
          (request) => request['kind'] == 'terminal.zmodem.accept_receive',
        ),
        isEmpty,
      );
      expect(
        find.text(
          'ZMODEM transfer already ended; the picker result was not used.',
        ),
        findsWidgets,
      );

      await tester.tap(find.byKey(const Key('shell-zmodem-transfer-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(pickerCalls, 2);
      expect(
        fakeBindings.jsonRequests
            .where(
              (request) => request['kind'] == 'terminal.zmodem.accept_receive',
            )
            .single,
        <String, Object?>{
          'kind': 'terminal.zmodem.accept_receive',
          'transferId': '45',
          'destination': '/current/downloads',
        },
      );
    },
  );

  testWidgets(
    'ZMODEM rejects bidi filenames before display or receive authorization',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();
      const channel = MethodChannel('app/window_bridge');
      final bridgeCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        bridgeCalls.add(call);
        return call.method == 'chooseZmodemReceiveDirectory'
            ? '/chosen/downloads'
            : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.jsonRequests.clear();

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '52',
            'direction': 'receive',
            'filename': 'invoice\u202Egpj.exe',
            'size': 1024,
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.isZmodemTransferActive('1'), isFalse);
      expect(
        find.byKey(const Key('shell-zmodem-transfer-detail')),
        findsNothing,
      );
      expect(find.textContaining('invoice'), findsNothing);
      expect(
        bridgeCalls.where(
          (call) => call.method == 'chooseZmodemReceiveDirectory',
        ),
        isEmpty,
      );
      expect(
        fakeBindings.jsonRequests.where(
          (request) => request['kind'] == 'terminal.zmodem.accept_receive',
        ),
        isEmpty,
      );

      const unicodeFilename = '发票-東京-😀.jpg';
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '52',
            'direction': 'receive',
            'filename': unicodeFilename,
            'size': 1024,
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.isZmodemTransferActive('1'), isTrue);
      expect(find.textContaining(unicodeFilename), findsOneWidget);
      expect(
        bridgeCalls.where(
          (call) => call.method == 'chooseZmodemReceiveDirectory',
        ),
        hasLength(1),
      );
      expect(fakeBindings.jsonRequests.single, <String, Object?>{
        'kind': 'terminal.zmodem.accept_receive',
        'transferId': '52',
        'destination': '/chosen/downloads',
      });
    },
  );

  testWidgets(
    'ZMODEM rejects 257 selected files without authorizing a truncated batch',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();
      const channel = MethodChannel('app/window_bridge');
      final selected = List<String>.generate(
        257,
        (index) => '/tmp/file-$index.bin',
        growable: false,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            call.method == 'chooseZmodemSendFiles' ? selected : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.jsonRequests.clear();
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_detected',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '60',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('at most 256 files'), findsWidgets);
      expect(
        fakeBindings.jsonRequests.where(
          (request) => request['kind'] == 'terminal.zmodem.accept_send',
        ),
        isEmpty,
      );
      expect(
        find.byKey(const Key('shell-zmodem-transfer-retry')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ZMODEM gap survivor exposes recovery without prior transfer UI state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend()..zmodemCancelActiveOutcome = 'idle';
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);

      fakeBindings.enqueueEvent(
        '1',
        PtyRuntimeEventGapDiagnostic(
          sessionId: '1',
          expectedSequence: 2,
          nextSequence: 6,
          droppedCount: 4,
          survivingEventCount: 1,
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '60',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.complete.ianvs-part',
            'stagingPreserved': true,
            'recoveryToken': '00112233445566778899aabbccddeeff',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('shell-zmodem-recovery')), findsOneWidget);
      expect(
        find.textContaining('Complete file preserved as .complete.ianvs-part'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Old publish recovery does not hide the current gap reconciliation UI',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend()
        ..zmodemCancelActiveOutcome = 'cancelled';
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);

      fakeBindings.enqueueEvent(
        '1',
        PtyRuntimeEventGapDiagnostic(
          sessionId: '1',
          expectedSequence: 2,
          nextSequence: 5,
          droppedCount: 1,
          survivingEventCount: 2,
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.complete.ianvs-part',
            'stagingPreserved': true,
            'recoveryToken': '00112233445566778899aabbccddeeff',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_detected',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive('1'), isTrue);
      expect(find.textContaining('Transfer state lost'), findsOneWidget);
      expect(find.byKey(const Key('shell-zmodem-recovery')), findsOneWidget);
      expect(
        find.textContaining('Complete file preserved as .complete.ianvs-part'),
        findsOneWidget,
      );

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive('1'), isFalse);
      expect(find.textContaining('Transfer state lost'), findsNothing);
      expect(find.byKey(const Key('shell-zmodem-recovery')), findsOneWidget);
    },
  );

  testWidgets(
    'Old terminal does not hide a successor drain reconciliation UI',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend()
        ..zmodemCancelActiveOutcome = 'cancelled';
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_detected',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();

      fakeBindings.enqueueEvent(
        '1',
        PtyRuntimeEventGapDiagnostic(
          sessionId: '1',
          expectedSequence: 3,
          nextSequence: 6,
          droppedCount: 1,
          survivingEventCount: 2,
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_completed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_detected',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive('1'), isTrue);
      expect(find.textContaining('Transfer state lost'), findsOneWidget);

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive('1'), isFalse);
      expect(find.textContaining('Transfer state lost'), findsNothing);
    },
  );

  testWidgets(
    'First-batch ZMODEM gap survivor exposes transfer UI and pauses input',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend()
        ..zmodemResponses['terminal.zmodem.cancel_active'] = false;
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.jsonRequests.clear();

      fakeBindings.enqueueEvent(
        '1',
        PtyRuntimeEventGapDiagnostic(
          sessionId: '1',
          expectedSequence: 2,
          nextSequence: 4,
          droppedCount: 1,
          survivingEventCount: 1,
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_detected',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '61',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.activeZmodemTransferIdFor('1'), '61');
      expect(find.byKey(const Key('shell-zmodem-transfer-61')), findsOneWidget);
      expect(find.textContaining('terminal input paused'), findsOneWidget);
      expect(
        find.byKey(const Key('shell-zmodem-transfer-cancel')),
        findsOneWidget,
      );
      expect(fakeBindings.jsonRequests.single, <String, Object?>{
        'kind': 'terminal.zmodem.cancel_active',
      });
    },
  );

  testWidgets(
    'First-batch ZMODEM gap without survivors exposes cancellation recovery',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend()
        ..zmodemResponses['terminal.zmodem.cancel'] = false
        ..zmodemResponses['terminal.zmodem.cancel_active'] = false;
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.jsonRequests.clear();

      fakeBindings.enqueueEvent(
        '1',
        PtyRuntimeEventGapDiagnostic(
          sessionId: '1',
          expectedSequence: 2,
          nextSequence: 5,
          droppedCount: 3,
          survivingEventCount: 0,
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.isZmodemTransferActive('1'), isTrue);
      expect(find.textContaining('Transfer state lost'), findsOneWidget);
      expect(
        find.byKey(const Key('shell-zmodem-transfer-cancel')),
        findsOneWidget,
      );

      fakeBindings.zmodemResponses['terminal.zmodem.cancel_active'] = true;
      await tester.tap(find.byKey(const Key('shell-zmodem-transfer-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.isZmodemTransferActive('1'), isTrue);
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '18446744073709551615',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      expect(runtime.isZmodemTransferActive('1'), isFalse);
      expect(find.textContaining('Transfer state lost'), findsNothing);
    },
  );

  testWidgets('Cancel during native drain preserves the completed result', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fakeBindings = FakePtyBackend()
      ..zmodemResponses['terminal.zmodem.cancel'] = false
      ..zmodemCancelActiveOutcome = 'draining';
    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final runtime = container.read(terminalRuntimeControllerProvider);

    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_started',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '62',
          'direction': 'receive',
          'fileCount': 1,
          'totalBytes': 3,
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('shell-zmodem-transfer-cancel')));
    await tester.pump();

    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_completed',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '62',
          'direction': 'receive',
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ZMODEM receive completed'), findsOneWidget);
    expect(find.text('ZMODEM transfer cancelled'), findsNothing);
  });

  testWidgets('Inactive ZMODEM result is shown when its session is activated', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final runtime = container.read(terminalRuntimeControllerProvider);
    final sessions = container.read(sessionControllerProvider.notifier);

    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_started',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '63',
          'direction': 'receive',
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
    sessions.createSession(defaultTerminalProfile());
    await tester.pump();

    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_completed',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '63',
          'direction': 'receive',
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
    expect(find.text('ZMODEM receive completed'), findsNothing);
    expect(
      notifications.where(
        (notification) =>
            notification['identifier'] == 'ianvs-terminal.zmodem.1' &&
            notification['body'] == 'ZMODEM receive completed',
      ),
      hasLength(1),
    );

    sessions.activateSession('1');
    await tester.pump();
    await tester.pump();
    expect(find.text('ZMODEM receive completed'), findsOneWidget);
  });

  testWidgets('Inactive ZMODEM authorization is cancelled and notified', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final runtime = container.read(terminalRuntimeControllerProvider);
    container
        .read(sessionControllerProvider.notifier)
        .createSession(defaultTerminalProfile());
    await tester.pump();
    fakeBindings.jsonRequests.clear();

    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_detected',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '64',
          'direction': 'send',
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
    await tester.pump();

    expect(fakeBindings.jsonRequests.single, <String, Object?>{
      'kind': 'terminal.zmodem.cancel',
      'transferId': '64',
    });
    expect(
      notifications.where(
        (notification) =>
            notification['identifier'] == 'ianvs-terminal.zmodem.1' &&
            notification['title']!.startsWith('ZMODEM request cancelled') &&
            notification['body']!.contains('pane is inactive'),
      ),
      hasLength(1),
    );
  });

  testWidgets(
    'Inactive ZMODEM reconciliation marks output and notifies attention',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend()
        ..zmodemCancelActiveOutcome = 'draining';
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
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      container
          .read(sessionControllerProvider.notifier)
          .createSession(defaultTerminalProfile());
      await tester.pump();

      fakeBindings.enqueueEvent(
        '1',
        PtyRuntimeEventGapDiagnostic(
          sessionId: '1',
          expectedSequence: 2,
          nextSequence: 5,
          droppedCount: 3,
          survivingEventCount: 0,
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('shell-tab-new-output-1')), findsOneWidget);
      expect(
        notifications.where(
          (notification) =>
              notification['identifier'] == 'ianvs-terminal.zmodem.1' &&
              notification['title']!.startsWith(
                'ZMODEM transfer needs attention',
              ) &&
              notification['body']!.contains('Transfer state was lost'),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'Inactive preserved ZMODEM receive marks output and notifies attention',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
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
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      container
          .read(sessionControllerProvider.notifier)
          .createSession(defaultTerminalProfile());
      await tester.pump();

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '65',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.inactive.ianvs-part',
            'stagingPreserved': true,
            'recoveryToken': '11223344556677889900aabbccddeeff',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('shell-tab-new-output-1')), findsOneWidget);
      expect(
        notifications.where(
          (notification) =>
              notification['identifier'] == 'ianvs-terminal.zmodem.1' &&
              notification['title']!.startsWith('ZMODEM file preserved') &&
              notification['body']!.contains('complete file was preserved'),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'Fallback ZMODEM recovery identifies its inactive source session',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      container
          .read(sessionControllerProvider.notifier)
          .createSession(defaultTerminalProfile());
      await tester.pump();

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '66',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.same-name.ianvs-part',
            'stagingPreserved': true,
            'recoveryToken': '22334455667788990011aabbccddeeff',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining(
          '.same-name.ianvs-part from Local Shell (session 1)',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ZMODEM recovery survives session close and is consumed after Reveal',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();
      const channel = MethodChannel('app/window_bridge');
      final bridgeCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        bridgeCalls.add(call);
        return call.method == 'chooseZmodemReceiveDirectory'
            ? '/chosen/downloads'
            : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.zmodemRecoveryPath = '/current/downloads/.report.ianvs-part';
      fakeBindings.jsonRequests.clear();
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '61',
            'direction': 'receive',
            'filename': 'report.bin',
            'size': 8,
            'modificationTimeSeconds': 1700000456,
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeBindings.jsonRequests.last, <String, Object?>{
        'kind': 'terminal.zmodem.accept_receive',
        'transferId': '61',
        'destination': '/chosen/downloads',
      });
      expect(
        find.textContaining('modified 2023-11-14 22:20:56 UTC'),
        findsOneWidget,
      );

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '61',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.report.ianvs-part',
            'stagingPreserved': true,
            'recoveryToken': '0123456789abcdef0123456789abcdef',
            'recoverablePartialPath': '/stale/downloads/.report.ianvs-part',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.isZmodemTransferActive('1'), isFalse);
      expect(
        find.textContaining('Complete file preserved as .report.ianvs-part'),
        findsOneWidget,
      );
      expect(find.textContaining('selected folder'), findsNothing);
      expect(find.textContaining('/chosen/downloads'), findsNothing);
      expect(
        find.textContaining('0123456789abcdef0123456789abcdef'),
        findsNothing,
      );
      expect(find.text('Reveal'), findsOneWidget);
      expect(
        fakeBindings.jsonRequests.where(
          (request) => request['kind'] == 'terminal.zmodem.resolve_recovery',
        ),
        isEmpty,
      );

      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('shell-zmodem-recovery')), findsOneWidget);
      expect(find.text('Reveal'), findsOneWidget);

      await container
          .read(sessionControllerProvider.notifier)
          .closeSession('1');
      await tester.pumpAndSettle();
      expect(fakeBindings.closedSessionIds, contains('1'));
      expect(find.byKey(const Key('shell-zmodem-recovery')), findsOneWidget);

      await tester.tap(find.text('Reveal'));
      await tester.pump();
      expect(
        fakeBindings.jsonRequests
            .where(
              (request) =>
                  request['kind'] == 'terminal.zmodem.resolve_recovery' ||
                  request['kind'] == 'terminal.zmodem.consume_recovery',
            )
            .toList(),
        <Map<String, Object?>>[
          <String, Object?>{
            'kind': 'terminal.zmodem.resolve_recovery',
            'recoveryToken': '0123456789abcdef0123456789abcdef',
          },
          <String, Object?>{
            'kind': 'terminal.zmodem.consume_recovery',
            'recoveryToken': '0123456789abcdef0123456789abcdef',
          },
        ],
      );
      final reveal = bridgeCalls.singleWhere(
        (call) => call.method == 'revealInFinder',
      );
      expect(reveal.arguments, <String, Object?>{
        'path': '/current/downloads/.report.ianvs-part',
      });
      expect(find.byKey(const Key('shell-zmodem-recovery')), findsNothing);
    },
  );

  testWidgets(
    'ZMODEM recovery retains transient Reveal failures and dismisses stale tokens',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();
      const channel = MethodChannel('app/window_bridge');
      final bridgeCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        bridgeCalls.add(call);
        return call.method == 'chooseZmodemReceiveDirectory'
            ? '/chosen/downloads'
            : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      fakeBindings.zmodemRecoveryRequestFails = true;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.jsonRequests.clear();
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '62',
            'direction': 'receive',
            'filename': 'report.bin',
            'size': 8,
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '62',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.report.ianvs-part',
            'stagingPreserved': true,
            'recoveryToken': 'fedcba9876543210fedcba9876543210',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Reveal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Could not resolve the preserved ZMODEM file; try again'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('shell-zmodem-recovery')), findsOneWidget);
      expect(
        find.textContaining('fedcba9876543210fedcba9876543210'),
        findsNothing,
      );
      expect(find.textContaining('/chosen/downloads'), findsNothing);
      expect(
        find.textContaining('relative/unsafe-recovery-path'),
        findsNothing,
      );
      expect(
        fakeBindings.jsonRequests
            .where(
              (request) =>
                  request['kind'] == 'terminal.zmodem.resolve_recovery' ||
                  request['kind'] == 'terminal.zmodem.consume_recovery',
            )
            .toList(),
        <Map<String, Object?>>[
          <String, Object?>{
            'kind': 'terminal.zmodem.resolve_recovery',
            'recoveryToken': 'fedcba9876543210fedcba9876543210',
          },
        ],
      );
      expect(
        bridgeCalls.where((call) => call.method == 'revealInFinder'),
        isEmpty,
      );

      fakeBindings.zmodemResponses['terminal.zmodem.dismiss_recovery'] = false;
      await tester.tap(find.byKey(const Key('shell-zmodem-recovery-dismiss')));
      await tester.pump();

      expect(find.text('Permanently discard file?'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(
        fakeBindings.jsonRequests.where(
          (request) => request['kind'] == 'terminal.zmodem.dismiss_recovery',
        ),
        isEmpty,
      );

      await tester.tap(
        find.byKey(const Key('shell-zmodem-recovery-discard-cancel')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shell-zmodem-recovery')), findsOneWidget);

      await tester.tap(find.byKey(const Key('shell-zmodem-recovery-dismiss')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('shell-zmodem-recovery-discard-confirm')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('shell-zmodem-recovery')), findsNothing);
      expect(fakeBindings.jsonRequests.last, <String, Object?>{
        'kind': 'terminal.zmodem.dismiss_recovery',
        'recoveryToken': 'fedcba9876543210fedcba9876543210',
      });
    },
  );

  testWidgets(
    'ZMODEM Reveal consumes native authority safely after ShellScreen unmounts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();
      fakeBindings.zmodemRecoveryPath = '/chosen/.late-recovery.part';
      const channel = MethodChannel('app/window_bridge');
      final revealCompleter = Completer<bool>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'revealInFinder') {
          return revealCompleter.future;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_detected',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '63',
            'direction': 'receive',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '63',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.late-recovery.part',
            'stagingPreserved': true,
            'recoveryToken': '00112233445566778899aabbccddeeff',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Reveal'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      revealCompleter.complete(true);
      await tester.pump();
      await tester.pump();

      expect(
        fakeBindings.jsonRequests.where(
          (request) => request['kind'] == 'terminal.zmodem.consume_recovery',
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ZMODEM multi-file send keeps batch progress and clears finished names',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend();
      const channel = MethodChannel('app/window_bridge');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'chooseZmodemSendFiles'
            ? <String>['/tmp/first.bin', '/tmp/second.bin']
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.jsonRequests.clear();

      Future<void> deliver(String kind, Map<String, Object?> payload) async {
        fakeBindings.enqueueEvent(
          '1',
          PtyEvent(kind: kind, sessionId: '1', payload: payload),
        );
        runtime.refreshSession('1');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }

      await deliver('zmodem_detected', const <String, Object?>{
        'source': 'zmodem',
        'transferId': '55',
        'direction': 'send',
      });
      expect(fakeBindings.jsonRequests.last, <String, Object?>{
        'kind': 'terminal.zmodem.accept_send',
        'transferId': '55',
        'files': <String>['/tmp/first.bin', '/tmp/second.bin'],
      });

      await deliver('zmodem_started', const <String, Object?>{
        'source': 'zmodem',
        'transferId': '55',
        'direction': 'send',
        'fileCount': 2,
        'totalBytes': 300,
      });
      await deliver('zmodem_progress', const <String, Object?>{
        'source': 'zmodem',
        'transferId': '55',
        'direction': 'send',
        'bytesTransferred': 100,
        'totalBytes': 300,
      });
      await deliver('zmodem_file_completed', const <String, Object?>{
        'source': 'zmodem',
        'transferId': '55',
        'direction': 'send',
        'filename': 'first.bin',
        'size': 100,
        'completedFiles': 1,
      });

      var detail = tester.widget<Text>(
        find.byKey(const Key('shell-zmodem-transfer-detail')),
      );
      expect(detail.data, contains('1 / 2 files'));
      expect(detail.data, contains('100 B / 300 B'));
      expect(detail.data, isNot(contains('first.bin')));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('shell-zmodem-transfer-progress')),
            )
            .value,
        closeTo(1 / 3, 0.001),
      );

      await deliver('zmodem_progress', const <String, Object?>{
        'source': 'zmodem',
        'transferId': '55',
        'direction': 'send',
        'bytesTransferred': 150,
        'totalBytes': 300,
      });
      await deliver('zmodem_file_skipped', const <String, Object?>{
        'source': 'zmodem',
        'transferId': '55',
        'direction': 'send',
        'filename': 'second.bin',
        'size': 200,
        'completedFiles': 1,
        'skippedFiles': 1,
      });

      detail = tester.widget<Text>(
        find.byKey(const Key('shell-zmodem-transfer-detail')),
      );
      expect(detail.data, contains('2 / 2 files'));
      expect(detail.data, contains('1 skipped'));
      expect(detail.data, contains('150 B / 300 B'));
      expect(detail.data, isNot(contains('second.bin')));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('shell-zmodem-transfer-progress')),
            )
            .value,
        0.5,
      );
    },
  );

  testWidgets('ZMODEM picker cancel keeps a recoverable retry state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fakeBindings = FakePtyBackend();
    const channel = MethodChannel('app/window_bridge');
    var pickerCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'chooseZmodemReceiveDirectory') {
        return null;
      }
      pickerCalls += 1;
      return pickerCalls == 1 ? null : '/retry/downloads';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final runtime = container.read(terminalRuntimeControllerProvider);
    fakeBindings.jsonRequests.clear();
    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_file_offer',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '52',
          'direction': 'receive',
          'filename': 'unknown.bin',
          'size': null,
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('Destination selection cancelled'),
      findsWidgets,
    );
    expect(
      find.byKey(const Key('shell-zmodem-transfer-retry')),
      findsOneWidget,
    );
    expect(fakeBindings.jsonRequests, isEmpty);

    await tester.tap(find.byKey(const Key('shell-zmodem-transfer-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(pickerCalls, 2);
    expect(fakeBindings.jsonRequests.last, <String, Object?>{
      'kind': 'terminal.zmodem.accept_receive',
      'transferId': '52',
      'destination': '/retry/downloads',
    });
    expect(find.byKey(const Key('shell-zmodem-transfer-retry')), findsNothing);
    expect(find.textContaining('unknown size'), findsOneWidget);
  });

  testWidgets('Active ZMODEM transfer blocks pane close without losing state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fakeBindings = FakePtyBackend();
    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final runtime = container.read(terminalRuntimeControllerProvider);
    final sessions = container.read(sessionControllerProvider.notifier);
    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_started',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '520',
          'direction': 'receive',
          'fileCount': 1,
          'totalBytes': 3,
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await sessions.closeSession('1'), isFalse);
    await tester.pump();

    expect(runtime.hasSession('1'), isTrue);
    expect(fakeBindings.closedSessionIds, isNot(contains('1')));
    expect(
      container.read(sessionControllerProvider).lastError,
      contains('Cancel the active ZMODEM transfer'),
    );
    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_cancelled',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '520',
          'direction': 'receive',
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
  });

  testWidgets(
    'Native ZMODEM close busy protects an event not yet polled by Dart',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend()..failingCloseSessionIds.add('1');
      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      final sessions = container.read(sessionControllerProvider.notifier);
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_detected',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '521',
            'direction': 'send',
          },
        ),
      );

      expect(runtime.isZmodemTransferActive('1'), isFalse);
      expect(await sessions.closeSession('1'), isFalse);
      await tester.pump();

      expect(runtime.hasSession('1'), isTrue);
      expect(fakeBindings.closedSessionIds, isNot(contains('1')));
      expect(
        container.read(sessionControllerProvider).lastError,
        contains('native ZMODEM transfer'),
      );

      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(runtime.activeZmodemTransferIdFor('1'), '521');
      fakeBindings.failingCloseSessionIds.remove('1');
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '521',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
    },
  );

  testWidgets('ZMODEM authorization failure remains retryable', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fakeBindings = FakePtyBackend()
      ..zmodemResponses['terminal.zmodem.accept_receive'] = false;
    const channel = MethodChannel('app/window_bridge');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'chooseZmodemReceiveDirectory'
          ? '/chosen/downloads'
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final runtime = container.read(terminalRuntimeControllerProvider);
    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_file_offer',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '53',
          'direction': 'receive',
          'filename': 'retry.bin',
          'size': 3,
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Could not authorize'), findsWidgets);
    expect(
      find.byKey(const Key('shell-zmodem-transfer-retry')),
      findsOneWidget,
    );

    fakeBindings.zmodemResponses['terminal.zmodem.accept_receive'] = true;
    await tester.tap(find.byKey(const Key('shell-zmodem-transfer-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      fakeBindings.jsonRequests
          .where(
            (request) => request['kind'] == 'terminal.zmodem.accept_receive',
          )
          .length,
      2,
    );
    expect(find.byKey(const Key('shell-zmodem-transfer-retry')), findsNothing);
  });

  testWidgets(
    'ZMODEM native start clears a lost authorization response error',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fakeBindings = FakePtyBackend()
        ..zmodemResponses['terminal.zmodem.accept_receive'] = false;
      const channel = MethodChannel('app/window_bridge');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'chooseZmodemReceiveDirectory'
            ? '/chosen/downloads'
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '54',
            'direction': 'receive',
            'filename': 'accepted.bin',
            'size': 3,
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Could not authorize'), findsWidgets);
      expect(
        find.byKey(const Key('shell-zmodem-transfer-retry')),
        findsOneWidget,
      );

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_started',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '54',
            'direction': 'receive',
            'fileCount': 1,
            'totalBytes': 3,
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('Could not authorize'), findsNothing);
      expect(
        find.byKey(const Key('shell-zmodem-transfer-retry')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('shell-zmodem-transfer-detail')),
        findsOneWidget,
      );

      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '54',
            'direction': 'receive',
            'filename': 'second.bin',
            'size': 4,
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        fakeBindings.jsonRequests
            .where(
              (request) => request['kind'] == 'terminal.zmodem.accept_receive',
            )
            .length,
        1,
        reason: 'native start proves the original authorization was accepted',
      );
      fakeBindings.enqueueEvent(
        '1',
        const PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '54',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession('1');
      await tester.pump();
    },
  );

  testWidgets('ZMODEM session-switch cancel failure is visible and retryable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fakeBindings = FakePtyBackend()
      ..zmodemResponses['terminal.zmodem.cancel'] = false
      ..zmodemResponses['terminal.zmodem.cancel_active'] = false;
    final notifications = <Map<String, String?>>[];
    const channel = MethodChannel('app/window_bridge');
    final picker = Completer<String?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) => call.method == 'chooseZmodemReceiveDirectory'
          ? picker.future
          : Future<Object?>.value(),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final runtime = container.read(terminalRuntimeControllerProvider);
    final sessions = container.read(sessionControllerProvider.notifier);
    fakeBindings.enqueueEvent(
      '1',
      const PtyEvent(
        kind: 'zmodem_file_offer',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'zmodem',
          'transferId': '54',
          'direction': 'receive',
          'filename': 'switch.bin',
          'size': null,
        },
      ),
    );
    runtime.refreshSession('1');
    await tester.pump();

    sessions.createSession(defaultTerminalProfile());
    await tester.pump();
    picker.complete('/chosen/downloads');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('shell-tab-new-output-1')), findsOneWidget);
    expect(
      notifications.where(
        (notification) =>
            notification['identifier'] == 'ianvs-terminal.zmodem.1' &&
            notification['title']!.startsWith(
              'ZMODEM transfer needs attention',
            ) &&
            notification['body']!.contains('cancellation failed'),
      ),
      hasLength(1),
    );

    sessions.activateSession('1');
    await tester.pump();

    expect(find.textContaining('cancellation failed'), findsWidgets);
    expect(
      find.byKey(const Key('shell-zmodem-transfer-retry')),
      findsOneWidget,
    );
    expect(
      fakeBindings.jsonRequests
          .skip(fakeBindings.jsonRequests.length - 2)
          .map((request) => request['kind']),
      <Object?>['terminal.zmodem.cancel', 'terminal.zmodem.cancel_active'],
    );

    fakeBindings.zmodemResponses['terminal.zmodem.cancel'] = true;
    await tester.tap(find.byKey(const Key('shell-zmodem-transfer-retry')));
    await tester.pump();
    expect(find.byKey(const Key('shell-zmodem-transfer-retry')), findsNothing);
  });

  testWidgets('OSC 1337 download cancel and inactive pane release bytes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fakeBindings = FakePtyBackend();
    const channel = MethodChannel('app/window_bridge');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpShellScreen(tester, fakeBindings: fakeBindings);
    fakeBindings.fileDownloads[('1', 8)] = Uint8List.fromList(const <int>[1]);
    fakeBindings.enqueueEvent(
      1,
      const PtyEvent(
        kind: 'file_download',
        sessionId: '1',
        payload: <String, Object?>{
          'source': 'iterm1337',
          'transferId': '8',
          'filename': 'cancel.bin',
          'size': 1,
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('osc1337-file-download-save-8')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fakeBindings.discardedFileDownloads, <(String, int)>[('1', 8)]);
    expect(find.text('Received file discarded'), findsOneWidget);

    await _tapTabContextMenuAction(tester, 'Split right');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final splitState = container.read(sessionControllerProvider);
    final activeSessionId = splitState.activeSessionId!;
    final inactiveSessionId = splitState.tabs.single.effectivePanes
        .firstWhere((pane) => pane.sessionId != activeSessionId)
        .sessionId;
    fakeBindings.fileDownloads[(inactiveSessionId, 9)] = Uint8List.fromList(
      const <int>[2],
    );
    fakeBindings.enqueueEvent(
      inactiveSessionId,
      PtyEvent(
        kind: 'file_download',
        sessionId: inactiveSessionId,
        payload: const <String, Object?>{
          'source': 'iterm1337',
          'transferId': '9',
          'filename': 'background.bin',
          'size': 1,
        },
      ),
    );
    container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(inactiveSessionId);
    await tester.pump();

    expect(find.textContaining('Received background.bin'), findsNothing);
    expect(fakeBindings.discardedFileDownloads, <(String, int)>[
      ('1', 8),
      (inactiveSessionId, 9),
    ]);
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
    await _chooseDefaultLocalSession(tester);
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
          'command': 'deploy staging --token super-secret',
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
    expect(notifications.single['body'], 'Exit code 0');
    expect(
      notifications.single['identifier'],
      startsWith('ianvs-terminal.command.1.'),
    );
    for (final field in const <String>['title', 'body', 'identifier']) {
      final value = notifications.single[field] ?? '';
      expect(value, isNot(contains('deploy staging --token super-secret')));
      expect(value, isNot(contains('--token')));
      expect(value, isNot(contains('super-secret')));
    }
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
        frameWithText('TOKEN=super-secret-output one'),
      );
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(inactiveSessionId);
      await tester.pump(const Duration(milliseconds: 40));
      fakeBindings.setFrame(
        inactiveSessionId,
        frameWithText('TOKEN=super-secret-output two'),
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
        'New terminal output is available.',
      );
      for (final field in const <String>['title', 'body', 'identifier']) {
        final value = activityNotifications.single[field] ?? '';
        expect(value, isNot(contains('TOKEN=super-secret-output')));
        expect(value, isNot(contains('TOKEN')));
        expect(value, isNot(contains('secret')));
      }
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
        layout: LocalTerminalLayoutConfig(restoreLayout: true),
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
    expect(savedConfig.layout.restoreLayout, isTrue);
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

  testWidgets('shortcut editor saves and hot-reloads an override', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final localConfigRepository = _MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(),
    );
    await _pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      localConfigRepository: localConfigRepository,
    );

    await _openCommandMenu(tester);
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();
    final filter = find.byKey(const Key('shortcut-editor-filter'));
    await tester.ensureVisible(filter);
    await tester.enterText(filter, 'new tab');
    await tester.pump();
    final editNewTab = find.byKey(const Key('shortcut-edit-newTab'));
    await tester.ensureVisible(editNewTab);
    await tester.pumpAndSettle();
    await tester.tap(editNewTab);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();
    await tester.tap(find.byKey(const Key('shortcut-capture-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    final savedBinding = localConfigRepository
        .savedDocuments
        .last
        .keybindings
        .overrides[TerminalActionId.newTab]
        ?.binding;
    expect(savedBinding?.key, 'Key N');
    expect(savedBinding?.meta, isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    expect(container.read(sessionControllerProvider).tabs, hasLength(1));
    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();
    await _sendMetaShortcut(tester, LogicalKeyboardKey.keyN);
    await _chooseDefaultLocalSession(tester);
    expect(container.read(sessionControllerProvider).tabs, hasLength(2));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shortcut editor restores defaults and hot-reloads them', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final localConfigRepository = _MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        keybindings: LocalTerminalKeybindingsConfig(
          overrides: {
            TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
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
      fakeBindings: FakePtyBackend(),
      localConfigRepository: localConfigRepository,
    );

    await _openCommandMenu(tester);
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();
    final restoreAll = find.byKey(const Key('shortcut-editor-restore-all'));
    await tester.ensureVisible(restoreAll);
    await tester.pumpAndSettle();
    await tester.tap(restoreAll);
    await tester.pump();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(
      localConfigRepository.savedDocuments.last.keybindings,
      const LocalTerminalKeybindingsConfig(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    expect(container.read(sessionControllerProvider).tabs, hasLength(1));
    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();
    await _sendMetaShortcut(tester, LogicalKeyboardKey.keyN);
    expect(container.read(sessionControllerProvider).tabs, hasLength(1));
    await _sendMetaShortcut(tester, LogicalKeyboardKey.keyT);
    await _chooseDefaultLocalSession(tester);
    expect(container.read(sessionControllerProvider).tabs, hasLength(2));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native paste confirms multiline text before sending', (
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

    final pasteFuture = _dispatchNativeWindowBridge(
      tester,
      const MethodCall('nativePaste'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('paste-confirmation-dialog')), findsOneWidget);
    expect(fakeBindings.writes, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Paste'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await pasteFuture;

    expect(fakeBindings.writes, hasLength(1));
    expect(utf8.decode(fakeBindings.writes.single), contains(clipboardText));
  });

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

    await _invokeNativeWindowBridge(tester, const MethodCall('nativePaste'));

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

    await _invokeNativeWindowBridge(tester, const MethodCall('nativePaste'));

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

    await _invokeNativeWindowBridge(tester, const MethodCall('nativePaste'));

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

      await _invokeNativeWindowBridge(tester, const MethodCall('nativePaste'));

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

  testWidgets('terminal focus alone does not show the shell layout cue', (
    tester,
  ) async {
    await _pumpShellScreen(tester, fakeBindings: FakePtyBackend());

    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    expect(find.byKey(const Key('shell-layout-focus-cue')), findsNothing);
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
      ThemeData.light().colorScheme.surfaceContainerLowest.toARGB32(),
    );
    expect(
      renderObject.debugColors.foreground.toARGB32(),
      ThemeData.light().colorScheme.onSurface.toARGB32(),
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
      ThemeData.dark().colorScheme.surfaceContainerLowest.toARGB32(),
    );
    expect(
      renderObject.debugColors.foreground.toARGB32(),
      ThemeData.dark().colorScheme.onSurface.toARGB32(),
    );
  });

  testWidgets(
    'launcher close shows a brief return cue at top right and keeps keyboard path',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(tester, fakeBindings: fakeBindings);

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      expect(find.byKey(const Key('shell-layout-focus-cue')), findsNothing);

      await _openCommandMenu(tester);
      await tester.tap(find.byTooltip('Close command palette'));
      await tester.pumpAndSettle();

      final cueFinder = find.byKey(const Key('shell-layout-focus-cue'));
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

  testWidgets('defaults close restores the layout cue and keyboard path', (
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

    expect(find.byKey(const Key('shell-layout-focus-cue')), findsOneWidget);
    expect(find.text('Back in shell'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.pump();

    expect(fakeBindings.writes, isNotEmpty);
    expect(fakeBindings.writes.last, 'v'.codeUnits);
  });
}
