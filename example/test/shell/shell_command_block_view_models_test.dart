import 'dart:ui';

import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlockViewModels', () {
    test('returns no overlays when commandBlocks flag is off', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          ShellCommandBlock(
            id: 'cmd',
            command: 'flutter test',
            outputRange: const ShellCommandBlockRange(
              commandRow: 1,
              outputStartRow: 2,
              outputEndRow: 4,
            ),
            status: ShellCommandBlockStatus.failed,
          ),
        ],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: CommandBlocksHistoryFeatureFlags.disabled,
      );

      expect(viewModel.blocks, isEmpty);
    });

    test('maps visible failed block into overlay state', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          ShellCommandBlock(
            id: 'cmd',
            command: 'flutter test',
            cwd: '/repo',
            exitCode: 1,
            outputRange: const ShellCommandBlockRange(
              commandRow: 10,
              outputStartRow: 11,
              outputEndRow: 20,
            ),
            status: ShellCommandBlockStatus.failed,
          ),
        ],
        viewportStartRow: 8,
        viewportEndRow: 24,
        activeBlockId: 'cmd',
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.id, 'cmd');
      expect(viewModel.blocks.single.active, isTrue);
      expect(viewModel.blocks.single.statusLabel, 'exit 1');
      expect(viewModel.blocks.single.showFailureSnapshotAction, isTrue);
      expect(viewModel.blocks.single.showReplayAction, isTrue);
    });

    test(
      'builds bottom stack newest first with output and duration summary',
      () {
        final startedAt = DateTime(2026, 6, 9, 19, 31, 0);
        final finishedAt = startedAt.add(const Duration(milliseconds: 1240));

        final viewModel = ShellCommandBlockViewModelBuilder.build(
          blocks: [
            _commandBlock(startRow: 2, endRow: 4, command: 'pwd'),
            _commandBlock(startRow: 20, endRow: 22, command: 'ls -al'),
          ],
          viewportStartRow: 100,
          viewportEndRow: 120,
          visibleRows: [
            terminal.TerminalRow(
              index: 20,
              text: 'ls -al',
              modifiedAt: startedAt,
            ),
            terminal.TerminalRow(
              index: 21,
              text: 'Applications  Desktop',
              styleRuns: [
                terminal.TerminalStyleRun(
                  start: 12,
                  end: 14,
                  background: Color(0xFF000000),
                ),
              ],
              modifiedAt: startedAt.add(const Duration(milliseconds: 180)),
            ),
            terminal.TerminalRow(
              index: 22,
              text: 'Documents     Downloads',
              modifiedAt: finishedAt,
            ),
          ],
          flags: _enabledFlags(),
        );

        expect(viewModel.blocks.map((block) => block.command), [
          'ls -al',
          'pwd',
        ]);
        expect(
          viewModel.blocks.first.outputPreview,
          ['Applications  Desktop', 'Documents     Downloads'].join('\n'),
        );
        expect(viewModel.blocks.first.terminalRows.map((row) => row.text), [
          'Applications  Desktop',
          'Documents     Downloads',
        ]);
        expect(viewModel.blocks.first.terminalRows.map((row) => row.index), [
          0,
          1,
        ]);
        expect(
          viewModel.blocks.first.terminalRows.first.styleRuns.single.background,
          const Color(0xFF000000),
        );
        expect(viewModel.blocks.first.outputRangeLabel, 'rows 21-22');
        expect(viewModel.blocks.first.durationLabel, '1.2s');
      },
    );

    test('filters prompt and readline rows from output preview', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 10,
            endRow: 13,
            command: 'ls-al',
            cwd: '/Users/robinfai',
            status: ShellCommandBlockStatus.failed,
          ),
        ],
        viewportStartRow: 10,
        viewportEndRow: 13,
        visibleRows: const [
          terminal.TerminalRow(
            index: 11,
            text: '?? robinfai? ~ ???? ? 20:18 ?? ls-al',
          ),
          terminal.TerminalRow(
            index: 12,
            text: 'zsh: command not found: ls-al',
          ),
          terminal.TerminalRow(
            index: 13,
            text: '?? robinfai? ~ ???? ? 20:18 ??',
          ),
        ],
        flags: _enabledFlags(),
      );

      expect(
        viewModel.blocks.single.outputPreview,
        'zsh: command not found: ls-al',
      );
      expect(viewModel.blocks.single.terminalRows.map((row) => row.text), [
        'zsh: command not found: ls-al',
      ]);
    });

    test('terminal preview stops at the next prompt for broad ranges', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 10,
            endRow: 20,
            command: 'pwd',
            cwd: '/Users/dev',
          ),
        ],
        viewportStartRow: 10,
        viewportEndRow: 20,
        visibleRows: const [
          terminal.TerminalRow(index: 11, text: '/Users/dev'),
          terminal.TerminalRow(index: 12, text: 'dev ~ 00:43 >'),
          terminal.TerminalRow(index: 13, text: 'echo 123'),
          terminal.TerminalRow(index: 14, text: '123'),
        ],
        flags: _enabledFlags(),
      );

      final block = viewModel.blocks.single;
      expect(block.outputPreview, '/Users/dev');
      expect(block.terminalRows.map((row) => row.text), ['/Users/dev']);
    });

    test('terminal preview stops before arrow prompt command lines', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 10,
            endRow: 20,
            command: 'pwd',
            cwd: '/Users/dev',
          ),
        ],
        viewportStartRow: 10,
        viewportEndRow: 20,
        visibleRows: const [
          terminal.TerminalRow(index: 11, text: '/Users/dev'),
          terminal.TerminalRow(index: 12, text: 'dev ~ 00:43 \u279c'),
          terminal.TerminalRow(index: 13, text: '\u2192 echo 123'),
          terminal.TerminalRow(index: 14, text: '123'),
        ],
        flags: _enabledFlags(),
      );

      final block = viewModel.blocks.single;
      expect(block.outputPreview, '/Users/dev');
      expect(block.terminalRows.map((row) => row.text), ['/Users/dev']);
    });

    test('maps viewport-relative terminal rows to command block output', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 20, endRow: 22, command: 'ls')],
        viewportStartRow: 20,
        viewportEndRow: 39,
        visibleRows: const [
          terminal.TerminalRow(index: 0, text: 'ls'),
          terminal.TerminalRow(index: 1, text: 'Documents  Downloads'),
          terminal.TerminalRow(index: 2, text: 'Pictures   Public'),
        ],
        flags: _enabledFlags(),
      );

      final block = viewModel.blocks.single;
      expect(block.inputLine, 'ls');
      expect(block.outputPreview, 'Documents  Downloads\nPictures   Public');
      expect(block.terminalRows.map((row) => row.text), [
        'Documents  Downloads',
        'Pictures   Public',
      ]);
      expect(block.terminalRows.map((row) => row.index), [0, 1]);
    });

    test('uses captured preview rows when output is outside current frame', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 20, endRow: 22, command: 'ls')],
        viewportStartRow: 80,
        viewportEndRow: 99,
        visibleRows: const [
          terminal.TerminalRow(index: 0, text: ''),
          terminal.TerminalRow(index: 1, text: 'prompt'),
        ],
        capturedRowsByBlockId: const {
          'cmd-20-22': [
            terminal.TerminalRow(index: 0, text: 'Documents  Downloads'),
            terminal.TerminalRow(index: 1, text: 'Pictures   Public'),
          ],
        },
        flags: _enabledFlags(),
      );

      final block = viewModel.blocks.single;
      expect(block.outputPreview, 'Documents  Downloads\nPictures   Public');
      expect(block.terminalRows.map((row) => row.text), [
        'Documents  Downloads',
        'Pictures   Public',
      ]);
      expect(block.terminalRows.map((row) => row.index), [0, 1]);
    });

    test('reviewWorkspaceEntrypoints flag drives replay action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 1, endRow: 4)],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(reviewWorkspaceEntrypoints: false),
      );

      expect(viewModel.blocks.single.showReplayAction, isFalse);
    });

    test('invalid viewport returns empty and does not throw', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 5, endRow: 10)],
        viewportStartRow: 20,
        viewportEndRow: 10,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, isEmpty);
    });

    test('block crossing viewport is clipped', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 5, endRow: 20)],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.rowOffset, 0);
      expect(viewModel.blocks.single.rowSpan, 3);
    });

    test('block completely outside viewport stays in command stack', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 1, endRow: 4)],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks.single.command, 'flutter test');
    });

    test('invalid block is skipped', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          const ShellCommandBlock(
            id: '',
            command: 'flutter test',
            outputRange: ShellCommandBlockRange(
              commandRow: 1,
              outputStartRow: 2,
              outputEndRow: 4,
            ),
          ),
        ],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, isEmpty);
    });

    test('view model freezes blocks list against external mutation', () {
      final blocks = [_overlayItem(id: 'first')];
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks(blocks);

      blocks.add(_overlayItem(id: 'second'));

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.id, 'first');
      expect(
        () => viewModel.blocks.add(_overlayItem(id: 'third')),
        throwsA(anything),
      );
    });

    test('failed without exitCode status label is failed', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 1,
            endRow: 4,
            status: ShellCommandBlockStatus.failed,
          ),
        ],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks.single.statusLabel, 'failed');
    });

    test('single block with outputDiff flag does not show diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 1, endRow: 4)],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.single.showDiffAction, isFalse);
    });

    test('previous matching command and cwd enables diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(startRow: 1, endRow: 4, cwd: '/repo'),
          _commandBlock(startRow: 10, endRow: 12, cwd: '/repo'),
        ],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.first.id, 'cmd-10-12');
      expect(viewModel.blocks.first.showDiffAction, isTrue);
    });

    test('future matching command and cwd does not enable diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(startRow: 10, endRow: 12, cwd: '/repo'),
          _commandBlock(startRow: 20, endRow: 24, cwd: '/repo'),
        ],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(outputDiff: true),
      );

      final current = viewModel.blocks.singleWhere(
        (block) => block.id == 'cmd-10-12',
      );

      expect(current.showDiffAction, isFalse);
    });

    test('previous command mismatch does not enable diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 1,
            endRow: 4,
            command: 'dart test',
            cwd: '/repo',
          ),
          _commandBlock(startRow: 10, endRow: 12, cwd: '/repo'),
        ],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.first.id, 'cmd-10-12');
      expect(viewModel.blocks.first.showDiffAction, isFalse);
    });

    test('previous cwd mismatch does not enable diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(startRow: 1, endRow: 4, cwd: '/other'),
          _commandBlock(startRow: 10, endRow: 12, cwd: '/repo'),
        ],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.first.id, 'cmd-10-12');
      expect(viewModel.blocks.first.showDiffAction, isFalse);
    });

    test('succeeded block does not show failure snapshot action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 1, endRow: 4)],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(failureSnapshots: true),
      );

      expect(viewModel.blocks.single.showFailureSnapshotAction, isFalse);
    });

    test(
      'failed block without failureSnapshots flag hides snapshot action',
      () {
        final viewModel = ShellCommandBlockViewModelBuilder.build(
          blocks: [
            _commandBlock(
              startRow: 1,
              endRow: 4,
              status: ShellCommandBlockStatus.failed,
            ),
          ],
          viewportStartRow: 0,
          viewportEndRow: 10,
          flags: _enabledFlags(failureSnapshots: false),
        );

        expect(viewModel.blocks.single.showFailureSnapshotAction, isFalse);
      },
    );

    test('block ending on viewport start is visible', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 5, endRow: 10)],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.rowOffset, 0);
      expect(viewModel.blocks.single.rowSpan, 1);
    });

    test('block starting on viewport end is visible', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 12, endRow: 12)],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.rowOffset, 2);
      expect(viewModel.blocks.single.rowSpan, 1);
    });
  });
}

CommandBlocksHistoryFeatureFlags _enabledFlags({
  bool failureSnapshots = true,
  bool reviewWorkspaceEntrypoints = true,
  bool outputDiff = false,
}) {
  return CommandBlocksHistoryFeatureFlags(
    enabled: true,
    commandBlocks: true,
    historyPeek: false,
    failureSnapshots: failureSnapshots,
    reviewWorkspaceEntrypoints: reviewWorkspaceEntrypoints,
    outputDiff: outputDiff,
  );
}

ShellCommandBlock _commandBlock({
  required int startRow,
  required int endRow,
  String command = 'flutter test',
  String? cwd,
  ShellCommandBlockStatus status = ShellCommandBlockStatus.succeeded,
}) {
  return ShellCommandBlock(
    id: 'cmd-$startRow-$endRow',
    command: command,
    cwd: cwd,
    outputRange: ShellCommandBlockRange(
      commandRow: startRow,
      outputStartRow: startRow == endRow ? startRow : startRow + 1,
      outputEndRow: endRow,
    ),
    status: status,
  );
}

ShellCommandBlockOverlayItem _overlayItem({required String id}) {
  return ShellCommandBlockOverlayItem(
    id: id,
    command: 'flutter test',
    rowOffset: 0,
    rowSpan: 1,
    status: ShellCommandBlockStatus.succeeded,
    statusLabel: 'exit 0',
    active: false,
    showFailureSnapshotAction: false,
    showReplayAction: false,
    showDiffAction: false,
  );
}
