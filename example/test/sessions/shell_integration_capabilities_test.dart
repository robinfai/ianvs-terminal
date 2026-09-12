import 'dart:convert';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

void main() {
  group(ShellIntegrationCapabilities, () {
    const pending = ShellIntegrationCapabilities.pending();

    test('startup checks establish readiness before any command events', () {
      final ready = pending.applyRegistration({
        for (final capability in ShellIntegrationCapability.values)
          capability.id: 'registered',
      });
      expect(_active(ready), {
        for (final capability in ShellIntegrationCapability.values)
          if (capability.localHook) capability,
      });
      final start = ready[ShellIntegrationCapability.commandStart];
      expect(start.reason, ShellCapabilityReason.initializationChecked);
      expect(start.evidence, ShellCapabilityEvidence.bootstrapRegistration);
      expect(_active(pending), isEmpty);
      final observed = ready.observe(
        terminal.TerminalSessionShellHookEvent(
          'one',
          rawPayload: {'hook': 'preexec', 'command': 'false'},
        ),
      );
      expect(
        observed[ShellIntegrationCapability.commandStart].reason,
        ShellCapabilityReason.observed,
      );
      expect(
        observed[ShellIntegrationCapability.commandFinish].reason,
        ShellCapabilityReason.initializationChecked,
      );
      expect(
        observed.applyRegistration({
          'command_start': 'registered',
        })[ShellIntegrationCapability.commandStart].reason,
        ShellCapabilityReason.observed,
      );
    });

    test('failed and unknown checks are distinct and honor policy', () {
      final result = pending.applyRegistration({
        'command_start': 'unavailable',
        'command_finish': 'unverified',
        'exit_code': 'unknown',
      });
      expect(
        result[ShellIntegrationCapability.commandStart].status,
        ShellCapabilityStatus.unavailable,
      );
      expect(
        result[ShellIntegrationCapability.commandStart].reason,
        ShellCapabilityReason.initializationFailed,
      );
      expect(
        result[ShellIntegrationCapability.commandFinish].status,
        ShellCapabilityStatus.pending,
      );
      expect(
        result[ShellIntegrationCapability.exitCode].status,
        ShellCapabilityStatus.pending,
      );
      expect(
        pending
            .withPolicy(enabled: false, supportedEmulation: true)
            .applyRegistration({
              'command_start': 'registered',
            })[ShellIntegrationCapability.commandStart]
            .status,
        ShellCapabilityStatus.disabled,
      );
    });

    test(
      'new sessions expose every capability as pending despite enabled injection',
      () {
        final pane = TerminalPane(
          sessionId: 'new',
          title: 'New',
          profileId: 'zsh',
          profileSnapshot: defaultTerminalProfile(),
        );
        expect(
          pane.shellCapabilities.entries.length,
          ShellIntegrationCapability.values.length,
        );
        expect(
          pane.shellCapabilities.entries.values.every(
            (entry) => entry.status == ShellCapabilityStatus.pending,
          ),
          isTrue,
        );
      },
    );

    test(
      'prompt and directory events activate only their observed capabilities',
      () {
        final result = pending
            .observe(
              terminal.TerminalSessionShellHookEvent(
                'one',
                rawPayload: {'hook': 'precmd', 'shell': 'zsh'},
              ),
            )
            .observe(
              terminal.TerminalSessionShellHookEvent(
                'one',
                rawPayload: {
                  'hook': 'precmd.pwd',
                  'pwd': '/private/project',
                  'shell': 'zsh',
                },
              ),
            );
        expect(_active(result), {
          ShellIntegrationCapability.promptLifecycle,
          ShellIntegrationCapability.currentDirectory,
          ShellIntegrationCapability.shellIdentity,
        });
        expect(_active(pending), isEmpty);
      },
    );

    test(
      'command completion does not fabricate start, exit code, or output bounds',
      () {
        final result = pending.observe(
          terminal.TerminalSessionShellHookEvent(
            'one',
            rawPayload: {
              'hook': 'command_finished',
              'command': 'private-command',
            },
          ),
        );
        expect(_active(result), {
          ShellIntegrationCapability.commandFinish,
          ShellIntegrationCapability.commandText,
        });
        final finished = result.observe(
          terminal.TerminalSessionShellHookEvent(
            'one',
            rawPayload: {'hook': 'command_finished', 'exit_code': 0},
          ),
        );
        expect(finished[ShellIntegrationCapability.exitCode].isActive, isTrue);
        expect(
          finished[ShellIntegrationCapability.commandOutputRanges].isActive,
          isFalse,
        );
        expect(
          jsonEncode(finished.toJson()),
          isNot(contains('private-command')),
        );
      },
    );

    test(
      'empty fields, unknown hooks and fractional exit codes prove nothing',
      () {
        final unknown = pending.observe(
          terminal.TerminalSessionShellHookEvent(
            'one',
            rawPayload: {
              'hook': 'unknown',
              'command': 'fake',
              'pwd': '/fake',
              'shell': 'zsh',
            },
          ),
        );
        expect(identical(unknown, pending), isTrue);
        final result = pending.observe(
          terminal.TerminalSessionShellHookEvent(
            'one',
            rawPayload: {
              'hook': 'command_finished',
              'command': ' ',
              'pwd': '\u001b[0m',
              'exit_code': 1.5,
            },
          ),
        );
        expect(_active(result), {ShellIntegrationCapability.commandFinish});
      },
    );

    test('OSC command input does not count as command execution', () {
      var result = pending.observe(
        terminal.TerminalSessionShellCommandEvent(
          'one',
          rawPayload: {'source': 'osc133', 'eventType': 'command_start'},
        ),
      );
      expect(_active(result), isEmpty);
      result = result.observe(
        terminal.TerminalSessionShellCommandEvent(
          'one',
          rawPayload: {'source': 'osc133', 'eventType': 'command_executed'},
        ),
      );
      expect(_active(result), {ShellIntegrationCapability.commandStart});
    });

    test(
      'version metadata does not activate the bundled hook capability set',
      () {
        final result = pending.observe(
          terminal.TerminalSessionShellCommandEvent(
            'one',
            rawPayload: {
              'source': 'osc1337',
              'eventType': 'integration_version',
              'version': '17',
              'shell': 'zsh',
            },
          ),
        );
        expect(_active(result), {
          ShellIntegrationCapability.integrationVersion,
          ShellIntegrationCapability.shellIdentity,
        });
      },
    );

    test('navigation and command output require usable coordinates', () {
      var result = pending.observe(
        terminal.TerminalSessionShellHookEvent(
          'one',
          rawPayload: {'hook': 'precmd', 'prompt_scrollback_offset': -1},
        ),
      );
      expect(
        result[ShellIntegrationCapability.promptNavigation].isActive,
        isFalse,
      );
      result = result.observe(
        terminal.TerminalSessionShellCommandEvent(
          'one',
          rawPayload: {
            'source': 'osc1337',
            'eventType': 'mark',
            'cursorLine': 12,
          },
        ),
      );
      expect(
        result[ShellIntegrationCapability.promptNavigation].isActive,
        isTrue,
      );
      result = result.observe(
        terminal.TerminalSessionShellCommandEvent(
          'one',
          rawPayload: {
            'eventType': 'zone_closed',
            'zoneType': 'output',
            'zoneId': 2,
            'absRowStart': 5,
            'absRowEnd': 4,
          },
        ),
      );
      expect(
        result[ShellIntegrationCapability.commandOutputRanges].isActive,
        isFalse,
      );
      result = result.observe(
        terminal.TerminalSessionShellCommandEvent(
          'one',
          rawPayload: {
            'eventType': 'zone_closed',
            'zoneType': 'output',
            'zoneId': 2,
            'absRowStart': 5,
            'absRowEnd': 8,
          },
        ),
      );
      expect(
        result[ShellIntegrationCapability.commandOutputRanges].isActive,
        isTrue,
      );
    });

    test('identity and allowed user variables are independently observed', () {
      var result = pending.observe(
        terminal.TerminalSessionShellContextEvent(
          'one',
          rawPayload: {
            'source': 'osc7',
            'cwd': '/private/directory',
            'hostname': 'private-host',
          },
        ),
      );
      expect(_active(result), {
        ShellIntegrationCapability.currentDirectory,
        ShellIntegrationCapability.hostname,
      });
      result = result.observe(
        terminal.TerminalSessionShellUserVarEvent(
          'one',
          rawPayload: {'name': 'OTHER_VALUE', 'value': 'no'},
        ),
      );
      expect(
        result[ShellIntegrationCapability.userVariables].isActive,
        isFalse,
      );
      result = result.observe(
        terminal.TerminalSessionShellUserVarEvent(
          'one',
          rawPayload: {'name': 'IANVS_VALUE', 'value': 'private-value'},
        ),
      );
      expect(result[ShellIntegrationCapability.userVariables].isActive, isTrue);
      expect(jsonEncode(result.toJson()), isNot(contains('private-')));
      expect(() => result.entries.clear(), throwsUnsupportedError);
    });

    test(
      'disabled, unsupported and exited panes override observed evidence',
      () {
        final observed = pending.observe(
          terminal.TerminalSessionShellHookEvent(
            'one',
            rawPayload: {'hook': 'preexec', 'command': 'ls'},
          ),
        );
        final profile = defaultTerminalProfile();
        final pane = TerminalPane(
          sessionId: 'one',
          title: 'One',
          profileId: profile.id,
          profileSnapshot: profile,
          shellIntegration: TerminalShellIntegrationSnapshot(
            capabilities: observed,
          ),
        );
        expect(
          pane
              .shellCapabilities[ShellIntegrationCapability.commandStart]
              .isActive,
          isTrue,
        );
        final disabled = pane.copyWith(
          profileSnapshot: profile.copyWith(
            sessionConfig: profile.sessionConfig.copyWith(
              shellIntegration: profile.sessionConfig.shellIntegration.copyWith(
                enabled: false,
              ),
            ),
          ),
        );
        expect(
          disabled.shellCapabilities.entries.values.every(
            (entry) => entry.status == ShellCapabilityStatus.disabled,
          ),
          isTrue,
        );
        final unsupported = pane.copyWith(
          profileSnapshot: profile.copyWith(
            terminalEmulation: TerminalEmulation.vt220,
          ),
        );
        expect(
          unsupported
              .shellCapabilities[ShellIntegrationCapability.commandStart]
              .reason,
          ShellCapabilityReason.unsupportedEmulation,
        );
        expect(
          pane
              .copyWith(isExited: true)
              .shellCapabilities[ShellIntegrationCapability.commandStart]
              .reason,
          ShellCapabilityReason.sessionExited,
        );
        final afterDisabledEvent = disabled.shellCapabilities.observe(
          terminal.TerminalSessionShellHookEvent(
            'one',
            rawPayload: {'hook': 'precmd'},
          ),
        );
        expect(
          afterDisabledEvent.entries.values.every(
            (entry) => entry.status == ShellCapabilityStatus.disabled,
          ),
          isTrue,
        );
      },
    );
  });
}

Set<ShellIntegrationCapability> _active(
  ShellIntegrationCapabilities capabilities,
) => {
  for (final entry in capabilities.entries.entries)
    if (entry.value.isActive) entry.key,
};
