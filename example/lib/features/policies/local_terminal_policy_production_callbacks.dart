import 'dart:async';

typedef LocalTerminalPolicyProductionCallback =
    FutureOr<LocalTerminalPolicyBindingResult> Function(
      LocalTerminalPolicyBindingContext context,
    );

class LocalTerminalPolicyBindingContext {
  const LocalTerminalPolicyBindingContext({
    required this.operation,
    this.tabId,
    this.paneId,
    this.text,
    this.payload,
  });

  final LocalTerminalPolicyProductionOperation operation;
  final String? tabId;
  final String? paneId;
  final String? text;
  final Object? payload;
}

class LocalTerminalPolicyBindingResult {
  const LocalTerminalPolicyBindingResult._({
    required this.completed,
    required this.failureCode,
    required this.message,
  });

  const LocalTerminalPolicyBindingResult.completed([String? message])
    : this._(completed: true, failureCode: null, message: message);

  const LocalTerminalPolicyBindingResult.failed({
    required LocalTerminalPolicyBindingFailureCode failureCode,
    String? message,
  }) : this._(completed: false, failureCode: failureCode, message: message);

  final bool completed;
  final LocalTerminalPolicyBindingFailureCode? failureCode;
  final String? message;

  bool get failed => failureCode != null;
}

enum LocalTerminalPolicyBindingFailureCode {
  unavailable,
  unsupported,
  rejected,
  permissionDenied,
  platformFailure,
}

enum LocalTerminalPolicyProductionOperation {
  copy,
  paste,
  pasteHistory,
  pasteAsBracketed,
  confirmLargePaste,
  confirmMultilinePaste,
  recordPasteHistory,
  osc52Copy,
  emitBellNotification,
  emitCommandFinishedNotification,
  emitActivityNotification,
  emitSilenceNotification,
  emitPromptReadyNotification,
  toggleHotkeyWindow,
  applyHotkeyWindowConfig,
  recordHotkeyWindowFailure,
}

class LocalTerminalPolicyProductionCallbacks {
  const LocalTerminalPolicyProductionCallbacks({
    this.copy,
    this.paste,
    this.pasteHistory,
    this.pasteAsBracketed,
    this.confirmLargePaste,
    this.confirmMultilinePaste,
    this.recordPasteHistory,
    this.osc52Copy,
    this.emitBellNotification,
    this.emitCommandFinishedNotification,
    this.emitActivityNotification,
    this.emitSilenceNotification,
    this.emitPromptReadyNotification,
    this.toggleHotkeyWindow,
    this.applyHotkeyWindowConfig,
    this.recordHotkeyWindowFailure,
  });

  final LocalTerminalPolicyProductionCallback? copy;
  final LocalTerminalPolicyProductionCallback? paste;
  final LocalTerminalPolicyProductionCallback? pasteHistory;
  final LocalTerminalPolicyProductionCallback? pasteAsBracketed;
  final LocalTerminalPolicyProductionCallback? confirmLargePaste;
  final LocalTerminalPolicyProductionCallback? confirmMultilinePaste;
  final LocalTerminalPolicyProductionCallback? recordPasteHistory;
  final LocalTerminalPolicyProductionCallback? osc52Copy;
  final LocalTerminalPolicyProductionCallback? emitBellNotification;
  final LocalTerminalPolicyProductionCallback? emitCommandFinishedNotification;
  final LocalTerminalPolicyProductionCallback? emitActivityNotification;
  final LocalTerminalPolicyProductionCallback? emitSilenceNotification;
  final LocalTerminalPolicyProductionCallback? emitPromptReadyNotification;
  final LocalTerminalPolicyProductionCallback? toggleHotkeyWindow;
  final LocalTerminalPolicyProductionCallback? applyHotkeyWindowConfig;
  final LocalTerminalPolicyProductionCallback? recordHotkeyWindowFailure;

  Map<
    LocalTerminalPolicyProductionOperation,
    LocalTerminalPolicyProductionCallback
  >
  toCallbacksByOperation() {
    final callbacks =
        <
          LocalTerminalPolicyProductionOperation,
          LocalTerminalPolicyProductionCallback
        >{};

    void add(
      LocalTerminalPolicyProductionOperation operation,
      LocalTerminalPolicyProductionCallback? callback,
    ) {
      if (callback != null) {
        callbacks[operation] = callback;
      }
    }

    add(LocalTerminalPolicyProductionOperation.copy, copy);
    add(LocalTerminalPolicyProductionOperation.paste, paste);
    add(LocalTerminalPolicyProductionOperation.pasteHistory, pasteHistory);
    add(
      LocalTerminalPolicyProductionOperation.pasteAsBracketed,
      pasteAsBracketed,
    );
    add(
      LocalTerminalPolicyProductionOperation.confirmLargePaste,
      confirmLargePaste,
    );
    add(
      LocalTerminalPolicyProductionOperation.confirmMultilinePaste,
      confirmMultilinePaste,
    );
    add(
      LocalTerminalPolicyProductionOperation.recordPasteHistory,
      recordPasteHistory,
    );
    add(LocalTerminalPolicyProductionOperation.osc52Copy, osc52Copy);
    add(
      LocalTerminalPolicyProductionOperation.emitBellNotification,
      emitBellNotification,
    );
    add(
      LocalTerminalPolicyProductionOperation.emitCommandFinishedNotification,
      emitCommandFinishedNotification,
    );
    add(
      LocalTerminalPolicyProductionOperation.emitActivityNotification,
      emitActivityNotification,
    );
    add(
      LocalTerminalPolicyProductionOperation.emitSilenceNotification,
      emitSilenceNotification,
    );
    add(
      LocalTerminalPolicyProductionOperation.emitPromptReadyNotification,
      emitPromptReadyNotification,
    );
    add(
      LocalTerminalPolicyProductionOperation.toggleHotkeyWindow,
      toggleHotkeyWindow,
    );
    add(
      LocalTerminalPolicyProductionOperation.applyHotkeyWindowConfig,
      applyHotkeyWindowConfig,
    );
    add(
      LocalTerminalPolicyProductionOperation.recordHotkeyWindowFailure,
      recordHotkeyWindowFailure,
    );

    return Map.unmodifiable(callbacks);
  }
}

class LocalTerminalPolicyProductionWiring {
  LocalTerminalPolicyProductionWiring({
    required LocalTerminalPolicyProductionCallbacks callbacks,
    Iterable<LocalTerminalPolicyProductionOperation>? requiredOperations,
  }) : _callbacks = callbacks.toCallbacksByOperation(),
       requiredOperations = Set.unmodifiable(
         requiredOperations ?? LocalTerminalPolicyProductionOperation.values,
       );

  final Map<
    LocalTerminalPolicyProductionOperation,
    LocalTerminalPolicyProductionCallback
  >
  _callbacks;
  final Set<LocalTerminalPolicyProductionOperation> requiredOperations;

  Set<LocalTerminalPolicyProductionOperation> get registeredOperations {
    return _callbacks.keys.toSet();
  }

  Set<LocalTerminalPolicyProductionOperation> get missingRequiredOperations {
    return requiredOperations
        .where((operation) => !_callbacks.containsKey(operation))
        .toSet();
  }

  bool get isReady => missingRequiredOperations.isEmpty;

  Future<LocalTerminalPolicyBindingResult> run(
    LocalTerminalPolicyProductionOperation operation, {
    String? tabId,
    String? paneId,
    String? text,
    Object? payload,
  }) async {
    final callback = _callbacks[operation];
    if (callback == null) {
      return LocalTerminalPolicyBindingResult.failed(
        failureCode: LocalTerminalPolicyBindingFailureCode.unsupported,
        message: 'No production policy callback registered for $operation.',
      );
    }
    return callback(
      LocalTerminalPolicyBindingContext(
        operation: operation,
        tabId: tabId,
        paneId: paneId,
        text: text,
        payload: payload,
      ),
    );
  }
}
