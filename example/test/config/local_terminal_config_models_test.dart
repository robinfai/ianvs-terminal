import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/policies/local_terminal_policy_models.dart';
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

    test('schema version copyWith and toJson normalize persisted values', () {
      final copied = const LocalTerminalConfigDocument().copyWith(
        schemaVersion: -1,
      );
      const direct = LocalTerminalConfigDocument(schemaVersion: 0);

      expect(
        copied.schemaVersion,
        LocalTerminalConfigDocument.currentSchemaVersion,
      );
      expect(
        direct.toJson()['schemaVersion'],
        LocalTerminalConfigDocument.currentSchemaVersion,
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

    test(
      'default profile id copyWith and toJson normalize persisted values',
      () {
        final trimmed = const LocalTerminalConfigDocument().copyWith(
          defaultProfileId: ' ssh ',
        );
        final blank = const LocalTerminalConfigDocument(
          defaultProfileId: 'ssh',
        ).copyWith(defaultProfileId: '   ');
        const direct = LocalTerminalConfigDocument(defaultProfileId: '   ');

        expect(trimmed.defaultProfileId, 'ssh');
        expect(blank.defaultProfileId, isNull);
        expect(direct.toJson()['defaultProfileId'], isNull);
      },
    );

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

    test('keybinding json rejects overly long keys', () {
      final config = LocalTerminalConfigDocument.fromJson({
        'keybindings': {
          'overrides': {
            'newTab': {
              'binding': {
                'key': List<String>.filled(
                  maxLocalTerminalKeyBindingKeyLength + 1,
                  'K',
                ).join(),
                'meta': true,
              },
            },
            'openDefaults': {
              'binding': {'key': 'KeyO', 'meta': true},
            },
          },
        },
      });

      expect(
        config.keybindings.overrides[TerminalActionId.newTab]!.binding,
        isNull,
      );
      expect(
        config
            .keybindings
            .overrides[TerminalActionId.openDefaults]!
            .binding!
            .key,
        'KeyO',
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

    test('keybinding json restores valid actions after malformed prefixes', () {
      final malformedPrefixLength = TerminalActionId.values.length * 2;
      final config = LocalTerminalConfigDocument.fromJson({
        'keybindings': {
          'disabledDefaultActions': [
            for (var index = 0; index < malformedPrefixLength; index += 1)
              'not-an-action-$index',
            'newTab',
          ],
          'overrides': {
            for (var index = 0; index < malformedPrefixLength; index += 1)
              'not-an-action-$index': {
                'binding': {'key': 'KeyX'},
              },
            'paste': {
              'binding': {'key': 'KeyV', 'meta': true},
            },
          },
        },
      });

      expect(
        config.keybindings.disabledDefaultActions,
        contains(TerminalActionId.newTab),
      );
      expect(
        config.keybindings.overrides[TerminalActionId.paste]!.binding!.key,
        'KeyV',
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

    test('OSC 52 policy parses ask and deny aliases', () {
      final askConfig = LocalTerminalConfigDocument.fromJson(const {
        'clipboard': {'osc52': ' Ask '},
      });
      final denyConfig = LocalTerminalConfigDocument.fromJson(const {
        'clipboard': {'osc52': 'deny'},
      });

      expect(askConfig.clipboard.osc52, LocalTerminalOsc52Policy.ask);
      expect(denyConfig.clipboard.osc52, LocalTerminalOsc52Policy.disabled);
      expect(
        askConfig.clipboard
            .copyWith(osc52: LocalTerminalOsc52Policy.allow)
            .osc52,
        LocalTerminalOsc52Policy.allow,
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

    test('paste history size accepts zero and caps invalid values', () {
      final disabled = LocalTerminalConfigDocument.fromJson(const {
        'paste': {'historySize': 0},
      });
      final negative = LocalTerminalConfigDocument.fromJson(const {
        'paste': {'historySize': -1},
      });
      final fractional = LocalTerminalConfigDocument.fromJson(const {
        'paste': {'historySize': 2.5},
      });
      final excessive = LocalTerminalConfigDocument.fromJson({
        'paste': {'historySize': defaultLocalTerminalPasteHistoryEntries + 1},
      });

      expect(disabled.paste.historySize, 0);
      expect(
        negative.paste.historySize,
        defaultLocalTerminalPasteHistoryEntries,
      );
      expect(
        fractional.paste.historySize,
        defaultLocalTerminalPasteHistoryEntries,
      );
      expect(
        excessive.paste.historySize,
        defaultLocalTerminalPasteHistoryEntries,
      );
    });
  });
}
