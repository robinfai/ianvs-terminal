import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'terminal_ai_controller.dart';

String aiResponseLabel(AiResponseStage stage, bool zh) => switch (stage) {
  AiResponseStage.connecting => zh ? '正在发送请求…' : 'Sending request…',
  AiResponseStage.waiting => zh ? '等待模型回复…' : 'Waiting for the model…',
  AiResponseStage.receivingText => zh ? '正在生成回复…' : 'Generating response…',
  AiResponseStage.receivingTool => zh ? '正在接收完整提案…' : 'Receiving full proposal…',
  AiResponseStage.completed => zh ? '回复已完成' : 'Response complete',
  AiResponseStage.cancelled => zh ? '生成已停止' : 'Generation stopped',
  AiResponseStage.failed => zh ? '回复未完成' : 'Response incomplete',
};

/// A real indeterminate request indicator, not a percentage or fabricated TTFT.
/// Reduced motion and inactive/offstage routes do not run an animation ticker.
class AiResponseActivity extends StatelessWidget {
  const AiResponseActivity({required this.label, this.animate = false, super.key});
  final String label;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final animated = animate && !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.of(context) && (ModalRoute.isCurrentOf(context) ?? true);
    return Semantics(
      container: true, liveRegion: true, label: label, excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          SizedBox(width: 18, height: 18,
              child: animated
                  ? CircularProgressIndicator(strokeWidth: 2,
                      color: context.appTheme.accent)
                  : Icon(Icons.hourglass_top_rounded, size: 18,
                      color: context.appTheme.textMuted)),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appTheme.textMuted))),
        ]),
      ),
    );
  }
}
