import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/terminal_cursor_move.dart';

void main() {
  test(
    'generated Alt-click arrows reposition real bash/zsh input',
    () async {
      final cases = <Map<String, Object?>>[];
      for (final spec in [
        (
          sourceSuffix: '',
          name: 'ASCII left',
          value: 'abcdef',
          suffix: 'def',
          expected: 'abcXdef',
          cols: 80,
        ),
        (
          sourceSuffix: '',
          name: 'soft wrap left',
          value: 'abcdefghijklmnopqrstuvwxyz',
          suffix: 'klmnopqrstuvwxyz',
          expected: 'abcdefghijXklmnopqrstuvwxyz',
          cols: 20,
        ),
        (
          sourceSuffix: '',
          name: 'Chinese left',
          value: 'a中b',
          suffix: '中b',
          expected: 'aX中b',
          cols: 80,
        ),
        (
          sourceSuffix: 'bcdef',
          name: 'ASCII right',
          value: 'abcdef',
          suffix: 'def',
          expected: 'abcXdef',
          cols: 80,
        ),
        (
          sourceSuffix: '中b',
          name: 'Chinese right',
          value: 'a中b',
          suffix: 'b',
          expected: 'a中Xb',
          cols: 80,
        ),
      ]) {
        final command = "printf '\\nACCEPT:%s:END\\n' ${spec.value}";
        final display = '> $command';
        final cells = TerminalTextCells.fromText(display);
        final end = cells.cellCount;
        final target = end - TerminalTextCells.fromText(spec.suffix).cellCount;
        final sourceCells = TerminalTextCells.fromText(spec.sourceSuffix);
        final start = end - sourceCells.cellCount;
        final rowCount = end ~/ spec.cols + 1;
        final frame = TerminalFrameDiff(
          rows: [
            for (var row = 0; row < rowCount; row++)
              TerminalRow(
                index: row,
                text: cells.sliceColumns(
                  row * spec.cols,
                  (row + 1) * spec.cols,
                ),
                wrapped: row < rowCount - 1,
              ),
          ],
          cursor: TerminalCursor(
            row: start ~/ spec.cols,
            col: start % spec.cols,
            visible: true,
          ),
          viewportRows: 24,
          viewportCols: spec.cols,
          dirtyRanges: const [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        );
        cases.add({
          'beforeSequence':
              '\x1b[D' *
              sourceCells.cells.where((cell) => !cell.isContinuation).length,
          'name': spec.name,
          'command': command,
          'cols': spec.cols,
          'expected': spec.expected,
          'sequence': terminalCursorMoveSequence(
            frame,
            TerminalCellPosition(target ~/ spec.cols, target % spec.cols),
          ),
        });
      }
      final example = Directory.current.path.endsWith('/example')
          ? Directory.current.path
          : '${Directory.current.path}/example';
      final result = await Process.run('python3', [
        '$example/tool/verify_alt_click_pty.py',
        jsonEncode(cases),
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      stdout.write(result.stdout);
      expect(
        'PASS '.allMatches(result.stdout as String).length,
        greaterThanOrEqualTo(5),
      );
    },
    skip: Platform.isWindows,
  );
}
