import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabledFlags = CommandBlocksHistoryFeatureFlags(
  enabled: true,
  commandBlocks: true,
  failureSnapshots: true,
  reviewWorkspaceEntrypoints: false,
  outputDiff: false,
);

void main() {
  group('ShellCommandBlockShellHookReducer', () {
    test('keeps command blocks distinct when clear reuses a command row', () {
      var snapshot = const ShellCommandBlockSnapshot();

      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _enabledFlags,
        sessionId: '1',
        hook: 'preexec',
        command: 'ls',
        cwd: '/tmp/project',
        promptScrollbackOffset: 0,
      );
      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _enabledFlags,
        sessionId: '1',
        hook: 'command_finished',
        command: 'ls',
        cwd: '/tmp/project',
        exitCode: 0,
        promptScrollbackOffset: 2,
        viewportEndRow: 1,
      );

      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _enabledFlags,
        sessionId: '1',
        hook: 'preexec',
        command: 'echo hello',
        cwd: '/tmp/project',
        promptScrollbackOffset: 0,
      );
      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _enabledFlags,
        sessionId: '1',
        hook: 'command_finished',
        command: 'echo hello',
        cwd: '/tmp/project',
        exitCode: 0,
        promptScrollbackOffset: 2,
        viewportEndRow: 1,
      );

      expect(snapshot.blocks, hasLength(2));
      expect(snapshot.blocks.map((block) => block.command), [
        'ls',
        'echo hello',
      ]);
      expect(snapshot.blocks[0].id, '1:command:0');
      expect(snapshot.blocks[1].id, '1:command:0#2');
      expect(snapshot.blocks[0].outputRange.commandRow, 0);
      expect(snapshot.blocks[1].outputRange.commandRow, 0);
      expect(snapshot.blocks[0].status, ShellCommandBlockStatus.succeeded);
      expect(snapshot.blocks[1].status, ShellCommandBlockStatus.succeeded);
    });
  });
}
