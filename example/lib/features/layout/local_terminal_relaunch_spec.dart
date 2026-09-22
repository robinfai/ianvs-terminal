const int currentTerminalRelaunchSpecVersion = 1;
const String terminalRelaunchSpecContract = 'ianvs-terminal-relaunch-spec-v1';

final class UnsupportedTerminalRelaunchSpecVersion implements Exception {
  const UnsupportedTerminalRelaunchSpecVersion(this.version);

  final int version;

  @override
  String toString() {
    return 'Unsupported terminal relaunch spec version: $version '
        '(current: $currentTerminalRelaunchSpecVersion)';
  }
}

/// The persisted profile reference and working directory for a fresh session.
///
/// The referenced profile supplies command, arguments and connection settings.
/// Runtime state and recording associations live outside this contract.
class TerminalRelaunchSpec {
  const TerminalRelaunchSpec({required this.profileId, this.cwd});

  final String profileId;
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

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
