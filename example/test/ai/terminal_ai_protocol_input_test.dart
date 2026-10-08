import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_runtime.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../support/fake_pty_backend.dart';
import 'terminal_ai_test.dart' show FakeApi, MemoryAiStore, commandReply;

class _Backend extends FakePtyBackend {
  @override
  String? requestSessionJson(String id, String requestJson) {
    final request = jsonDecode(requestJson) as Map;
    return switch (request['kind']) {
      'composer.state' => jsonEncode({
        'state': 'ready',
        'lease': 'lease',
        'contextId': 'root',
        'cwd': '/tmp',
      }),
      'terminal.live_screen' => jsonEncode({'text': 'shell> '}),
      'terminal.command_blocks' => jsonEncode({'blocks': <Object?>[]}),
      _ => super.requestSessionJson(id, requestJson),
    };
  }
}

void main() {
  for (final whileThinking in [false, true]) {
    testWidgets(
      'automatic protocol input preserves AI '
      '${whileThinking ? 'inference' : 'approval'} and manual input revokes it',
      (tester) async {
        final backend = _Backend();
        final runtime = TerminalRuntimeController(
          backend: backend,
          copyToClipboard: (_) async {},
          readClipboard: () async => '',
          enableSessionPolling: false,
        );
        final session = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        await tester.pump();
        runtime.viewportFor(session).updateMeasuredCellSize(const Size(8, 16));
        runtime.resizeSession(session, const Size(640, 384), 1);
        await tester.pump();
        final settings = AiSettingsController(MemoryAiStore());
        await settings.loaded;
        final terminal = TerminalAiRuntime(
          sessionId: session,
          runtime: runtime,
          readPane: () => TerminalPane(
            sessionId: session,
            title: 'Shell',
            profileId: 'fixture',
          ),
          isReadOnly: () => false,
        );
        final answer = Completer<AiReply>();
        final api = FakeApi();
        if (whileThinking) api.respond = (_) => answer.future;
        final ai = TerminalAiController(
          settings: settings,
          terminal: terminal,
          api: api,
        );
        addTearDown(() {
          ai.dispose();
          settings.dispose();
          runtime.dispose();
        });
        final ask = ai.ask('List files');
        await tester.pump();
        expect(
          ai.phase,
          whileThinking ? AiPhase.thinking : AiPhase.awaitingApproval,
        );
        final guard = (await terminal.readContext()).guard;
        backend.writes.clear();

        backend.enqueueEvent(
          session,
          PtyEvent(kind: 'cell_size_report_request', sessionId: session),
        );
        runtime.refreshSession(session);
        await tester.pump();
        expect(
          backend.writes.map(utf8.decode),
          contains('\x1b]1337;ReportCellSize=16.00;8.00;1.00\x1b\\'),
        );
        final input = TerminalInputController(
          sessionId: session,
          runtime: runtime,
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => '',
        );
        input.sendFocusReport(
          focused: false,
          modes: const TerminalFrameModes(focusTracking: true),
        );
        runtime.sendInput(session, Uint8List(0));
        await tester.pump();
        expect(backend.writes.map(utf8.decode), contains('\x1b[O'));
        expect((await terminal.readContext()).guard, guard);
        expect(api.cancellations.single.isCancelled, isFalse);
        expect(
          ai.phase,
          whileThinking ? AiPhase.thinking : AiPhase.awaitingApproval,
        );
        if (whileThinking) answer.complete(commandReply('ls -la'));
        await ask;
        expect(ai.canApprove, isTrue);

        // The same bytes from an actual input action must still revoke a
        // proposal. Classification uses provenance, never byte heuristics.
        runtime.sendInput(session, Uint8List.fromList(ascii.encode('\x1b[O')));
        await tester.pump();
        expect(ai.canApprove, isFalse);
        expect(ai.takenOver, isTrue);
        expect((await terminal.readContext()).guard, isNot(guard));
      },
    );
  }
}
