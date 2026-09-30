import 'dart:io';

import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory executable;
  late Directory working;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ianvs-library-resolution-');
    executable = Directory('${root.path}/bundle')..createSync();
    working = Directory('${root.path}/source/example')
      ..createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  File library(String relative) {
    return File('${root.path}/$relative')
      ..createSync(recursive: true)
      ..writeAsStringSync('library path fixture');
  }

  String resolve({
    String os = 'linux',
    bool product = true,
    Map<String, String> environment = const <String, String>{},
  }) => resolveNativePtyLibraryPath(
    operatingSystem: os,
    environment: environment,
    executableDirectory: executable,
    workingDirectory: working,
    isProduct: product,
  );

  test('Linux release prefers Flutter bundled lib over adjacent library', () {
    final bundled = library('bundle/lib/libianvs_core.so');
    library('bundle/libianvs_core.so');
    expect(resolve(), bundled.absolute.path);
  });

  test('Linux accepts an adjacent shared object in a custom bundle', () {
    final adjacent = library('bundle/libianvs_core.so');
    expect(resolve(), adjacent.absolute.path);
  });

  test('Linux never loads an Apple library', () {
    library('Frameworks/ianvs_core.framework/ianvs_core');
    library('bundle/lib/libianvs_core.dylib');
    expect(
      resolve,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Unable to locate libianvs_core.so.'),
        ),
      ),
    );
  });

  test('product builds ignore overrides and source-tree debug libraries', () {
    final override = library('override/libianvs_core.so');
    library('source/native/core/target/debug/libianvs_core.so');
    final environment = <String, String>{'IANVS_CORE_LIB': override.path};
    expect(
      () => resolve(environment: environment),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('IANVS_CORE_LIB is ignored in product builds.'),
        ),
      ),
    );
    final bundled = library('bundle/lib/libianvs_core.so');
    expect(resolve(environment: environment), bundled.absolute.path);
  });

  test('development builds prefer an explicit native library', () {
    final override = library('override/libianvs_core.so');
    library('bundle/lib/libianvs_core.so');
    expect(
      resolve(
        product: false,
        environment: <String, String>{'IANVS_CORE_LIB': override.path},
      ),
      override.path,
    );
  });

  for (final os in <String>['linux', 'macos']) {
    test('development builds find Flutter test assets on $os', () {
      final libraryName = os == 'linux'
          ? 'libianvs_core.so'
          : 'libianvs_core.dylib';
      final asset = library(
        'source/example/build/native_assets/$os/$libraryName',
      );
      library('source/native/core/target/debug/$libraryName');
      expect(resolve(os: os, product: false), asset.absolute.path);
      expect(() => resolve(os: os), throwsStateError);
    });
  }

  test('development builds locate native debug output from the workspace', () {
    final debug = library('source/native/core/target/debug/libianvs_core.so');
    expect(resolve(product: false), debug.absolute.path);
  });

  test(
    'development builds locate standalone native output from executable',
    () {
      executable = Directory('${root.path}/standalone/build/bin')
        ..createSync(recursive: true);
      final debug = library(
        'standalone/native/core/target/debug/libianvs_core.so',
      );
      expect(resolve(product: false), debug.absolute.path);
    },
  );

  test('macOS dylib fallback remains available', () {
    final dylib = library('Frameworks/libianvs_core.dylib');
    expect(
      File(resolve(os: 'macos')).absolute.uri.normalizePath(),
      dylib.absolute.uri.normalizePath(),
    );
  });

  test('unsupported platforms report a useful error', () {
    expect(() => resolve(os: 'windows'), throwsUnsupportedError);
  });
}
