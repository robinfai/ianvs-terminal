import 'dart:io';

import 'package:test/test.dart';

import '../../hook/native_dependencies.dart';

void main() {
  test(
    'native hook tracks the complete source closure and excludes outputs',
    () {
      final root = Directory.systemTemp.createTempSync(
        'ianvs_native_dependency_closure_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      for (final path in <String>[
        'core/Cargo.toml',
        'core/Cargo.lock',
        'core/build.rs',
        'core/proto/frame.proto',
        'core/src/lib.rs',
        'vendor/parser/build.rs',
        'vendor/parser/src/font.ttf',
        'vendor/parser/src/generated/table.bin',
        'vendor/parser/src/lib.rs',
        'vendor/parser/target/debug/stale.dylib',
        'vendor/parser/build/generated/stale.rs',
        'vendor/parser/.git/index',
        'vendor/parser/.dart_tool/package_config.json',
      ]) {
        final file = File('${root.path}/$path');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(path);
      }

      final actual = nativeBuildDependencies(
        root.uri,
      ).map((file) => _relative(root, file)).toList(growable: false);

      expect(actual, <String>[
        'core/Cargo.lock',
        'core/Cargo.toml',
        'core/build.rs',
        'core/proto/frame.proto',
        'core/src/lib.rs',
        'vendor/parser/build.rs',
        'vendor/parser/src/font.ttf',
        'vendor/parser/src/generated/table.bin',
        'vendor/parser/src/lib.rs',
      ]);
    },
  );

  test('workspace and standalone hooks use the same dependency closure', () {
    final packageRoot = Directory.current.absolute;
    final repositoryRoot = packageRoot.parent.parent;
    final canonicalHelper = File(
      '${repositoryRoot.path}/packages/ianvs_pty/hook/'
      'native_dependencies.dart',
    ).readAsStringSync();
    final standaloneHelper = File(
      '${repositoryRoot.path}/packages/ianvs_terminal_core/hook/'
      'native_dependencies.dart',
    ).readAsStringSync();

    expect(standaloneHelper, canonicalHelper);
    final canonicalHook = File(
      '${repositoryRoot.path}/packages/ianvs_pty/hook/build.dart',
    ).readAsStringSync();
    final standaloneHook = File(
      '${repositoryRoot.path}/packages/ianvs_terminal_core/hook/build.dart',
    ).readAsStringSync();
    expect(
      _normalizeHook(standaloneHook),
      _normalizeHook(canonicalHook),
      reason: 'standalone hook may differ only in package identity and path',
    );

    for (final source in <String>[canonicalHook, standaloneHook]) {
      expect(source, contains('nativeBuildDependencies(nativeRoot)'));
      expect(source, contains('output.dependencies.add(dependency.uri)'));
      expect(source, contains("'CARGO_BUILD_JOBS': _cargoBuildJobs"));
      expect(source, contains("const _cargoBuildJobs = '2';"));
      expect(source, contains("'SDKROOT': macOSSDKRoot"));
      expect(source, contains('final macOSSDKRoot = await _macOSSDKRoot()'));
      expect(source, contains(r"..['CARGO_TARGET_${cargoTarget}_LINKER']"));
      expect(source, contains(r"..['CC_$ccTarget']"));
      expect(source, isNot(contains("path.endsWith('.rs')")));
      expect(source, isNot(contains("path.endsWith('.proto')")));
    }

    final semanticMutation = standaloneHook.replaceFirst(
      "'build',",
      "'check',",
    );
    expect(
      _normalizeHook(semanticMutation),
      isNot(_normalizeHook(canonicalHook)),
    );
  });
}

String _normalizeHook(String source) {
  return source
      .replaceAll('ianvs_terminal_core', 'ianvs_pty')
      .replaceAll(
        "input.packageRoot.resolve('native/')",
        "input.packageRoot.resolve('../../native/')",
      )
      .replaceAll(
        "'ianvs_pty native sources are missing from the package.'",
        "'ianvs_pty native sources are missing. Depend on the complete '\n"
            "        'ianvs-terminal repository, not a copied package directory.'",
      )
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(',);', ');');
}

String _relative(Directory root, File file) {
  final prefix = '${root.absolute.path}${Platform.pathSeparator}';
  return file.absolute.path
      .substring(prefix.length)
      .split(Platform.pathSeparator)
      .join('/');
}
