import 'dart:async';

typedef TerminalLayoutProductionCallback =
    FutureOr<TerminalLayoutBindingResult> Function(
      TerminalLayoutBindingContext context,
    );

class TerminalLayoutBindingContext {
  const TerminalLayoutBindingContext({
    required this.operation,
    this.tabId,
    this.paneId,
    this.cwd,
    this.payload,
  });

  final TerminalLayoutProductionOperation operation;
  final String? tabId;
  final String? paneId;
  final String? cwd;
  final Object? payload;
}

class TerminalLayoutBindingResult {
  const TerminalLayoutBindingResult._({
    required this.completed,
    required this.failureCode,
    required this.message,
  });

  const TerminalLayoutBindingResult.completed([String? message])
    : this._(completed: true, failureCode: null, message: message);

  const TerminalLayoutBindingResult.failed({
    required TerminalLayoutBindingFailureCode failureCode,
    String? message,
  }) : this._(completed: false, failureCode: failureCode, message: message);

  final bool completed;
  final TerminalLayoutBindingFailureCode? failureCode;
  final String? message;

  bool get failed => failureCode != null;
}

enum TerminalLayoutBindingFailureCode {
  unavailable,
  unsupported,
  rejected,
  platformFailure,
}

enum TerminalLayoutProductionOperation {
  newTab,
  closeTab,
  reopenClosedTab,
  duplicateCurrentCwd,
  splitRight,
  splitDown,
  closePane,
  reopenClosedPane,
  focusNextPane,
  focusPreviousPane,
  focusPaneDirection,
  resizePane,
  swapPane,
  zoomPane,
  saveLayout,
  restoreLayout,
}

class TerminalLayoutProductionCallbacks {
  const TerminalLayoutProductionCallbacks({
    this.newTab,
    this.closeTab,
    this.reopenClosedTab,
    this.duplicateCurrentCwd,
    this.splitRight,
    this.splitDown,
    this.closePane,
    this.reopenClosedPane,
    this.focusNextPane,
    this.focusPreviousPane,
    this.focusPaneDirection,
    this.resizePane,
    this.swapPane,
    this.zoomPane,
    this.saveLayout,
    this.restoreLayout,
  });

  final TerminalLayoutProductionCallback? newTab;
  final TerminalLayoutProductionCallback? closeTab;
  final TerminalLayoutProductionCallback? reopenClosedTab;
  final TerminalLayoutProductionCallback? duplicateCurrentCwd;
  final TerminalLayoutProductionCallback? splitRight;
  final TerminalLayoutProductionCallback? splitDown;
  final TerminalLayoutProductionCallback? closePane;
  final TerminalLayoutProductionCallback? reopenClosedPane;
  final TerminalLayoutProductionCallback? focusNextPane;
  final TerminalLayoutProductionCallback? focusPreviousPane;
  final TerminalLayoutProductionCallback? focusPaneDirection;
  final TerminalLayoutProductionCallback? resizePane;
  final TerminalLayoutProductionCallback? swapPane;
  final TerminalLayoutProductionCallback? zoomPane;
  final TerminalLayoutProductionCallback? saveLayout;
  final TerminalLayoutProductionCallback? restoreLayout;

  Map<TerminalLayoutProductionOperation, TerminalLayoutProductionCallback>
  toCallbacksByOperation() {
    final callbacks =
        <TerminalLayoutProductionOperation, TerminalLayoutProductionCallback>{};

    void add(
      TerminalLayoutProductionOperation operation,
      TerminalLayoutProductionCallback? callback,
    ) {
      if (callback != null) {
        callbacks[operation] = callback;
      }
    }

    add(TerminalLayoutProductionOperation.newTab, newTab);
    add(TerminalLayoutProductionOperation.closeTab, closeTab);
    add(TerminalLayoutProductionOperation.reopenClosedTab, reopenClosedTab);
    add(
      TerminalLayoutProductionOperation.duplicateCurrentCwd,
      duplicateCurrentCwd,
    );
    add(TerminalLayoutProductionOperation.splitRight, splitRight);
    add(TerminalLayoutProductionOperation.splitDown, splitDown);
    add(TerminalLayoutProductionOperation.closePane, closePane);
    add(TerminalLayoutProductionOperation.reopenClosedPane, reopenClosedPane);
    add(TerminalLayoutProductionOperation.focusNextPane, focusNextPane);
    add(TerminalLayoutProductionOperation.focusPreviousPane, focusPreviousPane);
    add(
      TerminalLayoutProductionOperation.focusPaneDirection,
      focusPaneDirection,
    );
    add(TerminalLayoutProductionOperation.resizePane, resizePane);
    add(TerminalLayoutProductionOperation.swapPane, swapPane);
    add(TerminalLayoutProductionOperation.zoomPane, zoomPane);
    add(TerminalLayoutProductionOperation.saveLayout, saveLayout);
    add(TerminalLayoutProductionOperation.restoreLayout, restoreLayout);

    return Map.unmodifiable(callbacks);
  }
}

class TerminalLayoutProductionWiring {
  TerminalLayoutProductionWiring({
    required TerminalLayoutProductionCallbacks callbacks,
    Iterable<TerminalLayoutProductionOperation>? requiredOperations,
  }) : _callbacks = callbacks.toCallbacksByOperation(),
       requiredOperations = Set.unmodifiable(
         requiredOperations ?? TerminalLayoutProductionOperation.values,
       );

  final Map<TerminalLayoutProductionOperation, TerminalLayoutProductionCallback>
  _callbacks;
  final Set<TerminalLayoutProductionOperation> requiredOperations;

  Set<TerminalLayoutProductionOperation> get registeredOperations {
    return _callbacks.keys.toSet();
  }

  Set<TerminalLayoutProductionOperation> get missingRequiredOperations {
    return requiredOperations
        .where((operation) => !_callbacks.containsKey(operation))
        .toSet();
  }

  bool get isReady => missingRequiredOperations.isEmpty;

  Future<TerminalLayoutBindingResult> run(
    TerminalLayoutProductionOperation operation, {
    String? tabId,
    String? paneId,
    String? cwd,
    Object? payload,
  }) async {
    final callback = _callbacks[operation];
    if (callback == null) {
      return TerminalLayoutBindingResult.failed(
        failureCode: TerminalLayoutBindingFailureCode.unsupported,
        message: 'No production layout callback registered for $operation.',
      );
    }
    return callback(
      TerminalLayoutBindingContext(
        operation: operation,
        tabId: tabId,
        paneId: paneId,
        cwd: cwd,
        payload: payload,
      ),
    );
  }
}
