import 'dart:io';

/// Every file that can affect the native build.
///
/// Cargo package sources include more than `.rs` and manifests: build scripts
/// can use `include_bytes!`, `include_str!`, or arbitrary generated inputs.
/// Track the complete checked-in native tree and exclude only output/VCS
/// directories so Flutter's native-asset cache cannot reuse a stale dylib.
Iterable<File> nativeBuildDependencies(Uri nativeRoot) sync* {
  final root = Directory.fromUri(nativeRoot).absolute;
  final rootPrefix = root.path.endsWith(Platform.pathSeparator)
      ? root.path
      : '${root.path}${Platform.pathSeparator}';
  final files =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  for (final file in files) {
    final absolute = file.absolute.path;
    if (!absolute.startsWith(rootPrefix)) {
      continue;
    }
    final components = absolute
        .substring(rootPrefix.length)
        .split(Platform.pathSeparator);
    if (components.any(_excludedNativeDirectory)) {
      continue;
    }
    yield file;
  }
}

bool _excludedNativeDirectory(String component) =>
    component == 'target' ||
    component == 'build' ||
    component == '.git' ||
    component == '.dart_tool';
