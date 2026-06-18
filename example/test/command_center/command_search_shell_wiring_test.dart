import 'package:app/features/command_center/command_center_runtime.dart';
import 'package:app/features/command_center/command_search_index.dart';
import 'package:app/features/command_center/command_search_intents.dart';
import 'package:app/features/command_center/command_search_overlay_controller.dart';
import 'package:app/features/command_center/command_search_shell_wiring.dart';
import 'package:app/features/command_center/global_command_history_repository.dart';
import 'package:app/features/command_center/shell_hook_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandSearchShellWiring', () {
    const wiring = CommandSearchShellWiring();

    test('builds overlay controller from runtime session history', () {
      const reducer = CommandCenterRuntimeReducer();
      final finishedAt = DateTime.utc(2026, 6, 15, 10);
      final state = reducer.apply(
        const CommandCenterRuntimeState(),
        CommandLifecycleFinishedEvent(
          sessionId: 'session-a',
          receivedAt: finishedAt,
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 0,
        ),
      );

      final controller = wiring.controllerFor(state, sessionId: 'session-a')
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch);

      expect(controller.state.results, hasLength(1));
      expect(
        controller.state.scope,
        CommandSearchHistoryScope.currentSession,
      );
      expect(controller.state.results.single.entry.command, 'flutter test');
      expect(controller.state.results.single.entry.cwd, '/repo');
      expect(controller.state.results.single.entry.finishedAt, finishedAt);
    });

    test(
      'current-session scope keeps the local block-backed duplicate when other sessions or global history share command and cwd',
      () {
        const reducer = CommandCenterRuntimeReducer();
        final sessionAFinishedAt = DateTime.utc(2026, 6, 15, 10);
        final sessionBFinishedAt = sessionAFinishedAt.add(
          const Duration(seconds: 1),
        );
        final sessionAState = reducer.apply(
          const CommandCenterRuntimeState(),
          CommandLifecycleFinishedEvent(
            sessionId: 'session-a',
            receivedAt: sessionAFinishedAt,
            command: 'flutter test',
            cwd: '/repo',
            exitCode: 0,
          ),
        );
        final state = reducer.apply(
          sessionAState,
          CommandLifecycleFinishedEvent(
            sessionId: 'session-b',
            receivedAt: sessionBFinishedAt,
            command: 'flutter test',
            cwd: '/repo',
            exitCode: 0,
          ),
        );
        final sessionAInvocationId = state
            .history
            .entriesForSession('session-a')
            .single
            .invocationId;
        final controller = wiring.controllerFor(
          state,
          sessionId: 'session-a',
          globalHistory: GlobalCommandHistoryDocument(
            entries: [
              GlobalCommandHistoryEntry(
                command: 'flutter test',
                cwd: '/repo',
                exitCode: 0,
                finishedAt: sessionAFinishedAt.subtract(
                  const Duration(minutes: 1),
                ),
                invocationId: 'global-duplicate',
              ),
            ],
          ),
        )..handleIntent(CommandSearchOverlayKeyIntent.openSearch);

        expect(controller.state.scope, CommandSearchHistoryScope.currentSession);
        expect(controller.state.results, hasLength(1));
        expect(controller.state.results.single.entry.sessionId, 'session-a');
        expect(
          controller.state.results.single.entry.invocationId,
          sessionAInvocationId,
        );
      },
    );

    test('resolves overlay output through terminal safety policy', () {
      final insert = wiring.terminalIntentFor(
        const CommandSearchOverlayOutput.insert('git status'),
        readOnly: false,
      );
      final execute = wiring.terminalIntentFor(
        const CommandSearchOverlayOutput.explicitExecute('git status'),
        readOnly: false,
      );
      final readOnly = wiring.terminalIntentFor(
        const CommandSearchOverlayOutput.insert('git status'),
        readOnly: true,
      );
      final multiline = wiring.terminalIntentFor(
        const CommandSearchOverlayOutput.insert('echo one\necho two'),
        readOnly: false,
      );

      expect(insert.kind, CommandSearchTerminalIntentKind.insertText);
      expect(insert.text, 'git status');
      expect(execute.kind, CommandSearchTerminalIntentKind.executeText);
      expect(execute.text, 'git status\n');
      expect(readOnly.kind, CommandSearchTerminalIntentKind.disabled);
      expect(
        multiline.kind,
        CommandSearchTerminalIntentKind.requiresPastePolicy,
      );
    });

    test('view block output does not resolve into terminal writes', () {
      final intent = wiring.terminalIntentFor(
        const CommandSearchOverlayOutput.viewBlock('invocation-1'),
        readOnly: false,
      );

      expect(intent.kind, CommandSearchTerminalIntentKind.none);
      expect(intent.writesToShell, isFalse);
    });
  });
}
