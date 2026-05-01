import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ianvs_terminal/src/session_restore.dart';
import 'package:ianvs_terminal/src/terminal_panes.dart';

void main() {
  test('store returns empty state when file is missing', () {
    final dir = Directory.systemTemp.createTempSync('ianvs_restore_missing_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    final store = TerminalSessionRestoreStore(
      file: File('${dir.path}/session_restore.json'),
    );

    expect(store.load().tabs, isEmpty);
    expect(store.load().activeTabIndex, 0);
  });

  test('store saves and reloads tabs panes active state and cwd', () {
    final dir = Directory.systemTemp.createTempSync('ianvs_restore_save_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    final store = TerminalSessionRestoreStore(
      file: File('${dir.path}/session_restore.json'),
    );
    final state = TerminalSessionRestoreState(
      activeTabIndex: 1,
      tabs: <TerminalSessionRestoreTab>[
        TerminalSessionRestoreTab(
          fallbackTitle: 'Local 1',
          activePaneId: 2,
          rootPane: TerminalSessionRestorePaneSplit(
            direction: TerminalPaneSplitDirection.right,
            ratio: 0.65,
            first: const TerminalSessionRestorePaneLeaf(id: 1, cwd: '/tmp/one'),
            second: const TerminalSessionRestorePaneLeaf(
              id: 2,
              cwd: '/tmp/two',
            ),
          ),
        ),
        const TerminalSessionRestoreTab(
          fallbackTitle: 'Local 2',
          activePaneId: 3,
          rootPane: TerminalSessionRestorePaneLeaf(id: 3, cwd: '/tmp/three'),
        ),
      ],
    );

    store.save(state);
    final reloaded = store.load();

    expect(reloaded.activeTabIndex, 1);
    expect(reloaded.tabs.length, 2);
    expect(reloaded.tabs.first.fallbackTitle, 'Local 1');
    expect(reloaded.tabs.first.activePaneId, 2);
    final split =
        reloaded.tabs.first.rootPane as TerminalSessionRestorePaneSplit;
    expect(split.direction, TerminalPaneSplitDirection.right);
    expect(split.ratio, 0.65);
    expect((split.first as TerminalSessionRestorePaneLeaf).cwd, '/tmp/one');
    expect((split.second as TerminalSessionRestorePaneLeaf).cwd, '/tmp/two');
  });

  test('bad json empty tabs and invalid fields fall back safely', () {
    final dir = Directory.systemTemp.createTempSync('ianvs_restore_bad_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    final file = File('${dir.path}/session_restore.json');
    final store = TerminalSessionRestoreStore(file: file);

    file
      ..createSync(recursive: true)
      ..writeAsStringSync('{not json');
    expect(store.load().tabs, isEmpty);

    final parsedEmpty = TerminalSessionRestoreState.fromJson(<String, Object?>{
      'activeTabIndex': 99,
      'tabs': <Object?>[],
    });
    expect(parsedEmpty.tabs, isEmpty);
    expect(parsedEmpty.activeTabIndex, 0);

    final parsedInvalid = TerminalSessionRestoreState.fromJson(
      <String, Object?>{
        'activeTabIndex': 0,
        'tabs': <Object?>[
          <String, Object?>{
            'fallbackTitle': '',
            'activePaneId': 42,
            'rootPane': <String, Object?>{
              'type': 'split',
              'direction': 'down',
              'ratio': 9,
              'first': <String, Object?>{'type': 'leaf', 'id': 7},
              'second': <String, Object?>{
                'type': 'leaf',
                'id': 8,
                'cwd': '/tmp/eight',
              },
            },
          },
        ],
      },
    );

    expect(parsedInvalid.tabs.single.fallbackTitle, 'Local 1');
    expect(parsedInvalid.tabs.single.activePaneId, 7);
    final split =
        parsedInvalid.tabs.single.rootPane as TerminalSessionRestorePaneSplit;
    expect(split.direction, TerminalPaneSplitDirection.down);
    expect(split.ratio, 0.5);
    expect((split.first as TerminalSessionRestorePaneLeaf).cwd, isEmpty);
  });

  test('restore reassigns duplicate pane ids globally', () {
    final parsed = TerminalSessionRestoreState.fromJson(<String, Object?>{
      'activeTabIndex': 1,
      'tabs': <Object?>[
        <String, Object?>{
          'fallbackTitle': 'Local 1',
          'activePaneId': 1,
          'rootPane': <String, Object?>{
            'type': 'split',
            'first': <String, Object?>{'type': 'leaf', 'id': 1},
            'second': <String, Object?>{'type': 'leaf', 'id': 1},
          },
        },
        <String, Object?>{
          'fallbackTitle': 'Local 2',
          'activePaneId': 1,
          'rootPane': <String, Object?>{'type': 'leaf', 'id': 1},
        },
      ],
    });

    final firstSplit =
        parsed.tabs.first.rootPane as TerminalSessionRestorePaneSplit;
    final paneIds = parsed.tabs
        .expand((tab) => tab.rootPane.leaves)
        .map((leaf) => leaf.id)
        .toList(growable: false);

    expect(paneIds, <int>[1, 2, 3]);
    expect(paneIds.toSet().length, paneIds.length);
    expect(parsed.tabs.first.activePaneId, 1);
    expect((firstSplit.second as TerminalSessionRestorePaneLeaf).id, 2);
    expect(parsed.tabs.last.activePaneId, 3);
  });

  test('controller debounces repeated saves', () async {
    final store = TerminalSessionRestoreStore.memory();
    final controller = TerminalSessionRestoreController(
      store: store,
      debounceDuration: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    controller.scheduleSave(_stateWithCwd('/tmp/one'));
    controller.scheduleSave(_stateWithCwd('/tmp/two'));
    controller.scheduleSave(_stateWithCwd('/tmp/three'));

    expect(store.saveCount, 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(store.saveCount, 1);
    final leaf =
        store.load().tabs.single.rootPane as TerminalSessionRestorePaneLeaf;
    expect(leaf.cwd, '/tmp/three');
  });

  test('default restore path keeps platform-specific storage boundaries', () {
    expect(
      defaultSessionRestoreFilePath(
        environment: const <String, String>{'HOME': '/Users/robin'},
        operatingSystem: 'macos',
        currentPath: '/workspace',
      ),
      '/Users/robin/Library/Application Support/Ianvs/ianvs-terminal/session_restore.json',
    );
    expect(
      defaultSessionRestoreFilePath(
        environment: const <String, String>{
          'APPDATA': r'C:\Users\Robin\AppData\Roaming',
        },
        operatingSystem: 'windows',
        currentPath: r'C:\workspace',
      ),
      r'C:\Users\Robin\AppData\Roaming\Ianvs\ianvs-terminal\session_restore.json',
    );
    expect(
      defaultSessionRestoreFilePath(
        environment: const <String, String>{'HOME': '/home/robin'},
        operatingSystem: 'linux',
        currentPath: '/workspace',
      ),
      '/home/robin/.local/state/ianvs-terminal/session_restore.json',
    );
    expect(
      defaultSessionRestoreFilePath(
        environment: const <String, String>{
          'XDG_STATE_HOME': '/tmp/ianvs-state',
        },
        operatingSystem: 'linux',
        currentPath: '/workspace',
      ),
      '/tmp/ianvs-state/ianvs-terminal/session_restore.json',
    );
  });
}

TerminalSessionRestoreState _stateWithCwd(String cwd) {
  return TerminalSessionRestoreState(
    tabs: <TerminalSessionRestoreTab>[
      TerminalSessionRestoreTab(
        fallbackTitle: 'Local 1',
        activePaneId: 1,
        rootPane: TerminalSessionRestorePaneLeaf(id: 1, cwd: cwd),
      ),
    ],
  );
}
