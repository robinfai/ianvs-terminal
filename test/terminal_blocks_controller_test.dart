import 'package:flutter_test/flutter_test.dart';

import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';

void main() {
  test('creates updates and completes command blocks', () {
    final controller = _blocksController();

    final block = controller.startBlock(
      id: 'block-1',
      sessionId: 'session-1',
      commandText: 'echo ianvs',
      scrollbackOffset: 4,
    );

    expect(block.status, TerminalBlockStatus.running);
    expect(controller.activeBlock?.id, 'block-1');
    expect(controller.displayIndex, 1);

    controller.updateBlockOutput('block-1', 'ianvs\n');
    controller.finishBlock('block-1', status: TerminalBlockStatus.succeeded);

    expect(controller.blocks.single.outputText, 'ianvs\n');
    expect(controller.blocks.single.status, TerminalBlockStatus.succeeded);
  });

  test('represents failed interrupted and unknown status labels', () {
    expect(TerminalBlockStatus.failed.label, 'Failed');
    expect(TerminalBlockStatus.interrupted.label, 'Interrupted');
    expect(TerminalBlockStatus.unknown.label, 'Unknown');
  });

  test('navigates between blocks and jumps to their scrollback offsets', () {
    final jumps = <int>[];
    final controller = _blocksController(jumpToOffset: jumps.add);
    controller.addBlock(
      const TerminalBlock(
        id: 'block-1',
        sessionId: 'session-1',
        commandText: 'pwd',
        outputText: '/tmp\n',
        status: TerminalBlockStatus.succeeded,
        scrollbackOffset: 2,
      ),
    );
    controller.addBlock(
      const TerminalBlock(
        id: 'block-2',
        sessionId: 'session-1',
        commandText: 'false',
        outputText: '',
        status: TerminalBlockStatus.failed,
        scrollbackOffset: 9,
      ),
    );

    controller.goToPreviousBlock();
    expect(controller.activeBlock?.id, 'block-1');
    expect(jumps, contains(2));

    controller.goToNextBlock();
    expect(controller.activeBlock?.id, 'block-2');
    expect(jumps, contains(9));
  });

  test('selects blocks by id and index while jumping to offsets', () {
    final jumps = <int>[];
    final controller = _blocksController(jumpToOffset: jumps.add)
      ..addBlock(
        const TerminalBlock(
          id: 'block-1',
          sessionId: 'session-1',
          commandText: 'pwd',
          outputText: '/tmp\n',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 2,
        ),
      )
      ..addBlock(
        const TerminalBlock(
          id: 'block-2',
          sessionId: 'session-1',
          commandText: 'false',
          outputText: '',
          status: TerminalBlockStatus.failed,
          scrollbackOffset: 9,
        ),
      );

    controller.selectBlockById('block-1');
    expect(controller.activeBlock?.id, 'block-1');
    expect(jumps.last, 2);

    controller.selectBlockAt(1);
    expect(controller.activeBlock?.id, 'block-2');
    expect(jumps.last, 9);
  });

  test('ignores invalid block selection without jumping', () {
    final jumps = <int>[];
    final controller = _blocksController(jumpToOffset: jumps.add)
      ..addBlock(
        const TerminalBlock(
          id: 'block-1',
          sessionId: 'session-1',
          commandText: 'pwd',
          outputText: '/tmp\n',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 2,
        ),
      );

    controller.selectBlockById('missing');
    controller.selectBlockAt(-1);
    controller.selectBlockAt(3);

    expect(controller.activeBlock?.id, 'block-1');
    expect(jumps, isEmpty);
  });

  test('copy and reinput use the newly selected active block', () async {
    final clipboard = _FakeClipboardClient();
    final reinput = <String>[];
    final controller =
        _blocksController(
            clipboard: clipboard,
            reinputCommand: (command) async {
              reinput.add(command);
            },
          )
          ..addBlock(
            const TerminalBlock(
              id: 'block-1',
              sessionId: 'session-1',
              commandText: 'pwd',
              outputText: '/tmp\n',
              status: TerminalBlockStatus.succeeded,
              scrollbackOffset: 2,
            ),
          )
          ..addBlock(
            const TerminalBlock(
              id: 'block-2',
              sessionId: 'session-1',
              commandText: 'false',
              outputText: '',
              status: TerminalBlockStatus.failed,
              scrollbackOffset: 9,
            ),
          );

    controller.selectBlockById('block-1');
    await controller.copyActiveCommand();
    await controller.copyActiveOutput();
    await controller.reinputActiveCommand();

    expect(clipboard.copied, <String>['pwd', '/tmp\n']);
    expect(reinput, <String>['pwd']);
  });

  test('copies command output and combined block text', () async {
    final clipboard = _FakeClipboardClient();
    final controller = _blocksController(clipboard: clipboard);
    controller.addBlock(
      const TerminalBlock(
        id: 'block-1',
        sessionId: 'session-1',
        commandText: 'printf ianvs',
        outputText: 'ianvs',
        status: TerminalBlockStatus.succeeded,
        scrollbackOffset: 0,
      ),
    );

    await controller.copyActiveCommand();
    await controller.copyActiveOutput();
    await controller.copyActiveCommandAndOutput();

    expect(clipboard.copied, <String>[
      'printf ianvs',
      'ianvs',
      'printf ianvs\nianvs',
    ]);
  });

  test('reinputs command text without appending a newline', () async {
    final reinput = <String>[];
    final controller = _blocksController(
      reinputCommand: (command) async {
        reinput.add(command);
      },
    );
    controller.addBlock(
      const TerminalBlock(
        id: 'block-1',
        sessionId: 'session-1',
        commandText: 'echo ianvs',
        outputText: 'ianvs\n',
        status: TerminalBlockStatus.succeeded,
        scrollbackOffset: 0,
      ),
    );

    await controller.reinputActiveCommand();

    expect(reinput, <String>['echo ianvs']);
  });
}

TerminalBlocksController _blocksController({
  ClipboardClient? clipboard,
  void Function(int offset)? jumpToOffset,
  Future<void> Function(String command)? reinputCommand,
}) {
  return TerminalBlocksController(
    clipboardClient: clipboard ?? _FakeClipboardClient(),
    jumpToOffset: jumpToOffset ?? (_) {},
    reinputCommand: reinputCommand ?? (_) async {},
  );
}

class _FakeClipboardClient implements ClipboardClient {
  final List<String> copied = <String>[];

  @override
  Future<String> readText() async => '';

  @override
  Future<void> writeText(String text) async {
    copied.add(text);
  }
}
