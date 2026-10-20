import 'dart:async';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_runtime.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'terminal_ai_test.dart' show FakeApi, MemoryAiStore;

class _Runtime extends Fake implements TerminalRuntimeController {
  final submissions = <String>[];
  @override
  Stream<TerminalSessionInputEvent> get inputEvents => const Stream.empty();
  @override
  bool hasSession(String sessionId) => true;
  @override
  bool isZmodemTransferActive(String sessionId) => false;
  @override
  Map<String, Object?>? liveScreen(String sessionId) => {'text': 'fixture>'};
  @override
  Map<String, Object?>? composerRequest(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) {
    if (operation == 'composer.submit') {
      submissions.add(payload['submissionId']! as String);
      return {'outcome': 'accepted'};
    }
    return {
      'contextId': 'root',
      'cwd': '/fixture',
      'state': 'ready',
      'lease': 'lease',
    };
  }

  @override
  Map<String, Object?>? commandBlocks(
    String sessionId, [
    Map<String, Object?> payload = const {},
  ]) => {'blocks': <Object?>[]};
}

class _DelayedTerminal extends TerminalAiRuntime {
  _DelayedTerminal(_Runtime runtime)
    : super(
        sessionId: 'one',
        runtime: runtime,
        readPane: () => const TerminalPane(
          sessionId: 'one',
          title: 'Fixture',
          profileId: 'fixture',
        ),
        isReadOnly: () => false,
      );
  int reads = 0;
  int? delayAt;
  final delayed = Completer<void>();

  @override
  Future<AiTerminalContext> readContext() async {
    if (++reads == delayAt) await delayed.future;
    return super.readContext();
  }
}

void main() {
  for (final readOffset in [1, 2]) {
    test(
      'pane changes during approval read $readOffset preserve an unsubmitted proposal',
      () async {
        final runtime = _Runtime();
        final terminal = _DelayedTerminal(runtime);
        final settings = AiSettingsController(MemoryAiStore());
        await settings.loaded;
        final api = FakeApi();
        final controller = TerminalAiController(
          settings: settings,
          terminal: terminal,
          api: api,
        );
        addTearDown(controller.dispose);
        addTearDown(settings.dispose);
        await controller.ask('Inspect fixture');
        final revision = controller.proposalRevision;
        terminal.delayAt = terminal.reads + readOffset;
        var active = true;
        final approval = controller.approve(
          revision: revision,
          canSubmit: () => active,
        );
        for (
          var attempt = 0;
          attempt < 10 && terminal.reads < terminal.delayAt!;
          attempt++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(terminal.reads, terminal.delayAt);
        active = false;
        terminal.delayed.complete();
        await approval;
        expect(runtime.submissions, isEmpty);
        expect(controller.hasUnresolvedSubmission, isFalse);
        expect(controller.phase, AiPhase.awaitingApproval);
        expect(controller.proposalRevision, revision);
        expect(controller.canApprove, isTrue);
        expect(api.requests, hasLength(1));
      },
    );
  }
}
