import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Evaluated once per test isolate, even when several fixtures load fonts.
final int _hostMacosMajor = _readMacosMajor();

void installVisualGoldenComparator() {
  final current = goldenFileComparator;
  if (current is VisualGoldenComparator) return;
  if (current is! LocalFileComparator) {
    throw StateError('Visual captures require Flutter LocalFileComparator.');
  }
  goldenFileComparator = VisualGoldenComparator(
    current.basedir.resolve('visual_golden_comparator.dart'),
    macosMajor: _hostMacosMajor,
  );
}

int _readMacosMajor() {
  if (!Platform.isMacOS) {
    throw StateError('Visual captures require a supported macOS host.');
  }
  final result = Process.runSync('/usr/bin/sw_vers', ['-productVersion']);
  final version = result.stdout.toString().trim();
  final major = int.tryParse(version.split('.').first);
  if (result.exitCode != 0 || major == null) {
    throw StateError('Unable to determine macOS version: $version');
  }
  return major;
}

/// Routes only the baseline URI. Pixel comparison and updates are inherited
/// unchanged from Flutter's exact LocalFileComparator, including missing-file
/// failures. CoreText can rasterize identical font bytes differently by OS.
class VisualGoldenComparator extends LocalFileComparator {
  VisualGoldenComparator(super.testFile, {required this.macosMajor}) {
    if (macosMajor != 26 && macosMajor != 27) {
      throw StateError(
        'No reviewed visual baseline for macOS $macosMajor. '
        'Supported baseline versions are macOS 26 and 27; '
        'review a new OS baseline explicitly before enabling it.',
      );
    }
  }

  final int macosMajor;

  @override
  Uri getTestUri(Uri key, int? version) {
    if (key.hasScheme ||
        key.hasAbsolutePath ||
        key.pathSegments.length < 2 ||
        key.pathSegments.first != 'goldens' ||
        key.pathSegments.contains('..')) {
      throw ArgumentError.value(
        key,
        'key',
        'Expected a relative goldens/ key.',
      );
    }
    final versioned = super.getTestUri(key, version);
    return versioned.replace(
      pathSegments: [
        'goldens',
        'macos-$macosMajor',
        ...versioned.pathSegments.skip(1),
      ],
    );
  }
}
