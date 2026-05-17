import 'dart:async';

typedef LocalWorkspaceProductionCallback =
    FutureOr<LocalWorkspaceBindingResult> Function(
      LocalWorkspaceBindingContext context,
    );

class LocalWorkspaceBindingContext {
  const LocalWorkspaceBindingContext({
    required this.operation,
    this.tabId,
    this.paneId,
    this.cwd,
    this.payload,
  });

  final LocalWorkspaceProductionOperation operation;
  final String? tabId;
  final String? paneId;
  final String? cwd;
  final Object? payload;
}

class LocalWorkspaceBindingResult {
  const LocalWorkspaceBindingResult._({
    required this.completed,
    required this.failureCode,
    required this.message,
  });

  const LocalWorkspaceBindingResult.completed([String? message])
    : this._(completed: true, failureCode: null, message: message);

  const LocalWorkspaceBindingResult.failed({
    required LocalWorkspaceBindingFailureCode failureCode,
    String? message,
  }) : this._(completed: false, failureCode: failureCode, message: message);

  final bool completed;
  final LocalWorkspaceBindingFailureCode? failureCode;
  final String? message;

  bool get failed => failureCode != null;
}

enum LocalWorkspaceBindingFailureCode {
  unavailable,
  unsupported,
  rejected,
  platformFailure,
}

enum LocalWorkspaceProductionOperation {
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

class LocalWorkspaceProductionCallbacks {
  const LocalWorkspaceProductionCallbacks({
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

  final LocalWorkspaceProductionCallback? newTab;
  final LocalWorkspaceProductionCallback? closeTab;
  final LocalWorkspaceProductionCallback? reopenClosedTab;
  final LocalWorkspaceProductionCallback? duplicateCurrentCwd;
  final LocalWorkspaceProductionCallback? splitRight;
  final LocalWorkspaceProductionCallback? splitDown;
  final LocalWorkspaceProductionCallback? closePane;
  final LocalWorkspaceProductionCallback? reopenClosedPane;
  final LocalWorkspaceProductionCallback? focusNextPane;
  final LocalWorkspaceProductionCallback? focusPreviousPane;
  final LocalWorkspaceProductionCallback? focusPaneDirection;
  final LocalWorkspaceProductionCallback? resizePane;
  final LocalWorkspaceProductionCallback? swapPane;
  final LocalWorkspaceProductionCallback? zoomPane;
  final LocalWorkspaceProductionCallback? saveLayout;
  final LocalWorkspaceProductionCallback? restoreLayout;

  Map<LocalWorkspaceProductionOperation, LocalWorkspaceProductionCallback>
  toCallbacksByOperation() {
    final callbacks =
        <LocalWorkspaceProductionOperation, LocalWorkspaceProductionCallback>{};

    void add(
      LocalWorkspaceProductionOperation operation,
      LocalWorkspaceProductionCallback? callback,
    ) {
      if (callback != null) {
        callbacks[operation] = callback;
      }
    }

    add(LocalWorkspaceProductionOperation.newTab, newTab);
    add(LocalWorkspaceProductionOperation.closeTab, closeTab);
    add(LocalWorkspaceProductionOperation.reopenClosedTab, reopenClosedTab);
    add(
      LocalWorkspaceProductionOperation.duplicateCurrentCwd,
      duplicateCurrentCwd,
    );
    add(LocalWorkspaceProductionOperation.splitRight, splitRight);
    add(LocalWorkspaceProductionOperation.splitDown, splitDown);
    add(LocalWorkspaceProductionOperation.closePane, closePane);
    add(LocalWorkspaceProductionOperation.reopenClosedPane, reopenClosedPane);
    add(LocalWorkspaceProductionOperation.focusNextPane, focusNextPane);
    add(LocalWorkspaceProductionOperation.focusPreviousPane, focusPreviousPane);
    add(
      LocalWorkspaceProductionOperation.focusPaneDirection,
      focusPaneDirection,
    );
    add(LocalWorkspaceProductionOperation.resizePane, resizePane);
    add(LocalWorkspaceProductionOperation.swapPane, swapPane);
    add(LocalWorkspaceProductionOperation.zoomPane, zoomPane);
    add(LocalWorkspaceProductionOperation.saveLayout, saveLayout);
    add(LocalWorkspaceProductionOperation.restoreLayout, restoreLayout);

    return Map.unmodifiable(callbacks);
  }
}

class LocalWorkspaceProductionWiring {
  LocalWorkspaceProductionWiring({
    required LocalWorkspaceProductionCallbacks callbacks,
    Iterable<LocalWorkspaceProductionOperation>? requiredOperations,
  }) : _callbacks = callbacks.toCallbacksByOperation(),
       requiredOperations = Set.unmodifiable(
         requiredOperations ?? LocalWorkspaceProductionOperation.values,
       );

  final Map<LocalWorkspaceProductionOperation, LocalWorkspaceProductionCallback>
  _callbacks;
  final Set<LocalWorkspaceProductionOperation> requiredOperations;

  Set<LocalWorkspaceProductionOperation> get registeredOperations {
    return _callbacks.keys.toSet();
  }

  Set<LocalWorkspaceProductionOperation> get missingRequiredOperations {
    return requiredOperations
        .where((operation) => !_callbacks.containsKey(operation))
        .toSet();
  }

  bool get isReady => missingRequiredOperations.isEmpty;

  Future<LocalWorkspaceBindingResult> run(
    LocalWorkspaceProductionOperation operation, {
    String? tabId,
    String? paneId,
    String? cwd,
    Object? payload,
  }) async {
    final callback = _callbacks[operation];
    if (callback == null) {
      return LocalWorkspaceBindingResult.failed(
        failureCode: LocalWorkspaceBindingFailureCode.unsupported,
        message: 'No production workspace callback registered for $operation.',
      );
    }
    return callback(
      LocalWorkspaceBindingContext(
        operation: operation,
        tabId: tabId,
        paneId: paneId,
        cwd: cwd,
        payload: payload,
      ),
    );
  }
}
