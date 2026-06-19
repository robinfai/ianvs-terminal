import 'package:app/features/agent_center/agent_center.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RouteDecisionChip', () {
    testWidgets('shows shell route decisions', (tester) async {
      await _pumpChip(
        tester,
        decision: const InputIntentDecision(
          kind: InputIntentKind.shellCommand,
          confidence: 0.95,
          reason: 'shell-syntax-or-vocabulary',
          normalizedInput: 'git status',
        ),
        originalText: 'git status',
      );

      expect(
        find.byKey(const Key('agent-route-decision-chip')),
        findsOneWidget,
      );
      expect(find.text('Shell'), findsOneWidget);
      expect(find.byIcon(Icons.terminal_rounded), findsOneWidget);
    });

    testWidgets('shows agent route decisions with an override action', (
      tester,
    ) async {
      RouteDecisionOverride? override;
      await _pumpChip(
        tester,
        decision: const InputIntentDecision(
          kind: InputIntentKind.naturalLanguageQuestion,
          confidence: 0.88,
          reason: 'natural-language-rule',
          normalizedInput: 'why did tests fail',
        ),
        originalText: 'why did tests fail',
        onOverride: (value) => override = value,
      );

      expect(find.text('Agent'), findsOneWidget);
      expect(find.text('Use Shell'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-route-toggle-override')));
      await tester.pump();

      expect(override?.target, RouteDecisionOverrideTarget.shell);
      expect(override?.originalText, 'why did tests fail');
      expect(override?.decision.normalizedInput, 'why did tests fail');
    });

    testWidgets('ambiguous decisions require visible choice', (tester) async {
      RouteDecisionOverride? override;
      await _pumpChip(
        tester,
        decision: const InputIntentDecision(
          kind: InputIntentKind.ambiguous,
          confidence: 0.62,
          reason: 'ambiguous-shell-agent-language',
          normalizedInput: 'show files modified today',
          requiresUserChoice: true,
          alternatives: <InputIntentAlternative>[
            InputIntentAlternative(
              kind: InputIntentKind.shellCommand,
              label: 'Shell',
              confidence: 0.62,
            ),
            InputIntentAlternative(
              kind: InputIntentKind.naturalLanguageQuestion,
              label: 'Agent',
              confidence: 0.62,
            ),
          ],
        ),
        originalText: 'show files modified today',
        onOverride: (value) => override = value,
      );

      expect(find.text('Ambiguous'), findsOneWidget);
      expect(
        find.byKey(const Key('agent-route-shell-override')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('agent-route-agent-override')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('agent-route-agent-override')));
      await tester.pump();

      expect(override?.target, RouteDecisionOverrideTarget.agent);
      expect(override?.originalText, 'show files modified today');
    });

    testWidgets('does not render empty hidden decisions', (tester) async {
      await _pumpChip(
        tester,
        decision: const InputIntentDecision(
          kind: InputIntentKind.empty,
          confidence: 1,
          reason: 'empty-input',
          visible: false,
        ),
        originalText: '',
      );

      expect(find.byKey(const Key('agent-route-decision-chip')), findsNothing);
    });
  });
}

Future<void> _pumpChip(
  WidgetTester tester, {
  required InputIntentDecision decision,
  required String originalText,
  ValueChanged<RouteDecisionOverride>? onOverride,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(Brightness.light),
      darkTheme: buildIanvsTerminalTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: RouteDecisionChip(
            decision: decision,
            originalText: originalText,
            onOverride: onOverride,
          ),
        ),
      ),
    ),
  );
}
