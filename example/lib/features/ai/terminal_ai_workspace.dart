import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:ianvs_design/ianvs_design.dart' show IanvsTypographyContext;
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../ui/app_ui.dart';
import 'ai_approval_notice.dart';
import 'ai_models.dart';
import 'ai_settings_dialog.dart';
import 'ai_strings.dart';
import 'terminal_ai_controller.dart';
import 'terminal_ai_message.dart';
import 'terminal_ai_target_notice.dart';

export 'ai_models.dart' show AiEvidenceReference;

part 'terminal_ai_workspace_preview_adapter.dart';
part 'terminal_ai_workspace_mobile.dart';

typedef AiTimelineBuilder =
    Widget Function(
      List<CommandBlockTimelineItem> items,
      ScrollController scroll,
      ValueNotifier<bool> followTail,
    );

/// A session task occupies the main content surface. The native PTY remains
/// mounted behind this view; opening a task never changes its input target.
class TerminalAiWorkspace extends StatefulWidget {
  const TerminalAiWorkspace({
    required this.controller,
    required this.onClose,
    this.onTakeOver,
    this.active = true,
    this.compactMobile = false,
    this.targetLabel = '',
    this.timelineBuilder,
    this.onInspectContext,
    this.onShowEvidence,
    this.onOpenLink,
    this.onReconnect,
    this.onConfigureTerminal,
    this.onInspectOriginalTarget,
    this.onObserveTerminal,
    this.fullScreenTerminal = false,
    super.key,
  });
  final TerminalAiController controller;

  /// Collapse into read-only observation without cancelling this task.
  final VoidCallback onClose;

  /// Explicitly revoke AI input before restoring the human terminal owner.
  final VoidCallback? onTakeOver;
  final bool active;

  /// The mobile host already owns session navigation. Opt in to its compact
  /// task/input presentation without changing standalone or desktop surfaces.
  final bool compactMobile;
  final String targetLabel;
  final AiTimelineBuilder? timelineBuilder;
  final ValueChanged<AiBlockContext>? onInspectContext;
  final ValueChanged<AiEvidenceReference>? onShowEvidence;
  final ValueChanged<String>? onOpenLink;
  final Future<void> Function()? onReconnect;
  final Future<void> Function()? onConfigureTerminal;
  final VoidCallback? onInspectOriginalTarget;
  final VoidCallback? onObserveTerminal;
  final bool fullScreenTerminal;

  @override
  State<TerminalAiWorkspace> createState() => _TerminalAiWorkspaceState();
}

class _TerminalAiWorkspaceState extends State<TerminalAiWorkspace>
    with WidgetsBindingObserver {
  late final TextEditingController _input;
  late final CommandTimelineScrollController _scroll;
  final _focus = FocusNode(debugLabel: 'AI task input');
  final _workspaceFocus = FocusNode(debugLabel: 'AI task');
  final _sendFocus = FocusNode(debugLabel: 'Send to AI');
  final _approvalFocus = FocusNode(debugLabel: 'Approve AI command');
  final _returnedActions = <String>{};
  Timer? _contextTimer;
  late String _taskId;
  int _count = 0;
  int _revision = 0;
  bool _wasBusy = false;
  bool _replyFocusAllowed = false;
  final _following = ValueNotifier<bool>(true);
  bool get _follow => _following.value;
  set _follow(bool value) {
    _following.value = value;
    c.followingOutput = value;
  }

  bool _refreshing = false;
  bool _resuming = false;
  bool _reconnecting = false;
  bool _draftEditorOpen = false;
  bool _mobileDetailsOpen = false;
  String? _mobileRecoveryNotice;
  String? _settingsNotice;
  bool _restoringPosition = false;
  bool _revalidatingPane = false;
  int _paneRevision = 0;
  int _terminalObservationRevision = 0;
  ({String taskId, AiTranscriptEntry entry})? _desktopReview;
  double? _returnOffset;
  CommandTimelineAnchor? _returnAnchor;
  int _positionRevision = 0;
  TerminalAiController get c => widget.controller;
  bool get _paneInteractive =>
      widget.active &&
      !_revalidatingPane &&
      CommandBlockReaderHost.maybeOf(context)?.blocksInput != true;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String en, String cn) => zh ? cn : en;
  bool get _commandIntent =>
      c
          .inputIntentDecision(composing: !_input.value.composing.isCollapsed)
          .intent ==
      InputIntent.command;
  bool get _mobile =>
      Theme.of(context).platform == TargetPlatform.iOS ||
      Theme.of(context).platform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _taskId = c.taskId;
    _input = TextEditingController(text: c.draft)..addListener(_saveDraft);
    _scroll = CommandTimelineScrollController(
      initialScrollOffset: c.readingOffset,
      onReadingAnchorChanged: (anchor) {
        if (!_restoringPosition && _taskId == c.taskId) {
          c.readingAnchor = (id: anchor.itemId, offset: anchor.offset);
        }
      },
    )..addListener(_savePosition);
    _follow = c.followingOutput;
    _returnedActions.addAll(
      c.transcript
          .where((entry) => entry.state == AiEntryState.accepted)
          .map((entry) => entry.id),
    );
    c.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _contextTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (_mobile &&
          lifecycle != null &&
          lifecycle != AppLifecycleState.resumed) {
        return;
      }
      if (mounted && c.phase == AiPhase.observing) setState(() {});
      if (_refreshing || c.busy) return;
      _refreshing = true;
      try {
        await c.refreshContext();
      } finally {
        _refreshing = false;
      }
    });
    _changed();
    if (!_follow && c.readingAnchor != null) {
      unawaited(_restorePosition(_savedAnchor, c.readingOffset));
    }
  }

  CommandTimelineAnchor? get _savedAnchor => c.readingAnchor == null
      ? null
      : CommandTimelineAnchor(
          itemId: c.readingAnchor!.id,
          offset: c.readingAnchor!.offset,
          scrollOffset: c.readingOffset,
        );

  Future<void> _restorePosition(
    CommandTimelineAnchor? anchor,
    double offset,
  ) async {
    final revision = ++_positionRevision;
    _restoringPosition = true;
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || revision != _positionRevision) return;
    final restored =
        anchor != null && await _scroll.restoreReadingAnchor(anchor);
    if (!mounted || revision != _positionRevision) return;
    if (!restored && _scroll.hasClients) {
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    }
    _restoringPosition = false;
    _savePosition();
  }

  void _saveDraft() {
    if (c.followUpEnded) return;
    c.setDraft(_input.text, composing: !_input.value.composing.isCollapsed);
  }

  void _savePosition() {
    if (!_restoringPosition && _scroll.hasClients) {
      c.readingOffset = _scroll.offset;
      final anchor = _scroll.readingAnchor;
      if (anchor != null) {
        c.readingAnchor = (id: anchor.itemId, offset: anchor.offset);
      }
      if (_scroll.position.extentAfter > 48) _follow = false;
    }
  }

  void _changed() {
    if (!mounted) return;
    final switched = _taskId != c.taskId;
    final reply = c.transcript.lastOrNull;
    final finishedReply =
        !switched &&
        _wasBusy &&
        c.phase == AiPhase.idle &&
        !c.takenOver &&
        reply?.role == 'assistant' &&
        _count != c.transcript.length;
    if (switched) _replyFocusAllowed = false;
    if (!_wasBusy && c.busy) _replyFocusAllowed = true;
    _wasBusy = c.busy;
    if (switched || c.busy || c.canApprove) _settingsNotice = null;
    if (switched) {
      _returnedActions.addAll(
        c.transcript
            .where((entry) => entry.state == AiEntryState.accepted)
            .map((entry) => entry.id),
      );
    } else {
      for (final entry in c.transcript) {
        if (entry.action?.kind == AiActionKind.sendKeys &&
            // An exit command can leave the alternate screen before its
            // receipt arrives. Observe the result using the approved target too.
            (widget.fullScreenTerminal ||
                entry.target?.alternateScreen == true) &&
            entry.state == AiEntryState.accepted &&
            _returnedActions.add(entry.id)) {
          _observeTerminalAfterFrame(
            stillCurrent: () => c.transcript.any(
              (current) =>
                  current.id == entry.id &&
                  current.state == AiEntryState.accepted,
            ),
          );
        }
      }
    }
    final changed =
        switched ||
        _count != c.transcript.length ||
        _revision != c.proposalRevision;
    _count = c.transcript.length;
    _revision = c.proposalRevision;
    if (_input.text != c.draft) {
      _input.value = TextEditingValue(
        text: c.draft,
        selection: TextSelection.collapsed(offset: c.draft.length),
      );
    }
    if (switched) {
      _taskId = c.taskId;
      _mobileRecoveryNotice = null;
      _follow = c.followingOutput;
      _returnOffset = null;
      _returnAnchor = null;
      unawaited(_restorePosition(_savedAnchor, c.readingOffset));
    } else if (changed && _follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _latest());
    }
    setState(() {});
    if (finishedReply) _restoreReplyFocus(c.taskId, reply!.id);
  }

  void _restoreReplyFocus(String taskId, String replyId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          c.taskId != taskId ||
          c.phase != AiPhase.idle ||
          c.takenOver ||
          c.transcript.lastOrNull?.id != replyId) {
        return;
      }
      final allowed = _replyFocusAllowed;
      _replyFocusAllowed = false;
      // Mobile keeps the user's keyboard state. Reading, selection, another
      // control, a modal route or an inactive window retain their input owner.
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!allowed ||
          _mobile ||
          !widget.active ||
          !_follow ||
          widget.fullScreenTerminal ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final owner = FocusManager.instance.primaryFocus;
      if (owner == _workspaceFocus ||
          owner == _focus ||
          owner == _sendFocus ||
          owner == _approvalFocus) {
        _focus.requestFocus();
      }
    });
  }

  void _latest() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _observeTerminalAfterFrame({required bool Function() stillCurrent}) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_paneInteractive ||
        !_workspaceFocus.hasFocus ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final taskId = c.taskId;
    final paneRevision = _paneRevision;
    final observationRevision = ++_terminalObservationRevision;
    final owner = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final currentOwner = FocusManager.instance.primaryFocus;
      if (!mounted ||
          c.taskId != taskId ||
          _paneRevision != paneRevision ||
          _terminalObservationRevision != observationRevision ||
          !_paneInteractive ||
          !_workspaceFocus.hasFocus ||
          (currentOwner != owner && currentOwner != _workspaceFocus) ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          ModalRoute.of(context)?.isCurrent == false ||
          !stillCurrent()) {
        return;
      }
      // TUI output and accepted keys can reveal their result, but neither is
      // a user request to revoke the task and acquire manual write ownership.
      _observeTerminal();
    });
  }

  @override
  void didUpdateWidget(TerminalAiWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _replyFocusAllowed = false;
      if (widget.active) {
        unawaited(_revalidatePane());
      } else {
        _paneRevision++;
      }
    }
    if (widget.fullScreenTerminal && !oldWidget.fullScreenTerminal) {
      _observeTerminalAfterFrame(stillCurrent: () => widget.fullScreenTerminal);
    }
  }

  Future<void> _revalidatePane() async {
    final revision = ++_paneRevision;
    _revalidatingPane = true;
    final alreadyChecking = c.checkingTerminal;
    await c.refreshContext();
    // A read started before activation cannot validate the newly active pane.
    if (alreadyChecking) await c.refreshContext();
    if (!mounted || revision != _paneRevision || !widget.active) return;
    setState(() => _revalidatingPane = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _replyFocusAllowed = false;
      _terminalObservationRevision++;
    }
  }

  @override
  void dispose() {
    _contextTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    _input.removeListener(_saveDraft);
    _input.dispose();
    _scroll.removeListener(_savePosition);
    _scroll.dispose();
    _following.dispose();
    _focus.dispose();
    _workspaceFocus.dispose();
    _sendFocus.dispose();
    _approvalFocus.dispose();
    super.dispose();
  }

  void _refreshMobile(VoidCallback change) {
    if (mounted) setState(change);
  }

  Future<void> _submit() async {
    if (!_paneInteractive || c.followUpEnded) return;
    if (_useCompactMobile && !_mobileCanSubmit) return;
    if (_input.value.composing.isValid && !_input.value.composing.isCollapsed) {
      return;
    }
    final prompt = _input.text.trim();
    if (prompt.isEmpty) return;
    if (_commandIntent) {
      await c.runUserCommand(_input.text);
      return;
    }
    if (c.hasUnresolvedSubmission) {
      await c.supplement(prompt);
      return;
    }
    if (c.settings.configuration == null) {
      await _openSettings();
      return; // Configuration never sends a saved draft automatically.
    }
    if (!_mobile && !_focus.hasFocus) _workspaceFocus.requestFocus();
    if (c.busy || c.canApprove) {
      await c.supplement(prompt);
    } else {
      await c.ask(prompt);
    }
  }

  void _observeTerminal() {
    if (!_paneInteractive) return;
    _terminalObservationRevision++;
    _replyFocusAllowed = false;
    _focus.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    (widget.onObserveTerminal ?? widget.onClose)();
  }

  void _collapseTask() {
    if (!_paneInteractive) return;
    _terminalObservationRevision++;
    _replyFocusAllowed = false;
    _focus.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    widget.onClose();
  }

  Future<void> _expandDraft() async {
    if (_draftEditorOpen || c.followUpEnded || !_paneInteractive) return;
    final owner = c;
    _input.value = _input.value.copyWith(composing: TextRange.empty);
    _focus.unfocus();
    final taskId = owner.taskId;
    final revision = owner.draftRevision;
    final original = _input.value;
    final choice = owner.inputIntentChoice;
    bool current() =>
        mounted &&
        _paneInteractive &&
        !owner.followUpEnded &&
        identical(c, owner) &&
        owner.taskId == taskId &&
        owner.draftRevision == revision &&
        _input.value == original &&
        owner.inputIntentChoice == choice;
    _draftEditorOpen = true;
    _replyFocusAllowed = false;
    try {
      final result = await showComposerDraftEditor(
        context,
        initialValue: original,
        initialIntentChoice: choice,
        resolveIntent: (value, intent) => owner.previewInputIntent(
          value.text,
          intent,
          composing: !value.composing.isCollapsed,
        ),
        targetLabel: '${widget.targetLabel} · ${owner.context?.cwd ?? ''}',
        chinese: zh,
        textStyle: Theme.of(context).textTheme.bodyLarge,
        canChooseCommand: () =>
            !owner.busy &&
            owner.pending == null &&
            owner.attachments.isEmpty &&
            !widget.fullScreenTerminal,
        isCurrent: current,
        stateChanges: owner,
      );
      if (result != null && current()) {
        // Set the whole editing value first. The existing listener saves its
        // text, and the synchronous controller notification retains selection.
        _input.value = result.value;
        owner.chooseInputIntent(result.intentChoice);
      }
    } finally {
      _draftEditorOpen = false;
      if (mounted) _focus.unfocus();
    }
  }

  Future<void> _openSettings() => showAiSettings(
    context,
    c.settings,
    onSaved: (saved) {
      if (!mounted) return;
      setState(() {
        _settingsNotice = saved
            ? t('AI connection saved. Task not sent.', 'AI 连接已保存，任务尚未发送。')
            : t('AI connection configuration removed.', 'AI 连接配置已移除。');
      });
    },
  );

  String get _status => c.followUpEnded
      ? c.hasUnresolvedSubmission
            ? t(
                'Follow-up ended · original outcome remains unknown',
                '已结束跟进 · 原提交结果仍未知',
              )
            : t('Follow-up ended · read-only', '已结束跟进 · 只读')
      : c.hasUnresolvedSubmission
      ? t('Submission unknown · check original receipt', '提交状态未知 · 请检查原回执')
      : c.terminalError != null
      ? t('Terminal unavailable · check its status', '终端暂不可用 · 请检查状态')
      : c.targetChanged
      ? t('Target changed · choose where to continue', '目标已变化 · 请确认继续位置')
      : _settingsNotice != null
      ? _settingsNotice!
      : c.interrupting
      ? t('Checking command interruption…', '正在核对命令中断结果…')
      : switch (c.phase) {
          AiPhase.thinking => t('Thinking…', '正在思考…'),
          AiPhase.reviewing => t('Reviewing command safety…', '正在审核命令…'),
          AiPhase.executing => t('Checking submission…', '正在核对提交…'),
          AiPhase.observing => t(
            'Waiting ${c.waitStartedAt == null ? 0 : DateTime.now().difference(c.waitStartedAt!).inSeconds}s · ${c.lastOutputAt == null ? "no new output observed" : "last output ${DateTime.now().difference(c.lastOutputAt!).inSeconds}s ago"}',
            '已等待 ${c.waitStartedAt == null ? 0 : DateTime.now().difference(c.waitStartedAt!).inSeconds} 秒 · ${c.lastOutputAt == null ? "尚未观察到新输出" : "最近输出在 ${DateTime.now().difference(c.lastOutputAt!).inSeconds} 秒前"}',
          ),
          AiPhase.awaitingApproval => t('One action needs review', '有一条命令待确认'),
          AiPhase.failed =>
            c.error == 'step_limit'
                ? t(
                    'Turn paused · continue from current state',
                    '本轮已暂停 · 可从当前状态继续',
                  )
                : t('Needs attention', '需要处理'),
          AiPhase.idle =>
            c.takenOver
                ? t('AI paused · command is not interrupted', 'AI 已暂停 · 命令未被中断')
                : c.transcript.isEmpty
                ? t('Ready for your task', '等待你的任务')
                : t('Response received', '已收到回复'),
        };

  // Elapsed seconds remain visible without turning every timer tick into a
  // screen-reader announcement. Only meaningful task phases change this label.
  String get _announcedStatus =>
      c.phase == AiPhase.observing &&
          !c.targetChanged &&
          !c.hasUnresolvedSubmission &&
          c.terminalError == null
      ? t('AI is observing the terminal', 'AI 正在观察终端')
      : _status;

  String _contextRange(AiBlockContext block) {
    if (block.outputRanges.isNotEmpty) {
      return t(
        '${block.includedLineCount} lines · ${block.outputRanges.length} ranges',
        '${block.includedLineCount} 行 · ${block.outputRanges.length} 个片段',
      );
    }
    if (block.outputEndLine == null) return t('Output snapshot', '输出快照');
    if (block.includedLineCount == 0) return t('No output', '无输出');
    final rows = '${block.outputStartLine + 1}–${block.outputEndLine}';
    return block.totalLines == null
        ? t('Lines $rows', '第 $rows 行')
        : t(
            'Lines $rows of ${block.totalLines}',
            '第 $rows 行，共 ${block.totalLines} 行',
          );
  }

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      t(
        'Describe a task, or attach command output. AI actions are reviewed before execution.',
        '描述任务，或附上命令输出。AI 提出的终端动作将在执行前单独审阅。',
      ),
    ),
  );

  Widget _contextChip(AiBlockContext block, {bool removable = false}) {
    final taskId = c.taskId;
    final range = _contextRange(block);
    final coverage = [
      if (block.toJson()['output_truncated'] == true)
        t('Partial output', '仅含部分输出'),
      if (block.evicted) t('Earlier output evicted', '早期输出已淘汰'),
    ].join(' · ');
    return InputChip(
      avatar: const Icon(Icons.terminal_outlined, size: 16),
      label: ConstrainedBox(
        // RawChip derives its content height from the label, then positions
        // the independent deletion slot within that height.
        constraints: const BoxConstraints(minHeight: 44, maxWidth: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(block.command, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              range,
              key: const Key('ai-context-range'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (coverage.isNotEmpty)
              Text(
                coverage,
                key: const Key('ai-context-coverage'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
      tooltip:
          '${block.cwd}\n${block.command}\n$range'
          '${coverage.isEmpty ? '' : '\n$coverage'}',
      deleteIcon: Icon(
        Icons.cancel,
        key: ValueKey('ai-context-delete-${block.id}'),
        size: 18,
      ),
      deleteIconBoxConstraints: const BoxConstraints.tightFor(
        width: 44,
        height: 44,
      ),
      onPressed: () => _inspect(block),
      onDeleted: !removable || c.followUpEnded || !_paneInteractive
          ? null
          : () {
              if (c.taskId != taskId || c.followUpEnded || !_paneInteractive) {
                return;
              }
              final index = c.attachments.indexOf(block);
              if (index >= 0) c.removeAttachment(index);
            },
    );
  }

  void _inspect(AiBlockContext block) {
    if (widget.onInspectContext case final callback?) {
      callback(block);
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        animationStyle: appDialogAnimation(context),
        builder: (context) => AlertDialog(
          title: Text(t('Attached output snapshot', '已附加的输出快照')),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(
                    block.command,
                    style: context.ianvsTypography.code.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${t('Directory: ', '目录：')}${block.cwd}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${t('Source: ', '来源：')}${block.sourceSessionId ?? ''} / ${block.sourceContextId ?? ''} · ${block.id ?? ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(_contextRange(block)),
                  if (block.evicted)
                    Text(
                      t(
                        'Earlier output has been evicted from terminal history.',
                        '更早的输出已从终端历史中淘汰。',
                      ),
                    ),
                  Text(
                    t('Exit ', '退出码 ') + (block.exitCode?.toString() ?? '?'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: block.exitCode != null && block.exitCode != 0
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                  if (block.toJson()['output_truncated'] == true)
                    Text(
                      t(
                        'This snapshot contains only the indicated retained range.',
                        '该快照只包含所示的保留范围。',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  if (block.outputRanges.isEmpty)
                    SelectableText(
                      block.output,
                      style: context.ianvsTypography.code,
                    ),
                  for (final range in block.outputRanges) ...[
                    Text(
                      t(
                        'Lines ${range.startLine + 1}–${range.endLine}',
                        '第 ${range.startLine + 1}–${range.endLine} 行',
                      ),
                    ),
                    SelectableText(
                      range.output,
                      style: context.ianvsTypography.code,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Close', '关闭')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entry(AiTranscriptEntry entry, bool narrow) {
    if (entry.action != null) return _proposal(entry, narrow);
    final evidence = entry.role == 'assistant' && widget.onShowEvidence != null
        ? _evidence(entry).toList()
        : const <AiEvidenceReference>[];
    // Source markers are protocol metadata, not user-facing prose. Preserve
    // the raw transcript, but do not expose malformed/unknown markers as if
    // they were evidence. Only validated numeric references become buttons.
    final message = entry.role == 'assistant' && widget.onShowEvidence != null
        ? entry.text.replaceAll(RegExp(r'\[block:[^\]\r\n]*\]'), '')
        : entry.text;
    return TerminalAiMessageFrame(
      entryId: entry.id,
      isUser: entry.role == 'user',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.role == 'assistant')
            TerminalAiMessage(
              text: message.trim(),
              onOpenLink: widget.onOpenLink,
            )
          else
            SelectableText(
              message.trim(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (entry.state == AiEntryState.deferred) ...[
            const SizedBox(height: 8),
            Text(
              t(
                'Saved, not sent. Check the original submission, then explicitly continue.',
                '已暂存，尚未发送。先检查原提交，再明确继续。',
              ),
            ),
            if (!c.followUpEnded)
              TextButton(
                key: ValueKey('ai-discard-supplement-${entry.id}'),
                onPressed: !_paneInteractive
                    ? null
                    : () {
                        if (_paneInteractive && !c.followUpEnded) {
                          c.discardDeferredSupplement(entry.id);
                        }
                      },
                child: Text(t('Remove saved requirement', '移除暂存要求')),
              ),
          ],
          if (entry.role == 'user' && entry.state == AiEntryState.revoked)
            Text(
              t(
                'Saved requirement withdrawn; it was not sent.',
                '暂存要求已撤销，未发送。',
              ),
            ),
          if (entry.role == 'assistant' && widget.onShowEvidence != null)
            Wrap(
              spacing: 8,
              children: [
                for (final ref in evidence)
                  TextButton.icon(
                    key: ValueKey(
                      'ai-evidence-${ref.id}-${ref.startLine}-${ref.endLine}',
                    ),
                    onPressed: () {
                      _follow = false;
                      widget.onShowEvidence!(ref);
                    },
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: Text(
                      t(
                        'Evidence · ${ref.startLine + 1}–${ref.endLine}',
                        '证据 · ${ref.startLine + 1}–${ref.endLine} 行',
                      ),
                    ),
                  ),
              ],
            ),
          if (entry.contexts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final block in entry.contexts) _contextChip(block),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Iterable<AiEvidenceReference> _evidence(AiTranscriptEntry entry) sync* {
    // Only the frozen request can establish provenance. Looking up today's
    // last block would silently rebind old replies after eviction/reconnection.
    final supplied = entry.suppliedEvidence;
    if (supplied == null) return;
    final seen = <(String, int, int)>{};
    for (final match in RegExp(
      r'\[block:([^:\]\s]{1,128}):(\d+)-(\d+)\]',
    ).allMatches(entry.text)) {
      final id = match[1]!;
      final first = int.tryParse(match[2]!);
      final last = int.tryParse(match[3]!);
      if (first == null || last == null || first < 1 || last < first) continue;
      final origins = supplied
          .where(
            (r) =>
                r.id == id &&
                (r.sessionId == c.context?.sessionId ||
                    c.retainsSource(r.sessionId)) &&
                first >= r.first &&
                last <= r.last,
          )
          .toList(growable: false);
      // A model may cite a range repeatedly or cite different ranges starting
      // on the same row. Deduplicate complete ranges, retaining every origin
      // for ambiguity checks, and keep distinct ranges independently usable.
      if (origins.isNotEmpty && seen.add((id, first, last))) {
        yield (id: id, startLine: first - 1, endLine: last, origins: origins);
        if (seen.length == 20) break;
      }
    }
  }

  Widget _proposal(
    AiTranscriptEntry entry,
    bool narrow, {
    bool reviewPage = false,
  }) {
    final action = entry.action!;
    final taskId = c.taskId;
    final active =
        _paneInteractive &&
        (_desktopReview == null || reviewPage) &&
        c.canApprove &&
        c.pending?.id == action.id &&
        c.proposalRevision == entry.revision &&
        entry.state == AiEntryState.proposed;
    final palette = context.appTheme;
    final label = switch (entry.state) {
      AiEntryState.proposed =>
        c.phase == AiPhase.reviewing && c.pending?.id == action.id
            ? t('Reviewing command safety…', '正在审核命令…')
            : t('Awaiting review', '待确认'),
      AiEntryState.submitted => t('Submitting', '提交中'),
      AiEntryState.accepted => t('Input submitted', '输入已提交'),
      AiEntryState.interrupted => t('Input partially submitted', '输入已部分提交'),
      AiEntryState.unknown => t('Submission outcome unknown', '提交结果未知'),
      AiEntryState.rejected => t('Declined', '已拒绝'),
      _ => t('Revoked', '已撤销'),
    };
    return Container(
      key: ValueKey('ai-proposal-${entry.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? palette.accent : palette.borderStrong,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: t('Purpose: ', '目的：'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextSpan(text: action.reason),
              ],
            ),
          ),
          if (entry.approvalReview case final review?) ...[
            const SizedBox(height: 8),
            AiApprovalNotice(
              key: ValueKey('ai-approval-review-${entry.id}'),
              review: review,
              pending: entry.state == AiEntryState.proposed,
              confirmed:
                  entry.state == AiEntryState.accepted ||
                  entry.state == AiEntryState.interrupted ||
                  entry.state == AiEntryState.submitted ||
                  entry.state == AiEntryState.unknown,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${t('Target: ', '执行目标：')}${entry.target?.targetLabel.isNotEmpty == true ? entry.target!.targetLabel : entry.target?.sessionId ?? ''} · ${entry.target?.contextId ?? ''}\n${t('Directory: ', '目录：')}${entry.target?.cwd ?? ''}',
            key: const Key('ai-action-target'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Text(
            action.kind == AiActionKind.runCommand
                ? t('Command', '命令')
                : t('Terminal input', '终端按键'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          SelectableText(
            action.preview,
            key: active ? const Key('ai-action-preview') : null,
            minLines: 1,
            maxLines: narrow && !reviewPage ? 3 : null,
            style: context.ianvsTypography.code.copyWith(fontSize: 14),
          ),
          if (entry.inputProgress case final progress?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t(
                  '${progress.sent} of ${progress.total} input steps were sent. '
                      '${progress.writeUncertain ? 'The next step has an unknown outcome. ' : ''}'
                      'Continuing reads the current screen; sent input and remaining steps are not replayed automatically.',
                  '已发送 ${progress.sent}/${progress.total} 步输入。'
                      '${progress.writeUncertain ? '下一步的发送结果未知。' : ''}'
                      '继续任务会重新读取屏幕，不会自动重发已发送或剩余输入。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (!active &&
              entry.inputProgress == null &&
              (entry.state == AiEntryState.unknown ||
                  entry.statusReason != null))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                entry.state == AiEntryState.unknown
                    ? t(
                        'This command may already have run. Check its original receipt before continuing; it will not be sent again.',
                        '此命令可能已经执行。继续前请核对原提交回执，不会再次发送此命令。',
                      )
                    : t(
                        'This proposal cannot be executed. Continue to read current state.',
                        '此提案已失效，继续任务时会重新读取当前状态。',
                      ),
                key: ValueKey('ai-proposal-status-${entry.id}'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (active && !reviewPage) ...[
            const SizedBox(height: 12),
            if (narrow && !reviewPage)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                children: [
                  TextButton(
                    key: const Key('ai-reject'),
                    onPressed: () {
                      if (_canActOn(entry, taskId)) c.reject();
                    },
                    child: Text(t('Decline', '拒绝')),
                  ),
                  FilledButton(
                    key: const Key('ai-review-action'),
                    onPressed: () => _review(entry),
                    child: Text(t('Review full command', '审阅完整命令')),
                  ),
                ],
              )
            else
              _proposalActions(entry),
          ],
        ],
      ),
    );
  }

  bool _canActOn(AiTranscriptEntry entry, String taskId) =>
      mounted &&
      _paneInteractive &&
      c.taskId == taskId &&
      c.canApprove &&
      c.pending?.id == entry.action?.id &&
      c.proposalRevision == entry.revision &&
      c.transcript.any(
        (current) =>
            current.id == entry.id &&
            current.revision == entry.revision &&
            current.state == AiEntryState.proposed,
      );

  Widget _proposalActions(AiTranscriptEntry entry, {VoidCallback? close}) {
    final taskId = c.taskId;
    final enabled = _canActOn(entry, taskId);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 6,
      children: [
        if (entry.action!.kind == AiActionKind.runCommand)
          TextButton.icon(
            key: const Key('ai-edit-action'),
            onPressed: enabled
                ? () {
                    if (_canActOn(entry, taskId)) unawaited(_edit(entry));
                  }
                : null,
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: Text(t('Edit', '编辑')),
          ),
        TextButton(
          key: const Key('ai-reject'),
          onPressed: enabled
              ? () {
                  if (!_canActOn(entry, taskId)) return;
                  c.reject();
                  close?.call();
                }
              : null,
          child: Text(t('Decline', '拒绝')),
        ),
        FilledButton(
          key: const Key('ai-approve'),
          focusNode: _approvalFocus,
          onPressed: enabled
              ? () {
                  if (!_canActOn(entry, taskId)) return;
                  final paneRevision = _paneRevision;
                  // The approval button disappears on submit. Give its keyboard
                  // ownership to the task, not a previously tabbed text region.
                  if (!_mobile) _workspaceFocus.requestFocus();
                  unawaited(
                    c.approve(
                      revision: entry.revision,
                      canSubmit: () =>
                          mounted &&
                          _paneInteractive &&
                          _paneRevision == paneRevision &&
                          c.taskId == taskId,
                    ),
                  );
                  close?.call();
                }
              : null,
          child: Text(t('Run once', '执行一次')),
        ),
      ],
    );
  }

  Future<void> _edit(AiTranscriptEntry entry) async {
    final taskId = c.taskId;
    if (!mounted || !_canActOn(entry, taskId)) return;
    final editor = TextEditingController(text: entry.action!.command);
    String? error;
    final value = await showDialog<String>(
      context: context,
      animationStyle: appDialogAnimation(context),
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: Text(t('Edit proposal', '编辑提案')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('ai-edit-command'),
                    controller: editor,
                    minLines: 3,
                    maxLines: 12,
                    autofocus: true,
                    style: context.ianvsTypography.code,
                    decoration: InputDecoration(errorText: error),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      'Saving creates a new revision for review. It does not execute.',
                      '保存后需要重新审阅，不会直接执行。',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('Cancel', '取消')),
            ),
            FilledButton(
              key: const Key('ai-save-edit'),
              onPressed: () {
                try {
                  if (!_canActOn(entry, taskId)) {
                    update(
                      () => error = t('The proposal changed.', '提案已更新或撤销。'),
                    );
                    return;
                  }
                  c.editPendingCommand(editor.text, revision: entry.revision);
                  Navigator.pop(dialogContext, editor.text);
                } on AiFailure catch (failure) {
                  update(() => error = aiErrorText(failure.code, zh));
                }
              },
              child: Text(t('Save for review', '保存并重新审阅')),
            ),
          ],
        ),
      ),
    );
    // The dialog may still animate out using this controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    editor.dispose();
    if (value != null && mounted) _focus.unfocus();
  }

  Future<void> _review(AiTranscriptEntry entry) async {
    final taskId = c.taskId;
    if (!_canActOn(entry, taskId)) return;
    _focus.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!mounted || !_canActOn(entry, taskId)) return;
    _replyFocusAllowed = false;
    if (!_mobile) {
      setState(() => _desktopReview = (taskId: taskId, entry: entry));
      _workspaceFocus.requestFocus();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(
            title: Text(t('Review command', '审阅命令')),
            leading: IconButton(
              key: const Key('ai-review-back'),
              tooltip: t('Return to task', '返回任务'),
              onPressed: () => Navigator.pop(routeContext),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: SafeArea(
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) =>
                  _reviewBody(entry, taskId, () => Navigator.pop(routeContext)),
            ),
          ),
        ),
      ),
    );
  }

  void _closeDesktopReview() {
    if (!mounted || !widget.active) return;
    setState(() => _desktopReview = null);
    _workspaceFocus.requestFocus();
  }

  Widget _reviewBody(
    AiTranscriptEntry entry,
    String taskId,
    VoidCallback close,
  ) {
    final current = c.taskId == taskId
        ? c.transcript.where((item) => item.id == entry.id).firstOrNull
        : null;
    if (current == null ||
        current.revision != entry.revision ||
        current.state != AiEntryState.proposed) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              t(
                'The proposal changed. Return to review its latest revision.',
                '提案已更新或撤销，请返回重新审阅。',
              ),
            ),
            TextButton(
              onPressed: close,
              child: Text(t('Return to task', '返回任务')),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (!_paneInteractive)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              widget.active
                  ? t('Checking this pane’s original target…', '正在核对该窗格的原执行目标…')
                  : t(
                      'Select this pane to review or approve.',
                      '选中此窗格后可审阅和批准。',
                    ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('ai-review-scroll'),
            child: _proposal(current, false, reviewPage: true),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _proposalActions(current, close: close),
        ),
      ],
    );
  }

  Widget _desktopReviewSurface() {
    final review = _desktopReview!;
    return Material(
      key: const Key('ai-desktop-review'),
      color: context.appTheme.panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('Review command', '审阅命令'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const Key('ai-review-back'),
                  tooltip: t('Return to task', '返回任务'),
                  onPressed: widget.active ? _closeDesktopReview : null,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _reviewBody(
              review.entry,
              review.taskId,
              _closeDesktopReview,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewPresentation(Widget task) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: _desktopReview != null,
        child: ExcludeFocus(excluding: _desktopReview != null, child: task),
      ),
      if (_desktopReview != null)
        Positioned.fill(child: _desktopReviewSurface()),
    ],
  );

  Widget _header(bool compact, {bool singleRow = false}) => Padding(
    padding: EdgeInsets.fromLTRB(12, singleRow ? 0 : 4, 4, singleRow ? 0 : 4),
    child: SizedBox(
      height: singleRow ? 44 : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!singleRow || !widget.fullScreenTerminal)
                  Text(
                    c.taskTitle.isEmpty
                        ? t('Terminal / New task', '终端 / 新任务')
                        : c.taskTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                if (widget.fullScreenTerminal)
                  Tooltip(
                    message:
                        c.context?.runningCommand ??
                        t('Full-screen terminal', '全屏终端'),
                    child: Text(
                      t(
                        'Terminal program: ${c.context?.runningCommand ?? "Full-screen terminal"}',
                        '终端程序：${c.context?.runningCommand ?? "全屏终端"}',
                      ),
                      key: const Key('ai-terminal-program'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (compact)
                  Semantics(
                    container: true,
                    liveRegion: true,
                    label: _announcedStatus,
                    excludeSemantics: true,
                    child: Tooltip(
                      message: _status,
                      child: Text(
                        _status,
                        key: const Key('ai-task-status'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (singleRow && c.attachments.isNotEmpty)
            _pendingContexts(compact: true),
          if (!singleRow || c.attachments.isEmpty)
            PopupMenuButton<String>(
              popUpAnimationStyle: appDialogAnimation(context),
              tooltip: t('Session tasks', '会话任务'),
              icon: const Icon(Icons.history, size: 20),
              onSelected: (id) {
                if (id == 'settings') {
                  unawaited(_openSettings());
                } else {
                  _savePosition();
                  c.selectTask(id);
                }
              },
              itemBuilder: (_) => [
                for (final task in c.tasks)
                  CheckedPopupMenuItem(
                    value: task.id,
                    checked: task.id == c.taskId,
                    child: Text(
                      '${task.title.isEmpty ? t('New task', '新任务') : task.title}${task.followUpEnded ? t(' · Follow-up ended', ' · 已结束跟进') : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (compact) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'settings',
                    child: Text(t('AI connection', 'AI 连接')),
                  ),
                ],
              ],
            ),
          if (singleRow)
            _hideKeyboardButton()
          else
            IconButton(
              key: const Key('ai-new-task'),
              tooltip: t('New task', '新任务'),
              onPressed: () {
                _savePosition();
                c.newTask();
              },
              icon: const Icon(Icons.add, size: 20),
            ),
          if (!compact)
            IconButton(
              key: const Key('ai-open-settings'),
              tooltip: t('AI connection', 'AI 连接'),
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined, size: 20),
            ),
          if (singleRow) _taskActions(includeInlineActions: true),
          IconButton(
            key: const Key('ai-close'),
            tooltip: t('Collapse to read-only terminal', '收起并只读查看终端'),
            onPressed: _collapseTask,
            icon: const Icon(Icons.close, size: 20),
          ),
          if (widget.onObserveTerminal != null)
            IconButton(
              key: const Key('ai-observe-terminal'),
              tooltip: t('View terminal (read-only)', '只读查看终端'),
              onPressed: _observeTerminal,
              icon: const Icon(Icons.visibility_outlined, size: 20),
            ),
        ],
      ),
    ),
  );

  String get _resumeLabel => c.hasDeferredSupplement
      ? t('Send saved requirements', '发送已暂存要求')
      : c.targetChanged
      ? t('Continue on current target', '在当前目标继续')
      : t('Continue task', '继续任务');

  Future<void> _resume({AiTerminalContext? selectedTarget}) async {
    if (_resuming || !_paneInteractive || c.followUpEnded) return;
    final controller = c;
    final taskId = controller.taskId;
    final paneRevision = _paneRevision;
    bool canStart() =>
        mounted &&
        _paneInteractive &&
        _paneRevision == paneRevision &&
        c == controller &&
        controller.taskId == taskId;
    setState(() => _resuming = true);
    try {
      if (selectedTarget != null) {
        // The inline choice applies only to the target displayed at the click.
        // resume() refreshes the terminal and checks that guard before asking.
        await controller.resume(
          label: t('Continue on current target', '在当前目标继续'),
          useCurrentTarget: true,
          expectedTargetGuard: selectedTarget.guard,
          canStart: canStart,
        );
        return;
      }
      await controller.refreshContext();
      if (!mounted ||
          !_paneInteractive ||
          c != controller ||
          controller.taskId != taskId ||
          !controller.canResume) {
        return;
      }
      if (!controller.targetChanged) {
        await controller.resume(label: _resumeLabel, canStart: canStart);
        return;
      }
      final target = controller.context!;
      final previous = controller.originalTarget!;
      final shortDialog = MediaQuery.sizeOf(context).height < 360;
      final useCurrent = await showDialog<bool>(
        context: context,
        animationStyle: appDialogAnimation(context),
        builder: (dialogContext) => AlertDialog(
          title: Text(
            t('Choose execution target', '选择执行目标'),
            style: shortDialog ? Theme.of(context).textTheme.titleMedium : null,
          ),
          titlePadding: shortDialog ? const EdgeInsets.all(16) : null,
          contentPadding: shortDialog
              ? const EdgeInsets.symmetric(horizontal: 16)
              : const EdgeInsets.fromLTRB(24, 20, 24, 24),
          actionsPadding: shortDialog ? const EdgeInsets.all(12) : null,
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          constraints: const BoxConstraints(maxWidth: 560),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AiTargetComparison(original: previous, current: target, zh: zh),
              const SizedBox(height: 16),
              Text(AiTargetChangeNotice.explanation(zh)),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('ai-target-dialog-return'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                shortDialog
                    ? t('Terminal', '返回终端')
                    : t('Return to terminal', '返回终端检查原目标'),
              ),
            ),
            FilledButton(
              key: const Key('ai-target-dialog-continue'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                shortDialog
                    ? t('Continue here', '在此继续')
                    : t('Continue on current target', '在当前目标继续'),
              ),
            ),
          ],
        ),
      );
      // A dialog opened for one task must never resume a different task.
      if (!mounted ||
          !_paneInteractive ||
          c != controller ||
          controller.taskId != taskId ||
          !controller.canResume) {
        return;
      }
      if (useCurrent == false) {
        (widget.onInspectOriginalTarget ?? widget.onClose)();
      } else if (useCurrent == true) {
        await controller.resume(
          label: t('Continue on current target', '在当前目标继续'),
          useCurrentTarget: true,
          expectedTargetGuard: target.guard,
          canStart: canStart,
        );
      }
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
  }

  void _returnToReading() {
    _follow = false;
    if (_scroll.hasClients && _returnOffset != null) {
      unawaited(_restorePosition(_returnAnchor, _returnOffset!));
    }
    setState(() {
      _returnOffset = null;
      _returnAnchor = null;
    });
  }

  Widget _recovery() {
    final taskId = c.taskId;
    final checkTerminal = c.terminalError != null || c.hasUnresolvedSubmission;
    final configure = const {
      'configuration',
      'authentication',
      'connection',
      'timeout',
      'response_format',
    }.contains(c.error);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.canEndFollowUp || c.followUpEnded)
            Text(
              c.followUpEnded
                  ? c.hasUnresolvedSubmission
                        ? t(
                            'Follow-up ended. The old operation remains unknown and read-only. A new task will not resend it.',
                            '已结束跟进。旧操作仍为未知并保留只读记录，新任务不会重发原命令。',
                          )
                        : t(
                            'Follow-up ended. The original receipt has been updated; this task stays read-only.',
                            '已结束跟进。原回执已更新，该任务继续保留只读记录。',
                          )
                  : t(
                      'If the original result cannot be recovered, you can end follow-up while keeping its unknown record. This does not stop or resend the command.',
                      '如果无法找回原结果，可以结束跟进并保留未知记录。这不会中断或重发原命令。',
                    ),
            ),
          if (c.terminalError != null)
            Text(
              aiErrorText(c.terminalError!, zh),
              key: const Key('ai-terminal-error'),
            ),
          if (c.error != null || c.hasUnresolvedSubmission)
            Text(
              aiErrorText(c.error ?? 'submission_unknown', zh),
              key: const Key('ai-error'),
            ),
          Wrap(
            spacing: 8,
            children: [
              if (c.canEndFollowUp)
                TextButton(
                  key: const Key('ai-end-follow-up'),
                  onPressed: !_paneInteractive
                      ? null
                      : () {
                          if (c.taskId == taskId && _paneInteractive) {
                            c.endFollowUp();
                          }
                        },
                  child: Text(t('End follow-up', '结束跟进')),
                ),
              if (c.followUpEnded)
                FilledButton.icon(
                  key: const Key('ai-new-independent-task'),
                  onPressed: !_paneInteractive
                      ? null
                      : () {
                          if (c.taskId != taskId || !_paneInteractive) return;
                          _savePosition();
                          c.newTask();
                        },
                  icon: const Icon(Icons.add),
                  label: Text(t('Start a new task', '新建独立任务')),
                ),
              if (checkTerminal)
                TextButton.icon(
                  key: const Key('ai-check-terminal'),
                  onPressed: c.checkingTerminal ? null : c.refreshContext,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    c.checkingTerminal
                        ? t('Checking…', '正在检查…')
                        : c.hasUnresolvedSubmission
                        ? t('Check original submission', '检查原提交')
                        : t('Check terminal status', '检查终端状态'),
                  ),
                ),
              if (c.terminalError != null && widget.onReconnect != null)
                FilledButton.icon(
                  key: const Key('ai-reconnect-terminal'),
                  onPressed: _reconnecting || c.checkingTerminal
                      ? null
                      : () async {
                          setState(() => _reconnecting = true);
                          try {
                            await widget.onReconnect!();
                          } finally {
                            if (mounted) setState(() => _reconnecting = false);
                          }
                        },
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text(
                    _reconnecting
                        ? t('Reconnecting…', '正在重新连接…')
                        : t('Reconnect and inspect', '重新连接并检查'),
                  ),
                ),
              if (checkTerminal)
                TextButton(
                  key: const Key('ai-inspect-terminal'),
                  onPressed: _observeTerminal,
                  child: Text(t('Inspect terminal (read-only)', '只读检查终端')),
                ),
              if (c.terminalError != null && widget.onConfigureTerminal != null)
                TextButton.icon(
                  key: const Key('ai-terminal-settings'),
                  onPressed: _reconnecting || c.checkingTerminal
                      ? null
                      : widget.onConfigureTerminal,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: Text(t('SSH connection settings', 'SSH 连接设置')),
                ),
              if (configure)
                TextButton.icon(
                  key: const Key('ai-recovery-settings'),
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: Text(t('AI connection', 'AI 连接')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLatest() {
    ++_positionRevision;
    _restoringPosition = false;
    _scroll.cancelReadingRestoration();
    if (_scroll.hasClients && _scroll.position.extentAfter > 48) {
      setState(() {
        _returnOffset = _scroll.offset;
        _returnAnchor = _scroll.readingAnchor;
      });
    }
    _follow = true;
    _latest();
  }

  Widget _taskActions({bool includeInlineActions = false}) =>
      PopupMenuButton<String>(
        popUpAnimationStyle: appDialogAnimation(context),
        key: const Key('ai-task-actions'),
        tooltip: t('Task actions', '任务操作'),
        icon: const Icon(Icons.more_horiz),
        onSelected: (action) {
          if (!_paneInteractive) return;
          if (action == 'new-task') {
            _savePosition();
            c.newTask();
          }
          if (action == 'interrupt') unawaited(c.interruptCommand());
          if (action == 'return') _returnToReading();
          if (action == 'keyboard') _workspaceFocus.requestFocus();
          if (action == 'pause') c.takeOver();
          if (action == 'resume') unawaited(_resume());
          if (action == 'latest') _showLatest();
        },
        itemBuilder: (_) => [
          if (includeInlineActions)
            PopupMenuItem(
              key: const Key('ai-new-task'),
              value: 'new-task',
              child: Text(t('New task', '新任务')),
            ),
          if (includeInlineActions && (c.busy || c.canApprove))
            PopupMenuItem(
              key: const Key('ai-take-over'),
              value: 'pause',
              child: Text(t('Pause AI; keep command running', '暂停 AI，命令继续运行')),
            ),
          if (includeInlineActions && c.canResume)
            PopupMenuItem(
              key: const Key('ai-resume'),
              enabled: !_resuming,
              value: 'resume',
              child: Text(_resumeLabel),
            ),
          if (includeInlineActions)
            PopupMenuItem(
              key: const Key('ai-show-latest'),
              value: 'latest',
              child: Text(
                c.canApprove
                    ? t('Locate pending proposal', '定位待确认提案')
                    : t('Show latest', '查看最新'),
              ),
            ),
          if (_mobile && View.of(context).viewInsets.bottom > 0)
            PopupMenuItem(
              key: const Key('ai-hide-keyboard'),
              value: 'keyboard',
              child: Text(t('Hide keyboard', '收起键盘')),
            ),
          if (c.canInterrupt)
            PopupMenuItem(
              value: 'interrupt',
              child: Text(
                t(
                  'Interrupt ${c.context?.runningCommand}',
                  '中断 ${c.context?.runningCommand}',
                ),
              ),
            ),
          if (_returnOffset != null)
            PopupMenuItem(
              value: 'return',
              child: Text(t('Return to reading position', '返回阅读位置')),
            ),
        ],
      );

  Widget _navigationAction({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required bool showLabel,
  }) => showLabel
      ? TextButton.icon(
          key: key,
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        )
      : IconButton(
          key: key,
          tooltip: label,
          onPressed: onPressed,
          icon: Icon(icon),
        );

  Widget _statusBar(bool compact, {bool collapsed = false}) => collapsed
      ? _taskActions(includeInlineActions: true)
      : LayoutBuilder(
          builder: (context, bounds) {
            final latestLabel = c.canApprove
                ? t('Locate pending proposal', '定位待确认提案')
                : t('Show latest', '查看最新');
            final returnLabel = t('Return to reading position', '返回阅读位置');
            final textScaler = MediaQuery.textScalerOf(context);
            double labelWidth(String label) {
              final painter = TextPainter(
                text: TextSpan(
                  text: label,
                  style:
                      Theme.of(
                        context,
                      ).textButtonTheme.style?.textStyle?.resolve({}) ??
                      Theme.of(context).textTheme.labelLarge,
                ),
                textDirection: Directionality.of(context),
                textScaler: textScaler,
                maxLines: 1,
              )..layout();
              final width = painter.width + 64;
              painter.dispose();
              return width;
            }

            final reserved =
                textScaler.scale(160) +
                48 *
                    ((c.busy || c.canApprove ? 1 : 0) +
                        (c.canResume ? 1 : 0) +
                        (c.canInterrupt ? 1 : 0) +
                        (_returnOffset != null ? 1 : 0));
            final labelLatest =
                !compact &&
                bounds.maxWidth >= reserved + labelWidth(latestLabel);
            final labelReturn =
                labelLatest &&
                _returnOffset != null &&
                bounds.maxWidth >=
                    reserved -
                        48 +
                        labelWidth(latestLabel) +
                        labelWidth(returnLabel);
            return Row(
              children: [
                if (!compact)
                  Expanded(
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      label: _announcedStatus,
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          _status,
                          key: const Key('ai-task-status'),
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                if (c.busy || c.canApprove)
                  IconButton(
                    key: const Key('ai-take-over'),
                    tooltip: t(
                      'Pause AI; keep command running',
                      '暂停 AI，命令继续运行',
                    ),
                    onPressed: c.takeOver,
                    icon: const Icon(Icons.pause_circle_outline),
                  ),
                if (c.canResume)
                  IconButton(
                    key: const Key('ai-resume'),
                    tooltip: _resumeLabel,
                    onPressed: _resuming ? null : _resume,
                    icon: const Icon(Icons.play_arrow_outlined),
                  ),
                if (!compact && c.canInterrupt)
                  IconButton(
                    key: const Key('ai-interrupt-command'),
                    tooltip: t(
                      'Interrupt ${c.context?.runningCommand} · Ctrl+C',
                      '中断 ${c.context?.runningCommand} · Ctrl+C',
                    ),
                    onPressed: c.interruptCommand,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
                if (compact &&
                    (c.canInterrupt ||
                        _returnOffset != null ||
                        (_mobile && View.of(context).viewInsets.bottom > 0)))
                  _taskActions(),
                if (!compact && _returnOffset != null)
                  _navigationAction(
                    key: const Key('ai-return-reading'),
                    label: returnLabel,
                    onPressed: _returnToReading,
                    icon: Icons.undo,
                    showLabel: labelReturn,
                  ),
                _navigationAction(
                  key: const Key('ai-show-latest'),
                  label: latestLabel,
                  onPressed: _showLatest,
                  icon: Icons.arrow_downward_outlined,
                  showLabel: labelLatest,
                ),
              ],
            );
          },
        );

  Widget _prompt({int maxLines = 4, String? hintText, bool dense = false}) => Focus(
    onKeyEvent: (_, event) {
      if (!_input.value.composing.isCollapsed) return KeyEventResult.ignored;
      final keyboard = HardwareKeyboard.instance;
      final shortcut = Theme.of(context).platform == TargetPlatform.macOS
          ? keyboard.isMetaPressed
          : keyboard.isControlPressed;
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyI &&
          shortcut) {
        if (_paneInteractive &&
            !c.followUpEnded &&
            !c.busy &&
            c.pending == null &&
            c.attachments.isEmpty &&
            !widget.fullScreenTerminal) {
          c.chooseInputIntent(
            _commandIntent ? InputIntentChoice.ai : InputIntentChoice.command,
          );
        }
        return KeyEventResult.handled;
      }
      if ((event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
          !keyboard.isShiftPressed &&
          !keyboard.isAltPressed &&
          !keyboard.isControlPressed &&
          !keyboard.isMetaPressed) {
        if (event is KeyDownEvent) unawaited(_submit());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: TextField(
      key: const Key('ai-prompt'),
      readOnly: c.followUpEnded || !_paneInteractive,
      controller: _input,
      focusNode: _focus,
      minLines: 1,
      maxLines: maxLines,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      onEditingComplete: () {},
      style: Theme.of(context).textTheme.bodyLarge,
      strutStyle: StrutStyle.fromTextStyle(
        Theme.of(context).textTheme.bodyLarge!,
        forceStrutHeight: true,
      ),
      decoration: InputDecoration(
        hintText: hintText ?? t('Ask about this terminal…', '向当前终端提问…'),
        isDense: dense ? true : null,
        hintMaxLines: dense ? 1 : null,
        contentPadding: dense
            ? const EdgeInsets.symmetric(vertical: 8)
            : null,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    ),
  );

  void _insertDiagnosis(AiBlockContext block) {
    if (c.followUpEnded || !_paneInteractive) return;
    if (_input.text.trim().isEmpty || !c.attachments.contains(block)) return;
    final value = _input.value;
    final offset = value.selection.isValid
        ? value.selection.extentOffset
        : value.text.length;
    final question = t(
      'Explain why this command failed and propose a corrected command: ${block.command}',
      '请解释这条命令失败的原因，并提出修正建议：${block.command}',
    );
    final insert =
        '${offset > 0 && value.text[offset - 1] != "\n" ? "\n" : ""}$question';
    _input.value = TextEditingValue(
      text: value.text.replaceRange(offset, offset, insert),
      selection: TextSelection.collapsed(offset: offset + insert.length),
    );
    c.chooseInputIntent(InputIntentChoice.ai);
  }

  Widget _pendingContexts({bool compact = false}) => TextButton.icon(
    key: const Key('ai-pending-contexts'),
    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    onPressed: () => showDialog<void>(
      context: context,
      animationStyle: appDialogAnimation(context),
      builder: (dialogContext) => AlertDialog(
        title: Text(t('Pending context', '待附加上下文')),
        content: ListenableBuilder(
          listenable: c,
          builder: (_, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < c.attachments.length; i++) ...[
                  _contextChip(c.attachments[i], removable: true),
                  if (!c.followUpEnded &&
                      _input.text.trim().isNotEmpty &&
                      c.attachments[i].exitCode != null &&
                      c.attachments[i].exitCode != 0)
                    TextButton.icon(
                      key: ValueKey(
                        'ai-insert-diagnosis-${c.attachments[i].id}',
                      ),
                      onPressed: () {
                        _insertDiagnosis(c.attachments[i]);
                        Navigator.pop(dialogContext);
                      },
                      icon: const Icon(Icons.add_comment_outlined),
                      label: Text(t('Insert diagnosis question', '插入诊断问题')),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('Close', '关闭')),
          ),
        ],
      ),
    ),
    icon: const Icon(Icons.attach_file, size: 18),
    label: Text(
      compact
          ? '${c.attachments.length}'
          : t(
              '${c.attachments.length} ${c.attachments.length == 1 ? 'source' : 'sources'}',
              '${c.attachments.length} 个来源',
            ),
    ),
  );

  Widget _inputIntentMenu({bool condensed = false}) {
    final command = _commandIntent;
    final label =
        '${c.inputIntentChoice == InputIntentChoice.automatic ? t('Auto · ', '自动 · ') : ''}${command ? t('Command', '命令') : 'AI'}';
    return PopupMenuButton<InputIntentChoice>(
      key: const Key('ai-input-intent'),
      enabled: _paneInteractive && !c.followUpEnded,
      popUpAnimationStyle: appDialogAnimation(context),
      tooltip: t('Input intent', '输入意图'),
      onSelected: (choice) {
        if (!_paneInteractive || c.followUpEnded) return;
        c.chooseInputIntent(choice);
        _focus.requestFocus();
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: InputIntentChoice.automatic,
          checked: c.inputIntentChoice == InputIntentChoice.automatic,
          child: Text(t('Automatic', '自动识别')),
        ),
        CheckedPopupMenuItem(
          value: InputIntentChoice.command,
          enabled:
              !c.busy &&
              c.pending == null &&
              c.attachments.isEmpty &&
              !widget.fullScreenTerminal,
          checked: c.inputIntentChoice == InputIntentChoice.command,
          child: Text(
            c.attachments.isEmpty
                ? t('Command', '命令')
                : t('Command · remove sources first', '命令 · 请先移除来源'),
          ),
        ),
        CheckedPopupMenuItem(
          value: InputIntentChoice.ai,
          checked: c.inputIntentChoice == InputIntentChoice.ai,
          child: const Text('AI'),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: condensed
                    ? Theme.of(context).textTheme.labelSmall
                    : Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _expandDraftButton() => IconButton(
    key: const Key('ai-expand-draft'),
    tooltip: t('Expand editor', '展开编辑'),
    onPressed: c.followUpEnded || !_paneInteractive ? null : _expandDraft,
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    icon: const Icon(Icons.open_in_full, size: 20),
  );

  Widget _hideKeyboardButton() => IconButton(
    key: const Key('ai-dismiss-keyboard'),
    tooltip: t('Hide keyboard', '收起键盘'),
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    onPressed: () {
      _focus.unfocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    },
    icon: const Icon(Icons.keyboard_hide_outlined),
  );

  Widget _sendButton({bool iconOnly = false}) {
    final command = _commandIntent;
    final canSend =
        _paneInteractive &&
        !c.followUpEnded &&
        _input.text.trim().isNotEmpty &&
        (!c.hasUnresolvedSubmission || !command) &&
        _input.value.composing.isCollapsed &&
        (!command || c.canRunUserCommand) &&
        (!_useCompactMobile || _mobileCanSubmit);
    final label = c.hasUnresolvedSubmission && !command
        ? t('Save requirement', '暂存要求')
        : command
        ? t('Run', '执行')
        : c.busy || c.canApprove
        ? t('Add requirement', '补充要求')
        : t('Send to AI', '发送给 AI');
    return Tooltip(
      message: label,
      child: FilledButton(
        key: const Key('ai-send'),
        focusNode: _sendFocus,
        onPressed: canSend ? _submit : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.symmetric(horizontal: iconOnly ? 10 : 12),
        ),
        child: iconOnly
            ? Icon(
                command
                    ? Icons.keyboard_return
                    : _useCompactMobile && c.hasUnresolvedSubmission
                    ? Icons.save_outlined
                    : Icons.arrow_upward,
                semanticLabel: label,
              )
            : Text(label),
      ),
    );
  }

  Widget _composer(
    bool compact, {
    bool short = false,
    bool singleRow = false,
    bool tiny = false,
    int maxLines = 4,
  }) {
    final palette = context.appTheme;
    if (tiny) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _prompt(maxLines: 1)),
                _expandDraftButton(),
                _hideKeyboardButton(),
                _sendButton(iconOnly: true),
              ],
            ),
            Row(
              children: [
                if (c.attachments.isNotEmpty) _pendingContexts(compact: true),
                Expanded(child: _inputIntentMenu()),
                Tooltip(
                  message: _status,
                  child: Semantics(
                    liveRegion: true,
                    label: _announcedStatus,
                    child: _taskActions(includeInlineActions: true),
                  ),
                ),
                IconButton(
                  key: const Key('ai-close'),
                  tooltip: t('Collapse to read-only terminal', '收起并只读查看终端'),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  onPressed: _collapseTask,
                  icon: const Icon(Icons.close, size: 20),
                ),
                if (widget.onObserveTerminal != null)
                  IconButton(
                    key: const Key('ai-observe-terminal'),
                    tooltip: t('View terminal (read-only)', '只读查看终端'),
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    onPressed: _observeTerminal,
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      margin: EdgeInsets.all(
        singleRow
            ? 4
            : compact
            ? 6
            : 12,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: singleRow
            ? 6
            : compact
            ? 8
            : 14,
        vertical: singleRow ? 0 : 6,
      ),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.borderStrong),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!short)
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: '${widget.targetLabel} · ${c.context?.cwd ?? ''}',
                    child: Text(
                      '${widget.targetLabel.isEmpty ? t('Current terminal', '当前终端') : widget.targetLabel} · ${c.context?.cwd ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                  ),
                ),
                if (c.attachments.isNotEmpty) _pendingContexts(),
              ],
            ),
          if (c.attachments.isNotEmpty && !short)
            LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < c.attachments.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: bounds.maxWidth,
                          ),
                          child: _contextChip(
                            c.attachments[i],
                            removable: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (!singleRow) _prompt(maxLines: maxLines),
          LayoutBuilder(
            builder: (context, bounds) => Row(
              children: [
                if (singleRow) ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: bounds.maxWidth * .3),
                    child: _inputIntentMenu(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: _prompt(maxLines: 1)),
                ] else
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _inputIntentMenu(),
                    ),
                  ),
                _expandDraftButton(),
                if (singleRow)
                  _sendButton(iconOnly: bounds.maxWidth < 480)
                else
                  Flexible(flex: 2, child: _sendButton()),
              ],
            ),
          ),
          if (compact && !singleRow)
            Row(
              children: [
                if (short && c.attachments.isNotEmpty) _pendingContexts(),
                if (View.of(context).viewInsets.bottom > 0)
                  _hideKeyboardButton(),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _statusBar(true),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final compact = bounds.maxHeight < 360 || bounds.maxWidth < 600;
      // Phone landscape keyboards can leave barely two control rows. Keep the
      // draft and primary action on one row without resizing the underlying PTY.
      // Reserve enough reading space for one full-sized timeline action too.
      // A three-row composer can otherwise consume a short 260-point window.
      final singleRow = _mobile && bounds.maxHeight < 320;
      final tiny = _mobile && bounds.maxHeight < 100;
      final short =
          bounds.maxHeight <
          360 * (_mobile ? 1 : MediaQuery.textScalerOf(context).scale(1));
      final narrow = _mobile || bounds.maxWidth < 600;
      final composer = _composer(
        compact,
        short: short,
        singleRow: singleRow,
        tiny: tiny,
        maxLines: bounds.maxHeight < 280 ? 1 : 4,
      );
      final items = <CommandBlockTimelineItem>[];
      final renderedBlocks = <String>{};
      void addSource(AiBlockContext source) {
        final id = source.id;
        if (widget.timelineBuilder == null ||
            id == null ||
            (source.sourceSessionId != null &&
                source.sourceSessionId != c.context?.sessionId &&
                !c.retainsSource(source.sourceSessionId!))) {
          return;
        }
        if (renderedBlocks.add('${source.sourceSessionId}:$id')) {
          items.add(
            CommandBlockTimelineItem.block(
              id,
              id: 'source-${source.sourceSessionId}-$id',
              sourceSessionId: source.sourceSessionId,
            ),
          );
        }
      }

      for (final entry in c.transcript) {
        for (final source in entry.contexts) {
          addSource(source);
        }
        if (entry.state == AiEntryState.accepted &&
            entry.blockId != null &&
            widget.timelineBuilder != null) {
          if (entry.approvalReview case final review?) {
            items.add(
              CommandBlockTimelineItem.content(
                'approval-${entry.id}',
                (_) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: AiApprovalNotice(review: review, confirmed: true),
                ),
              ),
            );
          }
          if (renderedBlocks.add(
            '${entry.target?.sessionId}:${entry.blockId}',
          )) {
            items.add(
              CommandBlockTimelineItem.block(
                entry.blockId,
                id: entry.id,
                sourceSessionId: entry.target?.sessionId,
              ),
            );
          }
        } else {
          items.add(
            CommandBlockTimelineItem.content(
              entry.id,
              (_) => _entry(entry, narrow),
            ),
          );
        }
      }
      for (final source in c.attachments) {
        addSource(source);
      }
      if (c.transcript.isEmpty && c.attachments.isEmpty) {
        items.add(
          CommandBlockTimelineItem.content('empty', (_) => _emptyState()),
        );
      }
      if (c.targetChanged && c.terminalError == null) {
        final target = c.context!;
        final original = c.originalTarget!;
        items.add(
          CommandBlockTimelineItem.content(
            'target-changed',
            (_) => AiTargetChangeNotice(
              original: original,
              current: target,
              zh: zh,
              unresolvedSubmission: c.hasUnresolvedSubmission,
              onReturn: widget.onInspectOriginalTarget ?? widget.onClose,
              onContinue: c.canResume && !_resuming
                  ? () => _resume(selectedTarget: target)
                  : null,
            ),
          ),
        );
      }
      final targetNoticeExplainsError =
          c.targetChanged &&
          (c.error == 'stale_context' || c.error == 'target_changed');
      // Mobile exposes recovery once in the pinned task strip/details sheet.
      // Original proposals and source/target notices stay in the transcript.
      if (!_useCompactMobile &&
          ((c.error != null && !targetNoticeExplainsError) ||
              c.terminalError != null ||
              c.hasUnresolvedSubmission ||
              c.followUpEnded)) {
        items.add(
          CommandBlockTimelineItem.content('error', (_) => _recovery()),
        );
      }
      final timeline =
          widget.timelineBuilder?.call(items, _scroll, _following) ??
          CommandTimelineView(
            controller: _scroll,
            followTail: () => _follow,
            itemIds: [for (final item in items) item.id],
            itemBuilder: (context, index) =>
                items[index].builder?.call(context) ?? const SizedBox.shrink(),
          );
      return Material(
        key: const Key('terminal-ai-workspace'),
        color: context.appTheme.panel,
        child: ExcludeFocus(
          excluding: !widget.active,
          child: IgnorePointer(
            ignoring: !widget.active,
            child: Focus(
              focusNode: _workspaceFocus,
              autofocus: widget.active,
              onKeyEvent: (_, event) {
                if (!widget.active) return KeyEventResult.ignored;
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape &&
                    (!_input.value.composing.isValid ||
                        _input.value.composing.isCollapsed)) {
                  if (_desktopReview != null) {
                    _closeDesktopReview();
                  } else {
                    _observeTerminal();
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: _reviewPresentation(
                _useCompactMobile
                    ? _mobilePage(timeline, bounds)
                    : tiny
                    ? SingleChildScrollView(
                        key: const Key('ai-short-window-scroll'),
                        child: _composer(
                          true,
                          short: true,
                          singleRow: true,
                          tiny: true,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!tiny) _header(compact, singleRow: singleRow),
                          Divider(
                            height: 1,
                            color: context.appTheme.borderStrong,
                          ),
                          Expanded(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification.depth == 0 &&
                                    (notification is ScrollStartNotification &&
                                            notification.dragDetails != null ||
                                        notification
                                                is UserScrollNotification &&
                                            notification.direction !=
                                                ScrollDirection.idle)) {
                                  _follow = false;
                                  _replyFocusAllowed = false;
                                  _positionRevision++;
                                  _restoringPosition = false;
                                }
                                return false;
                              },
                              child: Listener(
                                onPointerDown: (_) =>
                                    _replyFocusAllowed = false,
                                child: KeyedSubtree(
                                  key: ValueKey(_taskId),
                                  child: timeline,
                                ),
                              ),
                            ),
                          ),
                          if (!compact) _statusBar(false),
                          if (!_mobile && short)
                            // At large desktop text sizes keep reading space;
                            // the composer retains all controls in its scroll.
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: bounds.maxHeight * .5,
                              ),
                              child: SingleChildScrollView(child: composer),
                            )
                          else
                            composer,
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
