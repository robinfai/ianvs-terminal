import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_ui.dart';
import 'ai_approval_notice.dart';
import 'ai_models.dart';
import 'ai_settings_dialog.dart';
import 'ai_strings.dart';
import 'terminal_ai_controller.dart';

/// Bounded overlay: opening AI never resizes or replaces the full-screen PTY.
class TerminalAiPanel extends StatefulWidget {
  const TerminalAiPanel({
    required this.controller,
    required this.onClose,
    super.key,
  });
  final TerminalAiController controller;
  final VoidCallback onClose;
  @override
  State<TerminalAiPanel> createState() => _TerminalAiPanelState();
}

class _TerminalAiPanelState extends State<TerminalAiPanel> {
  final _input = TextEditingController();
  final _focus = FocusNode(debugLabel: 'AI input');
  final _scroll = ScrollController();
  int _transcriptLength = -1;
  String? _proposalId;
  TerminalAiController get c => widget.controller;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String en, String cn) => zh ? cn : en;

  String get _status => switch (c.phase) {
    AiPhase.thinking => t('Thinking…', '正在思考…'),
    AiPhase.reviewing => t('Reviewing command safety…', '正在审核命令…'),
    AiPhase.executing => t('Checking command result…', '正在获取命令结果…'),
    AiPhase.observing => t('Waiting for terminal state…', '正在等待终端状态更新…'),
    AiPhase.awaitingApproval => t('Review the proposed input', '请确认待执行内容'),
    AiPhase.failed =>
      c.error == 'step_limit'
          ? t('Turn paused at step limit', '本轮已达上限，可继续任务')
          : t('Needs attention', '需要处理'),
    AiPhase.idle =>
      c.takenOver
          ? t('AI paused · terminal keeps running', 'AI 已暂停 · 终端继续运行')
          : c.transcript.isEmpty
          ? t('Ready for your task', '等待你的任务')
          : t('Response received', '已收到回复'),
  };

  void _showLatest() {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  @override
  void initState() {
    super.initState();
    c.addListener(_contentChanged);
    _contentChanged();
  }

  void _contentChanged() {
    if (_transcriptLength == c.transcript.length &&
        _proposalId == c.pending?.id) {
      return;
    }
    final follow = !_scroll.hasClients || _scroll.position.extentAfter < 80;
    _transcriptLength = c.transcript.length;
    _proposalId = c.pending?.id;
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    c.removeListener(_contentChanged);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit() {
    if (c.busy || _input.text.trim().isEmpty) return;
    if (c.settings.configuration == null) {
      unawaited(showAiSettings(context, c.settings));
      return;
    }
    final text = _input.text;
    _input.clear();
    unawaited(c.ask(text));
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) => Material(
          key: const Key('terminal-ai-panel'),
          color: palette.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: palette.borderStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            liveRegion: constraints.maxHeight < 360,
                            child: Text(
                              constraints.maxHeight < 360
                                  ? _status
                                  : t('Terminal AI', '终端 AI'),
                              key: constraints.maxHeight < 360
                                  ? const Key('ai-task-status')
                                  : null,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: constraints.maxHeight < 360
                                  ? Theme.of(context).textTheme.bodySmall
                                  : Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (c.settings.configuration case final config?
                              when constraints.maxHeight >= 360)
                            Text(
                              config.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: palette.textMuted),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: t('New conversation', '新对话'),
                      onPressed: c.busy ? null : c.clear,
                      icon: const Icon(Icons.add, size: 19),
                    ),
                    IconButton(
                      key: const Key('ai-open-settings'),
                      tooltip: t('AI connection', 'AI 连接'),
                      onPressed: () => showAiSettings(context, c.settings),
                      icon: const Icon(Icons.settings_outlined, size: 19),
                    ),
                    IconButton(
                      key: const Key('ai-close'),
                      tooltip: t('Close and pause AI', '关闭并暂停 AI'),
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, size: 19),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.borderStrong),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (c.transcript.isEmpty) ...[
                        Text(
                          t(
                            'Describe what you want to do. Ask about a failed command, or work inside vim, vi and k9s.',
                            '描述你想做什么。可以纠正报错命令，也可以协助操作 vim、vi 和 k9s。',
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        t(
                          'Current terminal · ${c.context?.cwd ?? ''}',
                          '当前终端 · ${c.context?.cwd ?? ''}',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      if (c.context?.lastBlock?.exitCode case final int exit
                          when exit != 0)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const Key('ai-correct-command'),
                            onPressed: c.busy ? null : c.correctLastCommand,
                            child: Text(t('Correct failed command', '纠正报错命令')),
                          ),
                        ),
                      for (final entry in c.transcript)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                switch (entry.role) {
                                  'user' => t('You', '你'),
                                  'tool' => t('Sent to terminal', '已发送至终端'),
                                  _ => 'AI',
                                },
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: palette.textMuted),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                entry.text,
                                style: entry.role == 'tool'
                                    ? const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      )
                                    : null,
                              ),
                              if (entry.approvalReview case final review?)
                                AiApprovalNotice(
                                  review: review,
                                  confirmed:
                                      entry.state == AiEntryState.accepted ||
                                      entry.state == AiEntryState.submitted,
                                ),
                            ],
                          ),
                        ),
                      if (c.pending case final AiAction action
                          when c.canApprove)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(action.reason),
                              const SizedBox(height: 8),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: SelectableText(
                                    action.preview,
                                    key: const Key('ai-action-preview'),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  FilledButton(
                                    key: const Key('ai-approve'),
                                    onPressed: c.canApprove ? c.approve : null,
                                    child: Text(t('Run once', '执行一次')),
                                  ),
                                  TextButton(
                                    key: const Key('ai-reject'),
                                    onPressed: c.reject,
                                    child: Text(t('Decline', '拒绝')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (c.takenOver)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            t(
                              'AI is paused. A running command is not interrupted. Continue when ready; new input still needs approval.',
                              'AI 已暂停，正在运行的命令不会被中断。可继续任务，新的输入仍需确认。',
                            ),
                          ),
                        ),
                      if (c.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            aiErrorText(c.error!, zh),
                            key: const Key('ai-error'),
                            style: TextStyle(
                              color: c.error == 'step_limit'
                                  ? palette.textMuted
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: palette.borderStrong),
              if (constraints.maxHeight >= 360)
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Row(
                    children: [
                      if (c.busy) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _status,
                            key: const Key('ai-task-status'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                      if (c.canResume)
                        TextButton(
                          key: const Key('ai-resume'),
                          onPressed: () =>
                              c.resume(label: t('Continue task', '继续任务')),
                          child: Text(t('Continue task', '继续任务')),
                        ),
                      IconButton(
                        key: const Key('ai-show-latest'),
                        tooltip: c.canApprove
                            ? t('Review pending action', '查看待执行动作')
                            : t('Show latest response', '查看最新回复'),
                        onPressed: _showLatest,
                        icon: const Icon(
                          Icons.arrow_downward_rounded,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            _submit();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          key: const Key('ai-prompt'),
                          controller: _input,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: constraints.maxHeight < 360 ? 1 : 3,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: t('Ask about this terminal…', '向当前终端提问…'),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    if (c.busy || c.pending != null)
                      IconButton(
                        key: const Key('ai-take-over'),
                        tooltip: t('Take over', '接管终端'),
                        onPressed: c.takeOver,
                        icon: const Icon(Icons.stop_rounded),
                      ),
                    if (constraints.maxHeight < 360 && c.canResume)
                      IconButton(
                        key: const Key('ai-resume'),
                        tooltip: t('Continue task', '继续任务'),
                        onPressed: () =>
                            c.resume(label: t('Continue task', '继续任务')),
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                    if (constraints.maxHeight < 360)
                      IconButton(
                        key: const Key('ai-show-latest'),
                        tooltip: c.canApprove
                            ? t('Review pending action', '查看待执行动作')
                            : t('Show latest response', '查看最新回复'),
                        onPressed: _showLatest,
                        icon: const Icon(
                          Icons.arrow_downward_rounded,
                          size: 18,
                        ),
                      ),
                    IconButton(
                      key: const Key('ai-send'),
                      tooltip: t('Send to AI', '发送给 AI'),
                      onPressed: c.busy ? null : _submit,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
