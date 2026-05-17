import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/visual/local_terminal_visual_production_callbacks.dart';

void main() {
  test('runs registered visual production callbacks', () async {
    final wiring = LocalTerminalVisualProductionWiring(
      requiredOperations: const [
        LocalTerminalVisualProductionOperation.applyTheme,
      ],
      callbacks: LocalTerminalVisualProductionCallbacks(
        applyTheme: (context) {
          expect(
            context.operation,
            LocalTerminalVisualProductionOperation.applyTheme,
          );
          expect(context.themeId, 'solarized-dark');
          return const LocalTerminalVisualBindingResult.completed('applied');
        },
      ),
    );

    final result = await wiring.run(
      LocalTerminalVisualProductionOperation.applyTheme,
      themeId: 'solarized-dark',
    );

    expect(wiring.isReady, isTrue);
    expect(result.completed, isTrue);
    expect(result.message, 'applied');
  });

  test('reports missing required visual production callbacks', () {
    final wiring = LocalTerminalVisualProductionWiring(
      requiredOperations: const [
        LocalTerminalVisualProductionOperation.openThemePicker,
        LocalTerminalVisualProductionOperation.exportScrollback,
      ],
      callbacks: LocalTerminalVisualProductionCallbacks(
        openThemePicker: (_) =>
            const LocalTerminalVisualBindingResult.completed(),
      ),
    );

    expect(wiring.isReady, isFalse);
    expect(wiring.missingRequiredOperations, {
      LocalTerminalVisualProductionOperation.exportScrollback,
    });
  });

  test('unsupported visual operation returns failed result', () async {
    final wiring = LocalTerminalVisualProductionWiring(
      requiredOperations: const [],
      callbacks: const LocalTerminalVisualProductionCallbacks(),
    );

    final result = await wiring.run(
      LocalTerminalVisualProductionOperation.applyLayoutTemplate,
    );

    expect(result.failed, isTrue);
    expect(
      result.failureCode,
      LocalTerminalVisualBindingFailureCode.unsupported,
    );
  });

  test('core visual baseline is ready with matching callbacks', () async {
    final wiring = LocalTerminalVisualProductionWiring(
      requiredOperations: _coreVisualOperations,
      callbacks: _coreVisualCallbacks(),
    );

    final exportResult = await wiring.run(
      LocalTerminalVisualProductionOperation.exportScrollback,
      destinationPath: '/tmp/scrollback.txt',
    );

    expect(wiring.isReady, isTrue);
    expect(wiring.missingRequiredOperations, isEmpty);
    expect(wiring.registeredOperations, containsAll(_coreVisualOperations));
    expect(exportResult.completed, isTrue);
  });

  test('default all-operations wiring keeps advanced gaps visible', () {
    final wiring = LocalTerminalVisualProductionWiring(
      callbacks: _coreVisualCallbacks(),
    );

    expect(wiring.isReady, isFalse);
    expect(
      wiring.missingRequiredOperations,
      containsAll({
        LocalTerminalVisualProductionOperation.importThemePreset,
        LocalTerminalVisualProductionOperation.exportThemePreset,
        LocalTerminalVisualProductionOperation.saveLayoutTemplate,
        LocalTerminalVisualProductionOperation.exportLayoutTemplate,
        LocalTerminalVisualProductionOperation.exportCommandOutput,
        LocalTerminalVisualProductionOperation.configureGraphicsStorage,
        LocalTerminalVisualProductionOperation.recordGraphicsEviction,
        LocalTerminalVisualProductionOperation.toggleTimestamps,
        LocalTerminalVisualProductionOperation.toggleCommandPane,
        LocalTerminalVisualProductionOperation.openScrollbackEditor,
      }),
    );
  });
}

const _coreVisualOperations = [
  LocalTerminalVisualProductionOperation.openThemePicker,
  LocalTerminalVisualProductionOperation.applyTheme,
  LocalTerminalVisualProductionOperation.applyLayoutTemplate,
  LocalTerminalVisualProductionOperation.exportScrollback,
  LocalTerminalVisualProductionOperation.applyPaneVisualPolicy,
  LocalTerminalVisualProductionOperation.applySplitDividerPolicy,
];

LocalTerminalVisualProductionCallbacks _coreVisualCallbacks() {
  return LocalTerminalVisualProductionCallbacks(
    openThemePicker: _complete,
    applyTheme: _complete,
    applyLayoutTemplate: _complete,
    exportScrollback: _complete,
    applyPaneVisualPolicy: _complete,
    applySplitDividerPolicy: _complete,
  );
}

LocalTerminalVisualBindingResult _complete(
  LocalTerminalVisualBindingContext context,
) {
  return const LocalTerminalVisualBindingResult.completed();
}
