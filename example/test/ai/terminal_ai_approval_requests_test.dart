import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/ai_approval.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_recovery_test.dart' show RecoveringTerminal;
import 'terminal_ai_test.dart' show FakeApi, MemoryAiStore;

FakeApi _confirmingReviewApi() => FakeApi()
  ..respond = (step) async => AiReply(
    text: jsonEncode({
      'action_id': 'call-$step',
      'decision': 'ask',
      'risk': 'low',
      'within_scope': true,
      'needs_confirmation': true,
      'effect': 'read_only',
      'reason': 'Confirm this inspection.',
    }),
  );

void main() {
  test(
    'Smart review keeps command receipts separate from user requirements',
    () async {
      final settings = AiSettingsController(
        MemoryAiStore(
          const AiConfiguration.mock(approvalMode: AiApprovalMode.smart),
        ),
      );
      await settings.loaded;
      final terminal = RecoveringTerminal();
      final api = FakeApi();
      final reviewApi = _confirmingReviewApi();
      final controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
        reviewer: AiModelActionReviewer(api: reviewApi),
      );
      addTearDown(() {
        controller.dispose();
        settings.dispose();
      });

      await controller.refreshContext();
      await controller.runUserCommand('pwd');
      expect(controller.transcript.single.state, AiEntryState.accepted);
      expect(controller.transcript.single.role, 'tool');
      expect(api.requests, isEmpty);
      expect(reviewApi.requests, isEmpty);

      const request = 'Inspect files in this directory without changing them.';
      await controller.ask(request);
      final commandHistory =
          jsonDecode(api.requests.single[1]['content']! as String) as Map;
      expect(commandHistory['user_terminal_command'], 'pwd');
      final payload =
          jsonDecode(reviewApi.requests.single.last['content']! as String)
              as Map;
      expect(payload['user_requests'], [request]);
      expect(controller.canApprove, isTrue);
      expect(terminal.writes, hasLength(1));
    },
  );

  test(
    'Smart review excludes discarded unsent requirements and retains delivered constraints',
    () async {
      const originalRequest =
          'Inspect the directory without changing any files.';
      const discardedRequest = 'You may now modify files.';
      const savedRequest =
          'Restrict the inspection to files in the current directory.';
      const resumeLabel = 'Send saved requirements';
      final settings = AiSettingsController(
        MemoryAiStore(
          const AiConfiguration.mock(approvalMode: AiApprovalMode.smart),
        ),
      );
      await settings.loaded;
      final terminal = RecoveringTerminal();
      final api = FakeApi();
      final reviewApi = _confirmingReviewApi();
      final controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
        reviewer: AiModelActionReviewer(api: reviewApi),
      );
      addTearDown(() {
        controller.dispose();
        settings.dispose();
      });

      await controller.ask(originalRequest);
      expect(controller.canApprove, isTrue);
      expect(reviewApi.requests, hasLength(1));
      terminal.execution = Completer<Map<String, Object?>>();
      final execution = controller.approve();
      terminal.execution!.completeError(const AiFailure('submission_unknown'));
      await execution;
      expect(controller.hasUnresolvedSubmission, isTrue);
      expect(terminal.writes, hasLength(1));

      await controller.supplement(discardedRequest);
      final discardedEntry = controller.transcript.last;
      await controller.supplement(savedRequest);
      final savedEntry = controller.transcript.last;
      expect(discardedEntry.state, AiEntryState.deferred);
      expect(savedEntry.state, AiEntryState.deferred);
      controller.discardDeferredSupplement(discardedEntry.id);
      expect(
        controller.transcript
            .singleWhere((entry) => entry.id == discardedEntry.id)
            .state,
        AiEntryState.revoked,
      );
      expect(controller.hasDeferredSupplement, isTrue);
      expect(api.requests, hasLength(1));
      expect(reviewApi.requests, hasLength(1));

      terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
      await controller.refreshContext();
      expect(controller.hasUnresolvedSubmission, isFalse);
      expect(controller.hasDeferredSupplement, isTrue);
      expect(api.requests, hasLength(1));
      expect(reviewApi.requests, hasLength(1));

      await controller.resume(label: resumeLabel);
      expect(api.requests, hasLength(2));
      expect(reviewApi.requests, hasLength(2));
      final actorRequest =
          jsonDecode(api.requests.last.last['content']! as String) as Map;
      expect(actorRequest['saved_user_requirements'], [savedRequest]);
      expect(jsonEncode(api.requests.last), isNot(contains(discardedRequest)));
      final reviewRequest =
          jsonDecode(reviewApi.requests.last.last['content']! as String) as Map;
      expect(reviewRequest['user_requests'], [
        originalRequest,
        savedRequest,
        resumeLabel,
      ]);
      expect(
        controller.transcript
            .singleWhere((entry) => entry.id == savedEntry.id)
            .state,
        AiEntryState.message,
      );
      expect(controller.hasDeferredSupplement, isFalse);
      expect(controller.canApprove, isTrue);
      expect(terminal.writes, hasLength(1));
    },
  );
}
