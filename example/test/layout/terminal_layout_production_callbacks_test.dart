import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/layout/terminal_layout_production_callbacks.dart';

void main() {
  test('runs registered layout production callbacks', () async {
    final wiring = TerminalLayoutProductionWiring(
      requiredOperations: const [TerminalLayoutProductionOperation.newTab],
      callbacks: TerminalLayoutProductionCallbacks(
        newTab: (context) {
          expect(context.operation, TerminalLayoutProductionOperation.newTab);
          expect(context.cwd, '/tmp/project');
          return const TerminalLayoutBindingResult.completed('created');
        },
      ),
    );

    final result = await wiring.run(
      TerminalLayoutProductionOperation.newTab,
      cwd: '/tmp/project',
    );

    expect(wiring.isReady, isTrue);
    expect(result.completed, isTrue);
    expect(result.message, 'created');
  });

  test('reports missing required layout production callbacks', () {
    final wiring = TerminalLayoutProductionWiring(
      requiredOperations: const [
        TerminalLayoutProductionOperation.newTab,
        TerminalLayoutProductionOperation.closeTab,
      ],
      callbacks: TerminalLayoutProductionCallbacks(
        newTab: (_) => const TerminalLayoutBindingResult.completed(),
      ),
    );

    expect(wiring.isReady, isFalse);
    expect(wiring.missingRequiredOperations, {
      TerminalLayoutProductionOperation.closeTab,
    });
  });

  test('unsupported layout operation returns failed result', () async {
    final wiring = TerminalLayoutProductionWiring(
      requiredOperations: const [],
      callbacks: const TerminalLayoutProductionCallbacks(),
    );

    final result = await wiring.run(
      TerminalLayoutProductionOperation.closePane,
    );

    expect(result.failed, isTrue);
    expect(result.failureCode, TerminalLayoutBindingFailureCode.unsupported);
  });

  test('core layout baseline is ready with matching callbacks', () async {
    final wiring = TerminalLayoutProductionWiring(
      requiredOperations: _coreLayoutOperations,
      callbacks: _coreLayoutCallbacks(),
    );

    final resizeResult = await wiring.run(
      TerminalLayoutProductionOperation.resizePane,
      paneId: 'pane-1',
    );

    expect(wiring.isReady, isTrue);
    expect(wiring.missingRequiredOperations, isEmpty);
    expect(wiring.registeredOperations, containsAll(_coreLayoutOperations));
    expect(resizeResult.completed, isTrue);
  });

  test('default all-operations wiring keeps layout gaps visible', () {
    final wiring = TerminalLayoutProductionWiring(
      callbacks: _coreLayoutCallbacks(),
    );

    expect(wiring.isReady, isFalse);
    expect(
      wiring.missingRequiredOperations,
      containsAll({
        TerminalLayoutProductionOperation.reopenClosedPane,
        TerminalLayoutProductionOperation.focusPaneDirection,
        TerminalLayoutProductionOperation.saveLayout,
        TerminalLayoutProductionOperation.restoreLayout,
      }),
    );
  });
}

const _coreLayoutOperations = [
  TerminalLayoutProductionOperation.newTab,
  TerminalLayoutProductionOperation.closeTab,
  TerminalLayoutProductionOperation.reopenClosedTab,
  TerminalLayoutProductionOperation.duplicateCurrentCwd,
  TerminalLayoutProductionOperation.splitRight,
  TerminalLayoutProductionOperation.splitDown,
  TerminalLayoutProductionOperation.closePane,
  TerminalLayoutProductionOperation.focusNextPane,
  TerminalLayoutProductionOperation.focusPreviousPane,
  TerminalLayoutProductionOperation.resizePane,
  TerminalLayoutProductionOperation.swapPane,
  TerminalLayoutProductionOperation.zoomPane,
];

TerminalLayoutProductionCallbacks _coreLayoutCallbacks() {
  return TerminalLayoutProductionCallbacks(
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

TerminalLayoutBindingResult _complete(TerminalLayoutBindingContext context) {
  return const TerminalLayoutBindingResult.completed();
}
