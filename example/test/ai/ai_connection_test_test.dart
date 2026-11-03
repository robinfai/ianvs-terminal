import 'dart:async';
import 'package:app/features/ai/ai_connection_test.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

const config = AiConfiguration.acp(
  agentCommand: '/secret/path',
  agentArguments: ['private'],
  model: 'test-model',
);
void main() {
  testWidgets('deadline cancels hung request and ignores late success', (
    tester,
  ) async {
    final pending = Completer<void>();
    late AiCancellation token;
    final c = AiConnectionTestController(
      runner: (_, cancellation, stage) {
        token = cancellation;
        stage(AiConnectionStage.handshake);
        return pending.future;
      },
    );
    addTearDown(c.dispose);
    c.start(config);
    await tester.pump(const Duration(seconds: 59));
    expect(c.running, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(c.status, AiConnectionTestStatus.timedOut);
    expect(token.isCancelled, isTrue);
    pending.complete();
    await tester.pump();
    expect(c.status, AiConnectionTestStatus.timedOut);
  });
  testWidgets(
    'cancel retry isolates old progress and failure; success persists',
    (tester) async {
      final pending = <Completer<void>>[];
      final progress = <void Function(AiConnectionStage)>[];
      final tokens = <AiCancellation>[];
      final c = AiConnectionTestController(
        runner: (_, token, stage) {
          tokens.add(token);
          progress.add(stage);
          final result = Completer<void>();
          pending.add(result);
          return result.future;
        },
      );
      addTearDown(c.dispose);
      c.start(config);
      c.cancel();
      expect(tokens.first.isCancelled, isTrue);
      expect(c.status, AiConnectionTestStatus.cancelled);
      c.start(config);
      progress.first(AiConnectionStage.reply);
      pending.first.completeError(const AiFailure('acp_authentication'));
      await tester.pump();
      expect(c.stage, AiConnectionStage.launch);
      expect(c.running, isTrue);
      for (final stage in c.stages.skip(1)) {
        progress.last(stage);
      }
      pending.last.complete();
      await tester.pump();
      expect(c.status, AiConnectionTestStatus.success);
      expect(c.completed.length, 5);
      await tester.pump(const Duration(minutes: 2));
      expect(c.status, AiConnectionTestStatus.success);
      c.invalidate();
      expect(c.stale, isTrue);
    },
  );
  testWidgets(
    'dispose cancels and diagnostics exclude arbitrary remote error',
    (tester) async {
      late AiCancellation token;
      final pending = Completer<void>();
      final c = AiConnectionTestController(
        runner: (_, cancellation, _) {
          token = cancellation;
          return pending.future;
        },
      );
      c.start(config);
      c.dispose();
      expect(token.isCancelled, isTrue);
      pending.complete();
      await tester.pump();
      final failed = AiConnectionTestController(
        runner: (_, _, _) async {
          throw const AiFailure('secret-key and remote output');
        },
      );
      addTearDown(failed.dispose);
      failed.start(config);
      await tester.pump();
      expect(failed.status, AiConnectionTestStatus.failed);
      expect(failed.diagnostics(), isNot(contains('secret')));
      expect(failed.diagnostics(), isNot(contains('private')));
      expect(failed.diagnostics(), contains('error: connection'));
    },
  );
  testWidgets('API only reports observable request', (tester) async {
    final c = AiConnectionTestController(
      runner: (_, _, stage) async {
        stage(AiConnectionStage.request);
      },
    );
    addTearDown(c.dispose);
    c.start(const AiConfiguration.mock());
    await tester.pump();
    expect(c.stages, [AiConnectionStage.request]);
    expect(c.status, AiConnectionTestStatus.success);
  });
}
