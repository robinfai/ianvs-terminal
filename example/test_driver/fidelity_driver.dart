import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final dir = Directory(
      Platform.environment['TRAIL_CAPTURE_DIR'] ??
          '../docs/design/apple-fidelity-20261102/simulator',
    );
    await dir.create(recursive: true);
    await File('${dir.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
);
