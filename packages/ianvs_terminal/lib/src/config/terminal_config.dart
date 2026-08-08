import 'terminal_defaults.dart';

const int maxTerminalLaunchArgs = 128;
const int maxTerminalEnvironmentEntries = 256;
const int maxTerminalFontFallbackFamilies = 32;
const int _directConfigEntryScanMultiplier = 4;

enum TerminalEmulation { xterm256, vt220 }

enum TerminalCursorShape { block, underline, beam }

enum TerminalConnectionType { local, ssh }

enum TerminalSshAuthMethod { auto, password, publicKey, keyboardInteractive }

enum TerminalSshHostKeyPolicy { strict, acceptNew, insecure }

enum TerminalSshPortForwardType { local, remote, dynamic }

final class TerminalSshPortForwardConfig {
  const TerminalSshPortForwardConfig({
    required this.type,
    required this.bindHost,
    required this.bindPort,
    this.targetHost = '',
    this.targetPort = 0,
  });

  final TerminalSshPortForwardType type;
  final String bindHost;
  final int bindPort;
  final String targetHost;
  final int targetPort;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.name,
    'bindHost': bindHost,
    'bindPort': bindPort,
    'targetHost': targetHost,
    'targetPort': targetPort,
  };

  factory TerminalSshPortForwardConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalSshPortForwardConfig(
      type: switch (_normalizedConfigToken(map?['type'])) {
        'remote' => TerminalSshPortForwardType.remote,
        'dynamic' => TerminalSshPortForwardType.dynamic,
        _ => TerminalSshPortForwardType.local,
      },
      bindHost: _trimmedStringOrNull(map?['bindHost']) ?? '127.0.0.1',
      bindPort: _nonNegativeIntOr(map?['bindPort'], 0, maximum: 65535),
      targetHost: _trimmedStringOrNull(map?['targetHost']) ?? '',
      targetPort: _nonNegativeIntOr(map?['targetPort'], 0, maximum: 65535),
    );
  }
}

/// Independent authentication and host-verification settings for one
/// ProxyJump hop. Passwords and key passphrases are transient runtime values.
final class TerminalSshJumpConfig {
  const TerminalSshJumpConfig({
    this.host = '',
    this.user = '',
    this.port = 0,
    this.auth = TerminalSshAuthMethod.auto,
    this.password,
    this.privateKeys = const <String>[],
    this.privateKeyPassphrase,
    this.hostKeyPolicy = TerminalSshHostKeyPolicy.strict,
    this.knownHostsFile,
    this.connectTimeoutSeconds = 10,
    this.keepaliveSeconds = 0,
    this.keepaliveCountMax = 3,
  });

  final String host;
  final String user;
  final int port;
  final TerminalSshAuthMethod auth;
  final String? password;
  final List<String> privateKeys;
  final String? privateKeyPassphrase;
  final TerminalSshHostKeyPolicy hostKeyPolicy;
  final String? knownHostsFile;
  final int connectTimeoutSeconds;
  final int keepaliveSeconds;
  final int keepaliveCountMax;

  TerminalSshJumpConfig copyWith({
    String? host,
    String? user,
    int? port,
    TerminalSshAuthMethod? auth,
    Object? password = _terminalConfigNoChange,
    List<String>? privateKeys,
    Object? privateKeyPassphrase = _terminalConfigNoChange,
    TerminalSshHostKeyPolicy? hostKeyPolicy,
    Object? knownHostsFile = _terminalConfigNoChange,
    int? connectTimeoutSeconds,
    int? keepaliveSeconds,
    int? keepaliveCountMax,
  }) {
    return TerminalSshJumpConfig(
      host: host ?? this.host,
      user: user ?? this.user,
      port: port ?? this.port,
      auth: auth ?? this.auth,
      password: identical(password, _terminalConfigNoChange)
          ? this.password
          : password as String?,
      privateKeys: privateKeys ?? this.privateKeys,
      privateKeyPassphrase:
          identical(privateKeyPassphrase, _terminalConfigNoChange)
          ? this.privateKeyPassphrase
          : privateKeyPassphrase as String?,
      hostKeyPolicy: hostKeyPolicy ?? this.hostKeyPolicy,
      knownHostsFile: identical(knownHostsFile, _terminalConfigNoChange)
          ? this.knownHostsFile
          : knownHostsFile as String?,
      connectTimeoutSeconds:
          connectTimeoutSeconds ?? this.connectTimeoutSeconds,
      keepaliveSeconds: keepaliveSeconds ?? this.keepaliveSeconds,
      keepaliveCountMax: keepaliveCountMax ?? this.keepaliveCountMax,
    );
  }

  TerminalSshJumpConfig withoutSensitiveFields() {
    return copyWith(password: null, privateKeyPassphrase: null);
  }

  Map<String, Object?> toJson({bool includeSensitiveFields = true}) {
    return <String, Object?>{
      'host': host,
      'user': user,
      'port': port,
      'auth': _sshAuthMethodToJson(auth),
      if (includeSensitiveFields && password != null) 'password': password,
      'privateKeys': privateKeys,
      if (includeSensitiveFields && privateKeyPassphrase != null)
        'privateKeyPassphrase': privateKeyPassphrase,
      'hostKeyPolicy': _sshHostKeyPolicyToJson(hostKeyPolicy),
      if (knownHostsFile != null) 'knownHostsFile': knownHostsFile,
      'connectTimeoutSeconds': connectTimeoutSeconds,
      'keepaliveSeconds': keepaliveSeconds,
      'keepaliveCountMax': keepaliveCountMax,
    };
  }

  factory TerminalSshJumpConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalSshJumpConfig(
      host: _trimmedStringOrNull(map?['host']) ?? '',
      user: _trimmedStringOrNull(map?['user']) ?? '',
      port: _nonNegativeIntOr(map?['port'], 0, maximum: 65535),
      auth: _sshAuthMethodFromJson(map?['auth']),
      password: _stringOrNull(map?['password']),
      privateKeys: _stringList(map?['privateKeys'], maxEntries: 128),
      privateKeyPassphrase: _stringOrNull(map?['privateKeyPassphrase']),
      hostKeyPolicy: _sshHostKeyPolicyFromJson(map?['hostKeyPolicy']),
      knownHostsFile: _trimmedStringOrNull(map?['knownHostsFile']),
      connectTimeoutSeconds: _positiveIntOr(
        map?['connectTimeoutSeconds'],
        10,
        maximum: 120,
      ),
      keepaliveSeconds: _nonNegativeIntOr(
        map?['keepaliveSeconds'],
        0,
        maximum: 86400,
      ),
      keepaliveCountMax: _positiveIntOr(
        map?['keepaliveCountMax'],
        3,
        maximum: 100,
      ),
    );
  }
}

String _sshAuthMethodToJson(TerminalSshAuthMethod auth) => switch (auth) {
  TerminalSshAuthMethod.auto => 'auto',
  TerminalSshAuthMethod.password => 'password',
  TerminalSshAuthMethod.publicKey => 'public_key',
  TerminalSshAuthMethod.keyboardInteractive => 'keyboard_interactive',
};

TerminalSshAuthMethod _sshAuthMethodFromJson(Object? value) {
  return switch (_normalizedConfigToken(value)) {
    'password' => TerminalSshAuthMethod.password,
    'public_key' || 'publickey' => TerminalSshAuthMethod.publicKey,
    'keyboard_interactive' ||
    'keyboard-interactive' => TerminalSshAuthMethod.keyboardInteractive,
    _ => TerminalSshAuthMethod.auto,
  };
}

String _sshHostKeyPolicyToJson(TerminalSshHostKeyPolicy policy) {
  return switch (policy) {
    TerminalSshHostKeyPolicy.strict => 'strict',
    TerminalSshHostKeyPolicy.acceptNew => 'accept_new',
    TerminalSshHostKeyPolicy.insecure => 'insecure',
  };
}

TerminalSshHostKeyPolicy _sshHostKeyPolicyFromJson(Object? value) {
  return switch (_normalizedConfigToken(value)) {
    'accept_new' || 'accept-new' => TerminalSshHostKeyPolicy.acceptNew,
    'insecure' => TerminalSshHostKeyPolicy.insecure,
    _ => TerminalSshHostKeyPolicy.strict,
  };
}

enum TerminalOptionDragMode {
  normalSelection,
  blockSelection;

  String get jsonValue => switch (this) {
    TerminalOptionDragMode.normalSelection => 'normal_selection',
    TerminalOptionDragMode.blockSelection => 'block_selection',
  };

  static TerminalOptionDragMode fromJsonValue(Object? value) {
    return switch (_normalizedConfigToken(value)) {
      'normal_selection' => TerminalOptionDragMode.normalSelection,
      _ => TerminalOptionDragMode.blockSelection,
    };
  }
}

class TerminalLaunchConfig {
  const TerminalLaunchConfig({
    required this.program,
    this.args = const <String>[],
    this.env = const <String, String>{},
    this.cwd,
  });

  final String program;
  final List<String> args;
  final Map<String, String> env;
  final String? cwd;

  TerminalLaunchConfig copyWith({
    String? program,
    List<String>? args,
    Map<String, String>? env,
    Object? cwd = _terminalConfigNoChange,
  }) {
    return TerminalLaunchConfig(
      program: program ?? this.program,
      args: args ?? this.args,
      env: env ?? this.env,
      cwd: identical(cwd, _terminalConfigNoChange) ? this.cwd : cwd as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'program': program,
      'args': args,
      'env': env,
      'cwd': cwd,
    };
  }

  factory TerminalLaunchConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalLaunchConfig(
      program: _trimmedStringOrNull(map?['program']) ?? '',
      args: _stringList(map?['args'], maxEntries: maxTerminalLaunchArgs),
      env: _stringMap(map?['env'], maxEntries: maxTerminalEnvironmentEntries),
      cwd: _trimmedStringOrNull(map?['cwd']),
    );
  }
}

/// Connection settings shared by saved profiles and the native SessionConfig
/// wire. Destination and [proxyJumpProfiles] passwords/passphrases, plus
/// [x11AuthCookie], are transient secrets. Callers persisting a profile must
/// encode with `includeSensitiveFields: false` and store any supported
/// encrypted representation separately.
class TerminalConnectionConfig {
  const TerminalConnectionConfig.local()
    : type = TerminalConnectionType.local,
      host = '',
      user = '',
      port = 22,
      auth = TerminalSshAuthMethod.auto,
      password = null,
      privateKeys = const <String>[],
      privateKeyPassphrase = null,
      hostKeyPolicy = TerminalSshHostKeyPolicy.strict,
      knownHostsFile = null,
      connectTimeoutSeconds = 10,
      keepaliveSeconds = 0,
      keepaliveCountMax = 3,
      proxyCommand = null,
      proxyJump = null,
      proxyJumpProfiles = const <TerminalSshJumpConfig>[],
      portForwards = const <TerminalSshPortForwardConfig>[],
      agentForwarding = false,
      agentSocket = null,
      x11Forwarding = false,
      x11TargetHost = null,
      x11TargetPort = 0,
      x11AuthProtocol = 'MIT-MAGIC-COOKIE-1',
      x11AuthCookie = null,
      x11ScreenNumber = 0;

  const TerminalConnectionConfig.ssh({
    required this.host,
    required this.user,
    this.port = 22,
    this.auth = TerminalSshAuthMethod.auto,
    this.password,
    this.privateKeys = const <String>[],
    this.privateKeyPassphrase,
    this.hostKeyPolicy = TerminalSshHostKeyPolicy.strict,
    this.knownHostsFile,
    this.connectTimeoutSeconds = 10,
    this.keepaliveSeconds = 0,
    this.keepaliveCountMax = 3,
    this.proxyCommand,
    this.proxyJump,
    this.proxyJumpProfiles = const <TerminalSshJumpConfig>[],
    this.portForwards = const <TerminalSshPortForwardConfig>[],
    this.agentForwarding = false,
    this.agentSocket,
    this.x11Forwarding = false,
    this.x11TargetHost,
    this.x11TargetPort = 0,
    this.x11AuthProtocol = 'MIT-MAGIC-COOKIE-1',
    this.x11AuthCookie,
    this.x11ScreenNumber = 0,
  }) : type = TerminalConnectionType.ssh;

  final TerminalConnectionType type;
  final String host;
  final String user;
  final int port;
  final TerminalSshAuthMethod auth;
  final String? password;
  final List<String> privateKeys;
  final String? privateKeyPassphrase;
  final TerminalSshHostKeyPolicy hostKeyPolicy;
  final String? knownHostsFile;
  final int connectTimeoutSeconds;
  final int keepaliveSeconds;
  final int keepaliveCountMax;
  final String? proxyCommand;
  final String? proxyJump;
  final List<TerminalSshJumpConfig> proxyJumpProfiles;
  final List<TerminalSshPortForwardConfig> portForwards;
  final bool agentForwarding;
  final String? agentSocket;
  final bool x11Forwarding;
  final String? x11TargetHost;
  final int x11TargetPort;
  final String x11AuthProtocol;
  final String? x11AuthCookie;
  final int x11ScreenNumber;

  bool get isSsh => type == TerminalConnectionType.ssh;

  TerminalConnectionConfig copyWith({
    String? host,
    String? user,
    int? port,
    TerminalSshAuthMethod? auth,
    Object? password = _terminalConfigNoChange,
    List<String>? privateKeys,
    Object? privateKeyPassphrase = _terminalConfigNoChange,
    TerminalSshHostKeyPolicy? hostKeyPolicy,
    Object? knownHostsFile = _terminalConfigNoChange,
    int? connectTimeoutSeconds,
    int? keepaliveSeconds,
    int? keepaliveCountMax,
    Object? proxyCommand = _terminalConfigNoChange,
    Object? proxyJump = _terminalConfigNoChange,
    List<TerminalSshJumpConfig>? proxyJumpProfiles,
    List<TerminalSshPortForwardConfig>? portForwards,
    bool? agentForwarding,
    Object? agentSocket = _terminalConfigNoChange,
    bool? x11Forwarding,
    Object? x11TargetHost = _terminalConfigNoChange,
    int? x11TargetPort,
    String? x11AuthProtocol,
    Object? x11AuthCookie = _terminalConfigNoChange,
    int? x11ScreenNumber,
  }) {
    if (!isSsh) {
      return const TerminalConnectionConfig.local();
    }
    return TerminalConnectionConfig.ssh(
      host: host ?? this.host,
      user: user ?? this.user,
      port: port ?? this.port,
      auth: auth ?? this.auth,
      password: identical(password, _terminalConfigNoChange)
          ? this.password
          : password as String?,
      privateKeys: privateKeys ?? this.privateKeys,
      privateKeyPassphrase:
          identical(privateKeyPassphrase, _terminalConfigNoChange)
          ? this.privateKeyPassphrase
          : privateKeyPassphrase as String?,
      hostKeyPolicy: hostKeyPolicy ?? this.hostKeyPolicy,
      knownHostsFile: identical(knownHostsFile, _terminalConfigNoChange)
          ? this.knownHostsFile
          : knownHostsFile as String?,
      connectTimeoutSeconds:
          connectTimeoutSeconds ?? this.connectTimeoutSeconds,
      keepaliveSeconds: keepaliveSeconds ?? this.keepaliveSeconds,
      keepaliveCountMax: keepaliveCountMax ?? this.keepaliveCountMax,
      proxyCommand: identical(proxyCommand, _terminalConfigNoChange)
          ? this.proxyCommand
          : proxyCommand as String?,
      proxyJump: identical(proxyJump, _terminalConfigNoChange)
          ? this.proxyJump
          : proxyJump as String?,
      proxyJumpProfiles: proxyJumpProfiles ?? this.proxyJumpProfiles,
      portForwards: portForwards ?? this.portForwards,
      agentForwarding: agentForwarding ?? this.agentForwarding,
      agentSocket: identical(agentSocket, _terminalConfigNoChange)
          ? this.agentSocket
          : agentSocket as String?,
      x11Forwarding: x11Forwarding ?? this.x11Forwarding,
      x11TargetHost: identical(x11TargetHost, _terminalConfigNoChange)
          ? this.x11TargetHost
          : x11TargetHost as String?,
      x11TargetPort: x11TargetPort ?? this.x11TargetPort,
      x11AuthProtocol: x11AuthProtocol ?? this.x11AuthProtocol,
      x11AuthCookie: identical(x11AuthCookie, _terminalConfigNoChange)
          ? this.x11AuthCookie
          : x11AuthCookie as String?,
      x11ScreenNumber: x11ScreenNumber ?? this.x11ScreenNumber,
    );
  }

  TerminalConnectionConfig withoutSensitiveFields() {
    if (!isSsh) {
      return this;
    }
    return copyWith(
      password: null,
      privateKeyPassphrase: null,
      proxyJumpProfiles: proxyJumpProfiles
          .map((jump) => jump.withoutSensitiveFields())
          .toList(growable: false),
      x11AuthCookie: null,
    );
  }

  Map<String, Object?> toJson({bool includeSensitiveFields = true}) {
    if (!isSsh) {
      return const <String, Object?>{'type': 'local'};
    }
    return <String, Object?>{
      'type': 'ssh',
      'host': host,
      'user': user,
      'port': port,
      'auth': _sshAuthMethodToJson(auth),
      if (includeSensitiveFields && password != null) 'password': password,
      'privateKeys': privateKeys,
      if (includeSensitiveFields && privateKeyPassphrase != null)
        'privateKeyPassphrase': privateKeyPassphrase,
      'hostKeyPolicy': _sshHostKeyPolicyToJson(hostKeyPolicy),
      if (knownHostsFile != null) 'knownHostsFile': knownHostsFile,
      'connectTimeoutSeconds': connectTimeoutSeconds,
      'keepaliveSeconds': keepaliveSeconds,
      'keepaliveCountMax': keepaliveCountMax,
      if (proxyCommand != null) 'proxyCommand': proxyCommand,
      if (proxyJump != null) 'proxyJump': proxyJump,
      'proxyJumpProfiles': proxyJumpProfiles
          .map(
            (jump) =>
                jump.toJson(includeSensitiveFields: includeSensitiveFields),
          )
          .toList(growable: false),
      'portForwards': portForwards
          .map((forward) => forward.toJson())
          .toList(growable: false),
      'agentForwarding': agentForwarding,
      if (agentSocket != null) 'agentSocket': agentSocket,
      'x11Forwarding': x11Forwarding,
      if (x11TargetHost != null) 'x11TargetHost': x11TargetHost,
      'x11TargetPort': x11TargetPort,
      'x11AuthProtocol': x11AuthProtocol,
      if (includeSensitiveFields && x11AuthCookie != null)
        'x11AuthCookie': x11AuthCookie,
      'x11ScreenNumber': x11ScreenNumber,
    };
  }

  factory TerminalConnectionConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    if (_normalizedConfigToken(map?['type']) != 'ssh') {
      return const TerminalConnectionConfig.local();
    }
    return TerminalConnectionConfig.ssh(
      host: _trimmedStringOrNull(map?['host']) ?? '',
      user: _trimmedStringOrNull(map?['user']) ?? '',
      port: _positiveIntOr(map?['port'], 22, maximum: 65535),
      auth: _sshAuthMethodFromJson(map?['auth']),
      password: _stringOrNull(map?['password']),
      privateKeys: _stringList(map?['privateKeys'], maxEntries: 128),
      privateKeyPassphrase: _stringOrNull(map?['privateKeyPassphrase']),
      hostKeyPolicy: _sshHostKeyPolicyFromJson(map?['hostKeyPolicy']),
      knownHostsFile: _trimmedStringOrNull(map?['knownHostsFile']),
      connectTimeoutSeconds: _positiveIntOr(
        map?['connectTimeoutSeconds'],
        10,
        maximum: 120,
      ),
      keepaliveSeconds: _nonNegativeIntOr(
        map?['keepaliveSeconds'],
        0,
        maximum: 86400,
      ),
      keepaliveCountMax: _positiveIntOr(
        map?['keepaliveCountMax'],
        3,
        maximum: 100,
      ),
      proxyCommand: _trimmedStringOrNull(map?['proxyCommand']),
      proxyJump: _trimmedStringOrNull(map?['proxyJump']),
      proxyJumpProfiles: _objectList(
        map?['proxyJumpProfiles'],
        maxEntries: 128,
      ).map(TerminalSshJumpConfig.fromJson).toList(growable: false),
      portForwards: _objectList(
        map?['portForwards'],
        maxEntries: 128,
      ).map(TerminalSshPortForwardConfig.fromJson).toList(growable: false),
      agentForwarding: map?['agentForwarding'] == true,
      agentSocket: _trimmedStringOrNull(map?['agentSocket']),
      x11Forwarding: map?['x11Forwarding'] == true,
      x11TargetHost: _trimmedStringOrNull(map?['x11TargetHost']),
      x11TargetPort: _nonNegativeIntOr(
        map?['x11TargetPort'],
        0,
        maximum: 65535,
      ),
      x11AuthProtocol:
          _trimmedStringOrNull(map?['x11AuthProtocol']) ?? 'MIT-MAGIC-COOKIE-1',
      x11AuthCookie: _stringOrNull(map?['x11AuthCookie']),
      x11ScreenNumber: _nonNegativeIntOr(
        map?['x11ScreenNumber'],
        0,
        maximum: 65535,
      ),
    );
  }
}

class TerminalShellIntegrationConfig {
  const TerminalShellIntegrationConfig({this.enabled = true});

  final bool enabled;

  TerminalShellIntegrationConfig copyWith({bool? enabled}) {
    return TerminalShellIntegrationConfig(enabled: enabled ?? this.enabled);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'enabled': enabled};
  }

  factory TerminalShellIntegrationConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalShellIntegrationConfig(
      enabled: _boolOr(map?['enabled'], true),
    );
  }
}

class TerminalGraphicsConfig {
  const TerminalGraphicsConfig({
    this.enabled = true,
    this.advertise = 'kitty',
    this.maxImageBytes = defaultTerminalGraphicMaxImageBytes,
    this.maxTotalBytes = defaultTerminalGraphicMaxTotalBytes,
  });

  final bool enabled;
  final String advertise;
  final int maxImageBytes;
  final int maxTotalBytes;

  TerminalGraphicsConfig copyWith({
    bool? enabled,
    String? advertise,
    int? maxImageBytes,
    int? maxTotalBytes,
  }) {
    return TerminalGraphicsConfig(
      enabled: enabled ?? this.enabled,
      advertise: advertise ?? this.advertise,
      maxImageBytes: maxImageBytes ?? this.maxImageBytes,
      maxTotalBytes: maxTotalBytes ?? this.maxTotalBytes,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'advertise': advertise,
      'maxImageBytes': maxImageBytes,
      'maxTotalBytes': maxTotalBytes,
    };
  }

  factory TerminalGraphicsConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalGraphicsConfig(
      enabled: _boolOr(map?['enabled'], true),
      advertise: _graphicsAdvertiseOr(map?['advertise'], 'kitty'),
      maxImageBytes: _positiveIntOr(
        map?['maxImageBytes'],
        defaultTerminalGraphicMaxImageBytes,
      ),
      maxTotalBytes: _positiveIntOr(
        map?['maxTotalBytes'],
        defaultTerminalGraphicMaxTotalBytes,
      ),
    );
  }
}

class TerminalFontConfig {
  const TerminalFontConfig({
    this.family = terminalPrimaryFontFamily,
    this.fallback = terminalFontFamilyFallback,
    double size = terminalFontSize,
    double lineHeight = terminalLineHeight,
  }) : size = size > 0 && size < double.infinity ? size : terminalFontSize,
       lineHeight = lineHeight > 0 && lineHeight < double.infinity
           ? lineHeight
           : terminalLineHeight;

  final String family;
  final List<String> fallback;
  final double size;
  final double lineHeight;

  TerminalFontConfig copyWith({
    String? family,
    List<String>? fallback,
    double? size,
    double? lineHeight,
  }) {
    return TerminalFontConfig(
      family: family ?? this.family,
      fallback: fallback ?? this.fallback,
      size: size ?? this.size,
      lineHeight: lineHeight ?? this.lineHeight,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'family': family,
      'fallback': fallback,
      'size': size,
      'lineHeight': lineHeight,
    };
  }

  factory TerminalFontConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalFontConfig(
      family: _trimmedStringOrNull(map?['family']) ?? terminalPrimaryFontFamily,
      fallback: _trimmedStringList(
        map?['fallback'],
        fallback: terminalFontFamilyFallback,
        maxEntries: maxTerminalFontFallbackFamilies,
      ),
      size: _positiveFiniteDoubleOr(map?['size'], terminalFontSize),
      lineHeight: _positiveFiniteDoubleOr(
        map?['lineHeight'],
        terminalLineHeight,
      ),
    );
  }
}

class TerminalSpecialColors {
  const TerminalSpecialColors({
    this.foreground,
    this.background,
    this.cursor,
    this.selection,
    this.tab,
  });

  final String? foreground;
  final String? background;
  final String? cursor;
  final String? selection;
  final String? tab;

  TerminalSpecialColors copyWith({
    Object? foreground = _terminalConfigNoChange,
    Object? background = _terminalConfigNoChange,
    Object? cursor = _terminalConfigNoChange,
    Object? selection = _terminalConfigNoChange,
    Object? tab = _terminalConfigNoChange,
  }) {
    return TerminalSpecialColors(
      foreground: identical(foreground, _terminalConfigNoChange)
          ? this.foreground
          : foreground as String?,
      background: identical(background, _terminalConfigNoChange)
          ? this.background
          : background as String?,
      cursor: identical(cursor, _terminalConfigNoChange)
          ? this.cursor
          : cursor as String?,
      selection: identical(selection, _terminalConfigNoChange)
          ? this.selection
          : selection as String?,
      tab: identical(tab, _terminalConfigNoChange) ? this.tab : tab as String?,
    );
  }

  TerminalSpecialColors resolveWith(TerminalSpecialColors defaults) {
    return TerminalSpecialColors(
      foreground: foreground ?? defaults.foreground,
      background: background ?? defaults.background,
      cursor: cursor ?? defaults.cursor,
      selection: selection ?? defaults.selection,
      tab: tab ?? defaults.tab,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'foreground': foreground,
      'background': background,
      'cursor': cursor,
      'selection': selection,
      'tab': tab,
    };
  }

  factory TerminalSpecialColors.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalSpecialColors(
      foreground: _hexColorOrNull(map?['foreground']),
      background: _hexColorOrNull(map?['background']),
      cursor: _hexColorOrNull(map?['cursor']),
      selection: _hexColorOrNull(map?['selection']),
      tab: _hexColorOrNull(map?['tab']),
    );
  }
}

class TerminalAnsiColors {
  const TerminalAnsiColors({
    this.black,
    this.red,
    this.green,
    this.yellow,
    this.blue,
    this.magenta,
    this.cyan,
    this.white,
  });

  final String? black;
  final String? red;
  final String? green;
  final String? yellow;
  final String? blue;
  final String? magenta;
  final String? cyan;
  final String? white;

  TerminalAnsiColors copyWith({
    Object? black = _terminalConfigNoChange,
    Object? red = _terminalConfigNoChange,
    Object? green = _terminalConfigNoChange,
    Object? yellow = _terminalConfigNoChange,
    Object? blue = _terminalConfigNoChange,
    Object? magenta = _terminalConfigNoChange,
    Object? cyan = _terminalConfigNoChange,
    Object? white = _terminalConfigNoChange,
  }) {
    return TerminalAnsiColors(
      black: identical(black, _terminalConfigNoChange)
          ? this.black
          : black as String?,
      red: identical(red, _terminalConfigNoChange) ? this.red : red as String?,
      green: identical(green, _terminalConfigNoChange)
          ? this.green
          : green as String?,
      yellow: identical(yellow, _terminalConfigNoChange)
          ? this.yellow
          : yellow as String?,
      blue: identical(blue, _terminalConfigNoChange)
          ? this.blue
          : blue as String?,
      magenta: identical(magenta, _terminalConfigNoChange)
          ? this.magenta
          : magenta as String?,
      cyan: identical(cyan, _terminalConfigNoChange)
          ? this.cyan
          : cyan as String?,
      white: identical(white, _terminalConfigNoChange)
          ? this.white
          : white as String?,
    );
  }

  TerminalAnsiColors resolveWith(TerminalAnsiColors defaults) {
    return TerminalAnsiColors(
      black: black ?? defaults.black,
      red: red ?? defaults.red,
      green: green ?? defaults.green,
      yellow: yellow ?? defaults.yellow,
      blue: blue ?? defaults.blue,
      magenta: magenta ?? defaults.magenta,
      cyan: cyan ?? defaults.cyan,
      white: white ?? defaults.white,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'black': black,
      'red': red,
      'green': green,
      'yellow': yellow,
      'blue': blue,
      'magenta': magenta,
      'cyan': cyan,
      'white': white,
    };
  }

  factory TerminalAnsiColors.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalAnsiColors(
      black: _hexColorOrNull(map?['black']),
      red: _hexColorOrNull(map?['red']),
      green: _hexColorOrNull(map?['green']),
      yellow: _hexColorOrNull(map?['yellow']),
      blue: _hexColorOrNull(map?['blue']),
      magenta: _hexColorOrNull(map?['magenta']),
      cyan: _hexColorOrNull(map?['cyan']),
      white: _hexColorOrNull(map?['white']),
    );
  }
}

const TerminalSpecialColors defaultTerminalSpecialColors =
    TerminalSpecialColors(
      foreground: '#C0C0C0',
      background: '#000000',
      cursor: '#C0C0C0',
      selection: '#B5D5FF',
    );

const TerminalAnsiColors defaultTerminalAnsiColors = TerminalAnsiColors(
  black: '#14191E',
  red: '#B43C2A',
  green: '#00815B',
  yellow: '#CFA518',
  blue: '#3065B8',
  magenta: '#8818A3',
  cyan: '#009399',
  white: '#E5E5E5',
);

const TerminalAnsiColors defaultTerminalBrightAnsiColors = TerminalAnsiColors(
  black: '#687378',
  red: '#FF6148',
  green: '#00C984',
  yellow: '#FFC531',
  blue: '#4F9CFE',
  magenta: '#C54FFF',
  cyan: '#00CCCC',
  white: '#FFFFFF',
);

class TerminalColorPalette {
  const TerminalColorPalette({
    this.special = const TerminalSpecialColors(),
    this.normal = const TerminalAnsiColors(),
    this.bright = const TerminalAnsiColors(),
  });

  final TerminalSpecialColors special;
  final TerminalAnsiColors normal;
  final TerminalAnsiColors bright;

  String? get foreground => special.foreground;
  String? get background => special.background;
  String? get cursor => special.cursor;
  String? get selection => special.selection;
  String? get tab => special.tab;

  TerminalColorPalette copyWith({
    TerminalSpecialColors? special,
    TerminalAnsiColors? normal,
    TerminalAnsiColors? bright,
  }) {
    return TerminalColorPalette(
      special: special ?? this.special,
      normal: normal ?? this.normal,
      bright: bright ?? this.bright,
    );
  }

  TerminalColorPalette resolveWith([
    TerminalColorPalette defaults = defaultTerminalColorPalette,
  ]) {
    return TerminalColorPalette(
      special: special.resolveWith(defaults.special),
      normal: normal.resolveWith(defaults.normal),
      bright: bright.resolveWith(defaults.bright),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'special': special.toJson(),
      'normal': normal.toJson(),
      'bright': bright.toJson(),
    };
  }

  factory TerminalColorPalette.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalColorPalette(
      special: TerminalSpecialColors.fromJson(map?['special']),
      normal: TerminalAnsiColors.fromJson(map?['normal']),
      bright: TerminalAnsiColors.fromJson(map?['bright']),
    );
  }
}

const TerminalColorPalette defaultTerminalColorPalette = TerminalColorPalette(
  special: defaultTerminalSpecialColors,
  normal: defaultTerminalAnsiColors,
  bright: defaultTerminalBrightAnsiColors,
);

class TerminalCursorConfig {
  const TerminalCursorConfig({
    this.shape = TerminalCursorShape.block,
    this.blink = true,
  });

  final TerminalCursorShape shape;
  final bool blink;

  TerminalCursorConfig copyWith({TerminalCursorShape? shape, bool? blink}) {
    return TerminalCursorConfig(
      shape: shape ?? this.shape,
      blink: blink ?? this.blink,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'shape': shape.name, 'blink': blink};
  }

  factory TerminalCursorConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalCursorConfig(
      shape: _cursorShapeFromJson(map?['shape']),
      blink: _boolOr(map?['blink'], true),
    );
  }
}

class TerminalDisplayConfig {
  const TerminalDisplayConfig({
    this.font = const TerminalFontConfig(),
    this.colors = const TerminalColorPalette(),
    this.cursor = const TerminalCursorConfig(),
  });

  final TerminalFontConfig font;
  final TerminalColorPalette colors;
  final TerminalCursorConfig cursor;

  TerminalDisplayConfig copyWith({
    TerminalFontConfig? font,
    TerminalColorPalette? colors,
    TerminalCursorConfig? cursor,
  }) {
    return TerminalDisplayConfig(
      font: font ?? this.font,
      colors: colors ?? this.colors,
      cursor: cursor ?? this.cursor,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'font': font.toJson(),
      'colors': colors.toJson(),
      'cursor': cursor.toJson(),
    };
  }

  factory TerminalDisplayConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalDisplayConfig(
      font: TerminalFontConfig.fromJson(map?['font']),
      colors: TerminalColorPalette.fromJson(map?['colors']),
      cursor: TerminalCursorConfig.fromJson(map?['cursor']),
    );
  }
}

class TerminalInteractionConfig {
  const TerminalInteractionConfig({
    this.copyOnSelect = false,
    this.optionDragMode = TerminalOptionDragMode.blockSelection,
  });

  final bool copyOnSelect;
  final TerminalOptionDragMode optionDragMode;

  TerminalInteractionConfig copyWith({
    bool? copyOnSelect,
    TerminalOptionDragMode? optionDragMode,
  }) {
    return TerminalInteractionConfig(
      copyOnSelect: copyOnSelect ?? this.copyOnSelect,
      optionDragMode: optionDragMode ?? this.optionDragMode,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'copyOnSelect': copyOnSelect,
      'optionDragMode': optionDragMode.jsonValue,
    };
  }

  factory TerminalInteractionConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalInteractionConfig(
      copyOnSelect: _boolOr(map?['copyOnSelect'], false),
      optionDragMode: TerminalOptionDragMode.fromJsonValue(
        map?['optionDragMode'],
      ),
    );
  }
}

class TerminalSessionConfig {
  const TerminalSessionConfig({
    required this.launch,
    this.connection = const TerminalConnectionConfig.local(),
    this.emulation = TerminalEmulation.xterm256,
    int scrollbackLines = defaultTerminalScrollbackLines,
    this.graphics = const TerminalGraphicsConfig(),
    this.dragDropEnabled = false,
    this.shellIntegration = const TerminalShellIntegrationConfig(),
    this.display = const TerminalDisplayConfig(),
    this.interaction = const TerminalInteractionConfig(),
  }) : scrollbackLines = scrollbackLines < 1
           ? defaultTerminalScrollbackLines
           : scrollbackLines > maxTerminalScrollbackLines
           ? maxTerminalScrollbackLines
           : scrollbackLines;

  final TerminalLaunchConfig launch;
  final TerminalConnectionConfig connection;
  final TerminalEmulation emulation;
  final int scrollbackLines;
  final TerminalGraphicsConfig graphics;

  /// Enables bounded OSC 72 parsing. Set this only when a host drag/drop
  /// bridge is installed; false prevents advertising unusable support.
  final bool dragDropEnabled;
  final TerminalShellIntegrationConfig shellIntegration;
  final TerminalDisplayConfig display;
  final TerminalInteractionConfig interaction;

  TerminalSessionConfig copyWith({
    TerminalLaunchConfig? launch,
    TerminalConnectionConfig? connection,
    TerminalEmulation? emulation,
    int? scrollbackLines,
    TerminalGraphicsConfig? graphics,
    bool? dragDropEnabled,
    TerminalShellIntegrationConfig? shellIntegration,
    TerminalDisplayConfig? display,
    TerminalInteractionConfig? interaction,
  }) {
    return TerminalSessionConfig(
      launch: launch ?? this.launch,
      connection: connection ?? this.connection,
      emulation: emulation ?? this.emulation,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
      graphics: graphics ?? this.graphics,
      dragDropEnabled: dragDropEnabled ?? this.dragDropEnabled,
      shellIntegration: shellIntegration ?? this.shellIntegration,
      display: display ?? this.display,
      interaction: interaction ?? this.interaction,
    );
  }

  Map<String, Object?> toJson({bool includeSensitiveFields = true}) {
    return <String, Object?>{
      'launch': launch.toJson(),
      'connection': connection.toJson(
        includeSensitiveFields: includeSensitiveFields,
      ),
      'terminal': <String, Object?>{
        'emulation': emulation.name,
        'scrollbackLines': normalizeTerminalScrollbackLines(scrollbackLines),
        'graphics': graphics.toJson(),
        'dragDropEnabled': dragDropEnabled,
      },
      'shellIntegration': shellIntegration.toJson(),
      'appearance': display.toJson(),
      'interaction': interaction.toJson(),
    };
  }

  factory TerminalSessionConfig.fromJson(Map<String, Object?> json) {
    final terminal = _asObjectMap(json['terminal']);
    return TerminalSessionConfig(
      launch: TerminalLaunchConfig.fromJson(json['launch']),
      connection: TerminalConnectionConfig.fromJson(json['connection']),
      emulation: _emulationFromJson(terminal?['emulation']),
      scrollbackLines: _positiveIntOr(
        terminal?['scrollbackLines'],
        defaultTerminalScrollbackLines,
        maximum: maxTerminalScrollbackLines,
      ),
      graphics: TerminalGraphicsConfig.fromJson(terminal?['graphics']),
      dragDropEnabled: _boolOr(terminal?['dragDropEnabled'], false),
      display: TerminalDisplayConfig.fromJson(json['appearance']),
      interaction: TerminalInteractionConfig.fromJson(json['interaction']),
      shellIntegration: TerminalShellIntegrationConfig.fromJson(
        json['shellIntegration'],
      ),
    );
  }

  factory TerminalSessionConfig.fromProfileJson(
    Map<String, Object?> json, {
    required String defaultProgram,
    TerminalConfigWarningCallback? onWarning,
  }) {
    final terminal = _asObjectMap(json['terminal']);
    return TerminalSessionConfig(
      launch: _launchConfigFromProfileJson(
        json['launch'],
        legacy: json,
        defaultProgram: defaultProgram,
        onWarning: onWarning,
      ),
      connection: TerminalConnectionConfig.fromJson(json['connection']),
      emulation: _emulationFromProfileJson(
        terminal?['emulation'] ?? json['terminalEmulation'],
        path: terminal == null ? 'terminalEmulation' : 'terminal.emulation',
        onWarning: onWarning,
      ),
      scrollbackLines: _positiveIntField(
        terminal?['scrollbackLines'],
        fallback: defaultTerminalScrollbackLines,
        maximum: maxTerminalScrollbackLines,
        path: 'terminal.scrollbackLines',
        onWarning: onWarning,
      ),
      graphics: _graphicsConfigFromProfileJson(
        terminal?['graphics'],
        onWarning: onWarning,
      ),
      dragDropEnabled: _boolOr(terminal?['dragDropEnabled'], false),
      display: _displayConfigFromProfileJson(
        json['appearance'],
        onWarning: onWarning,
      ),
      interaction: _interactionConfigFromProfileJson(
        json['interaction'],
        onWarning: onWarning,
      ),
      shellIntegration: _shellIntegrationConfigFromProfileJson(
        json['shellIntegration'],
        onWarning: onWarning,
      ),
    );
  }
}

class TerminalConfigWarning {
  const TerminalConfigWarning({
    required this.path,
    required this.rawValue,
    required this.fallbackSummary,
  });

  final String path;
  final Object? rawValue;
  final String fallbackSummary;
}

typedef TerminalConfigWarningCallback =
    void Function(TerminalConfigWarning warning);

TerminalLaunchConfig _launchConfigFromProfileJson(
  Object? json, {
  required Map<String, Object?> legacy,
  required String defaultProgram,
  required TerminalConfigWarningCallback? onWarning,
}) {
  final launch = _asObjectMap(json);
  if (launch != null) {
    final rawProgram = launch['program'];
    final program = _stringOrNull(rawProgram)?.trim();
    return TerminalLaunchConfig(
      program: program == null || program.isEmpty
          ? _warnAndDefaultProgram(rawProgram, defaultProgram, onWarning)
          : program,
      args: _stringListField(
        launch['args'],
        path: 'launch.args',
        maxEntries: maxTerminalLaunchArgs,
        onWarning: onWarning,
      ),
      env: _stringMapField(
        launch['env'],
        path: 'launch.env',
        maxEntries: maxTerminalEnvironmentEntries,
        onWarning: onWarning,
      ),
      cwd: _nullableStringField(
        launch['cwd'],
        path: 'launch.cwd',
        onWarning: onWarning,
      ),
    );
  }

  final rawProgram = legacy['shell'];
  final program = _stringOrNull(rawProgram)?.trim();
  return TerminalLaunchConfig(
    program: program == null || program.isEmpty
        ? _warnAndDefaultProgram(
            rawProgram,
            defaultProgram,
            onWarning,
            path: 'shell',
          )
        : program,
    args: _stringListField(
      legacy['args'],
      path: 'args',
      maxEntries: maxTerminalLaunchArgs,
      onWarning: onWarning,
    ),
    env: _stringMapField(
      legacy['env'],
      path: 'env',
      maxEntries: maxTerminalEnvironmentEntries,
      onWarning: onWarning,
    ),
    cwd: _nullableStringField(legacy['cwd'], path: 'cwd', onWarning: onWarning),
  );
}

TerminalDisplayConfig _displayConfigFromProfileJson(
  Object? json, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  final appearance = _asObjectMap(json);
  final font = _asObjectMap(appearance?['font']);
  final rawFamily = font?['family'];
  final family = _stringOrNull(rawFamily)?.trim();
  final colors = _asObjectMap(appearance?['colors']);
  final specialColors = _asObjectMap(colors?['special']);
  final normalColors = _asObjectMap(colors?['normal']);
  final brightColors = _asObjectMap(colors?['bright']);
  final cursor = _asObjectMap(appearance?['cursor']);
  _warnLegacyFlatColorFields(colors, onWarning: onWarning);
  return TerminalDisplayConfig(
    font: TerminalFontConfig(
      family: family == null || family.isEmpty
          ? _warnAndDefaultString(
              rawFamily,
              path: 'appearance.font.family',
              fallback: terminalPrimaryFontFamily,
              onWarning: onWarning,
            )
          : family,
      fallback: _fontFallbackList(
        font?['fallback'],
        maxEntries: maxTerminalFontFallbackFamilies,
        onWarning: onWarning,
      ),
      size: _positiveDoubleField(
        font?['size'],
        fallback: terminalFontSize,
        path: 'appearance.font.size',
        onWarning: onWarning,
      ),
      lineHeight: _positiveDoubleField(
        font?['lineHeight'],
        fallback: terminalLineHeight,
        path: 'appearance.font.lineHeight',
        onWarning: onWarning,
      ),
    ),
    colors: TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: _nullableHexColor(
          specialColors?['foreground'],
          path: 'appearance.colors.special.foreground',
          onWarning: onWarning,
        ),
        background: _nullableHexColor(
          specialColors?['background'],
          path: 'appearance.colors.special.background',
          onWarning: onWarning,
        ),
        cursor: _nullableHexColor(
          specialColors?['cursor'],
          path: 'appearance.colors.special.cursor',
          onWarning: onWarning,
        ),
        selection: _nullableHexColor(
          specialColors?['selection'],
          path: 'appearance.colors.special.selection',
          onWarning: onWarning,
        ),
        tab: _nullableHexColor(
          specialColors?['tab'],
          path: 'appearance.colors.special.tab',
          onWarning: onWarning,
        ),
      ),
      normal: _ansiColorsFromProfileJson(
        normalColors,
        path: 'appearance.colors.normal',
        onWarning: onWarning,
      ),
      bright: _ansiColorsFromProfileJson(
        brightColors,
        path: 'appearance.colors.bright',
        onWarning: onWarning,
      ),
    ),
    cursor: TerminalCursorConfig(
      shape: _cursorShapeFromProfileJson(
        cursor?['shape'],
        path: 'appearance.cursor.shape',
        onWarning: onWarning,
      ),
      blink: _boolField(
        cursor?['blink'],
        fallback: true,
        path: 'appearance.cursor.blink',
        onWarning: onWarning,
      ),
    ),
  );
}

TerminalInteractionConfig _interactionConfigFromProfileJson(
  Object? json, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  final interaction = _asObjectMap(json);
  return TerminalInteractionConfig(
    copyOnSelect: _boolField(
      interaction?['copyOnSelect'],
      fallback: false,
      path: 'interaction.copyOnSelect',
      onWarning: onWarning,
    ),
    optionDragMode: _optionDragModeFromProfileJson(
      interaction?['optionDragMode'],
      path: 'interaction.optionDragMode',
      onWarning: onWarning,
    ),
  );
}

TerminalShellIntegrationConfig _shellIntegrationConfigFromProfileJson(
  Object? json, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  final shellIntegration = _asObjectMap(json);
  return TerminalShellIntegrationConfig(
    enabled: _boolField(
      shellIntegration?['enabled'],
      fallback: true,
      path: 'shellIntegration.enabled',
      onWarning: onWarning,
    ),
  );
}

TerminalGraphicsConfig _graphicsConfigFromProfileJson(
  Object? json, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  final graphics = _asObjectMap(json);
  return TerminalGraphicsConfig(
    enabled: _boolField(
      graphics?['enabled'],
      fallback: true,
      path: 'terminal.graphics.enabled',
      onWarning: onWarning,
    ),
    advertise: _graphicsAdvertiseField(
      graphics?['advertise'],
      fallback: 'kitty',
      path: 'terminal.graphics.advertise',
      onWarning: onWarning,
    ),
    maxImageBytes: _positiveIntField(
      graphics?['maxImageBytes'],
      fallback: defaultTerminalGraphicMaxImageBytes,
      path: 'terminal.graphics.maxImageBytes',
      onWarning: onWarning,
    ),
    maxTotalBytes: _positiveIntField(
      graphics?['maxTotalBytes'],
      fallback: defaultTerminalGraphicMaxTotalBytes,
      path: 'terminal.graphics.maxTotalBytes',
      onWarning: onWarning,
    ),
  );
}

void _warnLegacyFlatColorFields(
  Map<String, Object?>? colors, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (colors == null) {
    return;
  }
  for (final field in const <String>[
    'foreground',
    'background',
    'cursor',
    'selection',
    'tab',
  ]) {
    if (!colors.containsKey(field)) {
      continue;
    }
    onWarning?.call(
      TerminalConfigWarning(
        path: 'appearance.colors.$field',
        rawValue: colors[field],
        fallbackSummary:
            'ignored legacy flat color field; use appearance.colors.special.$field',
      ),
    );
  }
}

Map<String, Object?>? _asObjectMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry as Object?),
    );
  }
  return null;
}

String? _stringOrNull(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

String? _trimmedStringOrNull(Object? value) {
  final text = _stringOrNull(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _normalizedConfigToken(Object? value) {
  return _trimmedStringOrNull(value)?.toLowerCase();
}

String? _hexColorOrNull(Object? rawValue) {
  final value = _stringOrNull(rawValue);
  if (value == null) {
    return null;
  }
  final normalized = value.trim().toUpperCase();
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized) ? normalized : null;
}

List<String> _stringList(
  Object? value, {
  List<String> fallback = const <String>[],
  int? maxEntries,
}) {
  if (value is List) {
    final strings = <String>[];
    final entries = maxEntries == null
        ? value
        : value.take(maxEntries * _directConfigEntryScanMultiplier);
    for (final entry in entries) {
      if (maxEntries != null && strings.length >= maxEntries) {
        break;
      }
      final text = _trimmedStringOrNull(entry);
      if (text != null) {
        strings.add(text);
      }
    }
    return strings;
  }
  return fallback;
}

List<Object?> _objectList(Object? value, {int? maxEntries}) {
  if (value is! List) {
    return const <Object?>[];
  }
  return (maxEntries == null ? value : value.take(maxEntries)).toList(
    growable: false,
  );
}

List<String> _trimmedStringList(
  Object? value, {
  required List<String> fallback,
  int? maxEntries,
}) {
  if (value is! List) {
    return fallback;
  }
  final values = <String>[];
  final entries = maxEntries == null
      ? value
      : value.take(maxEntries * _directConfigEntryScanMultiplier);
  for (final entry in entries) {
    if (maxEntries != null && values.length >= maxEntries) {
      break;
    }
    final text = _trimmedStringOrNull(entry);
    if (text != null) {
      values.add(text);
    }
  }
  return values.isEmpty ? fallback : values;
}

Map<String, String> _stringMap(Object? value, {int? maxEntries}) {
  if (value is Map) {
    final values = <String, String>{};
    final entries = maxEntries == null
        ? value.entries
        : value.entries.take(maxEntries * _directConfigEntryScanMultiplier);
    for (final entry in entries) {
      if (maxEntries != null && values.length >= maxEntries) {
        break;
      }
      final key = entry.key;
      final entryValue = entry.value;
      if (key is String && key.trim().isNotEmpty && entryValue is String) {
        values[key.trim()] = entryValue;
      }
    }
    return values;
  }
  return const <String, String>{};
}

double _positiveFiniteDoubleOr(Object? value, double fallback) {
  if (value is num) {
    final parsed = value.toDouble();
    if (parsed.isFinite && parsed > 0) {
      return parsed;
    }
  }
  return fallback;
}

int _positiveIntOr(Object? value, int fallback, {int? maximum}) {
  final parsed = _positiveWholeIntOrNull(value);
  if (parsed == null) {
    return fallback;
  }
  if (maximum != null && parsed > maximum) {
    return maximum;
  }
  return parsed;
}

int _nonNegativeIntOr(Object? value, int fallback, {int? maximum}) {
  if (value is! num || !value.isFinite || value < 0 || value != value.toInt()) {
    return fallback;
  }
  final parsed = value.toInt();
  if (maximum != null && parsed > maximum) {
    return maximum;
  }
  return parsed;
}

bool _boolOr(Object? value, bool fallback) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

String _graphicsAdvertiseOr(Object? value, String fallback) {
  final parsed = _trimmedStringOrNull(value);
  return parsed == null || parsed.isEmpty ? fallback : parsed;
}

String _graphicsAdvertiseField(
  Object? rawValue, {
  required String fallback,
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  final value = _trimmedStringOrNull(rawValue);
  if (value != null && value.isNotEmpty) {
    return value;
  }
  if (rawValue != null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used default value $fallback',
      ),
    );
  }
  return fallback;
}

TerminalCursorShape _cursorShapeFromJson(Object? value) {
  return switch (_normalizedConfigToken(value)) {
    'underline' => TerminalCursorShape.underline,
    'beam' => TerminalCursorShape.beam,
    _ => TerminalCursorShape.block,
  };
}

TerminalEmulation _emulationFromJson(Object? value) {
  return switch (_normalizedConfigToken(value)) {
    'vt220' => TerminalEmulation.vt220,
    _ => TerminalEmulation.xterm256,
  };
}

String _warnAndDefaultProgram(
  Object? rawValue,
  String fallback,
  TerminalConfigWarningCallback? onWarning, {
  String path = 'launch.program',
}) {
  onWarning?.call(
    TerminalConfigWarning(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used default shell "$fallback"',
    ),
  );
  return fallback;
}

String _warnAndDefaultString(
  Object? rawValue, {
  required String path,
  required String fallback,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue != null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used default value "$fallback"',
      ),
    );
  }
  return fallback;
}

String? _nullableStringField(
  Object? rawValue, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return null;
  }
  final value = _stringOrNull(rawValue)?.trim();
  if (value != null && value.isNotEmpty) {
    return value;
  }
  onWarning?.call(
    TerminalConfigWarning(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used default null value',
    ),
  );
  return null;
}

List<String> _stringListField(
  Object? rawValue, {
  required String path,
  int? maxEntries,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return const <String>[];
  }
  if (rawValue is! List<dynamic>) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used empty list',
      ),
    );
    return const <String>[];
  }
  final values = <String>[];
  if (maxEntries != null && rawValue.length > maxEntries) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue.length,
        fallbackSummary: 'loaded first $maxEntries valid entries',
      ),
    );
  }
  final entries = maxEntries == null
      ? rawValue
      : rawValue.take(maxEntries * _directConfigEntryScanMultiplier);
  var index = 0;
  for (final entry in entries) {
    if (maxEntries != null && values.length >= maxEntries) {
      break;
    }
    if (entry is String) {
      if (entry.isEmpty) {
        onWarning?.call(
          TerminalConfigWarning(
            path: '$path[$index]',
            rawValue: entry,
            fallbackSummary: 'ignored empty value',
          ),
        );
        index += 1;
        continue;
      }
      values.add(entry);
      index += 1;
      continue;
    }
    onWarning?.call(
      TerminalConfigWarning(
        path: '$path[$index]',
        rawValue: entry,
        fallbackSummary: 'ignored invalid non-string value',
      ),
    );
    index += 1;
  }
  return values;
}

List<String> _fontFallbackList(
  Object? rawValue, {
  int? maxEntries,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return <String>[...terminalFontFamilyFallback];
  }
  if (rawValue is! List<dynamic>) {
    onWarning?.call(
      TerminalConfigWarning(
        path: 'appearance.font.fallback',
        rawValue: rawValue,
        fallbackSummary: 'used default fallback font list',
      ),
    );
    return <String>[...terminalFontFamilyFallback];
  }
  final values = <String>[];
  if (maxEntries != null && rawValue.length > maxEntries) {
    onWarning?.call(
      TerminalConfigWarning(
        path: 'appearance.font.fallback',
        rawValue: rawValue.length,
        fallbackSummary: 'loaded first $maxEntries valid fallback font entries',
      ),
    );
  }
  final entries = maxEntries == null
      ? rawValue
      : rawValue.take(maxEntries * _directConfigEntryScanMultiplier);
  var index = 0;
  for (final entry in entries) {
    if (maxEntries != null && values.length >= maxEntries) {
      break;
    }
    if (entry is String) {
      final normalized = entry.trim();
      if (normalized.isEmpty) {
        onWarning?.call(
          TerminalConfigWarning(
            path: 'appearance.font.fallback[$index]',
            rawValue: entry,
            fallbackSummary: 'ignored empty value',
          ),
        );
        index += 1;
        continue;
      }
      values.add(normalized);
      index += 1;
      continue;
    }
    onWarning?.call(
      TerminalConfigWarning(
        path: 'appearance.font.fallback[$index]',
        rawValue: entry,
        fallbackSummary: 'ignored invalid non-string value',
      ),
    );
    index += 1;
  }
  return values.isEmpty ? <String>[...terminalFontFamilyFallback] : values;
}

Map<String, String> _stringMapField(
  Object? rawValue, {
  required String path,
  int? maxEntries,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return const <String, String>{};
  }
  if (rawValue is! Map) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used empty map',
      ),
    );
    return const <String, String>{};
  }
  final values = <String, String>{};
  if (maxEntries != null && rawValue.length > maxEntries) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue.length,
        fallbackSummary: 'loaded first $maxEntries valid entries',
      ),
    );
  }
  final entries = maxEntries == null
      ? rawValue.entries
      : rawValue.entries.take(maxEntries * _directConfigEntryScanMultiplier);
  for (final entry in entries) {
    if (maxEntries != null && values.length >= maxEntries) {
      break;
    }
    final key = entry.key;
    final value = entry.value;
    if (key is! String || key.trim().isEmpty || value is! String) {
      onWarning?.call(
        TerminalConfigWarning(
          path: '$path.${key ?? 'unknown'}',
          rawValue: <Object?>[key, value],
          fallbackSummary: 'ignored invalid environment entry',
        ),
      );
      continue;
    }
    values[key.trim()] = value;
  }
  return values;
}

int _positiveIntField(
  Object? rawValue, {
  required int fallback,
  int? maximum,
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  final value = _positiveWholeIntOrNull(rawValue);
  if (value != null) {
    if (maximum != null && value > maximum) {
      onWarning?.call(
        TerminalConfigWarning(
          path: path,
          rawValue: rawValue,
          fallbackSummary: 'clamped to maximum value $maximum',
        ),
      );
      return maximum;
    }
    return value;
  }
  if (rawValue != null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used default value $fallback',
      ),
    );
  }
  return fallback;
}

int? _positiveWholeIntOrNull(Object? rawValue) {
  if (rawValue is int) {
    return rawValue >= 1 ? rawValue : null;
  }
  if (rawValue is num && rawValue.isFinite) {
    final parsed = rawValue.toInt();
    if (parsed >= 1 && rawValue == parsed) {
      return parsed;
    }
  }
  return null;
}

double _positiveDoubleField(
  Object? rawValue, {
  required double fallback,
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue is num) {
    final value = rawValue.toDouble();
    if (value.isFinite && value > 0) {
      return value;
    }
  }
  if (rawValue != null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used default value $fallback',
      ),
    );
  }
  return fallback;
}

bool _boolField(
  Object? rawValue, {
  required bool fallback,
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue is bool) {
    return rawValue;
  }
  if (rawValue != null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used default value $fallback',
      ),
    );
  }
  return fallback;
}

String? _nullableHexColor(
  Object? rawValue, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return null;
  }
  final value = _hexColorOrNull(rawValue);
  if (value != null) {
    return value;
  }
  onWarning?.call(
    TerminalConfigWarning(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used inherited default color',
    ),
  );
  return null;
}

TerminalAnsiColors _ansiColorsFromProfileJson(
  Object? rawValue, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return const TerminalAnsiColors();
  }
  final colors = _asObjectMap(rawValue);
  if (colors == null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used inherited default ansi colors',
      ),
    );
    return const TerminalAnsiColors();
  }
  return TerminalAnsiColors(
    black: _nullableHexColor(
      colors['black'],
      path: '$path.black',
      onWarning: onWarning,
    ),
    red: _nullableHexColor(
      colors['red'],
      path: '$path.red',
      onWarning: onWarning,
    ),
    green: _nullableHexColor(
      colors['green'],
      path: '$path.green',
      onWarning: onWarning,
    ),
    yellow: _nullableHexColor(
      colors['yellow'],
      path: '$path.yellow',
      onWarning: onWarning,
    ),
    blue: _nullableHexColor(
      colors['blue'],
      path: '$path.blue',
      onWarning: onWarning,
    ),
    magenta: _nullableHexColor(
      colors['magenta'],
      path: '$path.magenta',
      onWarning: onWarning,
    ),
    cyan: _nullableHexColor(
      colors['cyan'],
      path: '$path.cyan',
      onWarning: onWarning,
    ),
    white: _nullableHexColor(
      colors['white'],
      path: '$path.white',
      onWarning: onWarning,
    ),
  );
}

TerminalEmulation _emulationFromProfileJson(
  Object? raw, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  return switch (_normalizedConfigToken(raw)) {
    'vt220' => TerminalEmulation.vt220,
    'xterm256' || 'xterm-256color' || null => TerminalEmulation.xterm256,
    _ => () {
      onWarning?.call(
        TerminalConfigWarning(
          path: path,
          rawValue: raw,
          fallbackSummary:
              'used default emulation "${TerminalEmulation.xterm256.name}"',
        ),
      );
      return TerminalEmulation.xterm256;
    }(),
  };
}

TerminalCursorShape _cursorShapeFromProfileJson(
  Object? raw, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  return switch (_normalizedConfigToken(raw)) {
    'underline' => TerminalCursorShape.underline,
    'beam' => TerminalCursorShape.beam,
    'block' || null => TerminalCursorShape.block,
    _ => () {
      onWarning?.call(
        TerminalConfigWarning(
          path: path,
          rawValue: raw,
          fallbackSummary:
              'used default cursor shape "${TerminalCursorShape.block.name}"',
        ),
      );
      return TerminalCursorShape.block;
    }(),
  };
}

TerminalOptionDragMode _optionDragModeFromProfileJson(
  Object? raw, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  return switch (_normalizedConfigToken(raw)) {
    'normal_selection' => TerminalOptionDragMode.normalSelection,
    'block_selection' || null => TerminalOptionDragMode.blockSelection,
    _ => () {
      onWarning?.call(
        TerminalConfigWarning(
          path: path,
          rawValue: raw,
          fallbackSummary:
              'used default option-drag mode "${TerminalOptionDragMode.blockSelection.jsonValue}"',
        ),
      );
      return TerminalOptionDragMode.blockSelection;
    }(),
  };
}

const Object _terminalConfigNoChange = Object();
