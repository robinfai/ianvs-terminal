import 'dart:io';

import 'package:app/features/visual/local_terminal_scrollback_exporter.dart';
import 'package:app/features/visual/local_terminal_visual_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal scrollback exporter', () {
    test('writes plain text export', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-scrollback-export',
      );

      final file = await LocalTerminalScrollbackExporter.write(
        directory: directory,
        basename: 'session',
        export: const LocalTerminalScrollbackExport(
          format: LocalTerminalExportFormat.plainText,
          content: 'hello',
        ),
        policy: const LocalTerminalScrollbackExportPolicy(),
      );

      expect(file.path, contains('session.txt'));
      expect(await file.readAsString(), 'hello');
    });

    test('writes json export with metadata', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-scrollback-json',
      );

      final file = await LocalTerminalScrollbackExporter.write(
        directory: directory,
        basename: 'session',
        export: const LocalTerminalScrollbackExport(
          format: LocalTerminalExportFormat.json,
          content: 'hello',
          metadata: {'profileId': 'default'},
        ),
        policy: const LocalTerminalScrollbackExportPolicy(),
      );

      final raw = await file.readAsString();
      expect(file.path, contains('session.json'));
      expect(raw, contains('profileId'));
      expect(raw, contains('hello'));
    });

    test('rejects disabled export policy', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-scrollback-disabled',
      );

      expect(
        () => LocalTerminalScrollbackExporter.write(
          directory: directory,
          basename: 'session',
          export: const LocalTerminalScrollbackExport(
            format: LocalTerminalExportFormat.plainText,
            content: 'hello',
          ),
          policy: const LocalTerminalScrollbackExportPolicy(enabled: false),
        ),
        throwsStateError,
      );
    });
  });
}
