import 'package:app/features/sessions/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sampled_recording_shell.dart';
import '../support/shell_command_actions.dart';

void main() {
  sampledShellTest(
    'command palette manually starts and stops sampled capture and opens its saved result',
    (tester) async {
      final harness = await pumpSampledShell(tester, seed: false);
      final id = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await openShellCommand(tester, 'shell-toggle-session-recording');
      await pumpSampledUntil(
        tester,
        () => harness.container
            .read(sessionControllerProvider)
            .recordingSessionIds
            .contains(id),
      );
      expect(harness.backend.manifestBeforeStart, isTrue);
      expect(harness.backend.capturedIds, hasLength(1));
      await openShellCommand(tester, 'shell-toggle-session-recording');
      await pumpSampledUntil(
        tester,
        () => find
            .byKey(const Key('recording-saved-replay'))
            .evaluate()
            .isNotEmpty,
      );
      expect(harness.library.activeClaims, isEmpty);
      final entries = await pumpSampledFuture(
        tester,
        harness.library.listRecordings,
      );
      expect(entries, hasLength(1));
      expect(entries.single.state, 'finished');
      expect(entries.single.path, endsWith('.trailrec'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recording-saved-replay')));
      await pumpSampledUntil(
        tester,
        () => find
            .byKey(const Key('recording-replay-layout'))
            .evaluate()
            .isNotEmpty,
      );
      expect(harness.backend.createdSessions, hasLength(1));
      expect(
        harness.backend.actions.every(
          (op) => op.startsWith('terminal.sampled_recording_'),
        ),
        isTrue,
      );
    },
  );
}
