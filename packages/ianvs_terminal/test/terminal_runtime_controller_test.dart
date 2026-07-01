import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

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
    });
    final invalid = TerminalFrameModes.fromJson(const <String, Object?>{
      'kitty_keyboard_flags': -1,
    });

    expect(modes.alternateScreen, isTrue);
    expect(modes.kittyKeyboardFlags, 5);
    expect(modes.synchronizedOutput, isTrue);
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
          modes: TerminalFrameModes(synchronizedOutput: false),
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
          'style_runs': [],
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
      'viewport_rows': 2,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 2},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows.map((row) => row.modifiedAt), everyElement(isNull));
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
    });

    final run = frame.rows.single.styleRuns.first;
    expect(run.foreground, const Color(0xFF112233));
    expect(run.background, const Color(0x80445566));
    expect(frame.cursorColor, const Color(0xFF123456));
    expect(frame.rows.single.styleRuns.last.foreground, isNull);
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

    expect(negative.viewportRows, 0);
    expect(negative.viewportCols, 0);
    expect(negative.scrollbackOffset, 0);
    expect(negative.scrollbackMaxOffset, 0);
    expect(negative.viewportStartRow, 0);
    expect(negative.viewportRowShift, -1);
    expect(overflow.scrollbackOffset, 10);
    expect(overflow.scrollbackMaxOffset, 10);
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
        {'index': 0, 'text': 'image', 'style_runs': []},
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
        {'index': 0, 'text': 'image', 'style_runs': []},
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

  test('terminal frames parse graphics placement payloads', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'image', 'style_runs': []},
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
        {'index': 0, 'text': 'graphics', 'style_runs': []},
        {'index': 1, 'text': 'below', 'style_runs': []},
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
        {'index': 0, 'text': 'image', 'style_runs': []},
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
        {'index': 0, 'text': 'image', 'style_runs': []},
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
        {'index': 0, 'text': 'image', 'style_runs': []},
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
            key.version == 1 ? 255 : 0,
            key.version == 2 ? 255 : 0,
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
        {'index': 0, 'text': 'image', 'style_runs': []},
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
          {'index': 0, 'text': 'image', 'style_runs': []},
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
          runtimeBackend.lastCreateSessionPayload!['appearance']
              as Map<String, Object?>;
      final colors = appearance['colors'] as Map<String, Object?>;
      final special = colors['special'] as Map<String, Object?>;
      expect(special['background'], '#000000');
    },
  );

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
    'terminal runtime controller coalesces polling input bursts to 30fps',
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
        runtimeBackend.setFrame(sessionId, _singleRowSnapshot('coalesced'));

        runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));
        runtime.sendInput(sessionId, Uint8List.fromList(const [0x42]));
        runtime.scrollViewport(sessionId, 1);

        expect(runtimeBackend.takeFrameDiffCalls, 1);
        expect(viewport.frame.rows.first.text, 'demo');

        await tester.pump(const Duration(milliseconds: 32));
        expect(runtimeBackend.takeFrameDiffCalls, 1);

        await tester.pump(const Duration(milliseconds: 2));
        expect(runtimeBackend.takeFrameDiffCalls, 2);
        expect(viewport.frame.rows.first.text, 'coalesced');
      } finally {
        runtime.dispose();
      }
    },
  );

  testWidgets('terminal runtime controller backs off repeated idle polling', (
    tester,
  ) async {
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
      runtimeBackend.clearFrame(sessionId);

      await tester.pump(const Duration(milliseconds: 34));
      await tester.pump(const Duration(milliseconds: 34));

      expect(runtimeBackend.takeFrameDiffCalls, 3);
      expect(runtimeBackend.pollEventsCalls, 3);

      await tester.pump(const Duration(milliseconds: 100));

      expect(runtimeBackend.takeFrameDiffCalls, 3);
      expect(runtimeBackend.pollEventsCalls, 3);

      runtimeBackend.setFrame(sessionId, _singleRowSnapshot('wake'));
      runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));

      expect(runtimeBackend.takeFrameDiffCalls, 4);
      expect(runtimeBackend.pollEventsCalls, 4);
      expect(viewport.frame.rows.first.text, 'wake');
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
            'source': 'osc7',
            'cwd': '/tmp/project',
            'hostname': 'workstation.local',
            'username': 'dev',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_command',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc133',
            'eventType': 'command_finished',
            'command': 'dart test',
            'exitCode': 0,
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
          kind: 'session_notification',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc777',
            'title': 'Build',
            'message': 'Done',
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'session_progress',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc934',
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

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final shellContext = events.whereType<TerminalSessionShellContextEvent>();
      expect(shellContext.single.cwd, '/tmp/project');
      expect(shellContext.single.hostname, 'workstation.local');
      final shellCommand = events.whereType<TerminalSessionShellCommandEvent>();
      expect(shellCommand.single.eventType, 'command_finished');
      expect(shellCommand.single.exitCode, 0);
      expect(
        events.whereType<TerminalSessionShellUserVarEvent>().single.name,
        'IANVS_TEST',
      );
      expect(
        events.whereType<TerminalSessionNotificationEvent>().single.message,
        'Done',
      );
      expect(
        events.whereType<TerminalSessionProgressEvent>().single.id,
        'build',
      );
      expect(
        events.whereType<TerminalSessionBadgeEvent>().single.text,
        'Build',
      );
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
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final paddedPayload = base64.encode(utf8.encode('padded ok'));
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
          payload: const <String, Object?>{'data': ''},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(copiedTexts, <String>['padded ok', '']);
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
            'source': 'osc934',
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
            'source': 'osc934',
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

  testWidgets('terminal runtime controller continues to handle exit events', (
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

    final seenEvents = <TerminalSessionEvent>[];
    final subscription = runtime.events.listen(seenEvents.add);
    addTearDown(subscription.cancel);

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

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    expect(runtime.hasSession(sessionId), isFalse);
    expect(seenEvents.whereType<TerminalSessionExitEvent>().single.exitCode, 7);
  });

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
        resizeWindowBy:
            ({required double widthDelta, required double heightDelta}) async {
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
}

class _FakePtyBackend
    implements
        PtySessionBackend,
        PtySessionJsonRequestBackend,
        PtySessionGraphicAssetBackend {
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
  final Map<(int, int), PtyGraphicAsset> graphicAssets =
      <(int, int), PtyGraphicAsset>{};
  List<Map<String, Object?>> searchResponse = const <Map<String, Object?>>[];
  String? searchRawResponse;
  String? searchErrorText;
  String selectionResponse = '';
  String? selectionRawResponse;
  String? clearScrollbackRawResponse;
  String? scrollbackRawResponse;
  Map<String, Object?>? diagnosticsResponse;
  String? diagnosticsRawResponse;
  bool returnNullJsonRequests = false;

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
    final sessionId = (++_nextSessionId).toString();
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
    writeCalls.add(Uint8List.fromList(bytes));
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    scrollCalls.add((sessionId, deltaLines));
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    scrollToCalls.add((sessionId, offset));
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = (jsonDecode(requestJson) as Map).cast<String, Object?>();
    jsonRequests.add(request);
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
      'terminal.export_scrollback' =>
        scrollbackRawResponse ??
            jsonEncode(<String, Object?>{'content': 'scrollback text'}),
      'terminal.export_diagnostics' =>
        diagnosticsRawResponse ?? jsonEncode(diagnosticsResponse),
      _ => null,
    };
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
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
    pollEventsCalls += 1;
    return _queuedEvents.remove(sessionId) ?? const <PtyEvent>[];
  }

  @override
  PtyGraphicAsset? loadGraphicAsset(
    String sessionId, {
    required int assetId,
    required int assetVersion,
  }) {
    graphicAssetRequests.add((sessionId, assetId, assetVersion));
    return graphicAssets[(assetId, assetVersion)];
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

Map<String, Object?> _singleRowSnapshot(
  String text, {
  int viewportRows = 24,
  int viewportCols = 80,
}) {
  return <String, Object?>{
    'frame_kind': 'snapshot',
    'rows': <Object?>[
      <String, Object?>{'index': 0, 'text': text, 'style_runs': const []},
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
