import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final packageRoot = Directory('lib/src').existsSync()
      ? Directory.current.absolute
      : Directory('packages/ianvs_terminal').absolute;
  final libDirectory = Directory('${packageRoot.path}/lib');
  final graph = DartLibraryDependencyGraph.fromDirectory(
    packageName: 'ianvs_terminal',
    libDirectory: libDirectory,
  );

  test('package directives and part ownership are valid', () {
    expect(graph.validationErrors, isEmpty);
  });

  test(
    'AST graph covers imports, exports, conditions, and both part-of forms',
    () {
      final fixture = Directory.systemTemp.createTempSync(
        'ianvs_terminal_dependency_graph_',
      );
      addTearDown(() => fixture.deleteSync(recursive: true));
      final fixtureLib = Directory('${fixture.path}/lib')..createSync();
      File('${fixtureLib.path}/root.dart').writeAsStringSync('''
library fixture.root;
import 'base.dart' if (dart.library.io) 'conditional.dart';
export 'exported.dart';
part 'named_piece.dart';
part 'uri_piece.dart';
''');
      File('${fixtureLib.path}/named_piece.dart').writeAsStringSync('''
part of fixture.root;
''');
      File('${fixtureLib.path}/uri_piece.dart').writeAsStringSync('''
part of 'root.dart';
''');
      for (final name in <String>[
        'base.dart',
        'conditional.dart',
        'exported.dart',
      ]) {
        File('${fixtureLib.path}/$name').writeAsStringSync('// $name\n');
      }

      final fixtureGraph = DartLibraryDependencyGraph.fromDirectory(
        packageName: 'fixture',
        libDirectory: fixtureLib,
      );
      final owner = fixtureGraph.absolutePathOf('root.dart');
      final namedPart = fixtureGraph.absolutePathOf('named_piece.dart');
      final uriPart = fixtureGraph.absolutePathOf('uri_piece.dart');

      expect(fixtureGraph.validationErrors, isEmpty);
      expect(
        fixtureGraph
            .directDependenciesOf(owner)
            .map(fixtureGraph.relativePathOf),
        unorderedEquals(<String>[
          'base.dart',
          'conditional.dart',
          'exported.dart',
          'named_piece.dart',
          'uri_piece.dart',
        ]),
      );
      expect(fixtureGraph.libraryOwnerOf(namedPart), owner);
      expect(fixtureGraph.libraryOwnerOf(uriPart), owner);
      expect(fixtureGraph.directDependenciesOf(namedPart), contains(owner));
      expect(fixtureGraph.directDependenciesOf(uriPart), contains(owner));
    },
  );

  test('orphan part-of directives fail ownership validation', () {
    final fixture = Directory.systemTemp.createTempSync(
      'ianvs_terminal_orphan_part_',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final fixtureLib = Directory('${fixture.path}/lib')..createSync();
    File(
      '${fixtureLib.path}/orphan.dart',
    ).writeAsStringSync('part of missing.owner;\n');

    final fixtureGraph = DartLibraryDependencyGraph.fromDirectory(
      packageName: 'fixture',
      libDirectory: fixtureLib,
    );

    expect(
      fixtureGraph.validationErrors,
      contains(contains('has part-of but no owning part URI')),
    );
  });

  test('a part included by multiple owners fails ownership validation', () {
    final fixture = Directory.systemTemp.createTempSync(
      'ianvs_terminal_multi_owner_part_',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final fixtureLib = Directory('${fixture.path}/lib')..createSync();
    for (final owner in <String>['first', 'second']) {
      File('${fixtureLib.path}/$owner.dart').writeAsStringSync('''
library fixture.shared;
part 'piece.dart';
''');
    }
    File(
      '${fixtureLib.path}/piece.dart',
    ).writeAsStringSync('part of fixture.shared;\n');

    final fixtureGraph = DartLibraryDependencyGraph.fromDirectory(
      packageName: 'fixture',
      libDirectory: fixtureLib,
    );

    expect(
      fixtureGraph.validationErrors,
      contains(contains('is included by both')),
    );
  });

  test('parser errors fail directive graph validation', () {
    final fixture = Directory.systemTemp.createTempSync(
      'ianvs_terminal_parser_error_',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final fixtureLib = Directory('${fixture.path}/lib')..createSync();
    File('${fixtureLib.path}/broken.dart').writeAsStringSync('''
void broken( {
''');

    final fixtureGraph = DartLibraryDependencyGraph.fromDirectory(
      packageName: 'fixture',
      libDirectory: fixtureLib,
    );

    expect(
      fixtureGraph.validationErrors,
      contains(contains('has parse error')),
    );
  });

  test('a domain part inherits forbidden dependencies from its owner', () {
    final fixture = Directory.systemTemp.createTempSync(
      'ianvs_terminal_part_escape_',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final fixtureLib = Directory('${fixture.path}/lib');
    Directory('${fixtureLib.path}/src/terminal').createSync(recursive: true);
    Directory('${fixtureLib.path}/src/transport').createSync(recursive: true);
    File('${fixtureLib.path}/src/owner.dart').writeAsStringSync('''
library escape.owner;
import 'transport/wire.dart';
part 'terminal/domain_piece.dart';
''');
    File(
      '${fixtureLib.path}/src/terminal/domain_piece.dart',
    ).writeAsStringSync('part of escape.owner;\n');
    File(
      '${fixtureLib.path}/src/transport/wire.dart',
    ).writeAsStringSync('// wire\n');

    final fixtureGraph = DartLibraryDependencyGraph.fromDirectory(
      packageName: 'fixture',
      libDirectory: fixtureLib,
    );
    final part = fixtureGraph.absolutePathOf('src/terminal/domain_piece.dart');
    final path = fixtureGraph.firstPathFrom(
      part,
      (candidate) =>
          fixtureGraph.relativePathOf(candidate).startsWith('src/transport/'),
    );

    expect(fixtureGraph.validationErrors, isEmpty);
    expect(path?.map(fixtureGraph.relativePathOf), <String>[
      'src/terminal/domain_piece.dart',
      'src/owner.dart',
      'src/transport/wire.dart',
    ]);
  });

  test('an export with a conditional bridge cannot hide a wire dependency', () {
    final fixture = Directory.systemTemp.createTempSync(
      'ianvs_terminal_bridge_escape_',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final fixtureLib = Directory('${fixture.path}/lib');
    Directory('${fixtureLib.path}/src/xterm').createSync(recursive: true);
    Directory('${fixtureLib.path}/src/transport').createSync(recursive: true);
    File('${fixtureLib.path}/src/xterm/bridge.dart').writeAsStringSync('''
export 'bridge_stub.dart' if (dart.library.io) 'bridge_io.dart';
''');
    File(
      '${fixtureLib.path}/src/xterm/bridge_stub.dart',
    ).writeAsStringSync('// stub\n');
    File('${fixtureLib.path}/src/xterm/bridge_io.dart').writeAsStringSync('''
import '../transport/wire.dart';
''');
    File(
      '${fixtureLib.path}/src/transport/wire.dart',
    ).writeAsStringSync('// wire\n');

    final fixtureGraph = DartLibraryDependencyGraph.fromDirectory(
      packageName: 'fixture',
      libDirectory: fixtureLib,
    );
    final violations = _wireBoundaryViolations(
      fixtureGraph,
      compositionAllowlist: const <String>{},
    );

    expect(fixtureGraph.validationErrors, isEmpty);
    expect(
      violations,
      contains(
        'src/xterm/bridge.dart -> src/xterm/bridge_io.dart -> '
        'src/transport/wire.dart',
      ),
    );
  });

  test(
    'terminal input depends on a capability port, not runtime orchestration',
    () {
      final source = graph.absolutePathOf(
        'src/terminal/terminal_input_controller.dart',
      );
      final dependencies = graph.directDependenciesOf(source);

      expect(
        dependencies.map(graph.relativePathOf),
        contains('src/terminal/terminal_input_sink.dart'),
      );
      expect(
        dependencies.where(
          (dependency) =>
              graph.relativePathOf(dependency).startsWith('src/runtime/'),
        ),
        isEmpty,
      );
    },
  );

  test('domain has no direct or transitive transport/protobuf dependency', () {
    final roots = graph.filesWhere(
      (path) => _isUnderAny(path, const <String>[
        'src/terminal/',
        'src/config/',
        'src/recording/',
      ]),
    );

    _expectNoDependencyPaths(
      graph: graph,
      roots: roots,
      forbidden: _isWirePath,
      description: 'domain -> generated protobuf/transport',
    );
  });

  test('neutral contracts do not depend on implementations or wire code', () {
    final roots = graph.filesWhere((path) => path.startsWith('src/contracts/'));

    _expectNoDependencyPaths(
      graph: graph,
      roots: roots,
      forbidden: (path) => _isUnderAny(path, const <String>[
        'src/proto/',
        'src/transport/',
        'src/terminal/',
        'src/config/',
        'src/recording/',
        'src/runtime/',
      ]),
      description: 'contracts -> implementation',
    );
  });

  test('frame decoder and packet validator depend only on decode ports', () {
    final roots = <String>[
      graph.absolutePathOf('src/runtime/terminal_frame_decoder.dart'),
      graph.absolutePathOf('src/runtime/terminal_frame_packet_v1.dart'),
    ];

    _expectNoDependencyPaths(
      graph: graph,
      roots: roots,
      forbidden: _isWirePath,
      description: 'runtime decoder/packet -> concrete wire adapter',
    );
  });

  test(
    'all internal wire paths cross the allowlisted composition boundary',
    () {
      const compositionAllowlist = <String>{
        'src/runtime/terminal_frame_transport_coordinator.dart',
      };
      final violations = _wireBoundaryViolations(
        graph,
        compositionAllowlist: compositionAllowlist,
      );

      expect(
        violations,
        isEmpty,
        reason:
            'Internal files reached generated protobuf/transport without the '
            'composition boundary:\n${violations.join('\n')}',
      );
    },
  );

  test('JSON/domain and protobuf adapters share normalization policy', () {
    const policy = 'src/contracts/terminal_frame_normalization_policy.dart';
    for (final sourcePath in <String>[
      'src/terminal/terminal_models.dart',
      'src/transport/terminal_protobuf_frame_codec.dart',
    ]) {
      final dependencies = graph.directDependenciesOf(
        graph.absolutePathOf(sourcePath),
      );
      expect(
        dependencies.map(graph.relativePathOf),
        contains(policy),
        reason: '$sourcePath must use the shared neutral policy',
      );
    }
  });
}

bool _isUnderAny(String path, List<String> prefixes) {
  return prefixes.any(path.startsWith);
}

bool _isWirePath(String path) {
  return _isUnderAny(path, const <String>['src/proto/', 'src/transport/']);
}

List<String> _wireBoundaryViolations(
  DartLibraryDependencyGraph graph, {
  required Set<String> compositionAllowlist,
}) {
  final allowlistedNodes = compositionAllowlist
      .map(graph.absolutePathOf)
      .toSet();
  final violations = <String>[];
  final roots = graph.filesWhere(
    // The package barrel intentionally exports the public protobuf migration
    // codec. Composition enforcement covers all internal production libraries.
    (path) => path.startsWith('src/') && !_isWirePath(path),
  );
  for (final root in roots) {
    if (allowlistedNodes.contains(root)) {
      continue;
    }
    final paths = graph.firstBoundaryPathsFrom(
      root,
      isBoundary: (candidate) => _isWirePath(graph.relativePathOf(candidate)),
      stopTraversalAt: allowlistedNodes.contains,
    );
    violations.addAll(
      paths.map((path) => path.map(graph.relativePathOf).join(' -> ')),
    );
  }
  violations.sort();
  return violations;
}

void _expectNoDependencyPaths({
  required DartLibraryDependencyGraph graph,
  required Iterable<String> roots,
  required bool Function(String path) forbidden,
  required String description,
}) {
  final violations = <String>[];
  for (final root in roots) {
    final path = graph.firstPathFrom(
      root,
      (candidate) =>
          candidate != root && forbidden(graph.relativePathOf(candidate)),
    );
    if (path != null) {
      violations.add(path.map(graph.relativePathOf).join(' -> '));
    }
  }
  expect(
    violations,
    isEmpty,
    reason: '$description dependency paths:\n${violations.join('\n')}',
  );
}

final class DartLibraryDependencyGraph {
  DartLibraryDependencyGraph._({
    required this.packageName,
    required Directory libDirectory,
    required Map<String, Set<String>> dependencies,
    required Map<String, String> partOwnerByPart,
    required this.validationErrors,
  }) : _libDirectory = libDirectory.absolute,
       _dependencies = dependencies,
       _partOwnerByPart = partOwnerByPart;

  factory DartLibraryDependencyGraph.fromDirectory({
    required String packageName,
    required Directory libDirectory,
  }) {
    final absoluteLib = libDirectory.absolute;
    final dartFiles = absoluteLib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.absolute.path)
        .toSet();
    final dependencies = <String, Set<String>>{
      for (final file in dartFiles) file: <String>{},
    };
    final validationErrors = <String>[];
    final units = <String, CompilationUnit>{};
    for (final source in dartFiles) {
      final result = parseFile(
        path: source,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      units[source] = result.unit;
      validationErrors.addAll(
        result.errors.map((error) => '$source has parse error: $error'),
      );
    }

    for (final entry in units.entries) {
      final source = entry.key;
      final unit = entry.value;
      for (final directive in unit.directives.whereType<NamespaceDirective>()) {
        _addNamespaceDependency(
          source: source,
          uriLiteral: directive.uri,
          packageName: packageName,
          libDirectory: absoluteLib,
          dartFiles: dartFiles,
          dependencies: dependencies,
          validationErrors: validationErrors,
        );
        for (final configuration in directive.configurations) {
          _addNamespaceDependency(
            source: source,
            uriLiteral: configuration.uri,
            packageName: packageName,
            libDirectory: absoluteLib,
            dartFiles: dartFiles,
            dependencies: dependencies,
            validationErrors: validationErrors,
          );
        }
      }
    }

    final partOwnerByPart = <String, String>{};
    for (final entry in units.entries) {
      final owner = entry.key;
      final ownerUnit = entry.value;
      final ownerName = ownerUnit.directives
          .whereType<LibraryDirective>()
          .firstOrNull
          ?.name
          ?.toSource();
      for (final directive in ownerUnit.directives.whereType<PartDirective>()) {
        final part = _resolveRequiredInternalDirective(
          source: owner,
          uriLiteral: directive.uri,
          packageName: packageName,
          libDirectory: absoluteLib,
          dartFiles: dartFiles,
          validationErrors: validationErrors,
          directiveKind: 'part',
        );
        if (part == null) {
          continue;
        }
        final existingOwner = partOwnerByPart[part];
        if (existingOwner != null && existingOwner != owner) {
          validationErrors.add(
            '$part is included by both $existingOwner and $owner',
          );
          continue;
        }
        partOwnerByPart[part] = owner;
        dependencies[owner]!.add(part);
        dependencies[part]!.add(owner);
        _validatePartOfDirective(
          owner: owner,
          ownerName: ownerName,
          part: part,
          partUnit: units[part]!,
          packageName: packageName,
          libDirectory: absoluteLib,
          validationErrors: validationErrors,
        );
      }
    }

    for (final entry in units.entries) {
      final hasPartOf = entry.value.directives.any(
        (directive) => directive is PartOfDirective,
      );
      if (hasPartOf && !partOwnerByPart.containsKey(entry.key)) {
        validationErrors.add('${entry.key} has part-of but no owning part URI');
      }
    }

    return DartLibraryDependencyGraph._(
      packageName: packageName,
      libDirectory: absoluteLib,
      dependencies: dependencies,
      partOwnerByPart: partOwnerByPart,
      validationErrors: List<String>.unmodifiable(validationErrors),
    );
  }

  final String packageName;
  final Directory _libDirectory;
  final Map<String, Set<String>> _dependencies;
  final Map<String, String> _partOwnerByPart;
  final List<String> validationErrors;

  Iterable<String> filesWhere(bool Function(String path) predicate) {
    return _dependencies.keys.where((file) => predicate(relativePathOf(file)));
  }

  String absolutePathOf(String path) {
    return File.fromUri(_libDirectory.uri.resolve(path)).absolute.path;
  }

  String relativePathOf(String absolutePath) {
    final prefix = '${_libDirectory.path}${Platform.pathSeparator}';
    final normalized = File(absolutePath).absolute.path;
    if (!normalized.startsWith(prefix)) {
      return normalized;
    }
    return normalized
        .substring(prefix.length)
        .replaceAll(Platform.pathSeparator, '/');
  }

  String? libraryOwnerOf(String part) => _partOwnerByPart[part];

  Set<String> directDependenciesOf(String source) {
    return UnmodifiableSetView<String>(
      _dependencies[source] ?? const <String>{},
    );
  }

  List<String>? firstPathFrom(
    String root,
    bool Function(String candidate) matches,
  ) {
    final queue = Queue<List<String>>()..add(<String>[root]);
    final visited = <String>{root};
    while (queue.isNotEmpty) {
      final path = queue.removeFirst();
      final current = path.last;
      if (matches(current)) {
        return path;
      }
      for (final dependency in directDependenciesOf(current)) {
        if (visited.add(dependency)) {
          queue.add(<String>[...path, dependency]);
        }
      }
    }
    return null;
  }

  List<List<String>> firstBoundaryPathsFrom(
    String root, {
    required bool Function(String candidate) isBoundary,
    required bool Function(String candidate) stopTraversalAt,
  }) {
    final paths = <List<String>>[];
    final queue = Queue<List<String>>()..add(<String>[root]);
    final visited = <String>{root};
    while (queue.isNotEmpty) {
      final path = queue.removeFirst();
      final current = path.last;
      if (current != root && stopTraversalAt(current)) {
        continue;
      }
      for (final dependency in directDependenciesOf(current)) {
        final nextPath = <String>[...path, dependency];
        if (isBoundary(dependency)) {
          paths.add(nextPath);
        } else if (visited.add(dependency)) {
          queue.add(nextPath);
        }
      }
    }
    return paths;
  }
}

void _addNamespaceDependency({
  required String source,
  required StringLiteral uriLiteral,
  required String packageName,
  required Directory libDirectory,
  required Set<String> dartFiles,
  required Map<String, Set<String>> dependencies,
  required List<String> validationErrors,
}) {
  final resolution = _resolveDirectiveUri(
    source: source,
    uriLiteral: uriLiteral,
    packageName: packageName,
    libDirectory: libDirectory,
  );
  if (resolution.error case final error?) {
    validationErrors.add(error);
    return;
  }
  final internalPath = resolution.internalPath;
  if (internalPath == null) {
    return;
  }
  if (!dartFiles.contains(internalPath)) {
    validationErrors.add(
      '$source references missing Dart library $internalPath',
    );
    return;
  }
  dependencies[source]!.add(internalPath);
}

String? _resolveRequiredInternalDirective({
  required String source,
  required StringLiteral uriLiteral,
  required String packageName,
  required Directory libDirectory,
  required Set<String> dartFiles,
  required List<String> validationErrors,
  required String directiveKind,
}) {
  final resolution = _resolveDirectiveUri(
    source: source,
    uriLiteral: uriLiteral,
    packageName: packageName,
    libDirectory: libDirectory,
  );
  if (resolution.error case final error?) {
    validationErrors.add(error);
    return null;
  }
  final internalPath = resolution.internalPath;
  if (internalPath == null || !dartFiles.contains(internalPath)) {
    validationErrors.add(
      '$source has unresolved $directiveKind URI ${uriLiteral.toSource()}',
    );
    return null;
  }
  return internalPath;
}

void _validatePartOfDirective({
  required String owner,
  required String? ownerName,
  required String part,
  required CompilationUnit partUnit,
  required String packageName,
  required Directory libDirectory,
  required List<String> validationErrors,
}) {
  final directives = partUnit.directives.whereType<PartOfDirective>().toList();
  if (directives.length != 1) {
    validationErrors.add(
      '$part must contain exactly one part-of directive for $owner',
    );
    return;
  }
  final directive = directives.single;
  final partOwnerName = directive.libraryName?.toSource();
  if (partOwnerName != null) {
    if (ownerName == null || ownerName != partOwnerName) {
      validationErrors.add(
        '$part names library $partOwnerName but owner $owner is $ownerName',
      );
    }
    return;
  }
  final uriLiteral = directive.uri;
  if (uriLiteral == null) {
    validationErrors.add('$part has an invalid part-of directive');
    return;
  }
  final resolution = _resolveDirectiveUri(
    source: part,
    uriLiteral: uriLiteral,
    packageName: packageName,
    libDirectory: libDirectory,
  );
  if (resolution.error case final error?) {
    validationErrors.add(error);
  } else if (resolution.internalPath != owner) {
    validationErrors.add(
      '$part points part-of at ${resolution.internalPath}, expected $owner',
    );
  }
}

({String? internalPath, String? error}) _resolveDirectiveUri({
  required String source,
  required StringLiteral uriLiteral,
  required String packageName,
  required Directory libDirectory,
}) {
  final uriString = uriLiteral.stringValue;
  if (uriString == null) {
    return (
      internalPath: null,
      error: '$source contains a non-literal directive URI',
    );
  }
  final uri = Uri.tryParse(uriString);
  if (uri == null) {
    return (internalPath: null, error: '$source has invalid URI $uriString');
  }
  if (uri.scheme == 'dart') {
    return (internalPath: null, error: null);
  }
  if (uri.scheme == 'package') {
    final segments = uri.pathSegments;
    if (segments.isEmpty || segments.first != packageName) {
      return (internalPath: null, error: null);
    }
    if (segments.length == 1) {
      return (
        internalPath: null,
        error: '$source has invalid package URI $uriString',
      );
    }
    return (
      internalPath: File.fromUri(
        libDirectory.uri.resolve(segments.skip(1).join('/')),
      ).absolute.path,
      error: null,
    );
  }
  if (uri.hasScheme) {
    return (
      internalPath: null,
      error: '$source uses unsupported directive URI $uriString',
    );
  }
  final resolved = File.fromUri(
    File(source).absolute.uri.resolveUri(uri),
  ).absolute.path;
  final libPrefix = '${libDirectory.absolute.path}${Platform.pathSeparator}';
  if (!resolved.startsWith(libPrefix)) {
    return (
      internalPath: null,
      error: '$source resolves URI outside package lib: $uriString',
    );
  }
  return (internalPath: resolved, error: null);
}
