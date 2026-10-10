import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/widgets/desktop_session_status.dart';
import 'package:app/features/terminal_composer/composer_pane.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';

class _Runtime extends Fake implements TerminalRuntimeController {
  final submissions = <Map<String, Object?>>[];
  Map<String, Object?> state = {
    'state': 'ready',
    'contextId': 'root',
    'transport': 'shell',
    'cwd': '/fixture/a',
    'lease': 'root-lease',
  };

  @override
  Map<String, Object?>? composerRequest(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) {
    if (operation == 'composer.submit') submissions.add(Map.of(payload));
    return operation == 'composer.state' ? Map.of(state) : null;
  }
}

class _UnknownAi extends Fake
    with ChangeNotifier
    implements TerminalAiController {
  @override
  bool get hasUnresolvedSubmission => true;

  @override
  AiPhase get phase => AiPhase.failed;
}

void main() {
  const first = TerminalPane(
    sessionId: 'a',
    title: 'Fixture A',
    profileId: 'fixture',
    shellIntegration: TerminalShellIntegrationSnapshot(
      hostname: 'host-a.example',
      currentDirectory: '/fixture/a',
      contextId: 'root',
    ),
  );

  Widget status({
    String sessionId = 'a',
    TerminalPane? pane = first,
    ComposerPaneSession? composer,
    bool aiVisible = false,
    bool observing = false,
    TerminalAiController? ai,
    VoidCallback? onDetails,
  }) => Align(
    alignment: Alignment.bottomCenter,
    child: DesktopSessionStatus(
      sessionId: sessionId,
      pane: pane,
      composer: composer,
      ai: ai,
      aiVisible: aiVisible,
      observing: observing,
      readOnly: false,
      replaying: false,
      onDetails: onDetails,
    ),
  );

  testWidgets('switching targets never carries the previous ready state', (
    tester,
  ) async {
    final composer = ComposerPaneSession(sessionId: 'a', runtime: _Runtime());
    addTearDown(composer.dispose);
    composer.controller.updateShell(
      contextKey: 'a/root',
      cwd: '/fixture/a',
      ownership: ComposerOwnership.ready,
      lease: 'a-lease',
    );
    composer.mode.updateAvailability(null);
    await tester.pumpApp(status(composer: composer));
    expect(find.text('Shell ready'), findsOneWidget);
    await tester.pumpApp(status(sessionId: 'b', composer: composer));
    expect(find.textContaining('host-a'), findsNothing);
    expect(find.text('Shell ready'), findsNothing);
    expect(find.textContaining('Checking active target'), findsOneWidget);
    await tester.pumpApp(
      status(
        sessionId: 'b',
        pane: const TerminalPane(
          sessionId: 'b',
          title: 'Fixture B',
          profileId: 'fixture',
        ),
        composer: composer,
      ),
    );
    expect(find.textContaining('Fixture B'), findsOneWidget);
    expect(find.text('Checking shell state…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a new node never inherits the previous shell ready fact', (
    tester,
  ) async {
    final runtime = _Runtime();
    final composer = ComposerPaneSession(sessionId: 'a', runtime: runtime);
    addTearDown(composer.dispose);
    composer.updateEnvironment(first, readOnly: false);
    composer.refreshShellState();
    await tester.pumpApp(status(composer: composer));
    expect(find.text('Shell ready'), findsOneWidget);

    final nested = first.copyWith(
      shellIntegration: const TerminalShellIntegrationSnapshot(
        hostname: 'host-b.example',
        contextId: 'ssh-child',
        contextKind: 'ssh',
      ),
    );
    composer.updateEnvironment(nested, readOnly: false);
    expect(
      composer.mode.state.unavailableReason,
      BlockUnavailableReason.checking,
    );
    await tester.pumpApp(status(pane: nested, composer: composer));
    expect(find.textContaining('host-b.example'), findsOneWidget);
    expect(find.text('Shell ready'), findsNothing);
    expect(find.text('Checking shell state…'), findsOneWidget);

    runtime.state = {
      ...runtime.state,
      'contextId': 'ssh-child',
      'lease': 'new',
    };
    composer.refreshShellState();
    await tester.pumpAndSettle();
    expect(find.text('Shell ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a same-session SSH change keeps the real unknown receipt and checking fact',
    (tester) async {
      final runtime = _Runtime();
      final composer = ComposerPaneSession(
        sessionId: 'a',
        runtime: runtime,
        preferredMode: TerminalViewMode.blocks,
      );
      addTearDown(composer.dispose);
      composer.updateEnvironment(first, readOnly: false);
      composer.setVisible(true);
      composer.controller.editor.text = 'ssh child';
      await composer.controller.run();
      expect(runtime.submissions, hasLength(1));
      expect(runtime.submissions.single['text'], 'ssh child');
      expect(composer.controller.ownership, ComposerOwnership.unknown);
      final receipt = composer.controller.pendingSubmission;
      expect(receipt, isNotNull);

      await tester.pumpApp(status(composer: composer));
      expect(find.text('Submission unknown'), findsOneWidget);
      final nested = first.copyWith(
        shellIntegration: const TerminalShellIntegrationSnapshot(
          hostname: 'host-b.example',
          contextId: 'ssh-child',
          contextKind: 'ssh',
        ),
      );
      composer.updateEnvironment(nested, readOnly: false);
      expect(
        composer.mode.state.unavailableReason,
        BlockUnavailableReason.checking,
      );
      await tester.pumpApp(status(pane: nested, composer: composer));
      expect(find.textContaining('host-b.example'), findsOneWidget);
      expect(
        find.text('Submission unknown · Checking shell state…'),
        findsOneWidget,
      );
      expect(find.textContaining('Shell ready'), findsNothing);

      runtime.state = {
        ...runtime.state,
        'contextId': 'ssh-child',
        'lease': 'child-lease',
      };
      composer.refreshShellState();
      await tester.pump();
      expect(find.text('Submission unknown'), findsOneWidget);
      expect(composer.controller.pendingSubmission, same(receipt));
      expect(composer.controller.canRun, isFalse);

      final disconnected = nested.copyWith(isExited: true, exitCode: 255);
      composer.updateEnvironment(disconnected, readOnly: false);
      await tester.pumpApp(status(pane: disconnected, composer: composer));
      expect(
        find.text('Submission unknown · Disconnected · exit 255'),
        findsOneWidget,
      );
      expect(find.textContaining('Read-only'), findsOneWidget);
      expect(composer.controller.pendingSubmission, same(receipt));
      expect(runtime.submissions, hasLength(1));

      await tester.pumpApp(
        status(
          sessionId: 'b',
          pane: const TerminalPane(
            sessionId: 'b',
            title: 'Other session',
            profileId: 'fixture',
          ),
          composer: composer,
        ),
      );
      expect(find.textContaining('Submission unknown'), findsNothing);
      expect(find.text('Checking shell state…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('observer and disconnected status never imply human input', (
    tester,
  ) async {
    await tester.pumpApp(status(aiVisible: true, observing: true));
    expect(find.textContaining('Human input paused'), findsOneWidget);
    await tester.pumpApp(
      status(pane: first.copyWith(isExited: true, exitCode: 255)),
    );
    expect(find.text('Disconnected · exit 255'), findsOneWidget);
    expect(find.textContaining('Read-only'), findsOneWidget);
    expect(find.textContaining('Human input'), findsNothing);
  });

  testWidgets(
    'ready and disconnected shells never hide an unknown AI submission',
    (tester) async {
      final composer = ComposerPaneSession(sessionId: 'a', runtime: _Runtime());
      final ai = _UnknownAi();
      addTearDown(composer.dispose);
      addTearDown(ai.dispose);
      composer.controller.updateShell(
        contextKey: 'a/root',
        cwd: '/fixture/a',
        ownership: ComposerOwnership.ready,
        lease: 'a-lease',
      );
      composer.mode.updateAvailability(null);
      await tester.pumpApp(status(composer: composer, ai: ai));
      expect(find.text('Submission unknown · Shell ready'), findsOneWidget);
      await tester.pumpApp(
        status(pane: first.copyWith(isExited: true, exitCode: 255), ai: ai),
      );
      expect(
        find.text('Submission unknown · Disconnected · exit 255'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'narrow scaled status retains full accessible details without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      await tester.pumpApp(
        status(onDetails: () => opened++),
        textScale: 2,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      final semantic = tester.widget<Semantics>(
        find.byKey(const Key('desktop-session-status')),
      );
      expect(semantic.properties.label, contains('/fixture/a'));
      expect(semantic.properties.label, contains('Session: a'));
      await tester.tap(find.byKey(const Key('desktop-session-status')));
      expect(opened, 1);
    },
  );
}
