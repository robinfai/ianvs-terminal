import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/terminal_composer/composer_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';

class _UnknownReceiptRuntime extends Fake implements TerminalRuntimeController {
  String ownership = 'ready';
  final submissions = <String>[];

  @override
  Map<String, Object?>? composerRequest(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) {
    if (operation == 'composer.state') {
      return {
        'state': ownership,
        'lease': ownership == 'ready' ? 'ready-lease' : null,
        'transport': 'shell',
        'contextId': 'root',
        'cwd': '/tmp',
        'dialect': 'zsh',
      };
    }
    if (operation == 'composer.submit') {
      submissions.add(payload['text']! as String);
      return {'outcome': 'unknown'};
    }
    return null;
  }

  @override
  Map<String, Object?>? commandBlocks(
    String sessionId, [
    Map<String, Object?> payload = const {},
  ]) => {'blocks': <Object?>[]};
}

void main() {
  group('$ComposerPaneSession submission recovery', () {
    late _UnknownReceiptRuntime runtime;
    late ComposerPaneSession session;

    setUp(() {
      runtime = _UnknownReceiptRuntime();
      session = ComposerPaneSession(
        sessionId: 'local',
        runtime: runtime,
        preferredMode: TerminalViewMode.blocks,
      );
      session.updateEnvironment(
        const TerminalPane(
          sessionId: 'local',
          title: 'Local shell',
          profileId: 'local',
        ),
        readOnly: false,
      );
      session.setVisible(true);
    });

    for (final shellState in ['ready', 'running']) {
      testWidgets(
        'keeps explicit unknown recovery reachable while the shell is $shellState',
        (tester) async {
          try {
            await tester.pumpApp(
              ComposerPane(
                session: session,
                targetLabel: 'Local shell',
                onTerminalFocus: () {},
                active: true,
                available: true,
              ),
            );
            await tester.pump();
            expect(session.enabled, isTrue);
            session.controller.editor.text = 'printf once';
            await session.controller.run();
            runtime.ownership = shellState;

            // Ordinary polling and explicit support checks must retain both
            // the unresolved receipt lock and its local recovery affordance.
            await tester.pump(const Duration(milliseconds: 500));
            session.refreshShellState(recheckSupport: true);
            await tester.pump();
            expect(session.controller.ownership, ComposerOwnership.unknown);
            expect(session.controller.pendingSubmission, isNotNull);
            expect(session.controller.canRun, isFalse);
            expect(session.enabled, isTrue);
            expect(session.mode.state.canUseBlocks, isTrue);
            expect(
              find.byKey(const Key('composer-recover-draft')),
              findsOneWidget,
            );
            await session.controller.run();
            expect(runtime.submissions, ['printf once']);

            await tester.tap(find.byKey(const Key('composer-recover-draft')));
            expect(session.controller.pendingSubmission, isNull);
            expect(session.controller.editor.text, 'printf once');
            expect(session.controller.canRun, isFalse);
            expect(runtime.submissions, ['printf once']);
            session.refreshShellState();
            await tester.pump();
            expect(session.controller.canRun, shellState == 'ready');
            expect(runtime.submissions, ['printf once']);
            expect(
              find.byKey(const Key('composer-recover-draft')),
              findsNothing,
            );

            runtime.ownership = 'ready';
            session.refreshShellState();
            expect(session.controller.canRun, isTrue);
            expect(runtime.submissions, ['printf once']);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            session.dispose();
          }
        },
      );
    }
  });
}
