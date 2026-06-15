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
      expect(config.notifications.commandFinished, isTrue);
      expect(config.notifications.bell, isTrue);
      expect(config.notifications.activity, isTrue);
      expect(config.hotkeyWindow.enabled, isFalse);
      expect(config.commandCenter.enabled, isFalse);
      expect(config.commandCenter.historySearch, isFalse);
      expect(config.commandCenter.commandBlocks, isFalse);
      expect(config.commandCenter.commandBar, isFalse);
      expect(config.commandCenter.contextChips, isFalse);
      expect(config.commandCenter.reviewEntrypoints, isFalse);
      expect(config.commandCenter.verificationDiagnostics, isFalse);
    });

    test('command center config decodes explicit flags', () {
      final config = LocalTerminalConfigDocument.fromJson(const {
        'commandCenter': {
          'enabled': true,
          'historySearch': true,
          'commandBlocks': false,
          'commandBar': true,
          'contextChips': true,
          'reviewEntrypoints': false,
          'verificationDiagnostics': true,
        },
      });

      expect(config.commandCenter.enabled, isTrue);
      expect(config.commandCenter.historySearch, isTrue);
      expect(config.commandCenter.commandBlocks, isFalse);
      expect(config.commandCenter.commandBar, isTrue);
      expect(config.commandCenter.contextChips, isTrue);
      expect(config.commandCenter.reviewEntrypoints, isFalse);
      expect(config.commandCenter.verificationDiagnostics, isTrue);
      expect(config.commandCenter.toJson(), {
        'enabled': true,
        'historySearch': true,
        'commandBlocks': false,
        'commandBar': true,
        'contextChips': true,
        'reviewEntrypoints': false,
        'verificationDiagnostics': true,
      });
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

    test('default profile id trims whitespace and rejects blanks', () {
      final trimmed = LocalTerminalConfigDocument.fromJson(const {
        'defaultProfileId': ' ssh ',
      });
      final blank = LocalTerminalConfigDocument.fromJson(const {
        'defaultProfileId': '   ',
      });

      expect(trimmed.defaultProfileId, 'ssh');
      expect(blank.defaultProfileId, isNull);
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

    test('keybinding json trims keys and rejects blank keys', () {
      final config = LocalTerminalConfigDocument.fromJson(const {
        'keybindings': {
          'overrides': {
            'newTab': {
              'binding': {'key': ' KeyN ', 'meta': true},
            },
            'openDefaults': {
              'binding': {'key': '   ', 'meta': true},
            },
          },
        },
      });

      expect(
        config.keybindings.overrides[TerminalActionId.newTab]!.binding!.key,
        'KeyN',
      );
      expect(
        config.keybindings.overrides[TerminalActionId.openDefaults]!.binding,
        isNull,
      );
    });

    test('keybinding action ids trim whitespace and ignore case', () {
      final config = LocalTerminalConfigDocument.fromJson(const {
        'keybindings': {
          'disabledDefaultActions': [' PASTEHISTORY ', '   '],
          'overrides': {
            ' NEWTAB ': {
              'binding': {'key': 'KeyN', 'meta': true},
            },
          },
        },
      });

      expect(
        config.keybindings.disabledDefaultActions,
        contains(TerminalActionId.pasteHistory),
      );
      expect(
        config.keybindings.overrides[TerminalActionId.newTab]!.binding!.key,
        'KeyN',
      );
    });

    test('config enum values trim whitespace and ignore case', () {
      final config = LocalTerminalConfigDocument.fromJson(const {
        'keybindings': {
          'overrides': {
            'newTab': {
              'binding': {'scope': ' FOCUSEDAPP ', 'key': 'KeyN'},
            },
          },
        },
        'clipboard': {'osc52': ' ALLOW '},
        'paste': {'bracketedPaste': ' FORCE '},
      });

      expect(
        config.keybindings.overrides[TerminalActionId.newTab]!.binding!.scope,
        TerminalKeyBindingScope.focusedApp,
      );
      expect(config.clipboard.osc52, LocalTerminalOsc52Policy.allow);
      expect(
        config.paste.bracketedPaste,
        LocalTerminalBracketedPastePolicy.force,
      );
    });

    test('decode rejects non-object json roots', () {
      expect(
        () => LocalTerminalConfigDocument.decode('[]'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Local config JSON must be an object.',
          ),
        ),
      );
    });

    test('schema version rejects non-positive values', () {
      final zero = LocalTerminalConfigDocument.fromJson(const {
        'schemaVersion': 0,
      });
      final negative = LocalTerminalConfigDocument.fromJson(const {
        'schemaVersion': -1,
      });
      final fractional = LocalTerminalConfigDocument.fromJson(const {
        'schemaVersion': 2.5,
      });

      expect(
        zero.schemaVersion,
        LocalTerminalConfigDocument.currentSchemaVersion,
      );
      expect(
        negative.schemaVersion,
        LocalTerminalConfigDocument.currentSchemaVersion,
      );
      expect(
        fractional.schemaVersion,
        LocalTerminalConfigDocument.currentSchemaVersion,
      );
    });

    test('appearance viewport padding roundtrips through json', () {
      const config = LocalTerminalConfigDocument(
        appearance: TerminalAppAppearance(terminalViewportPadding: 16),
      );

      final decoded = LocalTerminalConfigDocument.decode(config.encode());

      expect(decoded.appearance.terminalViewportPadding, 16);
    });

    test('notifications keep independent toggles through json', () {
      const config = LocalTerminalConfigDocument(
        notifications: LocalTerminalNotificationsConfig(
          enabled: true,
          commandFinished: false,
          bell: true,
          activity: false,
        ),
      );

      final decoded = LocalTerminalConfigDocument.decode(config.encode());

      expect(decoded.notifications.enabled, isTrue);
      expect(decoded.notifications.commandFinished, isFalse);
      expect(decoded.notifications.bell, isTrue);
      expect(decoded.notifications.activity, isFalse);
    });

    test('paste history size accepts zero but rejects negatives', () {
      final disabled = LocalTerminalConfigDocument.fromJson(const {
        'paste': {'historySize': 0},
      });
      final negative = LocalTerminalConfigDocument.fromJson(const {
        'paste': {'historySize': -1},
      });
      final fractional = LocalTerminalConfigDocument.fromJson(const {
        'paste': {'historySize': 2.5},
      });

      expect(disabled.paste.historySize, 0);
      expect(negative.paste.historySize, 50);
      expect(fractional.paste.historySize, 50);
    });
  });
}
