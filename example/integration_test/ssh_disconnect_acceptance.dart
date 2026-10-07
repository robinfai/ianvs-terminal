import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'composer_acceptance_test.dart' show until;

/// Deterministic model transport; SSH and terminal IO remain native.
class SshDisconnectFixture implements AiConfigurationStore {
  late final HttpServer server;
  late final AiSettingsController settings;
  AiConfiguration? configuration;
  String? nextCommand;
  int requests = 0;

  static Future<SshDisconnectFixture> start() async {
    final fixture = SshDisconnectFixture();
    fixture.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fixture.configuration = AiConfiguration(
      endpoint: 'http://127.0.0.1:${fixture.server.port}/v1',
      apiKey: 'isolated-test-fixture',
      model: 'fixture',
    );
    fixture.settings = AiSettingsController(fixture);
    await fixture.settings.loaded;
    fixture.server.listen((request) async {
      await request.drain<void>();
      fixture.requests++;
      final command = fixture.nextCommand;
      fixture.nextCommand = null;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': command == null
                    ? 'The original submission was received. Inspect its block for the exit status.'
                    : 'Review this command on the current SSH target.',
                if (command != null)
                  'tool_calls': [
                    {
                      'id': 'ssh-proposal-${fixture.requests}',
                      'type': 'function',
                      'function': {
                        'name': 'run_command',
                        'arguments': jsonEncode({
                          'command': command,
                          'reason':
                              'Verify one execution on the disposable SSH target',
                        }),
                      },
                    },
                  ],
              },
            },
          ],
        }),
      );
      await request.response.close();
    });
    return fixture;
  }

  @override
  Future<AiConfiguration?> read() async => configuration;
  @override
  Future<void> write(AiConfiguration? value) async => configuration = value;
  Future<void> close() async {
    settings.dispose();
    await server.close(force: true);
  }

  Future<void> verify(
    WidgetTester tester, {
    required ProviderContainer container,
    required String sessionId,
    required String home,
    required String disconnectPath,
    required Future<void> Function(String) capture,
  }) async {
    Future<void> click(Key key) async {
      await tester.pump();
      final finder = find.byKey(key);
      await until(tester, () => finder.evaluate().isNotEmpty);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 150));
    }

    Future<void> relay(String action) async {
      final marker = File(disconnectPath);
      final done = File(
        disconnectPath.replaceFirst(RegExp(r'\.[^.]+$'), '.done'),
      );
      if (await done.exists()) await done.delete();
      final staged = File('$disconnectPath.staged');
      await staged.writeAsString(action, flush: true);
      await staged.rename(marker.path);
      await until(tester, done.existsSync);
      expect((await done.readAsString()).trim(), action);
    }

    await click(Key('terminal-ai-open-$sessionId'));
    final ai = tester
        .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
        .controller;
    await until(tester, () => ai.context != null);
    final taskId = ai.taskId;
    final runtime = container.read(terminalRuntimeControllerProvider);
    Future<void> propose(String command) async {
      nextCommand = command;
      await click(const Key('ai-prompt'));
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Check this SSH target once',
      );
      await tester.pump();
      expect(ai.draft, 'Check this SSH target once');
      await click(const Key('ai-send'));
      await until(tester, () => !ai.busy);
      await capture('D10-proposal-diagnostic');
      expect(
        ai.error,
        isNull,
        reason: 'HTTP requests: $requests; terminal: ${ai.terminalError}',
      );
      expect(
        ai.canApprove,
        true,
        reason:
            'phase=${ai.phase}, pending=${ai.pending}, context=${ai.context?.guard}, transcript=${ai.transcript.map((e) => e.text).toList()}',
      );
      await click(const Key('ai-show-latest'));
    }

    final proof = File('$home/disconnect-proof.txt');
    await propose(r"printf x >> disconnect-proof.txt; printf 'SSH_ONCE\n'");
    await click(const Key('ai-approve'));
    await until(tester, () => !ai.busy);
    await until(
      tester,
      () =>
          runtime.composerRequest(
            sessionId,
            'composer.state',
            const {},
          )?['state'] ==
          'ready',
    );
    await ai.refreshContext();
    expect(ai.error, isNull);
    expect(await proof.readAsString(), 'x');
    final original = ai.transcript.singleWhere(
      (e) => e.state == AiEntryState.accepted,
    );
    expect(original.blockId, isNotNull);
    expect(original.submissionId, isNotNull);
    final source = ai.context!.lastBlock!;
    expect(source.id, original.blockId);
    expect(source.exitCode, 0);
    expect(
      source.command,
      r"printf x >> disconnect-proof.txt; printf 'SSH_ONCE\n'",
    );
    await propose(r"printf 'MUST_NOT_RUN\n'");
    final pendingId = ai.transcript.last.id;
    await click(const Key('ai-prompt'));
    await tester.enterText(
      find.byKey(const Key('ai-prompt')),
      'Preserve the original evidence before reconnecting',
    );
    await tester.pump();
    expect(ai.draft, 'Preserve the original evidence before reconnecting');
    ai.attachContext(source);
    final requestCount = requests;
    final blocksBefore = runtime.commandBlocks(sessionId)!['blocks']! as List;
    await capture('D10-before-transport-loss');

    // Only the relay created by composer.py observes this marker.
    await relay('disconnect');
    await until(
      tester,
      () =>
          container
              .read(sessionControllerProvider)
              .tabs
              .firstOrNull
              ?.activePane
              .isExited ==
          true,
      diagnostics: () =>
          'native retained=${runtime.isSessionRetainedAfterExit(sessionId)}; ${container.read(sessionControllerProvider).lastError}',
    );
    await until(tester, () => ai.terminalError == 'session_unavailable');
    expect(runtime.isSessionRetainedAfterExit(sessionId), true);
    expect(
      container.read(sessionControllerProvider).tabs.single.activePane.exitCode,
      255,
    );
    expect(await File(disconnectPath).exists(), false);
    expect(ai.canApprove, false);
    expect(ai.canResume, false);
    expect(
      ai.transcript.singleWhere((e) => e.id == pendingId).state,
      AiEntryState.revoked,
    );
    expect(ai.taskId, taskId);
    expect(ai.draft, 'Preserve the original evidence before reconnecting');
    expect(ai.attachments, [source]);
    expect(
      tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller,
      same(ai),
    );
    await ai.approve();
    await ai.resume();
    final receipt = runtime.composerRequest(sessionId, 'composer.receipt', {
      'submissionId': original.submissionId,
    });
    expect(receipt?['outcome'], 'accepted');
    expect(receipt?['blockId'], original.blockId);
    final retained = runtime.commandBlocks(sessionId)!['blocks']! as List;
    expect(
      retained.map((b) => (b as Map)['id']),
      blocksBefore.map((b) => (b as Map)['id']),
    );
    expect(await proof.readAsString(), 'x');
    expect(requests, requestCount);
    expect(
      find.descendant(
        of: find.byType(TerminalAiWorkspace),
        matching: find.byType(TerminalCommandBlocksView),
      ),
      findsOneWidget,
    );
    await capture('D10-retained-task-after-disconnect');
    await click(const Key('ai-close'));
    expect(
      tester.widget<TerminalViewport>(find.byType(TerminalViewport)).readOnly,
      true,
    );
    await capture('D10-readonly-terminal-after-disconnect');
    await click(Key('terminal-ai-open-$sessionId'));
    expect(ai.taskId, taskId);
    expect(ai.draft, 'Preserve the original evidence before reconnecting');
    expect(ai.attachments, [source]);
    expect(tester.takeException(), isNull);
    await click(const Key('ai-reconnect-terminal'));
    await until(
      tester,
      () =>
          container.read(sessionControllerProvider).activeSessionId !=
          sessionId,
    );
    final newSession = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    await until(
      tester,
      () =>
          runtime.composerRequest(
            newSession,
            'composer.state',
            const {},
          )?['state'] ==
          'ready',
    );
    await ai.refreshContext();
    await tester.pump();
    expect(
      tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller,
      same(ai),
    );
    expect(ai.taskId, taskId);
    expect(ai.draft, 'Preserve the original evidence before reconnecting');
    expect(ai.attachments, [source]);
    expect(ai.originalTarget!.sessionId, sessionId);
    expect(ai.context!.sessionId, newSession);
    expect(ai.targetChanged, true);
    expect(ai.canApprove, false);
    expect(requests, requestCount);
    expect(await proof.readAsString(), 'x');
    expect(container.read(sessionControllerProvider).tabs, hasLength(2));
    final recoveredState = container.read(sessionControllerProvider);
    expect(recoveredState.lastError, isNull);
    for (final tab in recoveredState.tabs) {
      for (final pane in tab.effectivePanes) {
        expect(pane.runtimeError?.message, isNull);
      }
    }
    expect(runtime.isSessionRetainedAfterExit(sessionId), true);
    final oldReceipt = await (ai.terminal as AiSourceSubmissionInspector)
        .inspectSourceSubmission(original.submissionId!, sessionId);
    expect(oldReceipt['blockId'], original.blockId);
    final timeline = tester.widget<TerminalCommandBlocksView>(
      find.descendant(
        of: find.byType(TerminalAiWorkspace),
        matching: find.byType(TerminalCommandBlocksView),
      ),
    );
    expect(
      await timeline.controller.outputText('$sessionId/${source.id}'),
      contains('SSH_ONCE'),
    );
    await capture('D10-reconnected-target-choice');
    final reconnectedProof = File('$home/reconnect-proof.txt');
    nextCommand =
        r"printf y >> reconnect-proof.txt; printf 'RECONNECTED_ONCE\n'";
    await click(const Key('ai-target-continue'));
    await until(tester, () => ai.canApprove);
    expect(ai.proposalTarget!.sessionId, newSession);
    expect(await reconnectedProof.exists(), false);
    expect(requests, requestCount + 1);
    expect(await proof.readAsString(), 'x');
    await click(const Key('ai-approve'));
    await until(tester, () => !ai.busy);
    await ai.refreshContext();
    await tester.pump();
    expect(await reconnectedProof.readAsString(), 'y');
    expect(await proof.readAsString(), 'x');
    expect(ai.draft, 'Preserve the original evidence before reconnecting');
    expect(ai.attachments, [source]);
    final accepted = ai.transcript
        .where((e) => e.state == AiEntryState.accepted)
        .toList();
    expect(accepted, hasLength(2));
    expect(accepted.first.target!.sessionId, sessionId);
    expect(accepted.last.target!.sessionId, newSession);
    expect(accepted.first.blockId, original.blockId);
    expect(accepted.last.blockId, isNot(original.blockId));
    await capture('D10-reconnected-new-command-approved');

    // A second transport loss followed by a real public-key authentication
    // failure must preserve the same task through a further successful retry.
    // Only composer.py's disposable authorized key file is changed.
    final beforeRetryRequests = requests;
    await relay('disconnect');
    await until(tester, () => runtime.isSessionRetainedAfterExit(newSession));
    await until(tester, () => ai.terminalError == 'session_unavailable');
    final authorizedKey = File('$home/../client.pub');
    final savedKey = await authorizedKey.readAsBytes();
    late final String failedSession;
    try {
      await authorizedKey.writeAsString('', flush: true);
      await click(const Key('ai-reconnect-terminal'));
      await until(
        tester,
        () =>
            container.read(sessionControllerProvider).activeSessionId !=
            newSession,
      );
      failedSession = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await until(
        tester,
        () => runtime.isSessionRetainedAfterExit(failedSession),
      );
      await until(tester, () => ai.terminalError == 'session_unavailable');
      expect(ai.taskId, taskId);
      expect(ai.draft, 'Preserve the original evidence before reconnecting');
      expect(ai.attachments, [source]);
      expect(ai.canApprove, false);
      expect(ai.canResume, false);
      expect(requests, beforeRetryRequests);
      expect(container.read(sessionControllerProvider).lastError, isNotNull);
      expect(find.byKey(const Key('ai-target-continue')), findsNothing);
      await capture('D10-reconnect-authentication-failed');
      await click(const Key('ai-terminal-settings'));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('ssh-host')))
            .controller!
            .text,
        '127.0.0.1',
      );
      await capture('D10-reconnect-ssh-settings');
      await tester.tap(find.byTooltip('取消'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        failedSession,
      );
      expect(ai.taskId, taskId);
      expect(ai.draft, 'Preserve the original evidence before reconnecting');
    } finally {
      await authorizedKey.writeAsBytes(savedKey, flush: true);
    }
    await click(const Key('ai-terminal-settings'));
    final saveProfile = find.byKey(const Key('ssh-save-profile'));
    if (tester.widget<CheckboxListTile>(saveProfile).value == true) {
      await tester.ensureVisible(saveProfile);
      await tester.tap(saveProfile);
      await tester.pump();
    }
    await click(const Key('ssh-connect'));
    await until(
      tester,
      () =>
          container.read(sessionControllerProvider).activeSessionId !=
          failedSession,
    );
    final recoveredSession = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    await until(
      tester,
      () =>
          runtime.composerRequest(
            recoveredSession,
            'composer.state',
            const {},
          )?['state'] ==
          'ready',
    );
    await ai.refreshContext();
    await tester.pump();
    expect(ai.taskId, taskId);
    expect(ai.context!.sessionId, recoveredSession);
    expect(ai.originalTarget!.sessionId, newSession);
    expect(ai.targetChanged, true);
    expect(ai.canApprove, false);
    expect(requests, beforeRetryRequests);
    expect(ai.draft, 'Preserve the original evidence before reconnecting');
    expect(ai.attachments, [source]);
    expect(await proof.readAsString(), 'x');
    expect(await reconnectedProof.readAsString(), 'y');
    expect(container.read(sessionControllerProvider).tabs, hasLength(4));
    expect(container.read(sessionControllerProvider).lastError, isNull);
    for (final entry in accepted) {
      final receipt = await (ai.terminal as AiSourceSubmissionInspector)
          .inspectSourceSubmission(
            entry.submissionId!,
            entry.target!.sessionId,
          );
      expect(receipt['blockId'], entry.blockId);
    }
    expect(
      await timeline.controller.outputText('$sessionId/${original.blockId}'),
      contains('SSH_ONCE'),
    );
    expect(
      await timeline.controller.outputText(
        '$newSession/${accepted.last.blockId}',
      ),
      contains('RECONNECTED_ONCE'),
    );
    await capture('D10-reconnect-after-authentication-recovery');

    // The remote command runs while all server-to-client data is withheld.
    // Its local proof file is independent of the SSH receipt/UI under test.
    final unknownProof = File('$home/unknown-proof.txt');
    nextCommand = r"printf z >> unknown-proof.txt; printf 'UNKNOWN_ONCE\n'";
    await click(const Key('ai-target-continue'));
    await until(tester, () => ai.canApprove);
    expect(ai.proposalTarget!.sessionId, recoveredSession);
    final unknownActionId = ai.pending!.id;
    final beforeUnknownRequests = requests;
    await relay('pause-output');
    await click(const Key('ai-approve'));
    await until(tester, unknownProof.existsSync);
    expect(await unknownProof.readAsString(), 'z');
    final unknownSubmissionId = (ai.terminal as AiSubmissionInspector)
        .submissionFor(unknownActionId);
    expect(unknownSubmissionId, isNotNull);
    final pendingReceipt = runtime.composerRequest(
      recoveredSession,
      'composer.receipt',
      {'submissionId': unknownSubmissionId},
    );
    expect(pendingReceipt?['outcome'], 'pending');
    expect(pendingReceipt?['blockId'], isNull);
    await relay('disconnect');
    await until(
      tester,
      () => runtime.isSessionRetainedAfterExit(recoveredSession),
    );
    await until(tester, () => !ai.busy);
    await until(tester, () => ai.terminalError == 'session_unavailable');
    await ai.refreshContext();
    final unknown = ai.transcript.singleWhere(
      (entry) => entry.state == AiEntryState.unknown,
    );
    expect(unknown.submissionId, unknownSubmissionId);
    expect(unknown.target!.sessionId, recoveredSession);
    expect(unknown.blockId, isNull);
    expect(ai.hasUnresolvedSubmission, true);
    expect(ai.canResume, false);
    expect(
      tester
          .widget<Text>(
            find.byKey(ValueKey('ai-proposal-status-${unknown.id}')),
          )
          .data,
      contains('可能已经执行'),
    );
    expect(requests, beforeUnknownRequests);
    await capture('D10-executed-without-receipt-disconnected');
    await click(const Key('ai-reconnect-terminal'));
    await until(
      tester,
      () =>
          container.read(sessionControllerProvider).activeSessionId !=
          recoveredSession,
    );
    final unknownRecoverySession = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    await until(
      tester,
      () =>
          runtime.composerRequest(
            unknownRecoverySession,
            'composer.state',
            const {},
          )?['state'] ==
          'ready',
    );
    await ai.refreshContext();
    await tester.pump();
    await click(const Key('ai-check-terminal'));
    await ai.approve();
    await ai.resume();
    expect(ai.taskId, taskId);
    expect(ai.context!.sessionId, unknownRecoverySession);
    expect(ai.draft, 'Preserve the original evidence before reconnecting');
    expect(ai.attachments, [source]);
    expect(ai.hasUnresolvedSubmission, true);
    expect(ai.canResume, false);
    expect(ai.canApprove, false);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('ai-send'))).onPressed,
      isNull,
    );
    expect(
      ai.transcript.singleWhere((entry) => entry.id == unknown.id).state,
      AiEntryState.unknown,
    );
    final unknownReceipt = await (ai.terminal as AiSourceSubmissionInspector)
        .inspectSourceSubmission(unknownSubmissionId!, recoveredSession);
    expect(unknownReceipt['outcome'], 'unknown');
    expect(unknownReceipt['blockId'], isNull);
    expect(await unknownProof.readAsString(), 'z');
    expect(await proof.readAsString(), 'x');
    expect(await reconnectedProof.readAsString(), 'y');
    expect(requests, beforeUnknownRequests);
    expect(container.read(sessionControllerProvider).tabs, hasLength(5));
    expect(container.read(sessionControllerProvider).lastError, isNull);
    await capture('D10-unknown-original-receipt-after-reconnect');
    expect(tester.takeException(), isNull);
    const output = String.fromEnvironment('BLOCKS_NATIVE_EVIDENCE_DIR');
    if (output.isNotEmpty) {
      await File('$output/disconnect-result.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'passed': true,
          'scope':
              'Actual loopback SSH transport loss and reconnect; original task and native evidence retained; explicit target choice and new command approval.',
          'session_id': sessionId,
          'reconnected_session_id': newSession,
          'authentication_failed_session_id': failedSession,
          'authentication_recovered_session_id': recoveredSession,
          'unknown_recovery_session_id': unknownRecoverySession,
          'unknown_submission_id': unknownSubmissionId,
          'unknown_submission_source_session_id': recoveredSession,
          'receipt_before_disconnect': pendingReceipt,
          'receipt_after_reconnect': unknownReceipt,
          'execution_proof_after_reconnect': await unknownProof.readAsString(),
          'model_requests_before_fault': beforeUnknownRequests,
          'model_requests_after_reconnect_and_check': requests,
          'remote_execution_proven_before_receipt_loss': true,
          'unknown_receipt_remains_unknown_after_reconnect_and_check': true,
          'unknown_submission_not_replayed_and_model_not_requested': true,
          'task_id': taskId,
          'submission_id': original.submissionId,
          'block_id': original.blockId,
          'native_command_executed_once': true,
          'pending_approval_revoked': true,
          'draft_and_attachment_retained': true,
          'native_timeline_and_receipt_readable': true,
          'terminal_read_only': true,
          'no_model_request_or_resubmission_after_disconnect': true,
          'reconnect_keeps_original_receipt_source': true,
          'explicit_new_target_and_separate_approval': true,
          'repeated_reconnect_preserves_original_receipt_sources': true,
          'ssh_configuration_cancel_preserves_task_and_connect_requires_explicit_action':
              true,
          'real_authentication_failure_preserves_task_and_retry_does_not_replay':
              true,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    }
  }
}
