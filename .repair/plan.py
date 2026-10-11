plan={'base':'0abfaceee9e797d99750dc4ec1dd4418a6cfd198','edits':[]}
def edit(path,old,new,count=1):plan['edits'].append({'path':path,'old':old,'new':new,'count':count})
ai='example/lib/features/ai/'
shell='example/lib/features/shell/'
sessions='example/lib/features/sessions/'
edit(ai+'ai_api_client.dart',"import 'ai_models.dart';","import 'ai_models.dart';\nimport 'ai_chat_stream.dart';\n\nexport 'ai_chat_stream.dart' show AiStreamListener, AiStreamStage, AiStreamUpdate;")
edit(ai+'ai_api_client.dart','/// OpenAI-compatible Chat Completions, including terminal tool calls.','''/// Optional capability; existing fake/review clients retain the buffered API.
abstract interface class AiStreamingApi implements AiApi {
  Future<AiReply> completeStreaming(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation, {
    required AiStreamListener onUpdate,
  });
}

/// OpenAI-compatible Chat Completions, including terminal tool calls.''')
edit(ai+'ai_api_client.dart','class AiApiClient implements AiApi {','class AiApiClient implements AiApi, AiStreamingApi {')
edit(ai+'ai_api_client.dart','  final bool toolsEnabled;\n','''  final bool toolsEnabled;

  @override
  Future<AiReply> completeStreaming(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation, {
    required AiStreamListener onUpdate,
  }) => requestAiChatStream(
    configuration: configuration, messages: messages, cancellation: cancellation,
    onUpdate: onUpdate, tools: aiTerminalTools, toolsEnabled: toolsEnabled,
    timeout: timeout, totalTimeout: const Duration(minutes: 5),
    reasoningEffort: reasoningEffort,
  );
''')
edit(ai+'terminal_ai_controller.dart',"part 'terminal_ai_api_operations.dart';","part 'terminal_ai_api_operations.dart';\npart 'terminal_ai_streaming.dart';")
edit(ai+'terminal_ai_controller.dart','enum AiEntryState {\n  message,','enum AiEntryState {\n  message,\n  streaming,\n  partial,')
edit(ai+'terminal_ai_controller.dart','  final transcript = <AiTranscriptEntry>[];','''  final transcript = <AiTranscriptEntry>[];
  Object? responseToken;
  AiResponseProgress? responseProgress;
  int responseRevision = 0;''')
edit(ai+'terminal_ai_controller.dart','  String get taskId => _task.id;','''  String get taskId => _task.id;
  AiResponseProgress? get responseProgress => _task.responseProgress;
  int get responseRevision => _task.responseRevision;''')
edit(ai+'terminal_ai_controller.dart','''      final AiReply reply;
      try {
        reply = await api.complete(configuration, [
          {'role': 'system', 'content': aiSystemPrompt},
          ...requestHistory,
          if (correction != null) {'role': 'system', 'content': correction},
        ], cancellation);''','''      final AiReply reply;
      String? streamedEntryId;
      try {
        final completed = await _completeApiResponse(configuration, [
          {'role': 'system', 'content': aiSystemPrompt},
          ...requestHistory,
          if (correction != null) {'role': 'system', 'content': correction},
        ], cancellation, evidence: suppliedAiEvidence(requestHistory,
            sessionId: inferenceContext?.sessionId ?? ''));
        reply = completed.reply;
        streamedEntryId = completed.entryId;''')
edit(ai+'terminal_ai_controller.dart',"                  entry.role == 'assistant' && entry.text.trim().isNotEmpty,","                  entry.role == 'assistant' &&\n                  entry.state == AiEntryState.message && entry.text.trim().isNotEmpty,")
edit(ai+'terminal_ai_controller.dart','''      } on AiInvalidAction catch (failure) {
        cancellation.check();
        if (++proposalRepairs > 2) rethrow;''','''      } on AiInvalidAction catch (failure) {
        cancellation.check();
        _rejectApiResponse(streamedEntryId);
        if (++proposalRepairs > 2) rethrow;''')
edit(ai+'terminal_ai_controller.dart','''      _messages.add(reply.toMessage());
      if (reply.text.trim().isNotEmpty) {''','''      _messages.add(reply.toMessage());
      _finishApiResponse(reply, streamedEntryId);
      if (reply.text.trim().isNotEmpty && streamedEntryId == null) {''')
edit(ai+'terminal_ai_workspace.dart',"import 'ai_approval_notice.dart';","import 'ai_approval_notice.dart';\nimport 'ai_response_activity.dart';")
edit(ai+'terminal_ai_workspace.dart','  int _revision = 0;','  int _revision = 0;\n  int _responseRevision = 0;')
edit(ai+'terminal_ai_workspace.dart','        _count != c.transcript.length;','        (_count != c.transcript.length || _responseRevision != c.responseRevision);')
edit(ai+'terminal_ai_workspace.dart','''        _revision != c.proposalRevision;
    _count = c.transcript.length;''','''        _revision != c.proposalRevision ||
        _responseRevision != c.responseRevision;
    _responseRevision = c.responseRevision;
    _count = c.transcript.length;''')
edit(ai+'terminal_ai_workspace.dart','''      : _settingsNotice != null
      ? _settingsNotice!''','''      : c.responseProgress?.active == true
      ? aiResponseLabel(c.responseProgress!.stage, zh)
      : _settingsNotice != null
      ? _settingsNotice!''')
edit(ai+'terminal_ai_workspace.dart',"    final evidence = entry.role == 'assistant' && widget.onShowEvidence != null","    final evidence = entry.role == 'assistant' &&\n        entry.state == AiEntryState.message && widget.onShowEvidence != null")
edit(ai+'terminal_ai_workspace.dart',"entry.text.replaceAll(RegExp(r'\\[block:[^\\]\\r\\n]*\\]'), '')","entry.text.replaceAll(RegExp(entry.state == AiEntryState.streaming\n            ? r'\\[block:[^\\]\\r\\n]*(?:\\]|$)'\n            : r'\\[block:[^\\]\\r\\n]*\\]'), '')")
edit(ai+'terminal_ai_workspace.dart','          if (entry.state == AiEntryState.deferred) ...[',"""          if (entry.state == AiEntryState.partial) ...[
            const SizedBox(height: 8),
            Text(entry.statusReason == 'cancelled'
                ? t('Generation stopped · partial response', '生成已停止 · 内容不完整')
                : t('Response interrupted · partial content only', '回复未完成 · 仅保留已收到的内容'),
                key: ValueKey('ai-partial-${entry.id}'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (entry.state == AiEntryState.deferred) ...[""")
edit(ai+'terminal_ai_workspace.dart','      if (c.transcript.isEmpty && c.attachments.isEmpty) {',"""      if (c.phase == AiPhase.thinking || c.phase == AiPhase.reviewing) {
        final progress = c.responseProgress;
        items.add(CommandBlockTimelineItem.content('request-activity-$_taskId',
          (_) => TickerMode(enabled: widget.active && !_mobileDetailsOpen && _desktopReview == null,
            child: AiResponseActivity(key: const Key('ai-request-activity'),
              label: c.phase == AiPhase.reviewing
                  ? t('Reviewing command safety…', '正在审核命令…')
                  : progress?.active == true
                  ? aiResponseLabel(progress!.stage, zh)
                  : t('Preparing request…', '正在准备请求…'),
              animate: progress?.active == true && progress!.streamingCapable,
            )),
        ));
      }
      if (c.transcript.isEmpty && c.attachments.isEmpty) {""")
edit(ai+'terminal_ai_workspace_mobile.dart','padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),','padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),')
edit(ai+'terminal_ai_workspace_mobile.dart',"    if (c.busy) return (id: 'pause', label: t('Pause AI', '暂停 AI'));","""    if (c.busy) return (id: 'pause', label: c.responseProgress?.active == true
        ? t('Stop generating', '停止生成') : t('Pause AI', '暂停 AI'));""")
edit(shell+'shell_screen.dart',"part 'shell_screen_ai.dart';","part 'shell_screen_ai.dart';\npart 'shell_screen_unavailable_session.dart';")
layout=shell+'shell_screen_state_terminal_layout.dart'
edit(layout,'''    if (viewportController == null) {
      return const SizedBox.shrink();
    }''','''    if (viewportController == null) {
      return _buildUnavailableTerminalPane(context: context,
          sessionController: sessionController, pane: pane, expectedTab: activeTab,
          palette: palette, isActive: isActive);
    }''')
edit(layout,'''          viewportController,
        )) {
          return const SizedBox.shrink();
        }''','''          viewportController,
        )) {
          return _buildUnavailableTerminalPane(context: context,
              sessionController: sessionController, pane: pane, expectedTab: activeTab,
              palette: palette, isActive: isActive);
        }''')
edit(sessions+'session_controller.dart','        !_runtime.isSessionRetainedAfterExit(sessionId)) {','''        (!_runtime.isSessionRetainedAfterExit(sessionId) &&
            _runtime.hasSession(sessionId))) {''')
edit(sessions+'session_controller.dart','''    _runtime.resizeSession(sessionId, viewportSize, devicePixelRatio);
    _applyFrame(sessionId, _runtime.viewportFor(sessionId).frame);''','''    final tabIndex = _tabIndexContainingSession(sessionId);
    if (tabIndex < 0) return;
    final expectedTab = state.tabs[tabIndex];
    final before = _runtime.existingViewportFor(sessionId);
    if (before == null) {
      reconcileUnavailableSession(sessionId, expectedTab: expectedTab);
      return;
    }
    _runtime.resizeSession(sessionId, viewportSize, devicePixelRatio);
    final after = _runtime.existingViewportFor(sessionId);
    if (identical(before, after) && after != null) {
      _applyFrame(sessionId, after.frame);
    } else {
      reconcileUnavailableSession(sessionId, expectedTab: expectedTab);
    }''')
edit(sessions+'session_controller.dart','  void resizeActiveSession(Size viewportSize, double devicePixelRatio) {','''  /// Reconcile a feature pane whose runtime has already gone away. This does
  /// not fabricate an exit code, drop task drafts, create a PTY, or replay input.
  /// The expected tab identity prevents a stale post-frame callback from
  /// changing a replacement session. Normal delivered exit events keep their
  /// existing remove/retain policy.
  bool reconcileUnavailableSession(String sessionId, {
    required TerminalTab expectedTab,
  }) {
    if (!ref.mounted || _isShuttingDown ||
        ref.read(sessionDemoFixtureProvider) != null ||
        _runtime.hasSession(sessionId) ||
        !state.tabs.any((tab) => identical(tab, expectedTab) && tab.containsSession(sessionId))) return false;
    final expectedPane = expectedTab.paneFor(sessionId)!;
    if (expectedPane.isExited &&
        expectedPane.runtimeError?.operation == 'sessionUnavailable') return false;
    _replaceSessionPane(sessionId, expectedPane.copyWith(
      isExited: true,
      runtimeError: const TerminalPaneRuntimeErrorState(
        operation: 'sessionUnavailable',
        message: 'The original terminal runtime is unavailable. No input was replayed.',
      ),
      terminalMode: const TerminalModeState(
        unavailableReason: BlockUnavailableReason.exited,
      ),
    ));
    return true;
  }

  void resizeActiveSession(Size viewportSize, double devicePixelRatio) {''')
edit(ai+'ai_strings.dart',"    'response_format': (","""    'stream_incomplete': (
      'The response stream ended before completion. Partial content is retained; no incomplete proposal was submitted.',
      '流式回复未完整结束。已保留收到的内容，不会提交不完整的提案。',
    ),
    'stream_error': (
      'The provider interrupted the response stream. No terminal action was replayed.',
      '服务端中断了流式回复，没有重放终端动作。',
    ),
    'response_format': (""")
plan['expected_blobs']={
 ai+'ai_api_client.dart':'c40ae3d2fc2eef90cf5eedd069b6a73223c95ebd',
 ai+'terminal_ai_controller.dart':'db68607897fe86fb5d3e6ac03ca30ec90265ac95',
 ai+'terminal_ai_workspace.dart':'1bb4fba1a06427d84d62fe061063daea2ebeb2d3',
 ai+'terminal_ai_workspace_mobile.dart':'d8731dddc99a71ec8a1e0638cb62ae135c786bb5',
 ai+'ai_strings.dart':'2ce4bbd2aa17387b0a1a856fe406f01b0759c3e6',
 shell+'shell_screen.dart':'c9efdca68f4417fc16045ed25d60f9653a0de93b',
 layout:'88732882a92dea57208ebb59ac7bbd5a9fb43d37',
 sessions+'session_controller.dart':'77fb2bf6c904b6bfbc94d2473cf59f07025d73b5',
}
plan['new_files']=['example/lib/features/ai/ai_chat_stream.dart','example/lib/features/ai/terminal_ai_streaming.dart','example/lib/features/ai/ai_response_activity.dart','example/lib/features/shell/shell_screen_unavailable_session.dart','example/test/ai/ai_chat_stream_test.dart','example/test/ai/terminal_ai_streaming_test.dart','example/test/sessions/session_unavailable_recovery_test.dart','tools/check_mobile_image_metadata.py','test/test_mobile_image_metadata.py']
plan['tests']=[
 ['flutter','test','test/ai/ai_chat_stream_test.dart','test/ai/terminal_ai_streaming_test.dart','test/ai/terminal_ai_compact_mobile_test.dart','test/sessions/session_unavailable_recovery_test.dart','--reporter','expanded'],
 ['flutter','test','test/ai','--reporter','expanded'],
]
