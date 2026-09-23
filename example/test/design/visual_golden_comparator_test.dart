import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visual_golden_comparator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('routes nested golden keys and Flutter versions to the host OS', () {
    for (final major in [26, 27]) {
      final comparator = VisualGoldenComparator(
        File('test/design/capture_test.dart').absolute.uri,
        macosMajor: major,
      );
      expect(
        comparator.getTestUri(
          Uri.parse('goldens/group/current/light.png'),
          null,
        ),
        Uri.parse('goldens/macos-$major/group/current/light.png'),
      );
      expect(
        comparator.getTestUri(Uri.parse('goldens/group/current/light.png'), 2),
        Uri.parse('goldens/macos-$major/group/current/light.2.png'),
      );
    }
  });

  test('an unreviewed macOS version fails explicitly', () {
    expect(
      () => VisualGoldenComparator(
        File('test/design/capture_test.dart').absolute.uri,
        macosMajor: 28,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('keys cannot bypass the OS baseline directory', () {
    final comparator = VisualGoldenComparator(
      File('test/design/capture_test.dart').absolute.uri,
      macosMajor: 27,
    );
    for (final key in [
      'other/image.png',
      '/goldens/image.png',
      '../image.png',
    ]) {
      expect(
        () => comparator.getTestUri(Uri.parse(key), null),
        throwsArgumentError,
      );
    }
  });

  test(
    'updates only the host OS and rejects large changes and missing files',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'visual-golden-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final comparator = VisualGoldenComparator(
        directory.uri.resolve('capture_test.dart'),
        macosMajor: 27,
      );
      final golden = comparator.getTestUri(
        Uri.parse('goldens/nested/pixel.png'),
        null,
      );
      final red = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
      );
      final blue = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/5ncLrgAAAABJRU5ErkJggg==',
      );
      await comparator.update(golden, red);
      expect(
        File.fromUri(directory.uri.resolveUri(golden)).readAsBytesSync(),
        red,
      );
      expect(
        Directory.fromUri(
          directory.uri.resolve('goldens/macos-26/'),
        ).existsSync(),
        isFalse,
      );
      expect(await comparator.compare(red, golden), isTrue);
      await expectLater(
        comparator.compare(blue, golden),
        throwsA(isA<FlutterError>()),
      );
      await expectLater(
        comparator.compare(
          red,
          comparator.getTestUri(Uri.parse('goldens/missing.png'), null),
        ),
        throwsA(isA<TestFailure>()),
      );
    },
  );
  group('bounded edge tolerance', () {
    late Directory directory;
    late VisualGoldenComparator comparator;
    late Uri golden;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('visual-edge-test-');
      comparator = VisualGoldenComparator(
        directory.uri.resolve('capture_test.dart'),
        macosMajor: 27,
      );
      golden = comparator.getTestUri(Uri.parse('goldens/edge.png'), null);
    });
    tearDown(() => directory.deleteSync(recursive: true));

    Future<void> compare(
      Uint8List baseline,
      Uint8List actual, {
      required bool passes,
    }) async {
      await comparator.update(golden, baseline);
      if (passes) {
        expect(await comparator.compare(actual, golden), isTrue);
      } else {
        await expectLater(
          comparator.compare(actual, golden),
          throwsA(isA<FlutterError>()),
        );
      }
    }

    // A grayscale antialiased stroke edge: black / intermediate / white.
    int edge(int x, int y) => [0, 128, 255][x % 3];

    test('accepts edge deltas at both amplitude and area limits', () async {
      await compare(
        await _png(100, 100, edge),
        await _png(100, 100, (x, y) => x == 1 && y < 45 ? 184 : edge(x, y)),
        passes: true,
      );
    });

    test('rejects even one edge pixel above the channel limit', () async {
      await compare(
        await _png(100, 100, edge),
        await _png(100, 100, (x, y) => x == 1 && y == 1 ? 185 : edge(x, y)),
        passes: false,
      );
    });

    test(
      'rejects a single large color change and writes diff artifacts',
      () async {
        await compare(
          await _png(100, 100, (_, _) => 255),
          await _png(100, 100, (x, y) => x == 50 && y == 50 ? 0 : 255),
          passes: false,
        );
        expect(
          directory.listSync().whereType<Directory>().any(
            (entry) => entry.path.endsWith('failures'),
          ),
          isTrue,
        );
      },
    );

    test('rejects small edge deltas above the changed pixel limit', () async {
      await compare(
        await _png(100, 100, edge),
        await _png(100, 100, (x, y) => x == 1 && y < 46 ? 129 : edge(x, y)),
        passes: false,
      );
    });

    test(
      'rejects a one pixel shift of a low contrast rectangular region',
      () async {
        int rectangle(int x, int y) =>
            x >= 40 && x < 60 && y >= 40 && y < 60 ? 140 : 100;
        // Only 40/40000 pixels change, by 40: amplitude and area alone
        // would accept this real geometry change; the edge ratio rejects it.
        await compare(
          await _png(200, 200, rectangle),
          await _png(200, 200, (x, y) => rectangle(x - 1, y)),
          passes: false,
        );
      },
    );

    test('rejects a tiny color change away from existing edges', () async {
      await compare(
        await _png(100, 100, (_, _) => 100),
        await _png(100, 100, (x, y) => x == 50 && y == 50 ? 101 : 100),
        passes: false,
      );
    });

    test('rejects an alpha change at an otherwise eligible edge', () async {
      await compare(
        await _png(100, 100, edge),
        await _png(
          100,
          100,
          edge,
          alpha: (x, y) => x == 1 && y == 1 ? 254 : 255,
        ),
        passes: false,
      );
    });

    test('rejects different image dimensions', () async {
      await compare(
        await _png(100, 100, edge),
        await _png(101, 100, edge),
        passes: false,
      );
    });
  });
}

Future<Uint8List> _png(
  int width,
  int height,
  int Function(int x, int y) value, {
  int Function(int x, int y)? alpha,
}) async {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      bytes[offset] = bytes[offset + 1] = bytes[offset + 2] = value(x, y);
      bytes[offset + 3] = alpha?.call(x, y) ?? 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
