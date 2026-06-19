import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentDetectionPolicy', () {
    test('disabled policy keeps text on the shell route', () {
      const router = AgentIntentRouter(policy: AgentDetectionPolicy.disabled());

      final decision = router.routeText('why did tests fail');

      expect(decision.kind, InputIntentKind.shellCommand);
      expect(decision.route, InputIntentRoute.shell);
      expect(decision.reason, 'auto-detection-disabled');
      expect(decision.requiresUserChoice, isFalse);
    });

    test('direct route threshold can require a visible choice', () {
      const router = AgentIntentRouter(
        policy: AgentDetectionPolicy(directRouteThreshold: 0.95),
      );

      final decision = router.routeText('why did tests fail');

      expect(decision.kind, InputIntentKind.ambiguous);
      expect(decision.reason, 'below-direct-route-threshold');
      expect(decision.requiresUserChoice, isTrue);
      expect(decision.confidence, 0.88);
    });

    test('ambiguous behavior can prefer shell without changing input text', () {
      const router = AgentIntentRouter(
        policy: AgentDetectionPolicy(
          ambiguousInputBehavior: AgentAmbiguousInputBehavior.preferShell,
        ),
      );

      final decision = router.routeText('show files modified today');

      expect(decision.kind, InputIntentKind.shellCommand);
      expect(decision.route, InputIntentRoute.shell);
      expect(decision.normalizedInput, 'show files modified today');
      expect(decision.alternatives, hasLength(2));
      expect(decision.requiresUserChoice, isFalse);
    });

    test('copyWith updates prefixes and thresholds', () {
      const policy = AgentDetectionPolicy();

      final updated = policy.copyWith(
        shellPrefix: '%',
        agentPrefix: '~',
        directRouteThreshold: 0.9,
        enabled: false,
      );

      expect(updated.shellPrefix, '%');
      expect(updated.agentPrefix, '~');
      expect(updated.actionPrefix, '/');
      expect(updated.directRouteThreshold, 0.9);
      expect(updated.enabled, isFalse);
    });
  });
}
