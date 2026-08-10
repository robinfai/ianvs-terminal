import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'native_pty_backend.dart' show resolveNativePtyLibraryPath;

typedef _ImportProfilesDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);

final class ImportedSshProfile {
  const ImportedSshProfile({
    required this.id,
    required this.name,
    required this.group,
    required this.source,
    required this.alias,
    required this.host,
    required this.user,
    required this.port,
    required this.auth,
    required this.privateKeys,
    required this.hostKeyPolicy,
    required this.connectTimeoutSeconds,
    required this.keepaliveSeconds,
    required this.keepaliveCountMax,
    this.portForwards = const <ImportedSshPortForward>[],
    this.agentForwarding = false,
    this.x11Forwarding = false,
    this.knownHostsFile,
    this.proxyCommand,
    this.proxyJump,
    this.proxyJumpProfiles = const <ImportedSshJumpProfile>[],
  });

  final String id;
  final String name;
  final String group;
  final String source;
  final String alias;
  final String host;
  final String user;
  final int port;
  final String auth;
  final List<String> privateKeys;
  final String hostKeyPolicy;
  final String? knownHostsFile;
  final int connectTimeoutSeconds;
  final int keepaliveSeconds;
  final int keepaliveCountMax;
  final List<ImportedSshPortForward> portForwards;
  final bool agentForwarding;
  final bool x11Forwarding;
  final String? proxyCommand;
  final String? proxyJump;
  final List<ImportedSshJumpProfile> proxyJumpProfiles;

  factory ImportedSshProfile.fromJson(Map<String, Object?> json) {
    return ImportedSshProfile(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      group: _requiredString(json, 'group'),
      source: _requiredString(json, 'source'),
      alias: _requiredString(json, 'alias'),
      host: _requiredString(json, 'host'),
      user: _requiredString(json, 'user'),
      port: _boundedInt(json['port'], fallback: 22, maximum: 65535),
      auth: _string(json['auth']) ?? 'auto',
      privateKeys: _strings(json['privateKeys']),
      hostKeyPolicy: _string(json['hostKeyPolicy']) ?? 'strict',
      knownHostsFile: _string(json['knownHostsFile']),
      connectTimeoutSeconds: _boundedInt(
        json['connectTimeoutSeconds'],
        fallback: 10,
        maximum: 120,
      ),
      keepaliveSeconds: _boundedInt(
        json['keepaliveSeconds'],
        fallback: 0,
        maximum: 86400,
        allowZero: true,
      ),
      keepaliveCountMax: _boundedInt(
        json['keepaliveCountMax'],
        fallback: 3,
        maximum: 100,
      ),
      portForwards: _objectList(
        json['portForwards'],
      ).take(128).map(ImportedSshPortForward.fromJson).toList(growable: false),
      agentForwarding: json['agentForwarding'] == true,
      x11Forwarding: json['x11Forwarding'] == true,
      proxyCommand: _string(json['proxyCommand']),
      proxyJump: _string(json['proxyJump']),
      proxyJumpProfiles: json['proxyJumpProfiles'] == null
          ? const <ImportedSshJumpProfile>[]
          : _strictObjectList(
              json['proxyJumpProfiles'],
              path: 'proxyJumpProfiles',
              maximum: 128,
            ).map(ImportedSshJumpProfile.fromJson).toList(growable: false),
    );
  }
}

/// Fully resolved settings for one ProxyJump hop imported from OpenSSH.
///
/// A jump is an independent authentication and host-verification boundary;
/// destination settings must never be substituted for these values.
final class ImportedSshJumpProfile {
  const ImportedSshJumpProfile({
    required this.host,
    required this.user,
    required this.port,
    required this.auth,
    required this.privateKeys,
    required this.hostKeyPolicy,
    required this.connectTimeoutSeconds,
    required this.keepaliveSeconds,
    required this.keepaliveCountMax,
    this.knownHostsFile,
  });

  final String host;
  final String user;
  final int port;
  final String auth;
  final List<String> privateKeys;
  final String hostKeyPolicy;
  final String? knownHostsFile;
  final int connectTimeoutSeconds;
  final int keepaliveSeconds;
  final int keepaliveCountMax;

  factory ImportedSshJumpProfile.fromJson(Map<String, Object?> json) {
    return ImportedSshJumpProfile(
      host: _strictRequiredString(
        json['host'],
        path: 'proxyJumpProfiles[].host',
        maximum: 4096,
      ),
      user: _strictRequiredString(
        json['user'],
        path: 'proxyJumpProfiles[].user',
        maximum: 4096,
      ),
      port: _strictBoundedInt(
        json['port'],
        path: 'proxyJumpProfiles[].port',
        minimum: 1,
        maximum: 65535,
      ),
      auth: _strictEnum(
        json['auth'],
        path: 'proxyJumpProfiles[].auth',
        values: const <String>{
          'auto',
          'password',
          'public_key',
          'keyboard_interactive',
        },
      ),
      privateKeys: _strictStringList(
        json['privateKeys'],
        path: 'proxyJumpProfiles[].privateKeys',
        maximum: 128,
        maximumStringLength: 4096,
      ),
      hostKeyPolicy: _strictEnum(
        json['hostKeyPolicy'],
        path: 'proxyJumpProfiles[].hostKeyPolicy',
        values: const <String>{'strict', 'accept_new', 'insecure'},
      ),
      knownHostsFile: _strictOptionalString(
        json['knownHostsFile'],
        path: 'proxyJumpProfiles[].knownHostsFile',
        maximum: 4096,
      ),
      connectTimeoutSeconds: _strictBoundedInt(
        json['connectTimeoutSeconds'],
        path: 'proxyJumpProfiles[].connectTimeoutSeconds',
        minimum: 1,
        maximum: 120,
      ),
      keepaliveSeconds: _strictBoundedInt(
        json['keepaliveSeconds'],
        path: 'proxyJumpProfiles[].keepaliveSeconds',
        minimum: 0,
        maximum: 86400,
      ),
      keepaliveCountMax: _strictBoundedInt(
        json['keepaliveCountMax'],
        path: 'proxyJumpProfiles[].keepaliveCountMax',
        minimum: 1,
        maximum: 100,
      ),
    );
  }
}

enum ImportedSshPortForwardType { local, remote, dynamic }

final class ImportedSshPortForward {
  const ImportedSshPortForward({
    required this.type,
    required this.bindHost,
    required this.bindPort,
    required this.targetHost,
    required this.targetPort,
  });

  final ImportedSshPortForwardType type;
  final String bindHost;
  final int bindPort;
  final String targetHost;
  final int targetPort;

  factory ImportedSshPortForward.fromJson(Map<String, Object?> json) {
    final type = switch (_string(json['type'])) {
      'remote' => ImportedSshPortForwardType.remote,
      'dynamic' => ImportedSshPortForwardType.dynamic,
      _ => ImportedSshPortForwardType.local,
    };
    return ImportedSshPortForward(
      type: type,
      bindHost: _string(json['bindHost']) ?? '127.0.0.1',
      bindPort: _boundedInt(json['bindPort'], fallback: 0, maximum: 65535),
      targetHost: _string(json['targetHost']) ?? '',
      targetPort: _boundedInt(
        json['targetPort'],
        fallback: 0,
        maximum: 65535,
        allowZero: true,
      ),
    );
  }
}

final class SshConfigImportWarning {
  const SshConfigImportWarning({required this.path, required this.message});

  final String path;
  final String message;

  factory SshConfigImportWarning.fromJson(Map<String, Object?> json) {
    return SshConfigImportWarning(
      path: _string(json['path']) ?? '',
      message: _string(json['message']) ?? 'Unknown SSH config warning',
    );
  }
}

final class ImportedSshProfilesDocument {
  const ImportedSshProfilesDocument({
    required this.sourcePath,
    required this.sourceMtimeMicros,
    required this.profiles,
    required this.warnings,
  });

  final String sourcePath;
  final int sourceMtimeMicros;
  final List<ImportedSshProfile> profiles;
  final List<SshConfigImportWarning> warnings;

  factory ImportedSshProfilesDocument.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['contract'] != 'ianvs-openssh-profiles-v1') {
      throw const FormatException('Unsupported SSH profile import document');
    }
    final json = decoded.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    return ImportedSshProfilesDocument(
      sourcePath: _string(json['sourcePath']) ?? '',
      sourceMtimeMicros: _boundedInt(
        json['sourceMtimeMicros'],
        fallback: 0,
        maximum: 0x7fffffffffffffff,
        allowZero: true,
      ),
      profiles: _objectList(
        json['profiles'],
      ).map(ImportedSshProfile.fromJson).toList(growable: false),
      warnings: _objectList(
        json['warnings'],
      ).map(SshConfigImportWarning.fromJson).toList(growable: false),
    );
  }
}

final class NativeSshConfigImporter {
  NativeSshConfigImporter(ffi.DynamicLibrary library)
    : _import = library
          .lookupFunction<
            ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>),
            _ImportProfilesDart
          >('ianvs_ssh_import_profiles_json'),
      _free = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<Utf8>),
            _FreeStringDart
          >('ianvs_string_free');

  final _ImportProfilesDart _import;
  final _FreeStringDart _free;

  factory NativeSshConfigImporter.load() {
    return NativeSshConfigImporter(
      Platform.isIOS
          ? ffi.DynamicLibrary.process()
          : ffi.DynamicLibrary.open(resolveNativePtyLibraryPath()),
    );
  }

  ImportedSshProfilesDocument importProfiles({String? configPath}) {
    ffi.Pointer<Utf8> pathPointer = ffi.nullptr;
    ffi.Pointer<Utf8> resultPointer = ffi.nullptr;
    try {
      if (configPath != null && configPath.trim().isNotEmpty) {
        pathPointer = configPath.trim().toNativeUtf8();
      }
      resultPointer = _import(pathPointer);
      if (resultPointer == ffi.nullptr) {
        throw StateError('Native SSH config import failed');
      }
      return ImportedSshProfilesDocument.fromJsonString(
        resultPointer.toDartString(),
      );
    } finally {
      if (pathPointer != ffi.nullptr) {
        malloc.free(pathPointer);
      }
      if (resultPointer != ffi.nullptr) {
        _free(resultPointer);
      }
    }
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _string(json[key]);
  if (value == null || value.isEmpty) {
    throw FormatException('SSH profile is missing $key');
  }
  return value;
}

String? _string(Object? value) => value is String ? value : null;

List<String> _strings(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().take(128).toList(growable: false);
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List) {
    return const <Map<String, Object?>>[];
  }
  return value
      .whereType<Map<Object?, Object?>>()
      .map((entry) {
        return entry.map((key, value) => MapEntry(key.toString(), value));
      })
      .toList(growable: false);
}

List<Map<String, Object?>> _strictObjectList(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value is! List || value.length > maximum) {
    throw FormatException('$path must contain at most $maximum objects');
  }
  final result = <Map<String, Object?>>[];
  for (var index = 0; index < value.length; index += 1) {
    final entry = value[index];
    if (entry is! Map || entry.keys.any((key) => key is! String)) {
      throw FormatException('$path[$index] must be a string-keyed object');
    }
    result.add(<String, Object?>{
      for (final item in entry.entries) item.key as String: item.value,
    });
  }
  return List<Map<String, Object?>>.unmodifiable(result);
}

String _strictRequiredString(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > maximum ||
      value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw FormatException('$path must be a non-empty bounded string');
  }
  return value;
}

String? _strictOptionalString(
  Object? value, {
  required String path,
  required int maximum,
}) {
  if (value == null) {
    return null;
  }
  if (value is! String ||
      value.length > maximum ||
      value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw FormatException('$path must be a bounded string');
  }
  return value;
}

String _strictEnum(
  Object? value, {
  required String path,
  required Set<String> values,
}) {
  if (value is! String || !values.contains(value)) {
    throw FormatException('$path must be one of ${values.join(', ')}');
  }
  return value;
}

int _strictBoundedInt(
  Object? value, {
  required String path,
  required int minimum,
  required int maximum,
}) {
  if (value is! int || value < minimum || value > maximum) {
    throw FormatException('$path must be an integer from $minimum to $maximum');
  }
  return value;
}

List<String> _strictStringList(
  Object? value, {
  required String path,
  required int maximum,
  required int maximumStringLength,
}) {
  if (value is! List || value.length > maximum) {
    throw FormatException('$path must contain at most $maximum strings');
  }
  final result = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    final item = value[index];
    if (item is! String ||
        item.isEmpty ||
        item.length > maximumStringLength ||
        item.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      throw FormatException('$path[$index] must be a non-empty bounded string');
    }
    result.add(item);
  }
  return List<String>.unmodifiable(result);
}

int _boundedInt(
  Object? value, {
  required int fallback,
  required int maximum,
  bool allowZero = false,
}) {
  if (value is! num || !value.isFinite || value != value.toInt()) {
    return fallback;
  }
  final parsed = value.toInt();
  if (parsed < (allowZero ? 0 : 1)) {
    return fallback;
  }
  return parsed > maximum ? maximum : parsed;
}
