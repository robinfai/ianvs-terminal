import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_library_graph.dart';

void main() {
  group(DartLibraryGraphScanner, () {
    late Directory fixtureDirectory;

    setUp(() {
      fixtureDirectory = Directory.systemTemp.createTempSync(
        'shell_architecture_test.',
      );
    });

    tearDown(() {
      if (fixtureDirectory.existsSync()) {
        fixtureDirectory.deleteSync(recursive: true);
      }
    });

    test('counts a part after it is migrated to a real import', () {
      _writeFixture(
        fixtureDirectory,
        'shell_screen.dart',
        "part 'shell_screen_feature.dart';\n",
      );
      _writeFixture(
        fixtureDirectory,
        'shell_screen_feature.dart',
        "part of 'shell_screen.dart';\nfinal value = 1;\n",
      );

      final partGraph = _fixtureScanner(fixtureDirectory).scan();
      expect(partGraph.files, hasLength(2));

      _writeFixture(
        fixtureDirectory,
        'shell_screen.dart',
        "import 'shell_screen_feature.dart';\n",
      );
      _writeFixture(
        fixtureDirectory,
        'shell_screen_feature.dart',
        'final value = 1;\n',
      );

      final libraryGraph = _fixtureScanner(fixtureDirectory).scan();
      expect(libraryGraph.files, hasLength(2));
      expect(
        libraryGraph.files,
        contains(
          File(
            '${fixtureDirectory.path}/shell_screen_feature.dart',
          ).resolveSymbolicLinksSync(),
        ),
      );
    });

    test('rejects an unregistered owned real library as an orphan', () {
      _writeFixture(fixtureDirectory, 'shell_screen.dart', 'void root() {}\n');
      _writeFixture(
        fixtureDirectory,
        'shell_screen_orphan.dart',
        'void orphan() {}\n',
      );

      expect(
        _fixtureScanner(fixtureDirectory).scan,
        throwsA(
          isA<DartLibraryGraphException>().having(
            (error) => error.message,
            'message',
            contains('orphaned'),
          ),
        ),
      );
    });

    test(
      'counts multiline conditional imports and recursive export chains',
      () {
        _writeFixture(fixtureDirectory, 'shell_screen.dart', """
import
  'shell_screen_default.dart'
  if (dart.library.io)
    'shell_screen_io.dart';
export
  'package:fixture/shell_screen_exports.dart';
""");
        _writeFixture(
          fixtureDirectory,
          'shell_screen_default.dart',
          'final target = "default";\n',
        );
        _writeFixture(
          fixtureDirectory,
          'shell_screen_io.dart',
          "export 'shell_screen_nested.dart';\n",
        );
        _writeFixture(
          fixtureDirectory,
          'shell_screen_exports.dart',
          'final exported = true;\n',
        );
        _writeFixture(
          fixtureDirectory,
          'shell_screen_nested.dart',
          'final nested = true;\n',
        );

        final graph = _fixtureScanner(fixtureDirectory).scan();

        expect(graph.files, hasLength(5));
        expect(graph.aggregateLineCount, equals(10));
      },
    );

    test('counts non-prefixed relative package and conditional libraries', () {
      _writeFixture(fixtureDirectory, 'shell_screen.dart', """
import 'relative_feature.dart';
export 'package:fixture/package_feature.dart';
import 'conditional_default.dart'
  if (dart.library.io) 'conditional_io.dart';
""");
      _writeFixture(
        fixtureDirectory,
        'relative_feature.dart',
        List<String>.filled(5000, 'final value = 1;').join('\n'),
      );
      _writeFixture(
        fixtureDirectory,
        'package_feature.dart',
        'final packageValue = true;\n',
      );
      _writeFixture(
        fixtureDirectory,
        'conditional_default.dart',
        'final conditionalValue = false;\n',
      );
      _writeFixture(
        fixtureDirectory,
        'conditional_io.dart',
        'final conditionalValue = true;\n',
      );

      final graph = _fixtureScanner(fixtureDirectory).scan();
      final largeFilePath = File(
        '${fixtureDirectory.path}/relative_feature.dart',
      ).resolveSymbolicLinksSync();

      expect(graph.files, hasLength(5));
      expect(graph.lineCounts[largeFilePath], equals(5000));
      expect(
        graph.lineCounts.entries.where((entry) => entry.value > 4100),
        isNotEmpty,
      );
    });

    test('counts LF CRLF and CR physical lines identically', () {
      for (final entry in <String, String>{
        'lf.dart': 'one\ntwo\nthree\n',
        'crlf.dart': 'one\r\ntwo\r\nthree\r\n',
        'cr.dart': 'one\rtwo\rthree\r',
      }.entries) {
        _writeFixture(fixtureDirectory, entry.key, entry.value);
      }
      _writeFixture(
        fixtureDirectory,
        'shell_screen.dart',
        "import 'lf.dart';\rimport 'crlf.dart';\r\nimport 'cr.dart';\n",
      );

      final graph = _fixtureScanner(fixtureDirectory).scan();

      for (final basename in const <String>[
        'lf.dart',
        'crlf.dart',
        'cr.dart',
      ]) {
        final path = File(
          '${fixtureDirectory.path}/$basename',
        ).resolveSymbolicLinksSync();
        expect(graph.lineCounts[path], equals(3), reason: basename);
      }
    });

    test('ignores metadata strings and finds the following directives', () {
      _writeFixture(fixtureDirectory, 'shell_screen.dart', """
@DirectiveMetadata(
  label: 'import not_a_directive.dart',
  values: <String>['export neither_is_this.dart', 'part nor_this.dart'],
)
import 'metadata_target.dart';
""");
      _writeFixture(
        fixtureDirectory,
        'metadata_target.dart',
        'final reached = true;\n',
      );

      final graph = _fixtureScanner(fixtureDirectory).scan();

      expect(graph.files, hasLength(2));
    });

    test(
      'counts a large library after generic named metadata designations',
      () {
        _writeFixture(fixtureDirectory, 'shell_screen.dart', '''
@DirectiveMetadata<String>.named(
  nested: <Object>[
    "import 'not_a_directive.dart';",
    <String, Object>{
      'part': r"part 'also_not_a_directive.dart';",
      'export': <String>["export 'still_not_a_directive.dart';"],
    },
  ],
)
@annotations.shell.Metadata<int>.named
import 'named_metadata_target.dart';
''');
        _writeFixture(
          fixtureDirectory,
          'named_metadata_target.dart',
          List<String>.filled(5000, 'final value = 1;').join('\n'),
        );

        final graph = _fixtureScanner(fixtureDirectory).scan();
        final targetPath = File(
          '${fixtureDirectory.path}/named_metadata_target.dart',
        ).resolveSymbolicLinksSync();

        expect(graph.files, hasLength(2));
        expect(graph.lineCounts[targetPath], equals(5000));
        expect(
          graph.lineCounts.entries.where((entry) => entry.value > 4100),
          isNotEmpty,
        );
      },
    );

    test('rejects a cross-directory dependency without an allowlist entry', () {
      final externalDirectory = Directory('${fixtureDirectory.path}_external')
        ..createSync();
      addTearDown(() {
        if (externalDirectory.existsSync()) {
          externalDirectory.deleteSync(recursive: true);
        }
      });
      _writeFixture(
        fixtureDirectory,
        'shell_screen.dart',
        "import '../${externalDirectory.path.split(Platform.pathSeparator).last}/shared.dart';\n",
      );
      _writeFixture(externalDirectory, 'shared.dart', 'final shared = true;\n');

      expect(
        _fixtureScanner(fixtureDirectory).scan,
        throwsA(
          isA<DartLibraryGraphException>().having(
            (error) => error.message,
            'message',
            contains('without an explicit allowlist entry'),
          ),
        ),
      );
    });

    test('rejects a missing local directive target', () {
      _writeFixture(
        fixtureDirectory,
        'shell_screen.dart',
        "import 'shell_screen_missing.dart';\n",
      );

      expect(
        _fixtureScanner(fixtureDirectory).scan,
        throwsA(
          isA<DartLibraryGraphException>().having(
            (error) => error.message,
            'message',
            contains('missing local file'),
          ),
        ),
      );
    });

    test('rejects duplicate local directive targets', () {
      _writeFixture(fixtureDirectory, 'shell_screen.dart', """
import 'shell_screen_feature.dart';
export 'shell_screen_feature.dart';
""");
      _writeFixture(
        fixtureDirectory,
        'shell_screen_feature.dart',
        'final feature = true;\n',
      );

      expect(
        _fixtureScanner(fixtureDirectory).scan,
        throwsA(
          isA<DartLibraryGraphException>().having(
            (error) => error.message,
            'message',
            contains('Duplicate local directive target'),
          ),
        ),
      );
    });

    test('counts each library once when import and export cycles exist', () {
      _writeFixture(
        fixtureDirectory,
        'shell_screen.dart',
        "import 'shell_screen_feature.dart';\n",
      );
      _writeFixture(
        fixtureDirectory,
        'shell_screen_feature.dart',
        "export 'shell_screen.dart';\n",
      );

      final graph = _fixtureScanner(fixtureDirectory).scan();

      expect(graph.files, hasLength(2));
      expect(graph.lineCounts, hasLength(2));
      expect(graph.cycles, hasLength(1));
    });

    test('rejects a part-of directive naming a different owner', () {
      _writeFixture(
        fixtureDirectory,
        'shell_screen.dart',
        "part 'shell_screen_feature.dart';\n",
      );
      _writeFixture(
        fixtureDirectory,
        'shell_screen_feature.dart',
        "part of 'different_owner.dart';\n",
      );

      expect(
        _fixtureScanner(fixtureDirectory).scan,
        throwsA(
          isA<DartLibraryGraphException>().having(
            (error) => error.message,
            'message',
            contains('does not name its declaring library'),
          ),
        ),
      );
    });
  });

  group('shell screen architecture budget', () {
    test('bounds the complete owned library graph without a part count', () {
      final shellScreen = _shellScreenFile();
      final scanner = DartLibraryGraphScanner(
        entrypoint: shellScreen,
        packageName: 'app',
        packageLibDirectory: shellScreen.parent.parent.parent,
        ownedDirectory: shellScreen.parent,
        orphanProtectedFiles: _orphanProtectedShellScreenFiles(
          shellScreen.parent,
        ),
        allowedExternalFiles: _allowedShellExternalDependencies(
          shellScreen.parent.parent.parent,
        ),
      );

      final graph = scanner.scan();
      final entryPath = shellScreen.resolveSymbolicLinksSync();
      final oversizedFiles = graph.lineCounts.entries
          .where((entry) => entry.value > 4100)
          .toList(growable: false);

      expect(graph.lineCounts[entryPath], lessThanOrEqualTo(1600));
      expect(
        oversizedFiles,
        isEmpty,
        reason:
            'No owned shell library or part may exceed 4,100 lines: '
            '$oversizedFiles',
      );
      expect(
        graph.aggregateLineCount,
        lessThanOrEqualTo(38300),
        reason: 'The complete reachable shell-owned library graph is bounded.',
      );
    });
  });
}

File _shellScreenFile() {
  const rootPath = 'example/lib/features/shell/shell_screen.dart';
  const packagePath = 'lib/features/shell/shell_screen.dart';
  return File(File(rootPath).existsSync() ? rootPath : packagePath);
}

Iterable<File> _orphanProtectedShellScreenFiles(
  Directory shellDirectory,
) sync* {
  for (final entity in shellDirectory.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final basename = entity.uri.pathSegments.last;
    if (basename == 'shell_screen.dart' ||
        (basename.startsWith('shell_screen_') && basename.endsWith('.dart'))) {
      yield entity;
    }
  }
}

DartLibraryGraphScanner _fixtureScanner(Directory fixtureDirectory) {
  return DartLibraryGraphScanner(
    entrypoint: File('${fixtureDirectory.path}/shell_screen.dart'),
    packageName: 'fixture',
    packageLibDirectory: fixtureDirectory,
    ownedDirectory: fixtureDirectory,
    orphanProtectedFiles: fixtureDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
  );
}

void _writeFixture(Directory root, String relativePath, String source) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
}

Iterable<File> _allowedShellExternalDependencies(Directory libDirectory) {
  const paths = <String>[
    'data/configuration/data_api_configuration.dart',
    'data/configuration/data_api_configuration_providers.dart',
    'data/configuration/data_api_configuration_repository.dart',
    'data/repositories/data_api_repository_helpers.dart',
    'data/services/data_api_auth_contract.dart',
    'data/services/data_api_client.dart',
    'data/services/data_api_runtime.dart',
    'platform/clipboard_bridge.dart',
    'platform/corrupt_file_quarantine.dart',
    'platform/local_json_file.dart',
    'ui/app_ui.dart',
    'features/config/local_terminal_config_bootstrap.dart',
    'features/config/local_terminal_config_models.dart',
    'features/config/local_terminal_config_preferences_adapter.dart',
    'features/config/local_terminal_key_event_resolver.dart',
    'features/config/local_terminal_keybinding_resolver.dart',
    'features/config/shortcut_editor.dart',
    'features/layout/local_terminal_layout_models.dart',
    'features/layout/terminal_layout_action_reducer.dart',
    'features/layout/terminal_layout_production_callbacks.dart',
    'features/persistence/data_api_startup_recovery_presenter.dart',
    'features/persistence/versioned_document.dart',
    'features/policies/local_terminal_notification_dispatcher.dart',
    'features/policies/local_terminal_paste_decision.dart',
    'features/policies/local_terminal_policy_action_reducer.dart',
    'features/policies/local_terminal_policy_models.dart',
    'features/policies/local_terminal_policy_production_callbacks.dart',
    'features/preferences/app_preferences_models.dart',
    'features/productivity/shell_productivity_action_reducer.dart',
    'features/productivity/shell_productivity_models.dart',
    'features/productivity/shell_productivity_production_callbacks.dart',
    'features/profiles/dynamic_profiles_sheet.dart',
    'features/profiles/profile_editor.dart',
    'features/profiles/profile_models.dart',
    'features/profiles/profiles_sheet.dart',
    'features/recording/local_session_recording_repository.dart',
    'features/recording/recording_replay_search_index.dart',
    'features/recording/replay_viewport_layout.dart',
    'features/sessions/session_controller.dart',
    'features/sessions/session_ports.dart',
    'features/sessions/session_state.dart',
    'features/sessions/terminal_event_coordinator.dart',
    'features/ssh/new_session_launcher.dart',
    'features/ssh/ssh_auth_prompt.dart',
    'features/ssh/ssh_profile_import_service.dart',
    'features/terminal/selection_controller.dart',
    'features/terminal/terminal.dart',
    'features/terminal/terminal_input_controller.dart',
    'features/terminal/terminal_painter_models.dart',
    'features/terminal/terminal_viewport.dart',
    'features/terminal/terminal_viewport_colors.dart',
    'features/visual/local_terminal_diagnostics_exporter.dart',
    'features/visual/local_terminal_layout_template_applier.dart',
    'features/visual/local_terminal_scrollback_exporter.dart',
    'features/visual/local_terminal_visual_action_reducer.dart',
    'features/visual/local_terminal_visual_models.dart',
    'features/visual/local_terminal_visual_production_callbacks.dart',
  ];
  return paths.map((path) => File.fromUri(libDirectory.uri.resolve(path)));
}
