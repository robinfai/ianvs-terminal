import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local persistence production code has no predecessor entry points', () {
    final violations = <String>[];
    for (final file in _productionFiles()) {
      final result = parseString(
        path: file.path,
        content: file.readAsStringSync(),
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      result.unit.accept(_CurrentOnlyPersistenceVisitor(file.path, violations));
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Current local persistence must not regain predecessor parsers, '
          'filenames, prompt coordinates, or synchronous recording fallback:'
          '\n${violations.join('\n')}',
    );
  });

  test('gate catches aliases, tear-offs, and helper-hidden old filenames', () {
    const source = r'''
void escape(dynamic decoder, dynamic recorder) {
  final oldDecode = decoder.fromLegacyJson;
  final oldWorkspaceDecode = decoder.fromLegacyWorkspaceJson;
  final aliasedRecorder = recorder;
  final synchronousStop = aliasedRecorder.stop;
  String path(String name) => 'root/$name';
  print(path('workspace.json'));
  print(path('terminal_layout.json'));
  print(oldDecode);
  print(oldWorkspaceDecode);
  print(synchronousStop);
  print(legacyScrollbackOffset);
  print(_pendingRecordings);
  print(legacyPreferences);
  print(LocalTerminalConfigPreferencesAdapter);
}
''';
    final result = parseString(
      content: source,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    final violations = <String>[];
    result.unit.accept(
      _CurrentOnlyPersistenceVisitor(
        'lib/features/sessions/session_controller.dart',
        violations,
      ),
    );

    expect(violations, hasLength(9));
  });

  test(
    'external profile interchange stays outside the profile document parser',
    () {
      final violations = <String>[];
      for (final file in <File>[
        File('lib/features/profiles/profile_models.dart'),
        File('lib/features/profiles/profile_repository.dart'),
      ]) {
        final result = parseString(
          path: file.path,
          content: file.readAsStringSync(),
          featureSet: FeatureSet.latestLanguageVersion(),
          throwIfDiagnostics: false,
        );
        result.unit.accept(_ExternalProfileShapeVisitor(file.path, violations));
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
}

Iterable<File> _productionFiles() sync* {
  yield* _dartFiles(Directory('lib'));
}

Iterable<File> _dartFiles(Directory directory) sync* {
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

const Set<String> _forbiddenIdentifiers = <String>{
  'fromLegacyJson',
  'fromLegacyWorkspaceJson',
  'fromProfileJson',
  'legacyScrollbackOffset',
  '_pendingRecordings',
  'LocalTerminalConfigMigration',
  'LocalTerminalConfigPreferencesAdapter',
  'legacyPreferences',
  'legacyRevision',
};

const Set<String> _forbiddenFilenames = <String>{
  'workspace.json',
  'terminal_layout.json',
  'ianvs_workspace.json',
  'ianvs_workspace_layout.json',
  'ianvs_terminal_preferences.json',
};

final class _CurrentOnlyPersistenceVisitor extends RecursiveAstVisitor<void> {
  _CurrentOnlyPersistenceVisitor(this.path, this.violations);

  final String path;
  final List<String> violations;

  void _report(AstNode node, String message) {
    final unit = node.root as CompilationUnit;
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    violations.add('$path:$line $message');
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_forbiddenIdentifiers.contains(node.name)) {
      _report(node, 'references predecessor symbol ${node.name}');
    }
    if (path.endsWith('session_controller.dart') && node.name == 'stop') {
      final parent = node.parent;
      if (parent is MethodInvocation ||
          parent is PropertyAccess ||
          parent is PrefixedIdentifier) {
        final source = parent!.toSource().toLowerCase();
        if (source.contains('recorder')) {
          _report(node, 'references synchronous recorder.stop fallback');
        }
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (_forbiddenFilenames.contains(node.value)) {
      _report(node, 'references predecessor file ${node.value}');
    }
    super.visitSimpleStringLiteral(node);
  }
}

final class _ExternalProfileShapeVisitor extends RecursiveAstVisitor<void> {
  _ExternalProfileShapeVisitor(this.path, this.violations);

  final String path;
  final List<String> violations;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.value == 'Profiles') {
      final unit = node.root as CompilationUnit;
      final line = unit.lineInfo.getLocation(node.offset).lineNumber;
      violations.add('$path:$line parses the external Profiles shape');
    }
    super.visitSimpleStringLiteral(node);
  }
}
