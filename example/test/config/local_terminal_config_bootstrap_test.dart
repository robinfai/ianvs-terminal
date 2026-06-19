import 'package:app/features/config/local_terminal_config_bootstrap.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal config bootstrap', () {
    test('prefers local config when available', () {
      const local = LocalTerminalConfigDocument(defaultProfileId: 'local');
      const legacy = TerminalAppPreferencesDocument(
        defaults: TerminalAppDefaults(defaultProfileId: 'legacy'),
      );

      final result = LocalTerminalConfigBootstrap.resolve(
        localConfig: local,
        legacyAppPreferences: legacy,
      );

      expect(result.source, LocalTerminalConfigBootstrapSource.localConfig);
      expect(result.config.defaultProfileId, 'local');
      expect(result.config.commandBlocksHistory.enabled, isFalse);
      expect(result.config.commandBlocksHistory.commandBlocks, isFalse);
    });

    test('migrates legacy app preferences when local config is absent', () {
      const legacy = TerminalAppPreferencesDocument(
        defaults: TerminalAppDefaults(defaultProfileId: 'legacy'),
        appearance: TerminalAppAppearance(
          themeMode: TerminalThemeMode.dark,
          terminalViewportPadding: 18,
        ),
        notifications: TerminalAppNotifications(
          commandFinished: false,
          bell: false,
          activity: false,
        ),
      );

      final result = LocalTerminalConfigBootstrap.resolve(
        localConfig: null,
        legacyAppPreferences: legacy,
      );

      expect(
        result.source,
        LocalTerminalConfigBootstrapSource.legacyAppPreferences,
      );
      expect(result.config.defaultProfileId, 'legacy');
      expect(result.config.appearance.themeMode, TerminalThemeMode.dark);
      expect(result.config.appearance.terminalViewportPadding, 18);
      expect(result.config.notifications.enabled, isFalse);
      expect(result.config.commandCenter.enabled, isTrue);
      expect(result.config.commandCenter.historySearch, isTrue);
      expect(result.config.commandCenter.commandBlocks, isTrue);
      expect(result.config.commandCenter.commandBar, isTrue);
      expect(result.config.commandCenter.contextChips, isTrue);
      expect(result.config.commandCenter.reviewEntrypoints, isTrue);
      expect(result.config.commandCenter.verificationDiagnostics, isTrue);
      expect(result.config.commandBlocksHistory.enabled, isTrue);
      expect(result.config.commandBlocksHistory.commandBlocks, isTrue);
      expect(result.config.commandBlocksHistory.failureSnapshots, isTrue);
      expect(
        result.config.commandBlocksHistory.reviewWorkspaceEntrypoints,
        isTrue,
      );
      expect(result.config.commandBlocksHistory.outputDiff, isTrue);
    });

    test('falls back to defaults when no config sources exist', () {
      final result = LocalTerminalConfigBootstrap.resolve(
        localConfig: null,
        legacyAppPreferences: null,
      );

      expect(result.source, LocalTerminalConfigBootstrapSource.defaults);
      expect(result.config.defaultProfileId, isNull);
      expect(result.config.appearance.themeMode, TerminalThemeMode.system);
      expect(
        result.config.appearance.terminalViewportPadding,
        TerminalAppAppearance.defaultTerminalViewportPadding,
      );
      expect(result.config.commandCenter.enabled, isTrue);
      expect(result.config.commandCenter.historySearch, isTrue);
      expect(result.config.commandCenter.commandBlocks, isTrue);
      expect(result.config.commandCenter.commandBar, isTrue);
      expect(result.config.commandCenter.contextChips, isTrue);
      expect(result.config.commandCenter.reviewEntrypoints, isTrue);
      expect(result.config.commandCenter.verificationDiagnostics, isTrue);
      expect(result.config.commandBlocksHistory.enabled, isTrue);
      expect(result.config.commandBlocksHistory.commandBlocks, isTrue);
      expect(result.config.commandBlocksHistory.failureSnapshots, isTrue);
      expect(
        result.config.commandBlocksHistory.reviewWorkspaceEntrypoints,
        isTrue,
      );
      expect(result.config.commandBlocksHistory.outputDiff, isTrue);
    });
  });
}
