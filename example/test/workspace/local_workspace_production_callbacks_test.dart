import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/workspace/local_workspace_production_callbacks.dart';

void main() {
  test('runs registered workspace production callbacks', () async {
    final wiring = LocalWorkspaceProductionWiring(
      requiredOperations: const [LocalWorkspaceProductionOperation.newTab],
      callbacks: LocalWorkspaceProductionCallbacks(
        newTab: (context) {
          expect(context.operation, LocalWorkspaceProductionOperation.newTab);
          expect(context.cwd, '/tmp/project');
          return const LocalWorkspaceBindingResult.completed('created');
        },
      ),
    );

    final result = await wiring.run(
      LocalWorkspaceProductionOperation.newTab,
      cwd: '/tmp/project',
    );

    expect(wiring.isReady, isTrue);
    expect(result.completed, isTrue);
    expect(result.message, 'created');
  });

  test('reports missing required workspace production callbacks', () {
    final wiring = LocalWorkspaceProductionWiring(
      requiredOperations: const [
        LocalWorkspaceProductionOperation.newTab,
        LocalWorkspaceProductionOperation.closeTab,
      ],
      callbacks: LocalWorkspaceProductionCallbacks(
        newTab: (_) => const LocalWorkspaceBindingResult.completed(),
      ),
    );

    expect(wiring.isReady, isFalse);
    expect(wiring.missingRequiredOperations, {
      LocalWorkspaceProductionOperation.closeTab,
    });
  });

  test('unsupported workspace operation returns failed result', () async {
    final wiring = LocalWorkspaceProductionWiring(
      requiredOperations: const [],
      callbacks: const LocalWorkspaceProductionCallbacks(),
    );

    final result = await wiring.run(
      LocalWorkspaceProductionOperation.closePane,
    );

    expect(result.failed, isTrue);
    expect(result.failureCode, LocalWorkspaceBindingFailureCode.unsupported);
  });

  test('core workspace baseline is ready with matching callbacks', () async {
    final wiring = LocalWorkspaceProductionWiring(
      requiredOperations: _coreWorkspaceOperations,
      callbacks: _coreWorkspaceCallbacks(),
    );

    final resizeResult = await wiring.run(
      LocalWorkspaceProductionOperation.resizePane,
      paneId: 'pane-1',
    );

    expect(wiring.isReady, isTrue);
    expect(wiring.missingRequiredOperations, isEmpty);
    expect(wiring.registeredOperations, containsAll(_coreWorkspaceOperations));
    expect(resizeResult.completed, isTrue);
  });

  test('default all-operations wiring keeps layout gaps visible', () {
    final wiring = LocalWorkspaceProductionWiring(
      callbacks: _coreWorkspaceCallbacks(),
    );

    expect(wiring.isReady, isFalse);
    expect(
      wiring.missingRequiredOperations,
      containsAll({
        LocalWorkspaceProductionOperation.reopenClosedPane,
        LocalWorkspaceProductionOperation.focusPaneDirection,
        LocalWorkspaceProductionOperation.saveLayout,
        LocalWorkspaceProductionOperation.restoreLayout,
      }),
    );
  });
}

const _coreWorkspaceOperations = [
  LocalWorkspaceProductionOperation.newTab,
  LocalWorkspaceProductionOperation.closeTab,
  LocalWorkspaceProductionOperation.reopenClosedTab,
  LocalWorkspaceProductionOperation.duplicateCurrentCwd,
  LocalWorkspaceProductionOperation.splitRight,
  LocalWorkspaceProductionOperation.splitDown,
  LocalWorkspaceProductionOperation.closePane,
  LocalWorkspaceProductionOperation.focusNextPane,
  LocalWorkspaceProductionOperation.focusPreviousPane,
  LocalWorkspaceProductionOperation.resizePane,
  LocalWorkspaceProductionOperation.swapPane,
  LocalWorkspaceProductionOperation.zoomPane,
];

LocalWorkspaceProductionCallbacks _coreWorkspaceCallbacks() {
  return LocalWorkspaceProductionCallbacks(
    newTab: _complete,
    closeTab: _complete,
    reopenClosedTab: _complete,
    duplicateCurrentCwd: _complete,
    splitRight: _complete,
    splitDown: _complete,
    closePane: _complete,
    focusNextPane: _complete,
    focusPreviousPane: _complete,
    resizePane: _complete,
    swapPane: _complete,
    zoomPane: _complete,
  );
}

LocalWorkspaceBindingResult _complete(LocalWorkspaceBindingContext context) {
  return const LocalWorkspaceBindingResult.completed();
}
