import 'package:flutter/material.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

/// In-memory observation surface used after collapsing a preview task.
/// Reading retained Blocks never takes over, submits, or cancels the task.
class AiObservationPreview extends StatelessWidget {
  const AiObservationPreview({
    required this.blocks,
    required this.onReturn,
    required this.onPrepareDraft,
    super.key,
  });

  final CommandBlockController blocks;
  final VoidCallback onReturn;
  final ValueChanged<String> onPrepareDraft;

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final resultStyle = ComposerTheme.of(context).resultStyle;
    return Column(
      key: const Key('ai-preview-observation'),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                chinese
                    ? '只读预览 · AI 任务已保留'
                    : 'Read-only preview · AI task retained',
              ),
              TextButton(
                key: const Key('ai-preview-return'),
                onPressed: onReturn,
                child: Text(chinese ? '返回 AI 任务' : 'Return to AI task'),
              ),
            ],
          ),
        ),
        Expanded(
          child: TerminalCommandBlocksView(
            controller: blocks,
            font: const TerminalFontConfig().copyWith(
              family: resultStyle.fontFamily,
              fallback: resultStyle.fontFamilyFallback,
            ),
            onReinput: onPrepareDraft,
            showToolbar: false,
            chinese: chinese,
          ),
        ),
      ],
    );
  }
}
