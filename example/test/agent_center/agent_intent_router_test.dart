import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentIntentRouter', () {
    test('routes known shell commands to shell', () {
      const router = AgentIntentRouter();

      final decision = router.routeText('git status');

      expect(decision.kind, InputIntentKind.shellCommand);
      expect(decision.route, InputIntentRoute.shell);
      expect(decision.confidence, greaterThanOrEqualTo(0.85));
      expect(decision.requiresUserChoice, isFalse);
    });

    test('honors shell prefix', () {
      const router = AgentIntentRouter();

      final decision = router.routeText('! git status');

      expect(decision.kind, InputIntentKind.shellCommand);
      expect(decision.route, InputIntentRoute.shell);
      expect(decision.confidence, 1);
      expect(decision.reason, 'forced-shell-prefix');
      expect(decision.normalizedInput, 'git status');
    });

    test('honors Agent prefix', () {
      const router = AgentIntentRouter();

      final decision = router.routeText('? explain last failure');

      expect(decision.route, InputIntentRoute.agent);
      expect(decision.kind, InputIntentKind.naturalLanguageQuestion);
      expect(decision.confidence, 1);
      expect(decision.reason, 'forced-agent-prefix');
    });

    test('honors action prefix', () {
      const router = AgentIntentRouter();

      final decision = router.routeText('/debug-last-failure');

      expect(decision.kind, InputIntentKind.actionSearch);
      expect(decision.route, InputIntentRoute.actionSearch);
      expect(decision.normalizedInput, 'debug-last-failure');
    });

    test('routes Ctrl-R shortcut to command search', () {
      const router = AgentIntentRouter();

      final decision = router.routeShortcut(AgentIntentShortcut.ctrlR);

      expect(decision.kind, InputIntentKind.commandSearch);
      expect(decision.route, InputIntentRoute.commandSearch);
      expect(decision.confidence, 1);
    });

    test('routes shell syntax to shell', () {
      const router = AgentIntentRouter();

      expect(
        router.routeText('FOO=bar flutter test').kind,
        InputIntentKind.shellCommand,
      );
      expect(
        router.routeText('rg TODO | head').kind,
        InputIntentKind.shellCommand,
      );
    });

    test('routes Chinese last failure request to Agent debug intent', () {
      const router = AgentIntentRouter();

      final decision = router.routeText('解释上一个失败命令');

      expect(decision.kind, InputIntentKind.debugLastFailure);
      expect(decision.route, InputIntentRoute.agent);
      expect(decision.reason, 'last-failure-reference');
    });

    test('routes selected block explanations to Agent', () {
      const router = AgentIntentRouter();

      final decision = router.routeText('explain selected block');

      expect(decision.kind, InputIntentKind.explainSelectedBlock);
      expect(decision.route, InputIntentRoute.agent);
    });

    test('routes natural-language questions to Agent', () {
      const router = AgentIntentRouter();

      final decision = router.routeText('why did the tests fail');

      expect(decision.kind, InputIntentKind.naturalLanguageQuestion);
      expect(decision.route, InputIntentRoute.agent);
      expect(decision.confidence, greaterThanOrEqualTo(0.85));
    });

    test('keeps ambiguous shell-like natural language from auto-executing', () {
      const router = AgentIntentRouter();

      final decision = router.routeText('show files modified today');

      expect(decision.kind, InputIntentKind.ambiguous);
      expect(decision.route, InputIntentRoute.ambiguous);
      expect(decision.requiresUserChoice, isTrue);
      expect(
        decision.alternatives.map((alternative) => alternative.kind),
        <InputIntentKind>[
          InputIntentKind.shellCommand,
          InputIntentKind.naturalLanguageQuestion,
        ],
      );
    });

    test('policy can disable natural-language auto detection', () {
      const router = AgentIntentRouter(
        policy: AgentDetectionPolicy(
          naturalLanguageAutoDetectionEnabled: false,
        ),
      );

      final decision = router.routeText('why did the tests fail');

      expect(decision.kind, InputIntentKind.ambiguous);
      expect(decision.reason, 'natural-language-auto-detection-disabled');
      expect(decision.requiresUserChoice, isTrue);
    });
  });
}
