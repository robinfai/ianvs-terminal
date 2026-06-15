import '../shell/instant_replay_store.dart';
import 'command_block_models.dart';
import 'command_invocation_models.dart';

enum CommandReviewEntrypointAction { replayFromHere, openInReview, openDiff }

enum CommandReviewEntrypointIntentKind { none, replay, review, diff }

enum CommandReviewEntrypointDisabledReason {
  missingOutputRange,
  missingReplayFrame,
  diffUnavailable,
}

class CommandReviewSourceMetadata {
  const CommandReviewSourceMetadata({
    required this.blockId,
    required this.sessionId,
    required this.command,
    required this.startedAt,
    required this.status,
    required this.readOnly,
    this.paneId,
    this.cwd,
    this.finishedAt,
    this.exitCode,
    this.outputRange,
  });

  factory CommandReviewSourceMetadata.fromBlock(CommandBlock block) {
    return CommandReviewSourceMetadata(
      blockId: block.id,
      sessionId: block.sessionId,
      paneId: block.paneId,
      command: block.command,
      cwd: block.cwd,
      startedAt: block.startedAt,
      finishedAt: block.finishedAt,
      exitCode: block.exitCode,
      status: block.status,
      outputRange: block.outputRange,
      readOnly: true,
    );
  }

  final String blockId;
  final String sessionId;
  final String? paneId;
  final String command;
  final String? cwd;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final CommandInvocationStatus status;
  final CommandBlockRowRange? outputRange;
  final bool readOnly;

  Duration? get duration => finishedAt?.difference(startedAt);

  bool get isFailure => status == CommandInvocationStatus.failed;
}

class CommandReviewEntrypointIntent {
  const CommandReviewEntrypointIntent._({
    required this.kind,
    required this.source,
    this.targetFrame,
    this.replayFrames = const <InstantReplayFrame>[],
    this.targetRow,
  });

  const CommandReviewEntrypointIntent.none({
    required CommandReviewSourceMetadata source,
  }) : this._(kind: CommandReviewEntrypointIntentKind.none, source: source);

  const CommandReviewEntrypointIntent.replay({
    required CommandReviewSourceMetadata source,
    required InstantReplayFrame targetFrame,
    required List<InstantReplayFrame> replayFrames,
    required int targetRow,
  }) : this._(
         kind: CommandReviewEntrypointIntentKind.replay,
         source: source,
         targetFrame: targetFrame,
         replayFrames: replayFrames,
         targetRow: targetRow,
       );

  const CommandReviewEntrypointIntent.review({
    required CommandReviewSourceMetadata source,
    required InstantReplayFrame targetFrame,
    required List<InstantReplayFrame> replayFrames,
    required int targetRow,
  }) : this._(
         kind: CommandReviewEntrypointIntentKind.review,
         source: source,
         targetFrame: targetFrame,
         replayFrames: replayFrames,
         targetRow: targetRow,
       );

  const CommandReviewEntrypointIntent.diff({
    required CommandReviewSourceMetadata source,
    required InstantReplayFrame targetFrame,
    required List<InstantReplayFrame> replayFrames,
    required int targetRow,
  }) : this._(
         kind: CommandReviewEntrypointIntentKind.diff,
         source: source,
         targetFrame: targetFrame,
         replayFrames: replayFrames,
         targetRow: targetRow,
       );

  final CommandReviewEntrypointIntentKind kind;
  final CommandReviewSourceMetadata source;
  final InstantReplayFrame? targetFrame;
  final List<InstantReplayFrame> replayFrames;
  final int? targetRow;

  bool get writesToTerminal => false;
  bool get usesWritableInputController => false;
  bool get pausesLiveTerminal => false;
}

class CommandReviewEntrypointResult {
  const CommandReviewEntrypointResult._({
    required this.intent,
    this.disabledReason,
  });

  const CommandReviewEntrypointResult.enabled(
    CommandReviewEntrypointIntent intent,
  ) : this._(intent: intent);

  const CommandReviewEntrypointResult.disabled({
    required CommandReviewEntrypointIntent intent,
    required CommandReviewEntrypointDisabledReason reason,
  }) : this._(intent: intent, disabledReason: reason);

  final CommandReviewEntrypointIntent intent;
  final CommandReviewEntrypointDisabledReason? disabledReason;

  bool get enabled => disabledReason == null;
}

class CommandReviewEntrypointResolver {
  const CommandReviewEntrypointResolver({required InstantReplayStore store})
    : _store = store;

  final InstantReplayStore _store;

  CommandReviewEntrypointResult resolve(
    CommandReviewEntrypointAction action,
    CommandBlock block, {
    bool diffAvailable = false,
  }) {
    final source = CommandReviewSourceMetadata.fromBlock(block);
    final outputRange = block.outputRange;
    if (outputRange == null || outputRange.isEmpty) {
      return _disabled(
        source,
        CommandReviewEntrypointDisabledReason.missingOutputRange,
      );
    }

    if (action == CommandReviewEntrypointAction.openDiff && !diffAvailable) {
      return _disabled(
        source,
        CommandReviewEntrypointDisabledReason.diffUnavailable,
      );
    }

    final targetFrame = _store.frameForRows(
      block.sessionId,
      startRow: outputRange.startRow,
      endRowExclusive: outputRange.endRowExclusive,
    );
    if (targetFrame == null) {
      return _disabled(
        source,
        CommandReviewEntrypointDisabledReason.missingReplayFrame,
      );
    }

    final replayFrames = _store.framesForReplay(block.sessionId);
    final targetRow = outputRange.startRow;
    final intent = switch (action) {
      CommandReviewEntrypointAction.replayFromHere =>
        CommandReviewEntrypointIntent.replay(
          source: source,
          targetFrame: targetFrame,
          replayFrames: replayFrames,
          targetRow: targetRow,
        ),
      CommandReviewEntrypointAction.openInReview =>
        CommandReviewEntrypointIntent.review(
          source: source,
          targetFrame: targetFrame,
          replayFrames: replayFrames,
          targetRow: targetRow,
        ),
      CommandReviewEntrypointAction.openDiff =>
        CommandReviewEntrypointIntent.diff(
          source: source,
          targetFrame: targetFrame,
          replayFrames: replayFrames,
          targetRow: targetRow,
        ),
    };
    return CommandReviewEntrypointResult.enabled(intent);
  }

  CommandReviewEntrypointResult _disabled(
    CommandReviewSourceMetadata source,
    CommandReviewEntrypointDisabledReason reason,
  ) {
    return CommandReviewEntrypointResult.disabled(
      intent: CommandReviewEntrypointIntent.none(source: source),
      reason: reason,
    );
  }
}
