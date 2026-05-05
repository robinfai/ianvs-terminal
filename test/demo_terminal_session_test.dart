import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

import 'package:ianvs_terminal/main.dart';
import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/session_restore.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';
import 'package:ianvs_terminal/src/terminal_settings.dart';

void main() {
  group('desktop e2e harness', () {
    testWidgets('exports and reapplies app windows with success feedback', (
      tester,
    ) async {
      final backend = _FakePtySessionBackend();
      final settingsStore = _settingsStore();
      final dir = Directory.systemTemp.createTempSync('ianvs_demo_launch_');
      final file = File('${dir.path}/ianvs-terminal.launch.json');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final harness = _DesktopDemoHarness(
        tester,
        backend: backend,
        settingsStore: settingsStore,
      );
      await harness.pumpApp();

      await harness.newWindow();
      expect(find.text('Window 2'), findsOneWidget);

      await harness.openNewSshSession(
        host: 'prod.example.internal',
        project: 'window-two-ssh',
      );
      expect(
        find.byKey(const Key('terminal-tab-window-two-ssh')),
        findsOneWidget,
      );

      await harness.selectWindow(1);
      expect(
        find.byKey(const Key('terminal-tab-window-two-ssh')),
        findsNothing,
      );
      await harness.selectWindow(2);
      expect(
        find.byKey(const Key('terminal-tab-window-two-ssh')),
        findsOneWidget,
      );

      await harness.saveLaunchConfig(file.path);

      expect(file.existsSync(), isTrue);
      expect(
        find.byKey(const Key('terminal-launch-config-success-state')),
        findsOneWidget,
      );
      expect(find.textContaining(file.path), findsOneWidget);
      await harness.closeSavedLaunchConfig();

      final savedJson =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(savedJson['activeWindowIndex'], 1);
      expect((savedJson['windows'] as List<Object?>).length, 2);

      await harness.closeWindow();
      expect(
        find.byKey(const Key('terminal-tab-window-two-ssh')),
        findsNothing,
      );

      await harness.applyLaunchConfig(file.path);

      expect(find.text('Applied app config from ${file.path}'), findsOneWidget);
      expect(
        find.byKey(const Key('terminal-tab-window-two-ssh')),
        findsOneWidget,
      );
    });

    testWidgets('restores split panes after workspace navigation', (
      tester,
    ) async {
      final backend = _FakePtySessionBackend();
      final settingsStore = _settingsStore();
      final restoreStore = _sessionRestoreStore();
      final harness = _DesktopDemoHarness(
        tester,
        backend: backend,
        settingsStore: settingsStore,
        sessionRestoreStore: restoreStore,
      );

      await harness.pumpApp();
      await harness.splitRight();
      expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);

      await harness.openWorkspaceSearch();
      expect(find.text('1/2'), findsOneWidget);
      await harness.selectNextPaletteEntry();
      expect(find.text('2/2'), findsOneWidget);
      await harness.choosePaletteEntry();

      expect(find.byKey(const Key('terminal-pane-active-1')), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'ianvs-modern-input',
      );

      final savedState = restoreStore.load();
      expect(savedState.windows, hasLength(1));
      expect(savedState.windows.single.tabs, hasLength(1));
      expect(savedState.windows.single.tabs.single.activePaneId, 1);
      expect(
        savedState.windows.single.tabs.single.rootPane,
        isA<TerminalSessionRestorePaneSplit>(),
      );

      await harness.rebuildApp();

      expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
      expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);
      expect(find.byKey(const Key('terminal-pane-active-1')), findsOneWidget);
    });

    testWidgets('restarts ssh command sessions with updated targets', (
      tester,
    ) async {
      final backend = _FakePtySessionBackend();
      final settingsStore = _settingsStore();
      final harness = _DesktopDemoHarness(
        tester,
        backend: backend,
        settingsStore: settingsStore,
      );

      await harness.pumpApp();
      await harness.openNewSshSession(
        host: 'prod.example.internal',
        account: 'ops-user',
        environment: 'prod-use1',
        project: 'payments-api',
      );

      expect(
        find.byKey(const Key('terminal-tab-payments-api')),
        findsOneWidget,
      );
      expect(
        _launchArgsAt(backend, backend.createdSessionConfigs.length - 1),
        <String>['ops-user@prod.example.internal'],
      );

      await harness.updateSessionContextHost('staging.example.internal');
      await harness.restartActiveSession();

      expect(
        _launchArgsAt(backend, backend.createdSessionConfigs.length - 1),
        <String>['ops-user@staging.example.internal'],
      );
    });

    testWidgets('command palette reinputs active history across tabs', (
      tester,
    ) async {
      final backend = _FakePtySessionBackend();
      final settingsStore = _settingsStore();
      final harness = _DesktopDemoHarness(
        tester,
        backend: backend,
        settingsStore: settingsStore,
        initialBlocksForSession: _demoBlocksForSession,
      );

      await harness.pumpApp();
      await harness.newTab();
      await harness.openCommandSearch();

      expect(find.textContaining('echo second'), findsWidgets);
      await harness.choosePaletteEntry();

      expect(harness.modernInputText(), 'echo second');
    });
  });
}

class _DesktopDemoHarness {
  _DesktopDemoHarness(
    this.tester, {
    required this.backend,
    required this.settingsStore,
    this.sessionRestoreStore,
    this.initialBlocksForSession,
  });

  final WidgetTester tester;
  final _FakePtySessionBackend backend;
  final TerminalSettingsStore settingsStore;
  final TerminalSessionRestoreStore? sessionRestoreStore;
  final TerminalBlockSeedFactory? initialBlocksForSession;

  Future<void> pumpApp() async {
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: _FakeClipboardClient(''),
        settingsStore: settingsStore,
        sessionRestoreStore: sessionRestoreStore,
        sessionRestoreDebounceDuration: Duration.zero,
        initialBlocksForSession: initialBlocksForSession,
      ),
    );
    await tester.pump();
  }

  Future<void> rebuildApp() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpApp();
  }

  Future<void> newWindow() async {
    await _selectAddMenuAction('new-window');
  }

  Future<void> selectWindow(int windowId) async {
    await _tapByKey('terminal-window-$windowId');
  }

  Future<void> newTab() async {
    await _selectAddMenuAction('new-tab');
  }

  Future<void> closeWindow() async {
    await _selectHeaderOverflowAction('close-window');
  }

  Future<void> splitRight() async {
    await _selectHeaderOverflowAction('split-right');
  }

  Future<void> openWorkspaceSearch() async {
    await _selectHeaderOverflowAction('workspace-search');
  }

  Future<void> openCommandSearch() async {
    await _tapByKey('terminal-command-history-button');
  }

  Future<void> selectNextPaletteEntry() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }

  Future<void> choosePaletteEntry() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }

  String modernInputText() {
    final field = tester.widget<TextField>(
      find.byKey(const Key('terminal-modern-input-field')),
    );
    return field.controller?.text ?? '';
  }

  Future<void> saveLaunchConfig(String path) async {
    await _selectAddMenuAction('launch-config', settle: true);
    await _enterText('terminal-launch-config-name-field', 'demo-export');
    await _tapByKey('terminal-launch-config-advanced-toggle', settle: true);
    await _enterText('terminal-launch-config-path-field', path);
    await _tapByKey('terminal-launch-config-save-button', settle: true);
  }

  Future<void> closeSavedLaunchConfig() async {
    await _tapByKey('terminal-launch-config-done-button', settle: true);
  }

  Future<void> applyLaunchConfig(String path) async {
    await _selectAddMenuAction('launch-config', settle: true);
    await _tapByKey('terminal-launch-config-advanced-toggle', settle: true);
    await _enterText('terminal-launch-config-path-field', path);
    await _tapByKey('terminal-launch-config-apply-button', settle: true);
  }

  Future<void> openNewSshSession({
    required String host,
    String account = '',
    String environment = '',
    String project = '',
  }) async {
    await _selectAddMenuAction('new-ssh', settle: true);
    await _enterText('terminal-new-ssh-host-field', host);
    if (account.isNotEmpty) {
      await _enterText('terminal-new-ssh-account-field', account);
    }
    if (environment.isNotEmpty) {
      await _enterText('terminal-new-ssh-environment-field', environment);
    }
    if (project.isNotEmpty) {
      await _enterText('terminal-new-ssh-project-field', project);
    }
    await _tapByKey('terminal-new-ssh-open-button', settle: true);
  }

  Future<void> updateSessionContextHost(String host) async {
    await _selectHeaderOverflowAction('session-context', settle: true);
    await _enterText('terminal-session-host-field', host);
    await _tapByKey('terminal-session-context-apply-button', settle: true);
  }

  Future<void> restartActiveSession() async {
    await _selectHeaderOverflowAction('restart');
  }

  Future<void> _selectAddMenuAction(
    String action, {
    bool settle = false,
  }) async {
    final addMenu = find.byKey(const Key('terminal-add-menu-button'));
    tester.widget<PopupMenuButton<String>>(addMenu).onSelected!(action);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> _selectHeaderOverflowAction(
    String action, {
    bool settle = false,
  }) async {
    final overflowMenu = find.byKey(
      const Key('terminal-header-overflow-menu-button'),
    );
    tester.widget<PopupMenuButton<String>>(overflowMenu).onSelected!(action);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> _tapByKey(String key, {bool settle = false}) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> _enterText(String key, String value) async {
    await tester.enterText(find.byKey(Key(key)), value);
    await tester.pump();
  }
}

TerminalSettingsStore _settingsStore({String defaultShell = '/bin/zsh'}) {
  final dir = Directory.systemTemp.createTempSync('ianvs_demo_settings_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return TerminalSettingsStore(
    file: File('${dir.path}/settings.json'),
    defaultShell: defaultShell,
  );
}

TerminalSessionRestoreStore _sessionRestoreStore({
  TerminalSessionRestoreState? state,
}) {
  final dir = Directory.systemTemp.createTempSync('ianvs_demo_restore_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  final store = TerminalSessionRestoreStore(
    file: File('${dir.path}/session_restore.json'),
  );
  if (state != null) {
    store.save(state);
  }
  return store;
}

List<String> _launchArgsAt(_FakePtySessionBackend backend, int index) {
  final launch =
      backend.createdSessionConfigs[index]['launch'] as Map<String, Object?>;
  final args = launch['args'] as List<Object?>? ?? const <Object?>[];
  return args.cast<String>();
}

class _FakeClipboardClient implements ClipboardClient {
  _FakeClipboardClient(this.text);

  String text;

  @override
  Future<String> readText() async => text;

  @override
  Future<void> writeText(String text) async {
    this.text = text;
  }
}

class _FakePtySessionBackend implements PtySessionBackend {
  int _createCount = 0;
  final List<Map<String, Object?>> createdSessionConfigs =
      <Map<String, Object?>>[];
  final List<String> closedSessionIds = <String>[];
  final Queue<Map<String, Object?>> _queuedFrames =
      Queue<Map<String, Object?>>();

  @override
  int ping() => 42;

  @override
  String createSession(String sessionConfigJson) {
    _createCount += 1;
    createdSessionConfigs.add(
      jsonDecode(sessionConfigJson) as Map<String, Object?>,
    );
    return 'session-$_createCount';
  }

  @override
  void closeSession(String sessionId) {
    closedSessionIds.add(sessionId);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? searchTextJson(String sessionId, String query) {
    return jsonEncode(const <Map<String, Object?>>[]);
  }

  @override
  String? selectionText(String sessionId, String requestJson) => '';

  @override
  String? takeFrameDiffJson(String sessionId) {
    if (_queuedFrames.isNotEmpty) {
      return jsonEncode(_queuedFrames.removeFirst());
    }
    return jsonEncode(_frameJson());
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}

Map<String, Object?> _frameJson({
  String kind = 'snapshot',
  String text = 'ready',
  int cursorCol = 0,
  int cursorRow = 0,
  int viewportRows = 1,
  Map<String, Object?> modes = const <String, Object?>{},
  List<Map<String, Object?>> dirtyRanges = const <Map<String, Object?>>[
    <String, Object?>{'start': 0, 'end': 1},
  ],
}) {
  return <String, Object?>{
    'frame_kind': kind,
    'rows': <Object?>[
      <String, Object?>{
        'index': 0,
        'text': text,
        'style_runs': const <Object?>[],
      },
    ],
    'cursor': <String, Object?>{
      'row': cursorRow,
      'col': cursorCol,
      'visible': true,
    },
    'viewport_rows': viewportRows,
    'viewport_cols': 80,
    'dirty_ranges': dirtyRanges,
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
    'modes': modes,
  };
}

List<TerminalBlock> _demoBlocksForSession(String sessionId) {
  return switch (sessionId) {
    'session-1' => const <TerminalBlock>[
      TerminalBlock(
        id: 'session-1-block-1',
        sessionId: 'session-1',
        commandText: 'false',
        outputText: '',
        status: TerminalBlockStatus.failed,
        scrollbackOffset: 9,
      ),
    ],
    'session-2' => const <TerminalBlock>[
      TerminalBlock(
        id: 'session-2-block-1',
        sessionId: 'session-2',
        commandText: 'echo second',
        outputText: 'second\n',
        status: TerminalBlockStatus.succeeded,
        scrollbackOffset: 4,
      ),
    ],
    _ => const <TerminalBlock>[],
  };
}
