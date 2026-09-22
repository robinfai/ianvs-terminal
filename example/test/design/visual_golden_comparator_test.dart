import 'dart:convert';
import 'dart:io';

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
    'inherited exact comparison rejects changed pixels and missing files',
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
}
