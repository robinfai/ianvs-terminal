import 'package:flutter/material.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart'
    show CommandBlockReaderHostController, ComposerOwnership;

import '../../../ui/app_ui.dart';
import '../../ai/terminal_ai_controller.dart';
import '../../sessions/session_state.dart';
import '../../terminal_composer/composer_pane.dart';
import '../../terminal_composer/terminal_mode.dart';

/// Display-only state for the active pane. This widget never creates a session,
/// queries the terminal or obtains an input owner to populate missing data.
class DesktopSessionStatus extends StatelessWidget {
  const DesktopSessionStatus({
    required this.sessionId,
    required this.pane,
    required this.composer,
    required this.ai,
    required this.aiVisible,
    required this.observing,
    required this.readOnly,
    required this.replaying,
    required this.onDetails,
    this.reader,
    super.key,
  });

  final String? sessionId;
  final TerminalPane? pane;
  final ComposerPaneSession? composer;
  final TerminalAiController? ai;
  final bool aiVisible;
  final bool observing;
  final bool readOnly;
  final bool replaying;
  final VoidCallback? onDetails;
  final CommandBlockReaderHostController? reader;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([composer, composer?.controller, ai, reader]),
    builder: (context, _) {
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      String t(String en, String cn) => zh ? cn : en;
      final current = pane?.sessionId == sessionId ? pane : null;
      final currentComposer = composer?.sessionId == sessionId
          ? composer
          : null;
      final shell = current?.shellIntegration;
      final user = shell?.username ?? shell?.sshUser;
      final host = shell?.hostname ?? shell?.sshHost;
      final target = current == null
          ? sessionId == null
                ? t('No active terminal', '无活动终端')
                : t('Checking active target…', '正在核对活动目标…')
          : host?.isNotEmpty == true
          ? '${user?.isNotEmpty == true ? '$user@' : ''}$host'
          : current.title;
      final mode = replaying
          ? t('Replay', '回放')
          : reader?.isOpen == true
          ? t('Evidence reader', '证据阅读器')
          : observing
          ? t('Read-only observer', '只读观察')
          : aiVisible
          ? t('AI task', 'AI 任务')
          : currentComposer?.enabled == true
          ? 'Blocks'
          : t('Terminal', '终端');
      final owner =
          current == null ||
              current.isExited ||
              readOnly ||
              replaying ||
              reader?.blocksInput == true
          ? t('Read-only', '只读')
          : aiVisible
          ? ai?.phase == AiPhase.executing
                ? t('AI · this operation', 'AI · 本次操作')
                : t('Human input paused', '人工输入已暂停')
          : t('Human input', '人工输入');
      final shellState = current == null
          ? t('Checking…', '正在核对…')
          : current.isExited
          ? current.exitCode == null
                ? t('Disconnected', '连接已断开')
                : t(
                    'Disconnected · exit ${current.exitCode}',
                    '连接已断开 · 退出码 ${current.exitCode}',
                  )
          : currentComposer?.mode.state.unavailableReason ==
                BlockUnavailableReason.checking
          ? t('Checking shell state…', '正在核对 Shell 状态…')
          : switch (currentComposer?.controller.ownership) {
              ComposerOwnership.ready => t('Shell ready', 'Shell 已就绪'),
              ComposerOwnership.submitting => t('Submitting', '正在提交'),
              ComposerOwnership.unknown => t('Submission unknown', '提交结果未知'),
              ComposerOwnership.running => t('Command running', '命令运行中'),
              ComposerOwnership.suspended => t('Interactive input', '交互输入'),
              _ =>
                shell?.runningCommand != null
                    ? t('Command running', '命令运行中')
                    : t('Checking shell state…', '正在核对 Shell 状态…'),
            };
      // Shell checks and disconnects do not settle an unknown AI or manual
      // submission. Keep its receipt visible alongside the current shell fact.
      final state = {
        if (ai?.hasUnresolvedSubmission == true ||
            currentComposer?.controller.ownership == ComposerOwnership.unknown)
          t('Submission unknown', '提交结果未知'),
        shellState,
      }.join(' · ');
      final detail = [
        target,
        if (current != null) '${t('Session', '会话')}: ${current.sessionId}',
        if (shell?.contextId != null) '${t('Node', '节点')}: ${shell!.contextId}',
        if (shell?.currentDirectory?.isNotEmpty == true)
          shell!.currentDirectory!,
        mode,
        owner,
        state,
      ].join('\n');
      final palette = context.appTheme;
      return Semantics(
        key: const Key('desktop-session-status'),
        label: detail,
        button: onDetails != null,
        excludeSemantics: true,
        onTap: onDetails,
        child: Tooltip(
          message: detail,
          child: Material(
            color: palette.chrome,
            child: InkWell(
              onTap: onDetails,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: palette.border)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: palette.spacing.md,
                    vertical: palette.spacing.xs,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        Expanded(
                          child: Text(
                            constraints.maxWidth < 600
                                ? '$target · $owner'
                                : '$target · $mode · $owner',
                            key: const Key('desktop-status-target'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        SizedBox(width: palette.spacing.md),
                        Flexible(
                          child: Text(
                            state,
                            key: const Key('desktop-status-state'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (onDetails != null) ...[
                          SizedBox(width: palette.spacing.sm),
                          const Icon(Icons.info_outline, size: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
