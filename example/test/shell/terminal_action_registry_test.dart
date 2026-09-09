import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action registry', () {
    test('actions used by command menu are registered', () {
      const actionMenuIds = <TerminalActionId>{
        TerminalActionId.newTab,
        TerminalActionId.defaults,
        TerminalActionId.profiles,
        TerminalActionId.copy,
        TerminalActionId.paste,
        TerminalActionId.instantReplay,
        TerminalActionId.search,
        TerminalActionId.splitRight,
        TerminalActionId.splitDown,
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
        TerminalActionId.newSshSession,
        TerminalActionId.splitRight,
        TerminalActionId.splitDown,
        TerminalActionId.instantReplay,
        TerminalActionId.search,
        TerminalActionId.clearBuffer,
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

    test('default keybindings do not contain hidden conflicts', () {
      expect(ShellActionRegistry.defaultKeyBindingConflicts(), isEmpty);
    });

    test('registry contains exactly the release action surface', () {
      expect(
        ShellActionRegistry.releaseActionIds,
        containsAll(<TerminalActionId>{
          TerminalActionId.newTab,
          TerminalActionId.newSshSession,
          TerminalActionId.openTerminalAtFolder,
          TerminalActionId.openRecording,
          TerminalActionId.openSftpPanel,
          TerminalActionId.splitRight,
          TerminalActionId.splitDown,
          TerminalActionId.copy,
          TerminalActionId.paste,
          TerminalActionId.search,
          TerminalActionId.toggleSessionRecording,
          TerminalActionId.instantReplay,
          TerminalActionId.exportDiagnostics,
        }),
      );
      expect(
        ShellActionRegistry.commandPaletteVisible(
          TerminalActionId.openSftpPanel,
        ),
        isTrue,
      );
      expect(
        ShellActionRegistry.releaseActionIds,
        TerminalActionId.values.toSet(),
      );
      expect(
        ShellActionRegistry.actions.keys.toSet(),
        TerminalActionId.values.toSet(),
      );
      for (final actionId in TerminalActionId.values) {
        expect(
          ShellActionRegistry.hasUserEntryPoint(actionId),
          isTrue,
          reason: '$actionId must have a release entry point',
        );
      }
    });

    test('recording and replay actions share one product category', () {
      for (final actionId in const <TerminalActionId>[
        TerminalActionId.instantReplay,
        TerminalActionId.toggleSessionRecording,
        TerminalActionId.openRecording,
      ]) {
        expect(
          ShellActionRegistry.actions[actionId]!.category,
          TerminalActionCategory.replay,
        );
      }
    });
  });
}
