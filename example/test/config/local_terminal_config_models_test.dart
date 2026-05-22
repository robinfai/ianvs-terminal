import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal config models', () {
    test('decode fills local config defaults', () {
      final config = LocalTerminalConfigDocument.fromJson(const {});

      expect(
        config.schemaVersion,
        LocalTerminalConfigDocument.currentSchemaVersion,
      );
      expect(config.appearance.themeMode, TerminalThemeMode.system);
      expect(
        config.appearance.terminalViewportPadding,
        TerminalAppAppearance.defaultTerminalViewportPadding,
      );
      expect(config.keybindings.disabledDefaultActions, isEmpty);
      expect(config.clipboard.osc52, LocalTerminalOsc52Policy.profile);
      expect(
        config.paste.bracketedPaste,
        LocalTerminalBracketedPastePolicy.auto,
      );
      expect(config.shellIntegration.enabled, isTrue);
      expect(config.notifications.enabled, isTrue);
      expect(config.hotkeyWindow.enabled, isFalse);
    });

    test('decode rejects remote-only top-level fields', () {
      expect(
        () => LocalTerminalConfigDocument.fromJson(const {
          'schemaVersion': 1,
          'remoteDomains': [],
        }),
        throwsFormatException,
      );
    });

    test('keybinding overrides roundtrip through json', () {
      const config = LocalTerminalConfigDocument(
        keybindings: LocalTerminalKeybindingsConfig(
          disabledDefaultActions: {TerminalActionId.pasteHistory},
          overrides: {
            TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
              binding: LocalTerminalKeyBinding(
                scope: TerminalKeyBindingScope.focusedApp,
                key: 'KeyN',
                meta: true,
              ),
            ),
          },
        ),
      );

      final decoded = LocalTerminalConfigDocument.decode(config.encode());
      final override =
          decoded.keybindings.overrides[TerminalActionId.newTab]!.binding!;

      expect(
        decoded.keybindings.disabledDefaultActions,
        contains(TerminalActionId.pasteHistory),
      );
      expect(override.scope, TerminalKeyBindingScope.focusedApp);
      expect(override.key, 'KeyN');
      expect(override.meta, isTrue);
    });

    test('appearance viewport padding roundtrips through json', () {
      const config = LocalTerminalConfigDocument(
        appearance: TerminalAppAppearance(terminalViewportPadding: 16),
      );

      final decoded = LocalTerminalConfigDocument.decode(config.encode());

      expect(decoded.appearance.terminalViewportPadding, 16);
    });
  });
}
