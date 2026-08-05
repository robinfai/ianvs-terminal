import 'package:app/features/shell/shell_action_registry.dart';
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

    test('redesign features stay registered without user entry points', () {
      final composer =
          ShellActionRegistry.actions[TerminalActionId.autoComposer]!;
      final passwordManager =
          ShellActionRegistry.actions[TerminalActionId.passwordManager]!;

      expect(
        composer.releaseVisibility,
        TerminalActionReleaseVisibility.hiddenExperimental,
      );
      expect(
        passwordManager.releaseVisibility,
        TerminalActionReleaseVisibility.hiddenPendingRedesign,
      );
      for (final descriptor in [composer, passwordManager]) {
        expect(descriptor.enabledByDefault, isFalse);
        expect(descriptor.commandPaletteVisible, isFalse);
        expect(descriptor.defaultKeyBinding, isNull);
        expect(ShellActionRegistry.hasUserEntryPoint(descriptor.id), isFalse);
        expect(
          ShellActionRegistry.commandPaletteVisible(descriptor.id),
          isFalse,
        );
      }
    });

    test('release actions are an explicit allowlist', () {
      expect(
        ShellActionRegistry.releaseActionIds,
        containsAll(<TerminalActionId>{
          TerminalActionId.newTab,
          TerminalActionId.openTerminalAtFolder,
          TerminalActionId.openRecording,
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
        ShellActionRegistry.releaseActionIds,
        isNot(
          containsAll(<TerminalActionId>{
            TerminalActionId.toolbelt,
            TerminalActionId.globalSearch,
            TerminalActionId.autocomplete,
            TerminalActionId.pasteHistory,
          }),
        ),
      );
      for (final actionId in TerminalActionId.values) {
        expect(
          ShellActionRegistry.releaseVisibility(actionId) ==
              TerminalActionReleaseVisibility.product,
          ShellActionRegistry.releaseActionIds.contains(actionId),
          reason: '$actionId must derive visibility from the release allowlist',
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
