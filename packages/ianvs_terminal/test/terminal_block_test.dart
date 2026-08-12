import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/proto/frame_diff.pb.dart' as frame_pb;
import 'package:ianvs_terminal/src/transport/terminal_protobuf_frame_codec.dart';

import 'support/terminal_frame_from_json.dart';

void main() {
  test('OSC 1337 block JSON frames preserve reversible source mappings', () {
    final frame = terminalFrameFromJson(const <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'first …1 line… last',
          'source_row': 100,
          'source_end_row': 102,
        },
        <String, Object?>{
          'index': 1,
          'text': 'done',
          'source_row': 103,
          'source_end_row': 103,
        },
        <String, Object?>{'index': 2, 'text': ''},
        <String, Object?>{'index': 3, 'text': ''},
      ],
      'cursor': <String, Object?>{'row': 1, 'col': 4, 'visible': true},
      'viewport_rows': 4,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[],
      'scrollback_offset': 0,
      'scrollback_max_offset': 20,
      'viewport_start_row': 100,
      'blocks': <Object?>[
        <String, Object?>{
          'id': 'build-1',
          'block_type': 'build',
          'start_row': 0,
          'end_row': 0,
          'source_start_row': 100,
          'source_end_row': 102,
          'folded': true,
          'rendered': true,
          'hidden_rows': 2,
        },
      ],
    });

    expect(frame.rows.first.sourceRow, 100);
    expect(frame.rows.first.sourceEndRow, 102);
    expect(frame.sourceRowForViewportRow(0), 100);
    expect(frame.sourceEndRowForViewportRow(0), 102);
    expect(frame.viewportRowForSourceRow(101), 0);
    expect(frame.viewportRowForSourceRow(103), 1);
    expect(frame.viewportRowForSourceRow(99), isNull);
    expect(frame.mappedSourceRowForViewportRow(2), isNull);
    expect(frame.blocks, hasLength(1));
    expect(frame.blocks.single.id, 'build-1');
    expect(frame.blocks.single.blockType, 'build');
    expect(frame.blocks.single.folded, isTrue);
    expect(frame.blocks.single.rendered, isTrue);
    expect(frame.blocks.single.canFold, isTrue);
    expect(frame.blocks.single.hiddenRows, 2);
  });

  test('OSC 1337 block protobuf frames preserve source ranges', () {
    final payload = frame_pb.TerminalFrameDiff(
      frameSchemaVersion: TerminalFrameDiff.currentFrameSchemaVersion,
      frameKind: frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_SNAPSHOT,
      rows: <frame_pb.TerminalRow>[
        frame_pb.TerminalRow(
          index: 0,
          text: 'first …1 line… last',
          sourceRow: 100,
          sourceEndRow: 102,
        ),
      ],
      cursor: frame_pb.TerminalCursor(row: 0, col: 0, visible: false),
      viewportRows: 4,
      viewportCols: 80,
      scrollbackOffset: 0,
      scrollbackMaxOffset: 20,
      viewportStartRow: 100,
      blocks: <frame_pb.TerminalBlock>[
        frame_pb.TerminalBlock(
          id: 'build-1',
          blockType: 'build',
          startRow: 0,
          endRow: 0,
          sourceStartRow: 100,
          sourceEndRow: 102,
          folded: true,
          rendered: true,
          hiddenRows: 2,
        ),
      ],
    );

    final frame = const TerminalProtobufFrameCodec().decode(
      payload.writeToBuffer(),
    );

    expect(
      (frame.rows.single.sourceRow, frame.rows.single.sourceEndRow),
      (100, 102),
    );
    expect(frame.blocks, hasLength(1));
    expect(frame.blocks.single.id, 'build-1');
    expect(frame.blocks.single.blockType, 'build');
    expect(frame.blocks.single.sourceStartRow, 100);
    expect(frame.blocks.single.sourceEndRow, 102);
    expect(frame.blocks.single.folded, isTrue);
    expect(frame.blocks.single.rendered, isTrue);
    expect(frame.blocks.single.hiddenRows, 2);
  });

  test(
    'selection projection maps hidden source rows onto the fold summary',
    () {
      const frame = TerminalFrameDiff(
        rows: <TerminalRow>[
          TerminalRow(
            index: 0,
            text: 'first …1 line… last',
            sourceRow: 100,
            sourceEndRow: 102,
          ),
          TerminalRow(
            index: 1,
            text: 'done',
            sourceRow: 103,
            sourceEndRow: 103,
          ),
          TerminalRow(index: 2, text: ''),
          TerminalRow(index: 3, text: ''),
        ],
        cursor: TerminalCursor(row: 1, col: 4, visible: true),
        viewportRows: 4,
        viewportCols: 80,
        dirtyRanges: <TerminalDirtyRange>[],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 20,
        viewportStartRow: 100,
      );
      final selection = SelectionController();
      addTearDown(selection.dispose);
      selection.setSelection(
        const TerminalSelection(
          startRow: 101,
          startCol: 0,
          endRow: 103,
          endCol: 4,
        ),
      );

      final projected = selection.selectionForFrame(frame);

      expect(projected, isNotNull);
      expect(projected!.startRow, 0);
      expect(projected.endRow, 1);
      expect(projected.startCol, 0);
      expect(projected.endCol, 4);

      selection.setSelection(
        const TerminalSelection(
          startRow: 102,
          startCol: 0,
          endRow: 102,
          endCol: 4,
        ),
      );
      final hiddenOnly = selection.selectionForFrame(frame);
      expect(hiddenOnly, isNotNull);
      expect(hiddenOnly!.startRow, 0);
      expect(hiddenOnly.endRow, 0);
    },
  );
}
