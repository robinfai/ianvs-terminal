import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'ai_models.dart';

/// The same target evidence is used beside the timeline action and in the
/// resume dialog. Shell context IDs are retained: a tab title alone cannot
/// distinguish successive SSH hops within that tab.
class AiTargetComparison extends StatelessWidget {
  const AiTargetComparison({
    required this.original,
    required this.current,
    required this.zh,
    super.key,
  });

  final AiTerminalContext original;
  final AiTerminalContext current;
  final bool zh;

  Widget _target(BuildContext context, String label, AiTerminalContext target) {
    final theme = Theme.of(context).textTheme;
    final palette = context.appTheme;
    final title = target.targetLabel.trim().isEmpty
        ? target.sessionId
        : target.targetLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label  ',
                style: TextStyle(color: palette.textMuted),
              ),
              TextSpan(
                text: title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          style: theme.bodyMedium,
        ),
        if (target.cwd.isNotEmpty) Text(target.cwd, style: theme.bodyMedium),
        Text(
          '${zh ? '终端上下文' : 'Shell context'}: ${target.contextId}',
          style: theme.bodySmall?.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.appTheme.chrome,
      borderRadius: BorderRadius.circular(context.appTheme.radius.md),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _target(context, zh ? '原目标' : 'Original target', original),
          const SizedBox(height: 12),
          _target(context, zh ? '当前目标' : 'Current target', current),
          if (original.sessionId != current.sessionId) ...[
            const SizedBox(height: 12),
            Text(
              zh
                  ? '这是新建立的连接。旧连接的输出仍作为证据保留。'
                  : 'This is a new connection. Output from the previous connection remains available as evidence.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}

class AiTargetChangeNotice extends StatelessWidget {
  const AiTargetChangeNotice({
    required this.original,
    required this.current,
    required this.zh,
    required this.onReturn,
    required this.onContinue,
    this.unresolvedSubmission = false,
    super.key,
  });

  final AiTerminalContext original;
  final AiTerminalContext current;
  final bool zh;
  final VoidCallback onReturn;
  final VoidCallback? onContinue;
  final bool unresolvedSubmission;

  static String explanation(bool zh) => zh
      ? '旧提案已失效。继续前会重新读取当前终端，新命令仍需单独确认。'
      : 'Previous proposals are no longer valid. Continuing reads the current '
            'terminal again. New commands still need your approval.';

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            zh ? '执行目标已改变' : 'Execution target changed',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 12),
        AiTargetComparison(original: original, current: current, zh: zh),
        const SizedBox(height: 12),
        Text(
          unresolvedSubmission
              ? zh
                    ? '原连接仍有结果未知的提交。请先核对原回执，重连不会重发命令。'
                    : 'A submission on the original connection is still unknown. Check its receipt first. Reconnecting does not resend it.'
              : explanation(zh),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const Key('ai-target-return'),
              onPressed: onReturn,
              child: Text(zh ? '返回终端检查原目标' : 'Inspect original in terminal'),
            ),
            FilledButton(
              key: const Key('ai-target-continue'),
              onPressed: onContinue,
              child: Text(zh ? '在当前目标继续' : 'Continue on current target'),
            ),
          ],
        ),
      ],
    ),
  );
}
