part of 'terminal_ai_controller.dart';

extension _TerminalAiApproval on TerminalAiController {
  /// One decision is bound to a task, exact proposal revision, connection and
  /// observed terminal guard. No cache or command-prefix permission is created.
  Future<int?> _reviewPending(AiCancellation cancellation) async {
    final configuration = settings.configuration;
    if (configuration?.approvalMode != AiApprovalMode.smart) {
      if (pending case final action?) {
        _updateActionEntry(
          action,
          AiEntryState.proposed,
          approvalReview: AiModelActionReviewer.ask(
            'Confirm every command is selected. Enable Smart review in AI connection settings for automatic low-risk review.',
            'manual',
          ),
        );
      }
      _emit();
      return null;
    }
    final task = _task;
    final action = pending;
    final expected = task.proposalContext;
    final revision = task.revision;
    final connectionRevision = _connectionRevision;
    if (action == null || expected == null) return null;
    phase = AiPhase.reviewing;
    _emit();
    AiApprovalReview review;
    try {
      review = await reviewer.review(
        configuration: configuration!,
        action: action,
        target: expected,
        userRequests: [
          for (final entry in task.transcript)
            if (entry.role == 'user') entry.text,
        ],
        cancellation: cancellation,
      );
    } on Object {
      review = AiModelActionReviewer.ask(
        'Automatic review was unavailable.',
        'unavailable',
      );
    }
    if (_disposed ||
        cancellation.isCancelled ||
        !identical(task, _task) ||
        !identical(pending, action) ||
        task.revision != revision ||
        connectionRevision != _connectionRevision ||
        !identical(settings.configuration, configuration)) {
      return null;
    }
    // Read again after inference: a node/lease/cwd change revokes the proposal,
    // rather than blessing an old command with a new target.
    try {
      final fresh = await terminal.readContext();
      cancellation.check();
      if (!identical(task, _task) || !identical(pending, action)) return null;
      if (fresh.guard != expected.guard ||
          _differentTarget(task.target, fresh)) {
        _resolvePending('Terminal changed during automatic review.');
        cancellation.cancel();
        context = fresh;
        phase = AiPhase.idle;
        takenOver = true;
        _emit();
        return null;
      }
    } on Object catch (failure) {
      _fail(failure, cancellation);
      return null;
    }
    _updateActionEntry(action, AiEntryState.proposed, approvalReview: review);
    phase = AiPhase.awaitingApproval;
    _emit();
    return review.automatic &&
            canApprove &&
            identical(pending, action) &&
            identical(task, _task) &&
            task.revision == revision &&
            !cancellation.isCancelled
        ? revision
        : null;
  }
}
