import 'dart:async';

typedef LocalTerminalVisualProductionCallback =
    FutureOr<LocalTerminalVisualBindingResult> Function(
      LocalTerminalVisualBindingContext context,
    );

class LocalTerminalVisualBindingContext {
  const LocalTerminalVisualBindingContext({
    required this.operation,
    this.tabId,
    this.paneId,
    this.themeId,
    this.templateId,
    this.destinationPath,
    this.payload,
  });

  final LocalTerminalVisualProductionOperation operation;
  final String? tabId;
  final String? paneId;
  final String? themeId;
  final String? templateId;
  final String? destinationPath;
  final Object? payload;
}

class LocalTerminalVisualBindingResult {
  const LocalTerminalVisualBindingResult._({
    required this.completed,
    required this.failureCode,
    required this.message,
  });

  const LocalTerminalVisualBindingResult.completed([String? message])
    : this._(completed: true, failureCode: null, message: message);

  const LocalTerminalVisualBindingResult.failed({
    required LocalTerminalVisualBindingFailureCode failureCode,
    String? message,
  }) : this._(completed: false, failureCode: failureCode, message: message);

  final bool completed;
  final LocalTerminalVisualBindingFailureCode? failureCode;
  final String? message;

  bool get failed => failureCode != null;
}

enum LocalTerminalVisualBindingFailureCode {
  unavailable,
  unsupported,
  rejected,
  fileSystemFailure,
  platformFailure,
}

enum LocalTerminalVisualProductionOperation {
  openThemePicker,
  applyTheme,
  importThemePreset,
  exportThemePreset,
  applyLayoutTemplate,
  saveLayoutTemplate,
  exportLayoutTemplate,
  exportScrollback,
  exportCommandOutput,
  applyPaneVisualPolicy,
  applySplitDividerPolicy,
  configureGraphicsStorage,
  recordGraphicsEviction,
  toggleTimestamps,
  toggleCommandPane,
  openScrollbackEditor,
}

class LocalTerminalVisualProductionCallbacks {
  const LocalTerminalVisualProductionCallbacks({
    this.openThemePicker,
    this.applyTheme,
    this.importThemePreset,
    this.exportThemePreset,
    this.applyLayoutTemplate,
    this.saveLayoutTemplate,
    this.exportLayoutTemplate,
    this.exportScrollback,
    this.exportCommandOutput,
    this.applyPaneVisualPolicy,
    this.applySplitDividerPolicy,
    this.configureGraphicsStorage,
    this.recordGraphicsEviction,
    this.toggleTimestamps,
    this.toggleCommandPane,
    this.openScrollbackEditor,
  });

  final LocalTerminalVisualProductionCallback? openThemePicker;
  final LocalTerminalVisualProductionCallback? applyTheme;
  final LocalTerminalVisualProductionCallback? importThemePreset;
  final LocalTerminalVisualProductionCallback? exportThemePreset;
  final LocalTerminalVisualProductionCallback? applyLayoutTemplate;
  final LocalTerminalVisualProductionCallback? saveLayoutTemplate;
  final LocalTerminalVisualProductionCallback? exportLayoutTemplate;
  final LocalTerminalVisualProductionCallback? exportScrollback;
  final LocalTerminalVisualProductionCallback? exportCommandOutput;
  final LocalTerminalVisualProductionCallback? applyPaneVisualPolicy;
  final LocalTerminalVisualProductionCallback? applySplitDividerPolicy;
  final LocalTerminalVisualProductionCallback? configureGraphicsStorage;
  final LocalTerminalVisualProductionCallback? recordGraphicsEviction;
  final LocalTerminalVisualProductionCallback? toggleTimestamps;
  final LocalTerminalVisualProductionCallback? toggleCommandPane;
  final LocalTerminalVisualProductionCallback? openScrollbackEditor;

  Map<
    LocalTerminalVisualProductionOperation,
    LocalTerminalVisualProductionCallback
  >
  toCallbacksByOperation() {
    final callbacks =
        <
          LocalTerminalVisualProductionOperation,
          LocalTerminalVisualProductionCallback
        >{};

    void add(
      LocalTerminalVisualProductionOperation operation,
      LocalTerminalVisualProductionCallback? callback,
    ) {
      if (callback != null) {
        callbacks[operation] = callback;
      }
    }

    add(
      LocalTerminalVisualProductionOperation.openThemePicker,
      openThemePicker,
    );
    add(LocalTerminalVisualProductionOperation.applyTheme, applyTheme);
    add(
      LocalTerminalVisualProductionOperation.importThemePreset,
      importThemePreset,
    );
    add(
      LocalTerminalVisualProductionOperation.exportThemePreset,
      exportThemePreset,
    );
    add(
      LocalTerminalVisualProductionOperation.applyLayoutTemplate,
      applyLayoutTemplate,
    );
    add(
      LocalTerminalVisualProductionOperation.saveLayoutTemplate,
      saveLayoutTemplate,
    );
    add(
      LocalTerminalVisualProductionOperation.exportLayoutTemplate,
      exportLayoutTemplate,
    );
    add(
      LocalTerminalVisualProductionOperation.exportScrollback,
      exportScrollback,
    );
    add(
      LocalTerminalVisualProductionOperation.exportCommandOutput,
      exportCommandOutput,
    );
    add(
      LocalTerminalVisualProductionOperation.applyPaneVisualPolicy,
      applyPaneVisualPolicy,
    );
    add(
      LocalTerminalVisualProductionOperation.applySplitDividerPolicy,
      applySplitDividerPolicy,
    );
    add(
      LocalTerminalVisualProductionOperation.configureGraphicsStorage,
      configureGraphicsStorage,
    );
    add(
      LocalTerminalVisualProductionOperation.recordGraphicsEviction,
      recordGraphicsEviction,
    );
    add(
      LocalTerminalVisualProductionOperation.toggleTimestamps,
      toggleTimestamps,
    );
    add(
      LocalTerminalVisualProductionOperation.toggleCommandPane,
      toggleCommandPane,
    );
    add(
      LocalTerminalVisualProductionOperation.openScrollbackEditor,
      openScrollbackEditor,
    );

    return Map.unmodifiable(callbacks);
  }
}

class LocalTerminalVisualProductionWiring {
  LocalTerminalVisualProductionWiring({
    required LocalTerminalVisualProductionCallbacks callbacks,
    Iterable<LocalTerminalVisualProductionOperation>? requiredOperations,
  }) : _callbacks = callbacks.toCallbacksByOperation(),
       requiredOperations = Set.unmodifiable(
         requiredOperations ?? LocalTerminalVisualProductionOperation.values,
       );

  final Map<
    LocalTerminalVisualProductionOperation,
    LocalTerminalVisualProductionCallback
  >
  _callbacks;
  final Set<LocalTerminalVisualProductionOperation> requiredOperations;

  Set<LocalTerminalVisualProductionOperation> get registeredOperations {
    return _callbacks.keys.toSet();
  }

  Set<LocalTerminalVisualProductionOperation> get missingRequiredOperations {
    return requiredOperations
        .where((operation) => !_callbacks.containsKey(operation))
        .toSet();
  }

  bool get isReady => missingRequiredOperations.isEmpty;

  Future<LocalTerminalVisualBindingResult> run(
    LocalTerminalVisualProductionOperation operation, {
    String? tabId,
    String? paneId,
    String? themeId,
    String? templateId,
    String? destinationPath,
    Object? payload,
  }) async {
    final callback = _callbacks[operation];
    if (callback == null) {
      return LocalTerminalVisualBindingResult.failed(
        failureCode: LocalTerminalVisualBindingFailureCode.unsupported,
        message: 'No production visual callback registered for $operation.',
      );
    }
    return callback(
      LocalTerminalVisualBindingContext(
        operation: operation,
        tabId: tabId,
        paneId: paneId,
        themeId: themeId,
        templateId: templateId,
        destinationPath: destinationPath,
        payload: payload,
      ),
    );
  }
}
