import 'dart:io';

void main() async {
  final repository = File.fromUri(Platform.script).parent.parent.absolute;
  final source = Directory('${repository.path}/packages/ianvs_terminal_core');
  final temporary = await Directory.systemTemp.createTemp(
    'ianvs-terminal-core-publish-',
  );
  try {
    _rejectPublishControlFiles(source);
    final package = Directory('${temporary.path}/ianvs_terminal_core');
    await _copyPublishTree(source, package);
    final pubspec = File('${package.path}/pubspec.yaml');
    final publishPubspec = (await pubspec.readAsString()).replaceFirst(
      RegExp(r'^resolution:\s*workspace\s*\n', multiLine: true),
      '',
    );
    await pubspec.writeAsString(publishPubspec, flush: true);

    _verifyContent(package);
    final result = await Process.run(
      Platform.resolvedExecutable,
      const <String>['pub', 'publish', '--dry-run'],
      workingDirectory: package.path,
    );
    if (result.exitCode != 0) {
      stderr
        ..write(result.stdout)
        ..write(result.stderr);
      exitCode = result.exitCode;
      return;
    }
    final report = '${result.stdout}\n${result.stderr}';
    if (!report.contains('Package has 0 warnings.')) {
      stderr
        ..writeln(report)
        ..writeln('standalone pub dry-run must complete with zero warnings');
      exitCode = 1;
    }
  } finally {
    await temporary.delete(recursive: true);
  }
}

void _rejectPublishControlFiles(Directory source) {
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final basename = entity.uri.pathSegments.last;
    if (basename == '.gitignore' || basename == '.pubignore') {
      throw StateError(
        'standalone source contains archive-control file ${entity.path}',
      );
    }
  }
}

Future<void> _copyPublishTree(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  final files =
      source
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => !_excluded(source, file))
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  for (final file in files) {
    final relative = file.absolute.path.substring(
      source.absolute.path.length + 1,
    );
    final target = File('${destination.path}/$relative');
    await target.parent.create(recursive: true);
    await file.copy(target.path);
  }
}

bool _excluded(Directory root, File file) {
  final relative = file.absolute.path.substring(root.absolute.path.length + 1);
  return relative
      .split(Platform.pathSeparator)
      .any(const <String>{'target', 'build', '.git', '.dart_tool'}.contains);
}

void _verifyContent(Directory package) {
  final paths = package
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map(
        (file) =>
            file.absolute.path.substring(package.absolute.path.length + 1),
      )
      .toSet();
  for (final required in const <String>{
    'CHANGELOG.md',
    'LICENSE',
    'README.md',
    'hook/build.dart',
    'hook/native_dependencies.dart',
    'lib/ianvs_terminal_core.dart',
    'native/core/Cargo.toml',
    'native/core/ianvs_core.h',
    'native/core/ianvs_core_abi_v1.json',
    'native/vendor/par-term-emu-core-rust/LICENSE',
    'native/vendor/zmodem2/LICENSE-APACHE',
    'native/vendor/zmodem2/LICENSE-MIT',
  }) {
    if (!paths.contains(required)) {
      throw StateError('publish archive is missing $required');
    }
  }
  for (final path in paths) {
    final components = path.split(Platform.pathSeparator);
    for (final forbidden in const <String>{
      'target',
      'build',
      '.git',
      '.gitignore',
      '.pubignore',
      '.dart_tool',
      '.claude',
      '.woodpecker',
      '.cargo-ok',
      '.cargo_vcs_info.json',
      'Cargo.toml.orig',
    }) {
      if (components.contains(forbidden)) {
        throw StateError('publish archive contains forbidden path $path');
      }
    }
  }
}
