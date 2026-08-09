import 'shell_action_production_wiring_state.dart';
import 'shell_action_registry.dart';
import 'shell_action_runtime_bindings.dart';

class ShellActionProductionExecutor {
  const ShellActionProductionExecutor({required this.wiringState});

  final ShellActionProductionWiringState wiringState;

  bool get isReady => wiringState.isReady;

  Future<ShellActionProductionExecutionResult> execute(
    TerminalActionId actionId, {
    String? tabId,
    String? paneId,
    String? cwd,
    Object? payload,
  }) async {
    if (!wiringState.isReady) {
      return ShellActionProductionExecutionResult.failed(
        actionId: actionId,
        bindingResult: ShellActionBindingResult.failed(
          failureCode: ShellActionBindingFailureCode.unavailable,
          message: _blockingDiagnosticMessage(),
        ),
      );
    }

    try {
      final bindingResult = await wiringState.run(
        actionId,
        tabId: tabId,
        paneId: paneId,
        cwd: cwd,
        payload: payload,
      );
      return ShellActionProductionExecutionResult(
        actionId: actionId,
        bindingResult: bindingResult,
      );
    } on Object catch (error) {
      return ShellActionProductionExecutionResult.failed(
        actionId: actionId,
        bindingResult: ShellActionBindingResult.failed(
          failureCode: ShellActionBindingFailureCode.platformFailure,
          message: error.toString(),
        ),
        error: error,
      );
    }
  }

  String _blockingDiagnosticMessage() {
    final diagnostics = wiringState.blockingDiagnostics;
    if (diagnostics.isEmpty) {
      return 'Production action wiring is not ready.';
    }
    return diagnostics.map((item) => item.description).join('\n');
  }
}

class ShellActionProductionExecutionResult {
  const ShellActionProductionExecutionResult({
    required this.actionId,
    required this.bindingResult,
    this.error,
  });

  const ShellActionProductionExecutionResult.failed({
    required this.actionId,
    required this.bindingResult,
    this.error,
  });

  final TerminalActionId actionId;
  final ShellActionBindingResult bindingResult;
  final Object? error;

  bool get completed => bindingResult.completed;

  bool get failed => bindingResult.failed || error != null;

  String? get message => bindingResult.message;

  ShellActionBindingFailureCode? get failureCode {
    return bindingResult.failureCode;
  }
}
