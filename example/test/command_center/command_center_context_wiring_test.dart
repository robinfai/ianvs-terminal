import 'package:app/features/command_center/command_center_context_wiring.dart';
import 'package:app/features/command_center/command_center_runtime.dart';
import 'package:app/features/command_center/command_lifecycle_degraded_state.dart';
import 'package:app/features/command_center/context_chip_models.dart';
import 'package:app/features/command_center/shell_hook_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandCenterContextWiring', () {
    const wiring = CommandCenterContextWiring();

    test('builds context chips from runtime cwd and profile state', () {
      const reducer = CommandCenterRuntimeReducer();
      final state = reducer.apply(
        const CommandCenterRuntimeState(),
        CommandLifecycleCwdChangedEvent(
          sessionId: 'session-a',
          receivedAt: DateTime.utc(2026, 6, 15, 10),
          cwd: '/repo/runtime',
        ),
      );

      final chips = wiring.chipsForSession(
        state,
        sessionId: 'session-a',
        shellIntegrationCwd: '/repo/shell',
        profileId: 'default',
        profileName: 'Default',
        readOnly: true,
      );

      expect(chips.byKind(ContextChipKind.cwd)!.value, '/repo/runtime');
      expect(chips.byKind(ContextChipKind.profile)!.value, 'Default');
      expect(
        chips.byKind(ContextChipKind.shellHook)!.tone,
        ContextChipTone.success,
      );
      expect(
        chips.byKind(ContextChipKind.readOnly)!.intent.kind,
        ContextChipIntentKind.toggleReadOnly,
      );
    });

    test(
      'falls back to shell integration cwd and marks missing cwd limited',
      () {
        final fallback = wiring.chipsForSession(
          const CommandCenterRuntimeState(),
          sessionId: 'session-a',
          shellIntegrationCwd: '/repo/shell',
          profileId: null,
          profileName: null,
        );
        final missing = wiring.chipsForSession(
          const CommandCenterRuntimeState(),
          sessionId: 'session-a',
          shellIntegrationCwd: null,
          profileId: null,
          profileName: null,
        );

        expect(fallback.byKind(ContextChipKind.cwd)!.value, '/repo/shell');
        expect(
          missing.byKind(ContextChipKind.shellHook)!.unavailableReason,
          CommandCenterUnavailableReason.missingCwd,
        );
        expect(
          missing.byKind(ContextChipKind.shellHook)!.tone,
          ContextChipTone.warning,
        );
      },
    );
  });
}
