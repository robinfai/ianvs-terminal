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
    this.targetLabel = '',
    this.timelineBuilder,
    this.onInspectContext,
    this.onShowEvidence,
    this.onOpenLink,
    this.onReconnect,
    this.onConfigureTerminal,
    this.onInspectOriginalTarget,
    this.fullScreenTerminal = false,
    super.key,
  });
  final TerminalAiController controller;
  final VoidCallback onClose;
  final String targetLabel;
  final AiTimelineBuilder? timelineBuilder;
  final ValueChanged<AiBlockContext>? onInspectContext;
  final ValueChanged<AiEvidenceReference>? onShowEvidence;
  final ValueChanged<String>? onOpenLink;
  final Future<void> Function()? onReconnect;
  final Future<void> Function()? onConfigureTerminal;
  final VoidCallback? onInspectOriginalTarget;
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
  String? _settingsNotice;
  bool _restoringPosition = false;
  double? _returnOffset;
  CommandTimelineAnchor? _returnAnchor;
  int _positionRevision = 0;
  TerminalAiController get c => widget.controller;
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

  void _saveDraft() =>
      c.setDraft(_input.text, composing: !_input.value.composing.isCollapsed);
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
            // receipt arrives. Return ownership using the approved target too.
            (widget.fullScreenTerminal ||
                entry.target?.alternateScreen == true) &&
            entry.state == AiEntryState.accepted &&
            _returnedActions.add(entry.id)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onClose();
          });
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

  @override
  void didUpdateWidget(TerminalAiWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fullScreenTerminal && !oldWidget.fullScreenTerminal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onClose();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _replyFocusAllowed = false;
    if (!mounted || !_mobile) return;
    if (state != AppLifecycleState.resumed) {
      c.takeOver();
    } else {
      unawaited(c.refreshContext());
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

  Future<void> _submit() async {
    if (c.hasUnresolvedSubmission) return;
    if (_input.value.composing.isValid && !_input.value.composing.isCollapsed) {
      return;
    }
    final prompt = _input.text.trim();
    if (prompt.isEmpty) return;
    if (_commandIntent) {
      await c.runUserCommand(_input.text);
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

  String get _status => c.terminalError != null
      ? t('Terminal unavailable · check its status', '终端暂不可用 · 请检查状态')
      : c.hasUnresolvedSubmission
      ? t('Submission unknown · check original receipt', '提交状态未知 · 请检查原回执')
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
  String get _announcedStatus => c.phase == AiPhase.observing
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

  Widget _contextChip(AiBlockContext block, {VoidCallback? onRemove}) {
    final range = _contextRange(block);
    return InputChip(
      avatar: const Icon(Icons.terminal_outlined, size: 16),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
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
          ],
        ),
      ),
      tooltip: '${block.cwd}\n${block.command}\n$range',
      onPressed: () => _inspect(block),
      onDeleted: onRemove,
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
    final active =
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
          if (!active &&
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
                    onPressed: c.reject,
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

  Widget _proposalActions(AiTranscriptEntry entry, {VoidCallback? close}) =>
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 6,
        children: [
          if (entry.action!.kind == AiActionKind.runCommand)
            TextButton.icon(
              key: const Key('ai-edit-action'),
              onPressed: () => _edit(entry),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: Text(t('Edit', '编辑')),
            ),
          TextButton(
            key: const Key('ai-reject'),
            onPressed: () {
              c.reject();
              close?.call();
            },
            child: Text(t('Decline', '拒绝')),
          ),
          FilledButton(
            key: const Key('ai-approve'),
            focusNode: _approvalFocus,
            onPressed: () {
              // The approval button disappears on submit. Give its keyboard
              // ownership to the task, not a previously tabbed text region.
              if (!_mobile) _workspaceFocus.requestFocus();
              unawaited(c.approve(revision: entry.revision));
              close?.call();
            },
            child: Text(t('Run once', '执行一次')),
          ),
        ],
      );

  Future<void> _edit(AiTranscriptEntry entry) async {
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
    _focus.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!mounted) return;
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
              builder: (context, _) {
                final current = c.transcript
                    .where((e) => e.id == entry.id)
                    .firstOrNull;
                if (current == null ||
                    current.revision != entry.revision ||
                    current.state != AiEntryState.proposed) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t(
                              'The proposal changed. Return to review its latest revision.',
                              '提案已更新或撤销，请返回重新审阅。',
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(routeContext),
                            child: Text(t('Return to task', '返回任务')),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('ai-review-scroll'),
                        child: _proposal(current, false, reviewPage: true),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: _proposalActions(
                        current,
                        close: () => Navigator.pop(routeContext),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

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
                    task.title.isEmpty ? t('New task', '新任务') : task.title,
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
          IconButton(
            key: const Key('ai-close'),
            tooltip: t('Return to terminal and pause AI', '返回终端并暂停 AI'),
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    ),
  );

  Future<void> _resume({AiTerminalContext? selectedTarget}) async {
    if (_resuming) return;
    final controller = c;
    final taskId = controller.taskId;
    setState(() => _resuming = true);
    try {
      if (selectedTarget != null) {
        // The inline choice applies only to the target displayed at the click.
        // resume() refreshes the terminal and checks that guard before asking.
        await controller.resume(
          label: t('Continue on current target', '在当前目标继续'),
          useCurrentTarget: true,
          expectedTargetGuard: selectedTarget.guard,
        );
        return;
      }
      await controller.refreshContext();
      if (!mounted ||
          c != controller ||
          controller.taskId != taskId ||
          !controller.canResume) {
        return;
      }
      if (!controller.targetChanged) {
        await controller.resume(label: t('Continue task', '继续任务'));
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
                  onPressed: widget.onClose,
                  child: Text(t('Inspect in terminal', '返回终端检查')),
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
          if (action == 'interrupt') unawaited(c.interruptCommand());
          if (action == 'return') _returnToReading();
          if (action == 'keyboard') _workspaceFocus.requestFocus();
          if (action == 'pause') c.takeOver();
          if (action == 'resume') unawaited(_resume());
          if (action == 'latest') _showLatest();
        },
        itemBuilder: (_) => [
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
              child: Text(
                c.targetChanged
                    ? t('Continue on current target', '在当前目标继续')
                    : t('Continue task', '继续任务'),
              ),
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
                    tooltip: c.targetChanged
                        ? t('Continue on current target', '在当前目标继续')
                        : t('Continue task', '继续任务'),
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

  Widget _prompt(bool compact) => CallbackShortcuts(
    bindings: {
      SingleActivator(
        LogicalKeyboardKey.keyI,
        meta: Theme.of(context).platform == TargetPlatform.macOS,
        control: Theme.of(context).platform != TargetPlatform.macOS,
      ): () {
        if (!c.busy &&
            c.pending == null &&
            c.attachments.isEmpty &&
            !widget.fullScreenTerminal) {
          c.chooseInputIntent(
            _commandIntent ? InputIntentChoice.ai : InputIntentChoice.command,
          );
        }
      },
      const SingleActivator(LogicalKeyboardKey.enter): () =>
          unawaited(_submit()),
    },
    child: TextField(
      key: const Key('ai-prompt'),
      controller: _input,
      focusNode: _focus,
      minLines: 1,
      maxLines: compact ? 1 : 3,
      textInputAction: TextInputAction.send,
      onEditingComplete: () {},
      onSubmitted: (_) => unawaited(_submit()),
      decoration: InputDecoration(
        hintText: t('Ask about this terminal…', '向当前终端提问…'),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    ),
  );

  Widget _composer(
    bool compact, {
    bool short = false,
    bool singleRow = false,
    bool collapseActions = false,
  }) {
    final palette = context.appTheme;
    final commandIntent = _commandIntent;
    final canSend =
        _input.text.trim().isNotEmpty &&
        !c.hasUnresolvedSubmission &&
        (_input.value.composing.isCollapsed) &&
        (!commandIntent || c.canRunUserCommand);
    return Container(
      margin: EdgeInsets.all(
        singleRow
            ? 4
            : compact
            ? 6
            : 12,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: singleRow ? 6 : (compact ? 8 : 14),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${widget.targetLabel.isEmpty ? t('Current terminal', '当前终端') : widget.targetLabel} · ${c.context?.cwd ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
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
                            onRemove: () => c.removeAttachment(i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (!singleRow) _prompt(compact),
          Row(
            children: [
              PopupMenuButton<String>(
                key: const Key('ai-input-intent'),
                popUpAnimationStyle: appDialogAnimation(context),
                tooltip: t('Input intent', '输入意图'),
                onSelected: (value) {
                  c.chooseInputIntent(InputIntentChoice.values.byName(value));
                  _focus.requestFocus();
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 'automatic',
                    checked: c.inputIntentChoice == InputIntentChoice.automatic,
                    child: Text(t('Automatic', '自动识别')),
                  ),
                  CheckedPopupMenuItem(
                    value: 'command',
                    enabled:
                        !c.busy &&
                        c.pending == null &&
                        c.attachments.isEmpty &&
                        !widget.fullScreenTerminal,
                    checked: c.inputIntentChoice == InputIntentChoice.command,
                    child: Text(t('Command', '命令')),
                  ),
                  CheckedPopupMenuItem(
                    value: 'ai',
                    checked: c.inputIntentChoice == InputIntentChoice.ai,
                    child: Text(t('Ask AI', 'AI 提问')),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: _mobile ? 28 : 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          commandIntent
                              ? Icons.terminal_outlined
                              : Icons.auto_awesome_outlined,
                          size: 18,
                          color: palette.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          compact
                              ? commandIntent
                                    ? t('Run', '命令')
                                    : 'AI'
                              : '${commandIntent ? t('Command', '命令') : t('Ask AI', 'AI 提问')}${c.inputIntentChoice == InputIntentChoice.automatic ? t(' · Auto', ' · 自动') : ''}',
                        ),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              if (singleRow) Expanded(child: _prompt(true)),
              if (short && c.attachments.isNotEmpty)
                IconButton(
                  key: const Key('ai-pending-contexts'),
                  tooltip: t(
                    '${c.attachments.length} pending contexts',
                    '${c.attachments.length} 个待附加上下文',
                  ),
                  onPressed: () => showDialog<void>(
                    context: context,
                    animationStyle: appDialogAnimation(context),
                    builder: (dialogContext) => AlertDialog(
                      title: Text(t('Pending context', '待附加上下文')),
                      content: ListenableBuilder(
                        listenable: c,
                        builder: (_, _) => SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var i = 0; i < c.attachments.length; i++)
                                _contextChip(
                                  c.attachments[i],
                                  onRemove: () => c.removeAttachment(i),
                                ),
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
                  icon: const Icon(Icons.attach_file),
                ),
              if (singleRow)
                _statusBar(true, collapsed: collapseActions)
              else if (compact)
                Expanded(child: _statusBar(true)),
              if (compact)
                IconButton(
                  key: const Key('ai-send'),
                  focusNode: _sendFocus,
                  tooltip: commandIntent
                      ? t('Run command', '执行命令')
                      : t('Send to AI', '发送给 AI'),
                  onPressed: canSend ? _submit : null,
                  icon: Icon(
                    commandIntent ? Icons.keyboard_return : Icons.arrow_upward,
                  ),
                )
              else
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('ai-send'),
                      focusNode: _sendFocus,
                      onPressed: canSend ? _submit : null,
                      style: FilledButton.styleFrom(
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                      ),
                      child: Text(
                        commandIntent
                            ? t('Run command', '执行命令')
                            : c.busy || c.canApprove
                            ? t('Add requirement', '补充要求')
                            : t('Send to AI', '发送给 AI'),
                      ),
                    ),
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
      final singleRow = _mobile && bounds.maxHeight < 200;
      final narrow = _mobile || bounds.maxWidth < 600;
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
          CommandBlockTimelineItem.content(
            'empty',
            (_) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                t(
                  'Describe a task, or attach command output. AI actions are reviewed before execution.',
                  '描述任务，或附上命令输出。AI 提出的终端动作将在执行前单独审阅。',
                ),
              ),
            ),
          ),
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
      if ((c.error != null && !targetNoticeExplainsError) ||
          c.terminalError != null ||
          c.hasUnresolvedSubmission) {
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
        child: Focus(
          focusNode: _workspaceFocus,
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape &&
                (!_input.value.composing.isValid ||
                    _input.value.composing.isCollapsed)) {
              widget.onClose();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(compact, singleRow: singleRow),
              Divider(height: 1, color: context.appTheme.borderStrong),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.depth == 0 &&
                        (notification is ScrollStartNotification &&
                                notification.dragDetails != null ||
                            notification is UserScrollNotification &&
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
                    onPointerDown: (_) => _replyFocusAllowed = false,
                    child: KeyedSubtree(
                      key: ValueKey(_taskId),
                      child: timeline,
                    ),
                  ),
                ),
              ),
              if (!compact) _statusBar(false),
              _composer(
                compact,
                short: bounds.maxHeight < 360,
                singleRow: singleRow,
                collapseActions: singleRow && bounds.maxWidth < 480,
              ),
            ],
          ),
        ),
      );
    },
  );
}
