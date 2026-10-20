part of 'terminal_ai_controller.dart';

/// A provider's writing call ID identifies one operation for this task. Keep
/// its first result even after rejection, pause, host editing or receipt loss.
class _AiApiOperation {
  _AiApiOperation(this.action, this.input, this.target);

  final AiAction action;
  final String input;
  final AiTerminalContext? target;
  String? result;
  String? resultEntryId;
}

extension _TerminalAiApiOperations on TerminalAiController {
  String _apiOperationInput(AiAction action) => jsonEncode({
    'kind': action.kind.name,
    'reason': action.reason,
    if (action.kind == AiActionKind.runCommand) 'command': action.command,
    if (action.kind == AiActionKind.sendKeys)
      'keys': [
        for (final stroke in action.keys)
          if (stroke.key != null)
            {'key': stroke.key}
          else
            {'text': stroke.text},
      ],
  });

  /// Null means a genuinely new operation that still needs normal approval.
  Map<String, Object?>? _registerApiOperation(
    AiAction action,
    AiTerminalContext? target,
  ) {
    final input = _apiOperationInput(action);
    final original = _task.apiOperations[action.id];
    if (original == null) {
      _task.apiOperations[action.id] = _AiApiOperation(action, input, target);
      return null;
    }
    final receipt = _apiOperationReceipt(original);
    if (original.input != input) {
      return {
        'error': 'operation_id_conflict',
        'rejected': true,
        'original_result': receipt,
        'instruction':
            'This call ID already identifies a different writing operation. '
            'No input was sent for the conflicting call. Inspect the original '
            'receipt; do not resend it. A distinct intended operation requires '
            'a fresh call ID and normal approval.',
      };
    }
    return receipt;
  }

  void _rememberApiOperationResult(AiAction action, String content) {
    final operation = _task.apiOperations[action.id];
    if (operation == null || operation.result != null || !action.writesInput) {
      return;
    }
    final entry = _transcript
        .where(
          (entry) =>
              (entry.role == 'proposal' || entry.role == 'tool') &&
              identical(entry.action, action),
        )
        .lastOrNull;
    if (entry == null) return;
    // The host may have edited the proposal while retaining its operation ID.
    // That actual approved action is recorded in the original result; neither
    // its pre-edit input nor a provider retry creates another submission.
    operation.result = content;
    operation.resultEntryId = entry.id;
  }

  Map<String, Object?> _apiOperationReceipt(_AiApiOperation operation) {
    final entry = _transcript
        .where(
          (entry) => operation.resultEntryId == null
              ? identical(entry.action, operation.action)
              : entry.id == operation.resultEntryId,
        )
        .lastOrNull;
    return {
      if (operation.result case final content?)
        ...jsonDecode(content) as Map<String, Object?>,
      'operation_replayed': true,
      // Scope retained/unmapped evidence to its original source, even when
      // this reply is requested after reconnect or explicit target selection.
      if (operation.target case final target?) ...{
        'source_session_id': target.sessionId,
        'source_context_id': target.contextId,
      },
      // Reconciliation may have resolved the original unknown receipt since
      // its first tool response. Preserve that submission identity and expose
      // the new observation without dispatching the input again.
      'state': entry?.state.name ?? 'unknown',
      'submission_id': ?entry?.submissionId,
      'block_id': ?entry?.blockId,
      if (entry?.inputProgress case final progress?)
        'input_progress': progress.toJson(entry!.action!),
      'instruction':
          'This is the original operation and its recorded receipt. No new '
          'input was sent. Input acceptance does not prove command success. '
          'Observe existing output; do not replay this operation.',
    };
  }
}
