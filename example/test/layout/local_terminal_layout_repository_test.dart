import 'dart:convert';
import 'dart:io';

import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalTerminalLayoutRepository', () {
    test('returns null when no current layout exists', () async {
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

    test('does not discover or mutate predecessor workspace files', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-terminal-layout-predecessor',
      );
      addTearDown(() => directory.delete(recursive: true));
      final predecessorFiles = <File>[
        File('${directory.path}/ianvs_workspace_layout.json'),
        File('${directory.path}/ianvs_workspace_index.json'),
        File('${directory.path}/ianvs_workspaces/workspace-ZGVmYXVsdA.json'),
      ];
      const payload = '{"schemaVersion":3,"tabs":[]}';
      for (final file in predecessorFiles) {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload);
      }

      expect(await _repository(directory).load(), isNull);
      for (final file in predecessorFiles) {
        expect(await file.readAsString(), payload);
      }
      expect(
        File('${directory.path}/ianvs_terminal_layout.json').existsSync(),
        isFalse,
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
