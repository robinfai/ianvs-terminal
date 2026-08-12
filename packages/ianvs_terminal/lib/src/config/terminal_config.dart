import '../contracts/terminal_frame_normalization_policy.dart';
import 'terminal_defaults.dart';

const int maxTerminalLaunchArgs = 128;
const int maxTerminalEnvironmentEntries = 256;
const int maxTerminalFontFallbackFamilies = 32;
const int _directConfigEntryScanMultiplier = 4;

enum TerminalEmulation { xterm256, vt220 }

enum TerminalCursorShape {
  block,
  underline,
  beam;

  static TerminalCursorShape? fromWire(Object? value) {
    return switch (TerminalFrameNormalizationPolicy.cursorShape(value)) {
      TerminalWireCursorShape.block => TerminalCursorShape.block,
      TerminalWireCursorShape.underline => TerminalCursorShape.underline,
      TerminalWireCursorShape.beam => TerminalCursorShape.beam,
      null => null,
    };
  }
}

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
      type: switch (map?['type']) {
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
  return switch (value) {
    'password' => TerminalSshAuthMethod.password,
    'public_key' => TerminalSshAuthMethod.publicKey,
    'keyboard_interactive' => TerminalSshAuthMethod.keyboardInteractive,
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
  return switch (value) {
    'accept_new' => TerminalSshHostKeyPolicy.acceptNew,
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
    return switch (value) {
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
    if (map?['type'] != 'ssh') {
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
    _validateCurrentSessionConfigShape(json);
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
}

void _validateCurrentSessionConfigShape(Map<String, Object?> json) {
  _expectExactKeys(json, const <String>{
    'launch',
    'connection',
    'terminal',
    'shellIntegration',
    'appearance',
    'interaction',
  }, r'$');
  _expectExactObject(json['launch'], const <String>{
    'program',
    'args',
    'env',
    'cwd',
  }, r'$.launch');

  final connection = _expectExactObject(json['connection'], const <String>{
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
  }, r'$.connection');
  if (connection != null && connection['type'] != 'ssh') {
    _expectExactKeys(connection, const <String>{'type'}, r'$.connection');
  }
  _expectExactObjectList(connection?['proxyJumpProfiles'], const <String>{
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
  }, r'$.connection.proxyJumpProfiles');
  _expectExactObjectList(connection?['portForwards'], const <String>{
    'type',
    'bindHost',
    'bindPort',
    'targetHost',
    'targetPort',
  }, r'$.connection.portForwards');

  final terminal = _expectExactObject(json['terminal'], const <String>{
    'emulation',
    'scrollbackLines',
    'graphics',
    'dragDropEnabled',
  }, r'$.terminal');
  _expectExactObject(terminal?['graphics'], const <String>{
    'enabled',
    'advertise',
    'maxImageBytes',
    'maxTotalBytes',
  }, r'$.terminal.graphics');
  _expectExactObject(json['shellIntegration'], const <String>{
    'enabled',
  }, r'$.shellIntegration');

  final appearance = _expectExactObject(json['appearance'], const <String>{
    'font',
    'colors',
    'cursor',
  }, r'$.appearance');
  _expectExactObject(appearance?['font'], const <String>{
    'family',
    'fallback',
    'size',
    'lineHeight',
  }, r'$.appearance.font');
  final colors = _expectExactObject(appearance?['colors'], const <String>{
    'special',
    'normal',
    'bright',
  }, r'$.appearance.colors');
  _expectExactObject(colors?['special'], const <String>{
    'foreground',
    'background',
    'cursor',
    'selection',
    'tab',
  }, r'$.appearance.colors.special');
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
    colors?['normal'],
    ansiKeys,
    r'$.appearance.colors.normal',
  );
  _expectExactObject(
    colors?['bright'],
    ansiKeys,
    r'$.appearance.colors.bright',
  );
  _expectExactObject(appearance?['cursor'], const <String>{
    'shape',
    'blink',
  }, r'$.appearance.cursor');
  _expectExactObject(json['interaction'], const <String>{
    'copyOnSelect',
    'optionDragMode',
  }, r'$.interaction');
}

Map<Object?, Object?>? _expectExactObject(
  Object? value,
  Set<String> allowed,
  String path,
) {
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw FormatException('$path must be an object');
  }
  _expectExactKeys(value, allowed, path);
  return value;
}

void _expectExactObjectList(Object? value, Set<String> allowed, String path) {
  if (value == null) {
    return;
  }
  if (value is! List) {
    throw FormatException('$path must be an array');
  }
  for (var index = 0; index < value.length; index += 1) {
    _expectExactObject(value[index], allowed, '$path[$index]');
  }
}

void _expectExactKeys(
  Map<Object?, Object?> value,
  Set<String> allowed,
  String path,
) {
  for (final key in value.keys) {
    if (key is! String || !allowed.contains(key)) {
      throw FormatException('$path contains unknown field $key');
    }
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

TerminalCursorShape _cursorShapeFromJson(Object? value) {
  return switch (value) {
    'underline' => TerminalCursorShape.underline,
    'beam' => TerminalCursorShape.beam,
    _ => TerminalCursorShape.block,
  };
}

TerminalEmulation _emulationFromJson(Object? value) {
  return switch (value) {
    'vt220' => TerminalEmulation.vt220,
    _ => TerminalEmulation.xterm256,
  };
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

const Object _terminalConfigNoChange = Object();
