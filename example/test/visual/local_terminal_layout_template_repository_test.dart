import 'dart:io';

import 'package:app/features/visual/local_terminal_layout_template_repository.dart';
import 'package:app/features/visual/local_terminal_visual_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal layout template repository', () {
    test('returns empty list when template file is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-layout-templates-missing',
      );
      final repository = LocalTerminalLayoutTemplateRepository(
        directoryResolver: () async => directory,
      );

      expect(await repository.load(), isEmpty);
    });

    test('persists local-only templates', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-layout-templates-roundtrip',
      );
      final repository = LocalTerminalLayoutTemplateRepository(
        directoryResolver: () async => directory,
      );

      await repository.save(const [
        LocalTerminalLayoutTemplate(
          id: 'two-pane',
          name: 'Two Pane',
          paneCount: 2,
          localOnly: true,
        ),
        LocalTerminalLayoutTemplate(
          id: 'remote',
          name: 'Remote',
          paneCount: 2,
          localOnly: false,
        ),
      ]);
      final loaded = await repository.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'two-pane');
      expect(loaded.single.canApply, isTrue);
    });

    test('quarantines corrupt template file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-layout-templates-corrupt',
      );
      final file = File('${directory.path}/ianvs_layout_templates.json');
      await file.writeAsString('{bad json');
      final repository = LocalTerminalLayoutTemplateRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, isEmpty);
      expect(
        directory.listSync().any(
          (entry) =>
              entry.path.contains('ianvs_layout_templates.json.corrupt'),
        ),
        isTrue,
      );
    });
  });
}
