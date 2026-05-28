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
  });
}
