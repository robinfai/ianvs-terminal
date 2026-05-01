import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/saved_commands.dart';
import 'package:ianvs_terminal/src/session_restore.dart';
import 'package:ianvs_terminal/src/terminal_panes.dart';
import 'package:ianvs_terminal/src/terminal_settings.dart';
import 'package:ianvs_terminal/src/terminal_tabs_controller.dart';

void main() {
  test('initial tab starts with one active pane', () {
    final backend = _FakePtySessionBackend();
    final tabs = _tabs(backend);
    addTearDown(tabs.dispose);

    tabs.createInitialTab();

    expect(tabs.activeTab.paneCount, 1);
    expect(tabs.activeTab.rootPane, isA<TerminalPaneLeaf>());
    expect(tabs.activePane.shellController.sessionId, 'session-1');
    expect(tabs.activeShell.sessionId, 'session-1');
    expect(tabs.canCloseActivePane, isFalse);
  });

  test('split right and down create active panes with direction and ratio', () {
    final backend = _FakePtySessionBackend();
    final tabs = _tabs(backend);
    addTearDown(tabs.dispose);

    tabs.createInitialTab();
    tabs.splitActivePaneRight();

    expect(tabs.activeTab.paneCount, 2);
    expect(tabs.activeShell.sessionId, 'session-2');
    expect(tabs.canCloseActivePane, isTrue);
    final rightRoot = tabs.activeTab.rootPane as TerminalPaneSplit;
    expect(rightRoot.direction, TerminalPaneSplitDirection.right);
    expect(rightRoot.ratio, 0.5);

    tabs.splitActivePaneDown();

    expect(tabs.activeTab.paneCount, 3);
    expect(tabs.activeShell.sessionId, 'session-3');
    final nested = rightRoot.second as TerminalPaneSplit;
    expect(nested.direction, TerminalPaneSplitDirection.down);
    expect(nested.ratio, 0.5);
  });

  test('new pane inherits active pane cwd when creating shell config', () {
    final backend = _FakePtySessionBackend();
    final tabs = _tabs(backend);
    final cwd = Directory.systemTemp.createTempSync('ianvs_pane_cwd_');
    addTearDown(() {
      tabs.dispose();
      if (cwd.existsSync()) {
        cwd.deleteSync(recursive: true);
      }
    });

    tabs.createInitialTab();
    tabs.activeShell.completionController.updateCwd(cwd.path);
    tabs.splitActivePaneRight();

    expect(_createdCwdAt(backend, 1), cwd.path);
  });

  test('next and previous pane cycle through leaves', () {
    final backend = _FakePtySessionBackend();
    final tabs = _tabs(backend);
    addTearDown(tabs.dispose);

    tabs.createInitialTab();
    tabs.splitActivePaneRight();
    tabs.splitActivePaneDown();

    expect(tabs.activeShell.sessionId, 'session-3');
    tabs.previousPane();
    expect(tabs.activeShell.sessionId, 'session-2');
    tabs.previousPane();
    expect(tabs.activeShell.sessionId, 'session-1');
    tabs.nextPane();
    expect(tabs.activeShell.sessionId, 'session-2');
  });

  test('closing active pane disposes it and selects adjacent pane', () {
    final backend = _FakePtySessionBackend();
    final tabs = _tabs(backend);
    addTearDown(tabs.dispose);

    tabs.createInitialTab();
    tabs.splitActivePaneRight();
    expect(tabs.activeShell.sessionId, 'session-2');

    tabs.closeActivePane();

    expect(backend.closedSessionIds, contains('session-2'));
    expect(tabs.activeTab.paneCount, 1);
    expect(tabs.activeShell.sessionId, 'session-1');
    expect(tabs.canCloseActivePane, isFalse);
  });

  test('last pane cannot be closed', () {
    final backend = _FakePtySessionBackend();
    final tabs = _tabs(backend);
    addTearDown(tabs.dispose);

    tabs.createInitialTab();
    tabs.closeActivePane();

    expect(tabs.activeTab.paneCount, 1);
    expect(backend.closedSessionIds, isEmpty);
  });

  test('closing a tab disposes every pane shell in that tab', () {
    final backend = _FakePtySessionBackend();
    final tabs = _tabs(backend);
    addTearDown(tabs.dispose);

    tabs.createInitialTab();
    tabs.splitActivePaneRight();
    tabs.splitActivePaneDown();
    tabs.newTab();

    tabs.selectTab(0);
    tabs.closeActiveTab();

    expect(
      backend.closedSessionIds,
      containsAll(<String>['session-1', 'session-2', 'session-3']),
    );
    expect(tabs.tabs.length, 1);
    expect(tabs.activeShell.sessionId, 'session-4');
  });

  test('restores tabs pane tree active state and existing cwd', () {
    final backend = _FakePtySessionBackend();
    final cwdOne = Directory.systemTemp.createTempSync('ianvs_restore_cwd_1_');
    final cwdTwo = Directory.systemTemp.createTempSync('ianvs_restore_cwd_2_');
    final restoreController = TerminalSessionRestoreController(
      store: TerminalSessionRestoreStore.memory(
        TerminalSessionRestoreState(
          activeTabIndex: 1,
          tabs: <TerminalSessionRestoreTab>[
            TerminalSessionRestoreTab(
              fallbackTitle: 'Local 1',
              activePaneId: 2,
              rootPane: TerminalSessionRestorePaneSplit(
                direction: TerminalPaneSplitDirection.right,
                ratio: 0.7,
                first: TerminalSessionRestorePaneLeaf(id: 1, cwd: cwdOne.path),
                second: TerminalSessionRestorePaneLeaf(id: 2, cwd: cwdTwo.path),
              ),
            ),
            TerminalSessionRestoreTab(
              fallbackTitle: 'Local 2',
              activePaneId: 3,
              rootPane: TerminalSessionRestorePaneLeaf(id: 3, cwd: cwdTwo.path),
            ),
          ],
        ),
      ),
      debounceDuration: Duration.zero,
    );
    final tabs = _tabs(backend, restoreController: restoreController);
    addTearDown(() {
      tabs.dispose();
      restoreController.dispose();
      cwdOne.deleteSync(recursive: true);
      cwdTwo.deleteSync(recursive: true);
    });

    tabs.createInitialTab();

    expect(tabs.tabs.length, 2);
    expect(tabs.activeIndex, 1);
    expect(tabs.activeShell.sessionId, 'session-3');
    expect(tabs.tabs.first.paneCount, 2);
    final split = tabs.tabs.first.rootPane as TerminalPaneSplit;
    expect(split.direction, TerminalPaneSplitDirection.right);
    expect(split.ratio, 0.7);
    expect(_createdCwdAt(backend, 0), cwdOne.path);
    expect(_createdCwdAt(backend, 1), cwdTwo.path);
    expect(_createdCwdAt(backend, 2), cwdTwo.path);
  });

  test('restore reassigns duplicate pane ids before creating panes', () {
    final backend = _FakePtySessionBackend();
    final restoreController = TerminalSessionRestoreController(
      store: TerminalSessionRestoreStore.memory(
        TerminalSessionRestoreState(
          activeTabIndex: 1,
          tabs: <TerminalSessionRestoreTab>[
            TerminalSessionRestoreTab(
              fallbackTitle: 'Local 1',
              activePaneId: 2,
              rootPane: TerminalSessionRestorePaneSplit(
                direction: TerminalPaneSplitDirection.right,
                first: const TerminalSessionRestorePaneLeaf(id: 1, cwd: ''),
                second: const TerminalSessionRestorePaneLeaf(id: 2, cwd: ''),
              ),
            ),
            const TerminalSessionRestoreTab(
              fallbackTitle: 'Local 2',
              activePaneId: 2,
              rootPane: TerminalSessionRestorePaneLeaf(id: 2, cwd: ''),
            ),
          ],
        ),
      ),
      debounceDuration: Duration.zero,
    );
    final tabs = _tabs(backend, restoreController: restoreController);
    addTearDown(() {
      tabs.dispose();
      restoreController.dispose();
    });

    tabs.createInitialTab();

    final paneIds = tabs.tabs
        .expand((tab) => tab.panes)
        .map((pane) => pane.id)
        .toList(growable: false);
    expect(paneIds, <int>[1, 2, 3]);
    expect(paneIds.toSet().length, paneIds.length);
    expect(tabs.activeIndex, 1);
    expect(tabs.activePane.id, 3);

    tabs.selectTab(0);
    tabs.selectPane(2);
    expect(tabs.activePane.id, 2);
  });

  test(
    'shell hooks from another session do not mutate active pane state',
    () async {
      final backend = _FakePtySessionBackend();
      final tabs = _tabs(backend);
      addTearDown(tabs.dispose);

      tabs.createInitialTab();
      final originalCwd = tabs.activeShell.completionController.cwd;
      backend.enqueueEvent(
        'session-1',
        const PtyEvent(
          kind: 'shell_hook',
          sessionId: 'session-2',
          payload: <String, Object?>{
            'hook': 'preexec',
            'command': 'echo wrong',
          },
        ),
      );
      backend.enqueueEvent(
        'session-1',
        const PtyEvent(
          kind: 'shell_hook',
          sessionId: 'session-2',
          payload: <String, Object?>{'hook': 'precmd', 'pwd': '/tmp/wrong'},
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(tabs.activeShell.blocksController.blocks, isEmpty);
      expect(tabs.activeShell.completionController.cwd, originalCwd);
    },
  );

  test('restore falls back when restored cwd does not exist', () {
    final backend = _FakePtySessionBackend();
    final restoreController = TerminalSessionRestoreController(
      store: TerminalSessionRestoreStore.memory(
        const TerminalSessionRestoreState(
          tabs: <TerminalSessionRestoreTab>[
            TerminalSessionRestoreTab(
              fallbackTitle: 'Local 1',
              activePaneId: 1,
              rootPane: TerminalSessionRestorePaneLeaf(
                id: 1,
                cwd: '/tmp/ianvs-missing-cwd-does-not-exist',
              ),
            ),
          ],
        ),
      ),
      debounceDuration: Duration.zero,
    );
    final tabs = _tabs(backend, restoreController: restoreController);
    addTearDown(() {
      tabs.dispose();
      restoreController.dispose();
    });

    tabs.createInitialTab();

    expect(
      _createdCwdAt(backend, 0),
      isNot('/tmp/ianvs-missing-cwd-does-not-exist'),
    );
  });

  test('tab pane and cwd changes are saved to restore store', () {
    final backend = _FakePtySessionBackend();
    final restoreStore = TerminalSessionRestoreStore.memory();
    final restoreController = TerminalSessionRestoreController(
      store: restoreStore,
      debounceDuration: Duration.zero,
    );
    final tabs = _tabs(backend, restoreController: restoreController);
    final cwd = Directory.systemTemp.createTempSync('ianvs_restore_saved_cwd_');
    addTearDown(() {
      tabs.dispose();
      restoreController.dispose();
      cwd.deleteSync(recursive: true);
    });

    tabs.createInitialTab();
    tabs.splitActivePaneRight();
    tabs.activeShell.completionController.updateCwd(cwd.path);
    tabs.previousPane();
    tabs.newTab();
    tabs.selectTab(0);

    final saved = restoreStore.load();
    expect(saved.activeTabIndex, 0);
    expect(saved.tabs.length, 2);
    expect(saved.tabs.first.activePaneId, 1);
    final split = saved.tabs.first.rootPane as TerminalSessionRestorePaneSplit;
    expect(split.direction, TerminalPaneSplitDirection.right);
    expect((split.second as TerminalSessionRestorePaneLeaf).cwd, cwd.path);
  });

  test('shell ui state does not thrash restore saves but cwd changes do', () {
    final backend = _FakePtySessionBackend();
    final restoreStore = TerminalSessionRestoreStore.memory();
    final restoreController = TerminalSessionRestoreController(
      store: restoreStore,
      debounceDuration: Duration.zero,
    );
    final tabs = _tabs(backend, restoreController: restoreController);
    final cwd = Directory.systemTemp.createTempSync('ianvs_restore_cwd_ui_');
    addTearDown(() {
      tabs.dispose();
      restoreController.dispose();
      cwd.deleteSync(recursive: true);
    });

    tabs.createInitialTab();
    final initialSaveCount = restoreStore.saveCount;

    tabs.activeShell.openFind();
    tabs.activeShell.updateFindQuery('missing');
    tabs.activeShell.commandHistoryController.open();

    expect(restoreStore.saveCount, initialSaveCount);

    tabs.activeShell.completionController.updateCwd(cwd.path);

    expect(restoreStore.saveCount, initialSaveCount + 1);
  });
}

TerminalTabsController _tabs(
  _FakePtySessionBackend backend, {
  TerminalSessionRestoreController? restoreController,
}) {
  final settingsDir = Directory.systemTemp.createTempSync(
    'ianvs_pane_settings_',
  );
  addTearDown(() {
    if (settingsDir.existsSync()) {
      settingsDir.deleteSync(recursive: true);
    }
  });
  final settingsController = TerminalSettingsController(
    store: TerminalSettingsStore(
      file: File('${settingsDir.path}/settings.json'),
      defaultShell: '/bin/zsh',
    ),
  );
  return TerminalTabsController(
    backendFactory: () => backend,
    clipboardClient: _FakeClipboardClient(),
    settingsController: settingsController,
    savedCommandsController: SavedCommandsController.memory(),
    sessionRestoreController: restoreController,
  );
}

String? _createdCwdAt(_FakePtySessionBackend backend, int index) {
  final launch = backend.createdSessionConfigs[index]['launch'];
  return (launch as Map<String, Object?>)['cwd'] as String?;
}

class _FakeClipboardClient implements ClipboardClient {
  @override
  Future<String> readText() async => '';

  @override
  Future<void> writeText(String text) async {}
}

class _FakePtySessionBackend implements PtySessionBackend {
  int _createCount = 0;
  final List<Map<String, Object?>> createdSessionConfigs =
      <Map<String, Object?>>[];
  final List<String> closedSessionIds = <String>[];
  final Map<String, Queue<PtyEvent>> _queuedEvents =
      <String, Queue<PtyEvent>>{};

  void enqueueEvent(String sessionId, PtyEvent event) {
    _queuedEvents.putIfAbsent(sessionId, Queue<PtyEvent>.new).add(event);
  }

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
  List<PtyEvent> pollEvents(String sessionId) {
    final queued = _queuedEvents[sessionId];
    if (queued == null || queued.isEmpty) {
      return const <PtyEvent>[];
    }
    final events = queued.toList(growable: false);
    queued.clear();
    return events;
  }

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
  String? searchTextJson(String sessionId, String query) => '[]';

  @override
  String? selectionText(String sessionId, String requestJson) => '';

  @override
  String? takeFrameDiffJson(String sessionId) => jsonEncode(_frameJson());

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}

Map<String, Object?> _frameJson() {
  return <String, Object?>{
    'frame_kind': 'snapshot',
    'rows': <Object?>[
      <String, Object?>{
        'index': 0,
        'text': 'ready',
        'style_runs': const <Object?>[],
      },
    ],
    'cursor': const <String, Object?>{'row': 0, 'col': 0, 'visible': true},
    'viewport_rows': 1,
    'viewport_cols': 80,
    'dirty_ranges': const <Object?>[
      <String, Object?>{'start': 0, 'end': 1},
    ],
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
    'modes': const <String, Object?>{},
  };
}
