import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

void main() {
  group('TerminalReplayFrameHashComparator', () {
    test('matches equal applied Snapshot and Delta states', () {
      const comparator = TerminalReplayFrameHashComparator();
      final reference = <TerminalFrameDiff>[
        _snapshot(<String>['alpha', 'old']),
        _delta(row: 1, text: 'new'),
      ];
      final replayed = <TerminalFrameDiff>[
        _snapshot(<String>['alpha', 'old']),
        _delta(row: 1, text: 'new'),
      ];

      final comparison = comparator.compare(
        referenceFrames: reference,
        replayedFrames: replayed,
      );

      expect(comparison.matches, isTrue);
      expect(comparison.divergence, isNull);
      expect(comparison.firstDivergenceIndex, isNull);
      expect(comparison.referenceFrameCount, 2);
      expect(comparison.replayedFrameCount, 2);
    });

    test('compares applied state rather than raw Frame partitioning', () {
      const comparator = TerminalReplayFrameHashComparator();

      final comparison = comparator.compare(
        referenceFrames: <TerminalFrameDiff>[
          _snapshot(<String>['alpha', 'old']),
          _delta(row: 1, text: 'new'),
        ],
        replayedFrames: <TerminalFrameDiff>[
          _snapshot(<String>['alpha', 'old']),
          _snapshot(<String>['alpha', 'new']),
        ],
      );

      expect(comparison.matches, isTrue);
    });

    test('reports the first applied viewport hash mismatch', () {
      const comparator = TerminalReplayFrameHashComparator();

      final comparison = comparator.compare(
        referenceFrames: <TerminalFrameDiff>[
          _snapshot(<String>['alpha', 'old']),
          _delta(row: 1, text: 'expected'),
        ],
        replayedFrames: <TerminalFrameDiff>[
          _snapshot(<String>['alpha', 'old']),
          _delta(row: 1, text: 'actual'),
        ],
      );

      expect(comparison.matches, isFalse);
      expect(
        comparison.divergence,
        TerminalReplayFrameHashDivergence.hashMismatch,
      );
      expect(comparison.firstDivergenceIndex, 1);
      expect(comparison.referenceHash, isNotNull);
      expect(comparison.replayedHash, isNotNull);
      expect(comparison.referenceHash, isNot(comparison.replayedHash));
    });

    test('accepts a stricter applied-Frame hash projection', () {
      final comparator = TerminalReplayFrameHashComparator(
        hasher: (frame) =>
            '${terminalBenchmarkViewportHash(frame)}:${frame.cursor.col}',
      );

      final comparison = comparator.compare(
        referenceFrames: <TerminalFrameDiff>[
          _snapshot(<String>['alpha'], cursorCol: 0),
        ],
        replayedFrames: <TerminalFrameDiff>[
          _snapshot(<String>['alpha'], cursorCol: 1),
        ],
      );

      expect(
        comparison.divergence,
        TerminalReplayFrameHashDivergence.hashMismatch,
      );
      expect(comparison.firstDivergenceIndex, 0);
    });

    test('reports the first missing Frame and the available hash', () {
      const comparator = TerminalReplayFrameHashComparator();

      final comparison = comparator.compare(
        referenceFrames: <TerminalFrameDiff>[
          _snapshot(<String>['alpha', 'old']),
          _delta(row: 1, text: 'new'),
        ],
        replayedFrames: <TerminalFrameDiff>[
          _snapshot(<String>['alpha', 'old']),
        ],
      );

      expect(comparison.matches, isFalse);
      expect(
        comparison.divergence,
        TerminalReplayFrameHashDivergence.frameCountMismatch,
      );
      expect(comparison.firstDivergenceIndex, 1);
      expect(comparison.referenceHash, isNotNull);
      expect(comparison.replayedHash, isNull);
      expect(comparison.referenceFrameCount, 2);
      expect(comparison.replayedFrameCount, 1);
    });

    test('rejects Delta-first and over-limit traces', () {
      const comparator = TerminalReplayFrameHashComparator();

      expect(
        () => comparator.compare(
          referenceFrames: <TerminalFrameDiff>[_delta(row: 0, text: 'invalid')],
          replayedFrames: const <TerminalFrameDiff>[],
        ),
        throwsArgumentError,
      );

      final overLimit = List<TerminalFrameDiff>.filled(
        TerminalReplayFrameHashComparator.maxFrames + 1,
        _snapshot(<String>['bounded']),
      );
      expect(
        () => comparator.compare(
          referenceFrames: overLimit,
          replayedFrames: const <TerminalFrameDiff>[],
        ),
        throwsArgumentError,
      );
    });
  });
}

TerminalFrameDiff _snapshot(List<String> lines, {int cursorCol = 0}) {
  return TerminalFrameDiff(
    rows: <TerminalRow>[
      for (var index = 0; index < lines.length; index += 1)
        TerminalRow(index: index, text: lines[index]),
    ],
    cursor: TerminalCursor(row: 0, col: cursorCol, visible: true),
    viewportRows: lines.length,
    viewportCols: 80,
    dirtyRanges: <TerminalDirtyRange>[
      TerminalDirtyRange(start: 0, end: lines.length),
    ],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
  );
}

TerminalFrameDiff _delta({required int row, required String text}) {
  return TerminalFrameDiff(
    frameKind: TerminalFrameKind.delta,
    rows: <TerminalRow>[TerminalRow(index: row, text: text)],
    cursor: const TerminalCursor(row: 0, col: 0, visible: true),
    viewportRows: 2,
    viewportCols: 80,
    dirtyRanges: <TerminalDirtyRange>[
      TerminalDirtyRange(start: row, end: row + 1),
    ],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
  );
}
