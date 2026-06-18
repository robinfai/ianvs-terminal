import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action registry', () {
    test('actions used by command menu are registered', () {
      const actionMenuIds = <TerminalActionId>{
        TerminalActionId.newTab,
        TerminalActionId.toolbelt,
        TerminalActionId.defaults,
        TerminalActionId.profiles,
        TerminalActionId.dynamicProfiles,
        TerminalActionId.copy,
        TerminalActionId.copyMode,
        TerminalActionId.annotations,
        TerminalActionId.capturedOutput,
        TerminalActionId.paste,
        TerminalActionId.advancedPaste,
        TerminalActionId.pasteHistory,
        TerminalActionId.shellIntegrationUtilities,
        TerminalActionId.selectCommandOutput,
        TerminalActionId.tmuxIntegration,
        TerminalActionId.coprocess,
        TerminalActionId.passwordManager,
        TerminalActionId.instantReplay,
        TerminalActionId.search,
        TerminalActionId.openActionSearch,
        TerminalActionId.globalSearch,
        TerminalActionId.autocomplete,
        TerminalActionId.autoComposer,
        TerminalActionId.splitRight,
        TerminalActionId.splitDown,
        TerminalActionId.hotkeyWindow,
      };

      for (final actionId in actionMenuIds) {
        expect(
          ShellActionRegistry.has(actionId),
          isTrue,
          reason: 'Terminal action $actionId should be in registry',
        );
      }
    });

    test('shortcuts are mapped to registered action ids', () {
      const shortcutIds = <TerminalActionId>{
        TerminalActionId.openLauncher,
        TerminalActionId.newTab,
        TerminalActionId.splitRight,
        TerminalActionId.splitDown,
        TerminalActionId.autocomplete,
        TerminalActionId.copyMode,
        TerminalActionId.pasteHistory,
        TerminalActionId.instantReplay,
        TerminalActionId.search,
        TerminalActionId.previousPrompt,
        TerminalActionId.nextPrompt,
        TerminalActionId.closeActiveTab,
        TerminalActionId.openDefaults,
        TerminalActionId.requestQuitConfirmation,
      };

      for (final actionId in shortcutIds) {
        expect(
          ShellActionRegistry.has(actionId),
          isTrue,
          reason: 'Shortcut action $actionId should be in registry',
        );
      }
    });

    test('registered actions expose stable metadata for keybinding config', () {
      for (final actionId in TerminalActionId.values) {
        final descriptor = ShellActionRegistry.actions[actionId];

        expect(
          descriptor,
          isNotNull,
          reason: 'Terminal action $actionId should have descriptor metadata',
        );
        expect(descriptor!.id, actionId);
        expect(descriptor.label, isNotEmpty);
      }
    });

    test('command block history actions expose descriptors', () {
      const commandBlockActionIds = <TerminalActionId>{
        TerminalActionId.openHistoryPeek,
        TerminalActionId.replayFromCommandBlock,
        TerminalActionId.saveCommandSnapshot,
        TerminalActionId.compareLastCommandRun,
        TerminalActionId.markCommandBlock,
      };

      for (final actionId in commandBlockActionIds) {
        final descriptor = ShellActionRegistry.actions[actionId];

        expect(descriptor, isNotNull, reason: '$actionId should be registered');
        expect(descriptor!.terminalInputPolicy, TerminalInputPolicy.appFirst);
        expect(descriptor.requiresActiveSession, isTrue);
      }
    });

    test('history peek action surfaces command search metadata', () {
      final descriptor =
          ShellActionRegistry.actions[TerminalActionId.openHistoryPeek];

      expect(descriptor, isNotNull);
      expect(descriptor!.label, 'command_search');
      expect(descriptor.icon, isNot(Icons.history));
    });

    test('default keybindings do not contain hidden conflicts', () {
      expect(ShellActionRegistry.defaultKeyBindingConflicts(), isEmpty);
    });
  });
}
