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
      final roots = <File>[
        File('lib/main.dart'),
        File('lib/driver_main.dart'),
        File('lib/app.dart'),
        File('lib/app_bootstrap.dart'),
        File('lib/persistence_repository_composition.dart'),
        ...Directory('lib/data').listSync(recursive: true).whereType<File>(),
        ...Directory('lib/startup').listSync(recursive: true).whereType<File>(),
      ];
      final violations = <String>[];
      for (final file in _internalDartClosure(roots)) {
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

  test('an imported Data API adapter cannot hide environment access', () {
    final violations = <String>[];
    final fixtureRoot = File(
      'test/fixtures/architecture/data_api_environment_escape/entrypoint.dart',
    );

    for (final file in _internalDartClosure(<File>[fixtureRoot])) {
      final result = parseString(
        path: file.path,
        content: file.readAsStringSync(),
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      result.unit.accept(_ForbiddenEnvironmentVisitor(file.path, violations));
    }

    expect(violations, hasLength(1));
    expect(violations.single, contains('imported_adapter.dart'));
  });

  test('app bootstrap gate rejects environment access escapes', () {
    const source = '''
import 'dart:io' as io;
import 'dart:core' as core;
const value = String.fromEnvironment('IANVS_TEST');
const other = core.bool.fromEnvironment('IANVS_OTHER');
const present = bool.hasEnvironment('IANVS_PRESENT');
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
    expect(violations, hasLength(5));
  });

  test('narrow non-Data environment exceptions cannot hide another read', () {
    const profileSource = '''
void read() {
  const allowed = String.fromEnvironment('IANVS_DEFAULT_SHELL');
  const escaped = String.fromEnvironment('IANVS_SECRET');
}
''';
    const sessionSource = '''
import 'dart:io';
void read() {
  final allowed = Platform.environment['IANVS_TERMINAL_GRAPHICS_TRACE'];
  final escaped = Platform.environment['IANVS_SECRET'];
}
''';
    const sshImportSource = '''
import 'dart:io';
void read() {
  final allowed = Platform.environment['HOME'];
  final escaped = Platform.environment['IANVS_SECRET'];
}
''';
    final violations = <String>[];
    for (final fixture in <(String, String)>[
      ('lib/features/profiles/profile_models.dart', profileSource),
      ('lib/features/sessions/session_controller.dart', sessionSource),
      ('lib/features/ssh/ssh_profile_import_service.dart', sshImportSource),
    ]) {
      final result = parseString(
        path: fixture.$1,
        content: fixture.$2,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      result.unit.accept(_ForbiddenEnvironmentVisitor(fixture.$1, violations));
    }

    expect(violations, hasLength(3));
    expect(
      violations,
      contains(contains('features/profiles/profile_models.dart')),
    );
    expect(
      violations,
      contains(contains('features/sessions/session_controller.dart')),
    );
    expect(
      violations,
      contains(contains('features/ssh/ssh_profile_import_service.dart')),
    );
  });
}

Iterable<File> _internalDartClosure(Iterable<File> roots) sync* {
  final libRoot = Directory('lib').absolute.uri;
  final pending = <File>[
    for (final root in roots)
      if (root.path.endsWith('.dart')) root.absolute,
  ];
  final visited = <String>{};

  while (pending.isNotEmpty) {
    final file = pending.removeLast();
    final path = file.absolute.path;
    if (!visited.add(path) || !file.existsSync()) {
      continue;
    }
    yield file;

    final result = parseString(
      path: path,
      content: file.readAsStringSync(),
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    for (final uri in _internalDirectiveUris(result.unit)) {
      final resolved = _resolveInternalUri(
        source: file,
        rawUri: uri,
        libRoot: libRoot,
      );
      if (resolved != null && resolved.path.endsWith('.dart')) {
        pending.add(resolved);
      }
    }
  }
}

Iterable<String> _internalDirectiveUris(CompilationUnit unit) sync* {
  for (final directive in unit.directives) {
    if (directive case NamespaceDirective(:final uri, :final configurations)) {
      final primary = uri.stringValue;
      if (primary != null) {
        yield primary;
      }
      for (final configuration in configurations) {
        final conditional = configuration.uri.stringValue;
        if (conditional != null) {
          yield conditional;
        }
      }
    } else if (directive case PartDirective(:final uri)) {
      final part = uri.stringValue;
      if (part != null) {
        yield part;
      }
    }
  }
}

File? _resolveInternalUri({
  required File source,
  required String rawUri,
  required Uri libRoot,
}) {
  final uri = Uri.tryParse(rawUri);
  if (uri == null) {
    return null;
  }
  if (uri.scheme == 'package') {
    const packagePrefix = 'app/';
    if (!rawUri.startsWith('package:$packagePrefix')) {
      return null;
    }
    return File.fromUri(
      libRoot.resolve(rawUri.substring('package:app/'.length)),
    );
  }
  if (uri.hasScheme) {
    return null;
  }
  return File.fromUri(source.absolute.uri.resolveUri(uri));
}

final class _ForbiddenEnvironmentVisitor extends RecursiveAstVisitor<void> {
  _ForbiddenEnvironmentVisitor(this.path, this.violations);

  final String path;
  final List<String> violations;

  void _report(AstNode node, String boundary) {
    if (_isAllowedNonDataEnvironmentUse(path, node)) {
      return;
    }
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
    if (node.name == 'fromEnvironment' || node.name == 'hasEnvironment') {
      _report(node, 'compile-time ${node.name}');
    }
    super.visitSimpleIdentifier(node);
  }
}

bool _isAllowedNonDataEnvironmentUse(String path, AstNode node) {
  if (node is SimpleIdentifier && node.name == 'fromEnvironment') {
    final invocation = _compileEnvironmentInvocation(node);
    if (invocation == null || invocation.$1 != 'String') {
      return false;
    }
    final key = invocation.$2;
    if (path.endsWith('features/profiles/profile_models.dart')) {
      return key == 'IANVS_DEFAULT_SHELL';
    }
    if (path.endsWith('features/sessions/session_controller.dart')) {
      return key == 'IANVS_TERMINAL_GRAPHICS_TRACE';
    }
    return false;
  }

  if (node.toSource() != 'Platform.environment') {
    return false;
  }
  final access = node.parent;
  if (access is! IndexExpression ||
      access.target != node ||
      access.index is! StringLiteral) {
    return false;
  }
  final key = (access.index as StringLiteral).stringValue;
  if (path.endsWith('features/sessions/session_controller.dart')) {
    return key == 'IANVS_TERMINAL_GRAPHICS_TRACE';
  }
  if (path.endsWith('features/ssh/ssh_profile_import_service.dart')) {
    return key == 'HOME';
  }
  return false;
}

/// Returns the exact static receiver and first literal argument for a
/// compile-time environment invocation. Analyzer represents constructor-like
/// core invocations as either form depending on surrounding const context.
(String, String?)? _compileEnvironmentInvocation(SimpleIdentifier node) {
  AstNode? current = node.parent;
  while (current != null) {
    if (current is InstanceCreationExpression) {
      final arguments = current.argumentList.arguments;
      return (
        current.constructorName.type.toSource(),
        arguments.isNotEmpty && arguments.first is StringLiteral
            ? (arguments.first as StringLiteral).stringValue
            : null,
      );
    }
    if (current is MethodInvocation && current.methodName == node) {
      final arguments = current.argumentList.arguments;
      return (
        current.target?.toSource() ?? '',
        arguments.isNotEmpty && arguments.first is StringLiteral
            ? (arguments.first as StringLiteral).stringValue
            : null,
      );
    }
    current = current.parent;
  }
  return null;
}
