import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Data API production code cannot read process or compile environment',
    () {
      final roots = <FileSystemEntity>[
        File('lib/main.dart'),
        File('lib/driver_main.dart'),
        File('lib/app.dart'),
        File('lib/app_bootstrap.dart'),
        Directory('lib/data'),
        File('lib/persistence_repository_composition.dart'),
        ...Directory('lib/startup').listSync(),
      ];
      final violations = <String>[];
      for (final file in roots.expand(_dartFiles).whereType<File>()) {
        final result = parseString(
          path: file.path,
          content: file.readAsStringSync(),
          featureSet: FeatureSet.latestLanguageVersion(),
          throwIfDiagnostics: false,
        );
        result.unit.accept(_ForbiddenEnvironmentVisitor(file.path, violations));
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Data API runtime configuration must come only from typed current '
            'configuration, never process or compile-time environment:\n'
            '${violations.join('\n')}',
      );
    },
  );

  test('app bootstrap gate rejects environment access escapes', () {
    const source = '''
import 'dart:io' as io;
import 'dart:core' as core;
const value = String.fromEnvironment('IANVS_TEST');
const other = core.bool.fromEnvironment('IANVS_OTHER');
void read(dynamic platform) {
  print(io.Platform.environment);
  print(platform.environment);
}
''';
    final result = parseString(
      content: source,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    final violations = <String>[];
    result.unit.accept(
      _ForbiddenEnvironmentVisitor('lib/app_bootstrap.dart', violations),
    );
    expect(violations, hasLength(4));
  });
}

Iterable<FileSystemEntity> _dartFiles(FileSystemEntity entity) sync* {
  if (entity is File) {
    if (entity.path.endsWith('.dart')) {
      yield entity;
    }
    return;
  }
  if (entity is Directory) {
    yield* entity
        .listSync(recursive: true)
        .where((entry) => entry is File && entry.path.endsWith('.dart'));
  }
}

final class _ForbiddenEnvironmentVisitor extends RecursiveAstVisitor<void> {
  _ForbiddenEnvironmentVisitor(this.path, this.violations);

  final String path;
  final List<String> violations;

  void _report(AstNode node, String boundary) {
    final line = node.root is CompilationUnit
        ? (node.root as CompilationUnit).lineInfo
              .getLocation(node.offset)
              .lineNumber
        : 0;
    violations.add('$path:$line uses $boundary');
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name == 'environment') {
      _report(node, 'Platform.environment');
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name == 'environment') {
      _report(node, 'Platform.environment');
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'fromEnvironment') {
      _report(node, 'compile-time fromEnvironment');
    }
    super.visitSimpleIdentifier(node);
  }
}
