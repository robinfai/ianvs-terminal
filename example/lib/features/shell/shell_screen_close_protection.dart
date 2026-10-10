part of 'shell_screen.dart';

class _CloseProtectionSnapshot {
  const _CloseProtectionSnapshot({
    required this.sessionId,
    required this.wholeTab,
    required this.tokens,
    required this.panes,
  });

  final String sessionId;
  final bool wholeTab;
  final List<Object?> tokens;
  final List<_CloseProtectionPane> panes;

  bool get needsConfirmation => panes.any((pane) => pane.risks.isNotEmpty);
}

class _CloseProtectionPane {
  const _CloseProtectionPane(this.label, this.risks, this.drafts);

  final String label;
  final List<String> risks;
  final List<({String label, String text})> drafts;
}

extension _ShellScreenCloseProtection on _ShellScreenState {
  _CloseProtectionSnapshot? _closeProtectionSnapshot(
    String sessionId, {
    required bool wholeTab,
  }) {
    if (!mounted) return null;
    final state = ref.read(sessionControllerProvider);
    final tab = wholeTab
        ? state.tabs.where((tab) => tab.sessionId == sessionId).firstOrNull
        : _tabForSession(state, sessionId);
    if (tab == null) return null;
    final panes = wholeTab
        ? tab.effectivePanes
        : tab.effectivePanes
              .where((pane) => pane.sessionId == sessionId)
              .toList(growable: false);
    if (panes.isEmpty) return null;
    final closingIds = panes.map((pane) => pane.sessionId).toSet();
    if (panes.any(
      (pane) =>
          _sessionSourceInUse(pane.sessionId, closingSessions: closingIds),
    )) {
      return null;
    }
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final tokens = <Object?>[tab.sessionId];
    final details = <_CloseProtectionPane>[];
    for (final pane in panes) {
      final id = pane.sessionId;
      final shell = pane.shellIntegration;
      final ai = _aiSessions[id];
      final composer = _composerSessions[id]?.controller;
      final command = pane.isExited ? null : shell.runningCommand;
      final risks = <String>[];
      final drafts = <({String label, String text})>[];
      tokens.addAll([
        id,
        pane.isExited,
        shell.contextId,
        shell.hostname,
        shell.currentDirectory,
        command,
        shell.commandStartedAt,
        ai,
        ai?.taskId,
        ai?.pending,
        ai?.interrupting,
        composer?.ownership,
        composer?.pendingSubmission?.id,
        composer?.editor.text,
      ]);
      if (command != null) {
        risks.add(zh ? '命令运行中：$command' : 'Running command: $command');
      }
      if (composer != null) {
        switch (composer.ownership) {
          case terminal.ComposerOwnership.submitting:
            risks.add(zh ? '命令正在提交。' : 'A command is being submitted.');
          case terminal.ComposerOwnership.unknown:
            risks.add(
              zh
                  ? '命令结果尚未核对；未知不代表未执行。'
                  : 'A command result is unresolved; unknown does not mean unexecuted.',
            );
          case terminal.ComposerOwnership.running:
            if (command == null && !pane.isExited) {
              risks.add(
                zh ? '终端命令仍在运行。' : 'A terminal command is still running.',
              );
            }
          default:
            break;
        }
        if (composer.editor.text.isNotEmpty) {
          drafts.add((
            label: zh ? '命令草稿' : 'Command draft',
            text: composer.editor.text,
          ));
        }
      }
      for (final task in ai?.tasks ?? const <AiTaskSummary>[]) {
        final taskLabel = task.title.isEmpty ? task.id : task.title;
        tokens.addAll([
          task.id,
          task.phase,
          task.proposalRevision,
          task.draftRevision,
          task.draft,
          task.hasUnresolvedSubmission,
          task.unresolvedEntryIds.length,
          ...task.unresolvedEntryIds,
          task.attachments.length,
          ...task.attachments,
        ]);
        final phase = switch (task.phase) {
          AiPhase.thinking => zh ? '分析中' : 'analysing',
          AiPhase.reviewing => zh ? '审核中' : 'reviewing',
          AiPhase.awaitingApproval =>
            zh ? '有未审提案' : 'has an unreviewed proposal',
          AiPhase.executing => zh ? '提交或执行中' : 'submitting or executing',
          AiPhase.observing => zh ? '正在跟进终端结果' : 'following terminal output',
          AiPhase.idle || AiPhase.failed => null,
        };
        if (phase != null) {
          risks.add('AI · $taskLabel · $phase');
          if (task.id == ai?.taskId && ai?.pending != null) {
            risks.add(ai!.pending!.preview);
          }
        }
        if (task.hasUnresolvedSubmission) {
          risks.add(
            zh
                ? 'AI · $taskLabel · 结果尚未核对；未知不代表未执行。'
                : 'AI · $taskLabel · Result unresolved; unknown does not mean unexecuted.',
          );
        }
        if (task.draft.isNotEmpty) {
          drafts.add((label: 'AI · $taskLabel', text: task.draft));
        }
      }
      if (ai?.interrupting == true) {
        risks.add(
          zh ? '正在请求中断终端命令。' : 'A command interruption is in progress.',
        );
      }
      final target = shell.hostname;
      final directory = shell.currentDirectory;
      details.add(
        _CloseProtectionPane(
          '${pane.title} · Session $id'
          '${target == null ? '' : '\n$target'}'
          '${directory == null ? '' : '\n$directory'}',
          risks,
          drafts,
        ),
      );
    }
    return _CloseProtectionSnapshot(
      sessionId: sessionId,
      wholeTab: wholeTab,
      tokens: tokens,
      panes: details,
    );
  }

  bool _closeProtectionStillValid(_CloseProtectionSnapshot approved) {
    if (!mounted) return false;
    final current = _closeProtectionSnapshot(
      approved.sessionId,
      wholeTab: approved.wholeTab,
    );
    if (current != null && listEquals(approved.tokens, current.tokens)) {
      return true;
    }
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    _showShellSnackBar(
      zh
          ? '会话、窗格或任务已变化。请检查后重新关闭。'
          : 'The sessions, panes, or tasks changed. Review them before closing again.',
    );
    return false;
  }

  Future<bool> _confirmProtectedClose(_CloseProtectionSnapshot snapshot) async {
    if (!snapshot.needsConfirmation) return true;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final drafts = [
      for (final pane in snapshot.panes)
        for (final draft in pane.drafts)
          '${pane.label} · ${draft.label}\n${draft.text}',
    ].join('\n\n');
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            key: const Key('shell-close-protection'),
            scrollable: true,
            title: Text(
              snapshot.wholeTab
                  ? (zh ? '关闭此标签页？' : 'Close this tab?')
                  : (zh ? '关闭此窗格？' : 'Close this pane?'),
            ),
            content: SizedBox(
              width: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    zh
                        ? '将关闭以下本地会话连接，并移除其内存中的 AI 任务与草稿。关闭连接不保证远端进程停止，已提交操作不会因此撤销。'
                        : 'This closes the local session connections below and removes their in-memory AI tasks and drafts. Closing a connection does not guarantee remote processes stop or undo submitted operations.',
                  ),
                  for (final pane in snapshot.panes) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      pane.label,
                      style: Theme.of(dialogContext).textTheme.titleSmall,
                    ),
                    for (final risk in pane.risks) ...[
                      const SizedBox(height: 8),
                      SelectableText(risk),
                    ],
                    for (final draft in pane.drafts) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${draft.label} · ${zh ? '草稿' : 'Draft'}',
                        style: Theme.of(dialogContext).textTheme.labelMedium,
                      ),
                      Text(
                        draft.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              if (drafts.isNotEmpty)
                TextButton.icon(
                  key: const Key('shell-close-copy-drafts'),
                  onPressed: () =>
                      ClipboardBridge.copyWithFeedback(dialogContext, drafts),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(zh ? '复制这些草稿' : 'Copy these drafts'),
                ),
              TextButton(
                key: const Key('shell-close-cancel'),
                autofocus: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(zh ? '取消' : 'Cancel'),
              ),
              FilledButton(
                key: const Key('shell-close-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(zh ? '关闭' : 'Close'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
