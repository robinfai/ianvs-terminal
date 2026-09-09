import 'dart:io';
import 'package:app/startup/app_environment.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only non-release macOS builds select development', () {
    for (final platform in TargetPlatform.values) {
      expect(
        AppEnvironment.forBuild(platform: platform, releaseMode: true),
        AppEnvironment.production,
      );
      expect(
        AppEnvironment.forBuild(platform: platform, releaseMode: false),
        platform == TargetPlatform.macOS
            ? AppEnvironment.development
            : AppEnvironment.production,
      );
    }
  });
  test('development uses an isolated data directory', () {
    final root = Directory('/tmp/ianvs-environment-test');
    expect(AppEnvironment.production.supportDirectory(root).path, root.path);
    expect(
      AppEnvironment.development.supportDirectory(root).path,
      '${root.path}/development',
    );
  });
}
