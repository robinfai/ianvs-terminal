import 'dart:io';

import 'package:flutter/foundation.dart';

/// Release keeps the established production identity and storage layout.
/// macOS Debug/Profile builds use a separate local development installation.
enum AppEnvironment {
  production,
  development;

  static AppEnvironment get current =>
      forBuild(platform: defaultTargetPlatform, releaseMode: kReleaseMode);

  static AppEnvironment forBuild({
    required TargetPlatform platform,
    required bool releaseMode,
  }) => platform == TargetPlatform.macOS && !releaseMode
      ? development
      : production;

  Directory supportDirectory(Directory platformDirectory) => this == development
      ? Directory(
          // The predecessor directory used a Keychain-only master key. Keep
          // it intact instead of opening its ciphertext with a new file key.
          '${platformDirectory.path}${Platform.pathSeparator}development-file-v1',
        )
      : platformDirectory;
}
