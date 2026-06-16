import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandBlocksHistoryFeatureFlags', () {
    test('disabled config disables every effective capability', () {
      final flags = CommandBlocksHistoryFeatureFlags.fromConfig(
        const LocalTerminalCommandBlocksHistoryConfig(
          enabled: false,
          commandBlocks: true,
          historyPeek: true,
          failureSnapshots: true,
          reviewWorkspaceEntrypoints: true,
          outputDiff: true,
        ),
      );

      expect(flags.enabled, isFalse);
      expect(flags.commandBlocks, isFalse);
      expect(flags.historyPeek, isFalse);
      expect(flags.failureSnapshots, isFalse);
      expect(flags.reviewWorkspaceEntrypoints, isFalse);
      expect(flags.outputDiff, isFalse);
    });

    test('enabled config allows each selected child capability', () {
      final flags = CommandBlocksHistoryFeatureFlags.fromConfig(
        const LocalTerminalCommandBlocksHistoryConfig(
          enabled: true,
          commandBlocks: true,
          historyPeek: false,
          failureSnapshots: true,
          reviewWorkspaceEntrypoints: false,
          outputDiff: true,
        ),
      );

      expect(flags.enabled, isTrue);
      expect(flags.commandBlocks, isTrue);
      expect(flags.historyPeek, isFalse);
      expect(flags.failureSnapshots, isTrue);
      expect(flags.reviewWorkspaceEntrypoints, isFalse);
      expect(flags.outputDiff, isTrue);
    });
  });
}
