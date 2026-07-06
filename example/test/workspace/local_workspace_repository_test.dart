import 'dart:convert';
import 'dart:io';

import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:app/features/workspace/local_workspace_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local workspace repository', () {
    test('returns null when layout file is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-workspace-missing',
      );
      final repository = LocalWorkspaceRepository(
        directoryResolver: () async => directory,
      );

      expect(await repository.load(), isNull);
    });

    test('persists local-only workspace layout', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-workspace-roundtrip',
      );
      final repository = LocalWorkspaceRepository(
        directoryResolver: () async => directory,
      );
      final workspace = const TerminalWorkspace().addTab(
        TerminalWorkspaceTab(
          id: 'tab-1',
          activePaneId: 'pane-1',
          root: TerminalPaneNode.leaf(
            id: 'pane-1',
            sessionIntent: const TerminalPaneSessionIntent(
              profileId: 'default',
              cwd: '/repo',
            ),
          ),
        ),
      );

      await repository.save(workspace);
      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.activeTabId, 'tab-1');
      expect(loaded.activeTab!.activeSessionIntent!.cwd, '/repo');
    });

    test(
      'quarantines corrupt layout and writes repaired empty layout',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-workspace-corrupt',
        );
        final file = File('${directory.path}/ianvs_workspace_layout.json');
        await file.writeAsString('{bad json');
        final repository = LocalWorkspaceRepository(
          directoryResolver: () async => directory,
        );

        final loaded = await repository.load();

        expect(loaded, isNotNull);
        expect(loaded!.isEmpty, isTrue);
        expect(
          directory.listSync().any(
            (entry) =>
                entry.path.contains('ianvs_workspace_layout.json.corrupt'),
          ),
          isTrue,
        );
      },
    );

    test(
      'defaults invalid primitive layout fields without quarantine',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-workspace-invalid-primitives',
        );
        final file = File('${directory.path}/ianvs_workspace_layout.json');
        await file.writeAsString(
          jsonEncode({
            'activeTabId': 7,
            'tabs': [
              {
                'id': 42,
                'activePaneId': 9,
                'zoomedPaneId': false,
                'root': {
                  'id': 'split-1',
                  'type': 'split',
                  'direction': 'down',
                  'ratio': 'wide',
                  'children': [
                    {
                      'id': 'pane-1',
                      'type': 'leaf',
                      'sessionIntent': {'profileId': 'default', 'cwd': 99},
                    },
                    {
                      'id': 'pane-2',
                      'type': 'leaf',
                      'sessionIntent': {'profileId': 404, 'cwd': '/repo'},
                    },
                  ],
                },
              },
            ],
          }),
        );
        final repository = LocalWorkspaceRepository(
          directoryResolver: () async => directory,
        );

        final loaded = await repository.load();

        expect(loaded, isNotNull);
        expect(loaded!.activeTabId, 'tab-1');
        expect(loaded.tabs, hasLength(1));
        final tab = loaded.tabs.single;
        expect(tab.id, 'tab-1');
        expect(tab.activePaneId, 'pane-1');
        expect(tab.zoomedPaneId, isNull);
        expect(tab.root.direction, TerminalPaneSplitDirection.down);
        expect(tab.root.ratio, 0.5);
        expect(tab.root.children.first.sessionIntent?.profileId, 'default');
        expect(tab.root.children.first.sessionIntent?.cwd, isNull);
        expect(tab.root.children.last.id, 'pane-2');
        expect(tab.root.children.last.sessionIntent?.profileId, '');
        expect(tab.root.children.last.sessionIntent?.cwd, '/repo');
        expect(
          directory.listSync().any(
            (entry) =>
                entry.path.contains('ianvs_workspace_layout.json.corrupt'),
          ),
          isFalse,
        );
      },
    );
  });
}
