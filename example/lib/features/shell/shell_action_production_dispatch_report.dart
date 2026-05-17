import 'shell_action_production_runtime_adapter.dart';
import 'shell_action_registry.dart';
import 'shell_action_runtime_bindings.dart';

class ShellActionProductionDispatchReport {
  const ShellActionProductionDispatchReport({
    required this.actionId,
    required this.readyBeforeDispatch,
    required this.completed,
    required this.failed,
    required this.failureCode,
    required this.message,
  });

  static Future<ShellActionProductionDispatchReport> execute({
    required ShellActionProductionRuntimeAdapter adapter,
    required ShellActionBindingContext context,
  }) async {
    final readyBeforeDispatch = adapter.isReady;
    final result = await adapter.execute(context);

    return ShellActionProductionDispatchReport(
      actionId: context.actionId,
      readyBeforeDispatch: readyBeforeDispatch,
      completed: result.completed,
      failed: result.failed,
      failureCode: result.failureCode,
      message: result.message,
    );
  }

  final TerminalActionId actionId;
  final bool readyBeforeDispatch;
  final bool completed;
  final bool failed;
  final ShellActionBindingFailureCode? failureCode;
  final String? message;

  String get actionName => actionId.name;

  Map<String, Object?> toJson() {
    return {
      'actionId': actionName,
      'readyBeforeDispatch': readyBeforeDispatch,
      'completed': completed,
      'failed': failed,
      'failureCode': failureCode?.name,
      'message': message,
    };
  }
}
