import 'dart:convert';
import 'dart:io';

import 'package:app/features/visual/local_terminal_scrollback_exporter.dart';
import 'package:app/features/visual/local_terminal_visual_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal scrollback exporter', () {
    test('writes plain text export', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-scrollback-export',
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

    test('does not overwrite an existing export file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-scrollback-collision',
      );
      addTearDown(() => directory.delete(recursive: true));
      final existing = File('${directory.path}/session.txt');
      await existing.writeAsString('previous export');

      final file = await LocalTerminalScrollbackExporter.write(
        directory: directory,
        basename: 'session',
        export: const LocalTerminalScrollbackExport(
          format: LocalTerminalExportFormat.plainText,
          content: 'new export',
        ),
        policy: const LocalTerminalScrollbackExportPolicy(),
      );

      expect(file.path, contains('session-1.txt'));
      expect(await file.readAsString(), 'new export');
      expect(await existing.readAsString(), 'previous export');
    });

    test('writes json export with metadata', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-scrollback-json',
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

    test('bounds json export metadata to encodable values', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-scrollback-json-metadata',
      );
      addTearDown(() => directory.delete(recursive: true));

      final file = await LocalTerminalScrollbackExporter.write(
        directory: directory,
        basename: 'session',
        export: LocalTerminalScrollbackExport(
          format: LocalTerminalExportFormat.json,
          content: 'hello',
          metadata: <String, Object?>{
            'badNumber': double.infinity,
            'badObject': DateTime(2026, 5, 31),
            'nullable': null,
            'longString': ' ${'x' * 5000} ',
            'list': <Object?>[
              for (var index = 0; index < 24; index += 1)
                ' ${index.toString().padLeft(2, '0')}-${'y' * 5000} ',
            ],
            'nested': <Object?, Object?>{
              for (var index = 0; index < 40; index += 1)
                ' nested-$index ': ' ${'z' * 5000} ',
            },
          },
        ),
        policy: const LocalTerminalScrollbackExportPolicy(),
      );

      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final metadata = json['metadata']! as Map<String, Object?>;
      final list = metadata['list']! as List<Object?>;
      final nested = metadata['nested']! as Map<String, Object?>;

      expect(json['content'], 'hello');
      expect(metadata.containsKey('badNumber'), isFalse);
      expect(metadata.containsKey('badObject'), isFalse);
      expect(metadata, containsPair('nullable', null));
      expect(metadata['longString']! as String, hasLength(4096));
      expect(list, hasLength(20));
      expect(list.first! as String, hasLength(4096));
      expect(nested, hasLength(32));
      expect(nested.keys.first, 'nested-0');
      expect(nested.values.first! as String, hasLength(4096));
    });

    test('scans json export metadata past invalid prefixes', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-scrollback-json-metadata-scan',
      );
      addTearDown(() => directory.delete(recursive: true));

      final file = await LocalTerminalScrollbackExporter.write(
        directory: directory,
        basename: 'session',
        export: LocalTerminalScrollbackExport(
          format: LocalTerminalExportFormat.json,
          content: 'hello',
          metadata: <String, Object?>{
            for (var index = 0; index < 34; index += 1)
              'invalid_$index': double.nan,
            'profileId': ' default ',
            'list': <Object?>[
              for (var index = 0; index < 22; index += 1) double.nan,
              ' recovered ',
            ],
            'nested': <Object?, Object?>{
              for (var index = 0; index < 34; index += 1) index: double.nan,
              ' key ': ' value ',
            },
          },
        ),
        policy: const LocalTerminalScrollbackExportPolicy(),
      );

      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final metadata = json['metadata']! as Map<String, Object?>;

      expect(metadata['profileId'], 'default');
      expect(metadata['list'], <String>['recovered']);
      expect(metadata['nested'], <String, Object?>{'key': 'value'});
      expect(metadata.containsKey('invalid_0'), isFalse);
    });

    test('sanitizes unsafe export basename inside target directory', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs terminal-scrollback-safe-name',
      );
      final directory = Directory('${root.path}/exports');

      final file = await LocalTerminalScrollbackExporter.write(
        directory: directory,
        basename: '../escaped/session:name',
        export: const LocalTerminalScrollbackExport(
          format: LocalTerminalExportFormat.plainText,
          content: 'hello',
        ),
        policy: const LocalTerminalScrollbackExportPolicy(),
      );

      final directoryPath = await directory.resolveSymbolicLinks();
      final filePath = await file.resolveSymbolicLinks();
      expect(filePath, startsWith('$directoryPath${Platform.pathSeparator}'));
      expect(file.path, contains('..-escaped-session-name.txt'));
      expect(File('${root.path}/escaped.txt').existsSync(), isFalse);
    });

    test('truncates long export basenames to a writable file name', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-scrollback-long-name',
      );
      addTearDown(() => directory.delete(recursive: true));

      final file = await LocalTerminalScrollbackExporter.write(
        directory: directory,
        basename: 'session-${List.filled(400, 'a').join()}',
        export: const LocalTerminalScrollbackExport(
          format: LocalTerminalExportFormat.plainText,
          content: 'hello',
        ),
        policy: const LocalTerminalScrollbackExportPolicy(),
      );

      final filename = file.uri.pathSegments.last;
      expect(filename.length, lessThanOrEqualTo(124));
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), 'hello');
    });

    test('rejects disabled export policy', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-scrollback-disabled',
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
