import 'dart:typed_data';
import 'dart:ui' show Color, Size;

import 'package:app/features/shell/instant_replay_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

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

  TerminalFrameDiff frameWithVisuals({
    required String text,
    List<TerminalStyleRun> styleRuns = const <TerminalStyleRun>[],
    List<TerminalInlineImage> inlineImages = const <TerminalInlineImage>[],
    List<TerminalHyperlinkRange> hyperlinks = const <TerminalHyperlinkRange>[],
    List<TerminalSizedTextPlacement> sizedText =
        const <TerminalSizedTextPlacement>[],
  }) {
    return TerminalFrameDiff(
      rows: <TerminalRow>[
        TerminalRow(index: 0, text: text, styleRuns: styleRuns),
      ],
      cursor: const TerminalCursor(row: 0, col: 0, visible: true),
      viewportRows: 1,
      viewportCols: 80,
      dirtyRanges: const <TerminalDirtyRange>[
        TerminalDirtyRange(start: 0, end: 1),
      ],
      scrollbackOffset: 0,
      scrollbackMaxOffset: 0,
      inlineImages: inlineImages,
      hyperlinks: hyperlinks,
      sizedText: sizedText,
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

  test('production sampling checkpoints the accumulated latest state', () {
    var now = DateTime.utc(2026, 7, 24);
    var materializedFrames = 0;
    final store = InstantReplayStore(
      minimumCaptureInterval: const Duration(milliseconds: 100),
      now: () => now,
      onFrameMaterialized: () => materializedFrames += 1,
    );

    store.record('1', frameWithRows(['first']));
    now = now.add(const Duration(milliseconds: 20));
    store.record('1', frameWithRows(['second']));
    now = now.add(const Duration(milliseconds: 100));
    store.record('1', frameWithRows(['third']));

    expect(store.framesFor('1').map((frame) => frame.text), ['third', 'first']);
    expect(materializedFrames, 2);
  });

  test('one millisecond delta burst materializes only its first frame', () {
    var now = DateTime.utc(2026, 7, 24);
    var materializedFrames = 0;
    final store = InstantReplayStore(
      minimumCaptureInterval: const Duration(milliseconds: 100),
      now: () => now,
      onFrameMaterialized: () => materializedFrames += 1,
    );

    store.record('1', frameWithRows(['initial']));
    for (var index = 1; index <= 50; index += 1) {
      now = now.add(const Duration(milliseconds: 1));
      store.record(
        '1',
        frameWithRows(['delta $index'], frameKind: TerminalFrameKind.delta),
      );
    }

    expect(materializedFrames, 1);
    expect(store.framesFor('1'), hasLength(1));
  });

  test('forced checkpoint exposes latest state inside sampling window', () {
    var now = DateTime.utc(2026, 7, 24);
    var materializedFrames = 0;
    final store = InstantReplayStore(
      minimumCaptureInterval: const Duration(milliseconds: 100),
      now: () => now,
      onFrameMaterialized: () => materializedFrames += 1,
    );

    store.record('1', frameWithRows(['initial']));
    now = now.add(const Duration(milliseconds: 1));
    store.record(
      '1',
      frameWithRows(['latest'], frameKind: TerminalFrameKind.delta),
    );
    expect(store.framesForReplay('1').last.text, 'initial');

    store.checkpoint('1', frameWithRows(['latest']));

    expect(materializedFrames, 2);
    expect(store.framesForReplay('1').last.text, 'latest');
  });

  test('stable fingerprint ignores row delivery order without sorting', () {
    final store = InstantReplayStore();
    final first = frameWithRows(['first', 'second']);
    final reordered = TerminalFrameDiff(
      frameKind: TerminalFrameKind.snapshot,
      rows: first.rows.reversed.toList(growable: false),
      cursor: first.cursor,
      viewportRows: first.viewportRows,
      viewportCols: first.viewportCols,
      dirtyRanges: first.dirtyRanges,
      scrollbackOffset: first.scrollbackOffset,
      scrollbackMaxOffset: first.scrollbackMaxOffset,
    );

    store.record('1', first);
    store.record('1', reordered);

    expect(store.framesFor('1'), hasLength(1));
  });

  test('same text with different styles creates a visual checkpoint', () {
    final store = InstantReplayStore();

    store.record('1', frameWithVisuals(text: 'styled output'));
    store.record(
      '1',
      frameWithVisuals(
        text: 'styled output',
        styleRuns: const <TerminalStyleRun>[
          TerminalStyleRun(
            start: 0,
            end: 6,
            foreground: Color(0xFFFF0000),
            bold: true,
          ),
        ],
      ),
    );

    expect(store.framesFor('1'), hasLength(2));
  });

  test('same text with different inline image bytes is not folded', () {
    final store = InstantReplayStore();

    store.record(
      '1',
      frameWithVisuals(
        text: 'image',
        inlineImages: <TerminalInlineImage>[
          TerminalInlineImage(
            row: 0,
            col: 0,
            widthCells: 1,
            heightCells: 1,
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
      ),
    );
    store.record(
      '1',
      frameWithVisuals(
        text: 'image',
        inlineImages: <TerminalInlineImage>[
          TerminalInlineImage(
            row: 0,
            col: 0,
            widthCells: 1,
            heightCells: 1,
            bytes: Uint8List.fromList(<int>[1, 2, 4]),
          ),
        ],
      ),
    );

    expect(store.framesFor('1'), hasLength(2));
  });

  test('large inline image fingerprint is one identity operation', () {
    final observedLengths = <int>[];
    final store = InstantReplayStore(
      onInlineImageFingerprint: observedLengths.add,
    );
    const imageBytes = 4 * 1024 * 1024;

    store.record(
      '1',
      frameWithVisuals(
        text: 'large image',
        inlineImages: <TerminalInlineImage>[
          TerminalInlineImage(
            row: 0,
            col: 0,
            widthCells: 1,
            heightCells: 1,
            bytes: Uint8List(imageBytes),
          ),
        ],
      ),
    );

    expect(observedLengths, <int>[imageBytes]);
  });

  test('global byte budget evicts the oldest session', () {
    var now = DateTime.utc(2026, 7, 24);
    final store = InstantReplayStore(byteBudget: 3500, now: () => now);

    store.record('old', frameWithRows([List.filled(200, 'a').join()]));
    now = now.add(const Duration(seconds: 1));
    store.record('new', frameWithRows([List.filled(200, 'b').join()]));

    expect(store.estimatedRetainedBytes, lessThanOrEqualTo(3500));
    expect(store.retainedSessionCount, 1);
    expect(store.framesFor('old'), isEmpty);
    expect(store.framesFor('new'), hasLength(1));
  });

  test(
    'inline image payload and current state participate in global budget',
    () {
      var now = DateTime.utc(2026, 7, 24);
      const imageBytes = 1024 * 1024;
      final store = InstantReplayStore(
        byteBudget: imageBytes * 3 + 2500,
        now: () => now,
      );

      store.record('old', frameWithRows(['old session']));
      now = now.add(const Duration(seconds: 1));
      store.record(
        'image',
        frameWithVisuals(
          text: 'image session',
          inlineImages: <TerminalInlineImage>[
            TerminalInlineImage(
              row: 0,
              col: 0,
              widthCells: 1,
              heightCells: 1,
              bytes: Uint8List(imageBytes),
              altText: 'large inline image',
            ),
          ],
        ),
      );

      expect(store.estimatedRetainedBytes, lessThanOrEqualTo(store.byteBudget));
      expect(store.framesFor('old'), isEmpty);
      expect(store.framesFor('image'), hasLength(1));
      expect(
        store.estimatedRetainedBytes,
        greaterThanOrEqualTo(imageBytes * 3),
      );
    },
  );

  test('variable visual strings contribute to the retained byte estimate', () {
    final store = InstantReplayStore();
    store.record('plain', frameWithVisuals(text: 'same'));
    final plainBytes = store.estimatedRetainedBytes;

    store.clear('plain');
    final longUri =
        'https://example.test/${List<String>.filled(200, 'segment-').join()}';
    final longText = List<String>.filled(200, 'large label ').join();
    store.record(
      'rich',
      frameWithVisuals(
        text: 'same',
        hyperlinks: <TerminalHyperlinkRange>[
          TerminalHyperlinkRange(
            row: 0,
            startCol: 0,
            endCol: 4,
            uri: longUri,
            protocolId: 'osc8-id',
          ),
        ],
        sizedText: <TerminalSizedTextPlacement>[
          TerminalSizedTextPlacement(
            text: longText,
            row: 0,
            col: 0,
            widthCells: 4,
            heightCells: 1,
            sourceRowOffsetCells: 0,
            visibleHeightCells: 1,
            scale: 1,
            subscaleN: 0,
            subscaleD: 0,
            verticalAlign: 0,
            horizontalAlign: 0,
            naturalWidth: true,
          ),
        ],
      ),
    );

    expect(store.estimatedRetainedBytes, greaterThan(plainBytes + 10000));
  });

  test('semantic events retain a time boundary when visuals are unchanged', () {
    var now = DateTime.utc(2026, 7, 24);
    final store = InstantReplayStore(now: () => now);
    final stable = frameWithRows(['stable output']);

    store.record('1', stable);
    now = now.add(const Duration(milliseconds: 100));
    store.recordSemantic(
      '1',
      kind: TerminalRecordingSemanticKind.commandStarted,
      command: 'pwd',
    );
    now = now.add(const Duration(milliseconds: 100));
    store.checkpoint('1', stable);

    expect(store.framesForReplay('1'), hasLength(2));
    expect(store.semanticsForReplay('1'), hasLength(1));
  });

  test('retains semantic SSH and remote command events with replay frames', () {
    var now = DateTime.utc(2026, 7, 24, 1);
    final store = InstantReplayStore(now: () => now);

    store.record('1', frameWithRows(['connecting']));
    now = now.add(const Duration(milliseconds: 100));
    store.recordSemantic(
      '1',
      kind: TerminalRecordingSemanticKind.remoteSessionStarted,
      command: 'ssh prod-server',
    );
    now = now.add(const Duration(milliseconds: 100));
    store.recordSemantic(
      '1',
      kind: TerminalRecordingSemanticKind.commandStarted,
      command: 'ls -la',
      remote: true,
    );
    now = now.add(const Duration(milliseconds: 40));
    store.recordSemantic(
      '1',
      kind: TerminalRecordingSemanticKind.commandStarted,
      command: 'ls -la',
      cwd: '/srv/app',
      remote: true,
    );
    now = now.add(const Duration(milliseconds: 60));
    store.record('1', frameWithRows(['remote output']));

    final semantics = store.semanticsForReplay('1');

    expect(
      semantics.map((event) => event.kind),
      <TerminalRecordingSemanticKind>[
        TerminalRecordingSemanticKind.remoteSessionStarted,
        TerminalRecordingSemanticKind.commandStarted,
      ],
    );
    expect(semantics.last.command, 'ls -la');
    expect(semantics.last.cwd, '/srv/app');
    expect(semantics.last.remote, isTrue);
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
