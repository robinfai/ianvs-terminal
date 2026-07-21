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
      final persisted =
          jsonDecode(
                File(
                  '${directory.path}/ianvs_workspace_layout.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(persisted['schemaVersion'], currentTerminalWorkspaceSchemaVersion);
    });

    test(
      'persists project workspaces independently and orders recents',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-workspace-collection',
        );
        var now = DateTime.utc(2026, 7, 21, 5);
        final repository = LocalWorkspaceRepository(
          directoryResolver: () async => directory,
          now: () => now,
        );

        final first = await repository.openProject(
          projectPath: '/projects/one',
        );
        await repository.save(first.addTab(_tab('first')));
        now = DateTime.utc(2026, 7, 21, 6);
        final second = await repository.openProject(
          projectPath: '/projects/two/',
          name: 'Second Project',
        );
        await repository.save(second.addTab(_tab('second')));

        expect((await repository.load())!.identity, second.identity);
        expect(
          (await repository.loadWorkspace(first.identity.id))!.activeTabId,
          'first',
        );
        expect(
          (await repository.loadWorkspace(second.identity.id))!.activeTabId,
          'second',
        );
        expect(
          (await repository.loadRecent()).map((entry) => entry.identity.id),
          [second.identity.id, first.identity.id],
        );

        now = DateTime.utc(2026, 7, 21, 7);
        final reopened = await repository.openWorkspace(first.identity.id);
        expect(reopened!.identity, first.identity);
        expect(
          (await repository.loadRecent()).map((entry) => entry.identity.id),
          [first.identity.id, second.identity.id],
        );
      },
    );

    test(
      'project preparation does not activate until explicitly committed',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-workspace-prepare-project',
        );
        final repository = LocalWorkspaceRepository(
          directoryResolver: () async => directory,
          now: () => DateTime.utc(2026, 7, 21, 8),
        );
        final current = await repository.openProject(
          projectPath: '/projects/current',
        );

        final prepared = await repository.loadOrCreateProject(
          projectPath: '/projects/prepared',
        );

        expect((await repository.load())!.identity, current.identity);
        expect(
          (await repository.loadRecent()).map((entry) => entry.identity.id),
          <String>[current.identity.id],
        );
        expect(
          (await repository.loadWorkspace(prepared.identity.id))!.identity,
          prepared.identity,
        );

        await repository.activateWorkspace(prepared);

        expect((await repository.load())!.identity, prepared.identity);
        expect(
          (await repository.loadRecent()).map((entry) => entry.identity.id),
          <String>[prepared.identity.id, current.identity.id],
        );
      },
    );

    test('migrates an unversioned layout and rewrites it as current', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-workspace-legacy',
      );
      final file = File('${directory.path}/ianvs_workspace_layout.json');
      await file.writeAsString(
        jsonEncode({
          'activeTabId': 'tab-1',
          'tabs': [
            {
              'id': 'tab-1',
              'activePaneId': 'pane-1',
              'root': {
                'id': 'pane-1',
                'type': 'leaf',
                'sessionIntent': {
                  'profileId': 'default',
                  'cwd': '/legacy-repo',
                },
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
      expect(loaded!.schemaVersion, currentTerminalWorkspaceSchemaVersion);
      expect(loaded.identity, TerminalWorkspaceIdentity.defaultWorkspace);
      expect(loaded.activeTab!.activeSessionIntent!.cwd, '/legacy-repo');
      final migrated = jsonDecode(await file.readAsString());
      expect(
        (migrated as Map<String, Object?>)['schemaVersion'],
        currentTerminalWorkspaceSchemaVersion,
      );
      final migratedLeaf =
          ((migrated['tabs'] as List<Object?>).single
                  as Map<String, Object?>)['root']
              as Map<String, Object?>;
      expect(migratedLeaf, contains('sessionDescriptor'));
      expect(migratedLeaf, isNot(contains('sessionIntent')));
      expect(
        File('${directory.path}/ianvs_workspace_index.json').existsSync(),
        isTrue,
      );
      expect(
        Directory('${directory.path}/ianvs_workspaces').listSync(),
        hasLength(1),
      );
    });

    test(
      'migrates schema v1 session intent to the current descriptor',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-workspace-v1',
        );
        final file = File('${directory.path}/ianvs_workspace_layout.json');
        await file.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'activeTabId': 'tab-1',
            'tabs': [
              {
                'id': 'tab-1',
                'activePaneId': 'pane-1',
                'root': {
                  'id': 'pane-1',
                  'type': 'leaf',
                  'sessionIntent': {
                    'profileId': 'default',
                    'cwd': '/legacy-repo',
                  },
                },
              },
            ],
          }),
        );
        final repository = LocalWorkspaceRepository(
          directoryResolver: () async => directory,
        );

        final loaded = await repository.load();

        final descriptor = loaded!.activeTab!.activeSessionDescriptor!;
        expect(descriptor.id, 'pane-1');
        expect(descriptor.profileId, 'default');
        expect(descriptor.cwd, '/legacy-repo');
        expect(descriptor.restartPolicy, TerminalSessionRestartPolicy.relaunch);
        final migrated =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        expect(
          migrated['schemaVersion'],
          currentTerminalWorkspaceSchemaVersion,
        );
        final migratedLeaf =
            ((migrated['tabs'] as List<Object?>).single
                    as Map<String, Object?>)['root']
                as Map<String, Object?>;
        final descriptorJson =
            migratedLeaf['sessionDescriptor'] as Map<String, Object?>;
        expect(
          descriptorJson['schemaVersion'],
          currentTerminalSessionDescriptorVersion,
        );
        expect(descriptorJson['id'], 'pane-1');
      },
    );

    test('preserves a workspace written by a newer schema', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-workspace-future',
      );
      final file = File('${directory.path}/ianvs_workspace_layout.json');
      final futureDocument = jsonEncode({
        'schemaVersion': currentTerminalWorkspaceSchemaVersion + 1,
        'tabs': const <Object?>[],
      });
      await file.writeAsString(futureDocument);
      final repository = LocalWorkspaceRepository(
        directoryResolver: () async => directory,
      );

      await expectLater(
        repository.load(),
        throwsA(isA<UnsupportedTerminalWorkspaceSchemaVersion>()),
      );

      expect(await file.readAsString(), futureDocument);
      expect(
        directory.listSync().any((entry) => entry.path.contains('.corrupt')),
        isFalse,
      );
    });

    test('preserves a workspace with a newer descriptor schema', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-workspace-future-descriptor',
      );
      final file = File('${directory.path}/ianvs_workspace_layout.json');
      final futureDocument = jsonEncode({
        'schemaVersion': currentTerminalWorkspaceSchemaVersion,
        'tabs': [
          {
            'id': 'tab-1',
            'activePaneId': 'pane-1',
            'root': {
              'id': 'pane-1',
              'type': 'leaf',
              'sessionDescriptor': {
                'schemaVersion': currentTerminalSessionDescriptorVersion + 1,
                'id': 'descriptor-1',
                'profileId': 'default',
              },
            },
          },
        ],
      });
      await file.writeAsString(futureDocument);
      final repository = LocalWorkspaceRepository(
        directoryResolver: () async => directory,
      );

      await expectLater(
        repository.load(),
        throwsA(isA<UnsupportedTerminalSessionDescriptorVersion>()),
      );

      expect(await file.readAsString(), futureDocument);
      expect(
        directory.listSync().any((entry) => entry.path.contains('.corrupt')),
        isFalse,
      );
    });

    test('preserves an index written by a newer schema', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-workspace-future-index',
      );
      final file = File('${directory.path}/ianvs_workspace_index.json');
      final futureDocument = jsonEncode({
        'schemaVersion': currentTerminalWorkspaceIndexSchemaVersion + 1,
        'recent': const <Object?>[],
      });
      await file.writeAsString(futureDocument);
      final repository = LocalWorkspaceRepository(
        directoryResolver: () async => directory,
      );

      await expectLater(
        repository.loadRecent(),
        throwsA(isA<UnsupportedTerminalWorkspaceIndexSchemaVersion>()),
      );

      expect(await file.readAsString(), futureDocument);
      expect(
        directory.listSync().any((entry) => entry.path.contains('.corrupt')),
        isFalse,
      );
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

TerminalWorkspaceTab _tab(String id) {
  final paneId = 'pane-$id';
  return TerminalWorkspaceTab(
    id: id,
    activePaneId: paneId,
    root: TerminalPaneNode.leaf(
      id: paneId,
      sessionDescriptor: TerminalSessionDescriptor(
        id: 'descriptor-$id',
        profileId: 'default',
      ),
    ),
  );
}
