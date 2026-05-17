import 'dart:async';

typedef ShellProductivityProductionCallback =
    FutureOr<ShellProductivityBindingResult> Function(
      ShellProductivityBindingContext context,
    );

class ShellProductivityBindingContext {
  const ShellProductivityBindingContext({
    required this.operation,
    this.tabId,
    this.paneId,
    this.commandId,
    this.query,
    this.payload,
  });

  final ShellProductivityProductionOperation operation;
  final String? tabId;
  final String? paneId;
  final String? commandId;
  final String? query;
  final Object? payload;
}

class ShellProductivityBindingResult {
  const ShellProductivityBindingResult._({
    required this.completed,
    required this.failureCode,
    required this.message,
  });

  const ShellProductivityBindingResult.completed([String? message])
    : this._(completed: true, failureCode: null, message: message);

  const ShellProductivityBindingResult.failed({
    required ShellProductivityBindingFailureCode failureCode,
    String? message,
  }) : this._(completed: false, failureCode: failureCode, message: message);

  final bool completed;
  final ShellProductivityBindingFailureCode? failureCode;
  final String? message;

  bool get failed => failureCode != null;
}

enum ShellProductivityBindingFailureCode {
  unavailable,
  unsupported,
  rejected,
  shellIntegrationDisabled,
  platformFailure,
}

enum ShellProductivityProductionOperation {
  nextPrompt,
  previousPrompt,
  selectCommandOutput,
  copyCommandOutput,
  openRecentDirectory,
  searchScrollback,
  nextSearchMatch,
  previousSearchMatch,
  clearSearch,
  clearScrollback,
  toggleReadOnly,
  jumpToCommandBlock,
  copyLastCommandOutput,
  saveCommandOutput,
}

class ShellProductivityProductionCallbacks {
  const ShellProductivityProductionCallbacks({
    this.nextPrompt,
    this.previousPrompt,
    this.selectCommandOutput,
    this.copyCommandOutput,
    this.openRecentDirectory,
    this.searchScrollback,
    this.nextSearchMatch,
    this.previousSearchMatch,
    this.clearSearch,
    this.clearScrollback,
    this.toggleReadOnly,
    this.jumpToCommandBlock,
    this.copyLastCommandOutput,
    this.saveCommandOutput,
  });

  final ShellProductivityProductionCallback? nextPrompt;
  final ShellProductivityProductionCallback? previousPrompt;
  final ShellProductivityProductionCallback? selectCommandOutput;
  final ShellProductivityProductionCallback? copyCommandOutput;
  final ShellProductivityProductionCallback? openRecentDirectory;
  final ShellProductivityProductionCallback? searchScrollback;
  final ShellProductivityProductionCallback? nextSearchMatch;
  final ShellProductivityProductionCallback? previousSearchMatch;
  final ShellProductivityProductionCallback? clearSearch;
  final ShellProductivityProductionCallback? clearScrollback;
  final ShellProductivityProductionCallback? toggleReadOnly;
  final ShellProductivityProductionCallback? jumpToCommandBlock;
  final ShellProductivityProductionCallback? copyLastCommandOutput;
  final ShellProductivityProductionCallback? saveCommandOutput;

  Map<ShellProductivityProductionOperation, ShellProductivityProductionCallback>
  toCallbacksByOperation() {
    final callbacks =
        <
          ShellProductivityProductionOperation,
          ShellProductivityProductionCallback
        >{};

    void add(
      ShellProductivityProductionOperation operation,
      ShellProductivityProductionCallback? callback,
    ) {
      if (callback != null) {
        callbacks[operation] = callback;
      }
    }

    add(ShellProductivityProductionOperation.nextPrompt, nextPrompt);
    add(ShellProductivityProductionOperation.previousPrompt, previousPrompt);
    add(
      ShellProductivityProductionOperation.selectCommandOutput,
      selectCommandOutput,
    );
    add(
      ShellProductivityProductionOperation.copyCommandOutput,
      copyCommandOutput,
    );
    add(
      ShellProductivityProductionOperation.openRecentDirectory,
      openRecentDirectory,
    );
    add(
      ShellProductivityProductionOperation.searchScrollback,
      searchScrollback,
    );
    add(ShellProductivityProductionOperation.nextSearchMatch, nextSearchMatch);
    add(
      ShellProductivityProductionOperation.previousSearchMatch,
      previousSearchMatch,
    );
    add(ShellProductivityProductionOperation.clearSearch, clearSearch);
    add(ShellProductivityProductionOperation.clearScrollback, clearScrollback);
    add(ShellProductivityProductionOperation.toggleReadOnly, toggleReadOnly);
    add(
      ShellProductivityProductionOperation.jumpToCommandBlock,
      jumpToCommandBlock,
    );
    add(
      ShellProductivityProductionOperation.copyLastCommandOutput,
      copyLastCommandOutput,
    );
    add(
      ShellProductivityProductionOperation.saveCommandOutput,
      saveCommandOutput,
    );

    return Map.unmodifiable(callbacks);
  }
}

class ShellProductivityProductionWiring {
  ShellProductivityProductionWiring({
    required ShellProductivityProductionCallbacks callbacks,
    Iterable<ShellProductivityProductionOperation>? requiredOperations,
  }) : _callbacks = callbacks.toCallbacksByOperation(),
       requiredOperations = Set.unmodifiable(
         requiredOperations ?? ShellProductivityProductionOperation.values,
       );

  final Map<
    ShellProductivityProductionOperation,
    ShellProductivityProductionCallback
  >
  _callbacks;
  final Set<ShellProductivityProductionOperation> requiredOperations;

  Set<ShellProductivityProductionOperation> get registeredOperations {
    return _callbacks.keys.toSet();
  }

  Set<ShellProductivityProductionOperation> get missingRequiredOperations {
    return requiredOperations
        .where((operation) => !_callbacks.containsKey(operation))
        .toSet();
  }

  bool get isReady => missingRequiredOperations.isEmpty;

  Future<ShellProductivityBindingResult> run(
    ShellProductivityProductionOperation operation, {
    String? tabId,
    String? paneId,
    String? commandId,
    String? query,
    Object? payload,
  }) async {
    final callback = _callbacks[operation];
    if (callback == null) {
      return ShellProductivityBindingResult.failed(
        failureCode: ShellProductivityBindingFailureCode.unsupported,
        message:
            'No production productivity callback registered for $operation.',
      );
    }
    return callback(
      ShellProductivityBindingContext(
        operation: operation,
        tabId: tabId,
        paneId: paneId,
        commandId: commandId,
        query: query,
        payload: payload,
      ),
    );
  }
}
