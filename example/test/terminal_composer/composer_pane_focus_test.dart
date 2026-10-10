import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/terminal_composer/composer_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';

class _Runtime extends Fake implements TerminalRuntimeController {
  String ownership = 'ready';

  @override
  Map<String, Object?>? composerRequest(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) => operation == 'composer.state'
      ? {
          'state': ownership,
          'lease': ownership == 'ready' ? 'ready-lease' : null,
          'transport': 'shell',
          'contextId': 'root',
          'cwd': '/tmp',
          'dialect': 'zsh',
        }
      : null;

  @override
  Map<String, Object?>? commandBlocks(
    String sessionId, [
    Map<String, Object?> payload = const {},
  ]) => {'blocks': <Object?>[]};
}

void main() {
  group('Composer ownership focus', () {
    late _Runtime runtime;
    late ComposerPaneSession session;
    late FocusNode terminalFocus;
    late FocusNode otherFocus;

    setUp(() {
      runtime = _Runtime();
      terminalFocus = FocusNode(debugLabel: 'Test live terminal');
      otherFocus = FocusNode(debugLabel: 'Another input owner');
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

    void focusTest(
      String description,
      Future<void> Function(WidgetTester tester) body,
    ) {
      testWidgets(description, (tester) async {
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          session.dispose();
          terminalFocus.dispose();
          otherFocus.dispose();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
        }
      });
    }

    Future<void> mount(WidgetTester tester) async {
      await tester.pumpApp(
        Column(
          children: [
            Expanded(
              child: Focus(
                focusNode: terminalFocus,
                child: const SizedBox.expand(),
              ),
            ),
            TextField(focusNode: otherFocus),
            ComposerPane(
              session: session,
              targetLabel: 'Local shell',
              onTerminalFocus: terminalFocus.requestFocus,
              terminalFocus: terminalFocus,
              active: true,
              available: true,
            ),
          ],
        ),
      );
      await tester.pump();
      session.editorFocus.requestFocus();
      await tester.pump();
      expect(session.editorFocus.hasFocus, isTrue);
    }

    Future<void> ownership(WidgetTester tester, String value) async {
      runtime.ownership = value;
      session.refreshShellState();
      await tester.pump();
      await tester.pump();
    }

    Future<void> running(WidgetTester tester) async {
      await ownership(tester, 'running');
      expect(terminalFocus.hasFocus, isTrue);
    }

    focusTest('shell ready preserves a settings modal keyboard owner', (
      tester,
    ) async {
      await mount(tester);
      await running(tester);
      final dialogFocus = FocusNode(debugLabel: 'Settings editor');
      final pageContext = tester.element(find.byType(ComposerPane));
      final dialog = showDialog<void>(
        context: pageContext,
        builder: (_) => AlertDialog(
          title: const Text('Settings'),
          content: TextField(focusNode: dialogFocus),
        ),
      );
      await tester.pumpAndSettle();
      dialogFocus.requestFocus();
      await tester.pump();
      final originalOwner = FocusManager.instance.primaryFocus;
      await ownership(tester, 'ready');
      expect(FocusManager.instance.primaryFocus, same(originalOwner));
      expect(session.editorFocus.hasFocus, isFalse);
      Navigator.of(pageContext).pop();
      await tester.pumpAndSettle();
      await dialog;
      await tester.pumpWidget(const SizedBox.shrink());
      dialogFocus.dispose();
    });

    focusTest('shell ready in an inactive window does not restore editing', (
      tester,
    ) async {
      await mount(tester);
      await running(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final originalOwner = FocusManager.instance.primaryFocus;
      await ownership(tester, 'ready');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(originalOwner));
      expect(session.editorFocus.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    focusTest('shell ready preserves a different editor in the same route', (
      tester,
    ) async {
      await mount(tester);
      await running(tester);
      otherFocus.requestFocus();
      await tester.pump();
      await ownership(tester, 'ready');
      expect(otherFocus.hasFocus, isTrue);
      expect(session.editorFocus.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    focusTest(
      'same-pane terminal returns to its composer when shell is ready',
      (tester) async {
        await mount(tester);
        await running(tester);
        await ownership(tester, 'ready');
        expect(session.editorFocus.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
