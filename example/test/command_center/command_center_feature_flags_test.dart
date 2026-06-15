import 'package:app/features/command_center/command_center_feature_flags.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandCenterFeatureFlags', () {
    test('defaults every capability to false', () {
      const flags = CommandCenterFeatureFlags();

      expect(flags.enabled, isFalse);
      expect(flags.historySearch, isFalse);
      expect(flags.commandBlocks, isFalse);
      expect(flags.commandBar, isFalse);
      expect(flags.contextChips, isFalse);
      expect(flags.reviewEntrypoints, isFalse);
      expect(flags.verificationDiagnostics, isFalse);
    });

    test('requires the total switch before enabling sub capabilities', () {
      const config = LocalTerminalCommandCenterConfig(
        enabled: false,
        historySearch: true,
        commandBlocks: true,
        commandBar: true,
        contextChips: true,
        reviewEntrypoints: true,
        verificationDiagnostics: true,
      );

      final flags = CommandCenterFeatureFlags.fromConfig(config);

      expect(flags.enabled, isFalse);
      expect(flags.historySearch, isFalse);
      expect(flags.commandBlocks, isFalse);
      expect(flags.commandBar, isFalse);
      expect(flags.contextChips, isFalse);
      expect(flags.reviewEntrypoints, isFalse);
      expect(flags.verificationDiagnostics, isFalse);
    });

    test('resolves enabled sub capabilities from config', () {
      const config = LocalTerminalCommandCenterConfig(
        enabled: true,
        historySearch: true,
        commandBlocks: false,
        commandBar: true,
        contextChips: true,
        reviewEntrypoints: false,
        verificationDiagnostics: true,
      );

      final flags = CommandCenterFeatureFlags.fromConfig(config);

      expect(flags.enabled, isTrue);
      expect(flags.historySearch, isTrue);
      expect(flags.commandBlocks, isFalse);
      expect(flags.commandBar, isTrue);
      expect(flags.contextChips, isTrue);
      expect(flags.reviewEntrypoints, isFalse);
      expect(flags.verificationDiagnostics, isTrue);
    });

    test('allows tests to inject an explicit snapshot', () {
      const flags = CommandCenterFeatureFlags(
        enabled: true,
        historySearch: true,
        commandBlocks: true,
        commandBar: false,
        contextChips: true,
        reviewEntrypoints: false,
        verificationDiagnostics: false,
      );

      expect(flags.enabled, isTrue);
      expect(flags.historySearch, isTrue);
      expect(flags.commandBlocks, isTrue);
      expect(flags.commandBar, isFalse);
      expect(flags.contextChips, isTrue);
      expect(flags.reviewEntrypoints, isFalse);
      expect(flags.verificationDiagnostics, isFalse);
    });

    test('applies development overrides before gating sub capabilities', () {
      final flags = CommandCenterFeatureFlags.fromConfig(
        const LocalTerminalCommandCenterConfig(enabled: false),
        overrides: const CommandCenterFeatureFlagOverrides(
          enabled: true,
          historySearch: true,
        ),
      );

      expect(flags.enabled, isTrue);
      expect(flags.historySearch, isTrue);
      expect(flags.commandBlocks, isFalse);
    });
  });
}
