import 'dart:convert';

import 'terminal_config.dart';

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
/// runtime. Unknown fields are ignored so additive minor evolution is safe.
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
      'config': config.toJson(),
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
    final schemaVersion = json['schema_version'];
    if (schemaVersion != terminalSessionConfigSchemaVersion) {
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
    var zmodemEnabled = false;
    final rawClientCapabilities = json['client_capabilities'];
    if (rawClientCapabilities != null) {
      final clientCapabilities = _objectMap(
        rawClientCapabilities,
        r'$.client_capabilities',
      );
      final rawZmodem = clientCapabilities['zmodem'];
      if (rawZmodem != null && rawZmodem is! bool) {
        throw const TerminalSessionConfigContractException(
          code: 'invalid_type',
          path: r'$.client_capabilities.zmodem',
          message: 'zmodem must be a boolean',
        );
      }
      zmodemEnabled = rawZmodem == true;
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
    _validateRawConnection(configJson['connection']);
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
    return TerminalSessionConfigV1(
      sessionId: sessionId,
      displayName: displayName,
      config: TerminalSessionConfig.fromJson(configJson),
      zmodemEnabled: zmodemEnabled,
    );
  }
}

void _validateRawConnection(Object? value) {
  if (value == null) {
    // SessionConfig v1 originally omitted connection for local sessions.
    // Compatibility is fail-closed: the model resolves this to local, and the
    // local launch validator above still requires a non-empty program.
    return;
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
    maximum: 4096,
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
  _validateBoundedOptionalString(
    connection,
    'password',
    maximum: TerminalSessionConfigV1.maxEncodedBytes,
  );
  _validateBoundedOptionalString(
    connection,
    'privateKeyPassphrase',
    maximum: TerminalSessionConfigV1.maxEncodedBytes,
  );
  _validateBoundedOptionalString(
    connection,
    'x11AuthCookie',
    maximum: TerminalSessionConfigV1.maxEncodedBytes,
  );
  for (final field in const <String>[
    'knownHostsFile',
    'proxyCommand',
    'proxyJump',
    'agentSocket',
    'x11TargetHost',
  ]) {
    _validateBoundedOptionalString(connection, field, maximum: 4096);
  }
  _validateStringList(
    connection['privateKeys'],
    path: r'$.config.connection.privateKeys',
    maximum: 128,
  );
  if (connection['privateKeys'] == null) {
    throw const TerminalSessionConfigContractException(
      code: 'missing_field',
      path: r'$.config.connection.privateKeys',
      message: 'privateKeys is required',
    );
  }
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
    maximum: 256,
  );
  _requiredBoundedInt(
    connection['x11ScreenNumber'],
    path: r'$.config.connection.x11ScreenNumber',
    minimum: 0,
    maximum: 65535,
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
    _boundedString(jump['host'], path: '$jumpPath.host', maximum: 4096);
    _boundedString(jump['user'], path: '$jumpPath.user', maximum: 4096);
    _requiredBoundedInt(
      jump['port'],
      path: '$jumpPath.port',
      minimum: 0,
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
    _validateStringList(
      jump['privateKeys'],
      path: '$jumpPath.privateKeys',
      maximum: 128,
    );
    if (jump['privateKeys'] == null) {
      throw TerminalSessionConfigContractException(
        code: 'missing_field',
        path: '$jumpPath.privateKeys',
        message: 'privateKeys is required',
      );
    }
    final privateKeys = jump['privateKeys'];
    if (privateKeys is List &&
        privateKeys.any(
          (item) =>
              item is String &&
              (item.isEmpty ||
                  item.length > 4096 ||
                  item.runes.any((rune) => rune < 0x20 || rune == 0x7f)),
        )) {
      throw TerminalSessionConfigContractException(
        code: 'invalid_collection',
        path: '$jumpPath.privateKeys',
        message: 'private key paths must be non-empty bounded strings',
      );
    }
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
      _validateBoundedOptionalStringAtPath(
        jump,
        field,
        path: '$jumpPath.$field',
        maximum: field == 'knownHostsFile'
            ? 4096
            : TerminalSessionConfigV1.maxEncodedBytes,
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

void _validateBoundedOptionalString(
  Map<String, Object?> object,
  String field, {
  required int maximum,
}) {
  if (!object.containsKey(field)) {
    return;
  }
  final value = object[field];
  if (value is! String || value.length > maximum || value.contains('\u0000')) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_type',
      path: r'$.config.connection.' + field,
      message: '$field must be a bounded string',
    );
  }
}

void _validateBoundedOptionalStringAtPath(
  Map<String, Object?> object,
  String field, {
  required String path,
  required int maximum,
}) {
  if (!object.containsKey(field)) {
    return;
  }
  final value = object[field];
  if (value is! String || value.length > maximum || value.contains('\u0000')) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_type',
      path: path,
      message: '$field must be a bounded string',
    );
  }
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
  if (value is! String || value.trim().isEmpty || value.length > maximum) {
    throw TerminalSessionConfigContractException(
      code: value == null ? 'missing_field' : 'invalid_string',
      path: path,
      message: 'expected a non-empty string of at most $maximum characters',
    );
  }
  if (value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
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
  if (value is! String || value.length > maximum) {
    throw TerminalSessionConfigContractException(
      code: value == null ? 'missing_field' : 'invalid_string',
      path: path,
      message: 'expected a string of at most $maximum characters',
    );
  }
  if (value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw TerminalSessionConfigContractException(
      code: 'invalid_string',
      path: path,
      message: 'control characters are not allowed',
    );
  }
  return value;
}

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
