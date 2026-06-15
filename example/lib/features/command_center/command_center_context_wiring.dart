import 'command_block_models.dart';
import 'command_center_runtime.dart';
import 'command_invocation_models.dart';
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
    CommandBlockRangeState? blockRangeState,
    String? selectedBlockId,
  }) {
    final cwd =
        _trimmedOrNull(state.cwdForSession(sessionId)) ??
        _trimmedOrNull(shellIntegrationCwd);
    final scope = CommandBlockScope(sessionId);
    final scopedBlocks =
        blockRangeState?.blocksForScope(scope) ?? const <CommandBlock>[];
    final selectedBlock = selectedBlockId == null
        ? null
        : blockRangeState?.blockByInvocationId(selectedBlockId);
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
      lastFailedBlock: _lastFailedBlock(scopedBlocks),
      selectedBlock: selectedBlock?.scope == scope ? selectedBlock : null,
    );
  }
}

CommandBlock? _lastFailedBlock(List<CommandBlock> blocks) {
  for (final block in blocks.reversed) {
    if (block.status == CommandInvocationStatus.failed) {
      return block;
    }
  }
  return null;
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
