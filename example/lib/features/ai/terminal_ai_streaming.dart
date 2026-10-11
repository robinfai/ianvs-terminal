part of 'terminal_ai_controller.dart';

enum AiResponseStage { connecting, waiting, receivingText, receivingTool,
  completed, cancelled, failed }

@immutable
class AiResponseProgress {
  const AiResponseProgress({required this.entryId, required this.stage,
      required this.streamingCapable});
  final String entryId;
  final AiResponseStage stage;
  final bool streamingCapable;
  bool get active => stage == AiResponseStage.connecting ||
      stage == AiResponseStage.waiting || stage == AiResponseStage.receivingText ||
      stage == AiResponseStage.receivingTool;
}

extension _TerminalAiStreaming on TerminalAiController {
  Future<({AiReply reply, String? entryId})> _completeApiResponse(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation, {
    required List<AiEvidenceRange> evidence,
  }) async {
    final task = _task;
    final token = Object();
    task.responseToken = token;
    final streaming = api is AiStreamingApi;
    final entryId = streaming ? 'entry-${++_entrySerial}' : 'request-$_steps';
    final text = StringBuffer();
    Timer? publishTimer;
    var entryCreated = false;
    var settled = false;
    var stage = AiResponseStage.connecting;
    bool ownsRequest() => !_disposed && identical(task.responseToken, token);
    bool acceptsUpdate() => !settled && ownsRequest() && identical(task, _task) &&
        identical(_cancellation, cancellation) && !cancellation.isCancelled;

    void progress(AiResponseStage next) {
      stage = next;
      task.responseProgress = AiResponseProgress(entryId: entryId,
          stage: next, streamingCapable: streaming);
    }

    void publish({AiEntryState state = AiEntryState.streaming, String? reason}) {
      publishTimer?.cancel();
      publishTimer = null;
      if (!ownsRequest()) return;
      if (text.isNotEmpty) {
        final entry = AiTranscriptEntry('assistant', text.toString(),
            id: entryId, state: state, statusReason: reason,
            suppliedEvidence: evidence);
        final index = task.transcript.indexWhere((item) => item.id == entryId);
        if (index < 0) {
          task.transcript.add(entry);
        } else {
          task.transcript[index] = entry;
        }
        entryCreated = true;
      }
      task.responseRevision++;
      if (identical(task, _task)) _emit();
    }

    void settlePartial(String reason) {
      if (settled || !ownsRequest()) return;
      settled = true;
      progress(reason == 'cancelled'
          ? AiResponseStage.cancelled : AiResponseStage.failed);
      publish(state: AiEntryState.partial, reason: reason);
    }

    progress(AiResponseStage.connecting);
    _emit();
    cancellation.onCancel(() => settlePartial('cancelled'));
    try {
      final AiReply reply;
      if (api case final AiStreamingApi streamingApi) {
        reply = await streamingApi.completeStreaming(configuration, messages,
            cancellation, onUpdate: (update) {
          if (!acceptsUpdate()) return;
          final next = switch (update.stage) {
            AiStreamStage.waiting => AiResponseStage.waiting,
            AiStreamStage.receivingText => AiResponseStage.receivingText,
            AiStreamStage.receivingTool => AiResponseStage.receivingTool,
          };
          final stateChanged = stage != next;
          text.write(update.textDelta);
          progress(next);
          // First content/state is immediate. Later real deltas are coalesced
          // to at most 20 UI updates/sec; this never invents a typing effect.
          if (stateChanged || !entryCreated && text.isNotEmpty) {
            publish();
          } else {
            publishTimer ??= Timer(const Duration(milliseconds: 50), () {
              if (acceptsUpdate()) publish();
            });
          }
        });
      } else {
        reply = await api.complete(configuration, messages, cancellation);
      }
      cancellation.check();
      if (!acceptsUpdate()) throw const AiFailure('cancelled');
      if (streaming && text.toString() != reply.text) {
        // A stream cannot replace already displayed content with a different
        // final answer. No proposal may be formed from a mismatching result.
        throw const AiFailure('response_format');
      }
      publishTimer?.cancel();
      if (entryCreated || text.isNotEmpty) publish();
      // Only _infer's validated response may promote the partial transcript.
      return (reply: reply, entryId: entryCreated ? entryId : null);
    } on Object catch (failure) {
      settlePartial(cancellation.isCancelled ? 'cancelled'
          : failure is AiFailure ? failure.code : 'response_format');
      rethrow;
    } finally {
      publishTimer?.cancel();
    }
  }

  void _finishApiResponse(AiReply reply, String? entryId) {
    _task.responseToken = null;
    if (entryId != null) {
      final index = _transcript.indexWhere((entry) => entry.id == entryId);
      if (index >= 0) {
        final previous = _transcript[index];
        _transcript[index] = AiTranscriptEntry('assistant', reply.text,
            id: previous.id, suppliedEvidence: previous.suppliedEvidence);
      }
    }
    final progress = _task.responseProgress;
    if (progress != null) {
      _task.responseProgress = AiResponseProgress(entryId: progress.entryId,
          stage: AiResponseStage.completed,
          streamingCapable: progress.streamingCapable);
    }
    _task.responseRevision++;
  }

  void _rejectApiResponse(String? entryId) {
    _task.responseToken = null;
    if (entryId != null) {
      final index = _transcript.indexWhere((entry) => entry.id == entryId);
      if (index >= 0) {
        final previous = _transcript[index];
        _transcript[index] = AiTranscriptEntry('assistant', previous.text,
            id: previous.id, state: AiEntryState.partial,
            statusReason: 'invalid_action',
            suppliedEvidence: previous.suppliedEvidence);
      }
    }
    final progress = _task.responseProgress;
    if (progress != null) {
      _task.responseProgress = AiResponseProgress(entryId: progress.entryId,
          stage: AiResponseStage.failed,
          streamingCapable: progress.streamingCapable);
    }
    _task.responseRevision++;
  }
}
