import 'package:flutter_test/flutter_test.dart';

import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/command_history.dart';
import 'package:ianvs_terminal/src/saved_commands.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';

void main() {
  test('derives latest completed non-empty command history from blocks', () {
    final blocks = _blocksController();
    final history = CommandHistoryController(
      blocksController: blocks,
      reinputCommand: (_) async {},
    );
    addTearDown(history.dispose);

    blocks
      ..addBlock(
        const TerminalBlock(
          id: 'block-1',
          sessionId: 'session-1',
          commandText: 'pwd',
          outputText: '/tmp\n',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 1,
        ),
      )
      ..addBlock(
        const TerminalBlock(
          id: 'block-2',
          sessionId: 'session-1',
          commandText: 'echo alpha',
          outputText: 'alpha\n',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 2,
        ),
      )
      ..addBlock(
        const TerminalBlock(
          id: 'block-3',
          sessionId: 'session-1',
          commandText: 'still running',
          outputText: '',
          status: TerminalBlockStatus.running,
          scrollbackOffset: 3,
        ),
      )
      ..addBlock(
        const TerminalBlock(
          id: 'block-4',
          sessionId: 'session-1',
          commandText: 'echo alpha',
          outputText: 'new alpha\nsecond\n',
          status: TerminalBlockStatus.failed,
          scrollbackOffset: 4,
        ),
      )
      ..addBlock(
        const TerminalBlock(
          id: 'block-5',
          sessionId: 'session-1',
          commandText: '   ',
          outputText: '',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 5,
        ),
      );

    expect(history.matches.map((entry) => entry.commandText), <String>[
      'echo alpha',
      'pwd',
    ]);
    expect(history.matches.first.blockId, 'block-4');
    expect(history.matches.first.outputPreview, 'new alpha');
    expect(history.matches.first.scrollbackOffset, 4);
    expect(history.displayIndex, 1);
  });

  test('filters commands case-insensitively and cycles active match', () {
    final blocks = _blocksController()
      ..addBlock(
        const TerminalBlock(
          id: 'block-1',
          sessionId: 'session-1',
          commandText: 'git status',
          outputText: '',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 1,
        ),
      )
      ..addBlock(
        const TerminalBlock(
          id: 'block-2',
          sessionId: 'session-1',
          commandText: 'echo Ianvs',
          outputText: 'Ianvs\n',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 2,
        ),
      )
      ..addBlock(
        const TerminalBlock(
          id: 'block-3',
          sessionId: 'session-1',
          commandText: 'grep ianvs README.md',
          outputText: '',
          status: TerminalBlockStatus.failed,
          scrollbackOffset: 3,
        ),
      );
    final history = CommandHistoryController(
      blocksController: blocks,
      reinputCommand: (_) async {},
    );
    addTearDown(history.dispose);

    history.updateQuery('IANVS');

    expect(history.matches.map((entry) => entry.commandText), <String>[
      'grep ianvs README.md',
      'echo Ianvs',
    ]);
    expect(history.displayIndex, 1);

    history.goToNext();
    expect(history.activeEntry?.commandText, 'echo Ianvs');
    expect(history.displayIndex, 2);

    history.goToNext();
    expect(history.activeEntry?.commandText, 'grep ianvs README.md');

    history.goToPrevious();
    expect(history.activeEntry?.commandText, 'echo Ianvs');
  });

  test(
    'choosing active history entry reinputs command without newline',
    () async {
      final reinput = <String>[];
      final blocks = _blocksController()
        ..addBlock(
          const TerminalBlock(
            id: 'block-1',
            sessionId: 'session-1',
            commandText: 'pwd',
            outputText: '/tmp\n',
            status: TerminalBlockStatus.succeeded,
            scrollbackOffset: 1,
          ),
        );
      final history = CommandHistoryController(
        blocksController: blocks,
        reinputCommand: (command) async {
          reinput.add(command);
        },
      );
      addTearDown(history.dispose);

      await history.chooseActiveEntry();

      expect(reinput, <String>['pwd']);
      expect(history.isOpen, isFalse);
    },
  );

  test(
    'merges saved commands before current tab history and removes duplicates',
    () {
      final saved = SavedCommandsController.memory()
        ..addCommand('pwd')
        ..addCommand('git status');
      addTearDown(saved.dispose);
      final blocks = _blocksController()
        ..addBlock(
          const TerminalBlock(
            id: 'block-1',
            sessionId: 'session-1',
            commandText: 'pwd',
            outputText: '/tmp\n',
            status: TerminalBlockStatus.succeeded,
            scrollbackOffset: 1,
          ),
        )
        ..addBlock(
          const TerminalBlock(
            id: 'block-2',
            sessionId: 'session-1',
            commandText: 'echo local',
            outputText: 'local\n',
            status: TerminalBlockStatus.succeeded,
            scrollbackOffset: 2,
          ),
        );
      final history = CommandHistoryController(
        blocksController: blocks,
        savedCommandsController: saved,
        reinputCommand: (_) async {},
      );
      addTearDown(history.dispose);

      expect(history.matches.map((entry) => entry.commandText), <String>[
        'git status',
        'pwd',
        'echo local',
      ]);
      expect(
        history.matches.map((entry) => entry.source),
        <CommandHistoryEntrySource>[
          CommandHistoryEntrySource.saved,
          CommandHistoryEntrySource.saved,
          CommandHistoryEntrySource.history,
        ],
      );

      history.updateQuery('P');

      expect(history.matches.map((entry) => entry.commandText), <String>[
        'pwd',
      ]);
      expect(history.matches.single.source, CommandHistoryEntrySource.saved);
    },
  );

  test('saves and removes active command search entries', () {
    final saved = SavedCommandsController.memory();
    addTearDown(saved.dispose);
    final blocks = _blocksController()
      ..addBlock(
        const TerminalBlock(
          id: 'block-1',
          sessionId: 'session-1',
          commandText: 'echo local',
          outputText: 'local\n',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 2,
        ),
      );
    final history = CommandHistoryController(
      blocksController: blocks,
      savedCommandsController: saved,
      reinputCommand: (_) async {},
    );
    addTearDown(history.dispose);

    expect(history.activeEntry?.source, CommandHistoryEntrySource.history);

    expect(history.saveActiveEntry(), isTrue);
    expect(saved.commands, <String>['echo local']);
    expect(history.activeEntry?.source, CommandHistoryEntrySource.saved);

    expect(history.removeActiveEntry(), isTrue);
    expect(saved.commands, isEmpty);
    expect(history.activeEntry?.source, CommandHistoryEntrySource.history);
  });
}

TerminalBlocksController _blocksController() {
  return TerminalBlocksController(
    clipboardClient: _FakeClipboardClient(),
    jumpToOffset: (_) {},
    reinputCommand: (_) async {},
  );
}

class _FakeClipboardClient implements ClipboardClient {
  @override
  Future<String> readText() async => '';

  @override
  Future<void> writeText(String text) async {}
}
