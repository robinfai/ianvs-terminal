const int currentTerminalSessionDescriptorVersion = 1;

const int _maxSessionCommandArguments = 128;
const int _maxSessionEnvironmentKeys = 256;
const int _sessionDescriptorScanMultiplier = 4;
const Object _sessionDescriptorNoChange = Object();

final class UnsupportedTerminalSessionDescriptorVersion implements Exception {
  const UnsupportedTerminalSessionDescriptorVersion(this.version);

  final int version;

  @override
  String toString() {
    return 'Unsupported terminal session descriptor version: $version '
        '(current: $currentTerminalSessionDescriptorVersion)';
  }
}

enum TerminalSessionExitState { unknown, running, exited }

enum TerminalSessionRestartPolicy { relaunch, never }

class TerminalSessionCommand {
  const TerminalSessionCommand({
    required this.program,
    this.arguments = const <String>[],
  });

  final String program;
  final List<String> arguments;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'program': _nonEmptyString(program) ?? '',
      'arguments': arguments
          .whereType<String>()
          .take(_maxSessionCommandArguments)
          .toList(growable: false),
    };
  }

  static TerminalSessionCommand? fromJson(Object? value) {
    final json = _objectMap(value);
    if (json == null) {
      return null;
    }
    final program = _nonEmptyString(json['program']);
    if (program == null) {
      return null;
    }
    return TerminalSessionCommand(
      program: program,
      arguments: _stringList(
        json['arguments'],
        maxEntries: _maxSessionCommandArguments,
        allowEmpty: true,
        trim: false,
      ),
    );
  }
}

class TerminalSessionEnvironmentMetadata {
  const TerminalSessionEnvironmentMetadata({
    this.keys = const <String>[],
    this.valuesRedacted = true,
  });

  final List<String> keys;

  /// Environment values are deliberately excluded from Workspace persistence.
  final bool valuesRedacted;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'keys': _normalizedEnvironmentKeys(keys),
      'valuesRedacted': true,
    };
  }

  static TerminalSessionEnvironmentMetadata fromJson(Object? value) {
    final json = _objectMap(value);
    if (json == null) {
      return const TerminalSessionEnvironmentMetadata();
    }
    return TerminalSessionEnvironmentMetadata(
      keys: _normalizedEnvironmentKeys(
        _stringList(json['keys'], maxEntries: _maxSessionEnvironmentKeys),
      ),
    );
  }
}

class TerminalSessionDescriptor {
  const TerminalSessionDescriptor({
    this.id = '',
    required this.profileId,
    this.command,
    this.cwd,
    this.environment = const TerminalSessionEnvironmentMetadata(),
    this.title,
    this.createdAtUtc,
    this.exitState = TerminalSessionExitState.unknown,
    this.exitCode,
    this.recordingPath,
    this.restartPolicy = TerminalSessionRestartPolicy.relaunch,
  });

  final String id;
  final String profileId;
  final TerminalSessionCommand? command;
  final String? cwd;
  final TerminalSessionEnvironmentMetadata environment;
  final String? title;
  final DateTime? createdAtUtc;
  final TerminalSessionExitState exitState;
  final int? exitCode;
  final String? recordingPath;
  final TerminalSessionRestartPolicy restartPolicy;

  int get schemaVersion => currentTerminalSessionDescriptorVersion;

  Map<String, Object?> toJson({String? fallbackId}) {
    final normalizedId = _nonEmptyString(id) ?? _nonEmptyString(fallbackId);
    final normalizedCommand = command == null
        ? null
        : TerminalSessionCommand.fromJson(command!.toJson());
    final normalizedExitCode = exitState == TerminalSessionExitState.exited
        ? exitCode
        : null;
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'id': normalizedId ?? '',
      'profileId': _nonEmptyString(profileId) ?? '',
      'command': normalizedCommand?.toJson(),
      'cwd': _nonEmptyString(cwd),
      'environment': environment.toJson(),
      'title': _nonEmptyString(title),
      'createdAtUtc': createdAtUtc?.toUtc().toIso8601String(),
      'exitState': exitState.name,
      'exitCode': normalizedExitCode,
      'recordingPath': _nonEmptyString(recordingPath),
      'restartPolicy': restartPolicy.name,
    };
  }

  static TerminalSessionDescriptor fromJson(Map<Object?, Object?> json) {
    _validateDescriptorVersion(json['schemaVersion']);
    final exitState = _exitStateFromJson(json['exitState']);
    return TerminalSessionDescriptor(
      id: _nonEmptyString(json['id']) ?? '',
      profileId: _nonEmptyString(json['profileId']) ?? '',
      command: TerminalSessionCommand.fromJson(json['command']),
      cwd: _nonEmptyString(json['cwd']),
      environment: TerminalSessionEnvironmentMetadata.fromJson(
        json['environment'],
      ),
      title: _nonEmptyString(json['title']),
      createdAtUtc: _utcDateTimeOrNull(json['createdAtUtc']),
      exitState: exitState,
      exitCode: exitState == TerminalSessionExitState.exited
          ? json['exitCode'] as int?
          : null,
      recordingPath: _nonEmptyString(json['recordingPath']),
      restartPolicy: _restartPolicyFromJson(json['restartPolicy']),
    );
  }

  static TerminalSessionDescriptor fromLegacyIntent(
    Map<Object?, Object?> json, {
    required String fallbackId,
  }) {
    return TerminalSessionDescriptor(
      id: _nonEmptyString(fallbackId) ?? '',
      profileId: _nonEmptyString(json['profileId']) ?? '',
      cwd: _nonEmptyString(json['cwd']),
      restartPolicy: TerminalSessionRestartPolicy.relaunch,
    );
  }

  TerminalSessionDescriptor copyWith({
    String? id,
    String? profileId,
    Object? command = _sessionDescriptorNoChange,
    Object? cwd = _sessionDescriptorNoChange,
    TerminalSessionEnvironmentMetadata? environment,
    Object? title = _sessionDescriptorNoChange,
    Object? createdAtUtc = _sessionDescriptorNoChange,
    TerminalSessionExitState? exitState,
    Object? exitCode = _sessionDescriptorNoChange,
    Object? recordingPath = _sessionDescriptorNoChange,
    TerminalSessionRestartPolicy? restartPolicy,
  }) {
    return TerminalSessionDescriptor(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      command: identical(command, _sessionDescriptorNoChange)
          ? this.command
          : command as TerminalSessionCommand?,
      cwd: identical(cwd, _sessionDescriptorNoChange)
          ? this.cwd
          : cwd as String?,
      environment: environment ?? this.environment,
      title: identical(title, _sessionDescriptorNoChange)
          ? this.title
          : title as String?,
      createdAtUtc: identical(createdAtUtc, _sessionDescriptorNoChange)
          ? this.createdAtUtc
          : createdAtUtc as DateTime?,
      exitState: exitState ?? this.exitState,
      exitCode: identical(exitCode, _sessionDescriptorNoChange)
          ? this.exitCode
          : exitCode as int?,
      recordingPath: identical(recordingPath, _sessionDescriptorNoChange)
          ? this.recordingPath
          : recordingPath as String?,
      restartPolicy: restartPolicy ?? this.restartPolicy,
    );
  }
}

void _validateDescriptorVersion(Object? value) {
  if (value is! int) {
    throw const FormatException(
      'Session descriptor schemaVersion must be an integer.',
    );
  }
  if (value != currentTerminalSessionDescriptorVersion) {
    throw UnsupportedTerminalSessionDescriptorVersion(value);
  }
}

TerminalSessionExitState _exitStateFromJson(Object? value) {
  return switch (value) {
    'running' => TerminalSessionExitState.running,
    'exited' => TerminalSessionExitState.exited,
    _ => TerminalSessionExitState.unknown,
  };
}

TerminalSessionRestartPolicy _restartPolicyFromJson(Object? value) {
  return switch (value) {
    'never' => TerminalSessionRestartPolicy.never,
    _ => TerminalSessionRestartPolicy.relaunch,
  };
}

DateTime? _utcDateTimeOrNull(Object? value) {
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

Map<Object?, Object?>? _objectMap(Object? value) {
  return value is Map<Object?, Object?> ? value : null;
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

List<String> _stringList(
  Object? value, {
  required int maxEntries,
  bool allowEmpty = false,
  bool trim = true,
}) {
  if (value is! List<Object?>) {
    return const <String>[];
  }
  final strings = <String>[];
  for (final candidate in value.take(
    maxEntries * _sessionDescriptorScanMultiplier,
  )) {
    if (candidate is! String) {
      continue;
    }
    final normalized = trim ? candidate.trim() : candidate;
    if (!allowEmpty && normalized.isEmpty) {
      continue;
    }
    strings.add(normalized);
    if (strings.length == maxEntries) {
      break;
    }
  }
  return List.unmodifiable(strings);
}

List<String> _normalizedEnvironmentKeys(Iterable<String> values) {
  final keys = <String>{};
  for (final value in values.take(
    _maxSessionEnvironmentKeys * _sessionDescriptorScanMultiplier,
  )) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      keys.add(normalized);
    }
    if (keys.length == _maxSessionEnvironmentKeys) {
      break;
    }
  }
  final result = keys.toList(growable: false)..sort();
  return List.unmodifiable(result);
}
