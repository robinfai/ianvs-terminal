import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/terminal_composer/composer_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class _Runtime extends Fake implements TerminalRuntimeController {
  @override
  Map<String, Object?>? composerRequest(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) => operation == 'composer.state'
      ? {
          'state': 'ready',
          'lease': 'ready-lease',
          'transport': 'shell',
          'contextId': 'root',
          'cwd': '/tmp',
        }
      : null;

  @override
  Map<String, Object?>? commandBlocks(
    String sessionId, [
    Map<String, Object?> payload = const {},
  ]) => {'blocks': <Object?>[]};
}

void main() {
  for (final currentOwner in [false, true]) {
    testWidgets(
      'a read-only layer ending before layout restores only the current pane owner: $currentOwner',
      (tester) async {
        const pane = TerminalPane(
          sessionId: 'local',
          title: 'Local shell',
          profileId: 'local',
        );
        final session = ComposerPaneSession(
          sessionId: 'local',
          runtime: _Runtime(),
          preferredMode: TerminalViewMode.blocks,
        )..updateEnvironment(pane, readOnly: false);
        Widget view(bool active) => MaterialApp(
          home: Scaffold(
            body: ComposerPane(
              session: session,
              targetLabel: pane.title,
              active: active,
              available: true,
              onTerminalFocus: () {},
            ),
          ),
        );
        try {
          await tester.pumpWidget(view(true));
          session.controller.editor.text = 'echo retained draft';
          await tester.pump();
          expect(session.controller.canRun, isTrue);

          // Opening a read-only layer revokes the session immediately. If it
          // closes before the next layout, the widget's active prop may never
          // observe false, so the current layout must reconcile that revoke.
          session.setVisible(false);
          expect(session.controller.canRun, isFalse);
          await tester.pumpWidget(view(currentOwner));
          await tester.pump();
          expect(session.controller.canRun, currentOwner);
          expect(session.controller.editor.text, 'echo retained draft');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          session.dispose();
        }
      },
    );
  }

  for (final disposeDuringBuild in [false, true]) {
    testWidgets(
      'layout environment change revokes input before deferred notification, dispose: $disposeDuringBuild',
      (tester) async {
        const pane = TerminalPane(
          sessionId: 'local',
          title: 'Local shell',
          profileId: 'local',
        );
        final session = ComposerPaneSession(
          sessionId: 'local',
          runtime: _Runtime(),
          preferredMode: TerminalViewMode.blocks,
        )..updateEnvironment(pane, readOnly: false);
        session.setVisible(true);
        session.controller.editor.text = 'echo draft';
        final locked = ValueNotifier(false);
        final sessionPhases = <SchedulerPhase>[];
        final controllerPhases = <SchedulerPhase>[];
        var disposed = false;
        var updated = false;
        session.addListener(
          () => sessionPhases.add(tester.binding.schedulerPhase),
        );
        session.controller.addListener(
          () => controllerPhases.add(tester.binding.schedulerPhase),
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    ListenableBuilder(
                      listenable: session,
                      builder: (_, _) => Text('enabled: ${session.enabled}'),
                    ),
                    ListenableBuilder(
                      listenable: session.controller,
                      builder: (_, _) =>
                          Text('canRun: ${session.controller.canRun}'),
                    ),
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: locked,
                        builder: (_, value, _) => LayoutBuilder(
                          builder: (_, _) {
                            if (value && !updated) {
                              updated = true;
                              session.updateEnvironment(pane, readOnly: true);
                              expect(session.enabled, isFalse);
                              expect(session.controller.canRun, isFalse);
                              expect(
                                session.controller.primaryAction,
                                ComposerPrimaryAction.disabled,
                              );
                              expect(sessionPhases, isEmpty);
                              expect(controllerPhases, isEmpty);
                              if (disposeDuringBuild) {
                                session.dispose();
                                disposed = true;
                              }
                            }
                            return const SizedBox.expand();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          expect(find.text('canRun: true'), findsOneWidget);

          locked.value = true;
          await tester.pump();
          expect(
            sessionPhases,
            disposeDuringBuild ? isEmpty : [SchedulerPhase.postFrameCallbacks],
          );
          expect(
            controllerPhases,
            disposeDuringBuild ? isEmpty : [SchedulerPhase.postFrameCallbacks],
          );
          if (!disposeDuringBuild) {
            await tester.pump();
            expect(find.text('enabled: false'), findsOneWidget);
            expect(find.text('canRun: false'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          if (!disposed) session.dispose();
          locked.dispose();
        }
      },
    );
  }
}
