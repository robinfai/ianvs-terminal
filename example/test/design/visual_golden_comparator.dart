import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

/// Routes baselines by OS and permits bounded, low-amplitude edge differences.
/// This is not a font classifier: similarly small icon-edge changes can pass.
/// Updates and rejected-comparison artifacts retain Flutter's implementation.
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

  // Reviewed fixed-font CoreText differences affected at most 0.41029% of
  // pixels, with RGB deltas <= 52/255 and unchanged alpha. Keep limited headroom.
  static const double _maxChangedFraction = 0.0045;
  static const int _maxChannelDelta = 56;
  static const int _minEdgeContrast = 20;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    // Keep missing-baseline failures; tolerance never creates an expectation.
    final baseline = Uint8List.fromList(await getGoldenBytes(golden));
    final actual = await _decode(imageBytes);
    final expected = await _decode(baseline);
    if (_withinTolerance(actual, expected, golden)) return true;
    // Preserve Flutter's diff images and failure message for every rejection.
    return super.compare(imageBytes, golden);
  }

  bool _withinTolerance(_Pixels actual, _Pixels expected, Uri golden) {
    if (actual.width != expected.width || actual.height != expected.height) {
      return false;
    }
    final count = actual.width * actual.height;
    var changed = 0;
    var maximumDelta = 0;
    for (var pixel = 0; pixel < count; pixel++) {
      final offset = pixel * 4;
      if (actual.bytes[offset + 3] != expected.bytes[offset + 3]) return false;
      var differs = false;
      for (var channel = 0; channel < 3; channel++) {
        final delta =
            (actual.bytes[offset + channel] - expected.bytes[offset + channel])
                .abs();
        if (delta > _maxChannelDelta) return false;
        if (delta > maximumDelta) maximumDelta = delta;
        differs |= delta != 0;
      }
      if (!differs) continue;
      changed++;
      if (changed / count > _maxChangedFraction) return false;
      // Both images must already have an edge here. Requiring local contrast
      // >= twice the change rejects shifts of a solid-color boundary as well
      // as isolated color changes in otherwise flat regions.
      if (!_isSmallEdgeChange(actual, expected, pixel) ||
          !_isSmallEdgeChange(expected, actual, pixel)) {
        return false;
      }
    }
    if (changed != 0) {
      debugPrint(
        'Golden tolerance accepted "$golden": $changed/$count pixels '
        '(${(100 * changed / count).toStringAsFixed(5)}%), '
        'max RGB delta $maximumDelta/255.',
      );
    }
    return true;
  }

  bool _isSmallEdgeChange(_Pixels image, _Pixels other, int pixel) {
    final x = pixel % image.width;
    final y = pixel ~/ image.width;
    var strongestContrast = 0;
    for (var channel = 0; channel < 3; channel++) {
      var minimum = 255;
      var maximum = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= image.width || ny >= image.height) {
            continue;
          }
          final value = image.bytes[(ny * image.width + nx) * 4 + channel];
          if (value < minimum) minimum = value;
          if (value > maximum) maximum = value;
        }
      }
      final contrast = maximum - minimum;
      if (contrast > strongestContrast) strongestContrast = contrast;
      final delta =
          (image.bytes[pixel * 4 + channel] - other.bytes[pixel * 4 + channel])
              .abs();
      if (contrast < delta * 2) return false;
    }
    return strongestContrast >= _minEdgeContrast;
  }

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

// Only retain copied RGBA bytes; native codec/image handles are always disposed.
Future<_Pixels> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return _Pixels(image.width, image.height, data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

class _Pixels {
  const _Pixels(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final Uint8List bytes;
}
