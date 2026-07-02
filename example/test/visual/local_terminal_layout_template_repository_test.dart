import 'dart:convert';
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
          id: 'two-pane',
          name: 'Duplicate Two Pane',
          paneCount: 1,
          localOnly: true,
        ),
        LocalTerminalLayoutTemplate(
          id: '   ',
          name: 'Blank',
          paneCount: 2,
          localOnly: true,
        ),
        LocalTerminalLayoutTemplate(
          id: 'remote',
          name: 'Remote',
          paneCount: 2,
          localOnly: false,
        ),
        LocalTerminalLayoutTemplate(
          id: 'three-pane',
          name: 'Three Pane',
          paneCount: 3,
          localOnly: true,
        ),
      ]);
      final loaded = await repository.load();
      final raw =
          jsonDecode(
                await File(
                  '${directory.path}/ianvs_layout_templates.json',
                ).readAsString(),
              )
              as List<dynamic>;

      expect(raw, hasLength(1));
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'two-pane');
      expect(loaded.single.canApply, isTrue);
    });

    test('caps persisted local-only templates', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-layout-templates-capped',
      );
      final repository = LocalTerminalLayoutTemplateRepository(
        directoryResolver: () async => directory,
      );

      await repository.save([
        for (
          var index = 0;
          index < maxLocalTerminalLayoutTemplates + 2;
          index += 1
        )
          LocalTerminalLayoutTemplate(
            id: 'template-$index',
            name: 'Template $index',
            paneCount: 2,
            localOnly: true,
          ),
      ]);
      final loaded = await repository.load();
      final raw =
          jsonDecode(
                await File(
                  '${directory.path}/ianvs_layout_templates.json',
                ).readAsString(),
              )
              as List<dynamic>;

      expect(raw, hasLength(maxLocalTerminalLayoutTemplates));
      expect(loaded, hasLength(maxLocalTerminalLayoutTemplates));
      expect(loaded.first.id, 'template-0');
      expect(loaded.last.id, 'template-${maxLocalTerminalLayoutTemplates - 1}');
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
          (entry) => entry.path.contains('ianvs_layout_templates.json.corrupt'),
        ),
        isTrue,
      );
    });

    test('skips malformed template entries without quarantine', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-layout-templates-invalid-entries',
      );
      final file = File('${directory.path}/ianvs_layout_templates.json');
      await file.writeAsString(
        jsonEncode([
          'not a template',
          {'id': '   ', 'name': 'Blank', 'paneCount': 2, 'localOnly': true},
          {
            'id': 'missing-name',
            'name': '   ',
            'paneCount': 2,
            'localOnly': true,
          },
          {
            'id': 'bad-local-flag',
            'name': 'Bad local flag',
            'paneCount': 2,
            'localOnly': 'true',
          },
          {
            'id': ' two-pane ',
            'name': ' Two Pane ',
            'paneCount': 2.0,
            'localOnly': true,
          },
        ]),
      );
      final repository = LocalTerminalLayoutTemplateRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'two-pane');
      expect(loaded.single.name, 'Two Pane');
      expect(loaded.single.paneCount, 2);
      expect(loaded.single.canApply, isTrue);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_layout_templates.json.corrupt'),
        ),
        isFalse,
      );
    });

    test('limits persisted layout template scans without quarantine', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-layout-templates-bounded-load',
      );
      final file = File('${directory.path}/ianvs_layout_templates.json');
      await file.writeAsString(
        jsonEncode([
          for (
            var index = 0;
            index < maxLocalTerminalLayoutTemplates * 4 + 1;
            index += 1
          )
            'not-a-template-$index',
          const LocalTerminalLayoutTemplate(
            id: 'too-late',
            name: 'Too Late',
            paneCount: 2,
            localOnly: true,
          ).toJson(),
        ]),
      );
      final repository = LocalTerminalLayoutTemplateRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, isEmpty);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_layout_templates.json.corrupt'),
        ),
        isFalse,
      );
    });

    test('skips duplicate template ids without quarantine', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-layout-templates-duplicate-ids',
      );
      final file = File('${directory.path}/ianvs_layout_templates.json');
      await file.writeAsString(
        jsonEncode([
          {
            'id': ' two-pane ',
            'name': 'Two Pane',
            'paneCount': 2,
            'localOnly': true,
          },
          {
            'id': 'two-pane',
            'name': 'Duplicate Two Pane',
            'paneCount': 1,
            'localOnly': true,
          },
          {
            'id': 'single-pane',
            'name': 'Single Pane',
            'paneCount': 1,
            'localOnly': true,
          },
        ]),
      );
      final repository = LocalTerminalLayoutTemplateRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(
        loaded.map((template) => template.name).toList(growable: false),
        const ['Two Pane', 'Single Pane'],
      );
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_layout_templates.json.corrupt'),
        ),
        isFalse,
      );
    });
  });
}
