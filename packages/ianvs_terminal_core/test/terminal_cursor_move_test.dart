import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';
import 'package:ianvs_terminal_core/src/terminal/terminal_cursor_move.dart';

void main() {
  group('terminalCursorMoveSequence', () {
    test('moves left and right without vertical arrows in normal buffer', () {
      final frame = _frame();
      expect(
        terminalCursorMoveSequence(frame, const TerminalCellPosition(1, 1)),
        '\x1b[D' * 3,
      );
      expect(
        terminalCursorMoveSequence(frame, const TerminalCellPosition(0, 8)),
        '\x1b[D' * 6,
      );
      expect(
        terminalCursorMoveSequence(frame, const TerminalCellPosition(2, 2)),
        '\x1b[C' * 8,
      );
      expect(
        terminalCursorMoveSequence(frame, const TerminalCellPosition(1, 4)),
        '',
      );
    });
    test('soft wrapping in normal buffer still uses only horizontal keys', () {
      expect(
        terminalCursorMoveSequence(
          _frame(wrapped: true),
          const TerminalCellPosition(0, 8),
        ),
        '\x1b[D' * 6,
      );
    });
    test('does not clamp trailing blank cells to the rendered text end', () {
      expect(
        terminalCursorMoveSequence(
          _frame(text: 'abc'),
          const TerminalCellPosition(1, 8),
        ),
        '\x1b[C' * 4,
      );
    });
    test('rejects projected history outside the current live screen', () {
      expect(
        terminalCursorMoveSequence(
          _frame(projected: true, placeholder: false),
          const TerminalCellPosition(0, 1),
        ),
        '',
      );
    });
    test(
      'does not compare retained source rows with lifetime history counters',
      () {
        expect(
          terminalCursorMoveSequence(
            _frame(projected: true, bottom: 10022),
            const TerminalCellPosition(1, 1),
          ),
          '\x1b[D' * 3,
        );
        expect(
          terminalCursorMoveSequence(
            _frame(alternate: true, bottom: 10022),
            const TerminalCellPosition(0, 2),
          ),
          '\x1b[A${'\x1b[D' * 2}',
        );
      },
    );
    test('encodes application cursor sequences', () {
      expect(
        terminalCursorMoveSequence(
          _frame(application: true),
          const TerminalCellPosition(1, 2),
        ),
        '\x1bOD' * 2,
      );
    });
    test('counts Chinese once and snaps its continuation to its start', () {
      final frame = _frame(text: 'a中b');
      expect(
        terminalCursorMoveSequence(frame, const TerminalCellPosition(1, 1)),
        '\x1b[D' * 2,
      );
      expect(
        terminalCursorMoveSequence(frame, const TerminalCellPosition(1, 2)),
        '\x1b[D' * 2,
      );
      expect(
        terminalCursorMoveSequence(frame, const TerminalCellPosition(2, 0)),
        '\x1b[C' * 6,
      );
    });
    test('counts wide emoji and combining clusters without UTF16 length', () {
      expect(
        terminalCursorMoveSequence(
          _frame(text: 'a😀b'),
          const TerminalCellPosition(1, 0),
        ),
        '\x1b[D' * 3,
      );
      expect(
        terminalCursorMoveSequence(
          _frame(text: 'ae\u0301bc'),
          const TerminalCellPosition(1, 0),
        ),
        '\x1b[D' * 4,
      );
    });
    test('navigates vertically in alternate buffer', () {
      expect(
        terminalCursorMoveSequence(
          _frame(alternate: true),
          const TerminalCellPosition(0, 2),
        ),
        '\x1b[A${'\x1b[D' * 2}',
      );
      expect(
        terminalCursorMoveSequence(
          _frame(alternate: true, application: true),
          const TerminalCellPosition(2, 6),
        ),
        '\x1bOB${'\x1bOC' * 2}',
      );
    });
    test('uses previous-line wrap flags in alternate buffer', () {
      final frame = _frame(alternate: true, wrapped: true);
      expect(
        terminalCursorMoveSequence(frame, const TerminalCellPosition(0, 8)),
        '\x1b[D' * 6,
      );
      expect(
        terminalCursorMoveSequence(frame, const TerminalCellPosition(2, 2)),
        '${'\x1b[D' * 10}\x1b[B${'\x1b[D' * 2}',
      );
    });
    test('rejects history, application mouse mode and outside coordinates', () {
      expect(
        terminalCursorMoveSequence(
          _frame(scroll: 1),
          const TerminalCellPosition(1, 0),
        ),
        '',
      );
      expect(
        terminalCursorMoveSequence(
          _frame(mouse: true),
          const TerminalCellPosition(1, 0),
        ),
        '',
      );
      for (final point in [
        const TerminalCellPosition(-1, 0),
        const TerminalCellPosition(3, 0),
        const TerminalCellPosition(0, 10),
      ]) {
        expect(terminalCursorMoveSequence(_frame(), point), '');
      }
    });
    test(
      'uses source distance across projected rows and rejects placeholders',
      () {
        final frame = _frame(projected: true);
        expect(
          terminalCursorMoveSequence(frame, const TerminalCellPosition(2, 2)),
          '\x1b[C' * 18,
        );
        expect(
          terminalCursorMoveSequence(frame, const TerminalCellPosition(0, 0)),
          '',
        );
      },
    );
  });
  group('TerminalInteractionConfig alt click', () {
    test('defaults on and preserves explicit false through JSON and copy', () {
      expect(
        TerminalInteractionConfig.fromJson({}).altClickMovesCursor,
        isTrue,
      );
      final value = const TerminalInteractionConfig().copyWith(
        altClickMovesCursor: false,
      );
      expect(
        TerminalInteractionConfig.fromJson(value.toJson()).altClickMovesCursor,
        isFalse,
      );
      expect(value.copyWith(copyOnSelect: true).altClickMovesCursor, isFalse);
    });
  });
}

TerminalFrameDiff _frame({
  bool alternate = false,
  bool application = false,
  bool wrapped = false,
  bool mouse = false,
  int scroll = 0,
  String text = 'abcdefghij',
  bool projected = false,
  bool placeholder = true,
  int? bottom,
}) => TerminalFrameDiff(
  rows: [
    TerminalRow(
      index: 0,
      text: '0123456789',
      wrapped: wrapped,
      sourceRow: projected ? 10 : null,
      sourceEndRow: projected ? (placeholder ? 17 : 10) : null,
    ),
    TerminalRow(index: 1, text: text, sourceRow: projected ? 18 : null),
    TerminalRow(index: 2, text: 'abcdefghij', sourceRow: projected ? 20 : null),
  ],
  cursor: const TerminalCursor(row: 1, col: 4, visible: true),
  viewportRows: 3,
  viewportCols: 10,
  globalBottomRow: bottom,
  dirtyRanges: const [],
  scrollbackOffset: scroll,
  scrollbackMaxOffset: 20,
  modes: TerminalFrameModes(
    alternateScreen: alternate,
    applicationCursor: application,
    mouseMode: mouse ? 'normal' : 'off',
  ),
);
