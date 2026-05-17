import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/productivity/shell_productivity_production_callbacks.dart';

void main() {
  test('runs registered productivity production callbacks', () async {
    final wiring = ShellProductivityProductionWiring(
      requiredOperations: const [
        ShellProductivityProductionOperation.searchScrollback,
      ],
      callbacks: ShellProductivityProductionCallbacks(
        searchScrollback: (context) {
          expect(
            context.operation,
            ShellProductivityProductionOperation.searchScrollback,
          );
          expect(context.query, 'build failed');
          return const ShellProductivityBindingResult.completed('searched');
        },
      ),
    );

    final result = await wiring.run(
      ShellProductivityProductionOperation.searchScrollback,
      query: 'build failed',
    );

    expect(wiring.isReady, isTrue);
    expect(result.completed, isTrue);
    expect(result.message, 'searched');
  });

  test('reports missing required productivity production callbacks', () {
    final wiring = ShellProductivityProductionWiring(
      requiredOperations: const [
        ShellProductivityProductionOperation.nextPrompt,
        ShellProductivityProductionOperation.copyCommandOutput,
      ],
      callbacks: ShellProductivityProductionCallbacks(
        nextPrompt: (_) => const ShellProductivityBindingResult.completed(),
      ),
    );

    expect(wiring.isReady, isFalse);
    expect(wiring.missingRequiredOperations, {
      ShellProductivityProductionOperation.copyCommandOutput,
    });
  });

  test('unsupported productivity operation returns failed result', () async {
    final wiring = ShellProductivityProductionWiring(
      requiredOperations: const [],
      callbacks: const ShellProductivityProductionCallbacks(),
    );

    final result = await wiring.run(
      ShellProductivityProductionOperation.clearScrollback,
    );

    expect(result.failed, isTrue);
    expect(result.failureCode, ShellProductivityBindingFailureCode.unsupported);
  });

  test('core productivity baseline is ready with matching callbacks', () async {
    final wiring = ShellProductivityProductionWiring(
      requiredOperations: _coreProductivityOperations,
      callbacks: _coreProductivityCallbacks(),
    );

    final searchResult = await wiring.run(
      ShellProductivityProductionOperation.searchScrollback,
      query: 'build failed',
    );

    expect(wiring.isReady, isTrue);
    expect(wiring.missingRequiredOperations, isEmpty);
    expect(
      wiring.registeredOperations,
      containsAll(_coreProductivityOperations),
    );
    expect(searchResult.completed, isTrue);
  });

  test('default all-operations wiring keeps advanced gaps visible', () {
    final wiring = ShellProductivityProductionWiring(
      callbacks: _coreProductivityCallbacks(),
    );

    expect(wiring.isReady, isFalse);
    expect(
      wiring.missingRequiredOperations,
      containsAll({
        ShellProductivityProductionOperation.jumpToCommandBlock,
        ShellProductivityProductionOperation.copyLastCommandOutput,
        ShellProductivityProductionOperation.saveCommandOutput,
      }),
    );
  });
}

const _coreProductivityOperations = [
  ShellProductivityProductionOperation.nextPrompt,
  ShellProductivityProductionOperation.previousPrompt,
  ShellProductivityProductionOperation.selectCommandOutput,
  ShellProductivityProductionOperation.copyCommandOutput,
  ShellProductivityProductionOperation.openRecentDirectory,
  ShellProductivityProductionOperation.searchScrollback,
  ShellProductivityProductionOperation.nextSearchMatch,
  ShellProductivityProductionOperation.previousSearchMatch,
  ShellProductivityProductionOperation.clearSearch,
  ShellProductivityProductionOperation.clearScrollback,
  ShellProductivityProductionOperation.toggleReadOnly,
];

ShellProductivityProductionCallbacks _coreProductivityCallbacks() {
  return ShellProductivityProductionCallbacks(
    nextPrompt: _complete,
    previousPrompt: _complete,
    selectCommandOutput: _complete,
    copyCommandOutput: _complete,
    openRecentDirectory: _complete,
    searchScrollback: _complete,
    nextSearchMatch: _complete,
    previousSearchMatch: _complete,
    clearSearch: _complete,
    clearScrollback: _complete,
    toggleReadOnly: _complete,
  );
}

ShellProductivityBindingResult _complete(
  ShellProductivityBindingContext context,
) {
  return const ShellProductivityBindingResult.completed();
}
