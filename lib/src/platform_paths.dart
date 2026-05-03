import 'dart:io';

String defaultUserHomePath({
  Map<String, String>? environment,
  String? operatingSystem,
  String? currentPath,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  final fallbackCurrentPath = currentPath ?? Directory.current.path;
  return switch (os) {
    'windows' =>
      _nonEmpty(env['USERPROFILE']) ??
          _nonEmpty(env['HOME']) ??
          fallbackCurrentPath,
    _ =>
      _nonEmpty(env['HOME']) ??
          _nonEmpty(env['USERPROFILE']) ??
          fallbackCurrentPath,
  };
}

String defaultTerminalStateDirectoryPath({
  Map<String, String>? environment,
  String? operatingSystem,
  String? currentPath,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  final fallbackCurrentPath = currentPath ?? Directory.current.path;
  final separator = pathSeparatorForOperatingSystem(os);
  return switch (os) {
    'macos' => joinPlatformPath(
      defaultUserHomePath(
        environment: env,
        operatingSystem: os,
        currentPath: fallbackCurrentPath,
      ),
      <String>['Library', 'Application Support', 'Ianvs', 'ianvs-terminal'],
      separator: separator,
    ),
    'windows' => joinPlatformPath(
      _nonEmpty(env['APPDATA']) ??
          defaultUserHomePath(
            environment: env,
            operatingSystem: os,
            currentPath: fallbackCurrentPath,
          ),
      <String>['Ianvs', 'ianvs-terminal'],
      separator: separator,
    ),
    'linux' => joinPlatformPath(
      _nonEmpty(env['XDG_STATE_HOME']) ??
          _linuxStateHome(
            home: _nonEmpty(env['HOME']),
            currentPath: fallbackCurrentPath,
          ),
      <String>['ianvs-terminal'],
      separator: separator,
    ),
    _ => joinPlatformPath(
      defaultUserHomePath(
        environment: env,
        operatingSystem: os,
        currentPath: fallbackCurrentPath,
      ),
      <String>['.ianvs-terminal'],
      separator: separator,
    ),
  };
}

String defaultTerminalSettingsFilePath({
  Map<String, String>? environment,
  String? operatingSystem,
  String? currentPath,
}) {
  return joinPlatformPath(
    defaultTerminalStateDirectoryPath(
      environment: environment,
      operatingSystem: operatingSystem,
      currentPath: currentPath,
    ),
    <String>['settings.json'],
    separator: pathSeparatorForOperatingSystem(
      operatingSystem ?? Platform.operatingSystem,
    ),
  );
}

String defaultSavedCommandsFilePath({
  Map<String, String>? environment,
  String? operatingSystem,
  String? currentPath,
}) {
  return joinPlatformPath(
    defaultTerminalStateDirectoryPath(
      environment: environment,
      operatingSystem: operatingSystem,
      currentPath: currentPath,
    ),
    <String>['saved_commands.json'],
    separator: pathSeparatorForOperatingSystem(
      operatingSystem ?? Platform.operatingSystem,
    ),
  );
}

String defaultTerminalSessionRestoreFilePath({
  Map<String, String>? environment,
  String? operatingSystem,
  String? currentPath,
}) {
  return joinPlatformPath(
    defaultTerminalStateDirectoryPath(
      environment: environment,
      operatingSystem: operatingSystem,
      currentPath: currentPath,
    ),
    <String>['session_restore.json'],
    separator: pathSeparatorForOperatingSystem(
      operatingSystem ?? Platform.operatingSystem,
    ),
  );
}

String defaultShellIntegrationZdotdirPath({
  Map<String, String>? environment,
  String? operatingSystem,
  String? currentPath,
}) {
  return joinPlatformPath(
    defaultTerminalStateDirectoryPath(
      environment: environment,
      operatingSystem: operatingSystem,
      currentPath: currentPath,
    ),
    <String>['shell-integration', 'zsh'],
    separator: pathSeparatorForOperatingSystem(
      operatingSystem ?? Platform.operatingSystem,
    ),
  );
}

String joinPlatformPath(
  String base,
  List<String> segments, {
  required String separator,
}) {
  final normalizedBase = base.trim();
  final normalizedSegments = segments
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (normalizedSegments.isEmpty) {
    return normalizedBase;
  }
  final trimmedBase = normalizedBase.endsWith(separator)
      ? normalizedBase.substring(0, normalizedBase.length - separator.length)
      : normalizedBase;
  return <String>[trimmedBase, ...normalizedSegments].join(separator);
}

String pathSeparatorForOperatingSystem(String operatingSystem) {
  return operatingSystem == 'windows' ? '\\' : '/';
}

String _linuxStateHome({required String? home, required String currentPath}) {
  if (home == null || home.isEmpty) {
    return currentPath;
  }
  return '$home/.local/state';
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
