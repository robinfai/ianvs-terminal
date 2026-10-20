import 'dart:io';

/// Host paths used only to locate an installed ACP adapter. These overrides
/// are not forwarded to the agent or used as model/Data API configuration.
Map<String, String> readAcpDiscoveryEnvironment() => _definedValues({
  'PATH': Platform.environment['PATH'],
  'HOME': Platform.environment['HOME'],
  'FNM_DIR': Platform.environment['FNM_DIR'],
  'NVM_DIR': Platform.environment['NVM_DIR'],
  'VOLTA_HOME': Platform.environment['VOLTA_HOME'],
  'ASDF_DATA_DIR': Platform.environment['ASDF_DATA_DIR'],
  'npm_config_prefix': Platform.environment['npm_config_prefix'],
  'NPM_CONFIG_PREFIX': Platform.environment['NPM_CONFIG_PREFIX'],
});

/// The existing minimal executable/locale environment for the isolated agent.
Map<String, String> readAcpProcessEnvironment() => _definedValues({
  'PATH': Platform.environment['PATH'],
  'HOME': Platform.environment['HOME'],
  'USER': Platform.environment['USER'],
  'TMPDIR': Platform.environment['TMPDIR'],
  'LANG': Platform.environment['LANG'],
  'LC_ALL': Platform.environment['LC_ALL'],
});

/// Locates the existing Codex login without exposing it as a child override.
String readCodexAuthenticationPath() =>
    '${Platform.environment['CODEX_HOME'] ?? '${Platform.environment['HOME'] ?? ''}/.codex'}/auth.json';

Map<String, String> _definedValues(Map<String, String?> values) =>
    Map.unmodifiable({
      for (final entry in values.entries)
        if (entry.value != null) entry.key: entry.value,
    });
