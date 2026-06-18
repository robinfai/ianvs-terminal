import 'dart:ui';

import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
import 'package:app/features/shell/shell_screen.dart';
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

    test('marks running blocks as live terminal output', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 10,
            endRow: 12,
            command: 'python manage.py shell',
            status: ShellCommandBlockStatus.running,
          ),
        ],
        viewportStartRow: 8,
        viewportEndRow: 24,
        visibleRows: const [terminal.TerminalRow(index: 3, text: '>>> ')],
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks.single.statusLabel, 'running');
      expect(viewModel.blocks.single.outputUsesLiveTerminal, isTrue);
      expect(viewModel.blocks.single.liveTerminalViewportRowOffset, 3);
      expect(viewModel.blocks.single.liveTerminalRows, 2);
      expect(
        shellCommandBlocksShouldRenderOverlay(
          viewModel: viewModel,
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: null,
        ),
        isTrue,
      );
      expect(
        shellCommandBlocksShouldEmbedLiveTerminal(
          viewModel: viewModel,
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: null,
        ),
        isTrue,
      );
      expect(
        shellCommandBlocksShouldHideDefaultTerminal(
          hideWhenVisible: true,
          viewModel: viewModel,
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: null,
        ),
        isTrue,
      );
    });

    test(
      'completed blocks keep the default terminal hidden behind overlay',
      () {
        final viewModel = ShellCommandBlockViewModelBuilder.build(
          blocks: [_commandBlock(startRow: 10, endRow: 12)],
          viewportStartRow: 8,
          viewportEndRow: 24,
          flags: _enabledFlags(),
        );

        expect(
          shellCommandBlocksShouldRenderOverlay(
            viewModel: viewModel,
            modes: terminal.TerminalFrameModes.empty,
            nativeTerminalBlockId: null,
          ),
          isTrue,
        );
        expect(
          shellCommandBlocksShouldEmbedLiveTerminal(
            viewModel: viewModel,
            modes: terminal.TerminalFrameModes.empty,
            nativeTerminalBlockId: null,
          ),
          isFalse,
        );
        expect(
          shellCommandBlocksShouldHideDefaultTerminal(
            hideWhenVisible: true,
            viewModel: viewModel,
            modes: terminal.TerminalFrameModes.empty,
            nativeTerminalBlockId: null,
          ),
          isTrue,
        );
      },
    );

    test('alternate screen switches back to native terminal chrome', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 10,
            endRow: 12,
            command: 'vi README.md',
            status: ShellCommandBlockStatus.running,
          ),
        ],
        viewportStartRow: 8,
        viewportEndRow: 24,
        visibleRows: const [terminal.TerminalRow(index: 3, text: '~')],
        flags: _enabledFlags(),
      );
      const alternateModes = terminal.TerminalFrameModes(alternateScreen: true);
      final nativeTerminalBlockId = shellCommandBlocksNativeTerminalBlockId(
        viewModel: viewModel,
        modes: alternateModes,
      );

      expect(nativeTerminalBlockId, viewModel.blocks.single.id);
      expect(
        shellCommandBlocksShouldUseNativeTerminal(
          modes: alternateModes,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isTrue,
      );
      expect(
        shellCommandBlocksShouldRenderOverlay(
          viewModel: viewModel,
          modes: alternateModes,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isFalse,
      );
      expect(
        shellCommandBlocksShouldEmbedLiveTerminal(
          viewModel: viewModel,
          modes: alternateModes,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isFalse,
      );
      expect(
        shellCommandBlocksShouldHideDefaultTerminal(
          hideWhenVisible: true,
          viewModel: viewModel,
          modes: alternateModes,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isFalse,
      );
      expect(
        shellCommandInputVisibleForCommandBlocks(
          flags: _enabledFlags(),
          modes: alternateModes,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isFalse,
      );
    });

    test('leaving alternate screen restores running command block chrome', () {
      final runningViewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 10,
            endRow: 12,
            command: 'vi README.md',
            status: ShellCommandBlockStatus.running,
          ),
        ],
        viewportStartRow: 8,
        viewportEndRow: 24,
        visibleRows: const [terminal.TerminalRow(index: 3, text: ':q')],
        flags: _enabledFlags(),
      );
      final nativeTerminalBlockId = shellCommandBlocksNativeTerminalBlockId(
        viewModel: runningViewModel,
        modes: terminal.TerminalFrameModes.empty,
      );

      expect(nativeTerminalBlockId, isNull);
      expect(
        shellCommandBlocksShouldUseNativeTerminal(
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isFalse,
      );
      expect(
        shellCommandBlocksShouldRenderOverlay(
          viewModel: runningViewModel,
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isTrue,
      );
      expect(
        shellCommandBlocksShouldEmbedLiveTerminal(
          viewModel: runningViewModel,
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isTrue,
      );
      expect(
        shellCommandBlocksShouldHideDefaultTerminal(
          hideWhenVisible: true,
          viewModel: runningViewModel,
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isTrue,
      );
      expect(
        shellCommandInputVisibleForCommandBlocks(
          flags: _enabledFlags(),
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isTrue,
      );
    });

    test('finished alternate screen command restores command block chrome', () {
      final finishedViewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(startRow: 10, endRow: 12, command: 'vi README.md'),
        ],
        viewportStartRow: 8,
        viewportEndRow: 24,
        visibleRows: const [terminal.TerminalRow(index: 3, text: 'prompt')],
        flags: _enabledFlags(),
      );
      final nativeTerminalBlockId = shellCommandBlocksNativeTerminalBlockId(
        viewModel: finishedViewModel,
        modes: terminal.TerminalFrameModes.empty,
      );

      expect(nativeTerminalBlockId, isNull);
      expect(
        shellCommandBlocksShouldUseNativeTerminal(
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isFalse,
      );
      expect(
        shellCommandBlocksShouldRenderOverlay(
          viewModel: finishedViewModel,
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isTrue,
      );
      expect(
        shellCommandInputVisibleForCommandBlocks(
          flags: _enabledFlags(),
          modes: terminal.TerminalFrameModes.empty,
          nativeTerminalBlockId: nativeTerminalBlockId,
        ),
        isTrue,
      );
    });

    test('empty captured rows suppress visible fallback output', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(startRow: 10, endRow: 12, command: 'vi public.key'),
        ],
        viewportStartRow: 8,
        viewportEndRow: 24,
        visibleRows: const [
          terminal.TerminalRow(
            index: 3,
            text: '2R1R82;10000;0c11;rgb:0000/0000/000010;2m12;0\$y',
          ),
        ],
        capturedRowsByBlockId: const {'cmd-10-12': <terminal.TerminalRow>[]},
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks.single.terminalRows, isEmpty);
      expect(viewModel.blocks.single.outputPreview, isEmpty);
      expect(viewModel.blocks.single.outputRangeLabel, 'rows 11-12');
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
          viewportStartRow: 20,
          viewportEndRow: 40,
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
        expect(viewModel.blocks.first.outputRangeLabel, '2 rows');
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

    test('uses command text when input row includes prompt chrome', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 20,
            endRow: 22,
            command: 'ls',
            cwd: '/Users/robinfai',
          ),
        ],
        viewportStartRow: 20,
        viewportEndRow: 39,
        visibleRows: const [
          terminal.TerminalRow(
            index: 0,
            text: '󰀵 robinfai ~   12:56  ❯ ls',
          ),
          terminal.TerminalRow(index: 1, text: 'Applications'),
        ],
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks.single.inputLine, 'ls');
    });

    test('uses structured command text instead of raw prompt row', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 20,
            endRow: 22,
            command: 'ls',
            cwd: '/Users/luobinghui',
          ),
        ],
        viewportStartRow: 20,
        viewportEndRow: 39,
        visibleRows: const [
          terminal.TerminalRow(index: 0, text: '\uF432 arbitrary PS1 ls'),
          terminal.TerminalRow(index: 1, text: 'Applications'),
        ],
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks.single.inputLine, 'ls');
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

    test(
      'prefers captured rows when historical range overlaps current frame',
      () {
        final viewModel = ShellCommandBlockViewModelBuilder.build(
          blocks: [
            _commandBlock(startRow: 6, endRow: 14, command: 'ls MissingDir'),
          ],
          viewportStartRow: 12,
          viewportEndRow: 23,
          visibleRows: const [
            terminal.TerminalRow(
              index: 0,
              text: 'download-04.txt download-11.txt',
            ),
            terminal.TerminalRow(
              index: 1,
              text: 'download-05.txt download-12.txt',
            ),
            terminal.TerminalRow(
              index: 2,
              text: 'download-06.txt download-13.txt',
            ),
          ],
          capturedRowsByBlockId: const {
            'cmd-6-14': [
              terminal.TerminalRow(
                index: 0,
                text: 'ls: MissingDir: No such file or directory',
              ),
            ],
          },
          flags: _enabledFlags(),
        );

        final block = viewModel.blocks.single;
        expect(
          block.outputPreview,
          'ls: MissingDir: No such file or directory',
        );
        expect(block.terminalRows.map((row) => row.text), [
          'ls: MissingDir: No such file or directory',
        ]);
      },
    );

    test('prefers captured rows over live rows for completed blocks', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 15, endRow: 22, command: 'ls')],
        viewportStartRow: 12,
        viewportEndRow: 23,
        visibleRows: const [
          terminal.TerminalRow(index: 4, text: ' -la'),
          terminal.TerminalRow(index: 5, text: 'total 16'),
          terminal.TerminalRow(index: 6, text: '.hidden-file'),
        ],
        capturedRowsByBlockId: const {
          'cmd-15-22': [
            terminal.TerminalRow(
              index: 0,
              text: 'download-06.txt download-13.txt download-34.txt',
            ),
          ],
        },
        flags: _enabledFlags(),
      );

      final block = viewModel.blocks.single;
      expect(
        block.outputPreview,
        'download-06.txt download-13.txt download-34.txt',
      );
      expect(block.terminalRows.map((row) => row.text), [
        'download-06.txt download-13.txt download-34.txt',
      ]);
    });

    test('does not map viewport-relative rows onto an offscreen block', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 20, endRow: 22, command: 'ls')],
        viewportStartRow: 80,
        viewportEndRow: 99,
        visibleRows: const [
          terminal.TerminalRow(index: 0, text: 'fresh command'),
          terminal.TerminalRow(index: 1, text: 'fresh output'),
        ],
        flags: _enabledFlags(),
      );

      final block = viewModel.blocks.single;
      expect(block.outputPreview, isEmpty);
      expect(block.terminalRows, isEmpty);
    });

    test('uses captured preview rows when current frame range is blank', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 20, endRow: 22, command: 'ls')],
        viewportStartRow: 20,
        viewportEndRow: 39,
        visibleRows: const [
          terminal.TerminalRow(index: 1, text: ''),
          terminal.TerminalRow(index: 2, text: ''),
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
    });

    test('trims trailing blank rows from terminal output', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 10, endRow: 40, command: 'pwd')],
        viewportStartRow: 10,
        viewportEndRow: 40,
        visibleRows: const [
          terminal.TerminalRow(index: 1, text: '/Users/robinfai'),
          terminal.TerminalRow(index: 2, text: ''),
          terminal.TerminalRow(index: 3, text: '   '),
        ],
        flags: _enabledFlags(),
      );

      final block = viewModel.blocks.single;
      expect(block.outputPreview, '/Users/robinfai');
      expect(block.terminalRows.map((row) => row.text), ['/Users/robinfai']);
      expect(block.terminalRows.map((row) => row.index), [0]);
      expect(block.outputRangeLabel, '1 row');
    });

    test('output capture remains open until a prompt boundary is seen', () {
      final block = _commandBlock(
        startRow: 42,
        endRow: 71,
        command: 'll',
        cwd: '/Users/robinfai',
      );

      final partialCapture = shellCommandBlockOutputCaptureFrom(block, const [
        terminal.TerminalRow(index: 0, text: 'total 7600'),
      ]);

      expect(partialCapture.rows.map((row) => row.text), ['total 7600']);
      expect(partialCapture.reachedPromptBoundary, isFalse);

      final completeCapture = shellCommandBlockOutputCaptureFrom(block, const [
        terminal.TerminalRow(index: 0, text: 'total 7600'),
        terminal.TerminalRow(
          index: 1,
          text: 'drwxr-xr-x  10 robinfai staff 320 Applications',
        ),
        terminal.TerminalRow(index: 2, text: 'robinfai ~ 10:39 ❯ ll'),
      ]);

      expect(completeCapture.rows.map((row) => row.text), [
        'total 7600',
        'drwxr-xr-x  10 robinfai staff 320 Applications',
      ]);
      expect(completeCapture.reachedPromptBoundary, isTrue);
    });

    test('output capture keeps long listing rows with owner and time', () {
      final block = _commandBlock(
        startRow: 42,
        endRow: 71,
        command: 'll',
        cwd: '/Users/robinfai',
      );

      final capture = shellCommandBlockOutputCaptureFrom(block, const [
        terminal.TerminalRow(
          index: 0,
          text: 'drwx------+  4 robinfai  staff   128B Mar 16 15:42 Pictures/',
        ),
        terminal.TerminalRow(
          index: 1,
          text: 'drwxr-xr-x+  4 robinfai  staff   128B Mar 16 15:42 Public/',
        ),
        terminal.TerminalRow(index: 2, text: 'robinfai ~ 15:42 ❯'),
      ]);

      expect(capture.rows.map((row) => row.text), [
        'drwx------+  4 robinfai  staff   128B Mar 16 15:42 Pictures/',
        'drwxr-xr-x+  4 robinfai  staff   128B Mar 16 15:42 Public/',
      ]);
      expect(capture.reachedPromptBoundary, isTrue);
    });

    test('output capture drops leading wrapped command continuations', () {
      final missingBlock = _commandBlock(
        startRow: 3,
        endRow: 5,
        command: 'ls MissingDir',
        cwd: '/tmp',
        status: ShellCommandBlockStatus.failed,
      );

      final missingCapture =
          shellCommandBlockOutputCaptureFrom(missingBlock, const [
            terminal.TerminalRow(index: 0, text: ' MissingDir'),
            terminal.TerminalRow(
              index: 1,
              text: 'ls: MissingDir: No such file or directory',
            ),
          ]);

      expect(missingCapture.rows.map((row) => row.text), [
        'ls: MissingDir: No such file or directory',
      ]);

      final echoBlock = _commandBlock(
        startRow: 10,
        endRow: 11,
        command: 'echo hello',
        cwd: '/tmp',
      );

      final echoCapture = shellCommandBlockOutputCaptureFrom(echoBlock, const [
        terminal.TerminalRow(index: 0, text: 'hello'),
      ]);

      expect(echoCapture.rows.map((row) => row.text), ['hello']);
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
