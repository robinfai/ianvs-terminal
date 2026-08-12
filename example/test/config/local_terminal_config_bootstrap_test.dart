import 'package:app/features/config/local_terminal_config_bootstrap.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal config bootstrap', () {
    test('prefers local config when available', () {
      const local = LocalTerminalConfigDocument(defaultProfileId: 'local');

      final result = LocalTerminalConfigBootstrap.resolve(localConfig: local);

      expect(result.source, LocalTerminalConfigBootstrapSource.localConfig);
      expect(result.config.defaultProfileId, 'local');
    });

    test('falls back to defaults when no config sources exist', () {
      final result = LocalTerminalConfigBootstrap.resolve(localConfig: null);

      expect(result.source, LocalTerminalConfigBootstrapSource.defaults);
      expect(result.config.defaultProfileId, isNull);
      expect(
        result.config.appearance.terminalViewportPadding,
        TerminalAppAppearance.defaultTerminalViewportPadding,
      );
      expect(result.config.layout.restoreLayout, isTrue);
    });
  });
}
