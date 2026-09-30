import 'dart:io';

/// Keeps explicit launch configuration authoritative while finding an available
/// login shell for a fresh Linux installation. A SHELL value is a program path,
/// never a command line to execute through another shell.
String resolveDefaultTerminalShell({
  String? operatingSystem,
  Map<String, String>? environment,
  String configuredShell = const String.fromEnvironment('IANVS_DEFAULT_SHELL'),
  bool Function(String path)? isExecutable,
}) {
  if (configuredShell.isNotEmpty) {
    return configuredShell;
  }
  if ((operatingSystem ?? Platform.operatingSystem) != 'linux') {
    return '/bin/zsh';
  }

  final canExecute = isExecutable ?? _isExecutableFile;
  final shell = environment == null
      ? Platform.environment['SHELL']
      : environment['SHELL'];
  for (final candidate in <String>[
    ?shell,
    '/bin/bash',
    '/usr/bin/bash',
    '/bin/sh',
    '/usr/bin/sh',
  ]) {
    if (candidate.startsWith('/') &&
        !candidate.contains('\u0000') &&
        canExecute(candidate)) {
      return candidate;
    }
  }
  throw StateError(
    'No executable Linux login shell was found. Set SHELL to an absolute '
    'executable path or configure IANVS_DEFAULT_SHELL for this build.',
  );
}

bool _isExecutableFile(String path) {
  try {
    final stat = File(path).statSync();
    // File.stat follows symlinks, including merged-/usr shell installations.
    return stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0;
  } on FileSystemException {
    return false;
  }
}
