import 'dart:convert';
import 'dart:io';

import 'package:app/features/workspace/local_terminal_layout_models.dart';
import 'package:app/features/workspace/local_terminal_layout_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalTerminalLayoutRepository', () {
    test('returns null when no current or legacy layout exists', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-terminal-layout-missing',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = _repository(directory);

      expect(await repository.load(), isNull);
    });

    test('persists one local layout without project identity', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-terminal-layout-roundtrip',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = _repository(directory);
      final layout = const TerminalLayout().addTab(_tab('tab-1', '/repo'));

      await repository.save(layout);
      final loaded = await repository.load();

      expect(loaded!.activeTabId, 'tab-1');
      expect(loaded.activeTab!.activeRelaunchSpec!.cwd, '/repo');
      final persisted =
          jsonDecode(
                await File(
                  '${directory.path}/ianvs_terminal_layout.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      expect(persisted['schemaVersion'], currentTerminalLayoutSchemaVersion);
      expect(persisted['contract'], terminalLayoutContract);
      expect(persisted, isNot(contains('id')));
      expect(persisted, isNot(contains('name')));
      expect(persisted, isNot(contains('projectPath')));
      expect(
        File('${directory.path}/ianvs_workspace_index.json').existsSync(),
        isFalse,
      );
      expect(
        Directory('${directory.path}/ianvs_workspaces').existsSync(),
        isFalse,
      );
    });

    test('migrates the legacy alias once and leaves it unchanged', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-terminal-layout-legacy-alias',
      );
      addTearDown(() => directory.delete(recursive: true));
      final legacyFile = File('${directory.path}/ianvs_workspace_layout.json');
      final legacyPayload = jsonEncode(_legacyLayout('/legacy-repo'));
      await legacyFile.writeAsString(legacyPayload);

      final loaded = await _repository(directory).load();

      expect(loaded!.activeTab!.activeRelaunchSpec!.cwd, '/legacy-repo');
      expect(await legacyFile.readAsString(), legacyPayload);
      final currentFile = File('${directory.path}/ianvs_terminal_layout.json');
      final current =
          jsonDecode(await currentFile.readAsString()) as Map<String, Object?>;
      expect(current['contract'], terminalLayoutContract);
      expect(current.toString(), isNot(contains('projectPath')));
      expect(current.toString(), isNot(contains('recordingPath')));
      expect(current.toString(), isNot(contains('secret-value')));
    });

    test('migrates the current entry from the legacy collection', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-terminal-layout-legacy-collection',
      );
      addTearDown(() => directory.delete(recursive: true));
      const workspaceId = 'project-legacy';
      final encodedId = base64Url
          .encode(utf8.encode(workspaceId))
          .replaceAll('=', '');
      await File('${directory.path}/ianvs_workspace_index.json').writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'currentWorkspaceId': workspaceId,
          'recent': <Object?>[
            <String, Object?>{'id': workspaceId},
          ],
        }),
      );
      final collectionFile = File(
        '${directory.path}/ianvs_workspaces/workspace-$encodedId.json',
      );
      await collectionFile.parent.create(recursive: true);
      await collectionFile.writeAsString(jsonEncode(_legacyLayout('/project')));

      final loaded = await _repository(directory).load();

      expect(loaded!.activeTab!.activeRelaunchSpec!.cwd, '/project');
      expect(collectionFile.existsSync(), isTrue);
      expect(
        File('${directory.path}/ianvs_terminal_layout.json').existsSync(),
        isTrue,
      );
    });

    test(
      'quarantines malformed current layout and writes an empty repair',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs-terminal-layout-corrupt',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/ianvs_terminal_layout.json');
        await file.writeAsString('{not json');

        final loaded = await _repository(directory).load();

        expect(loaded, isNotNull);
        expect(loaded!.isEmpty, isTrue);
        expect(
          directory.listSync().where(
            (entry) =>
                entry.path.contains('ianvs_terminal_layout.json.corrupt'),
          ),
          hasLength(1),
        );
        final repaired =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        expect(repaired['contract'], terminalLayoutContract);
      },
    );

    test('does not overwrite a layout written by a future version', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-terminal-layout-future',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/ianvs_terminal_layout.json');
      const futurePayload =
          '{"schemaVersion":99,"contract":"future-layout","tabs":[]}';
      await file.writeAsString(futurePayload);

      expect(
        () => _repository(directory).load(),
        throwsA(isA<UnsupportedTerminalLayoutSchemaVersion>()),
      );
      expect(await file.readAsString(), futurePayload);
      expect(
        directory.listSync().where((entry) => entry.path.contains('.corrupt')),
        isEmpty,
      );
    });
  });
}

LocalTerminalLayoutRepository _repository(Directory directory) {
  return LocalTerminalLayoutRepository(
    directoryResolver: () async => directory,
  );
}

TerminalLayoutTab _tab(String id, String cwd) {
  final paneId = 'pane-$id';
  return TerminalLayoutTab(
    id: id,
    activePaneId: paneId,
    root: TerminalPaneNode.leaf(
      id: paneId,
      relaunchSpec: TerminalRelaunchSpec(profileId: 'default', cwd: cwd),
    ),
  );
}

Map<String, Object?> _legacyLayout(String cwd) {
  return <String, Object?>{
    'schemaVersion': 3,
    'id': 'project-legacy',
    'name': 'Legacy Project',
    'projectPath': '/legacy/project',
    'activeTabId': 'tab-1',
    'tabs': <Object?>[
      <String, Object?>{
        'id': 'tab-1',
        'activePaneId': 'pane-1',
        'root': <String, Object?>{
          'id': 'pane-1',
          'type': 'leaf',
          'sessionDescriptor': <String, Object?>{
            'schemaVersion': 1,
            'id': 'descriptor-1',
            'profileId': 'default',
            'cwd': cwd,
            'title': 'Legacy title',
            'environment': <String, Object?>{
              'keys': <String>['TOKEN'],
              'values': <String, String>{'TOKEN': 'secret-value'},
            },
            'recordingPath': '/recordings/legacy.ndjson',
          },
        },
      },
    ],
  };
}
