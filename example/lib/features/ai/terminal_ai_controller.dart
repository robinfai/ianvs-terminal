import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart'
    show
        InputIntent,
        InputIntentChoice,
        InputIntentContext,
        InputIntentDecision,
        InputIntentState;

import 'acp/agent_backend.dart';
import 'acp/codex_acp_backend.dart';
import 'ai_api_client.dart';
import 'ai_approval.dart';
import 'ai_models.dart';
import 'ai_settings.dart';

part 'terminal_ai_acp.dart';
part 'terminal_ai_api_operations.dart';
part 'terminal_ai_approval.dart';

abstract interface class AiTerminalPort {
  Future<AiTerminalContext> readContext();
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  );
  Stream<void> get userInput;
  void dispose();
}

/// Optional read-only capability. It never falls back to shell commands.
abstract interface class AiBlockReader {
  Future<AiBlockContext> readBlockRange(
    String blockId, {
    required int startLine,
    required int lineCount,
    required AiTerminalContext expected,
  });
}

abstract interface class AiSubmissionInspector {
  String? submissionFor(String actionId);
  Future<Map<String, Object?>> inspectSubmission(String id);
}

abstract interface class AiKeyInputInspector {
  AiKeyInputProgress? keyInputProgress(AiAction action);
}

abstract interface class AiConnectionSources {
  Set<String> get sourceSessionIds;
}

abstract interface class AiSourceSubmissionInspector {
  Future<Map<String, Object?>> inspectSourceSubmission(
    String id,
    String sessionId,
  );
}

/// An explicit UI approval is valid only while its pane/focus epoch remains
/// active. Runtime checks this again after each asynchronous read, before input.
class _AiApprovalCancellation extends AiCancellation {
  _AiApprovalCancellation(this.parent, this.canSubmit);
  final AiCancellation parent;
  final bool Function() canSubmit;

  @override
  bool get isCancelled => parent.isCancelled || !canSubmit();

  @override
  void check() {
    parent.check();
    if (!canSubmit()) throw const AiFailure('approval_inactive');
  }
}

enum AiPhase {
  idle,
  thinking,
  reviewing,
  awaitingApproval,
  executing,
  observing,
  failed,
}

enum AiEntryState {
  message,
  deferred,
  proposed,
  submitted,
  accepted,
  interrupted,
  unknown,
  rejected,
  revoked,
}

class AiTranscriptEntry {
  const AiTranscriptEntry(
    this.role,
    this.text, {
    this.id = '',
    this.contexts = const [],
    this.action,
    this.target,
    this.state = AiEntryState.message,
    this.revision = 0,
    this.submissionId,
    this.blockId,
    this.statusReason,
    this.suppliedEvidence,
    this.approvalReview,
    this.inputProgress,
  });
  final String id;
  final String role;
  final String text;
  final List<AiBlockContext> contexts;
  final AiAction? action;
  final AiTerminalContext? target;
  final AiEntryState state;
  final int revision;
  final String? submissionId;
  final String? blockId;
  final String? statusReason;
  final List<AiEvidenceRange>? suppliedEvidence;
  final AiApprovalReview? approvalReview;
  final AiKeyInputProgress? inputProgress;
}

@immutable
class AiTaskSummary {
  const AiTaskSummary(
    this.id,
    this.title,
    this.phase,
    this.paused, {
    this.followUpEnded = false,
    this.hasUnresolvedSubmission = false,
    this.unresolvedEntryIds = const [],
    this.attachments = const [],
    this.draft = '',
    this.draftRevision = 0,
    this.proposalRevision = 0,
  });
  final String id;
  final String title;
  final AiPhase phase;
  final bool paused;
  final bool followUpEnded;
  final bool hasUnresolvedSubmission;
  final List<String> unresolvedEntryIds;
  final List<AiBlockContext> attachments;
  final String draft;
  final int draftRevision;
  final int proposalRevision;
}

class _AiDraftAttachment {
  _AiDraftAttachment(this.context);
  final AiBlockContext context;
}

class _AiTask {
  _AiTask(this.id);
  final String id;
  String title = '';
  String draft = '';
  int draftRevision = 0;
  bool retainedAiIntent = false;
  final inputIntent = InputIntentState(defaultIntent: InputIntent.ai);
  double readingOffset = 0;
  ({String id, double offset})? readingAnchor;
  bool followingOutput = true;
  DateTime? waitStartedAt;
  DateTime? lastOutputAt;
  final messages = <Map<String, Object?>>[];
  final transcript = <AiTranscriptEntry>[];
  final attachments = <_AiDraftAttachment>[];
  AiPhase phase = AiPhase.idle;
  AiAction? pending;
  AiAction? executing;
  AiTerminalContext? context;
  AiTerminalContext? target;
  AiTerminalContext? proposalContext;
  String? error;
  String? terminalError;
  Future<void>? contextRefresh;
  bool takenOver = false;
  int revision = 0;
  AgentBackend? agent;
  Object? agentTurn;
  Completer<void>? agentToolDone;
  Completer<void>? agentYield;
  Completer<Map<String, Object?>>? agentReply;
  int observation = 0;
  String? observationVersion;
  AiTerminalContext? observationContext;
  String? agentTextId;
  final agentOperations = <String, ({String input, AiAction action})>{};
  final agentResults = <String, Map<String, Object?>>{};
  final apiOperations = <String, _AiApiOperation>{};
  final agentEvidence = <AiEvidenceRange>{};
  final suppliedMessages = Set<Map<String, Object?>>.identity();
  final suppliedSourceBases = <(String, String), int?>{};
  bool agentToolBusy = false;
  bool configurationRetired = false;
  bool followUpEnded = false;

  void updateDraft(String value) {
    if (draft == value) return;
    draft = value;
    draftRevision++;
    if (value.isEmpty) retainedAiIntent = false;
  }
}

/// Session-local tasks share one PTY. Model writes require [approve]; an explicit
/// human command submitted in this view uses [runUserCommand] without inference.
/// Inference cancellation, manual input and session guards revoke old proposals.
class TerminalAiController extends ChangeNotifier {
  TerminalAiController({
    required this.settings,
    required this.terminal,
    AiApi? api,
    AgentBackendFactory? agentFactory,
    AiActionReviewer? reviewer,
    this.onAgentEvent,
    this.maxSteps = 24,
  }) : assert(maxSteps > 0, 'maxSteps must be positive'),
       api = api ?? const AiApiClient(),
       reviewer = reviewer ?? AiModelActionReviewer(),
       agentFactory = agentFactory ?? CodexAcpBackend.new {
    _tasks.add(_task);
    _lastConfiguration = settings.configuration;
    _inputSubscription = terminal.userInput.listen((_) => takeOver());
    settings.addListener(_configurationChanged);
  }
  final AiSettingsController settings;
  final AiTerminalPort terminal;
  final AiApi api;
  final AiActionReviewer reviewer;
  final AgentBackendFactory agentFactory;
  final AgentEventHandler? onAgentEvent;

  /// Hosts running long, supervised tasks may provide a larger turn budget.
  /// This never changes the requirement to approve each writing action.
  final int maxSteps;
  late final StreamSubscription<void> _inputSubscription;
  final _tasks = <_AiTask>[];
  _AiTask _task = _AiTask('task-1');
  int _taskSerial = 1;
  int _entrySerial = 0;
  int _connectionRevision = 0;
  AiConfiguration? _lastConfiguration;

  void prepareForConnectionChange() {
    takeOver();
    _connectionRevision++;
    for (final task in _tasks) {
      task.contextRefresh = null;
      task.terminalError = 'session_unavailable';
      task.takenOver = task.transcript.any((e) => e.role == 'user');
    }
    _emit();
  }

  List<Map<String, Object?>> get _messages => _task.messages;
  List<AiTranscriptEntry> get _transcript => _task.transcript;
  List<AiTranscriptEntry> get transcript => List.unmodifiable(_transcript);
  String get taskId => _task.id;
  String get taskTitle => _task.title;
  List<AiTaskSummary> get tasks => List.unmodifiable(
    _tasks.map(
      (task) => AiTaskSummary(
        task.id,
        task.title,
        task.phase,
        task.takenOver,
        followUpEnded: task.followUpEnded,
        hasUnresolvedSubmission: task.transcript.any(
          (entry) => entry.state == AiEntryState.unknown,
        ),
        unresolvedEntryIds: List.unmodifiable(
          task.transcript
              .where((entry) => entry.state == AiEntryState.unknown)
              .map((entry) => entry.id),
        ),
        attachments: List.unmodifiable(
          task.attachments.map((attachment) => attachment.context),
        ),
        draft: task.draft,
        draftRevision: task.draftRevision,
        proposalRevision: task.revision,
      ),
    ),
  );
  String get draft => _task.draft;
  int get draftRevision => _task.draftRevision;
  double get readingOffset => _task.readingOffset;
  set readingOffset(double value) => _task.readingOffset = value;
  ({String id, double offset})? get readingAnchor => _task.readingAnchor;
  set readingAnchor(({String id, double offset})? value) =>
      _task.readingAnchor = value;
  bool get followingOutput => _task.followingOutput;
  set followingOutput(bool value) => _task.followingOutput = value;
  List<AiBlockContext> get attachments => List.unmodifiable(
    _task.attachments.map((attachment) => attachment.context),
  );
  AiPhase get phase => _task.phase;
  set phase(AiPhase value) => _task.phase = value;
  AiAction? get pending => _task.pending;
  set pending(AiAction? value) => _task.pending = value;
  AiAction? get _executingAction => _task.executing;
  set _executingAction(AiAction? value) => _task.executing = value;
  AiTerminalContext? get context => _task.context;
  set context(AiTerminalContext? value) => _task.context = value;
  String? get error => _task.error;
  set error(String? value) => _task.error = value;
  String? get terminalError => _task.terminalError;
  bool get checkingTerminal => _task.contextRefresh != null;
  bool get hasUnresolvedSubmission =>
      _transcript.any((entry) => entry.state == AiEntryState.unknown);
  bool get hasDeferredSupplement =>
      _transcript.any((entry) => entry.state == AiEntryState.deferred);
  bool get followUpEnded => _task.followUpEnded;
  bool get canEndFollowUp => _canInteract && !busy && hasUnresolvedSubmission;
  bool get takenOver => _task.takenOver;
  set takenOver(bool value) => _task.takenOver = value;
  int get proposalRevision => _task.revision;
  AiTerminalContext? get proposalTarget => _task.proposalContext;
  AiTerminalContext? get originalTarget => _task.target;
  bool get targetChanged => _differentTarget(_task.target, context);
  bool retainsSource(String sessionId) =>
      terminal is AiConnectionSources &&
      (terminal as AiConnectionSources).sourceSessionIds.contains(sessionId);
  DateTime? get waitStartedAt => _task.waitStartedAt;
  DateTime? get lastOutputAt => _task.lastOutputAt;
  bool _interrupting = false;
  bool get interrupting => _interrupting;
  AiCancellation? _interruptCancellation;
  bool get canInterrupt =>
      _canInteract &&
      !_interrupting &&
      terminalError == null &&
      context != null &&
      context!.runningCommand != null &&
      !context!.canRunCommand &&
      !context!.readOnly;

  bool _differentTarget(AiTerminalContext? a, AiTerminalContext? b) =>
      a != null &&
      b != null &&
      (a.sessionId != b.sessionId ||
          a.contextId != b.contextId ||
          (a.cwd.isNotEmpty && b.cwd.isNotEmpty && a.cwd != b.cwd));

  void _adoptApprovedDirectory(AiTerminalContext fresh) {
    final original = _task.target;
    final block = fresh.lastBlock;
    if (takenOver ||
        _cancellation?.isCancelled != false ||
        original == null ||
        original.sessionId != fresh.sessionId ||
        original.contextId != fresh.contextId ||
        original.cwd == fresh.cwd ||
        block?.id == null ||
        (block!.sourceSessionId != null &&
            block.sourceSessionId != fresh.sessionId) ||
        (block.sourceContextId != null &&
            block.sourceContextId != fresh.contextId)) {
      return;
    }
    // The shell's cwd notification may arrive after the accepted receipt or
    // even after command completion. Only active observations correlated to
    // this task's accepted block can advance its directory. User input cancels
    // inference; a different session/node must still be explicitly selected.
    if (_transcript.any(
      (entry) =>
          entry.state == AiEntryState.accepted &&
          entry.blockId == block.id &&
          entry.target?.sessionId == fresh.sessionId &&
          entry.target?.contextId == fresh.contextId,
    )) {
      _task.target = fresh;
    }
  }

  void setDraft(String value, {bool composing = false}) {
    if (_task.draft == value) {
      // IME commit can change only the composing range. Publish the committed
      // intent before Enter rather than waiting for the periodic context poll.
      final before = _task.inputIntent.decision;
      final next = inputIntentDecision(composing: composing);
      if (before.intent != next.intent || before.source != next.source) _emit();
      return;
    }
    _task.updateDraft(value);
    inputIntentDecision(composing: composing);
    _emit();
  }

  InputIntentChoice get inputIntentChoice => _task.inputIntent.choice;

  InputIntentContext get _inputIntentContext => InputIntentContext(
    scope: context == null ? '' : '${context!.sessionId}:${context!.contextId}',
    commandNames: context?.commandNames ?? const {},
    aliases: context?.aliases ?? const {},
    agentFollowUp: _transcript.any((e) => e.role == 'assistant'),
    awaitingAnswer:
        _transcript.lastOrNull?.role == 'assistant' &&
        RegExp(r'[?？]\s*$').hasMatch(_transcript.last.text),
  );

  bool _agentOwnsInput({InputIntentChoice? previewChoice}) =>
      busy ||
      pending != null ||
      _task.attachments.isNotEmpty ||
      context?.alternateScreen == true ||
      (_task.retainedAiIntent && previewChoice != InputIntentChoice.command);

  InputIntentDecision inputIntentDecision({bool composing = false}) =>
      _task.inputIntent.update(
        draft,
        context: _inputIntentContext,
        composing: composing,
        agentOwnsInput: _agentOwnsInput(),
      );

  InputIntentDecision previewInputIntent(
    String text,
    InputIntentChoice choice, {
    bool composing = false,
  }) => _task.inputIntent.preview(
    text,
    choice: choice,
    context: _inputIntentContext,
    composing: composing,
    agentOwnsInput: _agentOwnsInput(previewChoice: choice),
  );

  void chooseInputIntent(InputIntentChoice choice) {
    if (choice == InputIntentChoice.command) _task.retainedAiIntent = false;
    _task.inputIntent.choice = choice;
    _emit();
  }

  bool get canRunUserCommand =>
      _canInteract &&
      !busy &&
      pending == null &&
      attachments.isEmpty &&
      !_task.retainedAiIntent &&
      !hasUnresolvedSubmission &&
      !targetChanged &&
      terminalError == null &&
      context?.canRunCommand == true;

  /// Enter on a visible Command draft is the user's execution request. It does
  /// not create a model turn or approve any pending agent action. The native
  /// port still validates the displayed target/lease and records a receipt.
  Future<void> runUserCommand(String command) async {
    if (!canRunUserCommand || command.trim().isEmpty) return;
    final expected = context!;
    final task = _task;
    _task.target ??= expected;
    final originalDraftRevision = draftRevision;
    final action = AiAction(
      id: 'human-${++_entrySerial}',
      kind: AiActionKind.runCommand,
      command: command,
      reason: 'Command entered by the user',
      rawCall: const {},
    );
    _cancellation?.cancel();
    final cancellation = _cancellation = AiCancellation();
    _executingAction = action;
    takenOver = false;
    phase = AiPhase.executing;
    error = null;
    _transcript.add(
      AiTranscriptEntry(
        'user',
        command,
        id: 'entry-${++_entrySerial}',
        action: action,
        target: expected,
        state: AiEntryState.submitted,
      ),
    );
    _emit();
    try {
      final result = await terminal.execute(action, expected, cancellation);
      if (_disposed ||
          !identical(task, _task) ||
          !identical(_executingAction, action)) {
        return;
      }
      _executingAction = null;
      _updateActionEntry(
        action,
        AiEntryState.accepted,
        submissionId: result['submission_id'] as String?,
        blockId: result['block_id'] as String?,
      );
      // Preserve manual command context for a subsequent question, without
      // fabricating an assistant tool call or sending a request right now.
      _messages.add({
        'role': 'user',
        'content': jsonEncode({
          'user_terminal_command': command,
          'result': result,
        }),
      });
      if (draftRevision == originalDraftRevision) {
        _task.updateDraft('');
        _task.inputIntent.reset();
      }
      phase = AiPhase.idle;
      _emit();
      await refreshContext();
    } on Object catch (failure) {
      if (_disposed ||
          !identical(task, _task) ||
          !identical(_executingAction, action)) {
        return;
      }
      _executingAction = null;
      final rejected =
          failure is AiFailure &&
          {
            'stale_context',
            'shell_not_ready',
            'read_only',
            'submission_rejected',
            'session_unavailable',
          }.contains(failure.code);
      _updateActionEntry(
        action,
        rejected ? AiEntryState.revoked : AiEntryState.unknown,
        submissionId: _submissionFor(action),
      );
      _fail(failure, cancellation);
    }
  }

  void attachContext(AiBlockContext block) {
    if (_disposed) return;
    // Attachments are immutable snapshots, distinct from live output.
    _task.attachments.removeWhere((attachment) {
      final previous = attachment.context;
      return previous.id == block.id &&
          previous.sourceSessionId == block.sourceSessionId &&
          previous.sourceContextId == block.sourceContextId &&
          previous.sourceLineBase == block.sourceLineBase &&
          previous.selectionKey == block.selectionKey &&
          previous.command == block.command;
    });
    if (_task.attachments.length >= 8) {
      error = 'context_limit';
      _emit();
      return;
    }
    _task.attachments.add(_AiDraftAttachment(block));
    _emit();
  }

  void removeAttachment(int index) {
    if (index < 0 || index >= _task.attachments.length) return;
    _task.retainedAiIntent = true;
    _task.attachments.removeAt(index);
    _emit();
  }

  void newTask() {
    takeOver();
    _cancellation?.cancel();
    _task = _AiTask('task-${++_taskSerial}');
    _tasks.add(_task);
    _emit();
  }

  void selectTask(String id) {
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task == null || identical(task, _task)) return;
    takeOver();
    _cancellation?.cancel();
    _task = task;
    _emit();
    // Switching never starts inference or restores an old approval.
    unawaited(refreshContext());
  }

  Future<void> supplement(String requirement) async {
    if (!_canInteract || requirement.trim().isEmpty) return;
    takeOver();
    if (hasUnresolvedSubmission) {
      // The command may already have run. Save the user's new constraint as
      // explicitly unsent; a receipt check alone must not start inference.
      final prompt = requirement.trim();
      _task.updateDraft(requirement);
      final deferred = _transcript.where(
        (entry) => entry.state == AiEntryState.deferred,
      );
      if (prompt.length + deferred.fold(0, (n, e) => n + e.text.length) >
          16000) {
        error = 'prompt_too_large';
      } else if (attachments.length +
              deferred.fold(0, (n, e) => n + e.contexts.length) >
          8) {
        error = 'context_limit';
      } else {
        _transcript.add(
          AiTranscriptEntry(
            'user',
            prompt,
            id: 'entry-${++_entrySerial}',
            contexts: [
              for (final block in attachments)
                context == null ? block : block.withFallbackSource(context!),
            ],
            target: context,
            state: AiEntryState.deferred,
          ),
        );
        _task.updateDraft('');
        _task.attachments.clear();
        error = 'submission_unknown';
      }
      _emit();
      return;
    }
    await ask(requirement);
  }

  void discardDeferredSupplement(String entryId) {
    if (!_canInteract || busy) return;
    final index = _transcript.indexWhere(
      (entry) => entry.id == entryId && entry.state == AiEntryState.deferred,
    );
    if (index < 0) return;
    final entry = _transcript[index];
    _transcript[index] = AiTranscriptEntry(
      entry.role,
      entry.text,
      id: entry.id,
      contexts: entry.contexts,
      target: entry.target,
      state: AiEntryState.revoked,
      statusReason: 'The saved requirement was discarded without sending.',
    );
    _emit();
  }

  /// Ends AI follow-up, not the remote command. Unknown receipts remain true
  /// historical facts; only a separately created task may start new work.
  void endFollowUp() {
    if (!canEndFollowUp) return;
    _cancellation?.cancel();
    _task.followUpEnded = true;
    phase = AiPhase.idle;
    takenOver = true;
    error = null;
    _emit();
  }

  void editPendingCommand(String command, {required int revision}) {
    final action = pending;
    if (!canApprove ||
        action?.kind != AiActionKind.runCommand ||
        revision != proposalRevision) {
      return;
    }
    final edited = AiAction.fromToolCall({
      ...action!.rawCall,
      'function': {
        'name': 'run_command',
        'arguments': jsonEncode({'command': command, 'reason': action.reason}),
      },
    });
    _updateActionEntry(
      action,
      AiEntryState.revoked,
      reason: 'Replaced by an edited proposal. The old version cannot run.',
    );
    pending = edited;
    _task.revision++;
    _transcript.add(
      AiTranscriptEntry(
        'proposal',
        edited.preview,
        id: 'entry-${++_entrySerial}',
        action: edited,
        target: proposalTarget,
        state: AiEntryState.proposed,
        revision: proposalRevision,
      ),
    );
    _emit();
  }

  bool _disposed = false;
  bool _appActive = true;
  bool _revalidatingAfterResume = false;
  int _lifecycleRevision = 0;
  bool get _canInteract =>
      !_disposed &&
      !_task.followUpEnded &&
      _appActive &&
      !_revalidatingAfterResume;
  AiCancellation? _cancellation;
  int _steps = 0;
  bool get busy =>
      _interrupting ||
      phase == AiPhase.thinking ||
      phase == AiPhase.reviewing ||
      phase == AiPhase.executing ||
      phase == AiPhase.observing;
  bool get canApprove =>
      _canInteract &&
      terminalError == null &&
      !hasUnresolvedSubmission &&
      pending != null &&
      phase == AiPhase.awaitingApproval;
  bool get canResume =>
      _canInteract &&
      !_task.configurationRetired &&
      !busy &&
      terminalError == null &&
      !hasUnresolvedSubmission &&
      pending == null &&
      _transcript.any((entry) => entry.role == 'user') &&
      (takenOver ||
          (phase == AiPhase.failed &&
              !const {
                'configuration',
                'authentication',
                'conversation_limit',
                'prompt_too_large',
                'session_unavailable',
              }.contains(error)));

  Future<void> resume({
    String label = 'Continue task',
    bool useCurrentTarget = false,
    String? expectedTargetGuard,
    bool Function()? canStart,
  }) async {
    if (!canResume || canStart?.call() == false) return;
    final task = _task;
    await refreshContext();
    if (!canResume || !identical(task, _task) || canStart?.call() == false) {
      return;
    }
    if (expectedTargetGuard != null && context?.guard != expectedTargetGuard) {
      error = 'stale_context';
      _emit();
      return;
    }
    if (targetChanged && !useCurrentTarget) {
      error = 'target_changed';
      _emit();
      return;
    }
    if (useCurrentTarget) _task.target = context;
    await ask(
      'Continue the original task with all prior user constraints. '
      'Inspect the fresh terminal context first. An earlier command may still '
      'be running or have completed; do not resend it merely because the AI '
      'paused or timed out. Propose any new input for approval.',
      displayText: label,
      preserveDraft: true,
      canStart: canStart,
    );
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _configurationChanged() {
    final previous = _lastConfiguration;
    final next = settings.configuration;
    _lastConfiguration = next;
    if (previous?.hasSameValues(next) ?? next == null) return;
    // Policy changes revoke in-flight permission without losing the agent's
    // conversation or pretending its endpoint/model changed.
    if (previous?.hasSameValues(next, includeApprovalPolicy: false) ?? false) {
      if (busy || pending != null) takeOver();
      _emit();
      return;
    }
    final changedAgent =
        previous?.backend == AiBackendKind.acp ||
        next?.backend == AiBackendKind.acp;
    // A proposal produced by a previous endpoint must not outlive that config.
    if (busy || pending != null) takeOver();
    for (final task in _tasks) {
      if (changedAgent && task.transcript.isNotEmpty) {
        task.configurationRetired = true;
        task.phase = AiPhase.failed;
        task.error = 'configuration_changed';
      }
      final agent = task.agent;
      task.agent = null;
      if (agent != null) unawaited(agent.dispose());
    }
    if (_task.configurationRetired) newTask();
    if (phase == AiPhase.failed &&
        settings.configuration != null &&
        (error == 'configuration' || error == 'authentication')) {
      error = null;
      phase = AiPhase.idle;
      takenOver = _transcript.any((entry) => entry.role == 'user');
    }
    _emit();
  }

  Future<void> refreshContext() {
    final task = _task;
    return task.contextRefresh ??= Future<void>.microtask(
      () => _refreshContext(task),
    );
  }

  Future<void> _refreshContext(_AiTask task) async {
    final connectionRevision = _connectionRevision;
    _emit();
    try {
      final fresh = await terminal.readContext();
      if (_disposed ||
          connectionRevision != _connectionRevision ||
          !identical(task, _task)) {
        return;
      }
      final staleProposal =
          pending != null &&
          phase == AiPhase.awaitingApproval &&
          fresh.guard != _task.proposalContext?.guard;
      if (staleProposal || (busy && _differentTarget(context, fresh))) {
        takeOver();
        error = 'stale_context';
      }
      context = fresh;
      _adoptApprovedDirectory(fresh);
      await _reconcileReceipts(task);
      if (_disposed ||
          connectionRevision != _connectionRevision ||
          !identical(task, _task)) {
        return;
      }
      task.terminalError = null;
      if (error == 'submission_unknown' && !hasUnresolvedSubmission) {
        error = null;
      }
    } on Object catch (failure) {
      if (!_disposed &&
          connectionRevision == _connectionRevision &&
          identical(task, _task)) {
        // Losing the target also invalidates an in-flight model response and
        // any approval based on the last readable screen. Preserve model errors.
        takeOver();
        task.terminalError =
            failure is AiFailure && failure.code == 'screen_unavailable'
            ? failure.code
            : 'session_unavailable';
        // The native receipt journal may still be readable after transport
        // loss. Inspect that original submission without reviving approval.
        try {
          await _reconcileReceipts(task);
        } on Object {
          // Keep the unknown result and disconnected state for manual review.
        }
      }
    } finally {
      if (!_disposed &&
          identical(task, _task) &&
          error == 'submission_unknown' &&
          !hasUnresolvedSubmission) {
        error = null;
      }
      if (connectionRevision == _connectionRevision) task.contextRefresh = null;
      _emit();
    }
  }

  Future<void> _reconcileReceipts(_AiTask task) async {
    final port = terminal;
    final inspector = port is AiSubmissionInspector
        ? port as AiSubmissionInspector
        : null;
    for (var i = 0; i < task.transcript.length; i++) {
      final entry = task.transcript[i];
      final progress = entry.action == null
          ? null
          : _keyInputProgressFor(entry.action!);
      if (entry.state == AiEntryState.unknown &&
          progress != null &&
          !progress.writeUncertain) {
        task.transcript[i] = AiTranscriptEntry(
          entry.role,
          entry.text,
          id: entry.id,
          contexts: entry.contexts,
          action: entry.action,
          target: entry.target,
          state: _keyInputState(progress),
          revision: entry.revision,
          approvalReview: entry.approvalReview,
          inputProgress: progress,
          statusReason: entry.statusReason,
          suppliedEvidence: entry.suppliedEvidence,
        );
        continue;
      }
      if (inspector == null ||
          entry.submissionId == null ||
          entry.blockId != null ||
          (entry.state != AiEntryState.unknown &&
              entry.state != AiEntryState.accepted)) {
        continue;
      }
      final receipt =
          port is AiSourceSubmissionInspector && entry.target != null
          ? await (port as AiSourceSubmissionInspector).inspectSourceSubmission(
              entry.submissionId!,
              entry.target!.sessionId,
            )
          : await inspector.inspectSubmission(entry.submissionId!);
      if (_disposed) return;
      if (!identical(task.transcript[i], entry)) continue;
      final state = switch (receipt['outcome']) {
        'accepted' => AiEntryState.accepted,
        'rejected' => AiEntryState.rejected,
        _ => entry.state,
      };
      // A receipt confirms input acceptance, never task success. The actual
      // block retains its running state and exit code in the native timeline.
      task.transcript[i] = AiTranscriptEntry(
        entry.role,
        entry.text,
        id: entry.id,
        contexts: entry.contexts,
        action: entry.action,
        target: entry.target,
        state: state,
        revision: entry.revision,
        approvalReview: entry.approvalReview,
        inputProgress: entry.inputProgress,
        submissionId: entry.submissionId,
        blockId: receipt['blockId'] as String?,
        statusReason: state == AiEntryState.unknown ? entry.statusReason : null,
      );
    }
  }

  String? _submissionFor(AiAction action) =>
      action.kind == AiActionKind.runCommand &&
          terminal is AiSubmissionInspector
      ? (terminal as AiSubmissionInspector).submissionFor(action.id)
      : null;

  AiKeyInputProgress? _keyInputProgressFor(AiAction action) =>
      action.kind == AiActionKind.sendKeys && terminal is AiKeyInputInspector
      ? (terminal as AiKeyInputInspector).keyInputProgress(action)
      : null;

  AiEntryState _keyInputState(AiKeyInputProgress progress) =>
      progress.writeUncertain
      ? AiEntryState.unknown
      : progress.sent == 0
      ? AiEntryState.revoked
      : progress.sent == progress.total
      ? AiEntryState.accepted
      : AiEntryState.interrupted;

  Map<String, Object?> _interruptedInputResult(
    AiAction action, {
    String? error,
  }) {
    final progress = _keyInputProgressFor(action);
    return {
      'interrupted': true,
      'error': ?error,
      if (progress != null) 'input_progress': progress.toJson(action),
      'instruction': progress != null && !progress.writeUncertain
          ? 'Input delivery is recorded in input_progress; application effects '
                'are not confirmed. Observe the fresh terminal before continuing. '
                'Do not replay sent_keys or automatically send the remaining keys.'
          : 'Input may already have been sent. Inspect the original submission '
                'and current screen before continuing. Do not retry automatically.',
    };
  }

  Future<void> ask(
    String input, {
    AiBlockContext? block,
    List<AiBlockContext> blocks = const [],
    String? displayText,
    bool preserveDraft = false,
    bool Function()? canStart,
  }) async {
    final prompt = input.trim();
    if (!_canInteract || busy || prompt.isEmpty || canStart?.call() == false) {
      return;
    }
    if (_task.configurationRetired) {
      error = 'configuration_changed';
      _emit();
      return;
    }
    if (prompt.length > 16000) {
      error = 'prompt_too_large';
      _emit();
      return;
    }
    final requestedTask = _task;
    final deferred = _transcript
        .where((entry) => entry.state == AiEntryState.deferred)
        .toList(growable: false);
    if (prompt.length + deferred.fold(0, (n, e) => n + e.text.length) > 16000) {
      error = 'prompt_too_large';
      _emit();
      return;
    }
    if (!preserveDraft) _task.updateDraft(input);
    final sentDraftRevision = requestedTask.draftRevision;
    final sentAttachments = preserveDraft
        ? const <_AiDraftAttachment>[]
        : List<_AiDraftAttachment>.of(requestedTask.attachments);
    final attached = List<AiBlockContext>.unmodifiable([
      ...sentAttachments.map((attachment) => attachment.context),
      for (final entry in deferred) ...entry.contexts,
      ...blocks,
      ?block,
    ]);
    if (hasUnresolvedSubmission) {
      error = 'submission_unknown';
      _emit();
      return;
    }
    await settings.loaded;
    if (!_canInteract ||
        busy ||
        !identical(requestedTask, _task) ||
        canStart?.call() == false) {
      return;
    }
    if (settings.configuration == null) {
      error = 'configuration';
      _emit();
      return;
    }
    _resolvePending('Superseded by a new user request. No input was sent.');
    _cancellation?.cancel();
    final cancellation = _cancellation = AiCancellation();
    takenOver = false;
    phase = AiPhase.thinking;
    error = null;
    _steps = 0;
    _emit();
    try {
      final fresh = await terminal.readContext();
      cancellation.check();
      if (!identical(requestedTask, _task)) return;
      if (canStart?.call() == false) {
        takeOver();
        return;
      }
      context = fresh;
      _task.terminalError = null;
      _task.target ??= fresh;
      if (targetChanged) {
        takenOver = true;
        throw const AiFailure('target_changed');
      }
      if (attached.length > 8) throw const AiFailure('context_limit');
      if (!preserveDraft) {
        if (_task.draftRevision == sentDraftRevision) {
          _task.updateDraft('');
          _task.inputIntent.reset();
        }
        _task.attachments.removeWhere(sentAttachments.contains);
      }
      if (_task.title.isEmpty) {
        _task.title = prompt.length > 80
            ? '${prompt.substring(0, 80)}…'
            : prompt;
      }
      _messages.add({
        'role': 'user',
        'content': jsonEncode({
          'request': prompt.startsWith('? ') ? prompt.substring(2) : prompt,
          if (deferred.isNotEmpty)
            'saved_user_requirements': deferred.map((e) => e.text).toList(),
          'terminal_context': context!.toJson(),
          if (preserveDraft)
            'original_submissions': [
              for (final entry in _transcript)
                if (entry.submissionId != null || entry.inputProgress != null)
                  {
                    'submission_id': entry.submissionId,
                    'block_id': entry.blockId,
                    'source_session_id': entry.target?.sessionId,
                    'source_context_id': entry.target?.contextId,
                    'state': entry.state.name,
                    'command': entry.action?.preview,
                    if (entry.inputProgress != null && entry.action != null)
                      'input_progress': entry.inputProgress!.toJson(
                        entry.action!,
                      ),
                  },
            ],
          if (block != null) 'selected_block': block.toJson(),
          if (attached.isNotEmpty && !(attached.length == 1 && block != null))
            'selected_blocks': attached.map((b) => b.toJson()).toList(),
        }),
      });
      for (final entry in deferred) {
        final index = _transcript.indexOf(entry);
        if (index < 0) continue;
        _transcript[index] = AiTranscriptEntry(
          entry.role,
          entry.text,
          id: entry.id,
          contexts: entry.contexts,
          target: entry.target,
        );
      }
      _transcript.add(
        AiTranscriptEntry(
          'user',
          displayText ?? prompt,
          id: 'entry-${++_entrySerial}',
          contexts: attached,
          target: fresh,
        ),
      );
      if (settings.configuration!.backend == AiBackendKind.acp) {
        await _runAcpTurn(cancellation);
      } else {
        await _infer(cancellation);
      }
    } on Object catch (failure) {
      _fail(failure, cancellation);
    }
  }

  Future<void> correctLastCommand() async {
    await refreshContext();
    final block = context?.lastBlock;
    if (block == null || block.exitCode == null || block.exitCode == 0) {
      error = 'no_failed_command';
      _emit();
      return;
    }
    await ask(
      'Explain why this command failed and propose a corrected command. '
      '请解释这条命令失败的原因，并给出修正后的命令。',
      block: block,
    );
  }

  Future<void> _infer(AiCancellation cancellation) async {
    var proposalRepairs = 0;
    String? correction;
    while (true) {
      cancellation.check();
      if (++_steps > maxSteps) throw const AiFailure('step_limit');
      final requestHistory = _compactHistory();
      phase = AiPhase.thinking;
      _emit();
      final configuration = settings.configuration;
      if (configuration == null) throw const AiFailure('configuration');
      final inferenceContext = context;
      // Compaction only deduplicates equivalent observations or references
      // their earlier snapshots. Remember the original message identities so
      // replaying history after reconnect cannot rebind unscoped old evidence.
      _rememberSuppliedEvidence(
        _messages,
        sessionId: inferenceContext?.sessionId ?? '',
      );
      final AiReply reply;
      try {
        reply = await api.complete(configuration, [
          {'role': 'system', 'content': aiSystemPrompt},
          ...requestHistory,
          if (correction != null) {'role': 'system', 'content': correction},
        ], cancellation);
        final lastUser = _transcript.lastIndexWhere(
          (entry) => entry.role == 'user',
        );
        final suppliedFailures =
            lastUser >= 0 &&
            _transcript[lastUser].contexts.any(
              (block) => block.exitCode != null && block.exitCode != 0,
            );
        final alreadyExplained = _transcript
            .skip(lastUser + 1)
            .any(
              (entry) =>
                  entry.role == 'assistant' && entry.text.trim().isNotEmpty,
            );
        if (suppliedFailures &&
            !alreadyExplained &&
            reply.action?.writesInput == true &&
            reply.text.trim().isEmpty) {
          throw const AiInvalidAction(
            'The user supplied failed command evidence. Before proposing new '
            'terminal input, include assistant text explaining the observed '
            'failure, its source citation, and what remains unknown. The tool '
            'reason alone is not a diagnosis. No proposal was shown or executed.',
          );
        }
      } on AiInvalidAction catch (failure) {
        cancellation.check();
        if (++proposalRepairs > 2) rethrow;
        // Nothing from the rejected response enters executable history. The
        // replacement still needs approval and retains the original guard.
        correction =
            'The previous tool proposal was rejected before execution. '
            'No terminal input was sent from it. ${failure.detail} '
            'Return a corrected proposal using the supplied tool schema.';
        continue;
      }
      proposalRepairs = 0;
      correction = null;
      cancellation.check();
      _messages.add(reply.toMessage());
      if (reply.text.trim().isNotEmpty) {
        _transcript.add(
          AiTranscriptEntry(
            'assistant',
            reply.text,
            id: 'entry-${++_entrySerial}',
            suppliedEvidence: suppliedAiEvidence(
              requestHistory,
              sessionId: inferenceContext?.sessionId ?? '',
            ),
          ),
        );
      }
      final action = reply.action;
      if (action == null) {
        phase = AiPhase.idle;
        _emit();
        return;
      }
      if (action.kind == AiActionKind.readScreen ||
          action.kind == AiActionKind.readBlock) {
        pending = action;
        phase = AiPhase.observing;
        _emit();
        final result = action.kind == AiActionKind.readScreen
            ? await _observe(action, cancellation)
            : await _readBlock(action, cancellation);
        _messages.add(_toolResult(action, result));
        pending = null;
        continue;
      }
      if (_registerApiOperation(action, inferenceContext) case final result?) {
        _messages.add(_toolResult(action, result, rememberApiOperation: false));
        continue;
      }
      // Bind approval to the context that actually informed inference. Reading
      // a fresh guard here could bless a command intended for a previous SSH hop.
      pending = action;
      _task.proposalContext = inferenceContext;
      _task.revision++;
      _transcript.add(
        AiTranscriptEntry(
          'proposal',
          action.preview,
          id: 'entry-${++_entrySerial}',
          action: action,
          target: inferenceContext,
          state: AiEntryState.proposed,
          revision: proposalRevision,
        ),
      );
      phase = AiPhase.awaitingApproval;
      if (await _reviewPending(cancellation) case final approvedRevision?) {
        await approve(revision: approvedRevision);
      }
      return;
    }
  }

  Future<Map<String, Object?>> _readBlock(
    AiAction action,
    AiCancellation cancellation,
  ) async {
    final expected = context;
    final reader = terminal;
    final allowed = <String>{
      ?context?.lastBlock?.id,
      for (final source in _task.suppliedSourceBases.keys)
        if (source.$1 == expected?.sessionId) source.$2,
      for (final entry in _transcript) ...[
        if (entry.target?.sessionId == expected?.sessionId) ?entry.blockId,
        for (final block in entry.contexts)
          if (block.id case final id?
              when (block.sourceSessionId ?? entry.target?.sessionId) ==
                  expected?.sessionId)
            id,
      ],
    };
    if (reader is! AiBlockReader ||
        expected == null ||
        !allowed.contains(action.blockId)) {
      return {
        'error': 'block_unavailable',
        'instruction':
            'Only read blocks supplied by this task in the current session. Do not re-run a command to reconstruct output.',
      };
    }
    try {
      // A line number belongs to the retained-output version the model saw.
      // Eviction must not silently make that number refer to different bytes.
      // Live UI context is not necessarily evidence already sent to the model.
      final sourceBase =
          _task.suppliedSourceBases[(expected.sessionId, action.blockId!)];
      final block = await (reader as AiBlockReader).readBlockRange(
        action.blockId!,
        startLine: action.startLine,
        lineCount: action.lineCount,
        expected: expected,
      );
      cancellation.check();
      if (sourceBase != null && block.sourceLineBase != sourceBase) {
        return {
          'error': 'block_range_evicted',
          'instruction':
              'The retained output changed since the supplied evidence. These line numbers no longer identify that range. Ask the user to select retained evidence again; never re-run the command to reconstruct it.',
        };
      }
      return {'block': block.toJson()};
    } on AiFailure catch (failure) {
      cancellation.check();
      return {'error': failure.code};
    }
  }

  void _rememberSuppliedEvidence(
    Iterable<Map<String, Object?>> messages, {
    required String sessionId,
  }) {
    for (final message in messages) {
      if (!_task.suppliedMessages.add(message)) continue;
      for (final evidence in suppliedAiEvidence([
        message,
      ], sessionId: sessionId)) {
        // Legacy/unmapped output cannot discard a known source identity.
        final key = (evidence.sessionId, evidence.id);
        if (evidence.sourceLineBase != null ||
            !_task.suppliedSourceBases.containsKey(key)) {
          _task.suppliedSourceBases[key] = evidence.sourceLineBase;
        }
      }
    }
  }

  void _updateActionEntry(
    AiAction action,
    AiEntryState state, {
    String? reason,
    String? submissionId,
    String? blockId,
    AiApprovalReview? approvalReview,
    AiKeyInputProgress? inputProgress,
    bool clearApprovalReview = false,
  }) {
    final index = _transcript.lastIndexWhere(
      (entry) => entry.action?.id == action.id,
    );
    if (index < 0) return;
    final entry = _transcript[index];
    _transcript[index] = AiTranscriptEntry(
      state == AiEntryState.accepted ? 'tool' : 'proposal',
      action.preview,
      id: entry.id,
      action: action,
      target: entry.target,
      state: state,
      revision: proposalRevision,
      submissionId: submissionId ?? entry.submissionId,
      blockId: blockId ?? entry.blockId,
      statusReason: reason,
      approvalReview: clearApprovalReview
          ? null
          : approvalReview ?? entry.approvalReview,
      inputProgress: inputProgress ?? entry.inputProgress,
    );
  }

  Future<Map<String, Object?>> _observe(
    AiAction action,
    AiCancellation cancellation,
  ) async {
    final before = context;
    _task.waitStartedAt = DateTime.now();
    final watch = Stopwatch()..start();
    var fresh = await terminal.readContext();
    cancellation.check();
    var screen = before?.screen;
    while (watch.elapsedMilliseconds < action.waitMs &&
        fresh.guard == before?.guard &&
        !fresh.canRunCommand &&
        !fresh.alternateScreen) {
      final remaining = action.waitMs - watch.elapsedMilliseconds;
      await Future<void>.delayed(
        Duration(milliseconds: remaining.clamp(1, 100)),
      );
      cancellation.check();
      fresh = await terminal.readContext();
      cancellation.check();
      if (fresh.screen != screen) {
        _task.lastOutputAt = DateTime.now();
        screen = fresh.screen;
      }
    }
    context = fresh;
    _adoptApprovedDirectory(fresh);
    return {
      ...fresh.toJson(),
      'observation': {
        'waited_ms': watch.elapsedMilliseconds,
        'state_changed': fresh.guard != before?.guard,
        'wait_expired':
            action.waitMs > 0 && watch.elapsedMilliseconds >= action.waitMs,
      },
    };
  }

  /// Explicit user interruption is independent from pausing model inference.
  Future<void> interruptCommand() async {
    if (!canInterrupt) return;
    final expected = context!;
    final task = _task;
    takeOver();
    _interrupting = true;
    _emit();
    final action = AiAction.fromToolCall({
      'id': 'user-interrupt-${++_entrySerial}',
      'function': {
        'name': 'send_keys',
        'arguments': jsonEncode({
          'keys': [
            {'key': 'CTRL_C'},
          ],
          'reason': 'User interrupted ${expected.runningCommand}',
        }),
      },
    });
    final cancellation = AiCancellation();
    _interruptCancellation = cancellation;
    try {
      final result = await terminal.execute(action, expected, cancellation);
      if (_disposed) return;
      task.messages.add({
        'role': 'user',
        'content': jsonEncode({
          'request':
              'I interrupted the current command. Inspect its actual exit state before continuing.',
          'interrupted_command': expected.runningCommand,
          'result': result,
        }),
      });
      task.transcript.add(
        AiTranscriptEntry(
          'user',
          'Ctrl+C → ${expected.runningCommand}',
          id: 'entry-${++_entrySerial}',
        ),
      );
      if (identical(task, _task)) await refreshContext();
    } on Object catch (failure) {
      if (identical(task, _task)) {
        _recordFailure(failure);
      }
    } finally {
      _interrupting = false;
      _interruptCancellation = null;
      _emit();
    }
  }

  List<Map<String, Object?>> _compactHistory() {
    // Repeated unchanged observations add no new evidence. Keep their newest
    // copy, but retain distinct output and every writing action/result pair.
    final observations = <String>{};
    for (var i = _messages.length - 2; i >= 0; i--) {
      final calls = _messages[i]['tool_calls'];
      if (_messages[i]['role'] != 'assistant' ||
          calls is! List ||
          calls.length != 1) {
        continue;
      }
      final call = calls.single as Map;
      if ((call['function'] as Map?)?['name'] != 'read_screen' ||
          _messages[i + 1]['role'] != 'tool' ||
          _messages[i + 1]['tool_call_id'] != call['id']) {
        continue;
      }
      final snapshot =
          jsonDecode(_messages[i + 1]['content']! as String) as Map;
      snapshot.remove('observation'); // Elapsed wait time is not new output.
      final fingerprint = jsonEncode({
        'snapshot': snapshot,
        'assistant_text': _messages[i]['content'],
      });
      if (!observations.add(fingerprint)) {
        _messages.removeRange(i, i + 2);
      }
    }
    // Retain every unique observation and every action/receipt pair. Only
    // replace byte-identical screen snapshots with an explicit earlier source.
    // References are scoped to this request. Keep the stored history intact so
    // deduplicating later read_screen pairs cannot leave dangling references.
    final compacted = List<Map<String, Object?>>.of(_messages);
    final snapshots = <String, String>{};
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message['role'] != 'user' && message['role'] != 'tool') continue;
      final content = jsonDecode(message['content']! as String) as Map;
      final snapshot = content['terminal_context'];
      if (snapshot == null) continue;
      final fingerprint = jsonEncode(snapshot);
      final existing = snapshots[fingerprint];
      if (existing == null) {
        final source = 'snapshot-$i';
        snapshots[fingerprint] = source;
        content['terminal_context_id'] = source;
      } else {
        content.remove('terminal_context');
        content['terminal_context_unchanged_from'] = existing;
      }
      compacted[i] = {...message, 'content': jsonEncode(content)};
    }
    if (_messages.where((message) => message['role'] == 'user').length > 64 ||
        jsonEncode(compacted).length > 192000) {
      // An explicit limit preserves the task for inspection. Silently deleting
      // old unique evidence could make the next proposal contradict its goal.
      throw const AiFailure('conversation_limit');
    }
    return compacted;
  }

  Future<void> approve({int? revision, bool Function()? canSubmit}) async {
    if (canSubmit?.call() == false) return;
    if (revision != null && revision != proposalRevision) return;
    final action = pending;
    final expected = _task.proposalContext;
    final cancellation = _cancellation;
    if (!canApprove ||
        action == null ||
        expected == null ||
        cancellation == null) {
      return;
    }
    if (canSubmit != null) {
      // Keep the proposal intact while the UI's explicit approval preflights.
      // Another click, task change or pane change cannot claim this operation.
      final task = _task;
      await refreshContext();
      if (!identical(task, _task) ||
          !canApprove ||
          !identical(pending, action) ||
          revision != null && revision != proposalRevision ||
          !canSubmit()) {
        return;
      }
    }
    final submissionCancellation = canSubmit == null
        ? cancellation
        : _AiApprovalCancellation(cancellation, canSubmit);
    pending = null;
    _executingAction = action;
    _updateActionEntry(action, AiEntryState.submitted);
    phase = AiPhase.executing;
    error = null;
    _emit();
    var resultRecorded = false;
    try {
      cancellation.check();
      final result = await terminal.execute(
        action,
        expected,
        submissionCancellation,
      );
      if (!identical(_executingAction, action)) return;
      _executingAction = null;
      // Preserve protocol history even if takeover happens during observation.
      _messages.add(
        _toolResult(action, {...result, 'approved_action': action.rawCall}),
      );
      _updateActionEntry(
        action,
        AiEntryState.accepted,
        submissionId: result['submission_id'] as String?,
        blockId: result['block_id'] as String?,
        inputProgress: _keyInputProgressFor(action),
      );
      resultRecorded = true;
      cancellation.check();
      final fresh = await terminal.readContext();
      cancellation.check();
      context = fresh;
      if (fresh.sessionId == expected.sessionId &&
          fresh.contextId == expected.contextId) {
        // An approved command may intentionally change directory. A changed
        // shell node still requires explicit target choice when continuing.
        _task.target = fresh;
      }
      if (_task.agentReply case final reply?) {
        final activeTurn = _task.agentTurn != null;
        final toolDone = _task.agentToolDone;
        final nextEvent = activeTurn
            ? _task.agentYield = Completer<void>()
            : null;
        _task.agentReply = null;
        phase = AiPhase.thinking;
        final observation = {
          ...result,
          'approved_action': action.rawCall,
          ..._agentObservation(),
        };
        _rememberSuppliedEvidence([
          _toolResult(action, observation),
        ], sessionId: fresh.sessionId);
        reply.complete(observation);
        _emit();
        if (nextEvent != null) {
          await nextEvent.future;
        } else {
          // An MCP client may time out and finish its prompt while approval is
          // pending. Release its old tool lock before delivering the receipt in
          // a new turn; never wait for a reply from that finished prompt.
          await toolDone?.future;
          cancellation.check();
          await _runAcpTurn(cancellation, continuation: observation);
        }
      } else {
        await _infer(cancellation);
      }
    } on Object catch (failure) {
      if (!resultRecorded &&
          identical(_executingAction, action) &&
          failure is AiFailure &&
          failure.code == 'approval_inactive' &&
          terminal is AiSubmissionInspector &&
          action.kind == AiActionKind.runCommand &&
          _submissionFor(action) == null) {
        _executingAction = null;
        pending = action;
        _updateActionEntry(action, AiEntryState.proposed);
        phase = AiPhase.awaitingApproval;
        _emit();
        return;
      }
      if (!resultRecorded && identical(_executingAction, action)) {
        final progress = _keyInputProgressFor(action);
        final result = _interruptedInputResult(
          action,
          error: failure is AiFailure ? failure.code : 'execution',
        );
        _executingAction = null;
        _updateActionEntry(
          action,
          progress != null
              ? _keyInputState(progress)
              : failure is AiFailure &&
                    {
                      'stale_context',
                      'shell_not_ready',
                      'read_only',
                      'submission_rejected',
                    }.contains(failure.code)
              ? AiEntryState.revoked
              : AiEntryState.unknown,
          submissionId: _submissionFor(action),
          inputProgress: progress,
          reason: 'Input observation failed. Inspect before continuing.',
        );
        _messages.add(_toolResult(action, result));
        final reply = _task.agentReply;
        _task.agentReply = null;
        if (reply != null && !reply.isCompleted) reply.complete(result);
      }
      _fail(failure, cancellation);
      if (_task.agent != null) cancellation.cancel();
    }
  }

  Map<String, Object?> _toolResult(
    AiAction action,
    Map<String, Object?> result, {
    bool rememberApiOperation = true,
  }) {
    final content = jsonEncode(result);
    if (rememberApiOperation) _rememberApiOperationResult(action, content);
    return {'role': 'tool', 'tool_call_id': action.id, 'content': content};
  }

  void _resolvePending(
    String reason, {
    AiEntryState state = AiEntryState.revoked,
  }) {
    if (pending case final AiAction action) {
      _updateActionEntry(action, state, reason: reason);
      _messages.add(_toolResult(action, {'cancelled': true, 'reason': reason}));
      pending = null;
      final reply = _task.agentReply;
      _task.agentReply = null;
      if (reply != null && !reply.isCompleted) {
        reply.complete({'cancelled': true, 'reason': reason});
      }
    }
  }

  void reject() {
    if (!canApprove) return;
    _resolvePending(
      'The user declined this action. No input was sent.',
      state: AiEntryState.rejected,
    );
    if (_task.agent != null) _cancellation?.cancel();
    phase = AiPhase.idle;
    _emit();
  }

  void takeOver() {
    if (_disposed || (!busy && pending == null && _executingAction == null)) {
      return;
    }
    _cancellation?.cancel();
    _interruptCancellation?.cancel();
    _resolvePending('The user took over. Stop sending terminal input.');
    _interruptExecuting(
      'Input may have been submitted before pause. Inspect before continuing.',
    );
    phase = AiPhase.idle;
    takenOver = true;
    error = null;
    _emit();
  }

  /// Waiting command proposals have no time limit. Backgrounding only pauses
  /// approval; running inference/input is still cancelled. Interactive keys
  /// depend on transient TUI state and must be proposed again after returning.
  void suspendForBackground() {
    if (_disposed || !_appActive) return;
    _appActive = false;
    _lifecycleRevision++;
    if (busy || pending?.kind != AiActionKind.runCommand) takeOver();
    _emit();
  }

  Future<void> resumeFromBackground() async {
    if (_disposed || _appActive) return;
    _appActive = true;
    _revalidatingAfterResume = true;
    final revision = ++_lifecycleRevision;
    // A read started before foregrounding cannot validate the resumed target.
    final previousRead = _task.contextRefresh;
    if (previousRead != null) await previousRead;
    if (_disposed || revision != _lifecycleRevision) return;
    await refreshContext();
    if (_disposed || revision != _lifecycleRevision) return;
    _revalidatingAfterResume = false;
    _emit();
    // Resuming never restarts inference or sends a retained proposal.
  }

  void _interruptExecuting(String reason) {
    if (_executingAction case final AiAction action) {
      final progress = _keyInputProgressFor(action);
      _updateActionEntry(
        action,
        progress == null ? AiEntryState.unknown : _keyInputState(progress),
        submissionId: _submissionFor(action),
        inputProgress: progress,
        reason: reason,
      );
      _messages.add(_toolResult(action, _interruptedInputResult(action)));
      _executingAction = null;
    }
  }

  void _fail(Object failure, AiCancellation cancellation) {
    if (_disposed ||
        cancellation != _cancellation ||
        cancellation.isCancelled) {
      return;
    }
    // Stop the shared execution token too: an ACP failure can arrive between
    // key writes or while an approved command is still being observed.
    cancellation.cancel();
    if (_executingAction != null) {
      _interruptExecuting(
        'Input observation failed. Inspect before continuing.',
      );
      takenOver = true;
    }
    _recordFailure(failure);
    _resolvePending('Observation failed. No additional input was sent.');
    phase = AiPhase.failed;
    _emit();
  }

  void _recordFailure(Object failure) {
    final code = failure is AiFailure ? failure.code : 'execution';
    if (code == 'session_unavailable' || code == 'screen_unavailable') {
      _task.terminalError = code;
    } else {
      error = code;
    }
  }

  /// Start a new task; retain previous tasks for explicit navigation.
  void clear() => newTask();

  Future<void> closeAgentSessions() async {
    final agents = [
      for (final task in _tasks)
        if (task.agent != null) task.agent!,
    ];
    for (final task in _tasks) {
      task.agent = null;
    }
    await Future.wait(agents.map((agent) => agent.dispose()));
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    _interruptCancellation?.cancel();
    unawaited(_inputSubscription.cancel());
    settings.removeListener(_configurationChanged);
    unawaited(closeAgentSessions());
    terminal.dispose();
    super.dispose();
  }
}
