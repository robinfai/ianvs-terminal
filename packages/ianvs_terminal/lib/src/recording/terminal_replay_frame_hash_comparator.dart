import '../runtime/terminal_benchmarking.dart';
import '../terminal/terminal_models.dart';

typedef TerminalReplayFrameHasher =
    String Function(TerminalFrameDiff appliedFrame);

enum TerminalReplayFrameHashDivergence { hashMismatch, frameCountMismatch }

final class TerminalReplayFrameHashComparison {
  const TerminalReplayFrameHashComparison._({
    required this.divergence,
    required this.referenceFrameCount,
    required this.replayedFrameCount,
    required this.firstDivergenceIndex,
    required this.referenceHash,
    required this.replayedHash,
  });

  final TerminalReplayFrameHashDivergence? divergence;
  final int referenceFrameCount;
  final int replayedFrameCount;
  final int? firstDivergenceIndex;
  final String? referenceHash;
  final String? replayedHash;

  bool get matches => divergence == null;
}

/// Compares bounded reference and replay Frame traces after applying each Frame
/// to its own viewport state.
///
/// The default hasher is the deterministic benchmark viewport projection. It
/// covers visible row text, wrapping and viewport geometry, but is not a
/// cryptographic integrity check and does not include graphic asset bytes.
final class TerminalReplayFrameHashComparator {
  const TerminalReplayFrameHashComparator({
    this.hasher = terminalBenchmarkViewportHash,
  });

  static const int maxFrames = 4096;

  final TerminalReplayFrameHasher hasher;

  TerminalReplayFrameHashComparison compare({
    required Iterable<TerminalFrameDiff> referenceFrames,
    required Iterable<TerminalFrameDiff> replayedFrames,
  }) {
    final reference = _boundedFrames(referenceFrames, 'referenceFrames');
    final replayed = _boundedFrames(replayedFrames, 'replayedFrames');
    _requireInitialSnapshot(reference, 'referenceFrames');
    _requireInitialSnapshot(replayed, 'replayedFrames');

    var referenceState = TerminalViewportState.empty;
    var replayedState = TerminalViewportState.empty;
    final sharedFrameCount = reference.length < replayed.length
        ? reference.length
        : replayed.length;

    for (var index = 0; index < sharedFrameCount; index += 1) {
      referenceState = referenceState.applyFrame(reference[index]);
      replayedState = replayedState.applyFrame(replayed[index]);
      final referenceHash = hasher(referenceState.frame);
      final replayedHash = hasher(replayedState.frame);
      if (referenceHash != replayedHash) {
        return TerminalReplayFrameHashComparison._(
          divergence: TerminalReplayFrameHashDivergence.hashMismatch,
          referenceFrameCount: reference.length,
          replayedFrameCount: replayed.length,
          firstDivergenceIndex: index,
          referenceHash: referenceHash,
          replayedHash: replayedHash,
        );
      }
    }

    if (reference.length != replayed.length) {
      String? referenceHash;
      String? replayedHash;
      if (reference.length > sharedFrameCount) {
        referenceState = referenceState.applyFrame(reference[sharedFrameCount]);
        referenceHash = hasher(referenceState.frame);
      }
      if (replayed.length > sharedFrameCount) {
        replayedState = replayedState.applyFrame(replayed[sharedFrameCount]);
        replayedHash = hasher(replayedState.frame);
      }
      return TerminalReplayFrameHashComparison._(
        divergence: TerminalReplayFrameHashDivergence.frameCountMismatch,
        referenceFrameCount: reference.length,
        replayedFrameCount: replayed.length,
        firstDivergenceIndex: sharedFrameCount,
        referenceHash: referenceHash,
        replayedHash: replayedHash,
      );
    }

    return TerminalReplayFrameHashComparison._(
      divergence: null,
      referenceFrameCount: reference.length,
      replayedFrameCount: replayed.length,
      firstDivergenceIndex: null,
      referenceHash: null,
      replayedHash: null,
    );
  }

  List<TerminalFrameDiff> _boundedFrames(
    Iterable<TerminalFrameDiff> frames,
    String argumentName,
  ) {
    final bounded = <TerminalFrameDiff>[];
    for (final frame in frames) {
      if (bounded.length == maxFrames) {
        throw ArgumentError.value(
          bounded.length + 1,
          argumentName,
          'must contain no more than $maxFrames Frames',
        );
      }
      bounded.add(frame);
    }
    return List<TerminalFrameDiff>.unmodifiable(bounded);
  }

  void _requireInitialSnapshot(
    List<TerminalFrameDiff> frames,
    String argumentName,
  ) {
    if (frames.isNotEmpty &&
        frames.first.frameKind != TerminalFrameKind.snapshot) {
      throw ArgumentError.value(
        frames.first.frameKind,
        argumentName,
        'must begin with a Snapshot',
      );
    }
  }
}
