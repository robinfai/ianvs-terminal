import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'native_dependencies.dart';

const _assetName = 'libianvs_core.dylib';
const _cargoBuildJobs = '2';

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
      throw UnsupportedError('ianvs_pty requires dynamic linking on macOS.');
    }

    final target = switch (code.targetArchitecture) {
      Architecture.arm64 => 'aarch64-apple-darwin',
      Architecture.x64 => 'x86_64-apple-darwin',
      final architecture => throw UnsupportedError(
        'Unsupported ianvs_pty macOS architecture: $architecture',
      ),
    };
    final nativeRoot = input.packageRoot.resolve('../../native/');
    final coreRoot = nativeRoot.resolve('core/');
    final manifest = coreRoot.resolve('Cargo.toml');
    if (!File.fromUri(manifest).existsSync()) {
      throw StateError(
        'ianvs_pty native sources are missing. Depend on the complete '
        'ianvs-terminal repository, not a copied package directory.',
      );
    }

    final cargoTargetDirectory = input.outputDirectory.resolve('cargo-target/');
    final macOSSDKRoot = await _macOSSDKRoot();
    final environment = <String, String>{
      ..._rustToolchainEnvironment(Platform.environment),
      // A cold native build links several host build scripts before compiling
      // the target library. Letting Cargo use every logical CPU can make ld
      // fail under memory pressure, while Flutter reports only the final cc
      // exit code. Keep the hook deterministic and bounded.
      'CARGO_BUILD_JOBS': _cargoBuildJobs,
      'CARGO_TARGET_DIR': cargoTargetDirectory.toFilePath(),
      'MACOSX_DEPLOYMENT_TARGET': '${code.macOS.targetVersion}.0',
      // Flutter provides clang/ld/ar as absolute Xcode paths. Unlike
      // /usr/bin/cc, that clang does not discover the active macOS SDK on its
      // own, so Rust host build scripts otherwise fail to link libSystem.
      'SDKROOT': macOSSDKRoot,
    };
    final cCompiler = code.cCompiler;
    if (cCompiler != null) {
      final cargoTarget = target.toUpperCase().replaceAll('-', '_');
      final ccTarget = target.replaceAll('-', '_');
      final compiler = cCompiler.compiler.toFilePath();
      final archiver = cCompiler.archiver.toFilePath();
      environment
        ..['CARGO_TARGET_${cargoTarget}_LINKER'] = compiler
        ..['CC_$ccTarget'] = compiler
        ..['AR_$ccTarget'] = archiver
        ..['HOST_CC'] = compiler
        ..['HOST_AR'] = archiver;
    }
    final cargoArguments = <String>[
      'build',
      '--locked',
      '--release',
      '--manifest-path',
      manifest.toFilePath(),
      '--target',
      target,
    ];
    final startedAt = DateTime.now().toUtc();
    final cargoTimer = Stopwatch()..start();
    final result = await Process.run(
      'cargo',
      cargoArguments,
      workingDirectory: coreRoot.toFilePath(),
      environment: environment,
    );
    cargoTimer.stop();
    // Hook stdout is normally captured by Flutter. Persist an explicit metric
    // so CI can distinguish native compilation from test startup/execution.
    // Record only build configuration, never the entire process environment.
    final cargoTargetKey = target.toUpperCase().replaceAll('-', '_');
    final ccTargetKey = target.replaceAll('-', '_');
    final metric = <String, Object?>{
      'schema_version': 1,
      'started_at': startedAt.toIso8601String(),
      'elapsed_ms': cargoTimer.elapsedMilliseconds,
      'exit_code': result.exitCode,
      'profile': 'release',
      'target': target,
      'manifest_path': manifest.toFilePath(),
      'working_directory': coreRoot.toFilePath(),
      'target_directory': cargoTargetDirectory.toFilePath(),
      'arguments': cargoArguments,
      'build_environment': <String, String>{
        for (final key in <String>[
          'CARGO_BUILD_JOBS',
          'CARGO_TARGET_DIR',
          'CARGO_HOME',
          'RUSTUP_HOME',
          'MACOSX_DEPLOYMENT_TARGET',
          'SDKROOT',
          'CARGO_TARGET_${cargoTargetKey}_LINKER',
          'CC_$ccTargetKey',
          'AR_$ccTargetKey',
          'HOST_CC',
          'HOST_AR',
        ])
          if (environment.containsKey(key)) key: environment[key]!,
      },
    };
    await File.fromUri(
      input.outputDirectory.resolve('ianvs-cargo-build.json'),
    ).writeAsString('${jsonEncode(metric)}\n');
    stdout.writeln(
      'Native Cargo build: ${cargoTimer.elapsedMilliseconds} ms; '
      'target=$target; profile=release; exit=${result.exitCode}; '
      'directory=${cargoTargetDirectory.toFilePath()}',
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'cargo',
        cargoArguments,
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

Future<String> _macOSSDKRoot() async {
  final result = await Process.run('xcrun', const <String>[
    '--sdk',
    'macosx',
    '--show-sdk-path',
  ]);
  final sdkRoot = '${result.stdout}'.trim();
  if (result.exitCode != 0 ||
      sdkRoot.isEmpty ||
      !Directory(sdkRoot).existsSync()) {
    throw ProcessException(
      'xcrun',
      const <String>['--sdk', 'macosx', '--show-sdk-path'],
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  return sdkRoot;
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
