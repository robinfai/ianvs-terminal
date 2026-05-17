import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/policies/local_terminal_policy_production_callbacks.dart';

void main() {
  test('runs registered policy production callbacks', () async {
    final wiring = LocalTerminalPolicyProductionWiring(
      requiredOperations: const [LocalTerminalPolicyProductionOperation.paste],
      callbacks: LocalTerminalPolicyProductionCallbacks(
        paste: (context) {
          expect(
            context.operation,
            LocalTerminalPolicyProductionOperation.paste,
          );
          expect(context.text, 'hello');
          return const LocalTerminalPolicyBindingResult.completed('pasted');
        },
      ),
    );

    final result = await wiring.run(
      LocalTerminalPolicyProductionOperation.paste,
      text: 'hello',
    );

    expect(wiring.isReady, isTrue);
    expect(result.completed, isTrue);
    expect(result.message, 'pasted');
  });

  test('reports missing required policy production callbacks', () {
    final wiring = LocalTerminalPolicyProductionWiring(
      requiredOperations: const [
        LocalTerminalPolicyProductionOperation.paste,
        LocalTerminalPolicyProductionOperation.toggleHotkeyWindow,
      ],
      callbacks: LocalTerminalPolicyProductionCallbacks(
        paste: (_) => const LocalTerminalPolicyBindingResult.completed(),
      ),
    );

    expect(wiring.isReady, isFalse);
    expect(wiring.missingRequiredOperations, {
      LocalTerminalPolicyProductionOperation.toggleHotkeyWindow,
    });
  });

  test('unsupported policy operation returns failed result', () async {
    final wiring = LocalTerminalPolicyProductionWiring(
      requiredOperations: const [],
      callbacks: const LocalTerminalPolicyProductionCallbacks(),
    );

    final result = await wiring.run(
      LocalTerminalPolicyProductionOperation.emitBellNotification,
    );

    expect(result.failed, isTrue);
    expect(
      result.failureCode,
      LocalTerminalPolicyBindingFailureCode.unsupported,
    );
  });

  test('core policy baseline is ready with matching callbacks', () async {
    final wiring = LocalTerminalPolicyProductionWiring(
      requiredOperations: _corePolicyOperations,
      callbacks: _corePolicyCallbacks(),
    );

    final pasteResult = await wiring.run(
      LocalTerminalPolicyProductionOperation.paste,
      text: 'hello',
    );

    expect(wiring.isReady, isTrue);
    expect(wiring.missingRequiredOperations, isEmpty);
    expect(wiring.registeredOperations, containsAll(_corePolicyOperations));
    expect(pasteResult.completed, isTrue);
  });

  test('default all-operations wiring keeps advanced gaps visible', () {
    final wiring = LocalTerminalPolicyProductionWiring(
      callbacks: _corePolicyCallbacks(),
    );

    expect(wiring.isReady, isFalse);
    expect(
      wiring.missingRequiredOperations,
      containsAll({
        LocalTerminalPolicyProductionOperation.emitSilenceNotification,
        LocalTerminalPolicyProductionOperation.emitPromptReadyNotification,
        LocalTerminalPolicyProductionOperation.applyHotkeyWindowConfig,
        LocalTerminalPolicyProductionOperation.recordHotkeyWindowFailure,
      }),
    );
  });
}

const _corePolicyOperations = [
  LocalTerminalPolicyProductionOperation.copy,
  LocalTerminalPolicyProductionOperation.paste,
  LocalTerminalPolicyProductionOperation.pasteHistory,
  LocalTerminalPolicyProductionOperation.pasteAsBracketed,
  LocalTerminalPolicyProductionOperation.confirmLargePaste,
  LocalTerminalPolicyProductionOperation.confirmMultilinePaste,
  LocalTerminalPolicyProductionOperation.recordPasteHistory,
  LocalTerminalPolicyProductionOperation.osc52Copy,
  LocalTerminalPolicyProductionOperation.emitBellNotification,
  LocalTerminalPolicyProductionOperation.emitCommandFinishedNotification,
  LocalTerminalPolicyProductionOperation.emitActivityNotification,
  LocalTerminalPolicyProductionOperation.toggleHotkeyWindow,
];

LocalTerminalPolicyProductionCallbacks _corePolicyCallbacks() {
  return LocalTerminalPolicyProductionCallbacks(
    copy: _complete,
    paste: _complete,
    pasteHistory: _complete,
    pasteAsBracketed: _complete,
    confirmLargePaste: _complete,
    confirmMultilinePaste: _complete,
    recordPasteHistory: _complete,
    osc52Copy: _complete,
    emitBellNotification: _complete,
    emitCommandFinishedNotification: _complete,
    emitActivityNotification: _complete,
    toggleHotkeyWindow: _complete,
  );
}

LocalTerminalPolicyBindingResult _complete(
  LocalTerminalPolicyBindingContext context,
) {
  return const LocalTerminalPolicyBindingResult.completed();
}
