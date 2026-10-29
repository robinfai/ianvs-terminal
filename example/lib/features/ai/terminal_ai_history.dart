part of 'terminal_ai_controller.dart';

extension TerminalAiHistory on TerminalAiController {
  String historySourceId(String source) =>
      source.startsWith('saved-') ? source : '$historyNamespace-$source';

  /// Content snapshots have no live session lease, cancellation handle or model
  /// credentials. Native output is serialized by the native-record adapter.
  List<Map<String, Object?>> exportHistory(Map<String, Object?> sources) => [
    for (final task in _tasks)
      if (task.transcript.isNotEmpty || task.draft.isNotEmpty)
        {
          'schema': 1,
          'id': task.historyId ??= '$historyNamespace-${task.id}',
          'title': task.title,
          'draft': task.draft,
          'readingOffset': task.readingOffset,
          'readingAnchor': task.readingAnchor == null
              ? null
              : {
                  'id': _historyAnchorId(task, task.readingAnchor!.id, sources),
                  'offset': task.readingAnchor!.offset,
                },
          'followingOutput': task.followingOutput,
          'expanded': task.expandedAgentEntries.toList(),
          'transcript': [
            for (final entry in task.transcript) _historyEntry(entry),
          ],
          'attachments': [
            for (final attachment in task.attachments)
              _historyBlock(attachment.context),
          ],
          'operations': {
            for (final operation in task.agentOperations.entries)
              operation.key: {
                'input': operation.value.input,
                'actionId': operation.value.action.id,
              },
          },
          'sources': {
            for (final source in _historySourcesFor(task))
              if (sources.containsKey(source)) source: sources[source],
          },
        },
  ];

  String _historyAnchorId(
    _AiTask task,
    String anchor,
    Map<String, Object?> sources,
  ) {
    final origins = <String>{
      if (task.context != null) task.context!.sessionId,
      if (task.target != null) task.target!.sessionId,
      for (final entry in task.transcript)
        if (entry.target != null) entry.target!.sessionId,
    };
    for (final source in origins) {
      if (source.startsWith('saved-')) continue;
      final saved = historySourceId(source);
      for (final block
          in (sources[saved] as List? ?? [])
              .whereType<Map<Object?, Object?>>()) {
        final id = block['id'];
        if (anchor == 'native-$source-$id' || anchor == 'native-$source/$id') {
          return 'native-$saved/$id';
        }
        if (anchor == 'source-$source-$id') return 'source-$saved-$id';
      }
    }
    return anchor;
  }

  Set<String> _historySourcesFor(_AiTask task) => {
    ...task.historySourceIds,
    if (task.context != null) historySourceId(task.context!.sessionId),
    if (task.target != null) historySourceId(task.target!.sessionId),
    for (final entry in task.transcript) ...[
      if (entry.target != null) historySourceId(entry.target!.sessionId),
      for (final context in entry.contexts)
        if (context.sourceSessionId != null)
          historySourceId(context.sourceSessionId!),
      for (final evidence in entry.suppliedEvidence ?? <AiEvidenceRange>[])
        historySourceId(evidence.sessionId),
    ],
  };

  Map<String, Object?> _historyEntry(AiTranscriptEntry entry) => {
    'id': entry.id,
    'role': entry.role,
    'text': entry.text,
    'state': entry.state.name,
    'revision': entry.revision,
    'action': entry.action?.rawCall,
    if (entry.action case final action? when action.rawCall.isEmpty)
      'humanCommand': {'id': action.id, 'command': action.command},
    'target': entry.target == null
        ? null
        : {
            ...entry.target!.toJson(),
            'session_id': historySourceId(entry.target!.sessionId),
            'read_only': true,
            'can_run_command': false,
          },
    'submissionId': entry.submissionId,
    'blockId': entry.blockId,
    'statusReason': entry.statusReason,
    'userEdited': entry.userEdited,
    'contexts': [for (final block in entry.contexts) _historyBlock(block)],
    'evidence': [
      for (final e in entry.suppliedEvidence ?? <AiEvidenceRange>[])
        {
          'id': e.id,
          'session': historySourceId(e.sessionId),
          'first': e.first,
          'last': e.last,
          'base': e.sourceLineBase,
        },
    ],
    if (entry.approvalReview case final r?)
      'review': {
        'automatic': r.automatic,
        'reason': r.reason,
        'source': r.source,
      },
    if (entry.inputProgress case final p?)
      'progress': {
        'sent': p.sent,
        'total': p.total,
        'uncertain': p.writeUncertain,
      },
    if (entry.agentContent case final m?)
      'content': {
        'role': m.role.name,
        'text': m.text,
        'turn': m.turnId,
        'revision': m.revision,
        'metadata': m.metadata,
        'timestamp': m.timestamp.toIso8601String(),
      },
  };

  Map<String, Object?> _historyBlock(AiBlockContext block) => {
    'id': block.id,
    'command': block.command,
    'output': block.output,
    'exit': block.exitCode,
    'cwd': block.cwd,
    'running': block.running,
    'total': block.totalLines,
    'start': block.outputStartLine,
    'end': block.outputEndLine,
    'evicted': block.evicted,
    'source': block.sourceSessionId == null
        ? null
        : historySourceId(block.sourceSessionId!),
    'context': block.sourceContextId,
    'base': block.sourceLineBase,
    'offsets': block.lineStartOffsets,
    'ranges': [
      for (final r in block.outputRanges)
        {
          'start': r.startLine,
          'end': r.endLine,
          'text': r.output,
          'offsets': r.lineStartOffsets,
        },
    ],
  };

  /// A restored task is an immutable execution history. Users may start a new
  /// task on the current target, but cannot revive its old proposals or tools.
  void restoreHistory(Iterable<Map<String, Object?>> documents) {
    final selectLatest =
        _task.transcript.isEmpty && _task.draft.isEmpty && !busy;
    _AiTask? latest;
    for (final document in documents) {
      try {
        final id = document['id']! as String;
        if (!id.startsWith('saved-') || _tasks.any((t) => t.historyId == id)) {
          continue;
        }
        final task = _AiTask(id)
          ..historyId = id
          ..restoredHistory = true
          ..followUpEnded = true
          ..takenOver = true
          ..title = document['title'] as String? ?? ''
          ..draft = document['draft'] as String? ?? ''
          ..readingOffset = (document['readingOffset'] as num? ?? 0).toDouble()
          ..followingOutput = document['followingOutput'] == true;
        task.historySourceIds.addAll(
          (document['sources'] as Map? ?? {}).keys.cast<String>(),
        );
        final anchor = document['readingAnchor'];
        if (anchor is Map) {
          task.readingAnchor = (
            id: anchor['id'] as String,
            offset: (anchor['offset'] as num).toDouble(),
          );
        }
        task.transcript.addAll(
          (document['transcript']! as List).map(
            (value) =>
                _restoreHistoryEntry(Map<String, Object?>.from(value as Map)),
          ),
        );
        task.expandedAgentEntries.addAll(
          (document['expanded'] as List? ?? []).cast<String>(),
        );
        task.attachments.addAll(
          (document['attachments'] as List? ?? []).map(
            (value) => _AiDraftAttachment(_restoreHistoryBlock(value as Map)),
          ),
        );
        for (final operation
            in (document['operations'] as Map? ?? {}).entries) {
          final value = operation.value as Map;
          final action = task.transcript
              .map((e) => e.action)
              .whereType<AiAction>()
              .where((a) => a.id == value['actionId'])
              .firstOrNull;
          if (action != null) {
            task.agentOperations[operation.key as String] = (
              input: value['input'] as String,
              action: action,
            );
          }
        }
        _tasks.add(task);
        latest ??= task;
      } on Object {
        // One invalid document must not erase unrelated recoverable histories.
        historyError = 'history_invalid';
      }
    }
    if (selectLatest && latest != null) _task = latest;
    _emit();
  }

  AiTranscriptEntry _restoreHistoryEntry(Map<String, Object?> data) {
    final state = AiEntryState.values.byName(data['state']! as String);
    final target = data['target'] as Map?;
    final content = data['content'] as Map?;
    final review = data['review'] as Map?;
    final progress = data['progress'] as Map?;
    return AiTranscriptEntry(
      data['role']! as String,
      data['text']! as String,
      id: data['id']! as String,
      action:
          data['humanCommand'] is Map ||
              (data['action'] is Map && (data['action']! as Map).isEmpty)
          ? AiAction(
              id:
                  (data['humanCommand'] as Map?)?['id'] as String? ??
                  'archived-${data['id']}',
              kind: AiActionKind.runCommand,
              reason: 'Command entered by the user',
              command:
                  (data['humanCommand'] as Map?)?['command'] as String? ??
                  data['text']! as String,
              rawCall: const {},
            )
          : data['action'] is Map
          ? AiAction.fromToolCall(
              Map<String, Object?>.from(data['action']! as Map),
            )
          : null,
      target: target == null
          ? null
          : AiTerminalContext(
              sessionId: target['session_id'] as String,
              contextId: target['context_id'] as String,
              guard: 'archived',
              screen: target['screen'] as String? ?? '',
              cwd: target['cwd'] as String? ?? '',
              targetLabel: target['target_label'] as String? ?? '',
              readOnly: true,
            ),
      // A recorded send in progress has an uncertain outcome, never success.
      state: state == AiEntryState.proposed
          ? AiEntryState.revoked
          : state == AiEntryState.submitted
          ? AiEntryState.unknown
          : state,
      revision: data['revision'] as int? ?? 0,
      submissionId: data['submissionId'] as String?,
      blockId: data['blockId'] as String?,
      statusReason: data['statusReason'] as String?,
      userEdited: data['userEdited'] == true,
      contexts: [
        for (final b in data['contexts'] as List? ?? [])
          _restoreHistoryBlock(b as Map),
      ],
      suppliedEvidence: [
        for (final e
            in (data['evidence'] as List? ?? [])
                .whereType<Map<Object?, Object?>>())
          (
            id: e['id']! as String,
            sessionId: e['session']! as String,
            first: e['first']! as int,
            last: e['last']! as int,
            sourceLineBase: e['base'] as int?,
          ),
      ],
      approvalReview: review == null
          ? null
          : AiApprovalReview(
              automatic: review['automatic'] == true,
              reason: review['reason'] as String,
              source: review['source'] as String,
            ),
      inputProgress: progress == null
          ? null
          : AiKeyInputProgress(
              sent: progress['sent'] as int,
              total: progress['total'] as int,
              writeUncertain: progress['uncertain'] == true,
            ),
      agentContent: content == null
          ? null
          : ChatMessageData(
              role: ChatMessageRole.values.byName(content['role'] as String),
              text: content['text'] as String,
              turnId: content['turn'] as int?,
              revision: content['revision'] as int? ?? 0,
              timestamp: DateTime.parse(content['timestamp'] as String),
              metadata: Map<String, Object?>.from(content['metadata'] as Map),
            ),
    );
  }

  AiBlockContext _restoreHistoryBlock(Map<Object?, Object?> data) =>
      AiBlockContext(
        id: data['id'] as String?,
        command: data['command']! as String,
        output: data['output']! as String,
        exitCode: data['exit'] as int?,
        cwd: data['cwd']! as String,
        running: data['running'] as bool?,
        totalLines: data['total'] as int?,
        outputStartLine: data['start'] as int? ?? 0,
        outputEndLine: data['end'] as int?,
        evicted: data['evicted'] == true,
        sourceSessionId: data['source'] as String?,
        sourceContextId: data['context'] as String?,
        sourceLineBase: data['base'] as int?,
        lineStartOffsets: (data['offsets'] as List? ?? []).cast<int>(),
        outputRanges: [
          for (final r
              in (data['ranges'] as List? ?? [])
                  .whereType<Map<Object?, Object?>>())
            AiBlockOutputRange(
              startLine: r['start']! as int,
              endLine: r['end']! as int,
              output: r['text']! as String,
              lineStartOffsets: (r['offsets'] as List? ?? []).cast<int>(),
            ),
        ],
      );
}
