import 'package:app/features/visual/local_terminal_visual_production_callbacks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs registered visual production callbacks', () async {
    final wiring = LocalTerminalVisualProductionWiring(
      requiredOperations: const [
        LocalTerminalVisualProductionOperation.exportScrollback,
      ],
      callbacks: LocalTerminalVisualProductionCallbacks(
        exportScrollback: (context) {
          expect(
            context.operation,
            LocalTerminalVisualProductionOperation.exportScrollback,
          );
          expect(context.destinationPath, '/tmp/scrollback.txt');
          return const LocalTerminalVisualBindingResult.completed('applied');
        },
      ),
    );

    final result = await wiring.run(
      LocalTerminalVisualProductionOperation.exportScrollback,
      destinationPath: '/tmp/scrollback.txt',
    );

    expect(wiring.isReady, isTrue);
    expect(result.completed, isTrue);
    expect(result.message, 'applied');
  });

  test('reports missing required visual production callbacks', () {
    final wiring = LocalTerminalVisualProductionWiring(
      requiredOperations: const [
        LocalTerminalVisualProductionOperation.exportScrollback,
        LocalTerminalVisualProductionOperation.exportCommandOutput,
      ],
      callbacks: LocalTerminalVisualProductionCallbacks(
        exportScrollback: (_) =>
            const LocalTerminalVisualBindingResult.completed(),
      ),
    );

    expect(wiring.isReady, isFalse);
    expect(wiring.missingRequiredOperations, {
      LocalTerminalVisualProductionOperation.exportCommandOutput,
    });
  });

  test('unsupported visual operation returns failed result', () async {
    final wiring = LocalTerminalVisualProductionWiring(
      requiredOperations: const [],
      callbacks: const LocalTerminalVisualProductionCallbacks(),
    );

    final result = await wiring.run(
      LocalTerminalVisualProductionOperation.importThemePreset,
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

const List<LocalTerminalVisualProductionOperation> _coreVisualOperations = [
  LocalTerminalVisualProductionOperation.exportScrollback,
  LocalTerminalVisualProductionOperation.applyPaneVisualPolicy,
  LocalTerminalVisualProductionOperation.applySplitDividerPolicy,
];

LocalTerminalVisualProductionCallbacks _coreVisualCallbacks() {
  return const LocalTerminalVisualProductionCallbacks(
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
