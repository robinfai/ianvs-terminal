import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Synchronizes the standalone `ianvs_terminal_core` release artifact from
/// the repository's canonical terminal, PTY, and native implementations.
///
/// The published package intentionally contains a source mirror so consumers
/// do not need workspace path dependencies. This tool is the only supported
/// way to update that mirror. Use `--check` in CI to reject drift.
void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln('Usage: dart run tools/sync_terminal_core.dart [--check]');
    exitCode = 64;
    return;
  }

  final checkOnly = arguments.contains('--check');
  final repository = _findRepositoryRoot();
  final core = Directory('${repository.path}/packages/ianvs_terminal_core');
  if (!core.existsSync()) {
    throw StateError('Missing standalone package: ${core.path}');
  }

  final mirrors = <_DirectoryMirror>[
    for (final directory in const <String>[
      'config',
      'contracts',
      'proto',
      'recording',
      'runtime',
      'terminal',
      'transport',
    ])
      _DirectoryMirror(
        source: Directory(
          '${repository.path}/packages/ianvs_terminal/lib/src/$directory',
        ),
        destination: Directory('${core.path}/lib/src/$directory'),
        transform: _rewriteTerminalDart,
      ),
    _DirectoryMirror(
      source: Directory('${repository.path}/packages/ianvs_pty/lib/src'),
      destination: Directory('${core.path}/lib/src/pty'),
    ),
    _DirectoryMirror(
      source: Directory('${repository.path}/native/core'),
      destination: Directory('${core.path}/native/core'),
    ),
    _DirectoryMirror(
      source: Directory('${repository.path}/native/vendor'),
      destination: Directory('${core.path}/native/vendor'),
      exclude: _excludePublishedVendorMetadata,
    ),
    _DirectoryMirror(
      source: Directory('${repository.path}/packages/ianvs_terminal/test'),
      destination: Directory('${core.path}/test'),
      transform: _rewriteTerminalTest,
      exclude: _excludeHandOwnedCoreTests,
      preservedDestinationPrefixes: <String>[
        'current_only_architecture_test.dart',
        'embed/',
      ],
    ),
    _DirectoryMirror(
      source: Directory('${repository.path}/packages/ianvs_pty/test'),
      destination: Directory('${core.path}/test/pty'),
      transform: _rewritePtyTest,
    ),
  ];

  final expectedFiles = <String, Uint8List>{};
  for (final mirror in mirrors) {
    if (!mirror.source.existsSync()) {
      throw StateError('Missing canonical source: ${mirror.source.path}');
    }
    for (final source in _sourceFiles(mirror.source)) {
      final relative = _relativePath(mirror.source, source);
      if (mirror.exclude?.call(relative) == true) {
        continue;
      }
      final destination = File('${mirror.destination.path}/$relative');
      var bytes = source.readAsBytesSync();
      final transform = mirror.transform;
      if (transform != null && source.path.endsWith('.dart')) {
        bytes = Uint8List.fromList(
          utf8.encode(transform(utf8.decode(bytes), relative)),
        );
      }
      expectedFiles[destination.absolute.path] = bytes;
    }
  }

  final ptyBarrel = File(
    '${repository.path}/packages/ianvs_pty/lib/ianvs_pty.dart',
  );
  final corePtyBarrel = File('${core.path}/lib/src/pty/ianvs_pty.dart');
  expectedFiles[corePtyBarrel.absolute.path] = Uint8List.fromList(
    utf8.encode(ptyBarrel.readAsStringSync().replaceAll("'src/", "'")),
  );
  final canonicalDependencyHelper = File(
    '${repository.path}/packages/ianvs_pty/hook/native_dependencies.dart',
  );
  final canonicalBuildHook = File(
    '${repository.path}/packages/ianvs_pty/hook/build.dart',
  );
  final coreBuildHook = File('${core.path}/hook/build.dart');
  expectedFiles[coreBuildHook.absolute.path] = Uint8List.fromList(
    utf8.encode(_rewritePtyBuildHook(canonicalBuildHook.readAsStringSync())),
  );
  final coreDependencyHelper = File(
    '${core.path}/hook/native_dependencies.dart',
  );
  expectedFiles[coreDependencyHelper.absolute.path] = canonicalDependencyHelper
      .readAsBytesSync();
  _formatExpectedDart(expectedFiles);

  final actualFiles = <String>{};
  for (final mirror in mirrors) {
    final root = mirror.destination;
    if (!root.existsSync()) {
      continue;
    }
    for (final file in _sourceFiles(root)) {
      final relative = _relativePath(root, file);
      if (mirror.preservedDestinationPrefixes.any(relative.startsWith)) {
        continue;
      }
      actualFiles.add(file.absolute.path);
    }
  }

  final problems = <String>[];
  for (final entry in expectedFiles.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      problems.add('missing ${_repoRelative(repository, file)}');
      continue;
    }
    if (!_sameBytes(file.readAsBytesSync(), entry.value)) {
      problems.add('stale ${_repoRelative(repository, file)}');
    }
  }
  for (final path in actualFiles.difference(expectedFiles.keys.toSet())) {
    problems.add('unexpected ${_repoRelative(repository, File(path))}');
  }
  problems.sort();

  if (checkOnly) {
    if (problems.isNotEmpty) {
      stderr.writeln(
        'ianvs_terminal_core generated sources are out of sync:\n'
        '${problems.join('\n')}',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln('ianvs_terminal_core generated sources are current.');
    return;
  }

  for (final path in actualFiles.difference(expectedFiles.keys.toSet())) {
    File(path).deleteSync();
  }
  for (final entry in expectedFiles.entries) {
    final file = File(entry.key);
    file.parent.createSync(recursive: true);
    if (!file.existsSync() ||
        !_sameBytes(file.readAsBytesSync(), entry.value)) {
      file.writeAsBytesSync(entry.value, flush: true);
    }
  }
  _removeEmptyDirectories(mirrors.map((mirror) => mirror.destination));
  stdout.writeln(
    'Synchronized ${expectedFiles.length} generated files into '
    'packages/ianvs_terminal_core.',
  );
}

Directory _findRepositoryRoot() {
  var directory = File.fromUri(Platform.script).parent.parent.absolute;
  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/native/core').existsSync() &&
        Directory('${directory.path}/packages/ianvs_terminal').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Unable to locate the ianvs-terminal repository root.');
    }
    directory = parent;
  }
}

Iterable<File> _sourceFiles(Directory root) sync* {
  final files =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => !_isExcluded(root, file))
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  yield* files;
}

bool _isExcluded(Directory root, File file) {
  final relative = _relativePath(root, file);
  final components = relative.split('/');
  return components.any(
    (component) =>
        component == 'target' ||
        component == '.dart_tool' ||
        component == 'build' ||
        component == '.git' ||
        component == '.gitignore' ||
        component == '.pubignore',
  );
}

bool _excludePublishedVendorMetadata(String relative) {
  final components = relative.split('/');
  if (components.any(
    (component) =>
        component == '.claude' ||
        component == '.github' ||
        component == '.woodpecker' ||
        component == 'target' ||
        component == 'debug' ||
        component == 'docs' ||
        component == 'web_term',
  )) {
    return true;
  }
  final basename = components.last;
  return const <String>{
    '.cargo-ok',
    '.cargo_vcs_info.json',
    '.gitattributes',
    '.gitignore',
    'AGENTS.md',
    'CHANGELOG.md',
    'Cargo.toml.orig',
    'QUICKSTART.md',
    'README.md',
    'PATCHES.md',
    'pyrightconfig.json',
    'release.sh',
    'requirements-dev.txt',
    'theme.css',
    'uv.lock',
  }.contains(basename);
}

bool _excludeHandOwnedCoreTests(String relative) =>
    relative == 'current_only_architecture_test.dart';

String _rewriteTerminalDart(String source, String _) {
  return source.replaceAll(
    'package:ianvs_pty/ianvs_pty.dart',
    'package:ianvs_terminal_core/src/pty/ianvs_pty.dart',
  );
}

String _rewriteTerminalTest(String source, String _) {
  var rewritten = source
      .replaceAll(
        'package:ianvs_terminal/ianvs_terminal.dart',
        'package:ianvs_terminal_core/ianvs_terminal_core.dart',
      )
      .replaceAll(
        'package:ianvs_terminal/ianvs_terminal.dart',
        'package:ianvs_terminal_core/ianvs_terminal_core.dart',
      )
      .replaceAll('package:ianvs_terminal/', 'package:ianvs_terminal_core/')
      .replaceAll(
        'packages/ianvs_pty/lib/src/native_pty_backend.dart',
        'packages/ianvs_terminal_core/lib/src/pty/native_pty_backend.dart',
      )
      .replaceAll(
        'packages/ianvs_terminal/test/',
        'packages/ianvs_terminal_core/test/',
      )
      .replaceAll(
        'packages/ianvs_terminal/lib/',
        'packages/ianvs_terminal_core/lib/',
      )
      .replaceAll('lib/ianvs_terminal.dart', 'lib/ianvs_terminal_core.dart')
      .replaceAll(
        "Directory('packages/ianvs_terminal')",
        "Directory('packages/ianvs_terminal_core')",
      )
      .replaceAll(
        "packageName: 'ianvs_terminal'",
        "packageName: 'ianvs_terminal_core'",
      );
  const canonicalPtyImport = "import 'package:ianvs_pty/ianvs_pty.dart';";
  const publicCoreImport =
      "import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';";
  rewritten = rewritten.contains(publicCoreImport)
      ? rewritten.replaceAll('$canonicalPtyImport\n', '')
      : rewritten.replaceAll(
          canonicalPtyImport,
          "import 'package:ianvs_terminal_core/src/pty/ianvs_pty.dart';",
        );
  return _sortPackageImports(rewritten);
}

String _rewritePtyTest(String source, String _) {
  return _sortPackageImports(
    source
        .replaceAll(
          'package:ianvs_pty/ianvs_pty.dart',
          'package:ianvs_terminal_core/ianvs_terminal_core.dart',
        )
        .replaceAll(
          '../hook/native_dependencies.dart',
          '../../hook/native_dependencies.dart',
        ),
  );
}

String _rewritePtyBuildHook(String source) {
  return source
      .replaceAll('ianvs_pty requires', 'ianvs_terminal_core requires')
      .replaceAll(
        'Unsupported ianvs_pty macOS architecture:',
        'Unsupported ianvs_terminal_core macOS architecture:',
      )
      .replaceAll(
        "input.packageRoot.resolve('../../native/')",
        "input.packageRoot.resolve('native/')",
      )
      .replaceAll(
        "'ianvs_pty native sources are missing. Depend on the complete '\n"
            "        'ianvs-terminal repository, not a copied package directory.'",
        "'ianvs_terminal_core native sources are missing from the package.'",
      );
}

String _sortPackageImports(String source) {
  final lines = source.split('\n');
  var blockStart = -1;
  for (var index = 0; index <= lines.length; index += 1) {
    final isPackageImport =
        index < lines.length && lines[index].startsWith("import 'package:");
    if (isPackageImport && blockStart < 0) {
      blockStart = index;
      continue;
    }
    if (!isPackageImport && blockStart >= 0) {
      lines.replaceRange(
        blockStart,
        index,
        lines.sublist(blockStart, index)..sort(),
      );
      blockStart = -1;
    }
  }
  return lines.join('\n');
}

String _relativePath(Directory root, File file) {
  final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  final absolute = file.absolute.path;
  if (!absolute.startsWith(rootPath)) {
    throw StateError('${file.path} is outside ${root.path}');
  }
  return absolute
      .substring(rootPath.length)
      .split(Platform.pathSeparator)
      .join('/');
}

String _repoRelative(Directory repository, File file) {
  return _relativePath(repository, file);
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _formatExpectedDart(Map<String, Uint8List> expectedFiles) {
  final dartEntries = expectedFiles.entries
      .where((entry) => entry.key.endsWith('.dart'))
      .toList(growable: false);
  if (dartEntries.isEmpty) {
    return;
  }
  final temporary = Directory.systemTemp.createTempSync(
    'ianvs_terminal_core_sync_',
  );
  try {
    final temporaryFiles = <String, File>{};
    for (var index = 0; index < dartEntries.length; index += 1) {
      final entry = dartEntries[index];
      final file = File('${temporary.path}/$index.dart')
        ..writeAsBytesSync(entry.value);
      temporaryFiles[entry.key] = file;
    }
    final result = Process.runSync(Platform.resolvedExecutable, <String>[
      'format',
      '--output=write',
      temporary.path,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'dart format failed while generating ianvs_terminal_core:\n'
        '${result.stdout}\n${result.stderr}',
      );
    }
    for (final entry in temporaryFiles.entries) {
      expectedFiles[entry.key] = entry.value.readAsBytesSync();
    }
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

void _removeEmptyDirectories(Iterable<Directory> roots) {
  for (final root in roots) {
    if (!root.existsSync()) {
      continue;
    }
    final directories =
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<Directory>()
            .toList(growable: false)
          ..sort(
            (left, right) => right.path.length.compareTo(left.path.length),
          );
    for (final directory in directories) {
      if (directory.listSync(followLinks: false).isEmpty) {
        directory.deleteSync();
      }
    }
  }
}

final class _DirectoryMirror {
  const _DirectoryMirror({
    required this.source,
    required this.destination,
    this.transform,
    this.exclude,
    this.preservedDestinationPrefixes = const <String>[],
  });

  final Directory source;
  final Directory destination;
  final String Function(String source, String relativePath)? transform;
  final bool Function(String relativePath)? exclude;
  final List<String> preservedDestinationPrefixes;
}
