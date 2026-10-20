import 'dart:convert';

import 'package:app/features/ai/ai_approval.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ai_approval_test.dart' show decision;
import 'terminal_ai_test.dart' show FakeApi, commandReply, contextFor;

void main() {
  const cautious = AiApprovalSensitivity.cautious;
  const balanced = AiApprovalSensitivity.balanced;
  const relaxed = AiApprovalSensitivity.relaxed;

  for (final sample in [
    (risk: 'low', effect: 'read_only', allowed: {cautious, balanced, relaxed}),
    (risk: 'low', effect: 'reversible_write', allowed: {balanced, relaxed}),
    (risk: 'medium', effect: 'read_only', allowed: {relaxed}),
    (risk: 'medium', effect: 'reversible_write', allowed: {relaxed}),
    (risk: 'medium', effect: 'external', allowed: {relaxed}),
    (risk: 'high', effect: 'read_only', allowed: <AiApprovalSensitivity>{}),
    (risk: 'unknown', effect: 'read_only', allowed: <AiApprovalSensitivity>{}),
    (risk: 'low', effect: 'unknown', allowed: <AiApprovalSensitivity>{}),
    (risk: 'low', effect: 'destructive', allowed: <AiApprovalSensitivity>{}),
  ]) {
    for (final sensitivity in AiApprovalSensitivity.values) {
      test('$sensitivity enforces ${sample.risk} / ${sample.effect}', () async {
        final api = FakeApi()
          ..respond = (_) async => AiReply(
            text: decision(risk: sample.risk, effect: sample.effect),
          );
        final result = await AiModelActionReviewer(api: api).review(
          configuration: AiConfiguration.mock(approvalSensitivity: sensitivity),
          action: commandReply('fixture-operation').action!,
          target: contextFor(),
          userRequests: ['Perform the scoped task.'],
          cancellation: AiCancellation(),
        );
        expect(result.automatic, sample.allowed.contains(sensitivity));
        if (!result.automatic) expect(result.source, 'threshold');
        expect(
          api.requests.single.first['content'],
          contains('Selected sensitivity: ${sensitivity.name}'),
        );
      });
    }
  }

  test(
    'relaxed routes scoped cleanup through review, never a prefix grant',
    () async {
      final api = FakeApi();
      Future<AiApprovalReview> cleanup() =>
          AiModelActionReviewer(api: api).review(
            configuration: const AiConfiguration.mock(
              approvalSensitivity: relaxed,
            ),
            action: commandReply('rm ./generated-fixture').action!,
            target: contextFor(),
            userRequests: [
              'Remove the generated fixture; its source is retained.',
            ],
            cancellation: AiCancellation(),
          );
      api.respond = (_) async => AiReply(
        text: decision(risk: 'medium', effect: 'reversible_write'),
      );
      expect((await cleanup()).automatic, true);
      api.respond = (_) async => AiReply(
        text: decision(risk: 'high', effect: 'destructive'),
      );
      expect((await cleanup()).automatic, false);
      expect(api.requests, hasLength(2));
    },
  );

  for (final response in [
    decision(scope: false),
    decision(confirmation: true),
    decision(id: 'old-action'),
    decision(risk: 'invalid'),
    decision(effect: 'invalid'),
    jsonEncode({...jsonDecode(decision()) as Map, 'decision': 'ask'}),
  ]) {
    test(
      'relaxed cannot bypass authorization or invalid review: $response',
      () async {
        final api = FakeApi()..respond = (_) async => AiReply(text: response);
        final result = await AiModelActionReviewer(api: api).review(
          configuration: const AiConfiguration.mock(
            approvalSensitivity: relaxed,
          ),
          action: commandReply('ls').action!,
          target: contextFor(),
          userRequests: ['Inspect this directory.'],
          cancellation: AiCancellation(),
        );
        expect(result.automatic, false);
      },
    );
  }

  test('sensitivity persists for API and ACP; legacy keeps its threshold', () {
    for (final sensitivity in AiApprovalSensitivity.values) {
      for (final config in [
        AiConfiguration.mock(
          approvalMode: AiApprovalMode.smart,
          approvalSensitivity: sensitivity,
        ),
        AiConfiguration.acp(
          agentCommand: '/fixture',
          approvalMode: AiApprovalMode.smart,
          approvalSensitivity: sensitivity,
        ),
      ]) {
        expect(
          AiConfiguration.fromJson(config.toJson()).hasSameValues(config),
          true,
        );
      }
    }
    const smart = AiConfiguration.mock(approvalMode: AiApprovalMode.smart);
    for (final unknown in [null, 'allow_all', 1]) {
      final config = AiConfiguration.fromJson({
        ...smart.toJson(),
        'approvalSensitivity': unknown,
      });
      expect(config.approvalSensitivity, balanced);
    }
    const wide = AiConfiguration.mock(
      approvalMode: AiApprovalMode.smart,
      approvalSensitivity: relaxed,
    );
    expect(smart.hasSameValues(wide), false);
    expect(smart.hasSameValues(wide, includeApprovalPolicy: false), true);
  });
}
