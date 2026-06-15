import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'package:app/features/shell/instant_replay_store.dart';

void main() {
  TerminalFrameDiff frameWithRows(
    List<String> rows, {
    TerminalFrameKind frameKind = TerminalFrameKind.snapshot,
    int? viewportRows,
    int viewportCols = 80,
  }) {
    return TerminalFrameDiff(
      frameKind: frameKind,
      rows: [
        for (var index = 0; index < rows.length; index += 1)
          TerminalRow(index: index, text: rows[index]),
      ],
      cursor: const TerminalCursor(row: 0, col: 0, visible: true),
      viewportRows: viewportRows ?? rows.length,
      viewportCols: viewportCols,
      dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
      scrollbackOffset: 0,
      scrollbackMaxOffset: 0,
    );
  }

  test('records terminal frames newest first and skips duplicates', () {
    final store = InstantReplayStore();

    store.record('1', frameWithRows(['first']));
    store.record('1', frameWithRows(['first']));
    store.record('1', frameWithRows(['second']));

    final frames = store.framesFor('1');

    expect(frames, hasLength(2));
    expect(frames.first.frame.rows.single.text, 'second');
    expect(frames.first.frame.viewportCols, 80);
    expect(frames.first.text, 'second');
    expect(frames.last.text, 'first');
  });

  test('exposes chronological replay frames oldest first', () {
    final store = InstantReplayStore();

    store.record('1', frameWithRows(['first']));
    store.record('1', frameWithRows(['second']));

    expect(store.framesForReplay('1').map((frame) => frame.text), [
      'first',
      'second',
    ]);
  });

  test('finds the newest frame that intersects a row range', () {
    final store = InstantReplayStore();

    store.record(
      '1',
      frameWithRows(['old prompt', 'old output'], viewportRows: 80),
    );
    store.record(
      '1',
      TerminalFrameDiff(
        frameKind: TerminalFrameKind.snapshot,
        rows: const [
          TerminalRow(index: 40, text: 'target command output'),
          TerminalRow(index: 41, text: 'stack trace'),
        ],
        cursor: const TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 80,
        viewportCols: 80,
        dirtyRanges: const [TerminalDirtyRange(start: 40, end: 42)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );

    final frame = store.frameForRows('1', startRow: 40, endRowExclusive: 48);

    expect(frame?.text, 'target command output\nstack trace');
    expect(
      store.frameForRows('1', startRow: 100, endRowExclusive: 110),
      isNull,
    );
  });

  test(
    'stores restored snapshots for delta frames without losing diff data',
    () {
      final store = InstantReplayStore();

      store.record('1', frameWithRows(['old prompt', 'stable output']));
      store.record(
        '1',
        frameWithRows(
          ['new prompt'],
          frameKind: TerminalFrameKind.delta,
          viewportRows: 2,
        ),
      );

      final latest = store.framesFor('1').first;

      expect(latest.frame.frameKind, TerminalFrameKind.delta);
      expect(latest.frame.rows, hasLength(1));
      expect(latest.snapshot.frameKind, TerminalFrameKind.snapshot);
      expect(latest.snapshot.rows.map((row) => row.text), [
        'new prompt',
        'stable output',
      ]);
      expect(latest.text, 'new prompt\nstable output');
    },
  );

  test(
    'retains blank terminal frames because clear-screen is visual state',
    () {
      final store = InstantReplayStore();

      store.record('1', frameWithRows(['visible output']));
      store.record('1', frameWithRows(['   ']));

      final frames = store.framesFor('1');

      expect(frames, hasLength(2));
      expect(frames.first.frame.rows.single.text, '   ');
      expect(frames.first.text, '');
      expect(frames.last.text, 'visible output');
    },
  );

  test('records replay size metadata with frames', () {
    final store = InstantReplayStore();
    const logicalSize = Size(1080, 648);
    const pixelSize = Size(2160, 1296);
    const windowSize = Size(1220, 820);

    store.record(
      '1',
      frameWithRows(['wide output'], viewportCols: 120),
      viewportLogicalSize: logicalSize,
      viewportPixelSize: pixelSize,
      devicePixelRatio: 2,
      windowContentSize: windowSize,
    );

    final frame = store.framesFor('1').single;

    expect(frame.frame.viewportCols, 120);
    expect(frame.viewportLogicalSize, logicalSize);
    expect(frame.viewportPixelSize, pixelSize);
    expect(frame.devicePixelRatio, 2);
    expect(frame.windowContentSize, windowSize);
  });

  test('updates duplicate frame metadata without adding another frame', () {
    final store = InstantReplayStore();
    const windowSize = Size(900, 600);

    store.record('1', frameWithRows(['same output']));
    store.record(
      '1',
      frameWithRows(['same output']),
      windowContentSize: windowSize,
    );

    final frames = store.framesFor('1');

    expect(frames, hasLength(1));
    expect(frames.single.text, 'same output');
    expect(frames.single.windowContentSize, windowSize);
  });

  test('enriches matching session frames with later window metadata', () {
    final store = InstantReplayStore();
    const viewportSize = Size(900, 600);
    const windowSize = Size(940, 660);

    store.record(
      '1',
      frameWithRows(['older output']),
      viewportLogicalSize: viewportSize,
    );
    store.record(
      '1',
      frameWithRows(['latest output']),
      viewportLogicalSize: viewportSize,
    );
    store.enrichSessionMetadata(
      '1',
      viewportLogicalSize: viewportSize,
      windowFrameSize: windowSize,
    );

    final frames = store.framesFor('1');

    expect(frames, hasLength(2));
    expect(frames.first.windowFrameSize, windowSize);
    expect(frames.last.windowFrameSize, windowSize);
  });

  test('does not enrich frames captured at a different viewport size', () {
    final store = InstantReplayStore();
    const oldViewportSize = Size(720, 420);
    const currentViewportSize = Size(900, 600);
    const windowSize = Size(940, 660);

    store.record(
      '1',
      frameWithRows(['old size']),
      viewportLogicalSize: oldViewportSize,
    );
    store.enrichSessionMetadata(
      '1',
      viewportLogicalSize: currentViewportSize,
      windowFrameSize: windowSize,
    );

    expect(store.framesFor('1').single.windowFrameSize, isNull);
  });

  test('skips invalid frames without usable viewport dimensions', () {
    final store = InstantReplayStore();

    store.record('1', TerminalFrameDiff.empty);

    expect(store.framesFor('1'), isEmpty);
  });

  test('limits frames per session', () {
    final store = InstantReplayStore(frameLimit: 2);

    store.record('1', frameWithRows(['one']));
    store.record('1', frameWithRows(['two']));
    store.record('1', frameWithRows(['three']));

    expect(store.framesFor('1').map((frame) => frame.text), ['three', 'two']);
  });

  test('non-positive frame limits disable retention without throwing', () {
    final zeroLimitStore = InstantReplayStore(frameLimit: 0);
    final negativeLimitStore = InstantReplayStore(frameLimit: -1);

    zeroLimitStore.record('1', frameWithRows(['one']));
    negativeLimitStore.record('1', frameWithRows(['one']));

    expect(zeroLimitStore.framesFor('1'), isEmpty);
    expect(negativeLimitStore.framesFor('1'), isEmpty);
  });

  test('default v1 retention keeps the latest sixty text frames', () {
    final store = InstantReplayStore();

    for (var index = 0; index < 61; index += 1) {
      store.record('1', frameWithRows(['frame $index']));
    }

    final frames = store.framesFor('1');
    expect(frames, hasLength(60));
    expect(frames.first.text, 'frame 60');
    expect(frames.last.text, 'frame 1');
  });

  test('clear removes only the requested session', () {
    final store = InstantReplayStore();

    store.record('1', frameWithRows(['one']));
    store.record('2', frameWithRows(['two']));
    store.clear('1');

    expect(store.framesFor('1'), isEmpty);
    expect(store.framesFor('2').single.text, 'two');
  });
}
