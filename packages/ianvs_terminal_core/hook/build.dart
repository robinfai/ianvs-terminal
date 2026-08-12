import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'native_dependencies.dart';

const _assetName = 'libianvs_core.dylib';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    final code = input.config.code;
    if (code.targetOS != OS.macOS) {
      return;
    }
    if (code.linkModePreference == LinkModePreference.static) {
      throw UnsupportedError(
        'ianvs_terminal_core requires dynamic linking on macOS.',
      );
    }

    final target = switch (code.targetArchitecture) {
      Architecture.arm64 => 'aarch64-apple-darwin',
      Architecture.x64 => 'x86_64-apple-darwin',
      final architecture => throw UnsupportedError(
        'Unsupported ianvs_terminal_core macOS architecture: $architecture',
      ),
    };
    final nativeRoot = input.packageRoot.resolve('native/');
    final coreRoot = nativeRoot.resolve('core/');
    final manifest = coreRoot.resolve('Cargo.toml');
    if (!File.fromUri(manifest).existsSync()) {
      throw StateError(
        'ianvs_terminal_core native sources are missing from the package.',
      );
    }

    final cargoTargetDirectory = input.outputDirectory.resolve('cargo-target/');
    final environment = <String, String>{
      ..._rustToolchainEnvironment(Platform.environment),
      'CARGO_TARGET_DIR': cargoTargetDirectory.toFilePath(),
      'MACOSX_DEPLOYMENT_TARGET': '${code.macOS.targetVersion}.0',
    };
    final result = await Process.run(
      'cargo',
      <String>[
        'build',
        '--locked',
        '--release',
        '--manifest-path',
        manifest.toFilePath(),
        '--target',
        target,
      ],
      workingDirectory: coreRoot.toFilePath(),
      environment: environment,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'cargo',
        const <String>['build', '--locked', '--release'],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }

    final builtLibrary = cargoTargetDirectory.resolve(
      '$target/release/$_assetName',
    );
    final asset = input.outputDirectory.resolve(_assetName);
    await File.fromUri(builtLibrary).copy(asset.toFilePath());
    final installName = await Process.run('install_name_tool', <String>[
      '-id',
      '@rpath/$_assetName',
      asset.toFilePath(),
    ]);
    if (installName.exitCode != 0) {
      throw ProcessException(
        'install_name_tool',
        <String>['-id', '@rpath/$_assetName', asset.toFilePath()],
        '${installName.stdout}\n${installName.stderr}',
        installName.exitCode,
      );
    }

    for (final dependency in nativeBuildDependencies(nativeRoot)) {
      output.dependencies.add(dependency.uri);
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        file: asset,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}

Map<String, String> _rustToolchainEnvironment(Map<String, String> environment) {
  final resolved = <String, String>{...environment};
  if (resolved['CARGO_HOME']?.isNotEmpty == true &&
      resolved['RUSTUP_HOME']?.isNotEmpty == true) {
    return resolved;
  }

  for (final entry in (resolved['PATH'] ?? '').split(':')) {
    if (!entry.endsWith('/.cargo/bin')) {
      continue;
    }
    final cargoHome = Directory(entry).parent;
    final rustupHome = Directory('${cargoHome.parent.path}/.rustup');
    if (!cargoHome.existsSync() || !rustupHome.existsSync()) {
      continue;
    }
    resolved.putIfAbsent('CARGO_HOME', () => cargoHome.path);
    resolved.putIfAbsent('RUSTUP_HOME', () => rustupHome.path);
    break;
  }
  return resolved;
}
