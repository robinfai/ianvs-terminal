enum TerminalZmodemRecoveryResolutionStatus {
  available,
  unavailable,
  requestFailed,
}

final class TerminalZmodemRecoveryResolution {
  const TerminalZmodemRecoveryResolution._(this.status, this.path);

  const TerminalZmodemRecoveryResolution.available(String path)
    : this._(TerminalZmodemRecoveryResolutionStatus.available, path);

  const TerminalZmodemRecoveryResolution.unavailable()
    : this._(TerminalZmodemRecoveryResolutionStatus.unavailable, null);

  const TerminalZmodemRecoveryResolution.requestFailed()
    : this._(TerminalZmodemRecoveryResolutionStatus.requestFailed, null);

  final TerminalZmodemRecoveryResolutionStatus status;
  final String? path;
}

enum TerminalZmodemRecoveryDisposition { success, unavailable, requestFailed }
