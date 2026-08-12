const int currentTerminalRelaunchSpecVersion = 1;
const String terminalRelaunchSpecContract = 'ianvs-terminal-relaunch-spec-v1';

const int _maxRelaunchCommandArguments = 128;

final class UnsupportedTerminalRelaunchSpecVersion implements Exception {
  const UnsupportedTerminalRelaunchSpecVersion(this.version);

  final int version;

  @override
  String toString() {
    return 'Unsupported terminal relaunch spec version: $version '
        '(current: $currentTerminalRelaunchSpecVersion)';
  }
}

/// The complete persisted intent needed to launch a fresh local terminal.
///
/// Runtime state (title, timestamps and exit information) and recording
/// associations deliberately live outside this contract.
class TerminalRelaunchCommand {
  const TerminalRelaunchCommand({
    required this.program,
    this.arguments = const <String>[],
  });

  final String program;
  final List<String> arguments;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'program': _nonEmptyString(program) ?? '',
      'arguments': arguments
          .take(_maxRelaunchCommandArguments)
          .toList(growable: false),
    };
  }

  static TerminalRelaunchCommand? fromJson(Object? value) {
    final json = _objectMap(value);
    if (json == null) {
      return null;
    }
    final program = _nonEmptyString(json['program']);
    if (program == null) {
      return null;
    }
    return TerminalRelaunchCommand(
      program: program,
      arguments: _stringList(
        json['arguments'],
        maxEntries: _maxRelaunchCommandArguments,
        allowEmpty: true,
        trim: false,
      ),
    );
  }
}

class TerminalRelaunchSpec {
  const TerminalRelaunchSpec({required this.profileId, this.command, this.cwd});

  final String profileId;
  final TerminalRelaunchCommand? command;
  final String? cwd;

  int get schemaVersion => currentTerminalRelaunchSpecVersion;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'contract': terminalRelaunchSpecContract,
      'profileId': _nonEmptyString(profileId) ?? '',
      'cwd': _nonEmptyString(cwd),
    };
  }

  static TerminalRelaunchSpec fromJson(Map<Object?, Object?> json) {
    _validateVersion(json['schemaVersion']);
    if (json['contract'] != terminalRelaunchSpecContract) {
      throw const FormatException('Unsupported terminal relaunch contract.');
    }
    return TerminalRelaunchSpec(
      profileId: _nonEmptyString(json['profileId']) ?? '',
      cwd: _nonEmptyString(json['cwd']),
    );
  }
}

void _validateVersion(Object? value) {
  if (value is! int) {
    throw const FormatException(
      'Terminal relaunch spec schemaVersion must be an integer.',
    );
  }
  if (value != currentTerminalRelaunchSpecVersion) {
    throw UnsupportedTerminalRelaunchSpecVersion(value);
  }
}

Map<Object?, Object?>? _objectMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<Object?, Object?>();
  }
  return null;
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
  if (value is! List) {
    return const <String>[];
  }
  final result = <String>[];
  for (final item in value.take(maxEntries * 4)) {
    if (item is! String) {
      continue;
    }
    final normalized = trim ? item.trim() : item;
    if (!allowEmpty && normalized.isEmpty) {
      continue;
    }
    result.add(normalized);
    if (result.length >= maxEntries) {
      break;
    }
  }
  return List.unmodifiable(result);
}
