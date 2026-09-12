import '../terminal/terminal.dart';

/// Stable capability IDs shared by session state and diagnostic exports.
/// A configured shell or an injection plan is not evidence of activation.
enum ShellIntegrationCapability {
  currentDirectory('current_directory', localHook: true),
  promptLifecycle('prompt_lifecycle', localHook: true),
  commandStart('command_start', localHook: true),
  commandText('command_text', localHook: true),
  commandFinish('command_finish', localHook: true),
  exitCode('exit_code', localHook: true),
  shellIdentity('shell_identity', localHook: true),
  hostname('hostname'),
  username('username'),
  integrationVersion('integration_version'),
  promptNavigation('prompt_navigation'),
  commandOutputRanges('command_output_ranges'),
  userVariables('user_variables');

  const ShellIntegrationCapability(this.id, {this.localHook = false});

  final String id;

  /// Whether the bundled zsh/bash/fish scripts emit this capability's data.
  /// This describes the scripts, never the current session's activation.
  final bool localHook;
}

enum ShellCapabilityStatus { pending, active, disabled, unavailable }

enum ShellCapabilityReason {
  awaitingEvidence,
  initializationChecked,
  initializationFailed,
  observed,
  disabledByProfile,
  unsupportedEmulation,
  sessionExited,
}

enum ShellCapabilityEvidence {
  bootstrapRegistration,
  dcsPrompt,
  dcsCommandStart,
  dcsCommandFinish,
  dcsPromptMark,
  shellContext,
  shellCommand,
  shellPromptMark,
  shellOutputZone,
  shellIntegrationVersion,
  shellUserVariable,
}

class ShellCapabilityActivation {
  const ShellCapabilityActivation({
    required this.status,
    required this.reason,
    this.evidence,
  });

  static const pending = ShellCapabilityActivation(
    status: ShellCapabilityStatus.pending,
    reason: ShellCapabilityReason.awaitingEvidence,
  );

  final ShellCapabilityStatus status;
  final ShellCapabilityReason reason;
  final ShellCapabilityEvidence? evidence;

  bool get isActive => status == ShellCapabilityStatus.active;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'reason': reason.name,
    if (evidence != null) 'evidence': evidence!.name,
  };
}

/// Immutable readiness and runtime evidence for one live shell session. Never
/// persist these in profiles or layouts: a newly created process must prove its own
/// capabilities. Activation records carry no command, path, host or user data.
class ShellIntegrationCapabilities {
  const ShellIntegrationCapabilities.pending()
    : _observations = const {},
      _policy = null;

  const ShellIntegrationCapabilities._(this._observations, this._policy);

  final Map<ShellIntegrationCapability, ShellCapabilityActivation>
  _observations;
  final ShellCapabilityActivation? _policy;

  ShellCapabilityActivation operator [](
    ShellIntegrationCapability capability,
  ) =>
      _policy ?? _observations[capability] ?? ShellCapabilityActivation.pending;

  Map<ShellIntegrationCapability, ShellCapabilityActivation> get entries =>
      Map.unmodifiable({
        for (final capability in ShellIntegrationCapability.values)
          capability: this[capability],
      });

  ShellIntegrationCapabilities withPolicy({
    required bool enabled,
    required bool supportedEmulation,
    bool exited = false,
  }) {
    final policy = !enabled
        ? const ShellCapabilityActivation(
            status: ShellCapabilityStatus.disabled,
            reason: ShellCapabilityReason.disabledByProfile,
          )
        : !supportedEmulation
        ? const ShellCapabilityActivation(
            status: ShellCapabilityStatus.unavailable,
            reason: ShellCapabilityReason.unsupportedEmulation,
          )
        : exited
        ? const ShellCapabilityActivation(
            status: ShellCapabilityStatus.unavailable,
            reason: ShellCapabilityReason.sessionExited,
          )
        : null;
    return ShellIntegrationCapabilities._(_observations, policy);
  }

  /// Apply checks from the current shell's completed bootstrap handshake.
  /// Bundled hook registration establishes readiness, not a runtime observation
  /// or the existence of command history, prompt coordinates or output ranges.
  ShellIntegrationCapabilities applyRegistration(Map<String, String> checks) {
    if (_policy != null) return this;
    final next = Map.of(_observations);
    for (final capability in ShellIntegrationCapability.values) {
      if (!capability.localHook ||
          this[capability].reason == ShellCapabilityReason.observed) {
        continue;
      }
      final check = checks[capability.id];
      if (check != 'registered' && check != 'unavailable') continue;
      next[capability] = ShellCapabilityActivation(
        status: check == 'registered'
            ? ShellCapabilityStatus.active
            : ShellCapabilityStatus.unavailable,
        reason: check == 'registered'
            ? ShellCapabilityReason.initializationChecked
            : ShellCapabilityReason.initializationFailed,
        evidence: ShellCapabilityEvidence.bootstrapRegistration,
      );
    }
    return ShellIntegrationCapabilities._(Map.unmodifiable(next), null);
  }

  /// Reduces actual typed events, not shell names, profile configuration or a
  /// historical non-null value. Unknown events and malformed fields prove
  /// nothing. [promptMarkRecorded] is supplied only after coordinate validation.
  ShellIntegrationCapabilities observe(
    TerminalSessionEvent event, {
    bool promptMarkRecorded = false,
  }) {
    if (_policy != null) return this;
    final found = <ShellIntegrationCapability, ShellCapabilityEvidence>{};
    void add(
      ShellIntegrationCapability capability,
      ShellCapabilityEvidence proof,
    ) {
      found[capability] = proof;
    }

    switch (event) {
      case TerminalSessionShellHookEvent():
        final proof = switch (event.hook) {
          'precmd' || 'precmd.pwd' => ShellCapabilityEvidence.dcsPrompt,
          'preexec' => ShellCapabilityEvidence.dcsCommandStart,
          'command_finished' => ShellCapabilityEvidence.dcsCommandFinish,
          _ => null,
        };
        if (proof == null) return this;
        if (event.hook == 'precmd') {
          add(ShellIntegrationCapability.promptLifecycle, proof);
        }
        if (event.hook == 'preexec') {
          add(ShellIntegrationCapability.commandStart, proof);
        }
        if (event.hook == 'command_finished') {
          add(ShellIntegrationCapability.commandFinish, proof);
          if (event.exitCode case final code? when code >= 0) {
            add(ShellIntegrationCapability.exitCode, proof);
          }
        }
        if (_hasText(event.command) &&
            (event.hook == 'preexec' || event.hook == 'command_finished')) {
          add(ShellIntegrationCapability.commandText, proof);
        }
        if (_hasText(event.cwd)) {
          add(ShellIntegrationCapability.currentDirectory, proof);
        }
        if (_hasText(event.shell)) {
          add(ShellIntegrationCapability.shellIdentity, proof);
        }
        if (_hasText(event.hostname)) {
          add(ShellIntegrationCapability.hostname, proof);
        }
        if (_hasText(event.username)) {
          add(ShellIntegrationCapability.username, proof);
        }
        if (promptMarkRecorded) {
          add(
            ShellIntegrationCapability.promptNavigation,
            ShellCapabilityEvidence.dcsPromptMark,
          );
        }
      case TerminalSessionShellContextEvent():
        const proof = ShellCapabilityEvidence.shellContext;
        if (_hasText(event.cwd)) {
          add(ShellIntegrationCapability.currentDirectory, proof);
        }
        if (_hasText(event.hostname)) {
          add(ShellIntegrationCapability.hostname, proof);
        }
        if (_hasText(event.username)) {
          add(ShellIntegrationCapability.username, proof);
        }
      case TerminalSessionShellCommandEvent():
        const proof = ShellCapabilityEvidence.shellCommand;
        final type = event.eventType;
        if (type == 'prompt_start' || type == 'prompt_end') {
          add(ShellIntegrationCapability.promptLifecycle, proof);
        }
        // OSC 133 B / command_start starts command INPUT. Only C /
        // command_executed confirms execution, equivalent to DCS preexec.
        if (type == 'command_executed') {
          add(ShellIntegrationCapability.commandStart, proof);
        }
        final completedOutput =
            type == 'zone_closed' && event.zoneType == 'output';
        if (type == 'command_finished' || completedOutput) {
          add(ShellIntegrationCapability.commandFinish, proof);
          if (event.exitCode case final code? when code >= 0) {
            add(ShellIntegrationCapability.exitCode, proof);
          }
        }
        if ((type == 'command_start' ||
                type == 'command_executed' ||
                type == 'command_finished' ||
                completedOutput) &&
            _hasText(event.command)) {
          add(ShellIntegrationCapability.commandText, proof);
        }
        if ((type == 'prompt_start' || type == 'mark') &&
            event.cursorLine != null &&
            event.cursorLine! >= 0) {
          add(
            ShellIntegrationCapability.promptNavigation,
            ShellCapabilityEvidence.shellPromptMark,
          );
        }
        if (completedOutput &&
            event.zoneId != null &&
            event.zoneId! >= 0 &&
            event.absRowStart != null &&
            event.absRowStart! >= 0 &&
            event.absRowEnd != null &&
            event.absRowEnd! >= event.absRowStart!) {
          add(
            ShellIntegrationCapability.commandOutputRanges,
            ShellCapabilityEvidence.shellOutputZone,
          );
        }
        if (type == 'integration_version') {
          if (_hasText(event.integrationVersion)) {
            add(
              ShellIntegrationCapability.integrationVersion,
              ShellCapabilityEvidence.shellIntegrationVersion,
            );
          }
          if (_hasText(event.shell)) {
            add(
              ShellIntegrationCapability.shellIdentity,
              ShellCapabilityEvidence.shellIntegrationVersion,
            );
          }
        }
      case TerminalSessionShellUserVarEvent():
        if (_hasText(event.name) &&
            event.name!.trim().startsWith('IANVS_') &&
            _hasText(event.value)) {
          add(
            ShellIntegrationCapability.userVariables,
            ShellCapabilityEvidence.shellUserVariable,
          );
        }
      default:
        return this;
    }

    found.removeWhere(
      (capability, _) =>
          this[capability].reason == ShellCapabilityReason.observed,
    );
    if (found.isEmpty) return this;
    return ShellIntegrationCapabilities._(
      Map.unmodifiable({
        ..._observations,
        for (final entry in found.entries)
          entry.key: ShellCapabilityActivation(
            status: ShellCapabilityStatus.active,
            reason: ShellCapabilityReason.observed,
            evidence: entry.value,
          ),
      }),
      null,
    );
  }

  Map<String, Object?> toJson() => {
    for (final capability in ShellIntegrationCapability.values)
      capability.id: this[capability].toJson(),
  };
}

bool _hasText(String? value) =>
    value != null &&
    value.trim().isNotEmpty &&
    !value.runes.any((rune) => rune == 0 || rune == 0x1b || rune == 0x7f);
