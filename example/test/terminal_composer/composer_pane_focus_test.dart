import 'dart:async';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/terminal_composer/composer_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';

class _Runtime extends Fake implements TerminalRuntimeController {
  String ownership = 'ready';
  String? submissionId;
  String outcome = 'pending';

  @override
  Map<String, Object?>? composerRequest(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) {
    if (operation == 'composer.submit') {
      submissionId = payload['submissionId']! as String;
      ownership = 'submitting';
      return {'outcome': 'pending'};
    }
    return operation == 'composer.state'
        ? {
            'state': ownership,
            'lease': ownership == 'ready' ? 'ready-lease' : null,
            'transport': 'shell',
            'contextId': 'root',
            'cwd': '/tmp',
            'dialect': 'zsh',
            'commandNames': ['printf'],
            if (submissionId != null) 'submissionId': submissionId,
            if (submissionId != null) 'outcome': outcome,
          }
        : null;
  }

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
    late ValueNotifier<bool> paneActive;
    late ValueNotifier<bool> terminalMounted;

    setUp(() {
      runtime = _Runtime();
      terminalFocus = FocusNode(debugLabel: 'Test live terminal');
      otherFocus = FocusNode(debugLabel: 'Another input owner');
      paneActive = ValueNotifier(true);
      terminalMounted = ValueNotifier(true);
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
          paneActive.dispose();
          terminalMounted.dispose();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
        }
      });
    }

    Future<void> mount(
      WidgetTester tester, {
      bool terminalAttached = true,
    }) async {
      terminalMounted.value = terminalAttached;
      await tester.pumpApp(
        Column(
          children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: terminalMounted,
                builder: (context, attached, child) => attached
                    ? Focus(
                        focusNode: terminalFocus,
                        child: const SizedBox.expand(),
                      )
                    : const SizedBox.expand(),
              ),
            ),
            TextField(focusNode: otherFocus),
            ValueListenableBuilder<bool>(
              valueListenable: paneActive,
              builder: (context, active, child) => ComposerPane(
                session: session,
                targetLabel: 'Local shell',
                onTerminalFocus: terminalFocus.requestFocus,
                terminalFocus: terminalFocus,
                active: active,
                available: true,
              ),
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

    for (final destination in [
      'editor',
      'another input',
      'released input',
      'another pane',
      'modal',
      'inactive window',
      'revoked visibility',
    ]) {
      focusTest('pending submission with no mounted live block '
          'respects $destination after disabling the field', (tester) async {
        await mount(tester, terminalAttached: false);
        final editor = find.byKey(const Key('composer-editor'));
        await tester.enterText(editor, 'printf first');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(session.controller.ownership, ComposerOwnership.submitting);
        await tester.pump();
        expect(tester.widget<TextField>(editor).enabled, isFalse);
        expect(session.editorFocus.hasFocus, isFalse);
        expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());

        switch (destination) {
          case 'another pane':
            paneActive.value = false;
            otherFocus.requestFocus();
            await tester.pump();
          case 'another input' || 'released input':
            otherFocus.requestFocus();
            await tester.pump();
            expect(otherFocus.hasFocus, isTrue);
            if (destination == 'released input') {
              otherFocus.unfocus();
              await tester.pump();
              expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
            }
          case 'modal':
            unawaited(
              showDialog<void>(
                context: tester.element(find.byType(ComposerPane)),
                builder: (_) =>
                    const AlertDialog(content: TextField(autofocus: true)),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          case 'inactive window':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await tester.pump();
          case 'revoked visibility':
            // Shell AI/Reader revoke synchronously, before active is rebuilt.
            // A quick reopen must not revive the previous return permission.
            session
              ..setVisible(false, deferNotification: true)
              ..setVisible(true);
          case 'editor':
            break;
        }
        final previousOwner = FocusManager.instance.primaryFocus;
        runtime
          ..ownership = 'running'
          ..outcome = 'accepted';
        await tester.pump(const Duration(milliseconds: 30));
        expect(session.controller.ownership, ComposerOwnership.running);
        await ownership(tester, 'ready');
        expect(tester.widget<TextField>(editor).enabled, isTrue);
        expect(session.controller.editor.text, isEmpty);
        expect(session.editorFocus.hasFocus, destination == 'editor');
        if (destination == 'editor') {
          await tester.enterText(editor, 'printf next');
          await tester.pump(const Duration(milliseconds: 150));
          expect(session.controller.editor.text, 'printf next');
        } else {
          expect(FocusManager.instance.primaryFocus, same(previousOwner));
        }
      });
    }

    for (final wasMounted in [false, true]) {
      focusTest('delayed live block ${wasMounted ? 'remount' : 'mount'} '
          'cannot steal a newer input owner', (tester) async {
        await mount(tester, terminalAttached: wasMounted);
        terminalMounted.value = false;
        await tester.pump();
        expect(terminalFocus.parent, isNull);
        final editor = find.byKey(const Key('composer-editor'));
        await tester.enterText(editor, 'printf first');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        runtime
          ..ownership = 'running'
          ..outcome = 'accepted';
        await tester.pump(const Duration(milliseconds: 30));
        await tester.pump();
        expect(session.controller.ownership, ComposerOwnership.running);

        otherFocus.requestFocus();
        await tester.pump();
        expect(otherFocus.hasFocus, isTrue);
        terminalMounted.value = true;
        await tester.pump();
        expect(terminalFocus.parent, isNotNull);
        expect(otherFocus.hasFocus, isTrue);
        expect(terminalFocus.hasFocus, isFalse);
        await ownership(tester, 'ready');
        expect(otherFocus.hasFocus, isTrue);
        expect(session.editorFocus.hasFocus, isFalse);
      });
    }

    for (final readyFirst in [false, true]) {
      for (final newOwner in [false, true]) {
        focusTest(
          'completed live block unmount ${readyFirst ? 'after' : 'before'} ready '
          '${newOwner ? 'preserves a newer owner' : 'restores its editor'}',
          (tester) async {
            await mount(tester);
            await running(tester);
            if (readyFirst) {
              runtime.ownership = 'ready';
              session.refreshShellState();
            }
            if (newOwner) otherFocus.requestFocus();
            terminalMounted.value = false;
            await tester.pump();
            expect(terminalFocus.parent, isNull);
            if (!readyFirst) await ownership(tester, 'ready');
            await tester.pump();
            expect(session.editorFocus.hasFocus, !newOwner);
            expect(otherFocus.hasFocus, newOwner);
          },
        );
      }
    }

    focusTest('explicit unfocus of an attached live terminal stays unfocused', (
      tester,
    ) async {
      await mount(tester);
      await running(tester);
      terminalFocus.unfocus();
      await tester.pump();
      expect(terminalFocus.parent, isNotNull);
      expect(terminalFocus.canRequestFocus, isTrue);
      final owner = FocusManager.instance.primaryFocus;
      await ownership(tester, 'ready');
      expect(FocusManager.instance.primaryFocus, same(owner));
      expect(session.editorFocus.hasFocus, isFalse);
    });
  });
}
