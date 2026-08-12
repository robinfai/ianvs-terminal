import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/proto/frame_diff.pb.dart' as frame_pb;
import 'package:ianvs_terminal/src/runtime/terminal_frame_transport_coordinator.dart';

void main() {
  test(
    'terminal viewport controller normalizes delta fallback state as a snapshot',
    () {
      final controller = TerminalViewportController();

      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [TerminalRow(index: 1, text: 'beta')],
          cursor: TerminalCursor(row: 1, col: 4, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 1, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          viewportStartRow: 12,
          viewportRowShift: -1,
        ),
      );

      final frame = controller.frame;
      expect(frame.frameKind, TerminalFrameKind.snapshot);
      expect(frame.viewportRowShift, 0);
      expect(
        frame.dirtyRanges
            .map((range) => (range.start, range.end))
            .toList(growable: false),
        <(int, int)>[(0, 2)],
      );
      expect(
        frame.rows.map((row) => (row.index, row.text)).toList(growable: false),
        <(int, String)>[(0, ''), (1, 'beta')],
      );
    },
  );

  test(
    'terminal viewport controller treats global bottom as frame-authoritative',
    () {
      final controller = TerminalViewportController();
      addTearDown(controller.dispose);

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'prompt')],
          cursor: TerminalCursor(row: 0, col: 6, visible: true),
          viewportRows: 1,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 100,
          globalBottomRow: 100,
        ),
      );
      expect(controller.frame.globalBottomRow, 100);

      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [],
          cursor: TerminalCursor(row: 0, col: 6, visible: true),
          viewportRows: 1,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 100,
        ),
      );
      expect(controller.frame.globalBottomRow, isNull);

      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 1,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          globalBottomRow: 0,
        ),
      );
      expect(controller.frame.globalBottomRow, 0);
    },
  );

  test(
    'terminal viewport controller treats incoming delta rows as dirty ranges',
    () {
      final controller = TerminalViewportController();

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [
            TerminalRow(index: 0, text: 'prompt'),
            TerminalRow(index: 1, text: 'old link'),
          ],
          cursor: TerminalCursor(row: 0, col: 6, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          hyperlinks: [
            TerminalHyperlinkRange(
              row: 1,
              startCol: 0,
              endCol: 8,
              uri: 'https://stale.example',
            ),
          ],
        ),
      );
      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [TerminalRow(index: 1, text: 'fresh prompt')],
          cursor: TerminalCursor(row: 1, col: 12, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      final frame = controller.frame;
      expect(frame.rows.map((row) => row.text).toList(), <String>[
        'prompt',
        'fresh prompt',
      ]);
      expect(
        frame.dirtyRanges
            .map((range) => (range.start, range.end))
            .toList(growable: false),
        <(int, int)>[(1, 2)],
      );
      expect(frame.hyperlinks, isEmpty);
    },
  );

  test('cursor-only deltas apply and clear protocol overrides', () {
    final controller = TerminalViewportController();
    addTearDown(controller.dispose);
    controller.updateFrame(
      const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'prompt')],
        cursor: TerminalCursor(row: 0, col: 6, visible: true),
        viewportRows: 1,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );

    controller.updateFrame(
      const TerminalFrameDiff(
        frameKind: TerminalFrameKind.delta,
        rows: [],
        cursor: TerminalCursor(
          row: 0,
          col: 6,
          visible: true,
          highlightLine: true,
          shape: TerminalCursorShape.beam,
          blink: false,
        ),
        viewportRows: 1,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        cursorGuideColor: Color(0xFF2A80D7),
      ),
    );
    expect(controller.frame.cursor.highlightLine, isTrue);
    expect(controller.frame.cursorGuideColor, const Color(0xFF2A80D7));
    expect(controller.frame.cursor.shape, TerminalCursorShape.beam);
    expect(controller.frame.cursor.blink, isFalse);
    expect(controller.frame.rows.single.text, 'prompt');

    controller.updateFrame(
      const TerminalFrameDiff(
        frameKind: TerminalFrameKind.delta,
        rows: [],
        cursor: TerminalCursor(row: 0, col: 6, visible: true),
        viewportRows: 1,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );
    expect(controller.frame.cursor.shape, isNull);
    expect(controller.frame.cursor.blink, isNull);
    expect(controller.frame.cursor.highlightLine, isFalse);
    expect(controller.frame.cursorGuideColor, const Color(0xFF2A80D7));
  });

  test(
    'terminal viewport controller treats graphics as frame-authoritative',
    () {
      final controller = TerminalViewportController();

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'image')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          graphics: [
            TerminalGraphicPlacement(
              renderId: 101,
              placementId: 101,
              assetKey: TerminalGraphicAssetKey(id: 7, version: 3),
              protocol: 'kitty',
              row: 0,
              col: 2,
              widthPx: 8,
              heightPx: 4,
              widthCells: 4,
              heightCells: 2,
            ),
          ],
        ),
      );
      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [TerminalRow(index: 0, text: 'image')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          viewportRowShift: -1,
          graphics: [],
        ),
      );

      expect(controller.frame.graphics, isEmpty);
    },
  );

  test(
    'terminal viewport controller tracks graphics and asset revisions independently',
    () {
      final controller = TerminalViewportController();
      const assetV1 = TerminalGraphicAssetKey(id: 7, version: 1);
      const assetV2 = TerminalGraphicAssetKey(id: 7, version: 2);
      const baseGraphic = TerminalGraphicPlacement(
        renderId: 101,
        placementId: 101,
        assetKey: assetV1,
        protocol: 'kitty',
        row: 0,
        col: 1,
        widthPx: 8,
        heightPx: 4,
        widthCells: 4,
        heightCells: 2,
      );

      TerminalFrameDiff frame({
        TerminalFrameKind kind = TerminalFrameKind.snapshot,
        String text = 'image',
        int cursorCol = 0,
        List<TerminalGraphicPlacement> graphics = const [],
      }) {
        return TerminalFrameDiff(
          frameKind: kind,
          rows: [TerminalRow(index: 0, text: text)],
          cursor: TerminalCursor(row: 0, col: cursorCol, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          graphics: graphics,
        );
      }

      expect(controller.graphicsRevision, 0);
      expect(controller.graphicsAssetRevision, 0);
      expect(controller.graphicsAssetKeys, isEmpty);

      controller.applySnapshot(frame(graphics: const [baseGraphic]));
      expect(controller.graphicsRevision, 1);
      expect(controller.graphicsAssetRevision, 1);
      expect(controller.graphicsAssetKeys, {assetV1});

      controller.applyDelta(
        frame(
          kind: TerminalFrameKind.delta,
          text: 'updated image',
          cursorCol: 2,
          graphics: const [baseGraphic],
        ),
      );
      expect(controller.graphicsRevision, 1);
      expect(controller.graphicsAssetRevision, 1);

      const movedGraphic = TerminalGraphicPlacement(
        renderId: 101,
        placementId: 101,
        assetKey: assetV1,
        protocol: 'kitty',
        row: 0,
        col: 2,
        widthPx: 8,
        heightPx: 4,
        widthCells: 4,
        heightCells: 2,
      );
      controller.applyDelta(
        frame(kind: TerminalFrameKind.delta, graphics: const [movedGraphic]),
      );
      expect(controller.graphicsRevision, 2);
      expect(controller.graphicsAssetRevision, 1);

      const versionedGraphic = TerminalGraphicPlacement(
        renderId: 101,
        placementId: 101,
        assetKey: assetV2,
        protocol: 'kitty',
        row: 0,
        col: 2,
        widthPx: 8,
        heightPx: 4,
        widthCells: 4,
        heightCells: 2,
      );
      controller.applyDelta(
        frame(
          kind: TerminalFrameKind.delta,
          graphics: const [versionedGraphic],
        ),
      );
      expect(controller.graphicsRevision, 3);
      expect(controller.graphicsAssetRevision, 2);
      expect(controller.graphicsAssetKeys, {assetV2});

      const duplicateGraphic = TerminalGraphicPlacement(
        renderId: 102,
        placementId: 102,
        assetKey: assetV2,
        protocol: 'kitty',
        row: 0,
        col: 4,
        widthPx: 8,
        heightPx: 4,
        widthCells: 4,
        heightCells: 2,
      );
      controller.applyDelta(
        frame(
          kind: TerminalFrameKind.delta,
          graphics: const [versionedGraphic, duplicateGraphic],
        ),
      );
      expect(controller.graphicsRevision, 4);
      expect(controller.graphicsAssetRevision, 2);
      expect(controller.graphicsAssetKeys, {assetV2});

      controller.applyDelta(frame(kind: TerminalFrameKind.delta));
      expect(controller.graphicsRevision, 5);
      expect(controller.graphicsAssetRevision, 3);
      expect(controller.graphicsAssetKeys, isEmpty);
    },
  );

  test(
    'terminal viewport controller rejects external graphics mutation without revision drift',
    () {
      const assetKey = TerminalGraphicAssetKey(id: 7, version: 1);
      final snapshot = TerminalFrameDiff.fromJson(const <String, Object?>{
        'rows': [
          {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
        ],
        'cursor': {'row': 0, 'col': 0, 'visible': false},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'graphics': [
          {
            'render_id': 101,
            'placement_id': 101,
            'asset_id': 7,
            'asset_version': 1,
            'protocol': 'kitty',
            'row': 0,
            'col': 1,
            'width_px': 8,
            'height_px': 4,
            'width_cells': 4,
            'height_cells': 2,
          },
        ],
      });
      final controller = TerminalViewportController();
      addTearDown(controller.dispose);

      controller.applySnapshot(snapshot);
      expect(controller.graphicsRevision, 1);
      expect(controller.graphicsAssetRevision, 1);
      expect(controller.graphicsAssetKeys, {assetKey});

      Object? parsedMutationError;
      Object? publishedMutationError;
      try {
        snapshot.graphics.clear();
      } on Object catch (error) {
        parsedMutationError = error;
      }
      try {
        controller.frame.graphics.clear();
      } on Object catch (error) {
        publishedMutationError = error;
      }

      controller.applyDelta(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [TerminalRow(index: 0, text: 'image')],
          cursor: TerminalCursor(row: 0, col: 0, visible: false),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(controller.graphicsRevision, 2);
      expect(controller.graphicsAssetRevision, 2);
      expect(controller.graphicsAssetKeys, isEmpty);
      expect(parsedMutationError, isA<UnsupportedError>());
      expect(publishedMutationError, isA<UnsupportedError>());
      expect(controller.frame.graphics.clear, throwsUnsupportedError);
    },
  );

  test('terminal graphic placement equality covers every render field', () {
    TerminalGraphicPlacement placement({
      int renderId = 11,
      int placementId = 12,
      int assetId = 7,
      int assetVersion = 1,
      String protocol = 'kitty',
      int row = 0,
      int col = 2,
      int widthPx = 8,
      int heightPx = 6,
      int widthCells = 4,
      int heightCells = 2,
      int sourceXOffsetPx = 1,
      int visibleWidthPx = 6,
      int sourceYOffsetPx = 1,
      int visibleHeightPx = 4,
      int zIndex = 0,
      int xOffsetPx = 0,
      int yOffsetPx = 0,
      bool preserveAspectRatio = true,
    }) {
      return TerminalGraphicPlacement(
        renderId: renderId,
        placementId: placementId,
        assetKey: TerminalGraphicAssetKey(id: assetId, version: assetVersion),
        protocol: protocol,
        row: row,
        col: col,
        widthPx: widthPx,
        heightPx: heightPx,
        widthCells: widthCells,
        heightCells: heightCells,
        sourceXOffsetPx: sourceXOffsetPx,
        visibleWidthPx: visibleWidthPx,
        sourceYOffsetPx: sourceYOffsetPx,
        visibleHeightPx: visibleHeightPx,
        zIndex: zIndex,
        xOffsetPx: xOffsetPx,
        yOffsetPx: yOffsetPx,
        preserveAspectRatio: preserveAspectRatio,
      );
    }

    TerminalFrameDiff frame(TerminalGraphicPlacement graphic) {
      return TerminalFrameDiff(
        rows: const [TerminalRow(index: 0, text: 'image')],
        cursor: const TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 3,
        viewportCols: 80,
        dirtyRanges: const [TerminalDirtyRange(start: 0, end: 3)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        graphics: [graphic],
      );
    }

    final base = placement();
    final equal = placement();
    final variants = <(String, TerminalGraphicPlacement)>[
      ('renderId', placement(renderId: 13)),
      ('placementId', placement(placementId: 13)),
      ('assetKey.id', placement(assetId: 8)),
      ('assetKey.version', placement(assetVersion: 2)),
      ('protocol', placement(protocol: 'sixel')),
      ('row', placement(row: 1)),
      ('col', placement(col: 3)),
      ('widthPx', placement(widthPx: 9)),
      ('heightPx', placement(heightPx: 7)),
      ('widthCells', placement(widthCells: 5)),
      ('heightCells', placement(heightCells: 3)),
      ('sourceXOffsetPx', placement(sourceXOffsetPx: 2)),
      ('visibleWidthPx', placement(visibleWidthPx: 5)),
      ('sourceYOffsetPx', placement(sourceYOffsetPx: 2)),
      ('visibleHeightPx', placement(visibleHeightPx: 3)),
      ('zIndex', placement(zIndex: 1)),
      ('xOffsetPx', placement(xOffsetPx: 1)),
      ('yOffsetPx', placement(yOffsetPx: 1)),
      ('preserveAspectRatio', placement(preserveAspectRatio: false)),
    ];

    expect(equal, base);
    expect(equal.hashCode, base.hashCode);
    for (final (field, variant) in variants) {
      expect(variant, isNot(base), reason: field);
      final controller = TerminalViewportController();
      try {
        controller.applySnapshot(frame(base));
        expect(controller.graphicsRevision, 1, reason: field);
        controller.applyDelta(frame(variant));
        expect(controller.graphicsRevision, 2, reason: field);
      } finally {
        controller.dispose();
      }
    }
  });

  test('terminal viewport controller timestamps changed rows', () {
    final firstModifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 3);
    final secondModifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 9);
    final timestamps = <DateTime>[firstModifiedAt, secondModifiedAt];
    final controller = TerminalViewportController(
      now: () => timestamps.removeAt(0),
    );

    controller.updateFrame(
      const TerminalFrameDiff(
        rows: [
          TerminalRow(index: 0, text: 'alpha'),
          TerminalRow(index: 1, text: 'beta'),
        ],
        cursor: TerminalCursor(row: 1, col: 4, visible: true),
        viewportRows: 2,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );
    controller.updateFrame(
      const TerminalFrameDiff(
        frameKind: TerminalFrameKind.delta,
        rows: [TerminalRow(index: 1, text: 'beta*')],
        cursor: TerminalCursor(row: 1, col: 5, visible: true),
        viewportRows: 2,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );

    expect(controller.frame.rows[0].modifiedAt, firstModifiedAt);
    expect(controller.frame.rows[1].modifiedAt, secondModifiedAt);
  });

  test(
    'terminal viewport controller reuses unchanged rows across sparse deltas',
    () {
      final modifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 3);
      final row0 = TerminalRow(index: 0, text: 'alpha', modifiedAt: modifiedAt);
      final row1 = TerminalRow(index: 1, text: 'beta', modifiedAt: modifiedAt);
      final row2 = TerminalRow(index: 2, text: 'gamma', modifiedAt: modifiedAt);
      final incomingRow = TerminalRow(
        index: 1,
        text: 'beta*',
        modifiedAt: modifiedAt.add(const Duration(seconds: 1)),
      );
      final controller = TerminalViewportController();

      controller.updateFrame(
        TerminalFrameDiff(
          rows: [row0, row1, row2],
          cursor: const TerminalCursor(row: 1, col: 4, visible: true),
          viewportRows: 3,
          viewportCols: 80,
          dirtyRanges: const [TerminalDirtyRange(start: 0, end: 3)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      controller.updateFrame(
        TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [incomingRow],
          cursor: const TerminalCursor(row: 1, col: 5, visible: true),
          viewportRows: 3,
          viewportCols: 80,
          dirtyRanges: const [TerminalDirtyRange(start: 1, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      final rows = controller.frame.rows;
      expect(rows[0], same(row0));
      expect(rows[1], same(incomingRow));
      expect(rows[2], same(row2));
    },
  );

  test(
    'terminal viewport controller preserves timestamps for repeated spinner frames',
    () {
      final firstModifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 3);
      final repeatedModifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 4);
      final styledModifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 5);
      final timestamps = <DateTime>[
        firstModifiedAt,
        repeatedModifiedAt,
        styledModifiedAt,
      ];
      final controller = TerminalViewportController(
        now: () => timestamps.removeAt(0),
      );

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: r'\ building')],
          cursor: TerminalCursor(row: 0, col: 10, visible: true),
          viewportRows: 1,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [TerminalRow(index: 0, text: r'\ building')],
          cursor: TerminalCursor(row: 0, col: 10, visible: true),
          viewportRows: 1,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(controller.frame.rows.single.modifiedAt, firstModifiedAt);

      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [
            TerminalRow(
              index: 0,
              text: r'\ building',
              styleRuns: [TerminalStyleRun(start: 0, end: 10, bold: true)],
            ),
          ],
          cursor: TerminalCursor(row: 0, col: 10, visible: true),
          viewportRows: 1,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(controller.frame.rows.single.modifiedAt, styledModifiedAt);
    },
  );

  test(
    'terminal viewport controller leaves whitespace-only rows untimestamped',
    () {
      final modifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 3);
      final controller = TerminalViewportController(now: () => modifiedAt);

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [
            TerminalRow(index: 0, text: '        '),
            TerminalRow(index: 1, text: 'alpha'),
          ],
          cursor: TerminalCursor(row: 1, col: 5, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(controller.frame.rows[0].modifiedAt, isNull);
      expect(controller.frame.rows[1].modifiedAt, modifiedAt);
    },
  );

  test('terminal frame modes parse alternate screen hints', () {
    final modes = TerminalFrameModes.fromJson(const <String, Object?>{
      'alternate_screen': true,
      'kitty_keyboard_flags': 5,
      'synchronized_output': true,
      'mime_paste': true,
    });
    final invalid = TerminalFrameModes.fromJson(const <String, Object?>{
      'kitty_keyboard_flags': -1,
    });

    expect(modes.alternateScreen, isTrue);
    expect(modes.kittyKeyboardFlags, 5);
    expect(modes.synchronizedOutput, isTrue);
    expect(modes.mimePaste, isTrue);
    expect(invalid.kittyKeyboardFlags, 0);
  });

  test(
    'terminal viewport controller applies synchronized output mode deltas',
    () {
      final controller = TerminalViewportController();

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'sync start')],
          cursor: TerminalCursor(row: 0, col: 10, visible: true),
          viewportRows: 1,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes(synchronizedOutput: true),
        ),
      );
      expect(controller.frame.modes.synchronizedOutput, isTrue);

      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [TerminalRow(index: 0, text: 'sync final')],
          cursor: TerminalCursor(row: 0, col: 10, visible: true),
          viewportRows: 1,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes.empty,
        ),
      );

      expect(controller.frame.rows.single.text, 'sync final');
      expect(controller.frame.modes.synchronizedOutput, isFalse);
    },
  );

  test('terminal frame modes normalize mouse tokens', () {
    final modes = TerminalFrameModes.fromJson(const <String, Object?>{
      'mouse_mode': ' Any_Event ',
      'mouse_encoding': ' SGR ',
    });
    final x10 = TerminalFrameModes.fromJson(const <String, Object?>{
      'mouse_mode': ' X10 ',
    });
    final pixels = TerminalFrameModes.fromJson(const <String, Object?>{
      'mouse_encoding': ' SGR-Pixels ',
    });
    final invalid = TerminalFrameModes.fromJson(const <String, Object?>{
      'mouse_mode': 'hover',
      'mouse_encoding': 'kitty',
    });

    expect(modes.mouseMode, 'any_event');
    expect(modes.mouseEncoding, 'sgr');
    expect(x10.mouseMode, 'x10');
    expect(pixels.mouseEncoding, 'sgr_pixels');
    expect(invalid.mouseMode, 'off');
    expect(invalid.mouseEncoding, 'default');
  });

  test('terminal frames parse row timestamp metadata', () {
    final modifiedAt = DateTime.parse('2026-05-13T08:09:10Z');
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {
          'index': 0,
          'text': 'timestamped',
          'modified_at': ' 2026-05-13T08:09:10Z ',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows.single.modifiedAt, modifiedAt);
  });

  test('terminal frames ignore invalid numeric row timestamps', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'non-finite', 'modified_at': double.infinity},
        {'index': 1, 'text': 'too-large', 'modified_at': 1e100},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 4,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 2},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows.map((row) => row.modifiedAt), everyElement(isNull));
  });

  test('terminal pointer shapes decode only canonical wire names', () {
    for (final shape in TerminalPointerShape.values) {
      final frame = TerminalFrameDiff.fromJson(<String, Object?>{
        'rows': const <Object?>[],
        'cursor': const <String, Object?>{'row': 0, 'col': 0, 'visible': false},
        'viewport_rows': 1,
        'viewport_cols': 1,
        'dirty_ranges': const <Object?>[],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'pointer_shape': shape.wireName,
      });
      expect(frame.pointerShape, shape);
    }

    final invalid = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': <Object?>[],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': false},
      'viewport_rows': 1,
      'viewport_cols': 1,
      'dirty_ranges': <Object?>[],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'pointer_shape': 'xterm',
    });
    expect(invalid.pointerShape, isNull);
  });

  test('terminal sized text validates bounds and fractional metadata', () {
    final oversizedUtf8 = List<String>.filled(1025, '😀').join();
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'rows': <Object?>[],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': false},
      'viewport_rows': 4,
      'viewport_cols': 20,
      'dirty_ranges': <Object?>[],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'sized_text': <Object?>[
        <String, Object?>{
          'text': 'AB',
          'row': 0,
          'col': 1,
          'width_cells': 4,
          'height_cells': 2,
          'source_row_offset_cells': 0,
          'visible_height_cells': 2,
          'scale': 2,
          'subscale_n': 1,
          'subscale_d': 2,
          'vertical_align': 2,
          'horizontal_align': 1,
          'natural_width': false,
        },
        <String, Object?>{
          'text': 'too-wide',
          'row': 0,
          'col': 0,
          'width_cells': 50,
          'height_cells': 1,
          'source_row_offset_cells': 0,
          'visible_height_cells': 1,
          'scale': 1,
        },
        <String, Object?>{
          'text': oversizedUtf8,
          'row': 0,
          'col': 0,
          'width_cells': 1,
          'height_cells': 1,
          'source_row_offset_cells': 0,
          'visible_height_cells': 1,
          'scale': 1,
        },
      ],
    });

    expect(frame.sizedText, hasLength(1));
    final placement = frame.sizedText.single;
    expect(placement.text, 'AB');
    expect(placement.widthCells, 4);
    expect(placement.heightCells, 2);
    expect(placement.scale, 2);
    expect(placement.subscaleN, 1);
    expect(placement.subscaleD, 2);
    expect(placement.verticalAlign, 2);
    expect(placement.horizontalAlign, 1);
  });

  test('terminal sized text protobuf enforces the 4 KiB UTF-8 limit', () {
    final payload = frame_pb.TerminalFrameDiff(
      cursor: frame_pb.TerminalCursor(row: 0, col: 0, visible: false),
      viewportRows: 4,
      viewportCols: 20,
      sizedText: <frame_pb.TerminalSizedTextPlacement>[
        frame_pb.TerminalSizedTextPlacement(
          text: List<String>.filled(1025, '😀').join(),
          row: 0,
          col: 0,
          widthCells: 1,
          heightCells: 1,
          sourceRowOffsetCells: 0,
          visibleHeightCells: 1,
          scale: 1,
        ),
      ],
    );

    final frame = const TerminalProtobufFrameCodec().decode(
      payload.writeToBuffer(),
    );
    expect(frame.sizedText, isEmpty);
  });

  test('terminal style runs normalize color strings', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {
          'index': 0,
          'text': 'styled',
          'style_runs': [
            {
              'start': 0,
              'end': 6,
              'foreground': ' #112233 ',
              'background': ' #80445566 ',
              'underline_color': ' #abcdef ',
            },
            {'start': 1, 'end': 6, 'foreground': '12#3456'},
          ],
        },
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'cursor_color': ' #123456 ',
      'selection_background': ' #234567 ',
      'selection_foreground': ' #345678 ',
      'link_color': ' #456789 ',
      'cursor_text_color': ' #56789a ',
      'tab_color': ' #6789ab ',
    });

    final run = frame.rows.single.styleRuns.first;
    expect(run.foreground, const Color(0xFF112233));
    expect(run.background, const Color(0x80445566));
    expect(run.underlineColor, const Color(0xFFABCDEF));
    expect(frame.cursorColor, const Color(0xFF123456));
    expect(frame.selectionBackground, const Color(0xFF234567));
    expect(frame.selectionForeground, const Color(0xFF345678));
    expect(frame.linkColor, const Color(0xFF456789));
    expect(frame.cursorTextColor, const Color(0xFF56789A));
    expect(frame.tabColor, const Color(0xFF6789AB));
    expect(frame.rows.single.styleRuns.last.foreground, isNull);
  });

  test('terminal rows cap style run batches', () {
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'rows': [
        {
          'index': 0,
          'text': 'styled',
          'style_runs': [
            for (var index = 0; index < 1026; index += 1)
              {'start': index, 'end': index + 1},
          ],
        },
      ],
      'cursor': const {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 1,
      'viewport_cols': 1200,
      'dirty_ranges': const [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows.single.styleRuns, hasLength(1024));
    expect(frame.rows.single.styleRuns.first.start, 0);
    expect(frame.rows.single.styleRuns.last.start, 1023);
  });

  test('terminal frames bound viewport row and dirty range batches', () {
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'rows': [
        for (var index = 0; index < 80; index += 1)
          {'index': index, 'text': 'row-$index'},
      ],
      'cursor': const {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 80,
      'dirty_ranges': [
        for (var index = 0; index < 80; index += 1) {'start': 0, 'end': 2},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows.map((row) => row.text).toList(), <String>[
      'row-0',
      'row-1',
    ]);
    expect(
      frame.dirtyRanges
          .map((range) => (range.start, range.end))
          .toList(growable: false),
      <(int, int)>[(0, 2)],
    );
  });

  test('terminal frames clamp row text to viewport columns', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {
          'index': 0,
          'text': 'abcdef',
          'style_runs': [
            {'start': 0, 'end': 6, 'bold': true},
          ],
        },
        {'index': 1, 'text': 'a你bc'},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 3,
      'dirty_ranges': [
        {'start': 0, 'end': 2},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows.map((row) => row.text).toList(), <String>['abc', 'a你']);
    expect(frame.rows.first.styleRuns, hasLength(1));
  });

  test('terminal frames omit partial wide glyphs when clamping rows', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': '你a'},
        {'index': 1, 'text': 'a你b'},
        {'index': 2, 'text': '你'},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 3,
      'viewport_cols': 1,
      'dirty_ranges': [
        {'start': 0, 'end': 3},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows.map((row) => row.text).toList(), <String>['', 'a', '']);
  });

  test('terminal frames cap hyperlink batches', () {
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'rows': const [],
      'cursor': const {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 5000,
      'viewport_cols': 80,
      'dirty_ranges': const [],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'hyperlinks': [
        for (var index = 0; index < 4100; index += 1)
          {
            'row': index,
            'start_col': 0,
            'end_col': 1,
            'uri': 'https://example.com/$index',
          },
      ],
    });

    expect(frame.hyperlinks, hasLength(4096));
    expect(frame.hyperlinks.first.uri, 'https://example.com/0');
    expect(frame.hyperlinks.last.uri, 'https://example.com/4095');
  });

  test('terminal frames skip malformed collection entries', () {
    final imageBytes = utf8.encode('fake-png');
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'frame_kind': 'delta',
      'rows': const [
        'bad-row',
        {
          'index': 0,
          'text': 'ok',
          'wrapped': 'not-a-bool',
          'style_runs': [
            'bad-style',
            {'start': 0, 'end': 2, 'bold': true},
            {'start': 'bad', 'end': 2},
            {'start': 0.5, 'end': 2, 'dim': true},
            {'start': -1, 'end': 2, 'italic': true},
            {'start': 2, 'end': 2, 'blink': true},
            {'start': 2, 'end': 3, 'underline': 'yes'},
          ],
        },
        {'index': 'bad', 'text': 'ignored'},
        {'index': 0.5, 'text': 'fractional'},
        {'index': 1, 'text': 42},
      ],
      'cursor': {'row': 0, 'col': 2, 'visible': true},
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [
        'bad-range',
        const {'start': 0, 'end': 1},
        {'start': 'bad', 'end': 1},
        {'start': 0.5, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'hyperlinks': [
        'bad-link',
        {
          'row': 0,
          'start_col': 0,
          'end_col': 2,
          'uri': ' https://example.com ',
        },
        const {'row': 0, 'start_col': 0, 'end_col': 2, 'uri': 7},
        const {
          'row': 0.5,
          'start_col': 0,
          'end_col': 2,
          'uri': 'https://fractional-row.example',
        },
        const {
          'row': -1,
          'start_col': 0,
          'end_col': 2,
          'uri': 'https://negative-row.example',
        },
        const {
          'row': 0,
          'start_col': -1,
          'end_col': 2,
          'uri': 'https://negative-col.example',
        },
        const {
          'row': 0,
          'start_col': 2,
          'end_col': 2,
          'uri': 'https://empty-range.example',
        },
        const {'row': 0, 'start_col': 0, 'end_col': 2, 'uri': '   '},
      ],
      'inline_images': [
        'bad-image',
        {
          'row': -1,
          'col': 0,
          'width_cells': 1,
          'height_cells': 1,
          'data': base64.encode(imageBytes),
        },
        {
          'row': 0,
          'col': -1,
          'width_cells': 1,
          'height_cells': 1,
          'data': base64.encode(imageBytes),
        },
        {
          'row': 0,
          'col': 0,
          'width_cells': 0,
          'height_cells': 1,
          'data': base64.encode(imageBytes),
        },
        {
          'row': 0,
          'col': 0,
          'width_cells': 1,
          'height_cells': -1,
          'data': base64.encode(imageBytes),
        },
      ],
      'modes': {'alternate_screen': true, 'mouse_mode': 7},
    });

    expect(frame.frameKind, TerminalFrameKind.delta);
    expect(frame.rows, hasLength(1));
    expect(frame.rows.single.index, 0);
    expect(frame.rows.single.text, 'ok');
    expect(frame.rows.single.wrapped, isFalse);
    expect(frame.rows.single.styleRuns, hasLength(2));
    expect(frame.rows.single.styleRuns.first.bold, isTrue);
    expect(frame.rows.single.styleRuns.last.underline, isFalse);
    expect(frame.dirtyRanges, hasLength(1));
    expect(frame.dirtyRanges.single.start, 0);
    expect(frame.hyperlinks, hasLength(1));
    expect(frame.hyperlinks.single.uri, 'https://example.com');
    expect(frame.inlineImages, isEmpty);
    expect(frame.modes.alternateScreen, isTrue);
    expect(frame.modes.mouseMode, 'off');
  });

  test(
    'terminal frames scan valid collection entries past malformed prefixes',
    () {
      final imageBytes = Uint8List.fromList(<int>[1, 2, 3]);
      final encodedImage = base64.encode(imageBytes);
      final frame = TerminalFrameDiff.fromJson(<String, Object?>{
        'rows': [
          for (var index = 0; index < 70; index += 1) 'bad-row-$index',
          {
            'index': 0,
            'text': 'styled',
            'style_runs': [
              for (var index = 0; index < 1030; index += 1) 'bad-style-$index',
              {'start': 0, 'end': 6, 'bold': true},
            ],
          },
          {'index': 1, 'text': 'plain'},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': [
          for (var index = 0; index < 70; index += 1) 'bad-range-$index',
          {'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'hyperlinks': [
          for (var index = 0; index < 4100; index += 1) 'bad-link-$index',
          {
            'row': 1,
            'start_col': 0,
            'end_col': 5,
            'uri': 'https://example.com/recovered',
          },
        ],
        'inline_images': [
          for (var index = 0; index < 40; index += 1) 'bad-image-$index',
          {
            'row': 1,
            'col': 0,
            'width_cells': 1,
            'height_cells': 1,
            'data': encodedImage,
          },
        ],
      });

      expect(frame.rows.map((row) => row.text), <String>['styled', 'plain']);
      expect(frame.rows.first.styleRuns.single.bold, isTrue);
      expect(
        frame.dirtyRanges.map((range) => (range.start, range.end)),
        <(int, int)>[(0, 2)],
      );
      expect(frame.hyperlinks.single.uri, 'https://example.com/recovered');
      expect(frame.inlineImages.single.bytes, imageBytes);
    },
  );

  test('terminal frames default malformed scalar fields', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'frame_kind': 7,
      'rows': [],
      'cursor': {'row': 'bad', 'col': 2, 'visible': true},
      'selection': {'start_row': 0, 'start_col': 'bad'},
      'viewport_rows': 'bad',
      'viewport_cols': null,
      'dirty_ranges': [],
      'scrollback_offset': 'bad',
      'scrollback_max_offset': 'bad',
      'viewport_start_row': 'bad',
      'viewport_row_shift': 'bad',
      'cursor_color': 'not-a-color',
      'modes': {
        'alternate_screen': 'yes',
        'mouse_mode': false,
        'mouse_encoding': 12,
      },
      'window_title': 99,
      'window_icon_name': false,
    });

    expect(frame.frameKind, TerminalFrameKind.snapshot);
    expect(frame.frameSchemaVersion, 'terminal-frame-diff-v1');
    expect(frame.cursor.row, 0);
    expect(frame.cursor.col, 0);
    expect(frame.cursor.visible, isFalse);
    expect(frame.cursorColor, isNull);
    expect(frame.selection, isNull);
    expect(frame.viewportRows, 0);
    expect(frame.viewportCols, 0);
    expect(frame.scrollbackOffset, 0);
    expect(frame.scrollbackMaxOffset, 0);
    expect(frame.viewportStartRow, 0);
    expect(frame.viewportRowShift, 0);
    expect(frame.modes.alternateScreen, isFalse);
    expect(frame.modes.mouseMode, 'off');
    expect(frame.modes.mouseEncoding, 'default');
    expect(frame.windowTitle, isNull);
    expect(frame.windowIconName, isNull);
  });

  test('terminal frames parse explicit frame schema versions', () {
    final explicit = TerminalFrameDiff.fromJson(const <String, Object?>{
      'frame_schema_version': ' terminal-frame-diff-v2 ',
      'rows': [],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    final legacy = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(explicit.frameSchemaVersion, 'terminal-frame-diff-v2');
    expect(legacy.frameSchemaVersion, 'terminal-frame-diff-v1');
  });

  test('terminal frames parse protobuf payloads', () {
    final imageBytes = utf8.encode('fake-png');
    final payload = frame_pb.TerminalFrameDiff(
      frameSchemaVersion: 'terminal-frame-diff-v2',
      frameKind: frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_DELTA,
      rows: [
        frame_pb.TerminalRow(
          index: 1,
          text: 'styled',
          wrapped: true,
          modifiedAtMicros: Int64(1780000000123456),
          styleRuns: [
            frame_pb.TerminalStyleRun(
              start: 0,
              end: 6,
              foreground: frame_pb.ColorRgb(present: true, rgb: 0x112233),
              background: frame_pb.ColorRgb(present: true, rgb: 0x445566),
              underlineColor: frame_pb.ColorRgb(present: true, rgb: 0xabcdef),
              bold: true,
            ),
          ],
        ),
      ],
      cursor: frame_pb.TerminalCursor(row: 1, col: 6, visible: true),
      selection: frame_pb.TerminalSelection(
        present: true,
        startRow: 1,
        startCol: 0,
        endRow: 1,
        endCol: 6,
      ),
      viewportRows: 3,
      viewportCols: 80,
      dirtyRanges: [frame_pb.TerminalDirtyRange(start: 1, end: 4)],
      scrollbackOffset: 9,
      scrollbackMaxOffset: 4,
      viewportStartRow: 12,
      viewportRowShift: -1,
      defaultForeground: frame_pb.ColorRgb(present: true, rgb: 0xaaaaaa),
      defaultBackground: frame_pb.ColorRgb(present: true, rgb: 0x101010),
      cursorColor: frame_pb.ColorRgb(present: true, rgb: 0xff00aa),
      selectionBackground: frame_pb.ColorRgb(present: true, rgb: 0x123456),
      selectionForeground: frame_pb.ColorRgb(present: true, rgb: 0xfedcba),
      linkColor: frame_pb.ColorRgb(present: true, rgb: 0x234567),
      cursorTextColor: frame_pb.ColorRgb(present: true, rgb: 0x345678),
      tabColor: frame_pb.ColorRgb(present: true, rgb: 0x456789),
      pointerShape: 'zoom-in',
      sizedText: [
        frame_pb.TerminalSizedTextPlacement(
          text: 'AB',
          row: 0,
          col: 1,
          widthCells: 4,
          heightCells: 2,
          sourceRowOffsetCells: 0,
          visibleHeightCells: 2,
          scale: 2,
          subscaleN: 1,
          subscaleD: 2,
          verticalAlign: 2,
          horizontalAlign: 1,
          naturalWidth: false,
          underlineColor: frame_pb.ColorRgb(present: true, rgb: 0x102030),
        ),
      ],
      modes: frame_pb.TerminalFrameModes(
        alternateScreen: true,
        mouseMode: ' Any_Event ',
        mouseEncoding: ' SGR-Pixels ',
        kittyKeyboardFlags: 7,
        synchronizedOutput: true,
      ),
      windowTitle: 'title',
      windowIconName: 'icon',
      hyperlinks: [
        frame_pb.TerminalHyperlinkRange(
          row: 1,
          startCol: 0,
          endCol: 6,
          uri: ' https://example.com ',
        ),
      ],
      inlineImages: [
        frame_pb.TerminalInlineImage(
          row: 1,
          col: 2,
          widthCells: 4,
          heightCells: 2,
          data: base64.encode(imageBytes),
          altText: 'preview',
        ),
      ],
      graphics: [
        frame_pb.TerminalGraphicPlacement(
          placementId: Int64(11),
          renderId: Int64(101),
          assetKey: frame_pb.TerminalGraphicAssetKey(
            assetId: Int64(7),
            assetVersion: Int64(3),
          ),
          protocol: 'kitty',
          row: 1,
          col: 2,
          widthPx: 8,
          heightPx: 4,
          widthCells: 4,
          heightCells: 2,
          sourceXOffsetPx: 2,
          visibleWidthPx: 6,
          sourceYOffsetPx: 1,
          visibleHeightPx: 3,
          zIndex: 1,
          xOffsetPx: 2,
          yOffsetPx: 1,
          preserveAspectRatio: false,
        ),
      ],
    );

    final frame = const TerminalProtobufFrameCodec().decode(
      payload.writeToBuffer(),
    );

    expect(frame.frameSchemaVersion, 'terminal-frame-diff-v2');
    expect(frame.frameKind, TerminalFrameKind.delta);
    expect(frame.rows.single.index, 1);
    expect(frame.rows.single.text, 'styled');
    expect(frame.rows.single.wrapped, isTrue);
    expect(
      frame.rows.single.modifiedAt,
      DateTime.fromMicrosecondsSinceEpoch(1780000000123456, isUtc: true),
    );
    expect(
      frame.rows.single.styleRuns.single.foreground,
      const Color(0xFF112233),
    );
    expect(
      frame.rows.single.styleRuns.single.background,
      const Color(0xFF445566),
    );
    expect(
      frame.rows.single.styleRuns.single.underlineColor,
      const Color(0xFFABCDEF),
    );
    expect(frame.rows.single.styleRuns.single.bold, isTrue);
    expect(frame.cursor.row, 1);
    expect(frame.cursor.col, 6);
    expect(frame.cursor.visible, isTrue);
    expect(frame.selection, isNotNull);
    expect(frame.selection!.startRow, 1);
    expect(frame.viewportRows, 3);
    expect(frame.viewportCols, 80);
    expect(
      frame.dirtyRanges.map((range) => (range.start, range.end)).toList(),
      <(int, int)>[(1, 3)],
    );
    expect(frame.scrollbackOffset, 4);
    expect(frame.scrollbackMaxOffset, 4);
    expect(frame.viewportStartRow, 12);
    expect(frame.viewportRowShift, -1);
    expect(frame.defaultForeground, const Color(0xFFAAAAAA));
    expect(frame.defaultBackground, const Color(0xFF101010));
    expect(frame.cursorColor, const Color(0xFFFF00AA));
    expect(frame.selectionBackground, const Color(0xFF123456));
    expect(frame.selectionForeground, const Color(0xFFFEDCBA));
    expect(frame.linkColor, const Color(0xFF234567));
    expect(frame.cursorTextColor, const Color(0xFF345678));
    expect(frame.tabColor, const Color(0xFF456789));
    expect(frame.pointerShape, TerminalPointerShape.zoomIn);
    expect(frame.sizedText, hasLength(1));
    expect(frame.sizedText.single.text, 'AB');
    expect(frame.sizedText.single.widthCells, 4);
    expect(frame.sizedText.single.scale, 2);
    expect(frame.sizedText.single.subscaleN, 1);
    expect(frame.sizedText.single.subscaleD, 2);
    expect(frame.sizedText.single.underlineColor, const Color(0xFF102030));
    expect(frame.modes.alternateScreen, isTrue);
    expect(frame.modes.mouseMode, 'any_event');
    expect(frame.modes.mouseEncoding, 'sgr_pixels');
    expect(frame.modes.kittyKeyboardFlags, 7);
    expect(frame.modes.synchronizedOutput, isTrue);
    expect(frame.windowTitle, 'title');
    expect(frame.windowIconName, 'icon');
    expect(frame.hyperlinks.single.uri, 'https://example.com');
    expect(frame.inlineImages.single.bytes, imageBytes);
    expect(frame.inlineImages.single.altText, 'preview');
    expect(
      frame.graphics.single.assetKey,
      const TerminalGraphicAssetKey(id: 7, version: 3),
    );
    expect(frame.graphics.single.renderId, 101);
    expect(frame.graphics.single.visibleWidthPx, 6);
    expect(frame.graphics.single.preserveAspectRatio, isFalse);
  });

  test('terminal render intent describes sparse delta repaint work', () {
    final intent = TerminalRenderIntent.fromFrame(
      const TerminalFrameDiff(
        frameKind: TerminalFrameKind.delta,
        rows: [TerminalRow(index: 2, text: 'changed')],
        cursor: TerminalCursor(row: 2, col: 7, visible: true),
        viewportRows: 4,
        viewportCols: 80,
        dirtyRanges: [
          TerminalDirtyRange(start: 0, end: 1),
          TerminalDirtyRange(start: 2, end: 3),
        ],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        viewportRowShift: -1,
      ),
      hasNewFrame: true,
    );

    expect(intent.rebuildAllRows, isFalse);
    expect(intent.shiftsRowCache, isTrue);
    expect(intent.rowCacheShift, -1);
    expect(intent.dirtyRowIndexes, <int>{0, 2});
    expect(intent.dirtyStart, 0);
    expect(intent.dirtyEnd, 3);
  });

  test('terminal viewport state retains and replaces OSC 50 font deltas', () {
    final initial = TerminalViewportState.empty.applySnapshot(
      const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'initial')],
        cursor: TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 1,
        viewportCols: 20,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        fontFamily: 'Profile Mono',
      ),
    );
    final retained = initial.applyDelta(
      const TerminalFrameDiff(
        frameKind: TerminalFrameKind.delta,
        rows: [TerminalRow(index: 0, text: 'retained')],
        cursor: TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 1,
        viewportCols: 20,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );
    final replaced = retained.applyDelta(
      const TerminalFrameDiff(
        frameKind: TerminalFrameKind.delta,
        rows: [TerminalRow(index: 0, text: 'replaced')],
        cursor: TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 1,
        viewportCols: 20,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        fontFamily: 'Courier Prime',
      ),
    );

    expect(retained.frame.fontFamily, 'Profile Mono');
    expect(replaced.frame.fontFamily, 'Courier Prime');
  });

  test(
    'terminal render intent keeps full rebuild separate from dirty rows',
    () {
      final snapshotIntent = TerminalRenderIntent.fromFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'full')],
          cursor: TerminalCursor(row: 0, col: 4, visible: true),
          viewportRows: 3,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 3)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
        hasNewFrame: true,
      );
      final idleIntent = TerminalRenderIntent.fromFrame(
        TerminalFrameDiff.empty,
        hasNewFrame: false,
      );

      expect(snapshotIntent.rebuildAllRows, isTrue);
      expect(snapshotIntent.dirtyRowIndexes, isEmpty);
      expect(snapshotIntent.dirtyStart, 0);
      expect(snapshotIntent.dirtyEnd, 3);
      expect(idleIntent, same(TerminalRenderIntent.none));
    },
  );

  test('terminal frames normalize frame kind tokens', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'frame_kind': ' Delta ',
      'rows': [],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 0,
      'viewport_cols': 80,
      'dirty_ranges': [],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.frameKind, TerminalFrameKind.delta);
  });

  test('terminal frames reject negative cursor and selection coordinates', () {
    final invalid = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [],
      'cursor': {'row': -1, 'col': 2, 'visible': true},
      'selection': {
        'start_row': 0,
        'start_col': 0,
        'end_row': -1,
        'end_col': 2,
      },
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    final reversedSelection = TerminalFrameDiff.fromJson(
      const <String, Object?>{
        'rows': [],
        'cursor': {'row': 0, 'col': 0, 'visible': true},
        'selection': {
          'start_row': 1,
          'start_col': 4,
          'end_row': 0,
          'end_col': 1,
        },
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': [],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      },
    );

    expect(invalid.cursor.row, 0);
    expect(invalid.cursor.col, 0);
    expect(invalid.cursor.visible, isFalse);
    expect(invalid.selection, isNull);
    expect(reversedSelection.selection, isNotNull);
    expect(
      reversedSelection.selection!.normalized().toJson(),
      const <String, Object?>{
        'start_row': 0,
        'start_col': 1,
        'end_row': 1,
        'end_col': 4,
      },
    );
  });

  test('terminal frames reject fractional coordinate fields', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0.5, 'text': 'fractional'},
        {'index': 0, 'text': 'ok'},
      ],
      'cursor': {'row': 0.5, 'col': 0, 'visible': true},
      'selection': {
        'start_row': 0,
        'start_col': 0.5,
        'end_row': 0,
        'end_col': 1,
      },
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0.5, 'end': 1},
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows, hasLength(1));
    expect(frame.rows.single.text, 'ok');
    expect(frame.cursor.visible, isFalse);
    expect(frame.selection, isNull);
    expect(
      frame.dirtyRanges
          .map((range) => (range.start, range.end))
          .toList(growable: false),
      <(int, int)>[(0, 1)],
    );
  });

  test('terminal frames clamp scalar bounds from native payloads', () {
    final negative = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': -2,
      'viewport_cols': -80,
      'dirty_ranges': [],
      'scrollback_offset': -4,
      'scrollback_max_offset': -1,
      'viewport_start_row': -9,
      'viewport_row_shift': -1,
    });
    final overflow = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [],
      'scrollback_offset': 99,
      'scrollback_max_offset': 10,
      'viewport_start_row': 3,
    });
    final oversized = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 70000,
      'viewport_cols': 70000,
      'dirty_ranges': [
        {'start': 0, 'end': 999999},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'viewport_start_row': 3,
    });

    expect(negative.viewportRows, 0);
    expect(negative.viewportCols, 0);
    expect(negative.scrollbackOffset, 0);
    expect(negative.scrollbackMaxOffset, 0);
    expect(negative.viewportStartRow, 0);
    expect(negative.viewportRowShift, -1);
    expect(overflow.scrollbackOffset, 10);
    expect(overflow.scrollbackMaxOffset, 10);
    expect(oversized.viewportRows, 65535);
    expect(oversized.viewportCols, 65535);
    expect(oversized.dirtyRanges.single.end, 65535);
  });

  test('terminal viewport controller clamps direct scalar frame bounds', () {
    final negativeController = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: -2,
          viewportCols: -80,
          dirtyRanges: [],
          scrollbackOffset: -4,
          scrollbackMaxOffset: -1,
          viewportStartRow: -9,
          viewportRowShift: -1,
        ),
      );
    addTearDown(negativeController.dispose);

    final negative = negativeController.frame;
    expect(negative.viewportRows, 0);
    expect(negative.viewportCols, 0);
    expect(negative.scrollbackOffset, 0);
    expect(negative.scrollbackMaxOffset, 0);
    expect(negative.viewportStartRow, 0);
    expect(negative.viewportRowShift, 0);

    final overflowController = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 70000,
          viewportCols: 70000,
          dirtyRanges: [],
          scrollbackOffset: 99,
          scrollbackMaxOffset: 10,
          viewportStartRow: 3,
        ),
      );
    addTearDown(overflowController.dispose);

    final overflow = overflowController.frame;
    expect(overflow.viewportRows, 65535);
    expect(overflow.viewportCols, 65535);
    expect(overflow.scrollbackOffset, 10);
    expect(overflow.scrollbackMaxOffset, 10);
    expect(overflow.viewportStartRow, 3);
  });

  test('terminal viewport controller drops invalid direct coordinates', () {
    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'ready')],
          cursor: TerminalCursor(row: -1, col: 0, visible: true),
          selection: TerminalSelection(
            startRow: 0,
            startCol: -1,
            endRow: 0,
            endCol: 5,
          ),
          viewportRows: 1,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
    addTearDown(controller.dispose);

    expect(controller.frame.cursor.row, 0);
    expect(controller.frame.cursor.col, 0);
    expect(controller.frame.cursor.visible, isFalse);
    expect(controller.frame.selection, isNull);
  });

  test('terminal frames default fractional scalar fields', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2.5,
      'viewport_cols': 80.5,
      'dirty_ranges': [],
      'scrollback_offset': 1.5,
      'scrollback_max_offset': 4.5,
      'viewport_start_row': 2.5,
      'viewport_row_shift': 1.5,
    });

    expect(frame.viewportRows, 0);
    expect(frame.viewportCols, 0);
    expect(frame.scrollbackOffset, 0);
    expect(frame.scrollbackMaxOffset, 0);
    expect(frame.viewportStartRow, 0);
    expect(frame.viewportRowShift, 0);
  });

  test('terminal frames clamp dirty ranges to the viewport', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 3,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': -4, 'end': 99},
        {'start': 2, 'end': 1},
        {'start': 4, 'end': 5},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    final emptyViewport = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 0,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(
      frame.dirtyRanges
          .map((range) => (range.start, range.end))
          .toList(growable: false),
      <(int, int)>[(0, 3)],
    );
    expect(emptyViewport.dirtyRanges, isEmpty);
  });

  test('terminal frames parse inline image payloads', () {
    final imageBytes = utf8.encode('fake-png');
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'rows': const [
        {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
      ],
      'cursor': const {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 4,
      'viewport_cols': 80,
      'dirty_ranges': const [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'inline_images': [
        {
          'row': 0,
          'col': 2,
          'width_cells': 4,
          'height_cells': 3,
          'data': base64.encode(imageBytes),
          'alt': 'preview',
        },
        {'base64': base64.encode(imageBytes)},
      ],
    });

    expect(frame.inlineImages, hasLength(2));
    expect(frame.inlineImages.first.row, 0);
    expect(frame.inlineImages.first.col, 2);
    expect(frame.inlineImages.first.widthCells, 4);
    expect(frame.inlineImages.first.heightCells, 3);
    expect(frame.inlineImages.first.bytes, imageBytes);
    expect(frame.inlineImages.first.altText, 'preview');
    expect(frame.inlineImages.last.row, 0);
    expect(frame.inlineImages.last.col, 0);
    expect(frame.inlineImages.last.widthCells, 1);
    expect(frame.inlineImages.last.heightCells, 1);
    expect(frame.inlineImages.last.bytes, imageBytes);
  });

  test('terminal frames drop inline images that start past the right edge', () {
    final imageBytes = utf8.encode('fake-png');
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'rows': const [
        {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
      ],
      'cursor': const {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 8,
      'dirty_ranges': const [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'inline_images': [
        {
          'row': 0,
          'col': 8,
          'width_cells': 4,
          'height_cells': 2,
          'data': base64.encode(imageBytes),
        },
      ],
    });

    expect(frame.inlineImages, isEmpty);
  });

  test('terminal frames clamp inline image overlays to viewport bounds', () {
    final imageBytes = utf8.encode('fake-png');
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'rows': const [
        {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
      ],
      'cursor': const {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 5,
      'dirty_ranges': const [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'inline_images': [
        {
          'row': 0,
          'col': 3,
          'width_cells': 10,
          'height_cells': 10,
          'data': base64.encode(imageBytes),
          'alt': 'wide preview',
        },
        {
          'row': 0,
          'col': 5,
          'width_cells': 1,
          'height_cells': 1,
          'data': base64.encode(imageBytes),
        },
        {
          'row': 2,
          'col': 0,
          'width_cells': 1,
          'height_cells': 1,
          'data': base64.encode(imageBytes),
        },
      ],
    });

    expect(frame.inlineImages, hasLength(1));
    expect(frame.inlineImages.single.col, 3);
    expect(frame.inlineImages.single.widthCells, 2);
    expect(frame.inlineImages.single.heightCells, 2);
    expect(frame.inlineImages.single.altText, 'wide preview');
  });

  test('terminal frames parse graphics placement payloads', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'graphics': [
        {
          'render_id': 101,
          'placement_id': 11,
          'asset_id': 7,
          'asset_version': 3,
          'protocol': 'kitty',
          'row': 0,
          'col': 2,
          'width_px': 8,
          'height_px': 4,
          'width_cells': 4,
          'height_cells': 2,
          'source_x_offset_px': 2,
          'visible_width_px': 6,
          'source_y_offset_px': 1,
          'visible_height_px': 3,
          'z_index': 1,
          'x_offset_px': 2,
          'y_offset_px': 1,
          'preserve_aspect_ratio': false,
        },
      ],
    });

    expect(frame.graphics, hasLength(1));
    final graphic = frame.graphics.single;
    expect(graphic.renderId, 101);
    expect(graphic.placementId, 11);
    expect(graphic.assetKey, const TerminalGraphicAssetKey(id: 7, version: 3));
    expect(graphic.protocol, 'kitty');
    expect(graphic.row, 0);
    expect(graphic.col, 2);
    expect(graphic.widthPx, 8);
    expect(graphic.heightPx, 4);
    expect(graphic.widthCells, 4);
    expect(graphic.heightCells, 2);
    expect(graphic.sourceXOffsetPx, 2);
    expect(graphic.visibleWidthPx, 6);
    expect(graphic.sourceYOffsetPx, 1);
    expect(graphic.visibleHeightPx, 3);
    expect(graphic.zIndex, 1);
    expect(graphic.xOffsetPx, 2);
    expect(graphic.yOffsetPx, 1);
    expect(graphic.preserveAspectRatio, isFalse);
  });

  test('terminal frames preserve multi-protocol graphics placements', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'graphics', 'style_runs': <Object?>[]},
        {'index': 1, 'text': 'below', 'style_runs': <Object?>[]},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 4,
      'viewport_cols': 12,
      'dirty_ranges': [
        {'start': 0, 'end': 2},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'graphics': [
        {
          'render_id': 303,
          'placement_id': 33,
          'asset_id': 30,
          'asset_version': 1,
          'protocol': 'iterm',
          'row': 1,
          'col': 2,
          'width_px': 12,
          'height_px': 6,
          'width_cells': 3,
          'height_cells': 1,
          'z_index': 1,
        },
        {
          'render_id': 101,
          'placement_id': 11,
          'asset_id': 10,
          'asset_version': 1,
          'protocol': 'kitty',
          'row': 0,
          'col': 1,
          'width_px': 8,
          'height_px': 6,
          'width_cells': 2,
          'height_cells': 1,
          'z_index': 0,
        },
        {
          'render_id': 202,
          'placement_id': 22,
          'asset_id': 20,
          'asset_version': 1,
          'protocol': 'sixel',
          'row': 0,
          'col': 0,
          'width_px': 8,
          'height_px': 6,
          'width_cells': 2,
          'height_cells': 1,
          'z_index': -1,
        },
      ],
    });

    expect(frame.graphics.map((graphic) => graphic.protocol).toList(), <String>[
      'sixel',
      'kitty',
      'iterm',
    ]);
    expect(frame.graphics.map((graphic) => graphic.renderId).toList(), <int>[
      202,
      101,
      303,
    ]);
  });

  test('terminal frames keep legacy graphics payloads readable', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'graphics': [
        {
          'placement_id': 0,
          'asset_id': 7,
          'asset_version': 3,
          'protocol': 'kitty',
          'row': 0,
          'col': 2,
          'width_px': 8,
          'height_px': 4,
          'width_cells': 4,
          'height_cells': 2,
        },
      ],
    });

    expect(frame.graphics, hasLength(1));
    expect(frame.graphics.single.renderId, 0);
    expect(frame.graphics.single.placementId, 0);
    expect(frame.graphics.single.sourceXOffsetPx, 0);
    expect(frame.graphics.single.visibleWidthPx, 8);
    expect(frame.graphics.single.sourceYOffsetPx, 0);
    expect(frame.graphics.single.visibleHeightPx, 4);
  });

  test('terminal frames drop graphics that start past the right edge', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 8,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'graphics': [
        {
          'placement_id': 11,
          'asset_id': 7,
          'asset_version': 3,
          'protocol': 'kitty',
          'row': 0,
          'col': 8,
          'width_px': 8,
          'height_px': 4,
          'width_cells': 4,
          'height_cells': 2,
        },
      ],
    });

    expect(frame.graphics, isEmpty);
  });

  test('terminal frames drop graphics with invalid horizontal clip', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 8,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'graphics': [
        {
          'placement_id': 11,
          'asset_id': 7,
          'asset_version': 3,
          'protocol': 'kitty',
          'row': 0,
          'col': 2,
          'width_px': 8,
          'height_px': 4,
          'width_cells': 4,
          'height_cells': 2,
          'source_x_offset_px': 6,
          'visible_width_px': 3,
        },
        {
          'placement_id': 12,
          'asset_id': 7,
          'asset_version': 3,
          'protocol': 'sixel',
          'row': 0,
          'col': 2,
          'width_px': 8,
          'height_px': 4,
          'width_cells': 4,
          'height_cells': 2,
          'source_x_offset_px': 8,
        },
      ],
    });

    expect(frame.graphics, isEmpty);
  });

  test(
    'terminal viewport controller drops graphics with invalid vertical clip',
    () {
      final controller = TerminalViewportController();

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'image')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          graphics: [
            TerminalGraphicPlacement(
              placementId: 11,
              assetKey: TerminalGraphicAssetKey(id: 7, version: 3),
              protocol: 'kitty',
              row: 0,
              col: 2,
              widthPx: 8,
              heightPx: 4,
              widthCells: 4,
              heightCells: 2,
              sourceYOffsetPx: 3,
              visibleHeightPx: 2,
            ),
          ],
        ),
      );

      expect(controller.frame.graphics, isEmpty);
    },
  );

  test('terminal graphics cache retries after a missing asset', () async {
    var loadCount = 0;
    final cache = TerminalGraphicsCache(
      loadAsset: (key) async {
        loadCount += 1;
        if (loadCount == 1) {
          return null;
        }
        return TerminalGraphicAsset(
          key: key,
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
        );
      },
      decodeImage: (rgba, width, height) {
        final completer = Completer<Image>();
        decodeImageFromPixels(
          rgba,
          width,
          height,
          PixelFormat.rgba8888,
          completer.complete,
        );
        return completer.future;
      },
    );
    addTearDown(cache.dispose);

    const key = TerminalGraphicAssetKey(id: 42, version: 2);
    final first = await cache.imageFor(key);
    final second = await cache.imageFor(key);
    final third = await cache.imageFor(key);

    expect(first, isNull);
    expect(second, isNotNull);
    expect(third, same(second));
    expect(loadCount, 2);
  });

  test('terminal graphics cache emits image lifecycle diagnostics', () async {
    final diagnosticEvents = <Map<String, Object?>>[];
    final cache = TerminalGraphicsCache(
      diagnosticSessionId: 'session-a',
      diagnosticEventSink: diagnosticEvents.add,
      loadAsset: (key) async {
        return TerminalGraphicAsset(
          key: key,
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
        );
      },
      decodeImage: (rgba, width, height) {
        final completer = Completer<Image>();
        decodeImageFromPixels(
          rgba,
          width,
          height,
          PixelFormat.rgba8888,
          completer.complete,
        );
        return completer.future;
      },
    );
    addTearDown(cache.dispose);

    const key = TerminalGraphicAssetKey(id: 42, version: 2);
    final first = await cache.imageFor(key);
    final second = await cache.imageFor(key);
    cache.evictExcept(const <TerminalGraphicAssetKey>{});

    expect(first, isNotNull);
    expect(second, same(first));
    expect(
      diagnosticEvents
          .where(
            (event) =>
                event['schema_version'] ==
                'ianvs-terminal-graphics-diagnostic-v1',
          )
          .map((event) => event['event'])
          .toList(),
      containsAllInOrder(<String>[
        'cache_load_start',
        'cache_store',
        'cache_hit',
        'cache_sync',
        'cache_evict',
      ]),
    );
    expect(
      diagnosticEvents
          .where((event) => event['event'] == 'cache_store')
          .map((event) => event['asset_key'])
          .single,
      <String, Object?>{'id': 42, 'version': 2},
    );
    final syncEvent = diagnosticEvents.singleWhere(
      (event) => event['event'] == 'cache_sync',
    );
    expect(syncEvent['live_asset_count'], 0);
    expect(syncEvent['cached_images_before'], 1);
    expect(syncEvent['pending_images_before'], 0);
  });

  test(
    'terminal graphics cache skips invalid assets without decoding',
    () async {
      var loadCount = 0;
      var decodeCount = 0;
      final cache = TerminalGraphicsCache(
        loadAsset: (key) async {
          loadCount += 1;
          if (loadCount == 1) {
            return TerminalGraphicAsset(
              key: key,
              width: 2,
              height: 1,
              rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
            );
          }
          return TerminalGraphicAsset(
            key: key,
            width: 1,
            height: 1,
            rgba: Uint8List.fromList(const <int>[0, 255, 0, 255]),
          );
        },
        decodeImage: (rgba, width, height) {
          decodeCount += 1;
          final completer = Completer<Image>();
          decodeImageFromPixels(
            rgba,
            width,
            height,
            PixelFormat.rgba8888,
            completer.complete,
          );
          return completer.future;
        },
      );
      addTearDown(cache.dispose);

      const key = TerminalGraphicAssetKey(id: 43, version: 1);
      final invalid = await cache.imageFor(key);
      final valid = await cache.imageFor(key);
      final cached = await cache.imageFor(key);

      expect(invalid, isNull);
      expect(valid, isNotNull);
      expect(cached, same(valid));
      expect(loadCount, 2);
      expect(decodeCount, 1);
    },
  );

  test('terminal graphics cache premultiplies alpha before decoding', () async {
    late Uint8List decodedRgba;
    final cache = TerminalGraphicsCache(
      loadAsset: (key) async => TerminalGraphicAsset(
        key: key,
        width: 3,
        height: 1,
        rgba: Uint8List.fromList(const <int>[
          100,
          50,
          200,
          0,
          100,
          50,
          200,
          128,
          10,
          20,
          30,
          255,
        ]),
      ),
      decodeImage: (rgba, width, height) {
        decodedRgba = Uint8List.fromList(rgba);
        final completer = Completer<Image>();
        decodeImageFromPixels(
          rgba,
          width,
          height,
          PixelFormat.rgba8888,
          completer.complete,
        );
        return completer.future;
      },
    );
    addTearDown(cache.dispose);

    final image = await cache.imageFor(
      const TerminalGraphicAssetKey(id: 9, version: 1),
    );

    expect(image, isNotNull);
    expect(decodedRgba, <int>[0, 0, 0, 0, 50, 25, 100, 128, 10, 20, 30, 255]);
  });

  test(
    'terminal graphics cache evicts assets omitted by Rust frames',
    () async {
      var loadCount = 0;
      final cache = TerminalGraphicsCache(
        loadAsset: (key) async {
          loadCount += 1;
          return TerminalGraphicAsset(
            key: key,
            width: 1,
            height: 1,
            rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
          );
        },
        decodeImage: (rgba, width, height) {
          final completer = Completer<Image>();
          decodeImageFromPixels(
            rgba,
            width,
            height,
            PixelFormat.rgba8888,
            completer.complete,
          );
          return completer.future;
        },
      );
      addTearDown(cache.dispose);

      const key = TerminalGraphicAssetKey(id: 42, version: 1);
      final first = await cache.imageFor(key);
      cache.evictExcept(const <TerminalGraphicAssetKey>{});
      final second = await cache.imageFor(key);

      expect(second, isNot(same(first)));
      expect(loadCount, 2);
    },
  );

  test('terminal graphics cache evicts old animation asset versions', () async {
    final loadCounts = <TerminalGraphicAssetKey, int>{};
    final cache = TerminalGraphicsCache(
      loadAsset: (key) async {
        loadCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
        return TerminalGraphicAsset(
          key: key,
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(<int>[
            if (key.version == 1) 255 else 0,
            if (key.version == 2) 255 else 0,
            0,
            255,
          ]),
        );
      },
      decodeImage: (rgba, width, height) {
        final completer = Completer<Image>();
        decodeImageFromPixels(
          rgba,
          width,
          height,
          PixelFormat.rgba8888,
          completer.complete,
        );
        return completer.future;
      },
    );
    addTearDown(cache.dispose);

    const firstVersion = TerminalGraphicAssetKey(id: 42, version: 1);
    const secondVersion = TerminalGraphicAssetKey(id: 42, version: 2);

    final firstImage = await cache.imageFor(firstVersion);
    expect(firstImage, isNotNull);

    cache.evictExcept(<TerminalGraphicAssetKey>{secondVersion});
    expect(firstImage!.debugDisposed, isTrue);

    final secondImage = await cache.imageFor(secondVersion);
    expect(secondImage, isNotNull);
    expect(loadCounts[firstVersion], 1);
    expect(loadCounts[secondVersion], 1);

    final reloadedFirstImage = await cache.imageFor(firstVersion);
    expect(reloadedFirstImage, isNotNull);
    expect(reloadedFirstImage, isNot(same(firstImage)));
    expect(loadCounts[firstVersion], 2);
  });

  test('terminal graphics cache drops pending image after eviction', () async {
    final loadAsset = Completer<TerminalGraphicAsset?>();
    final decodeImage = Completer<Image>();
    Image? decodedImage;
    final cache = TerminalGraphicsCache(
      loadAsset: (_) => loadAsset.future,
      decodeImage: (_, _, _) => decodeImage.future,
    );
    addTearDown(() {
      final image = decodedImage;
      if (image != null && !image.debugDisposed) {
        image.dispose();
      }
      cache.dispose();
    });

    const key = TerminalGraphicAssetKey(id: 77, version: 1);
    final pending = cache.imageFor(key);
    cache.evictExcept(const <TerminalGraphicAssetKey>{});
    loadAsset.complete(
      TerminalGraphicAsset(
        key: key,
        width: 1,
        height: 1,
        rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
      ),
    );
    final imageCompleter = Completer<Image>();
    decodeImageFromPixels(
      Uint8List.fromList(const <int>[255, 0, 0, 255]),
      1,
      1,
      PixelFormat.rgba8888,
      imageCompleter.complete,
    );
    decodedImage = await imageCompleter.future;
    decodeImage.complete(decodedImage);

    expect(await pending, isNull);
    expect(decodedImage.debugDisposed, isTrue);
  });

  test('terminal graphics cache drops pending image after dispose', () async {
    final loadAsset = Completer<TerminalGraphicAsset?>();
    final decodeImage = Completer<Image>();
    Image? decodedImage;
    final cache = TerminalGraphicsCache(
      loadAsset: (_) => loadAsset.future,
      decodeImage: (_, _, _) => decodeImage.future,
    );
    addTearDown(() {
      final image = decodedImage;
      if (image != null && !image.debugDisposed) {
        image.dispose();
      }
      cache.dispose();
    });

    const key = TerminalGraphicAssetKey(id: 78, version: 1);
    final pending = cache.imageFor(key);
    cache.dispose();
    loadAsset.complete(
      TerminalGraphicAsset(
        key: key,
        width: 1,
        height: 1,
        rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
      ),
    );
    final imageCompleter = Completer<Image>();
    decodeImageFromPixels(
      Uint8List.fromList(const <int>[255, 0, 0, 255]),
      1,
      1,
      PixelFormat.rgba8888,
      imageCompleter.complete,
    );
    decodedImage = await imageCompleter.future;
    decodeImage.complete(decodedImage);

    expect(await pending, isNull);
    expect(decodedImage.debugDisposed, isTrue);
  });

  test('terminal runtime loads graphic assets from the backend', () async {
    final runtimeBackend = _FakePtyBackend();
    runtimeBackend.graphicAssets[(7, 3)] = PtyGraphicAsset(
      assetId: 7,
      assetVersion: 3,
      width: 1,
      height: 1,
      rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
    );
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    final asset = await runtime.loadGraphicAsset(
      sessionId,
      const TerminalGraphicAssetKey(id: 7, version: 3),
    );

    expect(asset, isNotNull);
    expect(asset!.key, const TerminalGraphicAssetKey(id: 7, version: 3));
    expect(asset.width, 1);
    expect(asset.height, 1);
    expect(asset.rgba, <int>[255, 0, 0, 255]);
    expect(runtimeBackend.graphicAssetRequests, <(String, int, int)>[
      (sessionId, 7, 3),
    ]);
  });

  test('terminal runtime reports graphic asset load failures', () async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    final backendErrors = <TerminalSessionBackendErrorEvent>[];
    final backendErrorSubscription = runtime.events
        .where((event) => event is TerminalSessionBackendErrorEvent)
        .cast<TerminalSessionBackendErrorEvent>()
        .listen(backendErrors.add);
    addTearDown(backendErrorSubscription.cancel);

    runtimeBackend.failingOperations.add('loadGraphicAsset');

    final asset = await runtime.loadGraphicAsset(
      sessionId,
      const TerminalGraphicAssetKey(id: 7, version: 3),
    );
    await Future<void>.delayed(Duration.zero);

    expect(asset, isNull);
    expect(backendErrors.map((event) => event.operation), <String>[
      'loadGraphicAsset',
    ]);
    expect(
      backendErrors.single.error.toString(),
      contains('loadGraphicAsset failed'),
    );

    runtimeBackend.failingOperations.clear();
  });

  test(
    'terminal runtime keeps graphics caches isolated across panes',
    () async {
      final runtimeBackend = _FakePtyBackend();
      runtimeBackend.graphicAssets[(7, 3)] = PtyGraphicAsset(
        assetId: 7,
        assetVersion: 3,
        width: 1,
        height: 1,
        rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
      );
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final firstSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final secondSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/zsh'),
        ),
      );
      final firstCache = runtime.graphicsCacheFor(firstSessionId);
      final secondCache = runtime.graphicsCacheFor(secondSessionId);
      const key = TerminalGraphicAssetKey(id: 7, version: 3);

      final firstImage = await firstCache.imageFor(key);
      final secondImage = await secondCache.imageFor(key);
      final firstImageAgain = await firstCache.imageFor(key);
      final secondImageAgain = await secondCache.imageFor(key);

      expect(firstCache, isNot(same(secondCache)));
      expect(firstImage, isNotNull);
      expect(secondImage, isNotNull);
      expect(firstImage, isNot(same(secondImage)));
      expect(firstImageAgain, same(firstImage));
      expect(secondImageAgain, same(secondImage));
      expect(runtimeBackend.graphicAssetRequests, <(String, int, int)>[
        (firstSessionId, 7, 3),
        (secondSessionId, 7, 3),
      ]);
    },
  );

  test('terminal frames ignore malformed inline image payloads', () {
    const encodedImage = 'ZmFrZS1wbmc=';
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'inline_images': [
        {
          'row': 0,
          'col': 2,
          'width_cells': 4,
          'height_cells': 3,
          'data': 'not-valid-base64!!!',
        },
        {'row': 0, 'col': 2, 'width_cells': 4, 'height_cells': 3, 'data': 42},
        {
          'row': 'bad',
          'col': 2,
          'width_cells': 4,
          'height_cells': 3,
          'data': encodedImage,
        },
        {
          'row': 0.5,
          'col': 2,
          'width_cells': 4,
          'height_cells': 3,
          'data': encodedImage,
        },
        {
          'row': 0,
          'col': 'bad',
          'width_cells': 4,
          'height_cells': 3,
          'data': encodedImage,
        },
        {
          'row': 0,
          'col': 2,
          'width_cells': 'wide',
          'height_cells': 3,
          'data': encodedImage,
        },
        {
          'row': 0,
          'col': 2,
          'width_cells': 4,
          'height_cells': 3.5,
          'data': encodedImage,
        },
      ],
    });

    expect(frame.inlineImages, isEmpty);
  });

  test(
    'terminal frames ignore oversized inline image payloads before decoding',
    () {
      final oversizedPayload = 'A' * (6 * 1024 * 1024);
      final frame = TerminalFrameDiff.fromJson(<String, Object?>{
        'rows': const [
          {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': const [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'inline_images': [
          {
            'row': 0,
            'col': 2,
            'width_cells': 4,
            'height_cells': 3,
            'data': oversizedPayload,
          },
        ],
      });

      expect(frame.inlineImages, isEmpty);
    },
  );

  test('terminal frames cap inline image batches', () {
    final imageBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final encodedImage = base64.encode(imageBytes);
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'rows': const [
        {'index': 0, 'text': 'image', 'style_runs': <Object?>[]},
      ],
      'cursor': const {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 40,
      'viewport_cols': 80,
      'dirty_ranges': const [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'inline_images': [
        for (var index = 0; index < 34; index += 1)
          {
            'row': index,
            'col': 0,
            'width_cells': 1,
            'height_cells': 1,
            'data': encodedImage,
          },
      ],
    });

    expect(frame.inlineImages, hasLength(32));
    expect(frame.inlineImages.first.row, 0);
    expect(frame.inlineImages.last.row, 31);
  });

  test('terminal viewport controller caps normalized overlay state', () {
    final controller = TerminalViewportController();
    final imageBytes = Uint8List.fromList(<int>[1, 2, 3]);

    controller.updateFrame(
      TerminalFrameDiff(
        rows: const [TerminalRow(index: 0, text: 'ready')],
        cursor: const TerminalCursor(row: 0, col: 5, visible: true),
        viewportRows: 100,
        viewportCols: 80,
        dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        hyperlinks: [
          for (var index = 0; index < 4100; index += 1)
            TerminalHyperlinkRange(
              row: index % 100,
              startCol: 0,
              endCol: 1,
              uri: 'https://example.com/$index',
            ),
        ],
        inlineImages: [
          for (var index = 0; index < 40; index += 1)
            TerminalInlineImage(
              row: index % 100,
              col: 0,
              widthCells: 1,
              heightCells: 1,
              bytes: imageBytes,
            ),
        ],
      ),
    );

    expect(controller.frame.hyperlinks, hasLength(4096));
    expect(controller.frame.inlineImages, hasLength(32));
  });

  test('terminal viewport controller drops invalid direct hyperlinks', () {
    final controller = TerminalViewportController();

    controller.updateFrame(
      const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'ready')],
        cursor: TerminalCursor(row: 0, col: 5, visible: true),
        viewportRows: 1,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        hyperlinks: [
          TerminalHyperlinkRange(
            row: 0,
            startCol: -1,
            endCol: 5,
            uri: 'https://example.com/negative',
          ),
          TerminalHyperlinkRange(
            row: 0,
            startCol: 5,
            endCol: 5,
            uri: 'https://example.com/empty',
          ),
          TerminalHyperlinkRange(row: 0, startCol: 0, endCol: 1, uri: '  '),
          TerminalHyperlinkRange(
            row: 0,
            startCol: 1,
            endCol: 3,
            uri: 'https://example.com/valid',
          ),
        ],
      ),
    );

    expect(controller.frame.hyperlinks, hasLength(1));
    expect(controller.frame.hyperlinks.single.uri, 'https://example.com/valid');
  });

  test('terminal runtime falls back when JSON requests are unsupported', () {
    final runtimeBackend = _FakePtyBackend()..returnNullJsonRequests = true;
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    expect(runtime.searchText(sessionId, 'demo'), isEmpty);
    expect(
      runtime.selectionText(
        sessionId,
        const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 4),
        block: false,
      ),
      'demo',
    );
    expect(
      runtimeBackend.jsonRequests.map((request) => request['kind']),
      <String>['terminal.search_text', 'terminal.selection_text'],
    );
  });

  test(
    'ZMODEM recovery remains resolvable after the originating session closes',
    () {
      final backend = _FakePtyBackend()
        ..zmodemRecoveryPath = '/current/downloads/.report.ianvs-part';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final publishFailure = TerminalSessionZmodemEvent(
        sessionId,
        rawPayload: const <String, Object?>{
          'source': 'zmodem',
          'eventKind': 'zmodem_failed',
          'transferId': '7',
          'direction': 'receive',
          'reason': 'publish_failed',
          'recoverablePartialName': '.report.ianvs-part',
          'stagingPreserved': true,
          'recoveryToken': '0123456789abcdef0123456789abcdef',
        },
      );

      expect(runtime.tryCloseSession(sessionId), isTrue);

      expect(runtime.hasSession(sessionId), isFalse);
      final recovery = runtime.resolveZmodemRecovery(publishFailure);
      expect(recovery.status, TerminalZmodemRecoveryResolutionStatus.available);
      expect(recovery.path, '/current/downloads/.report.ianvs-part');
      expect(backend.jsonRequests.last, <String, Object?>{
        'kind': 'terminal.zmodem.resolve_recovery',
        'recoveryToken': '0123456789abcdef0123456789abcdef',
      });
      expect(
        runtime.consumeZmodemRecovery(publishFailure),
        TerminalZmodemRecoveryDisposition.success,
      );
      expect(backend.jsonRequests.last, <String, Object?>{
        'kind': 'terminal.zmodem.consume_recovery',
        'recoveryToken': '0123456789abcdef0123456789abcdef',
      });
    },
  );

  testWidgets(
    'terminal runtime controller owns sessions and viewport state without demo imports',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      expect(sessionId, '1');
      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');
      expect(runtimeBackend.lastCreateSessionJson, isNotNull);
      expect(runtimeBackend.lastCreateSessionPayload!['id'], 'runtime-1');
      expect(runtimeBackend.lastCreateSessionPayload!['name'], 'sh');
      expect(
        runtimeBackend.lastCreateSessionPayload!['launch'],
        <String, Object?>{
          'program': '/bin/sh',
          'args': const <String>[],
          'env': const <String, String>{},
          'cwd': null,
        },
      );
      expect(
        runtimeBackend.lastCreateSessionPayload!['shellIntegration'],
        <String, Object?>{'enabled': true},
      );
      final appearance =
          runtimeBackend.lastCreateSessionPayload!['appearance']!
              as Map<String, Object?>;
      final colors = appearance['colors']! as Map<String, Object?>;
      final special = colors['special']! as Map<String, Object?>;
      expect(special['background'], '#000000');
    },
  );

  testWidgets('terminal runtime prefers protobuf frame bytes when available', (
    tester,
  ) async {
    final runtimeBackend = _ProtobufFramePtyBackend(
      initialFrame: _singleRowProtobuf('protobuf demo'),
    );
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();

    expect(
      runtime.viewportFor(sessionId).frame.rows.first.text,
      'protobuf demo',
    );
    expect(runtimeBackend.takeFrameDiffProtobufCalls, 1);
    expect(runtimeBackend.takeFrameDiffCalls, 0);
  });

  testWidgets('terminal runtime can force JSON frame transport', (
    tester,
  ) async {
    final runtimeBackend = _ProtobufFramePtyBackend(
      initialFrame: _singleRowProtobuf('protobuf demo'),
    );
    final events = <Map<String, Object?>>[];
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
      frameWireFormatPreference: TerminalFrameWireFormatPreference.json,
      benchmarkEventSink: events.add,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();

    expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');
    expect(runtimeBackend.takeFrameDiffProtobufCalls, 0);
    expect(runtimeBackend.takeFrameDiffCalls, 1);
    final benchmarkEvent = events.singleWhere(
      (event) =>
          event['schema_version'] == 'ianvs-bench-dart-runtime-v1' &&
          event['wire_format'] == 'json',
    );
    expect(benchmarkEvent['raw_frame_bytes'], greaterThan(0));
    expect(benchmarkEvent['json_decode_micros'], isA<int>());
    expect(benchmarkEvent['protobuf_decode_micros'], 0);
  });

  testWidgets(
    'terminal runtime falls back to JSON when protobuf backend is unavailable',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');
      expect(runtimeBackend.takeFrameDiffCalls, 1);

      runtimeBackend.setFrame(sessionId, _singleRowSnapshot('json fallback'));
      runtime.refreshSession(sessionId);
      await tester.pump();

      expect(
        runtime.viewportFor(sessionId).frame.rows.first.text,
        'json fallback',
      );
      expect(runtimeBackend.takeFrameDiffCalls, 2);
    },
  );

  testWidgets(
    'terminal runtime does not JSON fallback while protobuf frame stream is idle',
    (tester) async {
      final runtimeBackend = _ProtobufFramePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      expect(runtimeBackend.takeFrameDiffProtobufCalls, 1);
      expect(runtimeBackend.takeFrameDiffCalls, 0);
    },
  );

  testWidgets(
    'terminal runtime skips malformed protobuf frames without reading JSON',
    (tester) async {
      final runtimeBackend = _ProtobufFramePtyBackend(
        initialFrame: _singleRowProtobuf('demo'),
      );
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');
      runtimeBackend.takeFrameDiffProtobufCalls = 0;
      runtimeBackend.takeFrameDiffCalls = 0;

      runtimeBackend
        ..enqueueRawProtobufFrame(sessionId, const <int>[0xff])
        ..setFrame(sessionId, _singleRowSnapshot('should not apply'));
      runtime.refreshSession(sessionId);
      await tester.pump();

      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');
      expect(runtimeBackend.takeFrameDiffProtobufCalls, 1);
      expect(runtimeBackend.takeFrameDiffCalls, 0);
    },
  );

  group(TerminalFrameTransportCoordinator, () {
    test('forced JSON never reads an implemented protobuf backend', () {
      final backend = _ProtobufFramePtyBackend(
        initialFrame: _singleRowProtobuf('protobuf ignored'),
      );
      final sessionId = backend.createSession('{}');
      final coordinator = TerminalFrameTransportCoordinator(
        backend: backend,
        preference: TerminalFrameWireFormatPreference.json,
      );

      final decoded = coordinator.take(sessionId);

      expect(decoded!.frame.rows.single.text, 'demo');
      expect(backend.takeFrameDiffCalls, 1);
      expect(backend.takeFrameDiffProtobufCalls, 0);
    });

    test('automatic uses protobuf only when implemented and supported', () {
      final supported = _ProtobufFramePtyBackend(
        initialFrame: _singleRowProtobuf('protobuf selected'),
      );
      final supportedSession = supported.createSession('{}');
      final supportedCoordinator = TerminalFrameTransportCoordinator(
        backend: supported,
        preference: TerminalFrameWireFormatPreference.automatic,
      );
      final unsupported = _UnsupportedProtobufFramePtyBackend();
      final unsupportedSession = unsupported.createSession('{}');
      final unsupportedCoordinator = TerminalFrameTransportCoordinator(
        backend: unsupported,
        preference: TerminalFrameWireFormatPreference.automatic,
      );
      final jsonOnly = _FakePtyBackend();
      final jsonOnlySession = jsonOnly.createSession('{}');
      final jsonOnlyCoordinator = TerminalFrameTransportCoordinator(
        backend: jsonOnly,
        preference: TerminalFrameWireFormatPreference.automatic,
      );

      expect(
        supportedCoordinator.take(supportedSession)!.frame.rows.single.text,
        'protobuf selected',
      );
      expect(supported.takeFrameDiffProtobufCalls, 1);
      expect(supported.takeFrameDiffCalls, 0);
      expect(
        unsupportedCoordinator.take(unsupportedSession)!.frame.rows.single.text,
        'demo',
      );
      expect(unsupported.takeFrameDiffProtobufCalls, 0);
      expect(unsupported.takeFrameDiffCalls, 1);
      expect(
        jsonOnlyCoordinator.take(jsonOnlySession)!.frame.rows.single.text,
        'demo',
      );
      expect(jsonOnly.takeFrameDiffCalls, 1);
    });

    test(
      'supported protobuf null and empty payloads are idle without JSON',
      () {
        final backend = _ProtobufFramePtyBackend();
        final sessionId = backend.createSession('{}');
        final coordinator = TerminalFrameTransportCoordinator(
          backend: backend,
          preference: TerminalFrameWireFormatPreference.automatic,
        );

        expect(coordinator.take(sessionId), isNull);
        backend.enqueueRawProtobufFrame(sessionId, const <int>[]);
        expect(coordinator.take(sessionId), isNull);
        expect(backend.takeFrameDiffProtobufCalls, 2);
        expect(backend.takeFrameDiffCalls, 0);
      },
    );

    test('malformed protobuf is dropped without consuming JSON', () {
      final backend = _ProtobufFramePtyBackend();
      final sessionId = backend.createSession('{}');
      backend.enqueueRawProtobufFrame(sessionId, const <int>[0xff]);
      final coordinator = TerminalFrameTransportCoordinator(
        backend: backend,
        preference: TerminalFrameWireFormatPreference.automatic,
      );

      expect(coordinator.take(sessionId), isNull);
      expect(backend.takeFrameDiffProtobufCalls, 1);
      expect(backend.takeFrameDiffCalls, 0);
    });

    test('JSON backend exceptions report the exact existing operation', () {
      final backend = _ThrowingJsonFramePtyBackend();
      final sessionId = backend.createSession('{}');
      final errors = <(String, String, Object)>[];
      final coordinator = TerminalFrameTransportCoordinator(
        backend: backend,
        preference: TerminalFrameWireFormatPreference.json,
        onRequestError: (sessionId, operation, error, stackTrace) {
          errors.add((sessionId, operation, error));
        },
      );

      expect(coordinator.take(sessionId), isNull);
      expect(backend.takeFrameDiffJsonAttempts, 1);
      expect(backend.takeFrameDiffJsonSessions, <String>[sessionId]);
      expect(errors, hasLength(1));
      expect(errors.single.$1, sessionId);
      expect(errors.single.$2, 'takeFrameDiffJson');
      expect(errors.single.$3, isA<StateError>());
    });

    test('protobuf backend exceptions report the exact existing operation', () {
      final backend = _ThrowingProtobufFramePtyBackend();
      final sessionId = backend.createSession('{}');
      final errors = <(String, String, Object)>[];
      final coordinator = TerminalFrameTransportCoordinator(
        backend: backend,
        preference: TerminalFrameWireFormatPreference.automatic,
        onRequestError: (sessionId, operation, error, stackTrace) {
          errors.add((sessionId, operation, error));
        },
      );

      expect(coordinator.take(sessionId), isNull);
      expect(backend.takeFrameDiffProtobufAttempts, 1);
      expect(backend.takeFrameDiffProtobufSessions, <String>[sessionId]);
      expect(errors, hasLength(1));
      expect(errors.single.$1, sessionId);
      expect(errors.single.$2, 'takeFrameDiffProtobuf');
      expect(errors.single.$3, isA<StateError>());
      expect(backend.takeFrameDiffCalls, 0);
    });
  });

  testWidgets(
    'terminal runtime controller refreshes after input and scrolling when polling is disabled',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      expect(runtimeBackend.takeFrameDiffCalls, 1);
      expect(runtimeBackend.pollEventsCalls, 1);

      runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));
      runtime.scrollViewport(sessionId, 1);
      runtime.scrollViewportTo(sessionId, 2);
      await tester.pump();

      expect(runtimeBackend.takeFrameDiffCalls, 2);
      expect(runtimeBackend.pollEventsCalls, 2);
    },
  );

  testWidgets(
    'terminal runtime scrolls to the live cursor before non-empty input',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.setFrame(sessionId, <String, Object?>{
        ..._singleRowSnapshot('history prompt'),
        'scrollback_offset': 8,
        'scrollback_max_offset': 8,
      });
      runtime.refreshSession(sessionId);
      await tester.pump();

      expect(runtime.viewportFor(sessionId).frame.scrollbackOffset, 8);
      runtimeBackend.scrollToCalls.clear();
      runtimeBackend.writeCalls.clear();

      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x41]));
      await tester.pump();

      expect(runtimeBackend.scrollToCalls, <(String, int)>[(sessionId, 0)]);
      expect(
        runtimeBackend.writeCalls.map(utf8.decode).toList(growable: false),
        <String>['A'],
      );
    },
  );

  testWidgets(
    'terminal runtime controller refreshes immediately after polling idle',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final viewport = runtime.viewportFor(sessionId);
        expect(runtimeBackend.takeFrameDiffCalls, 1);
        expect(viewport.frame.rows.first.text, 'demo');

        runtimeBackend.clearFrame(sessionId);
        await tester.pump(const Duration(milliseconds: 34));
        expect(runtimeBackend.takeFrameDiffCalls, 2);

        runtimeBackend.setFrame(sessionId, _singleRowSnapshot('after idle'));
        runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));

        expect(runtimeBackend.takeFrameDiffCalls, 3);
        expect(viewport.frame.rows.first.text, 'after idle');
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime coalesces input bursts into one low-latency probe',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final diagnosticEvents = <Map<String, Object?>>[];
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        benchmarkEventSink: diagnosticEvents.add,
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final viewport = runtime.viewportFor(sessionId);
        final fullPollCountBeforeBurst = runtime
            .refreshPolicySnapshotFor(sessionId)
            .fullPollCount;
        diagnosticEvents.clear();
        runtimeBackend.setFrame(sessionId, _singleRowSnapshot('coalesced'));

        runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));
        runtime.sendInput(sessionId, Uint8List.fromList(const [0x42]));
        runtime.scrollViewport(sessionId, 1);

        expect(runtimeBackend.takeFrameDiffCalls, 1);
        expect(viewport.frame.rows.first.text, 'demo');
        final requestedEvents = diagnosticEvents.where(
          (event) =>
              event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
              event['event'] == 'full_poll_requested',
        );
        expect(requestedEvents, hasLength(1));
        expect(
          requestedEvents.single['full_poll_count'],
          fullPollCountBeforeBurst + 1,
        );
        expect(
          runtime.refreshPolicySnapshotFor(sessionId).fullPollCount,
          fullPollCountBeforeBurst + 1,
        );
        final refreshId = requestedEvents.single['refresh_id'];
        expect(requestedEvents.single['request_reason'], 'input');

        await tester.pump(const Duration(milliseconds: 3));
        expect(runtimeBackend.takeFrameDiffCalls, 1);

        await tester.pump(const Duration(milliseconds: 1));
        expect(runtimeBackend.takeFrameDiffCalls, 2);
        expect(viewport.frame.rows.first.text, 'coalesced');
        expect(
          diagnosticEvents
              .where(
                (event) =>
                    event['schema_version'] ==
                        'ianvs-terminal-refresh-policy-v1' &&
                    event['refresh_id'] == refreshId,
              )
              .map((event) => event['event']),
          <String>[
            'full_poll_requested',
            'refresh_started',
            'frame_taken',
            'frame_applied',
            'refresh_result',
          ],
        );
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime consumes a delayed input hint before the 33ms tick',
    (tester) async {
      final runtimeBackend = _RefreshHintPtyBackend();
      final diagnosticEvents = <Map<String, Object?>>[];
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        benchmarkEventSink: diagnosticEvents.add,
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final viewport = runtime.viewportFor(sessionId);
        runtimeBackend.setFrame(
          sessionId,
          _singleRowSnapshot('low latency echo'),
        );
        diagnosticEvents.clear();

        runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));
        await tester.pump(const Duration(milliseconds: 4));

        expect(runtimeBackend.takeFrameDiffCalls, 1);
        expect(viewport.frame.rows.first.text, 'demo');

        runtimeBackend.hintFlags = PtyRefreshHintFlags.frameDirty;
        await tester.pump(const Duration(milliseconds: 4));

        expect(runtimeBackend.takeFrameDiffCalls, 2);
        expect(viewport.frame.rows.first.text, 'low latency echo');
        expect(runtimeBackend.refreshHintCalls, 2);
        expect(
          diagnosticEvents
              .where(
                (event) =>
                    event['schema_version'] ==
                        'ianvs-terminal-refresh-policy-v1' &&
                    event['event'] == 'full_poll_requested',
              )
              .single['request_reason'],
          'input',
        );
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime keeps refreshing when refresh diagnostics throw',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final diagnosticEvents = <Map<String, Object?>>[];
      var throwOnRefreshLifecycle = false;
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        benchmarkEventSink: (event) {
          if (event['schema_version'] != 'ianvs-terminal-refresh-policy-v1') {
            return;
          }
          diagnosticEvents.add(event);
          if (throwOnRefreshLifecycle &&
              event['event'] != 'full_poll_requested') {
            throw StateError('refresh diagnostic sink failed');
          }
        },
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        diagnosticEvents.clear();
        runtimeBackend.setFrame(
          sessionId,
          _singleRowSnapshot('throwing diagnostic'),
        );

        throwOnRefreshLifecycle = true;
        runtime.refreshSession(sessionId);
        await tester.pump();
        final uncaughtSinkError = tester.takeException();

        throwOnRefreshLifecycle = false;
        diagnosticEvents.clear();
        runtimeBackend.setFrame(
          sessionId,
          _singleRowSnapshot('after throwing diagnostic'),
        );
        runtime.refreshSession(sessionId);
        await tester.pump();

        final refreshEvents = diagnosticEvents
            .where(
              (event) =>
                  event['schema_version'] == 'ianvs-terminal-refresh-policy-v1',
            )
            .toList(growable: false);
        final refreshIds = refreshEvents
            .map((event) => event['refresh_id'])
            .whereType<int>()
            .toSet();
        expect(
          <Object?>[
            uncaughtSinkError,
            runtimeBackend.takeFrameDiffCalls,
            runtime.viewportFor(sessionId).frame.rows.first.text,
            refreshIds.length,
            refreshEvents.map((event) => event['event']).toList(),
          ],
          <Object?>[
            null,
            3,
            'after throwing diagnostic',
            1,
            <Object?>[
              'full_poll_requested',
              'refresh_started',
              'frame_taken',
              'frame_applied',
              'refresh_result',
            ],
          ],
        );
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime isolates async refreshes when a session id is reused',
    (tester) async {
      final oldResize = Completer<void>();
      final newResize = Completer<void>();
      final runtimeBackend = _FakePtyBackend()..forcedSessionId = 'reused';
      final diagnosticEvents = <Map<String, Object?>>[];
      var resizeRequestCount = 0;
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        resizeWindowBy: ({required widthDelta, required heightDelta}) {
          resizeRequestCount += 1;
          return resizeRequestCount == 1 ? oldResize.future : newResize.future;
        },
        benchmarkEventSink: diagnosticEvents.add,
      );
      try {
        final oldSessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        expect(
          runtime.resizeSession(oldSessionId, const Size(180, 144), 1),
          isTrue,
        );
        runtimeBackend.setFrame(
          oldSessionId,
          _singleRowSnapshot('stale old frame'),
        );
        runtimeBackend.enqueueEvent(
          oldSessionId,
          PtyEvent(
            kind: 'resize',
            sessionId: oldSessionId,
            payload: const <String, Object?>{'cols': 90, 'rows': 30},
          ),
        );
        runtime.refreshSession(oldSessionId);
        await tester.pump();
        expect(resizeRequestCount, 1);

        runtime.closeSession(oldSessionId);
        final newSessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/zsh'),
          ),
        );
        expect(newSessionId, oldSessionId);
        expect(
          runtime.resizeSession(newSessionId, const Size(180, 144), 1),
          isTrue,
        );
        diagnosticEvents.clear();

        runtimeBackend.setFrame(
          newSessionId,
          _singleRowSnapshot('fresh new frame'),
        );
        runtimeBackend.enqueueEvent(
          newSessionId,
          PtyEvent(
            kind: 'resize',
            sessionId: newSessionId,
            payload: const <String, Object?>{'cols': 100, 'rows': 40},
          ),
        );
        runtime.refreshSession(newSessionId);
        await tester.pump();
        expect(resizeRequestCount, 2);

        runtime.sendInput(newSessionId, Uint8List(0));
        oldResize.complete();
        await tester.pump();

        runtime.refreshSession(newSessionId);
        await tester.pump();

        final eventsBeforeNewRefreshCompletes = diagnosticEvents
            .where(
              (event) =>
                  event['schema_version'] == 'ianvs-terminal-refresh-policy-v1',
            )
            .toList(growable: false);
        final newRefreshId = eventsBeforeNewRefreshCompletes.firstWhere(
          (event) => event['event'] == 'refresh_started',
        )['refresh_id'];
        expect(
          <Object?>[
            runtimeBackend.takeFrameDiffCalls,
            runtime.viewportFor(newSessionId).frame.rows.first.text,
            eventsBeforeNewRefreshCompletes.any(
              (event) => event['event'] == 'frame_applied',
            ),
            eventsBeforeNewRefreshCompletes.any(
              (event) => event['event'] == 'refresh_result',
            ),
          ],
          <Object?>[4, 'demo', false, false],
        );

        newResize.complete();
        await tester.pump();
        final newRefreshResults = diagnosticEvents.where(
          (event) =>
              event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
              event['event'] == 'refresh_result' &&
              event['refresh_id'] == newRefreshId,
        );
        expect(
          <Object?>[
            runtime.viewportFor(newSessionId).frame.rows.first.text,
            newRefreshResults.length,
          ],
          <Object?>['fresh new frame', 1],
        );
      } finally {
        if (!oldResize.isCompleted) {
          oldResize.complete();
        }
        if (!newResize.isCompleted) {
          newResize.complete();
        }
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime ignores stale async event chains before a reused id exit',
    (tester) async {
      final oldResize = Completer<void>();
      final runtimeBackend = _FakePtyBackend()..forcedSessionId = 'reused';
      final exitEvents = <TerminalSessionExitEvent>[];
      var resizeRequestCount = 0;
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        resizeWindowBy: ({required widthDelta, required heightDelta}) {
          resizeRequestCount += 1;
          return oldResize.future;
        },
        enableSessionPolling: false,
      );
      final subscription = runtime.events
          .where((event) => event is TerminalSessionExitEvent)
          .cast<TerminalSessionExitEvent>()
          .listen(exitEvents.add);
      addTearDown(subscription.cancel);
      try {
        final oldSessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        expect(
          runtime.resizeSession(oldSessionId, const Size(180, 144), 1),
          isTrue,
        );
        runtimeBackend.enqueueEvent(
          oldSessionId,
          PtyEvent(
            kind: 'resize',
            sessionId: oldSessionId,
            payload: const <String, Object?>{'cols': 90, 'rows': 30},
          ),
        );
        runtimeBackend.enqueueEvent(
          oldSessionId,
          PtyEvent(
            kind: 'exit',
            sessionId: oldSessionId,
            payload: const <String, Object?>{'code': 23},
          ),
        );
        runtime.refreshSession(oldSessionId);
        await tester.pump();
        expect(resizeRequestCount, 1);

        runtime.closeSession(oldSessionId);
        final newSessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/zsh'),
          ),
        );
        expect(newSessionId, oldSessionId);
        exitEvents.clear();

        oldResize.complete();
        await tester.pump();

        expect(
          <Object?>[
            runtime.hasSession(newSessionId),
            exitEvents.map((event) => event.exitCode).toList(),
          ],
          <Object?>[true, <int>[]],
        );
      } finally {
        if (!oldResize.isCompleted) {
          oldResize.complete();
        }
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime ignores stale clipboard paste continuations after id reuse',
    (tester) async {
      final clipboardText = Completer<String>();
      final runtimeBackend = _FakePtyBackend()..forcedSessionId = 'reused';
      final clipboardEvents = <TerminalSessionClipboardEvent>[];
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () => clipboardText.future,
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
      );
      final subscription = runtime.events
          .where((event) => event is TerminalSessionClipboardEvent)
          .cast<TerminalSessionClipboardEvent>()
          .listen(clipboardEvents.add);
      addTearDown(subscription.cancel);
      try {
        final oldSessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        runtimeBackend.enqueueEvent(
          oldSessionId,
          PtyEvent(
            kind: 'clipboard_paste_request',
            sessionId: oldSessionId,
            payload: const <String, Object?>{'selection': 'c'},
          ),
        );
        runtime.refreshSession(oldSessionId);
        await tester.pump();

        runtime.closeSession(oldSessionId);
        final newSessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/zsh'),
          ),
        );
        expect(newSessionId, oldSessionId);
        runtimeBackend.writeCalls.clear();
        clipboardEvents.clear();

        clipboardText.complete('stale clipboard response');
        await tester.pump();

        expect(
          <Object?>[
            runtime.hasSession(newSessionId),
            runtimeBackend.writeCalls.map(utf8.decode).toList(),
            clipboardEvents
                .map((event) => (event.operation, event.decision))
                .toList(),
          ],
          <Object?>[
            true,
            <String>[],
            <(TerminalClipboardOperation, TerminalClipboardDecision)>[],
          ],
        );
      } finally {
        if (!clipboardText.isCompleted) {
          clipboardText.complete('cleanup');
        }
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime preserves new deferred refresh deduplication after id reuse',
    (tester) async {
      final runtimeBackend = _FakePtyBackend()..forcedSessionId = 'reused';
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      try {
        final oldSessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        runtime.sendInput(oldSessionId, Uint8List(0));

        runtime.closeSession(oldSessionId);
        final newSessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/zsh'),
          ),
        );
        expect(newSessionId, oldSessionId);
        scheduleMicrotask(() {
          runtime.sendInput(newSessionId, Uint8List(0));
        });
        runtime.sendInput(newSessionId, Uint8List(0));

        await tester.pump();

        expect(runtimeBackend.takeFrameDiffCalls, 3);
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets('terminal runtime controller backs off repeated idle polling', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    var monotonicNow = Duration.zero;
    Future<void> pumpTick() {
      monotonicNow += const Duration(milliseconds: 33);
      return tester.pump(const Duration(milliseconds: 33));
    }

    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      monotonicNow: () => monotonicNow,
    );
    try {
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      runtimeBackend.clearFrame(sessionId);
      monotonicNow = const Duration(milliseconds: 500);
      final callsBeforeIdle = runtimeBackend.takeFrameDiffCalls;

      await pumpTick();
      expect(runtimeBackend.takeFrameDiffCalls, callsBeforeIdle + 1);
      expect(runtimeBackend.pollEventsCalls, callsBeforeIdle + 1);

      await pumpTick();
      expect(runtimeBackend.takeFrameDiffCalls, callsBeforeIdle + 2);
      expect(runtimeBackend.pollEventsCalls, callsBeforeIdle + 2);

      await pumpTick();
      await pumpTick();
      await pumpTick();
      expect(runtimeBackend.takeFrameDiffCalls, callsBeforeIdle + 2);
      expect(runtimeBackend.pollEventsCalls, callsBeforeIdle + 2);

      runtimeBackend.setFrame(sessionId, _singleRowSnapshot('wake'));
      runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));

      expect(runtimeBackend.takeFrameDiffCalls, callsBeforeIdle + 3);
      expect(runtimeBackend.pollEventsCalls, callsBeforeIdle + 3);
      expect(viewport.frame.rows.first.text, 'wake');
    } finally {
      runtime.dispose();
    }
  });

  testWidgets(
    'terminal runtime controller expands idle polling backoff until activity',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      var monotonicNow = Duration.zero;
      Future<void> pumpTick() {
        monotonicNow += const Duration(milliseconds: 33);
        return tester.pump(const Duration(milliseconds: 33));
      }

      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        monotonicNow: () => monotonicNow,
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final viewport = runtime.viewportFor(sessionId);
        runtimeBackend.clearFrame(sessionId);
        monotonicNow = const Duration(milliseconds: 500);
        final callsBeforeIdle = runtimeBackend.takeFrameDiffCalls;

        await pumpTick();
        expect(runtimeBackend.takeFrameDiffCalls, callsBeforeIdle + 1);
        expect(
          runtime.refreshPolicySnapshotFor(sessionId).pumpMetrics.currentDelay,
          const Duration(milliseconds: 33),
        );

        await pumpTick();
        expect(runtimeBackend.takeFrameDiffCalls, callsBeforeIdle + 2);
        expect(
          runtime.refreshPolicySnapshotFor(sessionId).pumpMetrics.currentDelay,
          const Duration(milliseconds: 132),
        );

        for (
          var tick = 0;
          tick < 5 &&
              runtime
                      .refreshPolicySnapshotFor(sessionId)
                      .pumpMetrics
                      .currentDelay !=
                  const Duration(milliseconds: 264);
          tick += 1
        ) {
          await pumpTick();
        }
        expect(runtimeBackend.takeFrameDiffCalls, callsBeforeIdle + 3);

        for (
          var tick = 0;
          tick < 9 &&
              runtime
                      .refreshPolicySnapshotFor(sessionId)
                      .pumpMetrics
                      .currentDelay !=
                  const Duration(milliseconds: 396);
          tick += 1
        ) {
          await pumpTick();
        }
        expect(runtimeBackend.takeFrameDiffCalls, callsBeforeIdle + 4);

        runtimeBackend.setFrame(sessionId, _singleRowSnapshot('wake'));
        runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));

        expect(runtimeBackend.takeFrameDiffCalls, callsBeforeIdle + 5);
        expect(viewport.frame.rows.first.text, 'wake');
      } finally {
        runtime.dispose();
      }
    },
  );

  test('terminal runtime counts the creation full refresh request', () {
    final runtimeBackend = _FakePtyBackend();
    final diagnostics = <Map<String, Object?>>[];
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      benchmarkEventSink: diagnostics.add,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    final requested = diagnostics.singleWhere(
      (event) =>
          event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
          event['event'] == 'full_poll_requested',
    );
    expect(requested['full_poll_count'], 1);
    expect(runtime.refreshPolicySnapshotFor(sessionId).fullPollCount, 1);
  });

  test(
    'terminal runtime counts a new explicit full refresh request once',
    () async {
      final runtimeBackend = _FakePtyBackend();
      final diagnostics = <Map<String, Object?>>[];
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        benchmarkEventSink: diagnostics.add,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final fullPollCountBeforeRefresh = runtime
          .refreshPolicySnapshotFor(sessionId)
          .fullPollCount;
      diagnostics.clear();

      runtime.refreshSession(sessionId);

      final requested = diagnostics.singleWhere(
        (event) =>
            event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
            event['event'] == 'full_poll_requested',
      );
      expect(requested['full_poll_count'], fullPollCountBeforeRefresh + 1);
      expect(
        runtime.refreshPolicySnapshotFor(sessionId).fullPollCount,
        fullPollCountBeforeRefresh + 1,
      );
    },
  );

  testWidgets(
    'terminal runtime traces skipped ticks and full refresh lifecycle monotonically',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final diagnosticEvents = <Map<String, Object?>>[];
      var monotonicNow = Duration.zero;
      Future<void> pumpTick() {
        monotonicNow += const Duration(milliseconds: 34);
        return tester.pump(const Duration(milliseconds: 34));
      }

      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        benchmarkEventSink: diagnosticEvents.add,
        monotonicNow: () => monotonicNow,
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        diagnosticEvents.clear();
        runtimeBackend.clearFrame(sessionId);

        Map<String, Object?>? maximumEmptyResult;
        for (var tick = 0; tick < 40 && maximumEmptyResult == null; tick += 1) {
          await pumpTick();
          final refreshEvents = diagnosticEvents.where(
            (event) =>
                event['schema_version'] == 'ianvs-terminal-refresh-policy-v1',
          );
          for (final event in refreshEvents) {
            if (event['event'] == 'refresh_result' &&
                event['had_activity'] == false &&
                event['current_delay_micros'] == 396000) {
              maximumEmptyResult = event;
            }
          }
        }
        expect(maximumEmptyResult, isNotNull);
        expect(maximumEmptyResult!['backoff_skip_ticks'], 11);
        expect(maximumEmptyResult['hint_poll_count'], 0);
        expect(maximumEmptyResult['refresh_class'], 'idle');

        final emptyRefreshId = maximumEmptyResult['refresh_id'];
        final emptyLifecycle = diagnosticEvents.where(
          (event) =>
              event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
              event['refresh_id'] == emptyRefreshId,
        );
        expect(
          emptyLifecycle.map((event) => event['event']),
          containsAllInOrder(<String>[
            'full_poll_requested',
            'refresh_started',
            'frame_taken',
            'refresh_result',
          ]),
        );
        expect(
          emptyLifecycle.any((event) => event['event'] == 'frame_applied'),
          isFalse,
        );

        diagnosticEvents.clear();
        await pumpTick();
        runtimeBackend.setFrame(sessionId, _singleRowSnapshot('bounded wake'));
        for (
          var tick = 0;
          tick < 20 &&
              !diagnosticEvents.any(
                (event) =>
                    event['schema_version'] ==
                        'ianvs-terminal-refresh-policy-v1' &&
                    event['event'] == 'frame_applied',
              );
          tick += 1
        ) {
          await pumpTick();
        }

        final refreshEvents = diagnosticEvents
            .where(
              (event) =>
                  event['schema_version'] == 'ianvs-terminal-refresh-policy-v1',
            )
            .toList(growable: false);
        final requestedIndex = refreshEvents.indexWhere(
          (event) => event['event'] == 'full_poll_requested',
        );
        expect(requestedIndex, greaterThan(0));
        final skippedIndex = refreshEvents.lastIndexWhere(
          (event) => event['event'] == 'poll_tick_skipped',
          requestedIndex - 1,
        );
        expect(skippedIndex, greaterThanOrEqualTo(0));

        final refreshId = refreshEvents[requestedIndex]['refresh_id'];
        final lifecycle = refreshEvents
            .where((event) => event['refresh_id'] == refreshId)
            .toList(growable: false);
        expect(
          <Object?>[
            refreshEvents[skippedIndex]['event'],
            ...lifecycle.map((event) => event['event']),
          ],
          <String>[
            'poll_tick_skipped',
            'full_poll_requested',
            'refresh_started',
            'frame_taken',
            'frame_applied',
            'refresh_result',
          ],
        );

        for (final event in <Map<String, Object?>>[
          refreshEvents[skippedIndex],
          ...lifecycle,
        ]) {
          expect(event['session_id'], sessionId);
          expect(event['monotonic_micros'], isA<int>());
          expect(event['refresh_class'], isA<String>());
          expect(event['empty_refresh_count'], isA<int>());
          expect(event['backoff_skip_ticks'], isA<int>());
          expect(event['current_delay_micros'], isA<int>());
          expect(event['hint_poll_count'], 0);
          expect(event['full_poll_count'], isA<int>());
          expect(event, contains('refresh_requested_micros'));
          expect(event, contains('refresh_started_micros'));
          expect(event, contains('frame_taken_micros'));
          expect(event, contains('frame_applied_micros'));
        }

        final requested = lifecycle.singleWhere(
          (event) => event['event'] == 'full_poll_requested',
        );
        final started = lifecycle.singleWhere(
          (event) => event['event'] == 'refresh_started',
        );
        final taken = lifecycle.singleWhere(
          (event) => event['event'] == 'frame_taken',
        );
        final applied = lifecycle.singleWhere(
          (event) => event['event'] == 'frame_applied',
        );
        final result = lifecycle.singleWhere(
          (event) => event['event'] == 'refresh_result',
        );
        expect(
          requested['refresh_requested_micros']! as int,
          lessThanOrEqualTo(started['refresh_started_micros']! as int),
        );
        expect(
          started['refresh_started_micros']! as int,
          lessThanOrEqualTo(taken['frame_taken_micros']! as int),
        );
        expect(
          taken['frame_taken_micros']! as int,
          lessThanOrEqualTo(applied['frame_applied_micros']! as int),
        );
        expect(result['received_frame'], isTrue);
        expect(result['had_activity'], isTrue);
        expect(result['event_count'], 0);
        expect(result['current_delay_micros'], 33000);
        expect(result['backoff_skip_ticks'], 0);
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime interactive modes keep full polling every 33ms',
    (tester) async {
      for (final scenario in <String, TerminalFrameModes>{
        'focused': TerminalFrameModes.empty,
        'alternate': const TerminalFrameModes(alternateScreen: true),
        'mouse': const TerminalFrameModes(mouseMode: 'any_event'),
      }.entries) {
        final runtimeBackend = _FakePtyBackend();
        final diagnostics = <Map<String, Object?>>[];
        var monotonicNow = Duration.zero;
        Future<void> pumpTick() {
          monotonicNow += const Duration(milliseconds: 33);
          return tester.pump(const Duration(milliseconds: 33));
        }

        final runtime = TerminalRuntimeController(
          backend: runtimeBackend,
          copyToClipboard: (_) async {},
          readClipboard: () async => '',
          benchmarkEventSink: diagnostics.add,
          monotonicNow: () => monotonicNow,
        );
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        await tester.pump();
        runtimeBackend.clearFrame(sessionId);
        runtime.setSessionActive(sessionId, active: true);
        if (scenario.key == 'focused') {
          runtime.setSessionFocused(sessionId, focused: true);
        } else {
          monotonicNow = const Duration(seconds: 1);
          runtimeBackend.setFrame(sessionId, <String, Object?>{
            ..._singleRowSnapshot('${scenario.key} mode'),
            'modes': <String, Object?>{
              'alternate_screen': scenario.value.alternateScreen,
              'mouse_mode': scenario.value.mouseMode,
            },
          });
          runtime.refreshSession(sessionId);
          runtimeBackend.clearFrame(sessionId);
        }
        diagnostics.clear();
        final callsBefore = runtimeBackend.takeFrameDiffCalls;

        for (var tick = 0; tick < 8; tick += 1) {
          await pumpTick();
        }

        expect(
          runtimeBackend.takeFrameDiffCalls - callsBefore,
          8,
          reason: '${scenario.key} must full-poll on every 33ms tick',
        );
        final results = diagnostics
            .where((event) => event['event'] == 'refresh_result')
            .toList(growable: false);
        expect(results, hasLength(8));
        for (final result in results) {
          expect(result['refresh_class'], 'interactive');
          expect(result['current_delay_micros'], 33000);
          expect(result['backoff_skip_ticks'], 0);
        }
        runtime.dispose();
      }
    },
  );

  testWidgets('terminal runtime streaming keeps full polling every 33ms', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final diagnostics = <Map<String, Object?>>[];
    var monotonicNow = Duration.zero;
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      benchmarkEventSink: diagnostics.add,
      monotonicNow: () => monotonicNow,
    );
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    runtime.setSessionActive(sessionId, active: false);
    monotonicNow = const Duration(seconds: 1);
    runtimeBackend.setFrame(sessionId, _singleRowSnapshot('stream one'));
    runtime.refreshSession(sessionId);
    runtimeBackend.clearFrame(sessionId);
    monotonicNow += const Duration(milliseconds: 50);
    runtimeBackend.setFrame(sessionId, _singleRowSnapshot('stream two'));
    runtime.refreshSession(sessionId);
    runtimeBackend.clearFrame(sessionId);
    expect(
      runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
      TerminalRefreshClass.streaming,
    );
    diagnostics.clear();
    final callsBefore = runtimeBackend.takeFrameDiffCalls;

    for (var tick = 0; tick < 6; tick += 1) {
      monotonicNow += const Duration(milliseconds: 33);
      await tester.pump(const Duration(milliseconds: 33));
    }

    expect(runtimeBackend.takeFrameDiffCalls - callsBefore, 6);
    final results = diagnostics
        .where((event) => event['event'] == 'refresh_result')
        .toList(growable: false);
    expect(results, hasLength(6));
    for (final result in results) {
      expect(result['refresh_class'], 'streaming');
      expect(result['current_delay_micros'], 33000);
      expect(result['backoff_skip_ticks'], 0);
    }
    runtime.dispose();
  });

  testWidgets(
    'terminal runtime native hint bypasses deadline with complete lifecycle',
    (tester) async {
      final runtimeBackend = _RefreshHintPtyBackend();
      final diagnostics = <Map<String, Object?>>[];
      var monotonicNow = Duration.zero;
      Future<void> pump(Duration duration) {
        monotonicNow += duration;
        return tester.pump(duration);
      }

      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        benchmarkEventSink: diagnostics.add,
        monotonicNow: () => monotonicNow,
      );

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.clearFrame(sessionId);
      runtime.setSessionActive(sessionId, active: false);
      while (runtime
              .refreshPolicySnapshotFor(sessionId)
              .pumpMetrics
              .currentDelay !=
          const Duration(milliseconds: 132)) {
        await pump(const Duration(milliseconds: 33));
      }
      final callsBeforeHint = runtimeBackend.takeFrameDiffCalls;
      final fullPollBeforeHint =
          diagnostics
                  .where(
                    (event) =>
                        event['schema_version'] ==
                            'ianvs-terminal-refresh-policy-v1' &&
                        event['event'] == 'refresh_result',
                  )
                  .last['full_poll_count']!
              as int;
      diagnostics.clear();

      runtimeBackend
        ..setFrame(sessionId, _singleRowSnapshot('hint wake'))
        ..hintFlags = 1;
      for (
        var tick = 0;
        tick < 2 && runtimeBackend.takeFrameDiffCalls == callsBeforeHint;
        tick += 1
      ) {
        await pump(const Duration(milliseconds: 33));
      }

      expect(runtimeBackend.takeFrameDiffCalls, callsBeforeHint + 1);
      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'hint wake');
      final refreshEvents = diagnostics
          .where(
            (event) =>
                event['schema_version'] == 'ianvs-terminal-refresh-policy-v1',
          )
          .toList(growable: false);
      final requested = refreshEvents.singleWhere(
        (event) => event['event'] == 'full_poll_requested',
      );
      final refreshId = requested['refresh_id'];
      final lifecycle = refreshEvents
          .where((event) => event['refresh_id'] == refreshId)
          .toList(growable: false);
      expect(lifecycle.map((event) => event['event']), <String>[
        'full_poll_requested',
        'refresh_started',
        'frame_taken',
        'frame_applied',
        'refresh_result',
      ]);
      expect(requested['request_reason'], 'native_hint');
      expect(requested['hint_poll_count'], greaterThan(0));
      expect(requested['full_poll_count'], fullPollBeforeHint + 1);
      final timestamps = lifecycle
          .map((event) => event['monotonic_micros']! as int)
          .toList(growable: false);
      expect(timestamps, orderedEquals(timestamps.toList()..sort()));
      runtime.dispose();
    },
  );

  testWidgets(
    'terminal runtime false and unknown hints preserve bounded deadline fallback',
    (tester) async {
      for (final flags in <int>[0, 0x80000000]) {
        final runtimeBackend = _RefreshHintPtyBackend();
        final diagnostics = <Map<String, Object?>>[];
        final runtime = TerminalRuntimeController(
          backend: runtimeBackend,
          copyToClipboard: (_) async {},
          readClipboard: () async => '',
          benchmarkEventSink: diagnostics.add,
        );
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        runtimeBackend.clearFrame(sessionId);
        runtime.setSessionActive(sessionId, active: false);
        while (runtime
                .refreshPolicySnapshotFor(sessionId)
                .pumpMetrics
                .currentDelay !=
            const Duration(milliseconds: 132)) {
          await tester.pump(const Duration(milliseconds: 33));
        }
        final callsBeforeFallback = runtimeBackend.takeFrameDiffCalls;
        diagnostics.clear();

        runtimeBackend
          ..setFrame(sessionId, _singleRowSnapshot('deadline fallback'))
          ..hintFlags = flags;
        for (
          var tick = 0;
          tick < 5 && runtimeBackend.takeFrameDiffCalls == callsBeforeFallback;
          tick += 1
        ) {
          await tester.pump(const Duration(milliseconds: 33));
        }
        expect(runtimeBackend.takeFrameDiffCalls, callsBeforeFallback + 1);
        expect(
          runtime.viewportFor(sessionId).frame.rows.first.text,
          'deadline fallback',
        );
        expect(runtimeBackend.refreshHintCalls, greaterThan(0));
        expect(
          diagnostics.any((event) => event['request_reason'] == 'native_hint'),
          isFalse,
        );
        expect(
          diagnostics.any((event) => event['request_reason'] == 'deadline'),
          isTrue,
        );
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime labels maximum idle fallback as idle deadline',
    (tester) async {
      final runtimeBackend = _RefreshHintPtyBackend();
      final diagnostics = <Map<String, Object?>>[];
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        benchmarkEventSink: diagnostics.add,
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.clearFrame(sessionId);
      runtime.setSessionFocused(sessionId, focused: false);

      for (var tick = 0; tick < 30; tick += 1) {
        final snapshot = runtime.refreshPolicySnapshotFor(sessionId);
        if (snapshot.refreshClass == TerminalRefreshClass.idle &&
            snapshot.pumpMetrics.currentDelay ==
                const Duration(milliseconds: 132)) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(
        runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
        TerminalRefreshClass.idle,
      );
      final callsBeforeFallback = runtimeBackend.takeFrameDiffCalls;
      diagnostics.clear();
      runtimeBackend.setFrame(
        sessionId,
        _singleRowSnapshot('idle deadline fallback'),
      );

      for (
        var tick = 0;
        tick < 13 && runtimeBackend.takeFrameDiffCalls == callsBeforeFallback;
        tick += 1
      ) {
        await tester.pump(const Duration(milliseconds: 33));
      }

      expect(runtimeBackend.takeFrameDiffCalls, callsBeforeFallback + 1);
      expect(
        diagnostics.any((event) => event['request_reason'] == 'idle_deadline'),
        isTrue,
      );
      runtime.dispose();
    },
  );

  testWidgets(
    'terminal runtime disables throwing hints and falls back to full polling',
    (tester) async {
      final runtimeBackend = _RefreshHintPtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      final errors = <TerminalSessionBackendErrorEvent>[];
      final subscription = runtime.events
          .where((event) => event is TerminalSessionBackendErrorEvent)
          .cast<TerminalSessionBackendErrorEvent>()
          .listen(errors.add);
      addTearDown(subscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.clearFrame(sessionId);
      runtime.setSessionActive(sessionId, active: false);
      await tester.pump(const Duration(milliseconds: 34));
      await tester.pump(const Duration(milliseconds: 34));
      runtimeBackend.throwOnRefreshHint = true;

      await tester.pump(const Duration(milliseconds: 34));
      expect(errors.single.operation, 'refreshHintFlags');
      final hintCallsAfterError = runtimeBackend.refreshHintCalls;

      runtimeBackend
        ..throwOnRefreshHint = false
        ..setFrame(sessionId, _singleRowSnapshot('error fallback'));
      for (
        var tick = 0;
        tick < 12 &&
            runtime.viewportFor(sessionId).frame.rows.first.text !=
                'error fallback';
        tick += 1
      ) {
        await tester.pump(const Duration(milliseconds: 33));
      }

      expect(runtimeBackend.refreshHintCalls, hintCallsAfterError);
      expect(
        runtime.viewportFor(sessionId).frame.rows.first.text,
        'error fallback',
      );
      runtime.dispose();
    },
  );

  testWidgets(
    'terminal runtime isolates throwing hints with exact per-session counters',
    (tester) async {
      final runtimeBackend = _RefreshHintPtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      final errors = <TerminalSessionBackendErrorEvent>[];
      final subscription = runtime.events
          .where((event) => event is TerminalSessionBackendErrorEvent)
          .cast<TerminalSessionBackendErrorEvent>()
          .listen(errors.add);
      addTearDown(subscription.cancel);

      final first = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final second = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/zsh'),
        ),
      );
      runtimeBackend
        ..clearFrame(first)
        ..clearFrame(second)
        ..throwingSessions.add(first)
        ..hintFlagsBySession[second] = 1;

      await tester.pump(const Duration(milliseconds: 33));

      expect(errors, hasLength(1));
      expect(errors.single.sessionId, first);
      expect(errors.single.operation, 'refreshHintFlags');
      expect(runtimeBackend.refreshHintCallsBySession[first], 1);
      expect(runtimeBackend.refreshHintCallsBySession[second], 1);
      expect(runtime.refreshPolicySnapshotFor(first).hintPollCount, 0);
      expect(runtime.refreshPolicySnapshotFor(first).fullPollCount, 2);
      expect(runtime.refreshPolicySnapshotFor(second).hintPollCount, 1);
      expect(runtime.refreshPolicySnapshotFor(second).fullPollCount, 2);

      runtimeBackend.throwingSessions.clear();
      await tester.pump(const Duration(milliseconds: 33));

      expect(errors, hasLength(1), reason: 'the failing session emits once');
      expect(runtimeBackend.refreshHintCallsBySession[first], 1);
      expect(runtimeBackend.refreshHintCallsBySession[second], 2);
      expect(runtime.refreshPolicySnapshotFor(first).hintPollCount, 0);
      expect(runtime.refreshPolicySnapshotFor(first).fullPollCount, 3);
      expect(runtime.refreshPolicySnapshotFor(second).hintPollCount, 2);
      expect(runtime.refreshPolicySnapshotFor(second).fullPollCount, 3);
      runtime.dispose();
    },
  );

  testWidgets(
    'terminal runtime native hint keeps protobuf frame transport preferred',
    (tester) async {
      final runtimeBackend = _RefreshHintProtobufPtyBackend(
        initialFrame: _singleRowProtobuf('protobuf initial'),
      );
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 34));
      await tester.pump(const Duration(milliseconds: 34));
      final protobufCallsBeforeHint = runtimeBackend.takeFrameDiffProtobufCalls;
      runtimeBackend
        ..enqueueProtobufFrame(sessionId, _singleRowProtobuf('protobuf hint'))
        ..hintFlags = 1;

      await tester.pump(const Duration(milliseconds: 34));

      expect(
        runtimeBackend.takeFrameDiffProtobufCalls,
        protobufCallsBeforeHint + 1,
      );
      expect(runtimeBackend.takeFrameDiffCalls, 0);
      expect(
        runtime.viewportFor(sessionId).frame.rows.first.text,
        'protobuf hint',
      );
      runtime.dispose();
    },
  );

  testWidgets(
    'terminal runtime prefers native hint when deadline is also due',
    (tester) async {
      final runtimeBackend = _RefreshHintPtyBackend();
      final diagnostics = <Map<String, Object?>>[];
      var monotonicNow = Duration.zero;
      Future<void> pump(Duration duration) {
        monotonicNow += duration;
        return tester.pump(duration);
      }

      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        benchmarkEventSink: diagnostics.add,
        monotonicNow: () => monotonicNow,
      );

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.clearFrame(sessionId);
      runtime.setSessionActive(sessionId, active: false);
      while (runtime
              .refreshPolicySnapshotFor(sessionId)
              .pumpMetrics
              .currentDelay !=
          const Duration(milliseconds: 132)) {
        await pump(const Duration(milliseconds: 33));
      }
      monotonicNow = const Duration(seconds: 1);
      diagnostics.clear();
      runtimeBackend
        ..setFrame(sessionId, _singleRowSnapshot('simultaneous'))
        ..hintFlags = 1;

      await pump(const Duration(milliseconds: 33));

      final requested = diagnostics.singleWhere(
        (event) =>
            event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
            event['event'] == 'full_poll_requested',
      );
      expect(requested['request_reason'], 'native_hint');
      runtime.dispose();
    },
  );

  test('terminal runtime activation and focus update policy classes', () {
    final runtimeBackend = _FakePtyBackend();
    var monotonicNow = Duration.zero;
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
      monotonicNow: () => monotonicNow,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    runtime.setSessionActive(sessionId, active: false);
    expect(
      runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
      TerminalRefreshClass.background,
    );

    runtime.setSessionActive(sessionId, active: true);
    runtime.setSessionFocused(sessionId, focused: true);
    expect(
      runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
      TerminalRefreshClass.interactive,
    );

    runtime.setSessionFocused(sessionId, focused: false);
    monotonicNow += const Duration(seconds: 1);
    expect(
      runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
      isNot(TerminalRefreshClass.background),
    );
  });

  test('terminal runtime input and resize update interactive policy state', () {
    final runtimeBackend = _FakePtyBackend();
    var monotonicNow = Duration.zero;
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
      monotonicNow: () => monotonicNow,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    monotonicNow = const Duration(seconds: 1);
    expect(
      runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
      TerminalRefreshClass.idle,
    );

    runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x41]));
    expect(
      runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
      TerminalRefreshClass.interactive,
    );

    monotonicNow = const Duration(seconds: 2);
    expect(runtime.resizeSessionCells(sessionId, cols: 90, rows: 24), isTrue);
    expect(
      runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
      TerminalRefreshClass.interactive,
    );
  });

  test('terminal runtime applied frame updates alternate and mouse policy', () {
    final runtimeBackend = _FakePtyBackend();
    var monotonicNow = Duration.zero;
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
      monotonicNow: () => monotonicNow,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    monotonicNow = const Duration(seconds: 1);
    runtimeBackend.setFrame(sessionId, <String, Object?>{
      ..._singleRowSnapshot('interactive modes'),
      'modes': <String, Object?>{
        'alternate_screen': true,
        'mouse_mode': 'any_event',
      },
    });

    runtime.refreshSession(sessionId);

    final snapshot = runtime.refreshPolicySnapshotFor(sessionId);
    expect(snapshot.refreshClass, TerminalRefreshClass.interactive);
  });

  testWidgets(
    'terminal runtime continuous frames transition policy to streaming',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      var monotonicNow = Duration.zero;
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        monotonicNow: () => monotonicNow,
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.clearFrame(sessionId);
      await tester.pump(const Duration(milliseconds: 34));
      monotonicNow = const Duration(seconds: 1);
      runtimeBackend.setFrame(sessionId, _singleRowSnapshot('stream one'));
      runtime.refreshSession(sessionId);
      runtimeBackend.setFrame(sessionId, _singleRowSnapshot('stream two'));
      monotonicNow += const Duration(milliseconds: 33);
      await tester.pump(const Duration(milliseconds: 34));

      expect(
        runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
        TerminalRefreshClass.streaming,
      );
      runtime.dispose();
    },
  );

  test('terminal runtime background diagnostics use 264ms policy cadence', () {
    final runtimeBackend = _FakePtyBackend();
    final diagnostics = <Map<String, Object?>>[];
    const monotonicNow = Duration.zero;
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      benchmarkEventSink: diagnostics.add,
      monotonicNow: () => monotonicNow,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.clearFrame(sessionId);
    diagnostics.clear();

    runtime.setSessionActive(sessionId, active: false);
    runtime.refreshSession(sessionId);
    runtime.refreshSession(sessionId);
    runtime.refreshSession(sessionId);

    final result = diagnostics.lastWhere(
      (event) =>
          event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
          event['event'] == 'refresh_result',
    );
    expect(result['refresh_class'], 'background');
    expect(result['current_delay_micros'], 264000);
    expect(result['backoff_skip_ticks'], 7);
  });

  testWidgets('terminal runtime resets deadline state after input and resize', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final diagnosticEvents = <Map<String, Object?>>[];
    var monotonicNow = Duration.zero;
    Future<void> pumpTick() {
      monotonicNow += const Duration(milliseconds: 34);
      return tester.pump(const Duration(milliseconds: 34));
    }

    Map<String, Object?>? newestRefreshEvent(String eventName) {
      for (final event in diagnosticEvents.reversed) {
        if (event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
            event['event'] == eventName) {
          return event;
        }
      }
      return null;
    }

    Future<void> reachMaximumBackoff() async {
      for (
        var tick = 0;
        tick < 40 &&
            newestRefreshEvent('refresh_result')?['current_delay_micros'] !=
                396000;
        tick += 1
      ) {
        await pumpTick();
      }
      expect(
        newestRefreshEvent('refresh_result')?['current_delay_micros'],
        396000,
      );
    }

    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      benchmarkEventSink: diagnosticEvents.add,
      monotonicNow: () => monotonicNow,
    );
    try {
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.clearFrame(sessionId);
      diagnosticEvents.clear();
      await reachMaximumBackoff();

      diagnosticEvents.clear();
      runtime.sendInput(sessionId, Uint8List(0));

      final inputRequest = newestRefreshEvent('full_poll_requested');
      expect(inputRequest, isNotNull);
      expect(inputRequest!['empty_refresh_count'], 0);
      expect(inputRequest['backoff_skip_ticks'], 0);
      expect(inputRequest['current_delay_micros'], 33000);
      expect(inputRequest['refresh_class'], 'interactive');

      diagnosticEvents.clear();
      await reachMaximumBackoff();

      diagnosticEvents.clear();
      expect(runtime.resizeSessionCells(sessionId, cols: 90, rows: 3), isTrue);

      final resizeRequest = newestRefreshEvent('full_poll_requested');
      expect(resizeRequest, isNotNull);
      expect(resizeRequest!['empty_refresh_count'], 0);
      expect(resizeRequest['backoff_skip_ticks'], 0);
      expect(resizeRequest['current_delay_micros'], 33000);
      expect(resizeRequest['refresh_class'], 'interactive');
    } finally {
      runtime.dispose();
    }
  });

  testWidgets(
    'terminal runtime keeps synchronized output null frames hidden until final polling frame',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final viewport = runtime.viewportFor(sessionId);
        final frameEvents = <TerminalSessionFrameEvent>[];
        final subscription = runtime.events
            .where((event) => event is TerminalSessionFrameEvent)
            .cast<TerminalSessionFrameEvent>()
            .listen(frameEvents.add);
        addTearDown(subscription.cancel);

        expect(runtimeBackend.takeFrameDiffCalls, 1);
        expect(viewport.frame.rows.first.text, 'demo');

        runtimeBackend
          ..clearFrame(sessionId)
          ..enqueueRawFrame(sessionId, '');
        runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));

        await tester.pump(const Duration(milliseconds: 34));

        final hiddenFramePolls = runtimeBackend.takeFrameDiffCalls;
        expect(hiddenFramePolls, greaterThanOrEqualTo(2));
        expect(viewport.frame.rows.first.text, 'demo');
        expect(frameEvents, isEmpty);

        runtimeBackend.setFrame(sessionId, _singleRowSnapshot('sync final'));
        runtime.sendInput(sessionId, Uint8List.fromList(const [0x42]));
        await tester.pump();

        expect(
          runtimeBackend.takeFrameDiffCalls,
          greaterThan(hiddenFramePolls),
        );
        expect(viewport.frame.rows.first.text, 'sync final');
        expect(frameEvents, hasLength(1));
        expect(frameEvents.single.frame.rows.first.text, 'sync final');
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime keeps synchronized graphics clear frames hidden',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final viewport = runtime.viewportFor(sessionId);
        final frameEvents = <TerminalSessionFrameEvent>[];
        final subscription = runtime.events
            .where((event) => event is TerminalSessionFrameEvent)
            .cast<TerminalSessionFrameEvent>()
            .listen(frameEvents.add);
        addTearDown(subscription.cancel);

        runtimeBackend.setFrame(sessionId, <String, Object?>{
          ..._singleRowSnapshot('pet'),
          'graphics': <Object?>[
            <String, Object?>{
              'render_id': 101,
              'placement_id': 101,
              'asset_id': 7,
              'asset_version': 3,
              'protocol': 'kitty',
              'row': 0,
              'col': 2,
              'width_px': 8,
              'height_px': 4,
              'width_cells': 4,
              'height_cells': 2,
            },
          ],
        });
        runtime.refreshSession(sessionId);
        await tester.pump();

        expect(viewport.frame.graphics, hasLength(1));
        frameEvents.clear();

        runtimeBackend.setFrame(sessionId, <String, Object?>{
          ..._singleRowSnapshot('pet'),
          'frame_kind': 'delta',
          'dirty_ranges': <Object?>[],
          'modes': <String, Object?>{'synchronized_output': true},
          'graphics': <Object?>[],
        });
        runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));
        await tester.pump(const Duration(milliseconds: 34));

        expect(viewport.frame.graphics, hasLength(1));
        expect(frameEvents, isEmpty);

        runtimeBackend.setFrame(sessionId, <String, Object?>{
          ..._singleRowSnapshot('pet final'),
          'frame_kind': 'delta',
          'dirty_ranges': <Object?>[
            <String, Object?>{'start': 0, 'end': 1},
          ],
          'modes': <String, Object?>{'synchronized_output': false},
          'graphics': <Object?>[
            <String, Object?>{
              'render_id': 101,
              'placement_id': 101,
              'asset_id': 7,
              'asset_version': 4,
              'protocol': 'kitty',
              'row': 0,
              'col': 2,
              'width_px': 8,
              'height_px': 4,
              'width_cells': 4,
              'height_cells': 2,
            },
          ],
        });
        runtime.sendInput(sessionId, Uint8List.fromList(const [0x42]));
        await tester.pump();

        expect(viewport.frame.rows.first.text, 'pet final');
        expect(
          viewport.frame.graphics.single.assetKey,
          const TerminalGraphicAssetKey(id: 7, version: 4),
        );
        expect(frameEvents, hasLength(1));
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime controller schedules queued polling refresh after async events',
    (tester) async {
      final copyCompleter = Completer<void>();
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) => copyCompleter.future,
        readClipboard: () async => '',
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final viewport = runtime.viewportFor(sessionId);
        runtimeBackend.setFrame(sessionId, _singleRowSnapshot('blocked'));
        runtimeBackend.enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'clipboard_copy',
            sessionId: sessionId,
            payload: <String, Object?>{
              'data': base64.encode(utf8.encode('queued copy')),
            },
          ),
        );

        runtime.sendInput(sessionId, Uint8List(0));
        await tester.pump(const Duration(milliseconds: 34));

        expect(runtimeBackend.takeFrameDiffCalls, 2);
        expect(viewport.frame.rows.first.text, 'blocked');

        runtimeBackend.setFrame(sessionId, _singleRowSnapshot('after async'));
        runtime.sendInput(sessionId, Uint8List(0));
        await tester.pump(const Duration(milliseconds: 30));

        expect(runtimeBackend.takeFrameDiffCalls, 2);

        copyCompleter.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 4));

        expect(runtimeBackend.takeFrameDiffCalls, 3);
        expect(viewport.frame.rows.first.text, 'after async');
      } finally {
        if (!copyCompleter.isCompleted) {
          copyCompleter.complete();
        }
        runtime.dispose();
      }
    },
  );

  testWidgets(
    'terminal runtime controller cancels pending polling refresh on close',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      try {
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        runtimeBackend.setFrame(
          sessionId,
          _singleRowSnapshot('should not show'),
        );
        runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));

        expect(runtimeBackend.takeFrameDiffCalls, 1);

        runtime.closeSession(sessionId);
        await tester.pump(const Duration(milliseconds: 40));

        expect(runtimeBackend.takeFrameDiffCalls, 1);
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets('terminal runtime controller exposes explicit full refresh', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    runtimeBackend.setFrame(sessionId, _singleRowSnapshot('recovered prompt'));
    runtime.refreshSession(sessionId);
    await tester.pump();

    expect(runtimeBackend.scrollToCalls, <(String, int)>[(sessionId, 0)]);
    expect(
      runtime.viewportFor(sessionId).frame.rows.first.text,
      'recovered prompt',
    );
  });

  testWidgets('terminal runtime controller ignores stale session operations', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    runtime.closeSession(sessionId);
    expect(runtime.hasSession(sessionId), isFalse);

    final inputEvents = <TerminalSessionInputEvent>[];
    final resizeEvents = <TerminalSessionResizeEvent>[];
    final inputSubscription = runtime.inputEvents.listen(inputEvents.add);
    final resizeSubscription = runtime.resizeEvents.listen(resizeEvents.add);
    addTearDown(inputSubscription.cancel);
    addTearDown(resizeSubscription.cancel);

    runtimeBackend.closeCalls.clear();
    runtimeBackend.writeCalls.clear();
    runtimeBackend.scrollCalls.clear();
    runtimeBackend.scrollToCalls.clear();
    runtimeBackend.resizeCalls.clear();
    runtimeBackend.jsonRequests.clear();
    runtimeBackend.takeFrameDiffCalls = 0;
    runtimeBackend.pollEventsCalls = 0;

    runtime.closeSession(sessionId);
    runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x41]));
    runtime.scrollViewport(sessionId, 1);
    runtime.scrollViewportTo(sessionId, 2);
    runtime.resizeSession(sessionId, const Size(180, 144), 1);
    runtime.resizeSessionCells(
      sessionId,
      cols: 80,
      rows: 24,
      cellSize: terminalFallbackCellSize,
    );
    runtime.resizeSessionCells(
      sessionId,
      cols: 0,
      rows: 24,
      devicePixelRatio: double.nan,
      cellSize: const Size(double.infinity, 18),
    );
    final selectionText = runtime.selectionText(
      sessionId,
      const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 4),
      block: false,
    );
    final searchResult = runtime.searchTextResult(sessionId, 'demo');
    runtime.refreshSession(sessionId);
    await tester.pump();

    expect(selectionText, isEmpty);
    expect(searchResult.matches, isEmpty);
    expect(runtimeBackend.closeCalls, isEmpty);
    expect(runtimeBackend.writeCalls, isEmpty);
    expect(runtimeBackend.scrollCalls, isEmpty);
    expect(runtimeBackend.scrollToCalls, isEmpty);
    expect(runtimeBackend.resizeCalls, isEmpty);
    expect(runtimeBackend.jsonRequests, isEmpty);
    expect(runtimeBackend.takeFrameDiffCalls, 0);
    expect(runtimeBackend.pollEventsCalls, 0);
    expect(inputEvents, isEmpty);
    expect(resizeEvents, isEmpty);
  });

  testWidgets(
    'terminal runtime controller emits backend error events instead of success signals',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      final backendErrors = <TerminalSessionBackendErrorEvent>[];
      final inputEvents = <TerminalSessionInputEvent>[];
      final resizeEvents = <TerminalSessionResizeEvent>[];
      final backendErrorSubscription = runtime.events
          .where((event) => event is TerminalSessionBackendErrorEvent)
          .cast<TerminalSessionBackendErrorEvent>()
          .listen(backendErrors.add);
      final inputSubscription = runtime.inputEvents.listen(inputEvents.add);
      final resizeSubscription = runtime.resizeEvents.listen(resizeEvents.add);
      addTearDown(backendErrorSubscription.cancel);
      addTearDown(inputSubscription.cancel);
      addTearDown(resizeSubscription.cancel);

      runtimeBackend.failingOperations.addAll(<String>{
        'writeInput',
        'scrollViewport',
        'scrollViewportTo',
        'resizeSession',
        'closeSession',
      });

      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x41]));
      runtime.scrollViewport(sessionId, 1);
      runtime.scrollViewportTo(sessionId, 2);
      runtime.resizeSession(sessionId, const Size(180, 144), 1);
      expect(runtime.tryCloseSession(sessionId), isFalse);
      await tester.pump();

      expect(backendErrors.map((event) => event.operation), <String>[
        'writeInput',
        'scrollViewport',
        'scrollViewportTo',
        'resizeSession',
        'closeSession',
      ]);
      expect(inputEvents, isEmpty);
      expect(resizeEvents, isEmpty);
      expect(runtime.hasSession(sessionId), isTrue);
      expect(
        backendErrors.every(
          (event) => event.error.toString().contains('failed'),
        ),
        isTrue,
      );
      runtimeBackend.failingOperations.clear();
    },
  );

  testWidgets(
    'terminal runtime controller releases permanent dispose failures',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      final backendErrors = <TerminalSessionBackendErrorEvent>[];
      final backendErrorSubscription = runtime.events
          .where((event) => event is TerminalSessionBackendErrorEvent)
          .cast<TerminalSessionBackendErrorEvent>()
          .listen(backendErrors.add);
      addTearDown(backendErrorSubscription.cancel);

      runtimeBackend.failingOperations.add('closeSession');

      expect(runtime.tryDispose(), isTrue);
      await tester.pump();

      expect(runtime.hasSession(sessionId), isFalse);
      expect(backendErrors.map((event) => event.operation), <String>[
        'closeSession',
      ]);
      expect(
        backendErrors.single.error.toString(),
        contains('closeSession failed'),
      );
    },
  );

  testWidgets(
    'terminal runtime controller autonomously retries native busy disposal',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      runtimeBackend.retryableCloseSessionIds.add(sessionId);

      expect(runtime.tryDispose(), isFalse);
      expect(runtime.hasSession(sessionId), isTrue);

      runtimeBackend.retryableCloseSessionIds.remove(sessionId);
      await tester.pump(const Duration(milliseconds: 60));

      expect(runtime.hasSession(sessionId), isFalse);
      expect(runtime.tryDispose(), isTrue);
    },
  );

  testWidgets(
    'close busy polling survives a late native transition publication',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      backend.retryableCloseSessionIds.add(sessionId);
      addTearDown(() {
        backend.retryableCloseSessionIds.remove(sessionId);
      });

      expect(runtime.tryCloseSession(sessionId), isFalse);
      for (var index = 0; index < 25; index += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final pollsBeforeLateEvent = backend.pollEventsCalls;
      expect(pollsBeforeLateEvent, greaterThan(20));

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '9001',
            'direction': 'receive',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(runtime.activeZmodemTransferIdFor(sessionId), '9001');
      backend.retryableCloseSessionIds.remove(sessionId);
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '9001',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
    },
  );

  testWidgets(
    'transient close busy probe stops without silently closing the pane',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
        enableWarmUpRefresh: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      backend.retryableCloseSessionIds.add(sessionId);

      expect(runtime.tryCloseSession(sessionId), isFalse);
      backend.retryableCloseSessionIds.remove(sessionId);
      await tester.pump(const Duration(milliseconds: 60));

      expect(runtime.hasSession(sessionId), isTrue);
      expect(backend.closeCalls, isEmpty);
      final pollsAfterReady = backend.pollEventsCalls;
      await tester.pump(const Duration(milliseconds: 500));
      expect(backend.pollEventsCalls, pollsAfterReady);

      expect(runtime.tryCloseSession(sessionId), isTrue);
      expect(runtime.hasSession(sessionId), isFalse);
      expect(backend.closeCalls, <String>[sessionId]);
    },
  );

  testWidgets(
    'terminal runtime controller emits backend error events for JSON requests',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      final backendErrors = <TerminalSessionBackendErrorEvent>[];
      final backendErrorSubscription = runtime.events
          .where((event) => event is TerminalSessionBackendErrorEvent)
          .cast<TerminalSessionBackendErrorEvent>()
          .listen(backendErrors.add);
      addTearDown(backendErrorSubscription.cancel);

      runtimeBackend.failingOperations.add('requestSessionJson');

      final selectionText = runtime.selectionText(
        sessionId,
        const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 4),
        block: false,
      );
      final searchResult = runtime.searchTextResult(sessionId, 'demo');
      final clearResult = runtime.clearScrollback(sessionId);
      final blockResult = runtime.setBlockFolded(
        sessionId,
        'build-1',
        folded: true,
      );
      final blockRenderResult = runtime.setBlockRendered(
        sessionId,
        'build-1',
        rendered: false,
      );
      final exportText = runtime.exportScrollbackText(sessionId);
      final diagnostics = runtime.exportSessionDiagnostics(sessionId);
      await tester.pump();

      expect(selectionText, 'demo');
      expect(searchResult.matches, isEmpty);
      expect(clearResult, isFalse);
      expect(blockResult, isFalse);
      expect(blockRenderResult, isFalse);
      expect(exportText, isNull);
      expect(diagnostics, isNull);
      expect(backendErrors.map((event) => event.operation), <String>[
        'terminal.selection_text',
        'terminal.search_text',
        'terminal.clear_scrollback',
        'terminal.set_block_folded',
        'terminal.set_block_rendered',
        'terminal.export_scrollback',
        'terminal.export_diagnostics',
      ]);
      expect(
        backendErrors.every(
          (event) =>
              event.error.toString().contains('requestSessionJson failed'),
        ),
        isTrue,
      );

      runtimeBackend.failingOperations.clear();
    },
  );

  testWidgets(
    'terminal runtime controller emits backend error events for refresh reads',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      final backendErrors = <TerminalSessionBackendErrorEvent>[];
      final backendErrorSubscription = runtime.events
          .where((event) => event is TerminalSessionBackendErrorEvent)
          .cast<TerminalSessionBackendErrorEvent>()
          .listen(backendErrors.add);
      addTearDown(backendErrorSubscription.cancel);

      runtimeBackend.failingOperations.addAll(<String>{
        'takeFrameDiffJson',
        'pollEvents',
      });

      runtime.refreshSession(sessionId);
      await tester.pump();

      expect(backendErrors.map((event) => event.operation), <String>[
        'takeFrameDiffJson',
        'pollEvents',
      ]);
      expect(
        backendErrors.every(
          (event) => event.error.toString().contains('failed'),
        ),
        isTrue,
      );

      runtimeBackend.failingOperations.clear();
    },
  );

  testWidgets('terminal runtime controller emits typed shell hook events', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();

    final shellHooks = <TerminalSessionShellHookEvent>[];
    final subscription = runtime.events
        .where((event) => event is TerminalSessionShellHookEvent)
        .cast<TerminalSessionShellHookEvent>()
        .listen(shellHooks.add);
    addTearDown(subscription.cancel);

    runtimeBackend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'shell_hook',
        sessionId: sessionId,
        payload: <String, Object?>{
          'hook': 'command_finished',
          'command': 'echo ok',
          'pwd': '/tmp/project',
          'shell': 'zsh',
          'hostname': 'buildbox.local',
          'username': 'dev',
          'prompt_scrollback_offset': 17,
          'exit_code': 7,
          'extra': <String, Object?>{'kept': true},
        },
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    final event = shellHooks.single;
    expect(event.sessionId, sessionId);
    expect(event.rawPayload['extra'], <String, Object?>{'kept': true});
    expect(event.hook, 'command_finished');
    expect(event.command, 'echo ok');
    expect(event.cwd, '/tmp/project');
    expect(event.shell, 'zsh');
    expect(event.hostname, 'buildbox.local');
    expect(event.username, 'dev');
    expect(event.promptScrollbackOffset, 17);
    expect(event.exitCode, 7);
  });

  test('terminal shell hook payload ignores invalid numeric fields', () {
    final nonFinite = TerminalSessionShellHookEvent(
      '1',
      rawPayload: <String, Object?>{
        'prompt_scrollback_offset': double.infinity,
        'exit_code': double.nan,
      },
    );
    final fractional = TerminalSessionShellHookEvent(
      '1',
      rawPayload: <String, Object?>{
        'prompt_scrollback_offset': 17.5,
        'exit_code': 7.5,
      },
    );
    final wholeDouble = TerminalSessionShellHookEvent(
      '1',
      rawPayload: <String, Object?>{
        'prompt_scrollback_offset': 17.0,
        'exit_code': 7.0,
      },
    );

    expect(nonFinite.promptScrollbackOffset, isNull);
    expect(nonFinite.exitCode, isNull);
    expect(fractional.promptScrollbackOffset, isNull);
    expect(fractional.exitCode, isNull);
    expect(wholeDouble.promptScrollbackOffset, 17);
    expect(wholeDouble.exitCode, 7);
  });

  test('terminal shell hook payload normalizes hook tokens', () {
    final event = TerminalSessionShellHookEvent(
      '1',
      rawPayload: const <String, Object?>{
        'hook': ' command_finished ',
        'command': '  echo ok  ',
      },
    );
    final blank = TerminalSessionShellHookEvent(
      '1',
      rawPayload: const <String, Object?>{'hook': '   '},
    );

    expect(event.hook, 'command_finished');
    expect(event.command, '  echo ok  ');
    expect(event.rawPayload['hook'], ' command_finished ');
    expect(blank.hook, isNull);
  });

  testWidgets('terminal runtime controller emits bell events', (tester) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();

    final bells = <TerminalSessionBellEvent>[];
    final subscription = runtime.events
        .where((event) => event is TerminalSessionBellEvent)
        .cast<TerminalSessionBellEvent>()
        .listen(bells.add);
    addTearDown(subscription.cancel);

    runtimeBackend.enqueueEvent(
      sessionId,
      PtyEvent(kind: 'bell', sessionId: sessionId),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    expect(bells.single.sessionId, sessionId);
  });

  testWidgets(
    'terminal runtime controller passes through unknown shell hooks',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      final shellHooks = <TerminalSessionShellHookEvent>[];
      final subscription = runtime.events
          .where((event) => event is TerminalSessionShellHookEvent)
          .cast<TerminalSessionShellHookEvent>()
          .listen(shellHooks.add);
      addTearDown(subscription.cancel);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: sessionId,
          payload: const <String, Object?>{'hook': 'custom.future_hook'},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final event = shellHooks.single;
      expect(event.hook, 'custom.future_hook');
      expect(event.command, isNull);
      expect(event.cwd, isNull);
      expect(event.shell, isNull);
      expect(event.exitCode, isNull);
      expect(event.rawPayload, containsPair('hook', 'custom.future_hook'));
    },
  );

  testWidgets(
    'terminal runtime controller emits typed OSC session metadata events',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      final events = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_context',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc9;9',
            'cwd': '/tmp/project',
            'hostname': 'workstation.local',
            'username': 'dev',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'terminal_context',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc3008',
            'action': 'update',
            'id': 'command-1',
            'depth': 2,
            'active': true,
            'type': 'command',
            'user': 'dev',
            'hostname': 'workstation.local',
            'pid': 42,
            'cwd': '/tmp/project',
            'commandLine': 'dart test',
            'exit': null,
            'implicitClosedCount': 1,
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_command',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc633',
            'eventType': 'command_finished',
            'command': 'dart test',
            'exitCode': 0,
            'promptKind': 'right',
            'aid': 'inner-shell',
            'parentAid': 'outer-shell',
            'implicitClosedCount': 1,
            'freshLine': false,
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_user_var',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc1337_set_user_var',
            'name': 'IANVS_TEST',
            'value': 'ok',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'session_annotation',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'iterm1337',
            'message': 'Inspect this value',
            'selectedText': 'value',
            'visible': true,
            'startAbsRow': 42,
            'startCol': 3,
            'endAbsRow': 42,
            'endCol': 8,
            'startRow': 2,
            'endRow': 2,
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'session_notification',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc99',
            'action': 'update',
            'id': 'build-1',
            'title': 'Build',
            'message': 'Done',
            'application': 'buildctl',
            'types': <String>['deploy', 'ci'],
            'expiresAfterMs': 250,
            'reportActivation': true,
            'reportClose': true,
            'buttons': <String>['Approve', 'Retry'],
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'ianvs_osc934',
            'named': true,
            'action': 'set',
            'id': 'build',
            'state': 'normal',
            'percent': 70,
            'label': 'Compile',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'session_badge',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc1337_set_badge_format',
            'text': 'Build',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'session_tab_status',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc21337',
            'indicatorPresent': true,
            'indicator': '#ff9500',
            'statusPresent': true,
            'status': 'Working',
            'statusColorPresent': true,
            'statusColor': '#5f87ff',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'drag_drop_command',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc72',
            'action': 'a',
            'more': false,
            'identifier': 7,
            'operation': 1,
            'x': 3,
            'y': 4,
            'pixelX': 30,
            'pixelY': 40,
            'payload': 'text/plain text/uri-list',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(kind: 'session_reset', sessionId: sessionId),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final shellContext = events.whereType<TerminalSessionShellContextEvent>();
      expect(shellContext.single.source, 'osc9;9');
      expect(shellContext.single.cwd, '/tmp/project');
      expect(shellContext.single.hostname, 'workstation.local');
      final shellCommand = events.whereType<TerminalSessionShellCommandEvent>();
      expect(shellCommand.single.source, 'osc633');
      expect(shellCommand.single.eventType, 'command_finished');
      expect(shellCommand.single.exitCode, 0);
      expect(shellCommand.single.promptKind, 'right');
      expect(shellCommand.single.aid, 'inner-shell');
      expect(shellCommand.single.parentAid, 'outer-shell');
      expect(shellCommand.single.implicitClosedCount, 1);
      expect(shellCommand.single.freshLine, isFalse);
      expect(
        events.whereType<TerminalSessionShellUserVarEvent>().single.name,
        'IANVS_TEST',
      );
      final annotation = events
          .whereType<TerminalSessionAnnotationEvent>()
          .single;
      expect(annotation.source, 'iterm1337');
      expect(annotation.message, 'Inspect this value');
      expect(annotation.selectedText, 'value');
      expect(annotation.visible, isTrue);
      expect(annotation.startAbsRow, 42);
      expect(annotation.startCol, 3);
      expect(annotation.endAbsRow, 42);
      expect(annotation.endCol, 8);
      expect(annotation.startRow, 2);
      expect(annotation.endRow, 2);
      final notification = events
          .whereType<TerminalSessionNotificationEvent>()
          .single;
      expect(notification.source, 'osc99');
      expect(notification.action, 'update');
      expect(notification.identifier, 'build-1');
      expect(notification.message, 'Done');
      expect(notification.applicationName, 'buildctl');
      expect(notification.notificationTypes, <String>['deploy', 'ci']);
      expect(notification.expiresAfterMs, 250);
      expect(notification.reportActivation, isTrue);
      expect(notification.reportClose, isTrue);
      expect(notification.buttons, <String>['Approve', 'Retry']);
      expect(
        events.whereType<TerminalSessionProgressEvent>().single.id,
        'build',
      );
      expect(
        events.whereType<TerminalSessionProgressEvent>().single.source,
        'ianvs_osc934',
      );
      expect(
        events.whereType<TerminalSessionBadgeEvent>().single.text,
        'Build',
      );
      final tabStatus = events
          .whereType<TerminalSessionTabStatusEvent>()
          .single;
      expect(tabStatus.source, 'osc21337');
      expect(tabStatus.indicatorPresent, isTrue);
      expect(tabStatus.indicator, '#ff9500');
      expect(tabStatus.statusPresent, isTrue);
      expect(tabStatus.status, 'Working');
      expect(tabStatus.statusColorPresent, isTrue);
      expect(tabStatus.statusColor, '#5f87ff');
      final context = events.whereType<TerminalSessionContextEvent>().single;
      expect(context.source, 'osc3008');
      expect(context.action, 'update');
      expect(context.identifier, 'command-1');
      expect(context.depth, 2);
      expect(context.active, isTrue);
      expect(context.contextType, 'command');
      expect(context.user, 'dev');
      expect(context.pid, 42);
      expect(context.cwd, '/tmp/project');
      expect(context.commandLine, 'dart test');
      expect(context.implicitClosedCount, 1);
      final dragDrop = events
          .whereType<TerminalSessionDragDropCommandEvent>()
          .single;
      expect(dragDrop.action, 'a');
      expect(dragDrop.identifier, 7);
      expect(dragDrop.operation, 1);
      expect(dragDrop.x, 3);
      expect(dragDrop.y, 4);
      expect(dragDrop.pixelX, 30);
      expect(dragDrop.pixelY, 40);
      expect(dragDrop.payload, 'text/plain text/uri-list');
      expect(
        events.whereType<TerminalSessionResetEvent>().single.sessionId,
        sessionId,
      );
    },
  );

  testWidgets(
    'OSC 1337 downloads stay metadata-only until one-shot take or discard',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final events = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);
      backend.fileDownloads[(sessionId, 7)] = Uint8List.fromList(const <int>[
        104,
        101,
        108,
        108,
        111,
      ]);
      backend.fileDownloads[(sessionId, 8)] = Uint8List.fromList(const <int>[
        1,
        2,
      ]);
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'file_download',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'iterm1337',
            'transferId': '7',
            'filename': 'report.txt',
            'size': 5,
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'file_download_failed',
          sessionId: sessionId,
          payload: const <String, Object?>{'reason': 'size mismatch'},
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'file_upload_denied',
          sessionId: sessionId,
          payload: const <String, Object?>{'format': 'tgz'},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();

      final download = events
          .whereType<TerminalSessionFileDownloadEvent>()
          .single;
      expect(download.isValid, isTrue);
      expect(download.downloadId, 7);
      expect(download.filename, 'report.txt');
      expect(download.size, 5);
      expect(download.rawPayload.containsKey('data'), isFalse);
      expect(runtime.takeFileDownload(download), utf8.encode('hello'));
      expect(runtime.takeFileDownload(download), isNull);
      expect(
        TerminalSessionFileDownloadEvent(
          sessionId,
          rawPayload: const <String, Object?>{
            'source': 'iterm1337',
            'transferId': '9',
            'filename': '../escape.txt',
            'size': 1,
          },
        ).isValid,
        isFalse,
      );
      expect(
        events
            .whereType<TerminalSessionFileDownloadFailedEvent>()
            .single
            .reason,
        'size mismatch',
      );
      expect(
        events.whereType<TerminalSessionFileUploadDeniedEvent>().single.format,
        'tgz',
      );

      final discardEvent = TerminalSessionFileDownloadEvent(
        sessionId,
        rawPayload: const <String, Object?>{
          'source': 'iterm1337',
          'transferId': '8',
          'filename': 'discard.bin',
          'size': 2,
        },
      );
      expect(runtime.discardFileDownload(discardEvent), isTrue);
      expect(runtime.discardFileDownload(discardEvent), isFalse);
      expect(backend.fileDownloadTakeRequests, <(String, int, int)>[
        (sessionId, 7, 5),
        (sessionId, 7, 5),
      ]);
      expect(backend.fileDownloadDiscardRequests, <(String, int)>[
        (sessionId, 8),
        (sessionId, 8),
      ]);
    },
  );

  testWidgets('OSC 1337 OpenURL stays a typed validated request', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: backend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    final events = <TerminalSessionEvent>[];
    final subscription = runtime.events.listen(events.add);
    addTearDown(subscription.cancel);
    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'open_url_request',
        sessionId: sessionId,
        payload: const <String, Object?>{
          'source': 'iterm1337',
          'url': 'https://example.test/phase29',
        },
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    final request = events
        .whereType<TerminalSessionOpenUrlRequestEvent>()
        .single;
    expect(request.source, 'iterm1337');
    expect(request.url, 'https://example.test/phase29');
    expect(request.isValid, isTrue);
    for (final invalid in <Map<String, Object?>>[
      const {'source': 'unknown', 'url': 'https://example.test/phase29'},
      const {'source': 'iterm1337', 'url': 'javascript:alert(1)'},
      const {'source': 'iterm1337', 'url': 'https://'},
      const {'source': 'iterm1337', 'url': 'file:///'},
      const {'source': 'iterm1337', 'url': 'file://remote.example/path'},
      const {'source': 'iterm1337', 'url': ' https://example.test/space'},
      const {'source': 'iterm1337', 'url': 'https://example.test/control\n'},
    ]) {
      expect(
        TerminalSessionOpenUrlRequestEvent(
          sessionId,
          rawPayload: invalid,
        ).isValid,
        isFalse,
        reason: '$invalid',
      );
    }
    expect(
      TerminalSessionOpenUrlRequestEvent(
        sessionId,
        rawPayload: const <String, Object?>{
          'source': 'iterm1337',
          'url': 'file:///tmp/ianvs-phase29.txt',
        },
      ).isValid,
      isTrue,
    );
  });

  testWidgets(
    'OSC 1337 ReportVariable uses a one-shot session-bound exact reply',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final events = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);
      runtime
          .viewportFor(sessionId)
          .updateFrame(
            const TerminalFrameDiff(
              frameKind: TerminalFrameKind.snapshot,
              rows: <TerminalRow>[],
              cursor: TerminalCursor(row: 0, col: 0, visible: true),
              viewportRows: 24,
              viewportCols: 80,
              dirtyRanges: <TerminalDirtyRange>[],
              scrollbackOffset: 3,
              scrollbackMaxOffset: 3,
            ),
          );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'report_variable_request',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'iterm1337',
            'name': 'user.gitBranch',
            'value': 'feature/报告',
          },
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      final request = events
          .whereType<TerminalSessionReportVariableRequestEvent>()
          .single;
      expect(request.source, 'iterm1337');
      expect(request.name, 'user.gitBranch');
      expect(request.rawPayload, isNot(contains('value')));
      expect(request.isValid, isTrue);
      expect(request.isSupported, isTrue);

      backend.writeCalls.clear();
      final wrongSession = TerminalSessionReportVariableRequestEvent(
        'other-session',
        requestId: request.requestId,
        rawPayload: request.rawPayload,
      );
      expect(
        runtime.respondToOsc1337ReportVariable(
          wrongSession,
          useNativeResolvedValue: true,
        ),
        isFalse,
      );
      expect(
        runtime.respondToOsc1337ReportVariable(
          request,
          useNativeResolvedValue: true,
        ),
        isTrue,
      );
      expect(
        ascii.decode(backend.writeCalls.single),
        '\x1b]1337;ReportVariable=ZmVhdHVyZS/miqXlkYo=\x07',
      );
      expect(
        backend.scrollToCalls,
        isEmpty,
        reason: 'automatic protocol replies must preserve retained scrollback',
      );
      expect(
        runtime.respondToOsc1337ReportVariable(request, value: 'duplicate'),
        isFalse,
      );
      expect(backend.writeCalls, hasLength(1));

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'report_variable_request',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'iterm1337',
            'name': 'user.private',
            'value': 'must-not-leak',
          },
        ),
      );
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      final denied = events
          .whereType<TerminalSessionReportVariableRequestEvent>()
          .last;
      expect(denied.rawPayload, isNot(contains('value')));
      backend.writeCalls.clear();
      expect(runtime.respondToOsc1337ReportVariable(denied), isTrue);
      expect(
        ascii.decode(backend.writeCalls.single),
        '\x1b]1337;ReportVariable=\x07',
      );
    },
  );

  testWidgets(
    'OSC 1337 ReportVariable validates names and emits denied empty reply',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final events = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'report_variable_request',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'iterm1337',
            'name': 'session.environment',
          },
        ),
      );
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      final request = events
          .whereType<TerminalSessionReportVariableRequestEvent>()
          .single;
      expect(request.isValid, isTrue);
      expect(request.isSupported, isFalse);
      backend.writeCalls.clear();
      expect(runtime.respondToOsc1337ReportVariable(request), isTrue);
      expect(
        ascii.decode(backend.writeCalls.single),
        '\x1b]1337;ReportVariable=\x07',
      );

      for (final invalid in <Map<String, Object?>>[
        const {'source': 'unknown', 'name': 'session.path'},
        const {'source': 'iterm1337', 'name': ''},
        const {'source': 'iterm1337', 'name': 'session.path\n'},
      ]) {
        expect(
          TerminalSessionReportVariableRequestEvent(
            sessionId,
            requestId: 1,
            rawPayload: invalid,
          ).isValid,
          isFalse,
          reason: '$invalid',
        );
      }
      expect(
        TerminalSessionReportVariableRequestEvent.isSupportedName(
          'user.${List<String>.filled(81, 'x').join()}',
        ),
        isFalse,
      );
      expect(
        TerminalSessionReportVariableRequestEvent.isSupportedName(
          'user.${List<String>.filled(64, '😀').join()}',
        ),
        isFalse,
        reason: 'the complete UTF-8 name must remain within 256 bytes',
      );
      expect(
        TerminalSessionReportVariableRequestEvent.isSupportedName(
          'user.bad\u0085name',
        ),
        isFalse,
        reason: 'C1 controls are not valid variable-name content',
      );
      for (final supported in <String>{
        'session.shell',
        'session.lastCommand',
        'session.profileName',
        'session.badge',
        'session.terminalIconName',
        'session.terminalWindowName',
      }) {
        expect(
          TerminalSessionReportVariableRequestEvent.isSupportedName(supported),
          isTrue,
          reason: supported,
        );
      }
    },
  );

  testWidgets('OSC 1337 ClearCapturedOutput stays session-scoped and typed', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: backend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    final events = <TerminalSessionEvent>[];
    final subscription = runtime.events.listen(events.add);
    addTearDown(subscription.cancel);
    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'clear_captured_output',
        sessionId: sessionId,
        payload: const <String, Object?>{'source': 'iterm1337'},
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    final request = events
        .whereType<TerminalSessionClearCapturedOutputEvent>()
        .single;
    expect(request.sessionId, sessionId);
    expect(request.source, 'iterm1337');
    expect(request.isValid, isTrue);
    expect(
      TerminalSessionClearCapturedOutputEvent(
        sessionId,
        rawPayload: const <String, Object?>{'source': 'unknown'},
      ).isValid,
      isFalse,
    );
    expect(TerminalSessionClearCapturedOutputEvent(sessionId).isValid, isFalse);
  });

  testWidgets('OSC 1337 RequestAttention stays a strict typed request', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: backend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    final events = <TerminalSessionEvent>[];
    final subscription = runtime.events.listen(events.add);
    addTearDown(subscription.cancel);
    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'attention_request',
        sessionId: sessionId,
        payload: const <String, Object?>{
          'source': 'iterm1337',
          'action': 'fireworks',
        },
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    final request = events
        .whereType<TerminalSessionAttentionRequestEvent>()
        .single;
    expect(request.source, 'iterm1337');
    expect(request.action, 'fireworks');
    expect(request.isValid, isTrue);
    for (final action in <String>['yes', 'once', 'no', 'fireworks']) {
      expect(
        TerminalSessionAttentionRequestEvent(
          sessionId,
          rawPayload: <String, Object?>{
            'source': 'iterm1337',
            'action': action,
          },
        ).isValid,
        isTrue,
        reason: action,
      );
    }
    for (final invalid in <Map<String, Object?>>[
      const {'source': 'unknown', 'action': 'yes'},
      const {'source': 'iterm1337', 'action': 'YES'},
      const {'source': 'iterm1337', 'action': 'yes '},
      const {'source': 'iterm1337', 'action': 'forever'},
      const {'source': 'iterm1337'},
    ]) {
      expect(
        TerminalSessionAttentionRequestEvent(
          sessionId,
          rawPayload: invalid,
        ).isValid,
        isFalse,
        reason: '$invalid',
      );
    }
  });

  testWidgets(
    'OSC 1337 cell-size query waits for and reports exact logical metrics',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      runtimeBackend.writeCalls.clear();

      final requests = <TerminalSessionCellSizeReportRequestEvent>[];
      final subscription = runtime.events
          .where((event) => event is TerminalSessionCellSizeReportRequestEvent)
          .cast<TerminalSessionCellSizeReportRequestEvent>()
          .listen(requests.add);
      addTearDown(subscription.cancel);
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(kind: 'cell_size_report_request', sessionId: sessionId),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(kind: 'cell_size_report_request', sessionId: sessionId),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      expect(requests, hasLength(2));
      expect(
        runtimeBackend.writeCalls.where((bytes) => bytes.isNotEmpty),
        isEmpty,
      );

      runtime
          .viewportFor(sessionId)
          .updateMeasuredCellSize(const Size(8.25, 17.5));
      expect(runtime.resizeSession(sessionId, const Size(825, 350), 2), isTrue);
      await tester.pump();

      final responses = runtimeBackend.writeCalls
          .where((bytes) => bytes.isNotEmpty)
          .map(utf8.decode)
          .toList(growable: false);
      expect(responses, <String>[
        '\u001b]1337;ReportCellSize=17.50;8.25;2.00\u001b\\',
        '\u001b]1337;ReportCellSize=17.50;8.25;2.00\u001b\\',
      ]);
    },
  );

  testWidgets(
    'terminal runtime controller emits shell hooks before same-batch exits',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      final events = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'hook': 'command_finished',
            'exit_code': 0,
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 0},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final lifecycleEvents = events
          .where(
            (event) =>
                event is TerminalSessionShellHookEvent ||
                event is TerminalSessionExitEvent,
          )
          .toList(growable: false);
      expect(lifecycleEvents, hasLength(2));
      expect(lifecycleEvents.first, isA<TerminalSessionShellHookEvent>());
      expect(lifecycleEvents.last, isA<TerminalSessionExitEvent>());
    },
  );

  test('terminal runtime owns search and selection JSON request shapes', () {
    final runtimeBackend = _FakePtyBackend()
      ..searchResponse = const <Map<String, Object?>>[
        <String, Object?>{
          'row': 2,
          'start_col': 4,
          'end_col': 9,
          'text': 'ready',
          'scrollback_offset': 2,
        },
      ]
      ..selectionResponse = 'selected text';
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.jsonRequests.clear();

    final search = runtime.searchTextResult(
      sessionId,
      'ready',
      mode: TerminalSearchMode.caseInsensitiveRegex,
    );
    expect(search.matches.single.text, 'ready');
    expect(search.errorText, isNull);
    expect(runtimeBackend.jsonRequests.single, <String, Object?>{
      'kind': 'terminal.search_text',
      'query': 'ready',
      'mode': 'case_insensitive_regex',
    });

    final text = runtime.selectionText(
      sessionId,
      const TerminalSelection(startRow: 0, startCol: 1, endRow: 0, endCol: 4),
      block: true,
    );
    expect(text, 'selected text');
    expect(runtimeBackend.jsonRequests.last, <String, Object?>{
      'kind': 'terminal.selection_text',
      'selection': <String, Object?>{
        'start_row': 0,
        'start_col': 1,
        'end_row': 0,
        'end_col': 4,
      },
      'block': true,
    });

    expect(
      runtime.exportScrollbackText(sessionId, maxLines: -1),
      'scrollback text',
    );
    expect(runtimeBackend.jsonRequests.last, <String, Object?>{
      'kind': 'terminal.export_scrollback',
      'maxLines': 0,
    });

    expect(
      runtime.exportScrollbackText(
        sessionId,
        maxLines: maxTerminalScrollbackLines + 1,
      ),
      'scrollback text',
    );
    expect(runtimeBackend.jsonRequests.last, <String, Object?>{
      'kind': 'terminal.export_scrollback',
      'maxLines': maxTerminalScrollbackLines,
    });
  });

  testWidgets('terminal runtime toggles OSC 1337 blocks and refreshes frames', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    runtimeBackend.jsonRequests.clear();
    final readsBeforeToggle = runtimeBackend.takeFrameDiffCalls;

    expect(runtime.setBlockFolded(sessionId, 'build-1', folded: false), isTrue);
    expect(runtimeBackend.jsonRequests.single, <String, Object?>{
      'kind': 'terminal.set_block_folded',
      'id': 'build-1',
      'folded': false,
    });
    await tester.pump();
    expect(runtimeBackend.takeFrameDiffCalls, greaterThan(readsBeforeToggle));

    runtimeBackend.jsonRequests.clear();
    final readsBeforeRestore = runtimeBackend.takeFrameDiffCalls;
    expect(
      runtime.setBlockRendered(sessionId, 'build-1', rendered: false),
      isTrue,
    );
    expect(runtimeBackend.jsonRequests.single, <String, Object?>{
      'kind': 'terminal.set_block_rendered',
      'id': 'build-1',
      'rendered': false,
    });
    await tester.pump();
    expect(runtimeBackend.takeFrameDiffCalls, greaterThan(readsBeforeRestore));

    runtimeBackend
      ..setBlockFoldedResponse = false
      ..jsonRequests.clear();
    final readsBeforeRejectedToggle = runtimeBackend.takeFrameDiffCalls;
    expect(runtime.setBlockFolded(sessionId, 'missing', folded: true), isFalse);
    await tester.pump();
    expect(runtimeBackend.takeFrameDiffCalls, readsBeforeRejectedToggle);
    expect(runtimeBackend.jsonRequests.single['id'], 'missing');

    runtimeBackend.jsonRequests.clear();
    expect(runtime.setBlockFolded(sessionId, '', folded: true), isFalse);
    expect(runtime.setBlockRendered(sessionId, '', rendered: false), isFalse);
    expect(runtime.setBlockFolded('unknown', 'build-1', folded: true), isFalse);
    expect(
      runtime.setBlockRendered('unknown', 'build-1', rendered: false),
      isFalse,
    );
    expect(runtimeBackend.jsonRequests, isEmpty);
  });

  test(
    'terminal runtime activates OSC 1337 buttons through the native bridge',
    () {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.jsonRequests.clear();

      final custom = runtime.activateItermButton(sessionId, 7001);
      expect(custom.activated, isTrue);
      expect(custom.kind, TerminalInlineButtonKind.custom);
      expect(custom.text, isNull);
      expect(runtimeBackend.jsonRequests.single, <String, Object?>{
        'kind': 'terminal.activate_iterm_button',
        'id': 7001,
      });

      runtimeBackend
        ..inlineButtonActivationResponse = <String, Object?>{
          'activated': true,
          'kind': 'copy',
          'text': 'exact block text',
        }
        ..jsonRequests.clear();
      final copy = runtime.activateItermButton(sessionId, 7002);
      expect(copy.activated, isTrue);
      expect(copy.kind, TerminalInlineButtonKind.copy);
      expect(copy.text, 'exact block text');

      runtimeBackend.jsonRequests.clear();
      expect(runtime.activateItermButton(sessionId, 0).activated, isFalse);
      expect(runtime.activateItermButton('unknown', 7001).activated, isFalse);
      expect(runtimeBackend.jsonRequests, isEmpty);
    },
  );

  test('terminal runtime synchronizes OSC 99 product dismissal by ID', () {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.jsonRequests.clear();

    expect(runtime.dismissOsc99Notification(sessionId, 'deploy-1'), isTrue);
    expect(runtimeBackend.jsonRequests.single, <String, Object?>{
      'kind': 'terminal.dismiss_osc99_notification',
      'id': 'deploy-1',
    });

    runtimeBackend
      ..dismissOsc99NotificationResponse = false
      ..jsonRequests.clear();
    expect(runtime.dismissOsc99Notification(sessionId, 'missing'), isFalse);
    expect(runtime.dismissOsc99Notification(sessionId, ''), isFalse);
    expect(runtime.dismissOsc99Notification('unknown', 'deploy-1'), isFalse);
    expect(runtimeBackend.jsonRequests, hasLength(1));
  });

  test('terminal runtime delegates buffer clearing to the native core', () {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final viewport = runtime.viewportFor(sessionId);
    viewport.applySnapshot(
      const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'visible prompt')],
        cursor: TerminalCursor(row: 0, col: 14, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 12,
      ),
    );
    runtimeBackend.jsonRequests.clear();

    expect(runtime.clearBuffer(sessionId), isTrue);
    expect(
      runtimeBackend.jsonRequests
          .where((request) => request['kind'] == 'terminal.clear_buffer')
          .single,
      <String, Object?>{'kind': 'terminal.clear_buffer'},
    );
    // Rust sends the authoritative post-clear frame; Dart must not fabricate
    // an empty screen while waiting for it.
    expect(viewport.frame.rows.first.text, 'visible prompt');
    expect(viewport.frame.scrollbackMaxOffset, 12);
  });

  test('terminal runtime degrades malformed JSON request responses', () {
    final runtimeBackend = _FakePtyBackend()
      ..searchRawResponse = '{'
      ..selectionRawResponse = '{'
      ..clearScrollbackRawResponse = '{'
      ..scrollbackRawResponse = '{';
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    final search = runtime.searchTextResult(sessionId, 'ready');
    expect(search.matches, isEmpty);
    expect(search.errorText, isNull);

    final text = runtime.selectionText(
      sessionId,
      const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 4),
      block: false,
    );
    expect(text, 'demo');

    expect(runtime.clearScrollback(sessionId), isFalse);
    expect(runtime.exportScrollbackText(sessionId), isNull);

    runtimeBackend
      ..selectionRawResponse = jsonEncode(<String, Object?>{'text': 42})
      ..scrollbackRawResponse = jsonEncode(<String, Object?>{'content': 42});

    final invalidText = runtime.selectionText(
      sessionId,
      const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 4),
      block: false,
    );
    expect(invalidText, 'demo');
    expect(runtime.exportScrollbackText(sessionId), isNull);
  });

  test(
    'terminal runtime fallback selection preserves complex grapheme columns',
    () {
      const technologist = '👩\u{200D}💻';
      const nerdIcon = '󰣇';
      const combining = 'e\u0301';
      final runtimeBackend = _FakePtyBackend()..selectionRawResponse = '{';
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtime
          .viewportFor(sessionId)
          .applySnapshot(
            TerminalFrameDiff.fromJson(
              _singleRowSnapshot('$technologist$nerdIcon${combining}X'),
            ),
          );

      expect(
        runtime.selectionText(
          sessionId,
          const TerminalSelection(
            startRow: 0,
            startCol: 1,
            endRow: 0,
            endCol: 2,
          ),
          block: false,
        ),
        technologist,
      );
      expect(
        runtime.selectionText(
          sessionId,
          const TerminalSelection(
            startRow: 0,
            startCol: 2,
            endRow: 0,
            endCol: 4,
          ),
          block: false,
        ),
        '$nerdIcon$combining',
      );
      expect(
        runtime.selectionText(
          sessionId,
          const TerminalSelection(
            startRow: 0,
            startCol: 3,
            endRow: 0,
            endCol: 4,
          ),
          block: false,
        ),
        combining,
      );
    },
  );

  test('terminal runtime skips malformed search match entries', () {
    final runtimeBackend = _FakePtyBackend()
      ..searchRawResponse = jsonEncode(<String, Object?>{
        'matches': <Object?>[
          <String, Object?>{
            'row': 0,
            'start_col': 1,
            'end_col': 5,
            'text': 'good',
            'scrollback_offset': -2,
          },
          null,
          <String, Object?>{'row': 'bad'},
          <String, Object?>{
            'row': 0.5,
            'start_col': 1,
            'end_col': 5,
            'text': 'fractional-row',
          },
          <String, Object?>{
            'row': -1,
            'start_col': 1,
            'end_col': 5,
            'text': 'negative-row',
          },
          <String, Object?>{
            'row': 0,
            'start_col': -1,
            'end_col': 5,
            'text': 'negative-start',
          },
          <String, Object?>{
            'row': 0,
            'start_col': 5,
            'end_col': 5,
            'text': 'empty-range',
          },
          <String, Object?>{'row': 0, 'start_col': 1, 'end_col': 5, 'text': ''},
        ],
      });
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    final search = runtime.searchTextResult(sessionId, 'ready');

    expect(search.matches.map((match) => match.text), <String>['good']);
    expect(search.matches.single.scrollbackOffset, 0);
    expect(search.errorText, isNull);
  });

  test('terminal runtime scans search matches past malformed prefixes', () {
    final runtimeBackend = _FakePtyBackend()
      ..searchRawResponse = jsonEncode(<String, Object?>{
        'matches': <Object?>[
          for (var index = 0; index < 1004; index += 1)
            <String, Object?>{'row': 'bad-$index'},
          <String, Object?>{
            'row': 3,
            'start_col': 1,
            'end_col': 4,
            'text': 'hit',
            'scrollback_offset': 2,
          },
        ],
      });
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    final search = runtime.searchTextResult(sessionId, 'hit');

    expect(search.matches.single.text, 'hit');
    expect(search.matches.single.scrollbackOffset, 2);
  });

  test('terminal runtime caps oversized search match responses', () {
    final runtimeBackend = _FakePtyBackend()
      ..searchRawResponse = jsonEncode(<String, Object?>{
        'matches': <Object?>[
          for (var index = 0; index < 1002; index += 1)
            <String, Object?>{
              'row': index,
              'start_col': 0,
              'end_col': 1,
              'text': 'x$index',
              'scrollback_offset': index,
            },
        ],
      });
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    final search = runtime.searchTextResult(sessionId, 'x');

    expect(search.matches, hasLength(1000));
    expect(search.matches.first.text, 'x0');
    expect(search.matches.last.text, 'x999');
  });

  test('terminal runtime normalizes search error text', () {
    final runtimeBackend = _FakePtyBackend()
      ..searchRawResponse = jsonEncode(<String, Object?>{
        'matches': const <Object?>[],
        'error_text': ' invalid regex ',
      });
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    final error = runtime.searchTextResult(sessionId, 'ready');
    runtimeBackend.searchRawResponse = jsonEncode(<String, Object?>{
      'matches': const <Object?>[],
      'error_text': '   ',
    });
    final blank = runtime.searchTextResult(sessionId, 'ready');

    expect(error.errorText, 'invalid regex');
    expect(blank.errorText, isNull);
  });

  testWidgets('terminal runtime skips malformed frame payloads', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');

    runtimeBackend
      ..enqueueRawFrame(sessionId, '[]')
      ..setFrame(sessionId, _singleRowSnapshot('recovered prompt'));

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();
    expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();
    expect(
      runtime.viewportFor(sessionId).frame.rows.first.text,
      'recovered prompt',
    );
  });

  test('terminal runtime exports diagnostics with private defaults', () {
    final runtimeBackend = _FakePtyBackend()
      ..diagnosticsResponse = <String, Object?>{
        'manifest': <String, Object?>{
          'schema_version': 'terminal-diagnostics-session-v1',
          'session_id': 1,
        },
        'resource_samples': <Object?>[
          <String, Object?>{'timestamp_micros': 1, 'rss_bytes': 100},
          <String, Object?>{'timestamp_micros': 2, 'rss_bytes': 120},
        ],
        'terminal_stats': <String, Object?>{
          'session': <String, Object?>{'bytes_read': 4},
        },
        'events': <Object?>[
          <String, Object?>{'kind': 'started'},
        ],
        'summary': <String, Object?>{
          'conclusion': 'insufficient-evidence',
          'markdown': '# Terminal diagnostics',
        },
      };
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.jsonRequests.clear();

    final export = runtime.exportSessionDiagnostics(sessionId);

    expect(export, isNotNull);
    expect(export!.conclusion, 'insufficient-evidence');
    expect(export.resourceSamples.map((sample) => sample['rss_bytes']), [
      100,
      120,
    ]);
    expect(runtimeBackend.jsonRequests.single, <String, Object?>{
      'kind': 'terminal.export_diagnostics',
      'maxSamples': 60,
      'includeContent': false,
      'redactionMode': 'basic',
      'policy': <String, Object?>{
        'includeScrollback': false,
        'includeRawCommand': false,
        'includeRawCwd': false,
        'includeEnv': false,
      },
    });
  });

  test('terminal diagnostics export tolerates malformed summary fields', () {
    final export = TerminalDiagnosticsExport.fromJson(<String, Object?>{
      'manifest': <Object?, Object?>{
        7: 'ignored',
        'schema_version': 'terminal-diagnostics-session-v1',
      },
      'resource_samples': <Object?>[
        <Object?, Object?>{7: 'ignored', 'rss_bytes': 100},
        'bad-sample',
      ],
      'summary': <String, Object?>{'conclusion': '   ', 'markdown': 42},
    });

    expect(export.manifest, <String, Object?>{
      'schema_version': 'terminal-diagnostics-session-v1',
    });
    expect(export.resourceSamples, <Map<String, Object?>>[
      <String, Object?>{'rss_bytes': 100},
    ]);
    expect(export.conclusion, isNull);
    expect(export.summaryMarkdown, isNull);

    final trimmed = TerminalDiagnosticsExport.fromJson(<String, Object?>{
      'summary': <String, Object?>{
        'conclusion': ' insufficient-evidence ',
        'markdown': ' # Terminal diagnostics ',
      },
    });

    expect(trimmed.conclusion, 'insufficient-evidence');
    expect(trimmed.summaryMarkdown, '# Terminal diagnostics');
  });

  test('terminal diagnostics export caps decoded list fields', () {
    final export = TerminalDiagnosticsExport.fromJson(<String, Object?>{
      'resource_samples': <Object?>[
        for (var index = 0; index < 62; index += 1)
          <String, Object?>{'rss_bytes': index},
      ],
      'events': <Object?>[
        for (var index = 0; index < 202; index += 1)
          <String, Object?>{'sequence': index},
      ],
    });

    expect(export.resourceSamples, hasLength(60));
    expect(export.resourceSamples.last['rss_bytes'], 59);
    expect(export.events, hasLength(200));
    expect(export.events.last['sequence'], 199);
  });

  test(
    'terminal diagnostics export scans list fields past malformed prefixes',
    () {
      final export = TerminalDiagnosticsExport.fromJson(<String, Object?>{
        'resource_samples': <Object?>[
          for (var index = 0; index < 62; index += 1) 'bad-sample-$index',
          <String, Object?>{'rss_bytes': 128},
        ],
        'events': <Object?>[
          for (var index = 0; index < 202; index += 1) 'bad-event-$index',
          <String, Object?>{'sequence': 12},
        ],
      });

      expect(export.resourceSamples.single['rss_bytes'], 128);
      expect(export.events.single['sequence'], 12);
    },
  );

  test('terminal diagnostics export bounds decoded summary fields', () {
    final export = TerminalDiagnosticsExport.fromJson(<String, Object?>{
      'summary': <String, Object?>{
        'conclusion': ' ${'c' * 5000} ',
        'markdown': ' ${'m' * 5000} ',
        'evidence': <Object?>[
          for (var index = 0; index < 24; index += 1)
            ' ${index.toString().padLeft(2, '0')}-${'e' * 700} ',
          <String, Object?>{'raw_command': 'ssh prod'},
        ],
        'next_steps': <Object?>[
          for (var index = 0; index < 24; index += 1)
            ' ${index.toString().padLeft(2, '0')}-${'n' * 700} ',
        ],
        'attribution_scores': <Object?, Object?>{
          'non_finite': double.nan,
          7: 'ignored',
          for (var index = 0; index < 40; index += 1)
            ' score-$index ': ' ${'s' * 5000} ',
        },
      },
    });

    final evidence = export.summary['evidence']! as List<String>;
    final nextSteps = export.summary['next_steps']! as List<String>;
    final scores =
        export.summary['attribution_scores']! as Map<String, Object?>;

    expect(export.conclusion, hasLength(4096));
    expect(export.summaryMarkdown, hasLength(4096));
    expect(evidence, hasLength(20));
    expect(evidence.first, hasLength(512));
    expect(evidence.last, startsWith('19-'));
    expect(nextSteps, hasLength(20));
    expect(nextSteps.first, hasLength(512));
    expect(scores, hasLength(32));
    expect(scores.keys.first, 'score-0');
    expect(
      scores.values.first,
      isA<String>().having((value) => value.length, 'length', 4096),
    );
    expect(scores.containsKey('non_finite'), isFalse);
  });

  test('terminal diagnostics export scans summary fields past invalids', () {
    final export = TerminalDiagnosticsExport.fromJson(<String, Object?>{
      'summary': <String, Object?>{
        for (var index = 0; index < 34; index += 1)
          'invalid_$index': double.nan,
        'conclusion': ' recovered ',
        'evidence': <Object?>[
          for (var index = 0; index < 22; index += 1)
            <String, Object?>{'raw_command': 'ssh prod-$index'},
          ' evidence recovered ',
        ],
        'attribution_scores': <Object?, Object?>{
          for (var index = 0; index < 34; index += 1) index: double.nan,
          ' score ': ' useful ',
        },
      },
    });

    final evidence = export.summary['evidence']! as List<String>;
    final scores =
        export.summary['attribution_scores']! as Map<String, Object?>;

    expect(export.conclusion, 'recovered');
    expect(evidence, <String>['evidence recovered']);
    expect(scores, <String, Object?>{'score': 'useful'});
  });

  test(
    'terminal runtime degrades diagnostics export to null on bad backend data',
    () {
      final runtimeBackend = _FakePtyBackend()..diagnosticsRawResponse = '{';
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      expect(runtime.exportSessionDiagnostics(sessionId), isNull);

      runtimeBackend
        ..diagnosticsRawResponse = ''
        ..jsonRequests.clear();
      expect(runtime.exportSessionDiagnostics(sessionId), isNull);

      runtimeBackend
        ..diagnosticsRawResponse = null
        ..diagnosticsResponse = null
        ..returnNullJsonRequests = true;
      expect(runtime.exportSessionDiagnostics(sessionId), isNull);
    },
  );

  test('terminal runtime returns null diagnostics for unsupported backend', () {
    final runtimeBackend = _FrameOnlyPtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    expect(runtime.exportSessionDiagnostics(sessionId), isNull);
  });

  test(
    'terminal runtime controller ignores invalid viewport resize metrics',
    () {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      runtime.resizeSession(sessionId, const Size(double.infinity, 144), 1);
      runtime.resizeSession(sessionId, const Size(180, double.nan), 1);
      runtime.resizeSession(sessionId, const Size(180, 144), double.nan);

      expect(runtimeBackend.resizeCalls, isEmpty);
    },
  );

  test('terminal runtime controller rejects invalid cell resize metrics', () {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    expect(
      () => runtime.resizeSessionCells(
        sessionId,
        cols: 80,
        rows: 24,
        devicePixelRatio: double.nan,
      ),
      throwsRangeError,
    );
    expect(
      () => runtime.resizeSessionCells(
        sessionId,
        cols: 80,
        rows: 24,
        cellSize: const Size(double.infinity, 18),
      ),
      throwsRangeError,
    );
    expect(runtimeBackend.resizeCalls, isEmpty);
  });

  test('terminal runtime controller clamps oversized resize dimensions', () {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    runtime.resizeSessionCells(
      sessionId,
      cols: maxTerminalDimension + 1,
      rows: maxTerminalDimension + 2,
      cellSize: terminalFallbackCellSize,
    );

    expect(runtimeBackend.resizeCalls.last, <Object?>[
      sessionId,
      maxTerminalDimension,
      maxTerminalDimension,
      maxTerminalDimension,
      maxTerminalDimension,
      terminalFallbackCellSize.width.round(),
      terminalFallbackCellSize.height.round(),
    ]);

    final secondSessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.resizeCalls.clear();
    runtime.resizeSession(
      secondSessionId,
      Size(
        terminalFallbackCellSize.width * maxTerminalDimension * 2,
        terminalFallbackCellSize.height * maxTerminalDimension * 2,
      ),
      1,
    );

    expect(runtimeBackend.resizeCalls.last, <Object?>[
      secondSessionId,
      maxTerminalDimension,
      maxTerminalDimension,
      maxTerminalDimension,
      maxTerminalDimension,
      terminalFallbackCellSize.width.round(),
      terminalFallbackCellSize.height.round(),
    ]);
  });

  testWidgets(
    'terminal runtime controller does not keep started-only refreshes in flight',
    (tester) async {
      final runtimeBackend = _StartedEventPtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      runtimeBackend.setFrame(sessionId, _singleRowSnapshot('fresh'));
      runtime.resizeSession(sessionId, const Size(180, 144), 1);
      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'fresh');
      await tester.pump();

      expect(runtimeBackend.takeFrameDiffCalls, 2);
      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'fresh');
    },
  );

  testWidgets(
    'terminal runtime controller merges delta frames into stable viewport state',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'snapshot',
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'alpha',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 1,
            'text': 'beta',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 1, 'col': 4, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'cursor_color': '#123456',
        'selection_background': '#234567',
        'selection_foreground': '#345678',
        'link_color': '#456789',
        'cursor_text_color': '#56789a',
        'tab_color': '#6789ab',
        'hyperlinks': <Object?>[
          <String, Object?>{
            'row': 0,
            'start_col': 0,
            'end_col': 5,
            'uri': 'https://example.com/alpha',
          },
        ],
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'delta',
        'rows': <Object?>[
          <String, Object?>{
            'index': 1,
            'text': 'beta*',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 1, 'col': 5, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 1, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'hyperlinks': <Object?>[
          <String, Object?>{
            'row': 1,
            'start_col': 0,
            'end_col': 5,
            'uri': 'https://example.com/beta',
          },
        ],
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final merged = runtime.viewportFor(sessionId).frame;
      expect(merged.frameKind, TerminalFrameKind.delta);
      expect(merged.rows.map((row) => row.text).toList(), <String>[
        'alpha',
        'beta*',
      ]);
      expect(merged.hyperlinks.map((range) => range.uri).toList(), <String>[
        'https://example.com/alpha',
        'https://example.com/beta',
      ]);
      expect(merged.cursorColor, const Color(0xFF123456));
      expect(merged.selectionBackground, const Color(0xFF234567));
      expect(merged.selectionForeground, const Color(0xFF345678));
      expect(merged.linkColor, const Color(0xFF456789));
      expect(merged.cursorTextColor, const Color(0xFF56789A));
      expect(merged.tabColor, const Color(0xFF6789AB));
    },
  );

  testWidgets(
    'terminal runtime controller shifts viewport rows forward on scrolling delta frames',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'snapshot',
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'alpha',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 1,
            'text': 'beta',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 2,
            'text': 'gamma',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 2, 'col': 5, 'visible': true},
        'viewport_rows': 3,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 3},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 20,
        'viewport_start_row': 20,
        'hyperlinks': <Object?>[
          <String, Object?>{
            'row': 1,
            'start_col': 0,
            'end_col': 4,
            'uri': 'https://example.com/beta',
          },
        ],
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'delta',
        'rows': <Object?>[
          <String, Object?>{
            'index': 2,
            'text': 'delta',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 2, 'col': 5, 'visible': true},
        'viewport_rows': 3,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 2, 'end': 3},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 21,
        'viewport_start_row': 21,
        'viewport_row_shift': -1,
        'hyperlinks': <Object?>[
          <String, Object?>{
            'row': 2,
            'start_col': 0,
            'end_col': 5,
            'uri': 'https://example.com/delta',
          },
        ],
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final shifted = runtime.viewportFor(sessionId).frame;
      expect(shifted.rows.map((row) => row.text).toList(), <String>[
        'beta',
        'gamma',
        'delta',
      ]);
      expect(
        shifted.hyperlinks
            .map((range) => '${range.row}:${range.uri}')
            .toList(growable: false),
        <String>['0:https://example.com/beta', '2:https://example.com/delta'],
      );
    },
  );

  testWidgets(
    'terminal runtime controller coalesces refreshes while event handling is still in flight',
    (tester) async {
      final copyCompleter = Completer<void>();
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) => copyCompleter.future,
        readClipboard: () async => '',
        allowClipboardCopy: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      runtimeBackend.setFrame(
        sessionId,
        _singleRowSnapshot('queued visible frame'),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('queued copy')),
          },
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'queued visible frame');

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(
        runtimeBackend.takeFrameDiffCalls,
        2,
        reason:
            'second refresh should queue instead of re-entering immediately',
      );

      copyCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(runtimeBackend.takeFrameDiffCalls, 3);
    },
  );

  testWidgets(
    'terminal runtime controller applies queued delta frames in order after a blocked refresh',
    (tester) async {
      final copyCompleter = Completer<void>();
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) => copyCompleter.future,
        readClipboard: () async => '',
        allowClipboardCopy: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      await tester.pump();

      expect(viewport.frameVersion, 1);

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'snapshot',
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'alpha',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 1,
            'text': 'beta',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 1, 'col': 4, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.map((row) => row.text).toList(), <String>[
        'alpha',
        'beta',
      ]);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('block refresh')),
          },
        ),
      );
      runtimeBackend.enqueueFrame(sessionId, <String, Object?>{
        'frame_kind': 'delta',
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'alpha*',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 0, 'col': 6, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      runtimeBackend.enqueueFrame(sessionId, <String, Object?>{
        'frame_kind': 'delta',
        'rows': <Object?>[
          <String, Object?>{
            'index': 1,
            'text': 'beta*',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 1, 'col': 5, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 1, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.map((row) => row.text).toList(), <String>[
        'alpha*',
        'beta',
      ]);

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.map((row) => row.text).toList(), <String>[
        'alpha*',
        'beta',
      ]);

      copyCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(viewport.frame.rows.map((row) => row.text).toList(), <String>[
        'alpha*',
        'beta*',
      ]);
    },
  );

  testWidgets(
    'terminal runtime controller lets a queued snapshot replace older blocked frames',
    (tester) async {
      final copyCompleter = Completer<void>();
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) => copyCompleter.future,
        readClipboard: () async => '',
        allowClipboardCopy: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      await tester.pump();

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('block refresh')),
          },
        ),
      );
      runtimeBackend.enqueueFrame(sessionId, _singleRowSnapshot('stale'));
      runtimeBackend.enqueueFrame(sessionId, _singleRowSnapshot('fresh'));

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'stale');

      copyCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'fresh');
    },
  );

  testWidgets(
    'terminal runtime controller applies visible frames before clipboard paste handling completes',
    (tester) async {
      final readClipboardCompleter = Completer<String>();
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () => readClipboardCompleter.future,
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      runtimeBackend.setFrame(
        sessionId,
        _singleRowSnapshot('paste visible frame'),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': ' c '},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'paste visible frame');
      expect(
        runtimeBackend.writeCalls.where((call) => call.isNotEmpty),
        isEmpty,
      );

      readClipboardCompleter.complete('paste me');
      await tester.pump();
      await tester.pump();

      expect(
        utf8.decode(runtimeBackend.writeCalls.last),
        '\x1B]52;c;cGFzdGUgbWU=\x07',
      );
    },
  );

  testWidgets(
    'terminal runtime controller applies resize before queued write frames',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final timeline = <String>[];
      final eventSubscription = runtime.events.listen((event) {
        if (event is TerminalSessionFrameEvent) {
          timeline.add(
            'frame:${event.frame.viewportCols}x'
            '${event.frame.viewportRows}:'
            '${event.frame.rows.first.text}',
          );
        }
      });
      addTearDown(eventSubscription.cancel);
      final resizeSubscription = runtime.resizeEvents.listen((event) {
        timeline.add('resize:${event.cols}x${event.rows}');
      });
      addTearDown(resizeSubscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtime.resizeSession(sessionId, const Size(180, 144), 1);
      await tester.pump();
      timeline.clear();

      runtimeBackend.enqueueFrame(
        sessionId,
        _singleRowSnapshot(
          'write before resize',
          viewportCols: 20,
          viewportRows: 8,
        ),
      );
      runtimeBackend.setFrame(
        sessionId,
        _singleRowSnapshot('resize settled', viewportCols: 21, viewportRows: 9),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'resize',
          sessionId: sessionId,
          payload: const <String, Object?>{'cols': 21, 'rows': 9},
        ),
      );

      runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));
      await tester.pump();
      await tester.pump();

      expect(utf8.decode(runtimeBackend.writeCalls.last), 'A');
      expect(runtimeBackend.resizeCalls.last, <Object?>[
        '1',
        21,
        9,
        189,
        162,
        9,
        18,
      ]);
      expect(timeline, <String>['resize:21x9', 'frame:21x9:resize settled']);
      expect(
        runtime.viewportFor(sessionId).frame.rows.first.text,
        'resize settled',
      );
    },
  );

  testWidgets(
    'terminal runtime controller handles OSC 52 base64 copy edge cases',
    (tester) async {
      final copiedTexts = <String>[];
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (text) async {
          copiedTexts.add(text);
        },
        readClipboard: () async => '',
        allowClipboardCopy: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final paddedPayload = base64.encode(utf8.encode('padded ok'));
      final oversizedPayload = base64.encode(Uint8List(4 * 1024 * 1024 + 1));
      final whitespacePayload =
          '${paddedPayload.substring(0, 4)}\n ${paddedPayload.substring(4)}';

      runtimeBackend.enqueueEvent(
        sessionId,
        const PtyEvent(
          kind: 'clipboard_copy',
          sessionId: '1',
          payload: <String, Object?>{'data': 'not-valid-base64!!!'},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{'data': whitespacePayload},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{'data': oversizedPayload},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: const <String, Object?>{'data': ''},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(copiedTexts, <String>['padded ok', '']);
    },
  );

  testWidgets(
    'terminal runtime controller preserves iTerm2 clipboard protocol and named target',
    (tester) async {
      final writes = <(String, String)>[];
      final requests = <TerminalClipboardAccessRequest>[];
      final seenEvents = <TerminalSessionEvent>[];
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        writeTextClipboard: (text, selection) async {
          writes.add((text, selection));
        },
        readClipboard: () async => '',
        allowClipboardCopyWithContext: (request) async {
          requests.add(request);
          return true;
        },
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final subscription = runtime.events.listen(seenEvents.add);
      addTearDown(subscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'protocol': 'iterm1337',
            'mode': 'stream',
            'selection': 'find',
            'data': base64.encode(utf8.encode('Find 😀')),
          },
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(writes, <(String, String)>[('Find 😀', 'find')]);
      expect(requests.single.protocol, 'iterm1337');
      expect(requests.single.selection, 'find');
      expect(requests.single.textPreview, 'Find 😀');
      final event = seenEvents
          .whereType<TerminalSessionClipboardEvent>()
          .single;
      expect(event.protocol, 'iterm1337');
      expect(event.selection, 'find');
      expect(event.decision, TerminalClipboardDecision.allowed);
    },
  );

  testWidgets('terminal runtime controller can block OSC 52 copy events', (
    tester,
  ) async {
    final copiedTexts = <String>[];
    final seenEvents = <TerminalSessionEvent>[];
    TerminalClipboardAccessRequest? accessRequest;
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (text) async {
        copiedTexts.add(text);
      },
      readClipboard: () async => '',
      allowClipboardCopyWithContext: (request) async {
        accessRequest = request;
        return false;
      },
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final subscription = runtime.events.listen(seenEvents.add);
    addTearDown(subscription.cancel);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'clipboard_copy',
        sessionId: sessionId,
        payload: <String, Object?>{
          'data': base64.encode(utf8.encode('blocked')),
        },
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    expect(copiedTexts, isEmpty);
    expect(accessRequest?.operation, TerminalClipboardOperation.copy);
    expect(accessRequest?.sessionId, sessionId);
    expect(accessRequest?.textPreview, 'blocked');
    expect(accessRequest?.characterCount, 7);
    expect(accessRequest?.byteCount, 7);
    final clipboardEvent = seenEvents
        .whereType<TerminalSessionClipboardEvent>()
        .single;
    expect(clipboardEvent.operation, TerminalClipboardOperation.copy);
    expect(clipboardEvent.decision, TerminalClipboardDecision.blocked);
    expect(clipboardEvent.textPreview, 'blocked');
  });

  testWidgets(
    'terminal runtime controller accepts an explicit clipboard policy adapter',
    (tester) async {
      final copiedTexts = <String>[];
      final seenRequests = <TerminalClipboardAccessRequest>[];
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController.withClipboardPolicy(
        backend: runtimeBackend,
        copyToClipboard: (text) async {
          copiedTexts.add(text);
        },
        readClipboard: () async => '',
        clipboardPolicy: TerminalClipboardPolicyAdapter(
          allowClipboardCopyWithContext: (request) async {
            seenRequests.add(request);
            return request.textPreview == 'adapter copy';
          },
        ),
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('adapter copy')),
          },
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(copiedTexts, <String>['adapter copy']);
      expect(seenRequests.single.operation, TerminalClipboardOperation.copy);
      expect(seenRequests.single.sessionId, sessionId);
    },
  );

  testWidgets(
    'terminal runtime controller blocks OSC 52 access without an explicit policy',
    (tester) async {
      final copiedTexts = <String>[];
      var readClipboardCount = 0;
      final seenEvents = <TerminalSessionEvent>[];
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (text) async {
          copiedTexts.add(text);
        },
        readClipboard: () async {
          readClipboardCount += 1;
          return 'paste me';
        },
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final subscription = runtime.events.listen(seenEvents.add);
      addTearDown(subscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('implicit copy')),
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(copiedTexts, isEmpty);
      expect(readClipboardCount, 0);
      final clipboardEvents = seenEvents
          .whereType<TerminalSessionClipboardEvent>()
          .toList();
      expect(
        clipboardEvents.map((event) => event.decision),
        <TerminalClipboardDecision>[
          TerminalClipboardDecision.blocked,
          TerminalClipboardDecision.blocked,
        ],
      );
      expect(clipboardEvents.first.operation, TerminalClipboardOperation.copy);
      expect(
        clipboardEvents.last.operation,
        TerminalClipboardOperation.pasteRequest,
      );
    },
  );

  testWidgets('terminal runtime controller reports malformed OSC 52 UTF-8', (
    tester,
  ) async {
    final copiedTexts = <String>[];
    final seenEvents = <TerminalSessionEvent>[];
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (text) async {
        copiedTexts.add(text);
      },
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final subscription = runtime.events.listen(seenEvents.add);
    addTearDown(subscription.cancel);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'clipboard_copy',
        sessionId: sessionId,
        payload: <String, Object?>{
          'data': base64.encode([0xff, 0xfe]),
        },
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    expect(copiedTexts, isEmpty);
    final clipboardEvent = seenEvents
        .whereType<TerminalSessionClipboardEvent>()
        .single;
    expect(clipboardEvent.operation, TerminalClipboardOperation.copy);
    expect(clipboardEvent.decision, TerminalClipboardDecision.invalidPayload);
  });

  testWidgets('terminal runtime controller can block OSC 52 paste requests', (
    tester,
  ) async {
    var readClipboardCount = 0;
    final seenEvents = <TerminalSessionEvent>[];
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async {
        readClipboardCount += 1;
        return 'blocked paste';
      },
      allowClipboardPasteRequest: () async => false,
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final subscription = runtime.events.listen(seenEvents.add);
    addTearDown(subscription.cancel);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'clipboard_paste_request',
        sessionId: sessionId,
        payload: const <String, Object?>{'selection': 'c'},
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    expect(readClipboardCount, 0);
    expect(runtimeBackend.writeCalls, hasLength(1));
    expect(runtimeBackend.writeCalls.single, isEmpty);
    final clipboardEvent = seenEvents
        .whereType<TerminalSessionClipboardEvent>()
        .single;
    expect(clipboardEvent.operation, TerminalClipboardOperation.pasteRequest);
    expect(clipboardEvent.decision, TerminalClipboardDecision.blocked);
  });

  testWidgets(
    'terminal runtime responds to correlated OSC 52 Host Request v1 without a raw reply',
    (tester) async {
      final runtimeBackend = _FakePtyBackend()..hostResponseV1Supported = true;
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => 'host response',
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final hostRequest = PtyHostRequestV1.fromJson(
        <String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-host-request-v1',
          'request_id': 'host:$sessionId:3',
          'session_id': sessionId,
          'operation': 'clipboard.read_text',
          'sequence': 3,
          'timestamp_micros': 1200,
          'payload': <String, Object?>{'selection': 'c'},
        },
        expectedSessionId: sessionId,
        expectedSequence: 3,
        expectedTimestampMicros: 1200,
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: hostRequest.payload,
          sequence: 3,
          timestampMicros: 1200,
          wireSchemaVersion: 1,
          hostRequest: hostRequest,
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(runtimeBackend.hostResponses, hasLength(1));
      final response =
          jsonDecode(runtimeBackend.hostResponses.single.$2)
              as Map<String, Object?>;
      expect(response['request_id'], 'host:$sessionId:3');
      expect(response['operation'], 'clipboard.read_text');
      expect(response['ok'], isTrue);
      expect(
        (response['payload']! as Map<String, Object?>)['data_base64'],
        base64.encode(utf8.encode('host response')),
      );
      expect(runtimeBackend.writeCalls, hasLength(1));
      expect(runtimeBackend.writeCalls.single, isEmpty);
    },
  );

  testWidgets('shutdown drops a permission continuation and its pending exit', (
    tester,
  ) async {
    final permissionStarted = Completer<void>();
    final permission = Completer<bool>();
    var readClipboardCount = 0;
    var exitHookCount = 0;
    final backend = _FakePtyBackend()..hostResponseV1Supported = true;
    final runtime = TerminalRuntimeController(
      backend: backend,
      copyToClipboard: (_) async {},
      readClipboard: () async {
        readClipboardCount += 1;
        return 'secret';
      },
      allowClipboardPasteRequest: () {
        if (!permissionStarted.isCompleted) {
          permissionStarted.complete();
        }
        return permission.future;
      },
      enableSessionPolling: false,
      enableWarmUpRefresh: false,
      beforeSessionCloseOnExit: (_, _) {
        exitHookCount += 1;
      },
    );
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    backend
      ..enqueueEvent(
        sessionId,
        _clipboardPasteHostRequestEvent(sessionId, sequence: 3),
      )
      ..enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 0},
        ),
      );

    runtime.refreshSession(sessionId);
    await permissionStarted.future;
    runtime.beginShutdown();
    permission.complete(true);
    await tester.pump();
    await tester.pump();

    expect(readClipboardCount, 0);
    expect(backend.hostResponses, isEmpty);
    expect(backend.writeCalls, isEmpty);
    expect(exitHookCount, 0);
    expect(backend.closeCalls, isEmpty);
    expect(runtime.hasSession(sessionId), isTrue);
    expect(runtime.tryDispose(), isTrue);
    expect(backend.closeCalls, <String>[sessionId]);
  });

  testWidgets(
    'shutdown drops a clipboard-read continuation and its pending exit',
    (tester) async {
      final readStarted = Completer<void>();
      final clipboardText = Completer<String>();
      var exitHookCount = 0;
      final backend = _FakePtyBackend()..hostResponseV1Supported = true;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () {
          if (!readStarted.isCompleted) {
            readStarted.complete();
          }
          return clipboardText.future;
        },
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
        enableWarmUpRefresh: false,
        beforeSessionCloseOnExit: (_, _) {
          exitHookCount += 1;
        },
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      backend
        ..enqueueEvent(
          sessionId,
          _clipboardPasteHostRequestEvent(sessionId, sequence: 4),
        )
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'exit',
            sessionId: sessionId,
            payload: const <String, Object?>{'code': 0},
          ),
        );

      runtime.refreshSession(sessionId);
      await readStarted.future;
      runtime.beginShutdown();
      clipboardText.complete('secret');
      await tester.pump();
      await tester.pump();

      expect(backend.hostResponses, isEmpty);
      expect(backend.writeCalls, isEmpty);
      expect(exitHookCount, 0);
      expect(backend.closeCalls, isEmpty);
      expect(runtime.hasSession(sessionId), isTrue);
      expect(runtime.tryDispose(), isTrue);
      expect(backend.closeCalls, <String>[sessionId]);
    },
  );

  testWidgets(
    'saved contextual clipboard resolver rejects before reading after shutdown',
    (tester) async {
      final requestCaptured = Completer<void>();
      late TerminalClipboardAccessRequest savedRequest;
      var readClipboardCount = 0;
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async {
          readClipboardCount += 1;
          return 'secret';
        },
        allowClipboardPasteRequestWithContext: (request) async {
          savedRequest = request;
          requestCaptured.complete();
          return false;
        },
        enableSessionPolling: false,
        enableWarmUpRefresh: false,
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );

      runtime.refreshSession(sessionId);
      await requestCaptured.future;
      await tester.pump();
      runtime.beginShutdown();

      await expectLater(savedRequest.resolveText!(), throwsStateError);
      expect(readClipboardCount, 0);
      expect(backend.writeCalls, isEmpty);
      expect(runtime.tryDispose(), isTrue);
      expect(backend.closeCalls, <String>[sessionId]);
    },
  );

  testWidgets('terminal runtime returns structured Host Response v1 denial', (
    tester,
  ) async {
    var readClipboardCount = 0;
    final runtimeBackend = _FakePtyBackend()..hostResponseV1Supported = true;
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async {
        readClipboardCount += 1;
        return 'secret';
      },
      allowClipboardPasteRequest: () async => false,
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final hostRequest = PtyHostRequestV1.fromJson(
      <String, Object?>{
        'schema_version': 1,
        'contract': 'ianvs-host-request-v1',
        'request_id': 'host:$sessionId:4',
        'session_id': sessionId,
        'operation': 'clipboard.read_text',
        'sequence': 4,
        'timestamp_micros': 1201,
        'payload': <String, Object?>{'selection': 'c'},
      },
      expectedSessionId: sessionId,
      expectedSequence: 4,
      expectedTimestampMicros: 1201,
    );
    runtimeBackend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'clipboard_paste_request',
        sessionId: sessionId,
        payload: hostRequest.payload,
        hostRequest: hostRequest,
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    expect(readClipboardCount, 0);
    final response =
        jsonDecode(runtimeBackend.hostResponses.single.$2)
            as Map<String, Object?>;
    expect(response['ok'], isFalse);
    expect(response['payload'], isNull);
    expect(
      (response['error']! as Map<String, Object?>)['code'],
      'permission_denied',
    );
    expect(runtimeBackend.writeCalls, hasLength(1));
    expect(runtimeBackend.writeCalls.single, isEmpty);
  });

  testWidgets(
    'terminal runtime controller skips oversized OSC 52 paste request responses',
    (tester) async {
      var readClipboardCount = 0;
      final seenEvents = <TerminalSessionEvent>[];
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async {
          readClipboardCount += 1;
          return ''.padRight(4 * 1024 * 1024 + 1, 'a');
        },
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final subscription = runtime.events.listen(seenEvents.add);
      addTearDown(subscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(readClipboardCount, 1);
      expect(runtimeBackend.writeCalls, hasLength(1));
      expect(runtimeBackend.writeCalls.single, isEmpty);
      final clipboardEvent = seenEvents
          .whereType<TerminalSessionClipboardEvent>()
          .single;
      expect(clipboardEvent.operation, TerminalClipboardOperation.pasteRequest);
      expect(clipboardEvent.decision, TerminalClipboardDecision.invalidPayload);
    },
  );

  testWidgets(
    'terminal runtime controller skips malformed event payload fields',
    (tester) async {
      final copiedTexts = <String>[];
      final seenEvents = <TerminalSessionEvent>[];
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (text) async {
          copiedTexts.add(text);
        },
        readClipboard: () async => 'paste me',
        allowClipboardCopy: () async => true,
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final subscription = runtime.events.listen(seenEvents.add);
      addTearDown(subscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtime.resizeSession(sessionId, const Size(180, 144), 1);
      runtimeBackend.resizeCalls.clear();

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: const <String, Object?>{'data': 42},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('copy ok')),
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 42},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'resize',
          sessionId: sessionId,
          payload: const <String, Object?>{'cols': 'wide', 'rows': 9},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'resize',
          sessionId: sessionId,
          payload: const <String, Object?>{'cols': 21.5, 'rows': 9},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'resize',
          sessionId: sessionId,
          payload: const <String, Object?>{'cols': 21, 'rows': 9},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 7.5},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();

      expect(copiedTexts, <String>['copy ok']);
      expect(
        utf8.decode(runtimeBackend.writeCalls.last),
        '\x1B]52;c;cGFzdGUgbWU=\x07',
      );
      expect(runtimeBackend.resizeCalls, <List<Object?>>[
        <Object?>[sessionId, 21, 9, 189, 162, 9, 18],
      ]);
      expect(
        seenEvents.whereType<TerminalSessionExitEvent>().single.exitCode,
        isNull,
      );
      final clipboardEvents = seenEvents
          .whereType<TerminalSessionClipboardEvent>()
          .toList();
      expect(
        clipboardEvents.map((event) => event.decision),
        <TerminalClipboardDecision>[
          TerminalClipboardDecision.invalidPayload,
          TerminalClipboardDecision.allowed,
          TerminalClipboardDecision.allowed,
        ],
      );
      expect(clipboardEvents[1].operation, TerminalClipboardOperation.copy);
      expect(clipboardEvents[1].characterCount, 7);
      expect(
        clipboardEvents[2].operation,
        TerminalClipboardOperation.pasteRequest,
      );
      expect(clipboardEvents[2].selection, 'c');
      expect(clipboardEvents[2].characterCount, 8);
      expect(runtime.hasSession(sessionId), isFalse);
    },
  );

  testWidgets('terminal runtime controller ignores events for other sessions', (
    tester,
  ) async {
    final seenEvents = <TerminalSessionEvent>[];
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final subscription = runtime.events.listen(seenEvents.add);
    addTearDown(subscription.cancel);

    final firstSessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final secondSessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/zsh'),
      ),
    );
    runtime.resizeSession(firstSessionId, const Size(180, 144), 1);
    runtimeBackend.resizeCalls.clear();

    runtimeBackend.enqueueEvent(
      firstSessionId,
      PtyEvent(kind: 'bell', sessionId: secondSessionId),
    );
    runtimeBackend.enqueueEvent(
      firstSessionId,
      PtyEvent(
        kind: 'resize',
        sessionId: secondSessionId,
        payload: const <String, Object?>{'cols': 21, 'rows': 9},
      ),
    );
    runtimeBackend.enqueueEvent(
      firstSessionId,
      PtyEvent(
        kind: 'exit',
        sessionId: secondSessionId,
        payload: const <String, Object?>{'code': 0},
      ),
    );

    runtime.sendInput(firstSessionId, Uint8List(0));
    await tester.pump();

    expect(runtime.hasSession(firstSessionId), isTrue);
    expect(runtime.hasSession(secondSessionId), isTrue);
    expect(seenEvents.whereType<TerminalSessionBellEvent>(), isEmpty);
    expect(seenEvents.whereType<TerminalSessionExitEvent>(), isEmpty);
    expect(runtimeBackend.resizeCalls, isEmpty);
  });

  testWidgets(
    'terminal runtime controller keeps metadata events isolated across panes',
    (tester) async {
      final seenEvents = <TerminalSessionEvent>[];
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final subscription = runtime.events.listen(seenEvents.add);
      addTearDown(subscription.cancel);

      final deploySessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final testSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/zsh'),
        ),
      );

      runtimeBackend.enqueueEvent(
        deploySessionId,
        PtyEvent(
          kind: 'session_badge',
          sessionId: deploySessionId,
          payload: const <String, Object?>{
            'source': 'osc1337_set_badge_format',
            'text': 'Deploy',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        deploySessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: deploySessionId,
          payload: const <String, Object?>{
            'source': 'ianvs_osc934',
            'id': 'deploy',
            'state': 'normal',
            'percent': 42,
            'label': 'Deploy',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        testSessionId,
        PtyEvent(
          kind: 'session_badge',
          sessionId: testSessionId,
          payload: const <String, Object?>{
            'source': 'osc1337_set_badge_format',
            'text': 'Test',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        testSessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: testSessionId,
          payload: const <String, Object?>{
            'source': 'ianvs_osc934',
            'id': 'test',
            'state': 'normal',
            'percent': 7,
            'label': 'Test',
          },
        ),
      );

      runtime.sendInput(testSessionId, Uint8List(0));
      runtime.sendInput(deploySessionId, Uint8List(0));
      await tester.pump();

      final badges = seenEvents
          .whereType<TerminalSessionBadgeEvent>()
          .map((event) => (event.sessionId, event.text))
          .toSet();
      expect(badges, <(String, String?)>{
        (deploySessionId, 'Deploy'),
        (testSessionId, 'Test'),
      });

      final progressEvents = seenEvents
          .whereType<TerminalSessionProgressEvent>()
          .map(
            (event) => (event.sessionId, event.id, event.percent, event.label),
          )
          .toSet();
      expect(progressEvents, <(String, String?, int?, String?)>{
        (deploySessionId, 'deploy', 42, 'Deploy'),
        (testSessionId, 'test', 7, 'Test'),
      });
    },
  );

  testWidgets('terminal runtime controller dispose closes active sessions', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );

    runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/zsh'),
      ),
    );

    runtime.dispose();

    expect(runtimeBackend.closeCalls, <String>['1', '2']);
  });

  testWidgets(
    'beginShutdown freezes timers and events without closing backend sessions',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      var clipboardMimeReads = 0;
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        listClipboardMimeTypes: () async {
          clipboardMimeReads += 1;
          return const <String>['text/plain'];
        },
      );
      final seenEvents = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(seenEvents.add);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7',
            'direction': 'receive',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'report_variable_request',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'iterm1337',
            'name': 'session.name',
            'value': 'shell',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();
      final reportVariableRequest = seenEvents
          .whereType<TerminalSessionReportVariableRequestEvent>()
          .single;
      expect(runtime.activeZmodemTransferIdFor(sessionId), '7');
      seenEvents.clear();
      runtimeBackend
        ..closeCalls.clear()
        ..writeCalls.clear()
        ..resizeCalls.clear()
        ..scrollCalls.clear()
        ..scrollToCalls.clear()
        ..graphicAssetRequests.clear()
        ..jsonRequests.clear()
        ..fileDownloadTakeRequests.clear()
        ..fileDownloadDiscardRequests.clear()
        ..diagnosticEventV1Requests.clear()
        ..legacyDiagnosticRequests.clear();

      runtime.beginShutdown();
      runtime.beginShutdown();

      expect(runtime.shutdownHasStarted, isTrue);
      expect(runtimeBackend.closeCalls, isEmpty);
      expect(runtime.hasSession(sessionId), isTrue);
      expect(
        () => runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/zsh'),
          ),
        ),
        throwsStateError,
      );

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(kind: 'bell', sessionId: sessionId),
      );
      runtime.refreshSession(sessionId);
      runtime.sendInput(sessionId, Uint8List(0));
      runtime
        ..setSessionActive(sessionId, active: false)
        ..setSessionFocused(sessionId, focused: true)
        ..closeSession(sessionId)
        ..scrollViewport(sessionId, 1)
        ..scrollViewportTo(sessionId, 1);
      expect(runtime.tryCloseSession(sessionId), isFalse);
      expect(runtime.disposeSession(sessionId), isFalse);
      expect(
        runtime.acceptZmodemReceive(
          TerminalSessionZmodemEvent(
            sessionId,
            rawPayload: const <String, Object?>{
              'source': 'zmodem',
              'eventKind': 'zmodem_file_offer',
              'transferId': '7',
              'direction': 'receive',
              'filename': 'report.txt',
              'size': 5,
            },
          ),
          destination: '/tmp/downloads',
        ),
        isFalse,
      );
      expect(
        runtime.acceptZmodemSend(
          TerminalSessionZmodemEvent(
            sessionId,
            rawPayload: const <String, Object?>{
              'source': 'zmodem',
              'eventKind': 'zmodem_detected',
              'transferId': '7',
              'direction': 'send',
            },
          ),
          files: const <String>['/tmp/report.txt'],
        ),
        isFalse,
      );
      expect(
        runtime.cancelZmodem(
          TerminalSessionZmodemEvent(
            sessionId,
            rawPayload: const <String, Object?>{
              'source': 'zmodem',
              'eventKind': 'zmodem_detected',
              'transferId': '7',
              'direction': 'receive',
            },
          ),
        ),
        isFalse,
      );
      final recoveryEvent = TerminalSessionZmodemEvent(
        sessionId,
        rawPayload: const <String, Object?>{
          'source': 'zmodem',
          'eventKind': 'zmodem_failed',
          'transferId': '7',
          'direction': 'receive',
          'reason': 'publish_failed',
          'recoverablePartialName': '.report.ianvs-part',
          'stagingPreserved': true,
          'recoveryToken': '0123456789abcdef0123456789abcdef',
        },
      );
      expect(
        runtime.resolveZmodemRecovery(recoveryEvent).status,
        TerminalZmodemRecoveryResolutionStatus.requestFailed,
      );
      expect(
        runtime.consumeZmodemRecovery(recoveryEvent),
        TerminalZmodemRecoveryDisposition.requestFailed,
      );
      expect(
        runtime.dismissZmodemRecovery(recoveryEvent),
        TerminalZmodemRecoveryDisposition.requestFailed,
      );
      expect(
        runtime.respondToOsc1337ReportVariable(
          reportVariableRequest,
          value: 'shell',
        ),
        isFalse,
      );
      expect(await runtime.sendOsc5522PasteEvent(sessionId), isFalse);
      expect(
        await runtime.loadGraphicAsset(
          sessionId,
          const TerminalGraphicAssetKey(id: 1, version: 1),
        ),
        isNull,
      );
      final download = TerminalSessionFileDownloadEvent(
        sessionId,
        rawPayload: const <String, Object?>{
          'source': 'iterm1337',
          'transferId': '8',
          'filename': 'report.txt',
          'size': 5,
        },
      );
      expect(runtime.takeFileDownload(download), isNull);
      expect(runtime.discardFileDownload(download), isFalse);
      const selection = TerminalSelection(
        startRow: 0,
        startCol: 0,
        endRow: 0,
        endCol: 1,
      );
      expect(runtime.selectionText(sessionId, selection, block: false), '');
      expect(runtime.searchText(sessionId, 'demo'), isEmpty);
      expect(runtime.clearScrollback(sessionId), isFalse);
      expect(
        runtime.respondSshAuthentication(
          sessionId,
          challengeId: 1,
          responses: const <String>['secret'],
        ),
        isFalse,
      );
      expect(runtime.clearBuffer(sessionId), isFalse);
      expect(
        runtime.dismissOsc99Notification(sessionId, 'notification'),
        isFalse,
      );
      expect(runtime.setBlockFolded(sessionId, 'block', folded: true), isFalse);
      expect(
        runtime.setBlockRendered(sessionId, 'block', rendered: true),
        isFalse,
      );
      expect(runtime.activateItermButton(sessionId, 1).activated, isFalse);
      expect(runtime.exportScrollbackText(sessionId), isNull);
      expect(runtime.exportSessionDiagnostics(sessionId), isNull);
      expect(
        runtime.resizeSession(sessionId, const Size(800, 600), 1),
        isFalse,
      );
      expect(
        runtime.resizeSessionCells(sessionId, cols: 80, rows: 24),
        isFalse,
      );

      expect(seenEvents, isEmpty);
      expect(clipboardMimeReads, 0);
      expect(runtimeBackend.writeCalls, isEmpty);
      expect(runtimeBackend.closeCalls, isEmpty);
      expect(runtimeBackend.resizeCalls, isEmpty);
      expect(runtimeBackend.scrollCalls, isEmpty);
      expect(runtimeBackend.scrollToCalls, isEmpty);
      expect(runtimeBackend.graphicAssetRequests, isEmpty);
      expect(runtimeBackend.jsonRequests, isEmpty);
      expect(runtimeBackend.fileDownloadTakeRequests, isEmpty);
      expect(runtimeBackend.fileDownloadDiscardRequests, isEmpty);
      expect(runtimeBackend.diagnosticEventV1Requests, isEmpty);
      expect(runtimeBackend.legacyDiagnosticRequests, isEmpty);

      runtime.dispose();
      unawaited(subscription.cancel());
      expect(runtimeBackend.closeCalls, <String>[sessionId]);
    },
  );

  testWidgets(
    'viewport and graphics accessors require an active product session',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
        enableWarmUpRefresh: false,
      );
      expect(runtime.existingViewportFor('missing'), isNull);
      expect(() => runtime.viewportFor('missing'), throwsStateError);
      expect(() => runtime.graphicsCacheFor('missing'), throwsStateError);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      final graphics = runtime.graphicsCacheFor(sessionId);
      expect(runtime.existingViewportFor(sessionId), same(viewport));
      expect(runtime.viewportFor(sessionId), same(viewport));
      expect(runtime.graphicsCacheFor(sessionId), same(graphics));

      runtime.beginShutdown();
      expect(runtime.existingViewportFor(sessionId), isNull);
      expect(() => runtime.viewportFor(sessionId), throwsStateError);
      expect(() => runtime.graphicsCacheFor(sessionId), throwsStateError);
      expect(runtime.hasSession(sessionId), isTrue);

      expect(runtime.tryDispose(), isTrue);
      expect(runtime.disposed, isTrue);
      expect(runtime.hasSession(sessionId), isFalse);
      expect(runtime.existingViewportFor(sessionId), isNull);
      expect(() => runtime.viewportFor(sessionId), throwsStateError);
      expect(() => runtime.graphicsCacheFor(sessionId), throwsStateError);
    },
  );

  testWidgets('terminal runtime controller continues to handle exit events', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    var exitHookRanBeforeNativeClose = false;
    var typedExitHookRanBeforeNativeClose = false;
    TerminalSessionPreCloseSignal? typedPreCloseSignal;
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
      beforeSessionCloseOnExit: (_, _) {
        exitHookRanBeforeNativeClose = runtimeBackend.closeCalls.isEmpty;
      },
      beforeSessionCloseOnExitSignal: (signal) {
        typedPreCloseSignal = signal;
        typedExitHookRanBeforeNativeClose = runtimeBackend.closeCalls.isEmpty;
        return const TerminalSessionPreCloseOutcome.allowClose();
      },
    );
    addTearDown(runtime.dispose);

    final seenEvents = <TerminalSessionEvent>[];
    final runtimeEventGaps = <TerminalSessionRuntimeEventGapDiagnostic>[];
    final subscription = runtime.events.listen(seenEvents.add);
    final runtimeEventGapSubscription = runtime.runtimeEventGaps.listen(
      runtimeEventGaps.add,
    );
    addTearDown(subscription.cancel);
    addTearDown(runtimeEventGapSubscription.cancel);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.enqueueEvent(
      sessionId,
      const PtyEvent(
        kind: 'exit',
        sessionId: '1',
        payload: <String, Object?>{'code': 7},
      ),
    );
    runtimeBackend.enqueueEvent(
      sessionId,
      PtyRuntimeEventGapDiagnostic(
        sessionId: sessionId,
        expectedSequence: 3,
        nextSequence: 5,
        droppedCount: 1,
        survivingEventCount: 1,
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    expect(runtime.hasSession(sessionId), isFalse);
    expect(exitHookRanBeforeNativeClose, isTrue);
    expect(typedExitHookRanBeforeNativeClose, isTrue);
    expect(typedPreCloseSignal?.sessionId, sessionId);
    expect(typedPreCloseSignal?.sessionEpoch, isPositive);
    expect(typedPreCloseSignal?.exitCode, 7);
    expect(runtimeBackend.closeCalls, <String>[sessionId]);
    expect(seenEvents.whereType<TerminalSessionExitEvent>().single.exitCode, 7);
    expect(runtimeEventGaps, hasLength(1));
    expect(runtimeEventGaps.single.sessionId, sessionId);
    expect(runtimeEventGaps.single.expectedSequence, 3);
    expect(runtimeEventGaps.single.nextSequence, 5);
    expect(runtimeEventGaps.single.stateRefreshRequested, isFalse);
  });

  testWidgets('pre-close retries once before allowing native exit close', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    var attempts = 0;
    final runtime = TerminalRuntimeController(
      backend: backend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
      beforeSessionCloseOnExitSignal: (_) {
        attempts += 1;
        if (attempts == 1) {
          return TerminalSessionPreCloseOutcome.retryableFailure(
            error: StateError('transient pre-close failure'),
            stackTrace: StackTrace.current,
          );
        }
        return const TerminalSessionPreCloseOutcome.allowClose();
      },
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'exit',
        sessionId: sessionId,
        payload: const <String, Object?>{'code': 4},
      ),
    );

    runtime.refreshSession(sessionId);
    await tester.pump();

    expect(attempts, 2);
    expect(runtime.hasSession(sessionId), isFalse);
    expect(backend.closeCalls, <String>[sessionId]);
  });

  testWidgets(
    'persistent pre-close failure retains session and reports error',
    (tester) async {
      final backend = _FakePtyBackend();
      var attempts = 0;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
        beforeSessionCloseOnExitSignal: (_) {
          attempts += 1;
          return TerminalSessionPreCloseOutcome.retryableFailure(
            error: StateError('persistent pre-close failure'),
            stackTrace: StackTrace.current,
          );
        },
      );
      addTearDown(runtime.dispose);
      final errors = <TerminalSessionBackendErrorEvent>[];
      final subscription = runtime.events.listen((event) {
        if (event is TerminalSessionBackendErrorEvent) {
          errors.add(event);
        }
      });
      addTearDown(subscription.cancel);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 5},
        ),
      );

      runtime.refreshSession(sessionId);
      await tester.pump();

      expect(attempts, 2);
      expect(runtime.hasSession(sessionId), isTrue);
      expect(backend.closeCalls, isEmpty);
      expect(errors, hasLength(1));
      expect(errors.single.operation, 'beforeSessionCloseOnExitSignal');
      expect(errors.single.error, isA<StateError>());
    },
  );

  testWidgets(
    'beginShutdown cancels product exit-close retries until infra disposal',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
        enableWarmUpRefresh: false,
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      backend.retryableCloseSessionIds.add(sessionId);
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 0},
        ),
      );

      runtime.refreshSession(sessionId);
      await tester.pump();

      expect(runtime.hasSession(sessionId), isTrue);
      expect(backend.closeCalls, isEmpty);

      runtime.beginShutdown();
      backend.retryableCloseSessionIds.remove(sessionId);
      await tester.pump(const Duration(milliseconds: 60));

      expect(runtime.hasSession(sessionId), isTrue);
      expect(backend.closeCalls, isEmpty);
      expect(runtime.tryDispose(), isTrue);
      expect(runtime.hasSession(sessionId), isFalse);
      expect(backend.closeCalls, <String>[sessionId]);
    },
  );

  testWidgets(
    'polling-disabled runtime follows a native pending-exit hint to completion',
    (tester) async {
      final backend = _RefreshHintPtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
        enableWarmUpRefresh: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final pollsBeforeExit = backend.pollEventsCalls;

      backend.hintFlags = PtyRefreshHintFlags.exitPending;
      runtime.refreshSession(sessionId);
      await tester.pump();
      backend.hintFlags = PtyRefreshHintFlags.eventPending;
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 0},
        ),
      );

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(backend.pollEventsCalls, greaterThan(pollsBeforeExit + 1));
      expect(runtime.hasSession(sessionId), isFalse);
      expect(backend.closeCalls, <String>[sessionId]);
    },
  );

  testWidgets(
    'polling-disabled runtime follows exit tail after ZMODEM failure',
    (tester) async {
      final backend = _RefreshHintPtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
        enableWarmUpRefresh: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '88',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);

      backend.hintFlags = PtyRefreshHintFlags.exitPending;
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_failed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '88',
            'direction': 'receive',
            'reason': 'timeout',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);

      backend.hintFlags = PtyRefreshHintFlags.eventPending;
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 1},
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(runtime.hasSession(sessionId), isFalse);
      expect(backend.closeCalls, <String>[sessionId]);
    },
  );

  testWidgets(
    'terminal runtime controller applies the final frame before handling exit',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final seenEvents = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(seenEvents.add);
      addTearDown(subscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      await tester.pump();
      seenEvents.clear();
      runtimeBackend.setFrame(sessionId, _singleRowSnapshot('final output'));
      runtimeBackend.enqueueEvent(
        sessionId,
        const PtyEvent(
          kind: 'exit',
          sessionId: '1',
          payload: <String, Object?>{'code': 9},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'final output');
      expect(seenEvents.map((event) => event.runtimeType).toList(), <Type>[
        TerminalSessionFrameEvent,
        TerminalSessionExitEvent,
      ]);
      expect(
        seenEvents.whereType<TerminalSessionExitEvent>().single.exitCode,
        9,
      );
      expect(
        seenEvents
            .whereType<TerminalSessionExitEvent>()
            .single
            .finalFrame
            ?.rows
            .first
            .text,
        'final output',
      );
      expect(runtime.hasSession(sessionId), isFalse);
    },
  );

  testWidgets(
    'terminal runtime controller continues to handle clipboard and resize events',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      String copiedText = '';
      String? pasteWrite;
      double? resizeWidthDelta;
      double? resizeHeightDelta;
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (text) async {
          copiedText = text;
        },
        readClipboard: () async => 'paste me',
        allowClipboardCopy: () async => true,
        allowClipboardPasteRequest: () async => true,
        resizeWindowBy: ({required widthDelta, required heightDelta}) async {
          resizeWidthDelta = widthDelta;
          resizeHeightDelta = heightDelta;
        },
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtime.resizeSession(sessionId, const Size(180, 144), 1);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('copied text')),
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'resize',
          sessionId: sessionId,
          payload: const <String, Object?>{'cols': 21, 'rows': 9},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      pasteWrite = utf8.decode(runtimeBackend.writeCalls.last);

      expect(copiedText, 'copied text');
      expect(pasteWrite, '\x1B]52;c;cGFzdGUgbWU=\x07');
      expect(resizeWidthDelta, 9);
      expect(resizeHeightDelta, 18);
      expect(runtimeBackend.resizeCalls.last, <Object?>[
        '1',
        21,
        9,
        189,
        162,
        9,
        18,
      ]);
    },
  );

  test(
    'terminal runtime emits benchmark stats only when a sink is provided',
    () async {
      final runtimeBackend = _FakePtyBackend();
      final benchmarkEvents = <Map<String, Object?>>[];
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
        benchmarkEventSink: benchmarkEvents.add,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      benchmarkEvents.clear();

      runtime.refreshSession(sessionId);
      await Future<void>.delayed(Duration.zero);

      expect(benchmarkEvents, isNotEmpty);
      final event = benchmarkEvents.singleWhere(
        (event) => event['schema_version'] == 'ianvs-bench-dart-runtime-v1',
      );
      expect(event['session_id'], sessionId);
      expect(event['frame_kind'], 'snapshot');
      expect(event['raw_frame_bytes'], greaterThan(0));
      expect(event['json_decode_micros'], isA<int>());
      expect(event['apply_frame_micros'], isA<int>());
      expect(event['viewport_hash_after_apply'], isA<String>());
    },
  );

  test(
    'terminal runtime emits graphics diagnostics for synchronized skipped frames',
    () async {
      final runtimeBackend = _FakePtyBackend();
      final diagnosticEvents = <Map<String, Object?>>[];
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        benchmarkEventSink: diagnosticEvents.add,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      diagnosticEvents.clear();

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        ..._singleRowSnapshot('sync pet'),
        'frame_kind': 'delta',
        'modes': <String, Object?>{'synchronized_output': true},
        'graphics': <Object?>[],
      });
      runtime.refreshSession(sessionId);
      await Future<void>.delayed(Duration.zero);

      final graphicsEvent = diagnosticEvents.singleWhere(
        (event) =>
            event['schema_version'] ==
                'ianvs-terminal-graphics-diagnostic-v1' &&
            event['layer'] == 'runtime' &&
            event['event'] == 'frame_skipped_synchronized',
      );
      expect(graphicsEvent['session_id'], sessionId);
      expect(graphicsEvent['incoming_graphics_count'], 0);
      expect(graphicsEvent['applied_graphics_count'], 0);
    },
  );

  test('terminal runtime emits protobuf benchmark decode stats', () async {
    final runtimeBackend = _ProtobufFramePtyBackend();
    final benchmarkEvents = <Map<String, Object?>>[];
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
      benchmarkEventSink: benchmarkEvents.add,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    benchmarkEvents.clear();

    runtimeBackend.enqueueProtobufFrame(
      sessionId,
      _singleRowProtobuf('protobuf benchmark'),
    );
    runtime.refreshSession(sessionId);
    await Future<void>.delayed(Duration.zero);

    final event = benchmarkEvents.singleWhere(
      (event) => event['schema_version'] == 'ianvs-bench-dart-runtime-v1',
    );
    expect(event['wire_format'], 'protobuf');
    expect(event['raw_frame_bytes'], greaterThan(0));
    expect(event['json_decode_micros'], 0);
    expect(event['protobuf_decode_micros'], isA<int>());
  });

  test('terminal runtime emits native frame benchmark stats', () async {
    final runtimeBackend =
        _ProtobufFramePtyBackend(
            initialFrame: _singleRowProtobuf('native stats'),
          )
          ..frameDiagnosticsRawResponse = jsonEncode(<String, Object?>{
            'rows_scanned': 40,
            'rows_emitted': 8,
            'frame_build_micros': 321,
            'json_encode_micros': 0,
            'protobuf_encode_micros': 17,
          });
    final benchmarkEvents = <Map<String, Object?>>[];
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
      benchmarkEventSink: benchmarkEvents.add,
    );
    addTearDown(runtime.dispose);

    runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final event = benchmarkEvents.singleWhere(
      (event) => event['schema_version'] == 'ianvs-bench-dart-runtime-v1',
    );
    expect(event['native_frame_build_micros'], 321);
    expect(event['native_json_encode_micros'], 0);
    expect(event['native_protobuf_encode_micros'], 17);
    expect(event['native_rows_scanned'], 40);
    expect(event['native_rows_emitted'], 8);
  });

  test('terminal runtime prefers Diagnostic Event v1 frame stats', () async {
    final runtimeBackend =
        _ProtobufFramePtyBackend(
            initialFrame: _singleRowProtobuf('diagnostic v1 stats'),
          )
          ..diagnosticEventV1Supported = true
          ..frameDiagnosticV1Payload = <String, Object?>{
            'rows_scanned': 41,
            'rows_emitted': 9,
            'frame_build_micros': 654,
            'json_encode_micros': 0,
            'protobuf_encode_micros': 21,
          }
          ..frameDiagnosticsRawResponse = jsonEncode(<String, Object?>{
            'rows_scanned': 1,
            'frame_build_micros': 1,
          });
    final benchmarkEvents = <Map<String, Object?>>[];
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
      benchmarkEventSink: benchmarkEvents.add,
    );
    addTearDown(runtime.dispose);

    runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final event = benchmarkEvents.singleWhere(
      (event) => event['schema_version'] == 'ianvs-bench-dart-runtime-v1',
    );
    expect(event['native_frame_build_micros'], 654);
    expect(event['native_protobuf_encode_micros'], 21);
    expect(event['native_rows_scanned'], 41);
    expect(event['native_rows_emitted'], 9);
    expect(runtimeBackend.diagnosticEventV1Requests, <(String, String)>[
      ('1', 'frame_stats'),
    ]);
    expect(runtimeBackend.legacyDiagnosticRequests, isEmpty);
  });

  testWidgets(
    'OSC 5522 writes multiple binary MIME representations and replies DONE',
    (tester) async {
      final backend = _FakePtyBackend();
      final written = <TerminalClipboardMimeItem>[];
      final events = <TerminalSessionClipboardEvent>[];
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        writeMimeClipboard: (items) async => written.addAll(items),
        allowClipboardCopyWithContext: (request) async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final subscription = runtime.events
          .where((event) => event is TerminalSessionClipboardEvent)
          .cast<TerminalSessionClipboardEvent>()
          .listen(events.add);
      addTearDown(subscription.cancel);
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_mime_write',
          sessionId: sessionId,
          payload: <String, Object?>{
            'protocol': 'osc5522',
            'location': 'clipboard',
            'id': 'write-1',
            'items': <Object?>[
              <String, Object?>{
                'mime': 'text/plain',
                'data': base64.encode(utf8.encode('hello')),
                'aliases': <String>['text/utf8'],
              },
              <String, Object?>{
                'mime': 'image/png',
                'data': base64.encode(<int>[0, 1, 2, 255]),
              },
            ],
          },
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();

      expect(written.map((item) => item.mimeType), <String>[
        'text/plain',
        'image/png',
      ]);
      expect(written[0].aliases, <String>['text/utf8']);
      expect(written[1].bytes, <int>[0, 1, 2, 255]);
      expect(
        ascii.decode(backend.writeCalls.last),
        '\u001b]5522;type=write:status=DONE:id=write-1\u001b\\',
      );
      expect(events.single.protocol, 'osc5522');
      expect(events.single.operation, TerminalClipboardOperation.mimeWrite);
      expect(events.single.mimeTypes, <String>['text/plain', 'image/png']);
      expect(events.single.byteCount, 9);
    },
  );

  testWidgets(
    'OSC 5522 lists MIME types without permission and chunks allowed binary reads',
    (tester) async {
      final backend = _FakePtyBackend();
      var permissionRequests = 0;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        listClipboardMimeTypes: () async => <String>['text/plain', 'image/png'],
        readMimeClipboard: (types) async => <TerminalClipboardMimeItem>[
          TerminalClipboardMimeItem(
            mimeType: 'image/png',
            bytes: Uint8List.fromList(
              List<int>.generate(5000, (index) => index % 251),
            ),
          ),
        ],
        allowClipboardPasteRequestWithContext: (request) async {
          permissionRequests += 1;
          return true;
        },
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_mime_read_request',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'location': 'clipboard',
            'id': 'list-1',
            'mimeTypes': <String>['.'],
            'listOnly': true,
          },
        ),
      );
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();
      expect(permissionRequests, 0);
      expect(
        backend.writeCalls.map(ascii.decode).join(),
        contains(base64.encode(utf8.encode('image/png text/plain'))),
      );

      backend.writeCalls.clear();
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_mime_read_request',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'location': 'clipboard',
            'id': 'read-1',
            'mimeTypes': <String>['image/*'],
            'listOnly': false,
          },
        ),
      );
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();

      final responses = backend.writeCalls.map(ascii.decode).join();
      expect(permissionRequests, 1);
      expect(RegExp('status=DATA').allMatches(responses), hasLength(2));
      expect(
        responses,
        startsWith('\u001b]5522;type=read:status=OK:id=read-1'),
      );
      expect(
        responses,
        endsWith('\u001b]5522;type=read:status=DONE:id=read-1\u001b\\'),
      );
    },
  );

  testWidgets(
    'OSC 5522 denies unauthorized MIME access and reports unsupported primary selection',
    (tester) async {
      final backend = _FakePtyBackend();
      var platformWrites = 0;
      var platformReads = 0;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        writeMimeClipboard: (_) async => platformWrites += 1,
        readMimeClipboard: (_) async {
          platformReads += 1;
          return const <TerminalClipboardMimeItem>[];
        },
        allowClipboardCopyWithContext: (_) async => false,
        allowClipboardPasteRequestWithContext: (_) async => false,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_mime_write',
          sessionId: sessionId,
          payload: <String, Object?>{
            'location': 'clipboard',
            'id': 'deny-write',
            'items': <Object?>[
              <String, Object?>{
                'mime': 'application/octet-stream',
                'data': base64.encode(<int>[1, 2, 3]),
              },
            ],
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_mime_read_request',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'location': 'clipboard',
            'id': 'deny-read',
            'mimeTypes': <String>['application/*'],
            'listOnly': false,
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_mime_write',
          sessionId: sessionId,
          payload: <String, Object?>{
            'location': 'primary',
            'id': 'primary-write',
            'items': <Object?>[
              <String, Object?>{
                'mime': 'text/plain',
                'data': base64.encode(utf8.encode('ignored')),
              },
            ],
          },
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();

      final responses = backend.writeCalls.map(ascii.decode).join();
      expect(platformWrites, 0);
      expect(platformReads, 0);
      expect(responses, contains('type=write:status=EPERM:id=deny-write'));
      expect(responses, contains('type=read:status=EPERM:id=deny-read'));
      expect(responses, contains('type=write:status=ENOSYS:id=primary-write'));
    },
  );

  testWidgets(
    'OSC 5522 remembers an application password for later session access',
    (tester) async {
      final backend = _FakePtyBackend();
      backend.forcedSessionId = 'same-tty-id';
      var authorizations = 0;
      var platformWrites = 0;
      var platformReads = 0;
      final authorizationRequests = <TerminalClipboardAccessRequest>[];
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        writeMimeClipboard: (_) async => platformWrites += 1,
        readMimeClipboard: (_) async {
          platformReads += 1;
          return <TerminalClipboardMimeItem>[
            TerminalClipboardMimeItem(
              mimeType: 'text/plain',
              bytes: Uint8List.fromList(utf8.encode('remembered')),
            ),
          ];
        },
        authorizeMimeClipboardAccessWithContext: (request) async {
          authorizations += 1;
          authorizationRequests.add(request);
          return TerminalClipboardAuthorization.allowSession;
        },
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_mime_write',
          sessionId: sessionId,
          payload: <String, Object?>{
            'location': 'clipboard',
            'id': 'remember-write',
            'password': 'secret',
            'applicationName': 'Editor',
            'items': <Object?>[
              <String, Object?>{
                'mime': 'text/plain',
                'data': base64.encode(utf8.encode('hello')),
              },
            ],
          },
        ),
      );
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_mime_read_request',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'location': 'clipboard',
            'id': 'remember-read',
            'password': 'secret',
            'applicationName': 'Editor',
            'mimeTypes': <String>['text/plain'],
            'listOnly': false,
          },
        ),
      );
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();

      expect(authorizations, 1);
      expect(authorizationRequests.single.authorizationPassword, 'secret');
      expect(authorizationRequests.single.applicationName, 'Editor');
      expect(authorizationRequests.single.canRememberPassword, isTrue);
      expect(platformWrites, 1);
      expect(platformReads, 1);
      expect(
        backend.writeCalls.map(ascii.decode).join(),
        contains('type=read:status=DONE:id=remember-read'),
      );

      runtime.closeSession(sessionId);
      final replacementSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      expect(replacementSessionId, sessionId);
      backend.enqueueEvent(
        replacementSessionId,
        PtyEvent(
          kind: 'clipboard_mime_write',
          sessionId: replacementSessionId,
          payload: <String, Object?>{
            'location': 'clipboard',
            'id': 'after-close',
            'password': 'secret',
            'applicationName': 'Editor',
            'items': <Object?>[
              <String, Object?>{
                'mime': 'text/plain',
                'data': base64.encode(utf8.encode('new session')),
              },
            ],
          },
        ),
      );
      runtime.sendInput(replacementSessionId, Uint8List(0));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();

      expect(authorizations, 2);
      expect(platformWrites, 2);
    },
  );

  testWidgets(
    'OSC 5522 never remembers a password without an application name',
    (tester) async {
      final backend = _FakePtyBackend();
      var authorizations = 0;
      final rememberCapabilities = <bool>[];
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        writeMimeClipboard: (_) async {},
        authorizeMimeClipboardAccessWithContext: (request) async {
          authorizations += 1;
          rememberCapabilities.add(request.canRememberPassword);
          return TerminalClipboardAuthorization.allowSession;
        },
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      PtyEvent event(String id) => PtyEvent(
        kind: 'clipboard_mime_write',
        sessionId: sessionId,
        payload: <String, Object?>{
          'location': 'clipboard',
          'id': id,
          'password': 'no-name',
          'items': <Object?>[
            <String, Object?>{
              'mime': 'text/plain',
              'data': base64.encode(utf8.encode('hello')),
            },
          ],
        },
      );

      for (final id in <String>['first', 'second']) {
        backend.enqueueEvent(sessionId, event(id));
        runtime.sendInput(sessionId, Uint8List(0));
        await tester.pump(const Duration(milliseconds: 40));
        await tester.pump();
      }

      expect(authorizations, 2);
      expect(rememberCapabilities, <bool>[false, false]);
    },
  );

  testWidgets(
    'OSC 5522 paste event advertises MIME types and consumes its token once',
    (tester) async {
      final backend = _FakePtyBackend();
      var authorizations = 0;
      var platformReads = 0;
      var now = Duration.zero;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        listClipboardMimeTypes: () async => <String>[
          'text/plain',
          'image/png',
          'text/plain',
          'invalid',
        ],
        readMimeClipboard: (_) async {
          platformReads += 1;
          return <TerminalClipboardMimeItem>[
            TerminalClipboardMimeItem(
              mimeType: 'text/plain',
              bytes: Uint8List.fromList(utf8.encode('paste event')),
            ),
          ];
        },
        authorizeMimeClipboardAccessWithContext: (_) async {
          authorizations += 1;
          return TerminalClipboardAuthorization.denied;
        },
        monotonicNow: () => now,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      expect(await runtime.sendOsc5522PasteEvent(sessionId), isTrue);
      final eventPackets = backend.writeCalls.map(ascii.decode).toList();
      expect(eventPackets, hasLength(4));
      expect(
        eventPackets[1],
        '\u001b]5522;type=read:status=DATA:mime=aW1hZ2UvcG5n\u001b\\',
      );
      expect(
        eventPackets[2],
        '\u001b]5522;type=read:status=DATA:mime=dGV4dC9wbGFpbg==\u001b\\',
      );
      expect(eventPackets.last, '\u001b]5522;type=read:status=DONE\u001b\\');
      final encodedPassword = RegExp(
        r':pw=([^\x1b]+)',
      ).firstMatch(eventPackets.first)!.group(1)!;
      final password = utf8.decode(base64.decode(encodedPassword));

      PtyEvent readEvent(String id, String token) => PtyEvent(
        kind: 'clipboard_mime_read_request',
        sessionId: sessionId,
        payload: <String, Object?>{
          'location': 'clipboard',
          'id': id,
          'password': token,
          'mimeTypes': const <String>['text/plain'],
          'listOnly': false,
        },
      );
      backend.writeCalls.clear();
      backend.enqueueEvent(sessionId, readEvent('token-once', password));
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();
      expect(authorizations, 0);
      expect(platformReads, 1);
      expect(
        backend.writeCalls.map(ascii.decode).join(),
        contains('type=read:status=DONE:id=token-once'),
      );

      backend.writeCalls.clear();
      backend.enqueueEvent(sessionId, readEvent('token-reused', password));
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();
      expect(authorizations, 1);
      expect(platformReads, 1);
      expect(
        backend.writeCalls.map(ascii.decode).join(),
        contains('type=read:status=EPERM:id=token-reused'),
      );

      expect(await runtime.sendOsc5522PasteEvent(sessionId), isTrue);
      final expiredPacket = backend.writeCalls
          .map(ascii.decode)
          .lastWhere((packet) => packet.contains(':status=OK:pw='));
      final expiredEncoded = RegExp(
        r':pw=([^\x1b]+)',
      ).firstMatch(expiredPacket)!.group(1)!;
      final expiredPassword = utf8.decode(base64.decode(expiredEncoded));
      now = const Duration(seconds: 11);
      backend.enqueueEvent(sessionId, readEvent('expired', expiredPassword));
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();
      expect(authorizations, 2);
      expect(platformReads, 1);
    },
  );

  testWidgets(
    'ZMODEM events lock terminal input and authorize only the active transfer',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final sessionEvents = <TerminalSessionEvent>[];
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final deferredWriteFailures =
          <TerminalSessionZmodemDeferredWriteFailedDiagnostic>[];
      final runtimeEventGaps = <TerminalSessionRuntimeEventGapDiagnostic>[];
      final sessionSubscription = runtime.events.listen(sessionEvents.add);
      final zmodemSubscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      final deferredWriteFailureSubscription = runtime
          .zmodemDeferredWriteFailures
          .listen(deferredWriteFailures.add);
      final runtimeEventGapSubscription = runtime.runtimeEventGaps.listen(
        runtimeEventGaps.add,
      );
      addTearDown(sessionSubscription.cancel);
      addTearDown(zmodemSubscription.cancel);
      addTearDown(deferredWriteFailureSubscription.cancel);
      addTearDown(runtimeEventGapSubscription.cancel);
      backend.writeCalls.clear();

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(runtime.activeZmodemTransferIdFor(sessionId), '7');
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x41]));
      expect(backend.writeCalls, isEmpty);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_file_offer',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7',
            'direction': 'receive',
            'filename': 'report.txt',
            'size': null,
            'modificationTimeSeconds': 1700000456,
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();
      final offer = zmodemEvents
          .where((event) => event.kind == TerminalZmodemEventKind.fileOffer)
          .single;
      expect(
        sessionEvents,
        everyElement(isA<TerminalSessionFrameEvent>()),
        reason: 'ZMODEM does not widen the sealed TerminalSessionEvent stream',
      );
      expect(offer.isValid, isTrue);
      expect(offer.filename, 'report.txt');
      expect(offer.size, isNull);
      expect(offer.hasKnownSize, isFalse);
      expect(offer.modificationTimeSeconds, 1700000456);
      expect(
        TerminalSessionZmodemEvent(
          sessionId,
          rawPayload: const <String, Object?>{
            'source': 'zmodem',
            'eventKind': 'zmodem_file_offer',
            'transferId': '7',
            'direction': 'receive',
            'filename': 'epoch-is-unavailable.bin',
            'size': 1,
            'modificationTimeSeconds': 0,
          },
        ).modificationTimeSeconds,
        isNull,
      );
      expect(
        runtime.acceptZmodemReceive(offer, destination: '/tmp/downloads'),
        isTrue,
      );
      expect(backend.jsonRequests.last, <String, Object?>{
        'kind': 'terminal.zmodem.accept_receive',
        'transferId': '7',
        'destination': '/tmp/downloads',
      });

      expect(
        runtime.acceptZmodemReceive(
          TerminalSessionZmodemEvent(
            sessionId,
            rawPayload: const <String, Object?>{
              'source': 'zmodem',
              'eventKind': 'zmodem_file_offer',
              'transferId': '8',
              'direction': 'receive',
              'filename': '../escape',
              'size': 1,
            },
          ),
          destination: '/tmp/downloads',
        ),
        isFalse,
      );

      TerminalSessionZmodemEvent filenameOffer(String filename) =>
          TerminalSessionZmodemEvent(
            sessionId,
            rawPayload: <String, Object?>{
              'source': 'zmodem',
              'eventKind': 'zmodem_file_offer',
              'transferId': '7',
              'direction': 'receive',
              'filename': filename,
              'size': null,
            },
          );
      expect(filenameOffer('a' * 240).isValid, isTrue);
      expect(filenameOffer('a' * 241).isValid, isFalse);
      expect(filenameOffer('😀' * 60).isValid, isTrue);
      expect(filenameOffer('😀' * 61).isValid, isFalse);
      expect(filenameOffer('CON.txt').isValid, isFalse);
      expect(filenameOffer('bad?.txt').isValid, isFalse);
      expect(filenameOffer('发票-東京-😀.jpg').isValid, isTrue);

      const bidiControls = <int>[
        0x061c,
        0x200e,
        0x200f,
        0x202a,
        0x202b,
        0x202c,
        0x202d,
        0x202e,
        0x2066,
        0x2067,
        0x2068,
        0x2069,
      ];
      for (final rune in bidiControls) {
        expect(
          filenameOffer('invoice${String.fromCharCode(rune)}gpj.exe').isValid,
          isFalse,
          reason:
              'U+${rune.toRadixString(16).padLeft(4, '0')} must be rejected',
        );
      }
      final maliciousOffer = filenameOffer('invoice\u202Egpj.exe');
      expect(maliciousOffer.filename, isNull);
      expect(maliciousOffer.isValid, isFalse);
      expect(
        runtime.acceptZmodemReceive(
          maliciousOffer,
          destination: '/tmp/downloads',
        ),
        isFalse,
      );

      final exactLimitTrailingDot = '${'a' * 239}.';
      expect(utf8.encode(exactLimitTrailingDot), hasLength(240));
      expect(filenameOffer(exactLimitTrailingDot).isValid, isFalse);

      final publishFailure = TerminalSessionZmodemEvent(
        sessionId,
        rawPayload: const <String, Object?>{
          'source': 'zmodem',
          'eventKind': 'zmodem_failed',
          'transferId': '7',
          'direction': 'receive',
          'reason': 'publish_failed',
          'recoverablePartialName': '.report.ianvs-part',
          'stagingPreserved': true,
          'recoveryToken': '0123456789abcdef0123456789ABCDEF',
          'recoverablePartialPath': '/private/downloads/.report.ianvs-part',
        },
      );
      expect(publishFailure.isValid, isTrue);
      expect(publishFailure.recoverablePartialName, '.report.ianvs-part');
      expect(publishFailure.stagingPreserved, isTrue);
      expect(publishFailure.recoveryToken, '0123456789abcdef0123456789abcdef');
      expect(
        publishFailure.rawPayload.containsKey('recoverablePartialPath'),
        isFalse,
      );
      expect(publishFailure.rawPayload.containsKey('recoveryToken'), isFalse);
      backend.zmodemRecoveryPath = '/current/downloads/.report.ianvs-part';
      final recovery = runtime.resolveZmodemRecovery(publishFailure);
      expect(recovery.status, TerminalZmodemRecoveryResolutionStatus.available);
      expect(recovery.path, '/current/downloads/.report.ianvs-part');
      expect(backend.jsonRequests.last, <String, Object?>{
        'kind': 'terminal.zmodem.resolve_recovery',
        'recoveryToken': '0123456789abcdef0123456789abcdef',
      });
      expect(
        TerminalSessionZmodemEvent(
          sessionId,
          rawPayload: const <String, Object?>{
            'source': 'zmodem',
            'eventKind': 'zmodem_failed',
            'transferId': '7',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '../escaped.part',
            'stagingPreserved': true,
          },
        ).isValid,
        isFalse,
      );
      final invalidTokenFailure = TerminalSessionZmodemEvent(
        sessionId,
        rawPayload: const <String, Object?>{
          'source': 'zmodem',
          'eventKind': 'zmodem_failed',
          'transferId': '7',
          'direction': 'receive',
          'reason': 'publish_failed',
          'recoverablePartialName': '.report.ianvs-part',
          'stagingPreserved': true,
          'recoveryToken': 'not-a-token',
        },
      );
      expect(invalidTokenFailure.isValid, isTrue);
      expect(invalidTokenFailure.recoveryToken, isNull);
      expect(
        invalidTokenFailure.rawPayload.containsKey('recoveryToken'),
        isFalse,
      );

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_completed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x42]));
      expect(backend.writeCalls.single, Uint8List.fromList(const <int>[0x42]));

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '8',
            'direction': 'send',
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_file_skipped',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '8',
            'direction': 'send',
            'filename': 'already-there.bin',
            'size': 512,
            'completedFiles': 1,
            'skippedFiles': 1,
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.activeZmodemTransferIdFor(sessionId), '8');
      expect(
        zmodemEvents.last.kind,
        TerminalZmodemEventKind.fileSkipped,
        reason: 'skipping one file must not terminate the remaining batch',
      );
      expect(zmodemEvents.last.completedFiles, 1);
      expect(zmodemEvents.last.skippedFiles, 1);
      expect(sessionEvents, everyElement(isA<TerminalSessionFrameEvent>()));

      final zmodemEventCountBeforeDiagnostic = zmodemEvents.length;
      backend.enqueueEvent(
        sessionId,
        const PtyEvent(
          kind: 'zmodem_deferred_write_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'reason': 'io_error',
            'queuedChunks': 3,
            'queuedBytes': 12,
            'completedChunks': 1,
            'completedBytes': 4,
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.activeZmodemTransferIdFor(sessionId), '8');
      expect(zmodemEvents, hasLength(zmodemEventCountBeforeDiagnostic));
      expect(deferredWriteFailures, hasLength(1));
      final deferredWriteFailure = deferredWriteFailures.single;
      expect(deferredWriteFailure.sessionId, sessionId);
      expect(deferredWriteFailure.source, 'zmodem');
      expect(deferredWriteFailure.reason, 'io_error');
      expect(deferredWriteFailure.queuedChunks, 3);
      expect(deferredWriteFailure.queuedBytes, 12);
      expect(deferredWriteFailure.completedChunks, 1);
      expect(deferredWriteFailure.completedBytes, 4);
      expect(deferredWriteFailure.unconfirmedChunks, 2);
      expect(deferredWriteFailure.unconfirmedBytes, 8);

      backend.cancelActiveZmodemResponse = false;
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_completed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '8',
            'direction': 'send',
            'completedFiles': 1,
            'skippedFiles': 1,
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 4,
          nextSequence: 6,
          droppedCount: 1,
          survivingEventCount: 1,
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(zmodemEvents.last.kind, TerminalZmodemEventKind.completed);
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(runtimeEventGaps, hasLength(1));
      expect(runtimeEventGaps.single.expectedSequence, 4);
      expect(runtimeEventGaps.single.nextSequence, 6);
      expect(runtimeEventGaps.single.droppedCount, 1);
      expect(runtimeEventGaps.single.survivingEventCount, 1);
      expect(runtimeEventGaps.single.affectedZmodemTransferId, '8');
      expect(runtimeEventGaps.single.zmodemStateCleared, isFalse);
      expect(runtimeEventGaps.single.zmodemCancellationAccepted, isFalse);
      expect(runtimeEventGaps.single.stateRefreshRequested, isTrue);
      final writesWhileGapAuthorityIsUnknown = backend.writeCalls.length;
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x43]));
      expect(backend.writeCalls, hasLength(writesWhileGapAuthorityIsUnknown));

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '9',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x43]));
      expect(backend.writeCalls.last, Uint8List.fromList(const <int>[0x43]));
    },
  );

  testWidgets(
    'Runtime Event gaps preserve a standalone publish recovery token',
    (tester) async {
      final backend = _FakePtyBackend()..cancelActiveZmodemOutcome = 'idle';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      addTearDown(subscription.cancel);

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 3,
          nextSequence: 7,
          droppedCount: 4,
          survivingEventCount: 1,
        ),
      );
      backend.enqueueEvent(
        sessionId,
        const PtyEvent(
          kind: 'zmodem_failed',
          sessionId: '1',
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.complete.ianvs-part',
            'stagingPreserved': true,
            'recoveryToken': '1234567890abcdef1234567890abcdef',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(zmodemEvents, hasLength(1));
      expect(zmodemEvents.single.hasRecoverableReceiveStaging, isTrue);
      expect(
        zmodemEvents.single.recoveryToken,
        '1234567890abcdef1234567890abcdef',
      );
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
    },
  );

  testWidgets(
    'ZMODEM detection racing input pauses without a backend error event',
    (tester) async {
      final backend = _FakePtyBackend()..failingOperations.add('writeInput');
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final sessionEvents = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(sessionEvents.add);
      addTearDown(subscription.cancel);
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'send',
          },
        ),
      );

      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x41]));
      await tester.pump();

      expect(runtime.activeZmodemTransferIdFor(sessionId), '72');
      expect(
        sessionEvents.whereType<TerminalSessionBackendErrorEvent>(),
        isEmpty,
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
    },
  );

  testWidgets('async terminal protocol reply waits for ZMODEM terminal state', (
    tester,
  ) async {
    final clipboard = Completer<String>();
    final backend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: backend,
      copyToClipboard: (_) async {},
      readClipboard: () => clipboard.future,
      allowClipboardPasteRequest: () async => true,
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    backend.writeCalls.clear();
    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'clipboard_paste_request',
        sessionId: sessionId,
        payload: const <String, Object?>{'selection': 'c'},
      ),
    );
    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'zmodem_detected',
        sessionId: sessionId,
        payload: const <String, Object?>{
          'source': 'zmodem',
          'transferId': '721',
          'direction': 'send',
        },
      ),
    );

    runtime.refreshSession(sessionId);
    await tester.pump();
    expect(runtime.isZmodemTransferActive(sessionId), isTrue);
    clipboard.complete('reply after detection');
    await tester.pump();
    await tester.pump();
    expect(backend.writeCalls, isEmpty);

    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'zmodem_cancelled',
        sessionId: sessionId,
        payload: const <String, Object?>{
          'source': 'zmodem',
          'transferId': '721',
          'direction': 'send',
        },
      ),
    );
    runtime.refreshSession(sessionId);
    await tester.pump();
    await tester.pump();

    expect(backend.writeCalls, hasLength(1));
    expect(
      utf8.decode(backend.writeCalls.single),
      '\x1B]52;c;${base64.encode(utf8.encode('reply after detection'))}\x07',
    );
  });

  testWidgets(
    'deferred protocol reply waits across a contiguous successor transfer',
    (tester) async {
      final clipboard = Completer<String>();
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () => clipboard.future,
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      backend.writeCalls.clear();
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7211',
            'direction': 'send',
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      clipboard.complete('reply after both transfers');
      await tester.pump();
      expect(backend.writeCalls, isEmpty);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_completed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7211',
            'direction': 'send',
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7212',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();

      expect(runtime.activeZmodemTransferIdFor(sessionId), '7212');
      expect(backend.writeCalls, isEmpty);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7212',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(backend.writeCalls, hasLength(1));
      expect(
        utf8.decode(backend.writeCalls.single),
        '\x1B]52;c;${base64.encode(utf8.encode('reply after both transfers'))}\x07',
      );
    },
  );

  testWidgets(
    'fallback protocol reply survives detection racing its flush write',
    (tester) async {
      final backend = _ProtocolReplyFlushRacePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => 'reply preserved across raced detection',
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      backend.writeCalls.clear();
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7213',
            'direction': 'send',
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();
      expect(backend.writeCalls, isEmpty);

      backend.raceNextWriteWithTransferId = '7214';
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_completed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7213',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.activeZmodemTransferIdFor(sessionId), '7214');
      expect(backend.writeCalls, isEmpty);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '7214',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(backend.writeCalls, hasLength(1));
      expect(
        utf8.decode(backend.writeCalls.single),
        '\x1B]52;c;${base64.encode(utf8.encode('reply preserved across raced detection'))}\x07',
      );
    },
  );

  testWidgets(
    'async protocol reply uses native ordered path before Dart observes ZMODEM',
    (tester) async {
      final backend = _ProtocolReplyFakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => 'authoritative native ordering',
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      backend.writeCalls.clear();
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );

      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(backend.writeCalls, isEmpty);
      expect(backend.protocolReplyCalls, hasLength(1));
      expect(
        utf8.decode(backend.protocolReplyCalls.single),
        '\x1B]52;c;${base64.encode(utf8.encode('authoritative native ordering'))}\x07',
      );
    },
  );

  testWidgets('Repeated ZMODEM cancellation is one id-bound request', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: backend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final events = <TerminalSessionZmodemEvent>[];
    final subscription = runtime.zmodemEvents.listen(events.add);
    addTearDown(subscription.cancel);
    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'zmodem_detected',
        sessionId: sessionId,
        payload: const <String, Object?>{
          'source': 'zmodem',
          'transferId': '73',
          'direction': 'send',
        },
      ),
    );
    runtime.refreshSession(sessionId);
    await tester.pump();
    backend.jsonRequests.clear();

    expect(runtime.cancelZmodem(events.single), isTrue);
    expect(runtime.cancelZmodem(events.single), isTrue);

    expect(backend.jsonRequests, <Map<String, Object?>>[
      <String, Object?>{'kind': 'terminal.zmodem.cancel', 'transferId': '73'},
    ]);
    expect(runtime.tryCloseSession(sessionId), isTrue);
  });

  testWidgets(
    'Runtime Event gaps retain the ZMODEM input lock during native drain',
    (tester) async {
      final backend = _FakePtyBackend()
        ..cancelZmodemResponse = false
        ..cancelActiveZmodemOutcome = 'draining';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      await tester.pump();
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final runtimeEventGaps = <TerminalSessionRuntimeEventGapDiagnostic>[];
      final zmodemSubscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      final runtimeEventGapSubscription = runtime.runtimeEventGaps.listen(
        runtimeEventGaps.add,
      );
      addTearDown(zmodemSubscription.cancel);
      addTearDown(runtimeEventGapSubscription.cancel);
      backend.writeCalls.clear();
      backend.jsonRequests.clear();

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '9',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();
      expect(runtime.activeZmodemTransferIdFor(sessionId), '9');
      final pollsBeforeGap = backend.pollEventsCalls;

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 8,
          nextSequence: 11,
          droppedCount: 2,
          survivingEventCount: 1,
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(backend.pollEventsCalls - pollsBeforeGap, greaterThanOrEqualTo(2));
      expect(backend.jsonRequests.single, <String, Object?>{
        'kind': 'terminal.zmodem.cancel_active',
      });
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(zmodemEvents.last.isReconciliationRequired, isTrue);
      expect(zmodemEvents.last.kind, isNull);

      expect(runtimeEventGaps, hasLength(1));
      final gap = runtimeEventGaps.single;
      expect(gap.sessionId, sessionId);
      expect(gap.expectedSequence, 8);
      expect(gap.nextSequence, 11);
      expect(gap.droppedCount, 2);
      expect(gap.survivingEventCount, 1);
      expect(gap.affectedZmodemTransferId, '9');
      expect(gap.zmodemStateCleared, isFalse);
      expect(gap.zmodemCancellationAccepted, isFalse);
      expect(gap.stateRefreshRequested, isTrue);

      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x44]));
      expect(backend.writeCalls, isEmpty);

      backend.cancelActiveZmodemOutcome = 'cancelled';
      expect(runtime.cancelZmodem(zmodemEvents.last), isTrue);
      await tester.pump();
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(zmodemEvents.last.isReconciliationRequired, isTrue);
      expect(zmodemEvents.last.kind, isNull);
      expect(
        backend.jsonRequests
            .skip(backend.jsonRequests.length - 2)
            .map((request) => request['kind']),
        <Object?>['terminal.zmodem.cancel', 'terminal.zmodem.cancel_active'],
      );

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'eventKind': 'zmodem_cancelled',
            'transferId': '9',
            'direction': 'send',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(zmodemEvents.last.kind, TerminalZmodemEventKind.cancelled);
    },
  );

  testWidgets(
    'Gap cancellation suppresses stale authorization and retains drain lock',
    (tester) async {
      final backend = _FakePtyBackend()
        ..cancelActiveZmodemOutcome = 'cancelled';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final events = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(events.add);
      addTearDown(subscription.cancel);
      backend.writeCalls.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 1,
          nextSequence: 3,
          droppedCount: 1,
          survivingEventCount: 1,
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '751',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(events, hasLength(1));
      expect(events.single.isReconciliationRequired, isTrue);
      expect(events.single.kind, isNull);
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x55]));
      expect(backend.writeCalls, isEmpty);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '751',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(events.last.kind, TerminalZmodemEventKind.cancelled);
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
    },
  );

  testWidgets(
    'Known gap authority becomes unknown before a successor terminal',
    (tester) async {
      final backend = _FakePtyBackend()
        ..cancelActiveZmodemOutcome = 'cancelled';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final events = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(events.add);
      addTearDown(subscription.cancel);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      backend.writeCalls.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 4,
          nextSequence: 6,
          droppedCount: 1,
          survivingEventCount: 1,
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(runtime.activeZmodemTransferIdFor(sessionId), isNot('71'));
      expect(events.any((event) => event.isReconciliationRequired), isTrue);
      expect(
        events.where(
          (event) =>
              event.transferId == '72' &&
              event.kind == TerminalZmodemEventKind.detected,
        ),
        isEmpty,
      );
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x63]));
      expect(backend.writeCalls, isEmpty);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(events.last.transferId, '72');
      expect(events.last.kind, TerminalZmodemEventKind.cancelled);
    },
  );

  testWidgets(
    'Old terminal plus successor gap retains unknown authority during drain',
    (tester) async {
      final backend = _FakePtyBackend()
        ..cancelActiveZmodemOutcome = 'cancelled';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final events = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(events.add);
      addTearDown(subscription.cancel);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      backend.writeCalls.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 4,
          nextSequence: 7,
          droppedCount: 1,
          survivingEventCount: 2,
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_completed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(events.any((event) => event.isReconciliationRequired), isTrue);
      expect(
        events.any(
          (event) =>
              event.transferId == '71' &&
              event.kind == TerminalZmodemEventKind.completed,
        ),
        isTrue,
      );
      expect(
        events.where(
          (event) =>
              event.transferId == '72' &&
              event.kind == TerminalZmodemEventKind.detected,
        ),
        isEmpty,
      );
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x61]));
      expect(backend.writeCalls, isEmpty);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
    },
  );

  testWidgets(
    'Gap recovery from an old transfer preserves the current native drain',
    (tester) async {
      final backend = _FakePtyBackend()
        ..cancelActiveZmodemOutcome = 'cancelled';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final events = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(events.add);
      addTearDown(subscription.cancel);
      backend.writeCalls.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 1,
          nextSequence: 4,
          droppedCount: 1,
          survivingEventCount: 2,
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_failed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.complete.ianvs-part',
            'stagingPreserved': true,
            'recoveryToken': '1234567890abcdef1234567890abcdef',
          },
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(events, hasLength(2));
      expect(events.first.isReconciliationRequired, isTrue);
      expect(events.last.transferId, '71');
      expect(events.last.hasRecoverableReceiveStaging, isTrue);
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x55]));
      expect(backend.writeCalls, isEmpty);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '72',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(events.last.transferId, '72');
      expect(events.last.kind, TerminalZmodemEventKind.cancelled);
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
    },
  );

  testWidgets(
    'Idle reconciliation lets a recovery terminal clear unknown authority',
    (tester) async {
      final backend = _FakePtyBackend()..cancelActiveZmodemOutcome = 'draining';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final events = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(events.add);
      addTearDown(subscription.cancel);
      backend.writeCalls.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 1,
          nextSequence: 4,
          droppedCount: 3,
          survivingEventCount: 0,
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();
      expect(events.single.isReconciliationRequired, isTrue);
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);

      backend.cancelActiveZmodemOutcome = 'idle';
      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 4,
          nextSequence: 6,
          droppedCount: 1,
          survivingEventCount: 1,
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_failed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
            'reason': 'publish_failed',
            'recoverablePartialName': '.complete.ianvs-part',
            'stagingPreserved': true,
            'recoveryToken': '1234567890abcdef1234567890abcdef',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(events.last.transferId, '71');
      expect(events.last.hasRecoverableReceiveStaging, isTrue);
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x64]));
      expect(backend.writeCalls.last, Uint8List.fromList(const <int>[0x64]));
    },
  );

  testWidgets('Runtime Event gap clears a known transfer when native is idle', (
    tester,
  ) async {
    final backend = _FakePtyBackend()..cancelActiveZmodemOutcome = 'idle';
    final runtime = TerminalRuntimeController(
      backend: backend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    final zmodemEvents = <TerminalSessionZmodemEvent>[];
    final runtimeEventGaps = <TerminalSessionRuntimeEventGapDiagnostic>[];
    final zmodemSubscription = runtime.zmodemEvents.listen(zmodemEvents.add);
    final gapSubscription = runtime.runtimeEventGaps.listen(
      runtimeEventGaps.add,
    );
    addTearDown(zmodemSubscription.cancel);
    addTearDown(gapSubscription.cancel);

    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'zmodem_detected',
        sessionId: sessionId,
        payload: const <String, Object?>{
          'source': 'zmodem',
          'transferId': '901',
          'direction': 'send',
        },
      ),
    );
    runtime.refreshSession(sessionId);
    await tester.pump();
    backend.writeCalls.clear();
    backend.jsonRequests.clear();

    backend.enqueueEvent(
      sessionId,
      PtyRuntimeEventGapDiagnostic(
        sessionId: sessionId,
        expectedSequence: 4,
        nextSequence: 6,
        droppedCount: 2,
        survivingEventCount: 0,
      ),
    );
    runtime.refreshSession(sessionId);
    await tester.pump();
    await tester.pump();

    expect(runtime.isZmodemTransferActive(sessionId), isFalse);
    expect(zmodemEvents.last.kind, TerminalZmodemEventKind.failed);
    expect(zmodemEvents.last.reason, 'event_sequence_gap');
    expect(runtimeEventGaps.single.zmodemStateCleared, isTrue);
    expect(runtimeEventGaps.single.zmodemCancellationAccepted, isFalse);
    runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x49]));
    expect(backend.writeCalls.last, Uint8List.fromList(const <int>[0x49]));
  });

  testWidgets(
    'Runtime Event gap does not create an unknown lock when native is idle',
    (tester) async {
      final backend = _FakePtyBackend()..cancelActiveZmodemOutcome = 'idle';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      addTearDown(subscription.cancel);
      backend.writeCalls.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 1,
          nextSequence: 3,
          droppedCount: 2,
          survivingEventCount: 0,
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(zmodemEvents, isEmpty);
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x4a]));
      expect(backend.writeCalls.last, Uint8List.fromList(const <int>[0x4a]));
    },
  );

  testWidgets(
    'First-batch ZMODEM gap survivor establishes input lock when reconciliation fails',
    (tester) async {
      final backend = _FakePtyBackend()..cancelActiveZmodemResponse = false;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final runtimeEventGaps = <TerminalSessionRuntimeEventGapDiagnostic>[];
      final zmodemSubscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      final gapSubscription = runtime.runtimeEventGaps.listen(
        runtimeEventGaps.add,
      );
      addTearDown(zmodemSubscription.cancel);
      addTearDown(gapSubscription.cancel);
      backend.writeCalls.clear();
      backend.jsonRequests.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 1,
          nextSequence: 3,
          droppedCount: 1,
          survivingEventCount: 1,
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '74',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(backend.jsonRequests.single, <String, Object?>{
        'kind': 'terminal.zmodem.cancel_active',
      });
      expect(runtime.activeZmodemTransferIdFor(sessionId), '74');
      expect(zmodemEvents.single.kind, TerminalZmodemEventKind.detected);
      expect(runtimeEventGaps.single.zmodemCancellationAccepted, isFalse);
      expect(runtimeEventGaps.single.zmodemStateCleared, isFalse);

      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x45]));
      expect(backend.writeCalls, isEmpty);
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '74',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
    },
  );

  testWidgets(
    'First-batch ZMODEM gap without survivors exposes a cancelable unknown lock',
    (tester) async {
      final backend = _FakePtyBackend()
        ..cancelZmodemResponse = false
        ..cancelActiveZmodemResponse = false;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      addTearDown(subscription.cancel);
      backend.writeCalls.clear();
      backend.jsonRequests.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 1,
          nextSequence: 4,
          droppedCount: 3,
          survivingEventCount: 0,
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(zmodemEvents, hasLength(1));
      expect(zmodemEvents.single.kind, isNull);
      expect(zmodemEvents.single.isReconciliationRequired, isTrue);
      expect(zmodemEvents.single.direction, isNull);
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x46]));
      expect(backend.writeCalls, isEmpty);

      backend.cancelActiveZmodemResponse = true;
      backend.cancelActiveZmodemOutcome = 'cancelled';
      expect(runtime.cancelZmodem(zmodemEvents.single), isTrue);
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(zmodemEvents, hasLength(1));
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_failed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'eventKind': 'zmodem_failed',
            'transferId': '76',
            'direction': 'receive',
            'reason': 'cancelled_after_drain',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(zmodemEvents.last.kind, TerminalZmodemEventKind.failed);
      expect(zmodemEvents.last.reason, 'cancelled_after_drain');
    },
  );

  testWidgets(
    'Unknown ZMODEM gap lock remains active while native is draining',
    (tester) async {
      final backend = _FakePtyBackend()
        ..cancelZmodemResponse = false
        ..cancelActiveZmodemOutcome = 'draining';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      addTearDown(subscription.cancel);
      backend.writeCalls.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 1,
          nextSequence: 4,
          droppedCount: 3,
          survivingEventCount: 0,
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(zmodemEvents.single.isReconciliationRequired, isTrue);
      expect(runtime.cancelZmodem(zmodemEvents.single), isTrue);
      await tester.pump();
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(zmodemEvents, hasLength(1));
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x47]));
      expect(backend.writeCalls, isEmpty);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_failed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'eventKind': 'zmodem_failed',
            'transferId': '76',
            'direction': 'receive',
            'reason': 'cancelled_after_drain',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(zmodemEvents.last.kind, TerminalZmodemEventKind.failed);
      expect(zmodemEvents.last.reason, 'cancelled_after_drain');
    },
  );

  testWidgets(
    'Runtime Event gap does not lock a backend without ZMODEM capability',
    (tester) async {
      final backend = _FakePtyBackend()..runtimeCapabilities = null;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      addTearDown(subscription.cancel);
      backend.writeCalls.clear();
      backend.jsonRequests.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 1,
          nextSequence: 3,
          droppedCount: 2,
          survivingEventCount: 0,
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(zmodemEvents, isEmpty);
      expect(backend.jsonRequests, isEmpty);
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x48]));
      expect(backend.writeCalls.last, Uint8List.fromList(const <int>[0x48]));
    },
  );

  testWidgets(
    'Terminal survivor clears unknown cancellation de-duplication for a later gap',
    (tester) async {
      final backend = _FakePtyBackend()
        ..cancelZmodemResponse = false
        ..cancelActiveZmodemOutcome = 'draining';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      addTearDown(subscription.cancel);
      backend.writeCalls.clear();

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 1,
          nextSequence: 3,
          droppedCount: 2,
          survivingEventCount: 0,
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();
      expect(zmodemEvents.single.isReconciliationRequired, isTrue);
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(runtime.cancelZmodem(zmodemEvents.single), isTrue);
      expect(
        backend.jsonRequests.map((request) => request['kind']),
        containsAllInOrder(<Object?>[
          'terminal.zmodem.cancel',
          'terminal.zmodem.cancel_active',
        ]),
      );

      backend.cancelActiveZmodemOutcome = 'idle';

      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 3,
          nextSequence: 5,
          droppedCount: 1,
          survivingEventCount: 1,
        ),
      );
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_completed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'eventKind': 'zmodem_completed',
            'transferId': '77',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(zmodemEvents.last.kind, TerminalZmodemEventKind.completed);
      expect(
        zmodemEvents.where(
          (event) =>
              event.kind == TerminalZmodemEventKind.failed &&
              event.reason == 'event_sequence_gap',
        ),
        isEmpty,
      );
      runtime.sendInput(sessionId, Uint8List.fromList(const <int>[0x4b]));
      expect(backend.writeCalls.last, Uint8List.fromList(const <int>[0x4b]));

      backend.cancelActiveZmodemOutcome = 'draining';
      backend.jsonRequests.clear();
      backend.enqueueEvent(
        sessionId,
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: 5,
          nextSequence: 8,
          droppedCount: 3,
          survivingEventCount: 0,
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      final nextUnknown = zmodemEvents.last;
      expect(nextUnknown.isReconciliationRequired, isTrue);
      expect(runtime.cancelZmodem(nextUnknown), isTrue);
      expect(
        backend.jsonRequests.map((request) => request['kind']),
        containsAllInOrder(<Object?>[
          'terminal.zmodem.cancel_active',
          'terminal.zmodem.cancel',
          'terminal.zmodem.cancel_active',
        ]),
      );
      expect(runtime.tryCloseSession(sessionId), isTrue);
    },
  );

  testWidgets(
    'Accepted ZMODEM transfer polls autonomously when session polling is disabled',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      addTearDown(subscription.cancel);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '78',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(
        runtime.acceptZmodemSend(
          zmodemEvents.single,
          files: const <String>['/tmp/report.bin'],
        ),
        isTrue,
      );
      final pollsBeforeCompletion = backend.pollEventsCalls;
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_completed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'eventKind': 'zmodem_completed',
            'transferId': '78',
            'direction': 'send',
            'completedFiles': 1,
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(backend.pollEventsCalls, greaterThan(pollsBeforeCompletion));
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(zmodemEvents.last.kind, TerminalZmodemEventKind.completed);
    },
  );

  testWidgets(
    'Detected ZMODEM transfer polls before authorization is answered',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final events = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(events.add);
      addTearDown(subscription.cancel);
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '781',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();
      final pollsAfterDetection = backend.pollEventsCalls;
      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_cancelled',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '781',
            'direction': 'send',
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(backend.pollEventsCalls, greaterThan(pollsAfterDetection));
      expect(events.last.kind, TerminalZmodemEventKind.cancelled);
      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
    },
  );

  testWidgets(
    'Cancel during native drain waits for the authoritative completion event',
    (tester) async {
      final backend = _FakePtyBackend()
        ..cancelZmodemResponse = false
        ..cancelActiveZmodemOutcome = 'draining';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final subscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      addTearDown(subscription.cancel);

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '75',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.cancelZmodem(zmodemEvents.single), isTrue);
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      expect(zmodemEvents, hasLength(1));

      backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_completed',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'eventKind': 'zmodem_completed',
            'transferId': '75',
            'direction': 'send',
          },
        ),
      );
      runtime.refreshSession(sessionId);
      await tester.pump();
      await tester.pump();

      expect(runtime.isZmodemTransferActive(sessionId), isFalse);
      expect(zmodemEvents.last.kind, TerminalZmodemEventKind.completed);
      expect(
        zmodemEvents.where(
          (event) => event.kind == TerminalZmodemEventKind.cancelled,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'ordered runtime signals preserve legacy payload identity and total order',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final zmodemSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final exitingSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/zsh'),
        ),
      );
      await tester.pump();
      backend
        ..clearFrame(zmodemSessionId)
        ..clearFrame(exitingSessionId);

      final signals = <TerminalRuntimeSignal>[];
      final sessionEvents = <TerminalSessionEvent>[];
      final zmodemEvents = <TerminalSessionZmodemEvent>[];
      final deferredFailures =
          <TerminalSessionZmodemDeferredWriteFailedDiagnostic>[];
      final signalSubscription = runtime.runtimeSignals.listen(signals.add);
      final sessionSubscription = runtime.events.listen(sessionEvents.add);
      final zmodemSubscription = runtime.zmodemEvents.listen(zmodemEvents.add);
      final deferredSubscription = runtime.zmodemDeferredWriteFailures.listen(
        deferredFailures.add,
      );
      addTearDown(signalSubscription.cancel);
      addTearDown(sessionSubscription.cancel);
      addTearDown(zmodemSubscription.cancel);
      addTearDown(deferredSubscription.cancel);

      backend.enqueueEvent(
        zmodemSessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: zmodemSessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '900',
            'direction': 'receive',
          },
        ),
      );
      runtime.refreshSession(zmodemSessionId);
      await tester.pump();

      backend.enqueueEvent(
        exitingSessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: exitingSessionId,
          payload: const <String, Object?>{'code': 17},
        ),
      );
      runtime.refreshSession(exitingSessionId);
      await tester.pump();

      backend.enqueueEvent(
        zmodemSessionId,
        PtyEvent(
          kind: 'zmodem_deferred_write_failed',
          sessionId: zmodemSessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'reason': 'io_error',
            'queuedChunks': 2,
            'queuedBytes': 8,
            'completedChunks': 1,
            'completedBytes': 4,
          },
        ),
      );
      runtime.refreshSession(zmodemSessionId);
      await tester.pump();

      expect(signals, hasLength(3));
      expect(signals.map((signal) => signal.runtimeType), <Type>[
        TerminalRuntimeZmodemEventSignal,
        TerminalRuntimeSessionEventSignal,
        TerminalRuntimeZmodemDeferredFailureSignal,
      ]);
      final firstSequence = signals.first.sequence;
      expect(signals.map((signal) => signal.sequence), <int>[
        firstSequence,
        firstSequence + 1,
        firstSequence + 2,
      ]);
      expect(zmodemEvents, hasLength(1));
      expect(sessionEvents.whereType<TerminalSessionExitEvent>(), hasLength(1));
      expect(deferredFailures, hasLength(1));
      expect(
        identical(
          (signals[0] as TerminalRuntimeZmodemEventSignal).payload,
          zmodemEvents.single,
        ),
        isTrue,
      );
      expect(
        identical(
          (signals[1] as TerminalRuntimeSessionEventSignal).payload,
          sessionEvents.whereType<TerminalSessionExitEvent>().single,
        ),
        isTrue,
      );
      expect(
        identical(
          (signals[2] as TerminalRuntimeZmodemDeferredFailureSignal).payload,
          deferredFailures.single,
        ),
        isTrue,
      );
      expect(signals[0].sessionId, zmodemSessionId);
      expect(signals[1].sessionId, exitingSessionId);
      expect(signals[2].sessionId, zmodemSessionId);
      expect(signals[0].sessionEpoch, signals[2].sessionEpoch);
      expect(signals[1].sessionEpoch, isNot(signals[0].sessionEpoch));
      expect(runtime.tryDispose(), isTrue);
      await tester.pump();
    },
  );

  testWidgets(
    'runtime signals reject stale epochs when a backend session id is reused',
    (tester) async {
      final clipboardText = Completer<String>();
      final backend = _FakePtyBackend()..forcedSessionId = 'reused-signal';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () => clipboardText.future,
        allowClipboardPasteRequest: () async => true,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final signals = <TerminalRuntimeSignal>[];
      final subscription = runtime.runtimeSignals.listen(signals.add);
      addTearDown(subscription.cancel);

      final oldSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();
      backend.clearFrame(oldSessionId);
      signals.clear();
      backend.enqueueEvent(
        oldSessionId,
        PtyEvent(kind: 'bell', sessionId: oldSessionId),
      );
      runtime.refreshSession(oldSessionId);
      await tester.pump();
      final oldBell = signals
          .whereType<TerminalRuntimeSessionEventSignal>()
          .singleWhere((signal) => signal.payload is TerminalSessionBellEvent);

      backend.enqueueEvent(
        oldSessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: oldSessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );
      runtime.refreshSession(oldSessionId);
      await tester.pump();

      runtime.closeSession(oldSessionId);
      final newSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/zsh'),
        ),
      );
      expect(newSessionId, oldSessionId);
      await tester.pump();
      backend.clearFrame(newSessionId);
      signals.clear();
      backend.enqueueEvent(
        newSessionId,
        PtyEvent(kind: 'bell', sessionId: newSessionId),
      );
      runtime.refreshSession(newSessionId);
      await tester.pump();
      final newBell = signals
          .whereType<TerminalRuntimeSessionEventSignal>()
          .singleWhere((signal) => signal.payload is TerminalSessionBellEvent);
      final signalCountBeforeStaleContinuation = signals.length;

      clipboardText.complete('must not reach the reused session');
      await tester.pump();

      expect(newBell.sessionEpoch, greaterThan(oldBell.sessionEpoch));
      expect(signals, hasLength(signalCountBeforeStaleContinuation));
      expect(
        signals.whereType<TerminalRuntimeSessionEventSignal>().where(
          (signal) => signal.payload is TerminalSessionClipboardEvent,
        ),
        isEmpty,
      );
      expect(backend.writeCalls, isEmpty);
    },
  );

  testWidgets('runtime signal stream closes without post-dispose leakage', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: backend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();
    final signals = <TerminalRuntimeSignal>[];
    final completed = Completer<void>();
    final subscription = runtime.runtimeSignals.listen(
      signals.add,
      onDone: completed.complete,
    );
    addTearDown(subscription.cancel);

    expect(runtime.tryDispose(), isTrue);
    await tester.pump();
    await expectLater(completed.future, completes);
    final signalCountAfterDispose = signals.length;

    backend.enqueueEvent(
      sessionId,
      PtyEvent(kind: 'bell', sessionId: sessionId),
    );
    runtime.refreshSession(sessionId);
    await tester.pump();

    expect(signals, hasLength(signalCountAfterDispose));
  });
}

PtyEvent _clipboardPasteHostRequestEvent(
  String sessionId, {
  required int sequence,
}) {
  final hostRequest = PtyHostRequestV1.fromJson(
    <String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-host-request-v1',
      'request_id': 'host:$sessionId:$sequence',
      'session_id': sessionId,
      'operation': 'clipboard.read_text',
      'sequence': sequence,
      'timestamp_micros': 1200,
      'payload': <String, Object?>{'selection': 'c'},
    },
    expectedSessionId: sessionId,
    expectedSequence: sequence,
    expectedTimestampMicros: 1200,
  );
  return PtyEvent(
    kind: 'clipboard_paste_request',
    sessionId: sessionId,
    payload: hostRequest.payload,
    sequence: sequence,
    timestampMicros: 1200,
    wireSchemaVersion: 1,
    hostRequest: hostRequest,
  );
}

class _FakePtyBackend
    implements
        PtySessionBackend,
        PtySessionJsonRequestBackend,
        PtySessionGraphicAssetBackend,
        PtySessionFileDownloadBackend,
        PtySessionDiagnosticsBackend,
        PtySessionDiagnosticEventV1Backend,
        PtyHostResponseV1Backend,
        PtyRuntimeCapabilityBackend {
  @override
  PtyRuntimeCapabilities? runtimeCapabilities = PtyRuntimeCapabilities.fromJson(
    const <String, Object?>{
      'schema_version': ptyRuntimeCapabilitiesSchemaVersion,
      'runtime_contract': ptyRuntimeContractV1,
      'frame_schema_versions': <String>[],
      'recording_schema_versions': <int>[],
      'features': <String>['zmodem.receive.v1', 'zmodem.send.v1'],
    },
  );

  String? lastCreateSessionJson;
  int takeFrameDiffCalls = 0;
  int pollEventsCalls = 0;
  final List<String> closeCalls = <String>[];
  final List<Uint8List> writeCalls = <Uint8List>[];
  final List<List<Object?>> resizeCalls = <List<Object?>>[];
  final List<(String, int)> scrollCalls = <(String, int)>[];
  final List<(String, int)> scrollToCalls = <(String, int)>[];
  final List<(String, int, int)> graphicAssetRequests = <(String, int, int)>[];
  final List<Map<String, Object?>> jsonRequests = <Map<String, Object?>>[];
  final Set<String> failingOperations = <String>{};
  final Set<String> retryableCloseSessionIds = <String>{};
  final Map<(int, int), PtyGraphicAsset> graphicAssets =
      <(int, int), PtyGraphicAsset>{};
  final Map<(String, int), Uint8List> fileDownloads =
      <(String, int), Uint8List>{};
  final List<(String, int, int)> fileDownloadTakeRequests =
      <(String, int, int)>[];
  final List<(String, int)> fileDownloadDiscardRequests = <(String, int)>[];
  List<Map<String, Object?>> searchResponse = const <Map<String, Object?>>[];
  String? searchRawResponse;
  String? searchErrorText;
  String selectionResponse = '';
  String? selectionRawResponse;
  String? clearScrollbackRawResponse;
  bool setBlockFoldedResponse = true;
  bool setBlockRenderedResponse = true;
  Map<String, Object?> inlineButtonActivationResponse = <String, Object?>{
    'activated': true,
    'kind': 'custom',
  };
  bool dismissOsc99NotificationResponse = true;
  String? scrollbackRawResponse;
  Map<String, Object?>? diagnosticsResponse;
  String? diagnosticsRawResponse;
  String? frameDiagnosticsRawResponse;
  String? sessionDiagnosticsRawResponse;
  bool diagnosticEventV1Supported = false;
  Map<String, Object?>? frameDiagnosticV1Payload;
  Map<String, Object?>? sessionDiagnosticV1Payload;
  final List<(String, String)> diagnosticEventV1Requests = <(String, String)>[];
  final List<(String, String)> legacyDiagnosticRequests = <(String, String)>[];
  String? forcedSessionId;
  bool returnNullJsonRequests = false;
  bool cancelZmodemResponse = true;
  bool cancelActiveZmodemResponse = true;
  String cancelActiveZmodemOutcome = 'cancelled';
  bool? sessionCloseReadyResponse;
  String? zmodemRecoveryPath;
  bool hostResponseV1Supported = false;
  final List<(String, String)> hostResponses = <(String, String)>[];

  final Map<String, Map<String, Object?>> _frames =
      <String, Map<String, Object?>>{};
  final Map<String, List<Map<String, Object?>>> _queuedFrames =
      <String, List<Map<String, Object?>>>{};
  final Map<String, List<String>> _queuedRawFrames = <String, List<String>>{};
  final Map<String, List<PtyEvent>> _queuedEvents = <String, List<PtyEvent>>{};
  int _nextSessionId = 0;

  Map<String, Object?>? get lastCreateSessionPayload {
    final raw = lastCreateSessionJson;
    if (raw == null) {
      return null;
    }
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  void setFrame(String sessionId, Map<String, Object?> frame) {
    _frames[sessionId] = frame;
  }

  void clearFrame(String sessionId) {
    _frames.remove(sessionId);
  }

  void enqueueFrame(String sessionId, Map<String, Object?> frame) {
    _queuedFrames
        .putIfAbsent(sessionId, () => <Map<String, Object?>>[])
        .add(frame);
  }

  void enqueueRawFrame(String sessionId, String rawFrame) {
    _queuedRawFrames.putIfAbsent(sessionId, () => <String>[]).add(rawFrame);
  }

  void enqueueEvent(String sessionId, PtyEvent event) {
    _queuedEvents.putIfAbsent(sessionId, () => <PtyEvent>[]).add(event);
  }

  @override
  int ping() => 1;

  @override
  String createSession(String sessionConfigJson) {
    lastCreateSessionJson = sessionConfigJson;
    final sessionId = forcedSessionId ?? (++_nextSessionId).toString();
    _frames[sessionId] = <String, Object?>{
      'frame_kind': 'snapshot',
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'demo',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    };
    return sessionId;
  }

  @override
  void closeSession(String sessionId) {
    if (retryableCloseSessionIds.contains(sessionId)) {
      throw PtyNativeCallException(
        operation: 'closeSession',
        sessionId: sessionId,
        statusCode: -2,
      );
    }
    _throwIfFailing('closeSession');
    closeCalls.add(sessionId);
    _frames.remove(sessionId);
    _queuedFrames.remove(sessionId);
    _queuedRawFrames.remove(sessionId);
    _queuedEvents.remove(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {
    _throwIfFailing('resizeSession');
    resizeCalls.add(<Object?>[
      sessionId,
      cols,
      rows,
      pixelWidth,
      pixelHeight,
      cellWidth,
      cellHeight,
    ]);
    final frame = _frames[sessionId];
    if (frame != null) {
      frame['viewport_cols'] = cols;
      frame['viewport_rows'] = rows;
    }
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    _throwIfFailing('writeInput');
    writeCalls.add(Uint8List.fromList(bytes));
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    _throwIfFailing('scrollViewport');
    scrollCalls.add((sessionId, deltaLines));
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    _throwIfFailing('scrollViewportTo');
    scrollToCalls.add((sessionId, offset));
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = (jsonDecode(requestJson) as Map).cast<String, Object?>();
    jsonRequests.add(request);
    _throwIfFailing('requestSessionJson');
    if (returnNullJsonRequests) {
      return null;
    }
    return switch (request['kind']) {
      'terminal.search_text' =>
        searchRawResponse ??
            jsonEncode(<String, Object?>{
              'matches': searchResponse,
              'error_text': searchErrorText,
            }),
      'terminal.selection_text' =>
        selectionRawResponse ??
            jsonEncode(<String, Object?>{'text': selectionResponse}),
      'terminal.clear_scrollback' =>
        clearScrollbackRawResponse ??
            jsonEncode(<String, Object?>{'cleared': true}),
      'terminal.clear_buffer' => jsonEncode(<String, Object?>{'cleared': true}),
      'terminal.dismiss_osc99_notification' => jsonEncode(<String, Object?>{
        'dismissed': dismissOsc99NotificationResponse,
      }),
      'terminal.set_block_folded' => jsonEncode(<String, Object?>{
        'updated': setBlockFoldedResponse,
      }),
      'terminal.set_block_rendered' => jsonEncode(<String, Object?>{
        'updated': setBlockRenderedResponse,
      }),
      'terminal.activate_iterm_button' => jsonEncode(
        inlineButtonActivationResponse,
      ),
      'terminal.export_scrollback' =>
        scrollbackRawResponse ??
            jsonEncode(<String, Object?>{'content': 'scrollback text'}),
      'terminal.export_diagnostics' =>
        diagnosticsRawResponse ?? jsonEncode(diagnosticsResponse),
      'terminal.zmodem.accept_receive' || 'terminal.zmodem.accept_send' =>
        jsonEncode(<String, Object?>{'accepted': true}),
      'terminal.zmodem.cancel' => jsonEncode(<String, Object?>{
        'cancelled': cancelZmodemResponse,
      }),
      'terminal.zmodem.cancel_active' => jsonEncode(<String, Object?>{
        'reconciled': cancelActiveZmodemResponse,
        'outcome': cancelActiveZmodemOutcome,
      }),
      'terminal.session.close_readiness' => jsonEncode(<String, Object?>{
        'ready':
            sessionCloseReadyResponse ??
            !retryableCloseSessionIds.contains(sessionId),
      }),
      'terminal.zmodem.resolve_recovery' =>
        zmodemRecoveryPath == null
            ? jsonEncode(const <String, Object?>{'available': false})
            : jsonEncode(<String, Object?>{
                'available': true,
                'path': zmodemRecoveryPath,
              }),
      'terminal.zmodem.consume_recovery' => jsonEncode(const <String, Object?>{
        'consumed': true,
      }),
      'terminal.zmodem.dismiss_recovery' => jsonEncode(const <String, Object?>{
        'dismissed': true,
      }),
      _ => null,
    };
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    _throwIfFailing('takeFrameDiffJson');
    takeFrameDiffCalls += 1;
    final queuedRawFrames = _queuedRawFrames[sessionId];
    if (queuedRawFrames != null && queuedRawFrames.isNotEmpty) {
      return queuedRawFrames.removeAt(0);
    }
    final queuedFrames = _queuedFrames[sessionId];
    if (queuedFrames != null && queuedFrames.isNotEmpty) {
      return jsonEncode(queuedFrames.removeAt(0));
    }
    final frame = _frames[sessionId];
    return frame == null ? null : jsonEncode(frame);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    _throwIfFailing('pollEvents');
    pollEventsCalls += 1;
    return _queuedEvents.remove(sessionId) ?? const <PtyEvent>[];
  }

  @override
  PtyGraphicAsset? loadGraphicAsset(
    String sessionId, {
    required int assetId,
    required int assetVersion,
  }) {
    _throwIfFailing('loadGraphicAsset');
    graphicAssetRequests.add((sessionId, assetId, assetVersion));
    return graphicAssets[(assetId, assetVersion)];
  }

  @override
  Uint8List? takeFileDownload(
    String sessionId, {
    required int downloadId,
    required int expectedSize,
  }) {
    _throwIfFailing('takeFileDownload');
    fileDownloadTakeRequests.add((sessionId, downloadId, expectedSize));
    final bytes = fileDownloads.remove((sessionId, downloadId));
    return bytes?.length == expectedSize ? Uint8List.fromList(bytes!) : null;
  }

  @override
  bool discardFileDownload(String sessionId, {required int downloadId}) {
    _throwIfFailing('discardFileDownload');
    fileDownloadDiscardRequests.add((sessionId, downloadId));
    return fileDownloads.remove((sessionId, downloadId)) != null;
  }

  @override
  String? takeDiagnosticsJson(String sessionId, String kind) {
    legacyDiagnosticRequests.add((sessionId, kind));
    return switch (kind) {
      'frame' => frameDiagnosticsRawResponse,
      'session' => sessionDiagnosticsRawResponse,
      _ => null,
    };
  }

  @override
  bool get supportsDiagnosticEventV1 => diagnosticEventV1Supported;

  @override
  PtyDiagnosticEventV1? takeDiagnosticEventV1(String sessionId, String name) {
    if (!diagnosticEventV1Supported) {
      throw UnsupportedError('Diagnostic Event v1 is not supported');
    }
    diagnosticEventV1Requests.add((sessionId, name));
    final payload = switch (name) {
      'frame_stats' => frameDiagnosticV1Payload,
      'session_stats' => sessionDiagnosticV1Payload,
      _ => null,
    };
    if (payload == null) {
      return null;
    }
    return PtyDiagnosticEventV1.fromJson(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-runtime-envelope-v1',
      'message_class': 'diagnostic',
      'message_name': name,
      'session_id': sessionId,
      'sequence': diagnosticEventV1Requests.length - 1,
      'timestamp_micros': 1,
      'payload': payload,
    });
  }

  @override
  bool get supportsHostResponseV1 => hostResponseV1Supported;

  @override
  bool respondToHostRequestV1(String sessionId, String responseV1Json) {
    _throwIfFailing('respondToHostRequestV1');
    if (!hostResponseV1Supported) {
      throw UnsupportedError('Host Response v1 is not supported');
    }
    hostResponses.add((sessionId, responseV1Json));
    return true;
  }

  void _throwIfFailing(String operation) {
    if (failingOperations.contains(operation)) {
      throw StateError('$operation failed');
    }
  }
}

class _ProtocolReplyFakePtyBackend extends _FakePtyBackend
    implements PtyProtocolReplyBackend {
  final List<Uint8List> protocolReplyCalls = <Uint8List>[];

  @override
  bool get supportsProtocolReplies => true;

  @override
  void writeProtocolReply(String sessionId, List<int> bytes) {
    protocolReplyCalls.add(Uint8List.fromList(bytes));
  }
}

class _ProtobufFramePtyBackend extends _FakePtyBackend
    implements PtySessionProtobufFrameBackend {
  _ProtobufFramePtyBackend({frame_pb.TerminalFrameDiff? initialFrame})
    : _initialFrame = initialFrame;

  final frame_pb.TerminalFrameDiff? _initialFrame;
  int takeFrameDiffProtobufCalls = 0;
  final Map<String, List<Uint8List?>> _queuedProtobufFrames =
      <String, List<Uint8List?>>{};

  @override
  bool get supportsProtobufFrameDiffs => true;

  @override
  String createSession(String sessionConfigJson) {
    final sessionId = super.createSession(sessionConfigJson);
    final initialFrame = _initialFrame;
    if (initialFrame != null) {
      enqueueProtobufFrame(sessionId, initialFrame);
    }
    return sessionId;
  }

  void enqueueProtobufFrame(
    String sessionId,
    frame_pb.TerminalFrameDiff frame,
  ) {
    _queuedProtobufFrames
        .putIfAbsent(sessionId, () => <Uint8List?>[])
        .add(Uint8List.fromList(frame.writeToBuffer()));
  }

  void enqueueRawProtobufFrame(String sessionId, List<int>? bytes) {
    _queuedProtobufFrames
        .putIfAbsent(sessionId, () => <Uint8List?>[])
        .add(bytes == null ? null : Uint8List.fromList(bytes));
  }

  @override
  Uint8List? takeFrameDiffProtobuf(String sessionId) {
    takeFrameDiffProtobufCalls += 1;
    final queuedFrames = _queuedProtobufFrames[sessionId];
    if (queuedFrames != null && queuedFrames.isNotEmpty) {
      return queuedFrames.removeAt(0);
    }
    return null;
  }
}

class _UnsupportedProtobufFramePtyBackend extends _ProtobufFramePtyBackend {
  @override
  bool get supportsProtobufFrameDiffs => false;
}

class _ThrowingJsonFramePtyBackend extends _FakePtyBackend {
  int takeFrameDiffJsonAttempts = 0;
  final List<String> takeFrameDiffJsonSessions = <String>[];

  @override
  String? takeFrameDiffJson(String sessionId) {
    takeFrameDiffJsonAttempts += 1;
    takeFrameDiffJsonSessions.add(sessionId);
    throw StateError('takeFrameDiffJson failed');
  }
}

class _ThrowingProtobufFramePtyBackend extends _ProtobufFramePtyBackend {
  int takeFrameDiffProtobufAttempts = 0;
  final List<String> takeFrameDiffProtobufSessions = <String>[];

  @override
  Uint8List? takeFrameDiffProtobuf(String sessionId) {
    takeFrameDiffProtobufAttempts += 1;
    takeFrameDiffProtobufSessions.add(sessionId);
    takeFrameDiffProtobufCalls += 1;
    throw StateError('takeFrameDiffProtobuf failed');
  }
}

class _RefreshHintPtyBackend extends _FakePtyBackend
    implements PtySessionRefreshHintBackend {
  int hintFlags = 0;
  int refreshHintCalls = 0;
  bool throwOnRefreshHint = false;
  final Map<String, int> hintFlagsBySession = <String, int>{};
  final Map<String, int> refreshHintCallsBySession = <String, int>{};
  final Set<String> throwingSessions = <String>{};

  @override
  bool get supportsRefreshHints => true;

  @override
  int refreshHintFlags(String sessionId) {
    refreshHintCalls += 1;
    refreshHintCallsBySession[sessionId] =
        (refreshHintCallsBySession[sessionId] ?? 0) + 1;
    if (throwOnRefreshHint || throwingSessions.contains(sessionId)) {
      throw StateError('refreshHintFlags failed');
    }
    return hintFlagsBySession[sessionId] ?? hintFlags;
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    final frame = super.takeFrameDiffJson(sessionId);
    hintFlags &= ~1;
    if (hintFlagsBySession.containsKey(sessionId)) {
      hintFlagsBySession[sessionId] = hintFlagsBySession[sessionId]! & ~1;
    }
    return frame;
  }
}

class _RefreshHintProtobufPtyBackend extends _ProtobufFramePtyBackend
    implements PtySessionRefreshHintBackend {
  _RefreshHintProtobufPtyBackend({super.initialFrame});

  int hintFlags = 0;
  int refreshHintCalls = 0;

  @override
  bool get supportsRefreshHints => true;

  @override
  int refreshHintFlags(String sessionId) {
    refreshHintCalls += 1;
    return hintFlags;
  }

  @override
  Uint8List? takeFrameDiffProtobuf(String sessionId) {
    final frame = super.takeFrameDiffProtobuf(sessionId);
    hintFlags &= ~1;
    return frame;
  }
}

class _FrameOnlyPtyBackend implements PtySessionBackend {
  final Map<String, Map<String, Object?>> _frames =
      <String, Map<String, Object?>>{};
  int _nextSessionId = 0;

  @override
  int ping() => 1;

  @override
  String createSession(String sessionConfigJson) {
    final sessionId = (++_nextSessionId).toString();
    _frames[sessionId] = _singleRowSnapshot('demo');
    return sessionId;
  }

  @override
  void closeSession(String sessionId) {
    _frames.remove(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {}

  @override
  void writeInput(String sessionId, List<int> bytes) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? takeFrameDiffJson(String sessionId) {
    final frame = _frames[sessionId];
    return frame == null ? null : jsonEncode(frame);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];
}

class _StartedEventPtyBackend extends _FakePtyBackend {
  @override
  String createSession(String sessionConfigJson) {
    final sessionId = super.createSession(sessionConfigJson);
    enqueueEvent(sessionId, PtyEvent(kind: 'started', sessionId: sessionId));
    return sessionId;
  }
}

class _ProtocolReplyFlushRacePtyBackend extends _FakePtyBackend {
  String? raceNextWriteWithTransferId;

  @override
  void writeInput(String sessionId, List<int> bytes) {
    final transferId = raceNextWriteWithTransferId;
    if (transferId != null) {
      raceNextWriteWithTransferId = null;
      enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: <String, Object?>{
            'source': 'zmodem',
            'transferId': transferId,
            'direction': 'receive',
          },
        ),
      );
      throw StateError('injected ZMODEM detection/write race');
    }
    super.writeInput(sessionId, bytes);
  }
}

Map<String, Object?> _singleRowSnapshot(
  String text, {
  int viewportRows = 24,
  int viewportCols = 80,
}) {
  return <String, Object?>{
    'frame_kind': 'snapshot',
    'rows': <Object?>[
      <String, Object?>{
        'index': 0,
        'text': text,
        'style_runs': const <Object?>[],
      },
    ],
    'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
    'viewport_rows': viewportRows,
    'viewport_cols': viewportCols,
    'dirty_ranges': <Object?>[
      <String, Object?>{'start': 0, 'end': 1},
    ],
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
  };
}

frame_pb.TerminalFrameDiff _singleRowProtobuf(
  String text, {
  int viewportRows = 24,
  int viewportCols = 80,
}) {
  return frame_pb.TerminalFrameDiff(
    frameKind: frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_SNAPSHOT,
    rows: [frame_pb.TerminalRow(index: 0, text: text)],
    cursor: frame_pb.TerminalCursor(row: 0, col: 0, visible: true),
    viewportRows: viewportRows,
    viewportCols: viewportCols,
    dirtyRanges: [frame_pb.TerminalDirtyRange(start: 0, end: viewportRows)],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
  );
}
