import '../productivity/shell_command_block_controller.dart';
import '../productivity/shell_productivity_models.dart';
import 'command_block_models.dart';
import 'command_invocation_models.dart';
import 'command_lifecycle_degraded_state.dart';
import 'context_chip_models.dart';

class ShellCommandBlockCommandCenterAdapter {
  const ShellCommandBlockCommandCenterAdapter();

  CommandBlock? activeCompatibleBlockFor({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
    String? selectedBlockId,
  }) {
    final selected = compatibleBlockById(
      snapshot: snapshot,
      sessionId: sessionId,
      blockId: selectedBlockId,
    );
    if (selected != null) {
      return selected;
    }
    for (final block in snapshot.blocks.reversed) {
      if (block.isValid) {
        return compatibleBlockFor(sessionId: sessionId, block: block);
      }
    }
    return null;
  }

  CommandBlock? compatibleBlockById({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
    required String? blockId,
  }) {
    final targetId = blockId?.trim();
    if (targetId == null || targetId.isEmpty) {
      return null;
    }
    for (final block in snapshot.blocks) {
      if (block.id == targetId && block.isValid) {
        return compatibleBlockFor(sessionId: sessionId, block: block);
      }
    }
    return null;
  }

  CommandBlock? lastFailedCompatibleBlockFor({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
  }) {
    for (final block in snapshot.blocks.reversed) {
      if (block.isValid && block.status == ShellCommandBlockStatus.failed) {
        return compatibleBlockFor(sessionId: sessionId, block: block);
      }
    }
    return null;
  }

  List<CommandBlock> compatibleBlocksFor({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
  }) {
    return List<CommandBlock>.unmodifiable(
      snapshot.blocks
          .where((block) => block.isValid)
          .map(
            (block) => compatibleBlockFor(sessionId: sessionId, block: block),
          )
          .whereType<CommandBlock>(),
    );
  }

  ContextChipState contextChipsForSession({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
    required String? cwd,
    required String? profileId,
    required String? profileName,
    String? selectedBlockId,
    bool readOnly = false,
    bool shellIntegrationEnabled = true,
  }) {
    final trimmedCwd = _trimmedOrNull(cwd);
    final selectedBlock = compatibleBlockById(
      snapshot: snapshot,
      sessionId: sessionId,
      blockId: selectedBlockId,
    );
    return ContextChipState.fromContext(
      cwd: trimmedCwd,
      profileId: profileId,
      profileName: profileName,
      shellHookState: _shellHookState(
        cwd: trimmedCwd,
        shellIntegrationEnabled: shellIntegrationEnabled,
      ),
      readOnly: readOnly,
      lastFailedBlock: lastFailedCompatibleBlockFor(
        snapshot: snapshot,
        sessionId: sessionId,
      ),
      selectedBlock: selectedBlock,
    );
  }

  CommandBlock? compatibleBlockFor({
    required String sessionId,
    required ShellCommandBlock block,
  }) {
    if (!block.isValid) {
      return null;
    }
    final range = block.outputRange;
    return CommandBlock(
      id: block.id,
      sessionId: sessionId,
      command: block.command,
      cwd: block.cwd,
      startedAt: block.startedAt ?? _syntheticStartedAtFor(block),
      finishedAt: block.status == ShellCommandBlockStatus.running
          ? null
          : block.finishedAt ??
                block.startedAt ??
                _syntheticStartedAtFor(block),
      exitCode: block.exitCode,
      status: _statusFor(block.status),
      inputRange: CommandBlockRowRange(
        startRow: range.commandRow,
        endRowExclusive: range.commandRow + 1,
      ),
      outputRange: CommandBlockRowRange(
        startRow: range.outputStartRow,
        endRowExclusive: range.outputEndRow + 1,
      ),
    );
  }
}

CommandCenterCapabilityState _shellHookState({
  required String? cwd,
  required bool shellIntegrationEnabled,
}) {
  if (!shellIntegrationEnabled) {
    return const CommandCenterCapabilityState.unavailable(
      CommandCenterUnavailableReason.shellIntegrationDisabled,
    );
  }
  if (cwd == null) {
    return const CommandCenterCapabilityState.limited(
      CommandCenterUnavailableReason.missingCwd,
    );
  }
  return const CommandCenterCapabilityState.enabled();
}

CommandInvocationStatus _statusFor(ShellCommandBlockStatus status) {
  return switch (status) {
    ShellCommandBlockStatus.running => CommandInvocationStatus.running,
    ShellCommandBlockStatus.succeeded => CommandInvocationStatus.succeeded,
    ShellCommandBlockStatus.failed => CommandInvocationStatus.failed,
    ShellCommandBlockStatus.unknown => CommandInvocationStatus.unknown,
  };
}

DateTime _syntheticStartedAtFor(ShellCommandBlock block) {
  final row = block.startRow < 0 ? 0 : block.startRow;
  return DateTime.fromMicrosecondsSinceEpoch(row, isUtc: true);
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
