import 'dart:async';

import 'shell_action_registry.dart';

typedef ShellActionBinding =
    FutureOr<ShellActionBindingResult> Function(
      ShellActionBindingContext context,
    );

class ShellActionBindingContext {
  const ShellActionBindingContext({
    required this.actionId,
    this.tabId,
    this.paneId,
    this.cwd,
    this.payload,
  });

  final TerminalActionId actionId;
  final String? tabId;
  final String? paneId;
  final String? cwd;
  final Object? payload;
}

class ShellActionBindingResult {
  const ShellActionBindingResult._({
    required this.completed,
    required this.message,
    required this.failureCode,
  });

  const ShellActionBindingResult.completed([String? message])
    : this._(completed: true, message: message, failureCode: null);

  const ShellActionBindingResult.skipped([String? message])
    : this._(
        completed: false,
        message: message,
        failureCode: ShellActionBindingFailureCode.unavailable,
      );

  const ShellActionBindingResult.failed({
    required ShellActionBindingFailureCode failureCode,
    String? message,
  }) : this._(completed: false, message: message, failureCode: failureCode);

  final bool completed;
  final String? message;
  final ShellActionBindingFailureCode? failureCode;

  bool get failed => failureCode != null;
}

enum ShellActionBindingFailureCode {
  unavailable,
  unsupported,
  rejected,
  permissionDenied,
  platformFailure,
}

class ShellActionRuntimeBindings {
  ShellActionRuntimeBindings({
    required Map<TerminalActionId, ShellActionBinding> bindings,
  }) : _bindings = Map.unmodifiable(bindings);

  ShellActionRuntimeBindings.empty() : _bindings = const {};

  final Map<TerminalActionId, ShellActionBinding> _bindings;

  bool contains(TerminalActionId actionId) => _bindings.containsKey(actionId);

  Set<TerminalActionId> get actionIds => _bindings.keys.toSet();

  Set<TerminalActionId> missingActions(Iterable<TerminalActionId> actionIds) {
    return actionIds.where((actionId) => !contains(actionId)).toSet();
  }

  ShellActionRuntimeBindings merge(ShellActionRuntimeBindings other) {
    return ShellActionRuntimeBindings(
      bindings: {..._bindings, ...other._bindings},
    );
  }

  Future<ShellActionBindingResult> run(
    TerminalActionId actionId, {
    String? tabId,
    String? paneId,
    String? cwd,
    Object? payload,
  }) async {
    final binding = _bindings[actionId];
    if (binding == null) {
      return ShellActionBindingResult.failed(
        failureCode: ShellActionBindingFailureCode.unsupported,
        message: 'No production binding registered for $actionId.',
      );
    }
    return binding(
      ShellActionBindingContext(
        actionId: actionId,
        tabId: tabId,
        paneId: paneId,
        cwd: cwd,
        payload: payload,
      ),
    );
  }
}
