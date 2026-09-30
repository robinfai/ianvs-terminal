import 'dart:io';

import 'package:flutter/foundation.dart';

/// Release keeps the established production identity and storage layout.
/// Desktop Debug/Profile builds use a separate local development installation.
enum AppEnvironment {
  production,
  development;

  static AppEnvironment forBuild({
    required TargetPlatform platform,
    required bool releaseMode,
  }) =>
      (platform == TargetPlatform.macOS || platform == TargetPlatform.linux) &&
          !releaseMode
      ? development
      : production;

  Directory supportDirectory(Directory platformDirectory) => this == development
      ? Directory(
          '${platformDirectory.path}${Platform.pathSeparator}development',
        )
      : platformDirectory;
}
