import 'dart:convert';

import 'terminal_config.dart';
import 'terminal_defaults.dart';

const int terminalSessionConfigSchemaVersion = 1;
const String terminalSessionConfigContract = 'ianvs-session-config-v1';

/// A structured boundary failure for the product-neutral SessionConfig wire.
final class TerminalSessionConfigContractException implements Exception {
  const TerminalSessionConfigContractException({
    required this.code,
    required this.path,
    required this.message,
  });

  final String code;
  final String path;
  final String message;

  @override
  String toString() =>
      'TerminalSessionConfigContractException($code at $path: $message)';
}

/// Versioned, product-neutral session creation payload shared with the native
/// runtime. Schema evolution requires a new version; unknown fields fail closed.
final class TerminalSessionConfigV1 {
  const TerminalSessionConfigV1({
    required this.sessionId,
    required this.displayName,
    required this.config,
    this.zmodemEnabled = false,
  });

  static const int maxEncodedBytes = 1024 * 1024;
  static const int _maxSessionIdLength = 128;
  static const int _maxDisplayNameLength = 256;
  static const int _maxProgramLength = 4096;
  static const int _maxStringBytes = 64 * 1024;
  static const int _maxGraphicsBytes = 1024 * 1024 * 1024;

  int get schemaVersion => terminalSessionConfigSchemaVersion;
  String get contract => terminalSessionConfigContract;
  final String sessionId;
  final String displayName;
  final TerminalSessionConfig config;

  /// Explicit native protocol interception opt-in. It defaults off so an
  /// independently upgraded native library cannot change old-client PTY
  /// semantics.
  final bool zmodemEnabled;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': schemaVersion,
      'contract': contract,
      'session_id': sessionId,
      'display_name': displayName,
      'client_capabilities': <String, Object?>{'zmodem': zmodemEnabled},
      'config': _sessionConfigWireJson(config),
    };
  }

  String toJsonString() {
    final json = toJson();
    TerminalSessionConfigV1.fromJson(json);
    final encoded = jsonEncode(json);
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const TerminalSessionConfigContractException(
        code: 'encoded_config_too_large',
        path: r'$',
        message: 'encoded SessionConfig exceeds 1 MiB',
      );
    }
    return encoded;
  }

  factory TerminalSessionConfigV1.fromJsonString(String raw) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const TerminalSessionConfigContractException(
        code: 'encoded_config_too_large',
        path: r'$',
        message: 'encoded SessionConfig exceeds 1 MiB',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw TerminalSessionConfigContractException(
        code: 'invalid_json',
        path: r'$',
        message: error.message,
      );
    }
    if (decoded is! Map) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_type',
        path: r'$',
        message: 'SessionConfig must be a JSON object',
      );
    }
    return TerminalSessionConfigV1.fromJson(_objectMap(decoded, r'$'));
  }

  factory TerminalSessionConfigV1.fromJson(Map<String, Object?> json) {
    _expectOnlyKeys(json, const <String>{
      'schema_version',
      'contract',
      'session_id',
      'display_name',
      'client_capabilities',
      'config',
    }, r'$');
    final schemaVersion = json['schema_version'];
    if (schemaVersion is! int ||
        schemaVersion != terminalSessionConfigSchemaVersion) {
      throw const TerminalSessionConfigContractException(
        code: 'unsupported_schema',
        path: r'$.schema_version',
        message: 'expected schema version $terminalSessionConfigSchemaVersion',
      );
    }
    if (json['contract'] != terminalSessionConfigContract) {
      throw const TerminalSessionConfigContractException(
        code: 'unsupported_contract',
        path: r'$.contract',
        message: 'expected ianvs-session-config-v1',
      );
    }
    _expectRequiredKeys(json, const <String>{
      'schema_version',
      'contract',
      'session_id',
      'display_name',
      'client_capabilities',
      'config',
    }, r'$');
    final sessionId = _boundedRequiredString(
      json['session_id'],
      path: r'$.session_id',
      maximum: _maxSessionIdLength,
    );
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(sessionId)) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_session_id',
        path: r'$.session_id',
        message: 'session_id contains unsupported characters',
      );
    }
    final displayName = _boundedRequiredString(
      json['display_name'],
      path: r'$.display_name',
      maximum: _maxDisplayNameLength,
    );
    final rawClientCapabilities = json['client_capabilities'];
    final clientCapabilities = _objectMap(
      rawClientCapabilities,
      r'$.client_capabilities',
    );
    _expectOnlyKeys(clientCapabilities, const <String>{
      'zmodem',
    }, r'$.client_capabilities');
    _expectRequiredKeys(clientCapabilities, const <String>{
      'zmodem',
    }, r'$.client_capabilities');
    final rawZmodem = clientCapabilities['zmodem'];
    if (rawZmodem is! bool) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_type',
        path: r'$.client_capabilities.zmodem',
        message: 'zmodem must be a boolean',
      );
    }
    final rawConfig = json['config'];
    if (rawConfig == null) {
      throw const TerminalSessionConfigContractException(
        code: 'missing_field',
        path: r'$.config',
        message: 'config is required',
      );
    }
    final configJson = _objectMap(rawConfig, r'$.config');
    _validateExactSessionConfigWireShape(configJson);
    _validateExactSessionConfigWireValues(configJson);
    if (utf8.encode(jsonEncode(json)).length > maxEncodedBytes) {
      throw const TerminalSessionConfigContractException(
        code: 'encoded_config_too_large',
        path: r'$',
        message: 'encoded SessionConfig exceeds 1 MiB',
      );
    }
    final rawLaunch = configJson['launch'];
    if (rawLaunch == null) {
      throw const TerminalSessionConfigContractException(
        code: 'missing_field',
        path: r'$.config.launch',
        message: 'launch is required',
      );
    }
    final launch = _objectMap(rawLaunch, r'$.config.launch');
    final program = launch['program'];
    final connection = TerminalConnectionConfig.fromJson(
      configJson['connection'],
    );
    if (program is! String ||
        program.length > _maxProgramLength ||
        program.contains('\u0000') ||
        (connection.type == TerminalConnectionType.local &&
            (program.trim().isEmpty ||
                program.runes.any((rune) => rune < 0x20 && rune != 0x09)))) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_launch_program',
        path: r'$.config.launch.program',
        message: 'launch program must be a non-empty bounded string',
      );
    }
    if (connection.isSsh &&
        (connection.host.isEmpty ||
            connection.user.isEmpty ||
            connection.port < 1 ||
            connection.port > 65535 ||
            connection.portForwards.length > maxTerminalLaunchArgs ||
            connection.portForwards.any(
              (forward) =>
                  forward.bindHost.isEmpty ||
                  forward.bindPort < 1 ||
                  forward.bindPort > 65535 ||
                  (forward.type == TerminalSshPortForwardType.dynamic
                      ? forward.targetHost.isNotEmpty || forward.targetPort != 0
                      : forward.targetHost.isEmpty ||
                            forward.targetPort < 1 ||
                            forward.targetPort > 65535),
            ) ||
            (connection.x11Forwarding &&
                (connection.x11AuthProtocol.isEmpty ||
                    switch ((
                      connection.x11TargetHost,
                      connection.x11TargetPort,
                    )) {
                      (null, 0) => false,
                      (final String host, final int port) =>
                        host.isEmpty || port < 1 || port > 65535,
                      _ => true,
                    })))) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_ssh_connection',
        path: r'$.config.connection',
        message: 'SSH host, user, and port must be valid',
      );
    }
    _validateStringList(
      launch['args'],
      path: r'$.config.launch.args',
      maximum: maxTerminalLaunchArgs,
    );
    _validateStringMap(
      launch['env'],
      path: r'$.config.launch.env',
      maximum: maxTerminalEnvironmentEntries,
    );
    final cwd = launch['cwd'];
    if (cwd != null && (cwd is! String || cwd.length > _maxProgramLength)) {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_type',
        path: r'$.config.launch.cwd',
        message: 'cwd must be null or a bounded string',
      );
    }
    try {
      return TerminalSessionConfigV1(
        sessionId: sessionId,
        displayName: displayName,
        config: TerminalSessionConfig.fromJson(configJson),
        zmodemEnabled: rawZmodem,
      );
    } on FormatException catch (error) {
      throw TerminalSessionConfigContractException(
        code: 'unknown_field',
        path: r'$.config',
        message: error.message,
      );
    }
  }
}

void _validateExactSessionConfigWireValues(Map<String, Object?> config) {
  final launch = _objectMap(config['launch'], r'$.config.launch');
  _boundedString(
    launch['program'],
    path: r'$.config.launch.program',
    maximum: TerminalSessionConfigV1._maxProgramLength,
  );
  _validateRequiredStringList(
    launch['args'],
    path: r'$.config.launch.args',
    maximumEntries: maxTerminalLaunchArgs,
    maximumStringBytes: TerminalSessionConfigV1._maxStringBytes,
    allowEmpty: true,
  );
  _validateRequiredStringMap(
    launch['env'],
    path: r'$.config.launch.env',
    maximumEntries: maxTerminalEnvironmentEntries,
  );
  _validateNullableString(
    launch['cwd'],
    path: r'$.config.launch.cwd',
    maximum: TerminalSessionConfigV1._maxProgramLength,
    allowEmpty: false,
  );

  _validateRawConnection(config['connection']);

  final terminal = _objectMap(config['terminal'], r'$.config.terminal');
  _requiredEnum(
    terminal['emulation'],
    path: r'$.config.terminal.emulation',
    values: const <String>{'xterm256', 'vt220'},
  );
  _requiredBoundedInt(
    terminal['scrollbackLines'],
    path: r'$.config.terminal.scrollbackLines',
    minimum: 1,
    maximum: maxTerminalScrollbackLines,
  );
  _requiredBool(
    terminal['dragDropEnabled'],
    path: r'$.config.terminal.dragDropEnabled',
  );
  final graphics = _objectMap(
    terminal['graphics'],
    r'$.config.terminal.graphics',
  );
  _requiredBool(
    graphics['enabled'],
    path: r'$.config.terminal.graphics.enabled',
  );
  _requiredEnum(
    graphics['advertise'],
    path: r'$.config.terminal.graphics.advertise',
    values: const <String>{'auto', 'kitty', 'none'},
  );
  final maxImageBytes = _requiredBoundedInt(
    graphics['maxImageBytes'],
    path: r'$.config.terminal.graphics.maxImageBytes',
    minimum: 1,
    maximum: TerminalSessionConfigV1._maxGraphicsBytes,
  );
  final maxTotalBytes = _requiredBoundedInt(
    graphics['maxTotalBytes'],
    path: r'$.config.terminal.graphics.maxTotalBytes',
    minimum: 1,
    maximum: TerminalSessionConfigV1._maxGraphicsBytes,
  );
  if (maxImageBytes > maxTotalBytes) {
    throw const TerminalSessionConfigContractException(
      code: 'invalid_integer',
      path: r'$.config.terminal.graphics.maxImageBytes',
      message: 'maxImageBytes must not exceed maxTotalBytes',
    );
  }

  final shellIntegration = _objectMap(
    config['shellIntegration'],
    r'$.config.shellIntegration',
  );
  _requiredBool(
    shellIntegration['enabled'],
    path: r'$.config.shellIntegration.enabled',
  );

  final appearance = _objectMap(config['appearance'], r'$.config.appearance');
  final font = _objectMap(appearance['font'], r'$.config.appearance.font');
  _boundedRequiredString(
    font['family'],
    path: r'$.config.appearance.font.family',
    maximum: TerminalSessionConfigV1._maxStringBytes,
  );
  _validateRequiredStringList(
    font['fallback'],
    path: r'$.config.appearance.font.fallback',
    maximumEntries: maxTerminalFontFallbackFamilies,
    maximumStringBytes: TerminalSessionConfigV1._maxStringBytes,
    allowEmpty: false,
  );
  _requiredPositiveFiniteNumber(
    font['size'],
    path: r'$.config.appearance.font.size',
    maximum: 512,
  );
  _requiredPositiveFiniteNumber(
    font['lineHeight'],
    path: r'$.config.appearance.font.lineHeight',
    maximum: 10,
  );

  final colors = _objectMap(
    appearance['colors'],
    r'$.config.appearance.colors',
  );
  final colorGroups = <String, List<String>>{
    'special': const <String>[
      'foreground',
      'background',
      'cursor',
      'selection',
      'tab',
    ],
    'normal': const <String>[
      'black',
      'red',
      'green',
      'yellow',
      'blue',
      'magenta',
      'cyan',
      'white',
    ],
    'bright': const <String>[
      'black',
      'red',
      'green',
      'yellow',
      'blue',
      'magenta',
      'cyan',
      'white',
    ],
  };
  for (final group in colorGroups.entries) {
    final values = _objectMap(
      colors[group.key],
      '\$.config.appearance.colors.${group.key}',
    );
    for (final field in group.value) {
      _validateNullableHexColor(
        values[field],
        path: '\$.config.appearance.colors.${group.key}.$field',
      );
    }
  }

  final cursor = _objectMap(
    appearance['cursor'],
    r'$.config.appearance.cursor',
  );
  _requiredEnum(
    cursor['shape'],
    path: r'$.config.appearance.cursor.shape',
    values: const <String>{'block', 'underline', 'beam'},
  );
  _requiredBool(cursor['blink'], path: r'$.config.appearance.cursor.blink');

  final interaction = _objectMap(
    config['interaction'],
    r'$.config.interaction',
  );
  _requiredBool(
    interaction['copyOnSelect'],
    path: r'$.config.interaction.copyOnSelect',
  );
  _requiredEnum(
    interaction['optionDragMode'],
    path: r'$.config.interaction.optionDragMode',
    values: const <String>{'normal_selection', 'block_selection'},
  );
}

Map<String, Object?> _sessionConfigWireJson(TerminalSessionConfig config) {
  final json = config.toJson();
  final connection = json['connection']! as Map<String, Object?>;
  if (connection['type'] == 'ssh') {
    for (final field in _nullableSshConnectionFields) {
      connection.putIfAbsent(field, () => null);
    }
    final jumps = connection['proxyJumpProfiles']! as List<Object?>;
    for (final value in jumps) {
      final jump = value! as Map<String, Object?>;
      for (final field in _nullableSshJumpFields) {
        jump.putIfAbsent(field, () => null);
      }
    }
  }
  return json;
}

const Set<String> _nullableSshConnectionFields = <String>{
  'password',
  'privateKeyPassphrase',
  'knownHostsFile',
  'proxyCommand',
  'proxyJump',
  'agentSocket',
  'x11TargetHost',
  'x11AuthCookie',
};

const Set<String> _nullableSshJumpFields = <String>{
  'password',
  'privateKeyPassphrase',
  'knownHostsFile',
};

const Set<String> _sshConnectionWireKeys = <String>{
  'type',
  'host',
  'user',
  'port',
  'auth',
  'password',
  'privateKeys',
  'privateKeyPassphrase',
  'hostKeyPolicy',
  'knownHostsFile',
  'connectTimeoutSeconds',
  'keepaliveSeconds',
  'keepaliveCountMax',
  'proxyCommand',
  'proxyJump',
  'proxyJumpProfiles',
  'portForwards',
  'agentForwarding',
  'agentSocket',
  'x11Forwarding',
  'x11TargetHost',
  'x11TargetPort',
  'x11AuthProtocol',
  'x11AuthCookie',
  'x11ScreenNumber',
};

void _validateExactSessionConfigWireShape(Map<String, Object?> config) {
  _expectExactObject(config, const <String>{
    'launch',
    'connection',
    'terminal',
    'shellIntegration',
    'appearance',
    'interaction',
  }, r'$.config');
  _expectExactObject(config['launch'], const <String>{
    'program',
    'args',
    'env',
    'cwd',
  }, r'$.config.launch');

  final connection = _objectMap(config['connection'], r'$.config.connection');
  switch (connection['type']) {
    case 'local':
      _expectExactObject(connection, const <String>{
        'type',
      }, r'$.config.connection');
    case 'ssh':
      _expectExactObject(
        connection,
        _sshConnectionWireKeys,
        r'$.config.connection',
      );
      _expectExactObjectList(connection['proxyJumpProfiles'], const <String>{
        'host',
        'user',
        'port',
        'auth',
        'password',
        'privateKeys',
        'privateKeyPassphrase',
        'hostKeyPolicy',
        'knownHostsFile',
        'connectTimeoutSeconds',
        'keepaliveSeconds',
        'keepaliveCountMax',
      }, r'$.config.connection.proxyJumpProfiles');
      _expectExactObjectList(connection['portForwards'], const <String>{
        'type',
        'bindHost',
        'bindPort',
        'targetHost',
        'targetPort',
      }, r'$.config.connection.portForwards');
    default:
      throw const TerminalSessionConfigContractException(
        code: 'invalid_enum',
        path: r'$.config.connection.type',
        message: 'type must be local or ssh',
      );
  }

  final terminal = _expectExactObject(config['terminal'], const <String>{
    'emulation',
    'scrollbackLines',
    'graphics',
    'dragDropEnabled',
  }, r'$.config.terminal');
  _expectExactObject(terminal['graphics'], const <String>{
    'enabled',
    'advertise',
    'maxImageBytes',
    'maxTotalBytes',
  }, r'$.config.terminal.graphics');
  _expectExactObject(config['shellIntegration'], const <String>{
    'enabled',
  }, r'$.config.shellIntegration');
  final appearance = _expectExactObject(config['appearance'], const <String>{
    'font',
    'colors',
    'cursor',
  }, r'$.config.appearance');
  _expectExactObject(appearance['font'], const <String>{
    'family',
    'fallback',
    'size',
    'lineHeight',
  }, r'$.config.appearance.font');
  final colors = _expectExactObject(appearance['colors'], const <String>{
    'special',
    'normal',
    'bright',
  }, r'$.config.appearance.colors');
  _expectExactObject(colors['special'], const <String>{
    'foreground',
    'background',
    'cursor',
    'selection',
    'tab',
  }, r'$.config.appearance.colors.special');
  const ansiKeys = <String>{
    'black',
    'red',
    'green',
    'yellow',
    'blue',
    'magenta',
    'cyan',
    'white',
  };
  _expectExactObject(
    colors['normal'],
    ansiKeys,
    r'$.config.appearance.colors.normal',
  );
  _expectExactObject(
    colors['bright'],
    ansiKeys,
    r'$.config.appearance.colors.bright',
  );
  _expectExactObject(appearance['cursor'], const <String>{
    'shape',
    'blink',
  }, r'$.config.appearance.cursor');
  _expectExactObject(config['interaction'], const <String>{
    'copyOnSelect',
    'optionDragMode',
  }, r'$.config.interaction');
}

Map<String, Object?> _expectExactObject(
  Object? value,
  Set<String> keys,
  String path,
) {
  final object = _objectMap(value, path);
  _expectOnlyKeys(object, keys, path);
  _expectRequiredKeys(object, keys, path);
  return object;
}

void _expectExactObjectList(Object? value, Set<String> keys, String path) {
  if (value is! List) {
    throw TerminalSessionConfigContractException(
      code: value == null ? 'missing_field' : 'invalid_collection',
      path: path,
      message: 'expected an array',
    );
  }
  for (var index = 0; index < value.length; index += 1) {
    _expectExactObject(value[index], keys, '$path[$index]');
  }
}

void _validateRawConnection(Object? value) {
  if (value == null) {
    throw const TerminalSessionConfigContractException(
      code: 'missing_field',
      path: r'$.config.connection',
      message: 'connection is required',
    );
  }
  final connection = _objectMap(value, r'$.config.connection');
  final type = connection['type'];
  if (type != 'local' && type != 'ssh') {
    throw const TerminalSessionConfigContractException(
      code: 'invalid_enum',
      path: r'$.config.connection.type',
      message: 'type must be local or ssh',
    );
  }
  if (type == 'local') {
    return;
  }

  _boundedRequiredString(
    connection['host'],
    path: r'$.config.connection.host',
    maximum: 4096,
  );
  _boundedRequiredString(
    connection['user'],
    path: r'$.config.connection.user',
    maximum: TerminalSessionConfigV1._maxDisplayNameLength,
  );
  _requiredBoundedInt(
    connection['port'],
    path: r'$.config.connection.port',
    minimum: 1,
    maximum: 65535,
  );
  _requiredEnum(
    connection['auth'],
    path: r'$.config.connection.auth',
    values: const <String>{
      'auto',
      'password',
      'public_key',
      'keyboard_interactive',
    },
  );
  _requiredEnum(
    connection['hostKeyPolicy'],
    path: r'$.config.connection.hostKeyPolicy',
    values: const <String>{'strict', 'accept_new', 'insecure'},
  );
  for (final field in const <String>[
    'password',
    'privateKeyPassphrase',
    'knownHostsFile',
    'proxyCommand',
    'proxyJump',
    'agentSocket',
    'x11TargetHost',
  ]) {
    _validateNullableString(
      connection[field],
      path: r'$.config.connection.' + field,
      maximum: switch (field) {
        'password' ||
        'privateKeyPassphrase' => TerminalSessionConfigV1._maxStringBytes,
        _ => TerminalSessionConfigV1._maxProgramLength,
      },
      allowEmpty: false,
    );
  }
  _validateRequiredPrivateKeyList(
    connection['privateKeys'],
    path: r'$.config.connection.privateKeys',
    maximumEntries: 128,
  );
  _validateRawJumpProfiles(connection['proxyJumpProfiles']);
  _requiredBoundedInt(
    connection['connectTimeoutSeconds'],
    path: r'$.config.connection.connectTimeoutSeconds',
    minimum: 1,
    maximum: 120,
  );
  _requiredBoundedInt(
    connection['keepaliveSeconds'],
    path: r'$.config.connection.keepaliveSeconds',
    minimum: 0,
    maximum: 86400,
  );
  _requiredBoundedInt(
    connection['keepaliveCountMax'],
    path: r'$.config.connection.keepaliveCountMax',
    minimum: 1,
    maximum: 100,
  );
  for (final field in const <String>['agentForwarding', 'x11Forwarding']) {
    _requiredBool(connection[field], path: r'$.config.connection.' + field);
  }
  _requiredBoundedInt(
    connection['x11TargetPort'],
    path: r'$.config.connection.x11TargetPort',
    minimum: 0,
    maximum: 65535,
  );
  _boundedRequiredString(
    connection['x11AuthProtocol'],
    path: r'$.config.connection.x11AuthProtocol',
    maximum: 128,
  );
  _requiredBoundedInt(
    connection['x11ScreenNumber'],
    path: r'$.config.connection.x11ScreenNumber',
    minimum: 0,
    maximum: 65535,
  );
  _validateNullableHexCookie(
    connection['x11AuthCookie'],
    path: r'$.config.connection.x11AuthCookie',
  );
  if (connection['x11Forwarding'] == true) {
    if (connection['x11AuthProtocol'] != 'MIT-MAGIC-COOKIE-1') {
      throw const TerminalSessionConfigContractException(
        code: 'invalid_ssh_connection',
        path: r'$.config.connection.x11AuthProtocol',
        message: 'X11 forwarding requires MIT-MAGIC-COOKIE-1',
      );
    }
    final cookie = connection['x11AuthCookie'];
    if (cookie is! String ||
        cookie.length != 32 ||
        !RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(cookie)) {
      throw TerminalSessionConfigContractException(
        code: cookie == null ? 'missing_field' : 'invalid_string',
        path: r'$.config.connection.x11AuthCookie',
        message:
            'X11 forwarding requires a 32-character hexadecimal authentication cookie',
      );
    }
  }
  _validateRawPortForwards(connection['portForwards']);
}

void _expectOnlyKeys(
  Map<String, Object?> value,
  Set<String> allowed,
  String path,
) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw TerminalSessionConfigContractException(
        code: 'unknown_field',
        path: '$path.$key',
        message: 'unknown field $key',
      );
    }
  }
}

void _expectRequiredKeys(
  Map<String, Object?> value,
  Set<String> required,
  String path,
) {
  for (final key in required) {
    if (!value.containsKey(key)) {
      throw TerminalSessionConfigContractException(
        code: 'missing_field',
        path: '$path.$key',
        message: 'missing field $key',
      );
    }
  }
}

void _validateRawJumpProfiles(Object? value) {
  const path = r'$.config.connection.proxyJumpProfiles';
  if (value == null) {
    return;
  }
  if (value is! List || value.length > 128) {
    throw const TerminalSessionConfigContractException(
      code: 'invalid_collection',
      path: path,
      message: 'proxyJumpProfiles must contain at most 128 entries',
    );
  }
  for (var index = 0; index < value.length; index += 1) {
    final jumpPath = '$path[$index]';
    final jump = _objectMap(value[index], jumpPath);
    _boundedRequiredString(
      jump['host'],
      path: '$jumpPath.host',
      maximum: TerminalSessionConfigV1._maxProgramLength,
    );
    _boundedRequiredString(
      jump['user'],
      path: '$jumpPath.user',
      maximum: TerminalSessionConfigV1._maxDisplayNameLength,
    );
    _requiredBoundedInt(
      jump['port'],
      path: '$jumpPath.port',
      minimum: 1,
      maximum: 65535,
    );
    _requiredEnum(
      jump['auth'],
      path: '$jumpPath.auth',
      values: const <String>{
        'auto',
        'password',
        'public_key',
        'keyboard_interactive',
      },
    );
    _validateRequiredPrivateKeyList(
      jump['privateKeys'],
      path: '$jumpPath.privateKeys',
      maximumEntries: 128,
    );
    _requiredEnum(
      jump['hostKeyPolicy'],
      path: '$jumpPath.hostKeyPolicy',
      values: const <String>{'strict', 'accept_new', 'insecure'},
    );
    for (final field in const <String>[
      'password',
      'privateKeyPassphrase',
      'knownHostsFile',
    ]) {
      _validateNullableString(
        jump[field],
        path: '$jumpPath.$field',
        maximum: field == 'knownHostsFile'
            ? TerminalSessionConfigV1._maxProgramLength
            : TerminalSessionConfigV1._maxStringBytes,
        allowEmpty: false,
      );
    }
    _requiredBoundedInt(
      jump['connectTimeoutSeconds'],
      path: '$jumpPath.connectTimeoutSeconds',
      minimum: 1,
      maximum: 120,
    );
    _requiredBoundedInt(
      jump['keepaliveSeconds'],
      path: '$jumpPath.keepaliveSeconds',
      minimum: 0,
      maximum: 86400,
    );
    _requiredBoundedInt(
      jump['keepaliveCountMax'],
      path: '$jumpPath.keepaliveCountMax',
      minimum: 1,
      maximum: 100,
    );
  }
}

void _validateRawPortForwards(Object? value) {
  const path = r'$.config.connection.portForwards';
  if (value is! List || value.length > 128) {
    throw const TerminalSessionConfigContractException(
      code: 'invalid_collection',
      path: path,
      message: 'portForwards must contain at most 128 entries',
    );
  }
  for (var index = 0; index < value.length; index += 1) {
    final forwardPath = '$path[$index]';
    final forward = _objectMap(value[index], forwardPath);
    final type = _requiredEnum(
      forward['type'],
      path: '$forwardPath.type',
      values: const <String>{'local', 'remote', 'dynamic'},
    );
    _boundedRequiredString(
      forward['bindHost'],
      path: '$forwardPath.bindHost',
      maximum: 4096,
    );
    _requiredBoundedInt(
      forward['bindPort'],
      path: '$forwardPath.bindPort',
      minimum: 1,
      maximum: 65535,
    );
    if (type == 'dynamic') {
      if (forward['targetHost'] != '' || forward['targetPort'] != 0) {
        throw TerminalSessionConfigContractException(
          code: 'invalid_ssh_connection',
          path: forwardPath,
          message: 'dynamic forwards require an empty target and port 0',
        );
      }
      continue;
    }
    _boundedRequiredString(
      forward['targetHost'],
      path: '$forwardPath.targetHost',
      maximum: 4096,
    );
    _requiredBoundedInt(
      forward['targetPort'],
      path: '$forwardPath.targetPort',
      minimum: 1,
      maximum: 65535,
    );
  }
}

String _requiredEnum(
  Object? value, {
  required String path,
  required Set<String> values,
}) {
  if (value is! String || !values.contains(value)) {
    throw TerminalSessionConfigContractException(
      code: value == null ? 'missing_field' : 'invalid_enum',
      path: path,
      message: 'expected one of ${values.join(', ')}',
    );
  }
  return value;
}

int _requiredBoundedInt(
  Object? value, {
  required String path,
  required int minimum,
  required int maximum,
}) {
  if (value is! int || value < minimum || value > maximum) {
    throw TerminalSessionConfigContractException(
      code: value == null ? 'missing_field' : 'invalid_integer',
      path: path,
      message: 'expected an integer from $minimum to $maximum',
    );
  }
  return value;
}

void _requiredBool(Object? value, {required String path}) {
  if (value is! bool) {
    throw TerminalSessionConfigContractException(
      code: value == null ? 'missing_field' : 'invalid_type',
      path: path,
      message: 'expected a boolean',
    );
  }
}

void _validateNullableString(
  Object? value, {
  required String path,
  required int maximum,
  required bool allowEmpty,
}) {
  if (value == null) {
    return;
  }
  if (value is! String ||
      utf8.encode(value).length > maximum ||
      value.runes.any(_isControlRune) ||
      (!allowEmpty && (value.isEmpty || value.trim() != value))) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_string',
      path: path,
      message: 'expected null or an exact bounded string',
    );
  }
}

void _validateNullableHexCookie(Object? value, {required String path}) {
  if (value != null &&
      (value is! String || !RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(value))) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_string',
      path: path,
      message: 'expected null or a 32-character hexadecimal cookie',
    );
  }
}

void _validateNullableHexColor(Object? value, {required String path}) {
  if (value != null &&
      (value is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value))) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_string',
      path: path,
      message: 'expected null or an exact #RRGGBB color',
    );
  }
}

void _validateRequiredStringList(
  Object? value, {
  required String path,
  required int maximumEntries,
  required int maximumStringBytes,
  required bool allowEmpty,
}) {
  if (value is! List || value.length > maximumEntries) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_collection',
      path: path,
      message: 'expected at most $maximumEntries string entries',
    );
  }
  for (final item in value) {
    if (item is! String ||
        utf8.encode(item).length > maximumStringBytes ||
        item.runes.any(allowEmpty ? (rune) => rune == 0 : _isControlRune) ||
        (!allowEmpty && (item.isEmpty || item.trim() != item))) {
      throw TerminalSessionConfigContractException(
        code: 'invalid_collection',
        path: path,
        message: 'contains an invalid string entry',
      );
    }
  }
}

void _validateRequiredPrivateKeyList(
  Object? value, {
  required String path,
  required int maximumEntries,
}) {
  if (value is! List || value.length > maximumEntries) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_collection',
      path: path,
      message: 'expected at most $maximumEntries private key entries',
    );
  }
  for (final item in value) {
    final inline = item is String && _looksLikeInlinePrivateKey(item);
    if (item is! String ||
        item.isEmpty ||
        item.trim() != item ||
        utf8.encode(item).length >
            (inline
                ? TerminalSessionConfigV1._maxStringBytes
                : TerminalSessionConfigV1._maxProgramLength) ||
        item.runes.any(
          (rune) =>
              rune == 0 ||
              (!inline && _isControlRune(rune)) ||
              (inline && rune < 32 && rune != 10 && rune != 13),
        )) {
      throw TerminalSessionConfigContractException(
        code: 'invalid_collection',
        path: path,
        message: 'contains an invalid private key entry',
      );
    }
  }
}

bool _looksLikeInlinePrivateKey(String value) {
  final trimmed = value.trimLeft();
  return trimmed.startsWith('-----BEGIN ') ||
      trimmed.startsWith('PuTTY-User-Key-File-');
}

void _validateRequiredStringMap(
  Object? value, {
  required String path,
  required int maximumEntries,
}) {
  if (value is! Map || value.length > maximumEntries) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_collection',
      path: path,
      message: 'expected at most $maximumEntries string entries',
    );
  }
  for (final entry in value.entries) {
    final key = entry.key;
    final entryValue = entry.value;
    if (key is! String ||
        entryValue is! String ||
        key.isEmpty ||
        key.trim() != key ||
        key.contains('=') ||
        key.contains('\u0000') ||
        entryValue.contains('\u0000') ||
        utf8.encode(key).length > TerminalSessionConfigV1._maxStringBytes ||
        utf8.encode(entryValue).length >
            TerminalSessionConfigV1._maxStringBytes) {
      throw TerminalSessionConfigContractException(
        code: 'invalid_collection',
        path: path,
        message: 'contains an invalid environment entry',
      );
    }
  }
}

double _requiredPositiveFiniteNumber(
  Object? value, {
  required String path,
  required double maximum,
}) {
  if (value is! num || !value.isFinite || value <= 0 || value > maximum) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_number',
      path: path,
      message: 'expected a finite number greater than 0 and at most $maximum',
    );
  }
  return value.toDouble();
}

Map<String, Object?> _objectMap(Object? value, String path) {
  if (value is! Map) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_type',
      path: path,
      message: 'expected a JSON object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw TerminalSessionConfigContractException(
        code: 'invalid_type',
        path: path,
        message: 'object keys must be strings',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _boundedRequiredString(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value is! String ||
      value.isEmpty ||
      value.trim() != value ||
      utf8.encode(value).length > maximum) {
    throw TerminalSessionConfigContractException(
      code: value == null ? 'missing_field' : 'invalid_string',
      path: path,
      message: 'expected a non-empty string of at most $maximum characters',
    );
  }
  if (value.runes.any(_isControlRune)) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_string',
      path: path,
      message: 'control characters are not allowed',
    );
  }
  return value;
}

String _boundedString(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value is! String || utf8.encode(value).length > maximum) {
    throw TerminalSessionConfigContractException(
      code: value == null ? 'missing_field' : 'invalid_string',
      path: path,
      message: 'expected a string of at most $maximum characters',
    );
  }
  if (value.runes.any(_isControlRune)) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_string',
      path: path,
      message: 'control characters are not allowed',
    );
  }
  return value;
}

bool _isControlRune(int rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f);

void _validateStringList(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value == null) {
    return;
  }
  if (value is! List ||
      value.length > maximum ||
      value.any((item) => item is! String)) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_collection',
      path: path,
      message: 'expected at most $maximum string entries',
    );
  }
}

void _validateStringMap(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value == null) {
    return;
  }
  if (value is! Map ||
      value.length > maximum ||
      value.entries.any(
        (entry) => entry.key is! String || entry.value is! String,
      )) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_collection',
      path: path,
      message: 'expected at most $maximum string-to-string entries',
    );
  }
}
