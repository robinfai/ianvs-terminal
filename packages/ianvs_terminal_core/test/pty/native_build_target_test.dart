import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../../hook/build.dart';

void main() {
  test('Linux desktop targets bundle GNU shared objects', () {
    expect(nativeBuildTarget(OS.linux, Architecture.x64), (
      triple: 'x86_64-unknown-linux-gnu',
      libraryName: 'libianvs_core.so',
    ));
    expect(nativeBuildTarget(OS.linux, Architecture.arm64), (
      triple: 'aarch64-unknown-linux-gnu',
      libraryName: 'libianvs_core.so',
    ));
  });

  test('macOS desktop targets retain their Darwin dynamic libraries', () {
    expect(nativeBuildTarget(OS.macOS, Architecture.x64), (
      triple: 'x86_64-apple-darwin',
      libraryName: 'libianvs_core.dylib',
    ));
    expect(nativeBuildTarget(OS.macOS, Architecture.arm64), (
      triple: 'aarch64-apple-darwin',
      libraryName: 'libianvs_core.dylib',
    ));
  });

  test('unsupported targets cannot silently build for the host', () {
    expect(
      () => nativeBuildTarget(OS.linux, Architecture.ia32),
      throwsUnsupportedError,
    );
    expect(
      () => nativeBuildTarget(OS.windows, Architecture.x64),
      throwsUnsupportedError,
    );
  });
}
