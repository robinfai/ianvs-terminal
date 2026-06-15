import 'command_center_runtime.dart';
import 'command_lifecycle_degraded_state.dart';
import 'context_chip_models.dart';

class CommandCenterContextWiring {
  const CommandCenterContextWiring();

  ContextChipState chipsForSession(
    CommandCenterRuntimeState state, {
    required String sessionId,
    required String? shellIntegrationCwd,
    required String? profileId,
    required String? profileName,
    bool readOnly = false,
  }) {
    final cwd =
        _trimmedOrNull(state.cwdForSession(sessionId)) ??
        _trimmedOrNull(shellIntegrationCwd);
    return ContextChipState.fromContext(
      cwd: cwd,
      profileId: profileId,
      profileName: profileName,
      shellHookState: cwd == null
          ? const CommandCenterCapabilityState.limited(
              CommandCenterUnavailableReason.missingCwd,
            )
          : const CommandCenterCapabilityState.enabled(),
      readOnly: readOnly,
    );
  }
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
