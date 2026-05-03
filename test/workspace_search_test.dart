import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/local_shell_session_controller.dart';
import 'package:ianvs_terminal/src/saved_commands.dart';
import 'package:ianvs_terminal/src/terminal_settings.dart';
import 'package:ianvs_terminal/src/terminal_tabs_controller.dart';
import 'package:ianvs_terminal/src/workspace_search.dart';

void main() {
  test(
    'builds workspace search results from open tabs panes and active state',
    () {
      final backend = _FakePtySessionBackend();
      final tabs = _tabs(backend);
      final cwdOne = Directory.systemTemp.createTempSync('ianvs_ws_one_');
      final cwdTwo = Directory.systemTemp.createTempSync('ianvs_ws_two_');
      final cwdThree = Directory.systemTemp.createTempSync('ianvs_ws_three_');
      addTearDown(() {
        tabs.dispose();
        cwdOne.deleteSync(recursive: true);
        cwdTwo.deleteSync(recursive: true);
        cwdThree.deleteSync(recursive: true);
      });

      tabs.createInitialTab();
      tabs.activeShell.completionController.updateCwd(cwdOne.path);
      tabs.splitActivePaneRight();
      tabs.activeShell.completionController.updateCwd(cwdTwo.path);
      tabs.newTab();
      tabs.activeShell.completionController.updateCwd(cwdThree.path);
      tabs.selectTab(0);

      final results = buildWorkspaceSearchResults(tabs);

      expect(results.length, 3);
      expect(results[0].tabTitle, 'Local 1');
      expect(results[0].paneLabel, 'Pane 1 · #1');
      expect(results[0].cwd, cwdOne.path);
      expect(results[0].isActiveTab, isTrue);
      expect(results[0].isActivePane, isFalse);
      expect(results[1].cwd, cwdTwo.path);
      expect(results[1].isActivePane, isTrue);
      expect(results[1].statusLabel, 'Running');
      expect(results[2].tabTitle, 'Local 2');
      expect(results[2].cwd, cwdThree.path);
    },
  );

  test('filter sorts exact prefix substring and active ties', () {
    const exact = WorkspaceSearchResult(
      id: 'exact',
      tabIndex: 0,
      tabId: 1,
      tabTitle: 'work',
      paneId: 1,
      paneOrdinal: 0,
      cwd: '/tmp/a',
      status: LocalShellStatus.running,
      exitCode: null,
      isActiveTab: false,
      isActivePane: false,
    );
    const activePrefix = WorkspaceSearchResult(
      id: 'active-prefix',
      tabIndex: 0,
      tabId: 1,
      tabTitle: 'Local 1',
      paneId: 2,
      paneOrdinal: 1,
      cwd: 'workbench',
      status: LocalShellStatus.running,
      exitCode: null,
      isActiveTab: true,
      isActivePane: false,
    );
    const prefix = WorkspaceSearchResult(
      id: 'prefix',
      tabIndex: 1,
      tabId: 2,
      tabTitle: 'Local 2',
      paneId: 3,
      paneOrdinal: 0,
      cwd: 'workspace',
      status: LocalShellStatus.running,
      exitCode: null,
      isActiveTab: false,
      isActivePane: false,
    );
    const substring = WorkspaceSearchResult(
      id: 'substring',
      tabIndex: 2,
      tabId: 3,
      tabTitle: 'Local 3',
      paneId: 4,
      paneOrdinal: 0,
      cwd: '/tmp/demo-work',
      status: LocalShellStatus.running,
      exitCode: null,
      isActiveTab: false,
      isActivePane: true,
    );

    final matches = filterWorkspaceSearchResults(const <WorkspaceSearchResult>[
      substring,
      prefix,
      activePrefix,
      exact,
    ], 'work');

    expect(matches.map((entry) => entry.id).toList(growable: false), <String>[
      'exact',
      'active-prefix',
      'prefix',
      'substring',
    ]);
  });

  test('controller updates matches when closed panes disappear', () {
    final dependency = _TestNotifier();
    var entries = const <WorkspaceSearchResult>[
      WorkspaceSearchResult(
        id: 'pane-1',
        tabIndex: 0,
        tabId: 1,
        tabTitle: 'Alpha',
        paneId: 1,
        paneOrdinal: 0,
        cwd: '/tmp/alpha',
        status: LocalShellStatus.running,
        exitCode: null,
        isActiveTab: true,
        isActivePane: true,
      ),
      WorkspaceSearchResult(
        id: 'pane-2',
        tabIndex: 0,
        tabId: 1,
        tabTitle: 'Alpha',
        paneId: 2,
        paneOrdinal: 1,
        cwd: '/tmp/bravo',
        status: LocalShellStatus.running,
        exitCode: null,
        isActiveTab: true,
        isActivePane: false,
      ),
    ];
    final controller = WorkspaceSearchController(
      dependency: dependency,
      entriesBuilder: () => entries,
      jumpToResult: (_) {},
    );
    addTearDown(controller.dispose);

    controller.open();
    controller.updateQuery('bravo');
    expect(controller.matches.single.id, 'pane-2');

    entries = const <WorkspaceSearchResult>[
      WorkspaceSearchResult(
        id: 'pane-1',
        tabIndex: 0,
        tabId: 1,
        tabTitle: 'Alpha',
        paneId: 1,
        paneOrdinal: 0,
        cwd: '/tmp/alpha',
        status: LocalShellStatus.running,
        exitCode: null,
        isActiveTab: true,
        isActivePane: true,
      ),
    ];
    dependency.ping();

    expect(controller.matches, isEmpty);
  });

  test('choose jumps to the active result and resets the panel state', () {
    final jumpedIds = <String>[];
    final controller = WorkspaceSearchController(
      entriesBuilder: () => const <WorkspaceSearchResult>[
        WorkspaceSearchResult(
          id: 'pane-1',
          tabIndex: 0,
          tabId: 1,
          tabTitle: 'Alpha',
          paneId: 1,
          paneOrdinal: 0,
          cwd: '/tmp/alpha',
          status: LocalShellStatus.running,
          exitCode: null,
          isActiveTab: true,
          isActivePane: true,
        ),
      ],
      jumpToResult: (result) {
        jumpedIds.add(result.id);
      },
    );
    addTearDown(controller.dispose);

    controller.open();
    controller.chooseActiveResult();

    expect(jumpedIds, <String>['pane-1']);
    expect(controller.isOpen, isFalse);
    expect(controller.query, isEmpty);
  });
}

TerminalTabsController _tabs(_FakePtySessionBackend backend) {
  final settingsDir = Directory.systemTemp.createTempSync(
    'ianvs_workspace_search_settings_',
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
  );
}

class _FakeClipboardClient implements ClipboardClient {
  @override
  Future<String> readText() async => '';

  @override
  Future<void> writeText(String text) async {}
}

class _FakePtySessionBackend implements PtySessionBackend {
  int _createCount = 0;
  final Map<String, Queue<PtyEvent>> _queuedEvents =
      <String, Queue<PtyEvent>>{};

  @override
  int ping() => 42;

  @override
  String createSession(String sessionConfigJson) {
    _createCount += 1;
    return 'session-$_createCount';
  }

  @override
  void closeSession(String sessionId) {}

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

class _TestNotifier extends ChangeNotifier {
  void ping() {
    notifyListeners();
  }
}
