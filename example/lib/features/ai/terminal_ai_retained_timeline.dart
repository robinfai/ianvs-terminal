import 'package:flutter/material.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../ui/foundation/app_motion.dart';
import 'ai_models.dart';
import 'terminal_ai_connections.dart';
import 'terminal_ai_controller.dart';

/// Renders retained native evidence alongside the task's current connection.
/// The only copied fields are presentation identities; reads use native IDs.
class TerminalAiRetainedTimeline extends StatelessWidget {
  const TerminalAiRetainedTimeline({
    required this.controller,
    required this.items,
    required this.scroll,
    required this.followTail,
    required this.font,
    required this.onReinput,
    this.onOpenLinkTarget,
    this.sourceLabelFor,
    super.key,
  });
  final TerminalAiController controller;
  final List<CommandBlockTimelineItem> items;
  final ScrollController scroll;
  final ValueNotifier<bool> followTail;
  final TerminalFontConfig font;
  final ValueChanged<String> onReinput;
  final ValueChanged<TerminalLinkTarget>? onOpenLinkTarget;
  final String? Function(String sessionId)? sourceLabelFor;

  @override
  Widget build(BuildContext context) {
    final connections = controller.terminal as TerminalAiConnections;
    void attach(CommandBlock block, {bool range = false}) => controller
        .attachContext(connections.evidenceContext(block, useSnapshot: range));
    return TerminalCommandBlocksView(
      controller: connections.evidence,
      timeline: [
        for (final item in items)
          if (item.blockId == null)
            item
          else
            CommandBlockTimelineItem.block(
              TerminalAiConnections.evidenceId(
                item.sourceSessionId ?? connections.sessionId,
                item.blockId!,
              ),
              id: item.id,
              sourceSessionId: item.sourceSessionId ?? connections.sessionId,
              sourceLabel:
                  sourceLabelFor?.call(
                    item.sourceSessionId ?? connections.sessionId,
                  ) ??
                  (Localizations.localeOf(context).languageCode == 'zh'
                      ? '保留的来源终端'
                      : 'Retained source terminal'),
            ),
      ],
      scrollController: scroll,
      followTail: followTail,
      showToolbar: false,
      chinese: Localizations.localeOf(context).languageCode == 'zh',
      font: font,
      onReinput: onReinput,
      onAskAi: attach,
      onAttachRange: (block) => attach(block, range: true),
      onAttachBlocks: (blocks) {
        for (final block in blocks) {
          attach(block);
        }
      },
      onOpenLinkTarget: onOpenLinkTarget,
    );
  }
}

/// Opens the exact supplied snapshot, never an arbitrary block with the same ID.
Future<String?> showAiEvidenceReader(
  BuildContext context, {
  required CommandBlockController controller,
  required AiEvidenceReference reference,
  required String sourceSessionId,
  String? sourceLabel,
  String? blockId,
  TerminalFontConfig font = const TerminalFontConfig(),
  ValueChanged<CommandBlock>? onAttachRange,
  ValueChanged<TerminalLinkTarget>? onOpenLinkTarget,
}) async {
  final origins = reference.origins
      .map((r) => (r.sessionId, r.sourceLineBase))
      .toSet();
  if (origins.length != 1 || origins.single.$1 != sourceSessionId) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    await showDialog<void>(
      context: context,
      animationStyle: appDialogAnimation(context),
      builder: (context) => AlertDialog(
        key: const Key('ai-evidence-ambiguous'),
        title: Text(chinese ? '无法唯一定位证据' : 'Evidence source is ambiguous'),
        content: Text(
          chinese
              ? '该引用对应多个输出快照或已不可用的来源。请从原命令块重新选择证据。'
              : 'This citation refers to multiple output snapshots or an unavailable source. Select evidence from the original command block.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(chinese ? '关闭' : 'Close'),
          ),
        ],
      ),
    );
    return null;
  }
  return showCommandBlockReader(
    context,
    controller: controller,
    id: blockId ?? reference.id,
    sourceLabel:
        sourceLabel ??
        (Localizations.localeOf(context).languageCode == 'zh'
            ? '保留的来源终端'
            : 'Retained source terminal'),
    sourceDetails: '$sourceSessionId · ${reference.id}',
    initialRange: CommandBlockReadRange(
      startLine: reference.startLine,
      endLine: reference.endLine,
      sourceLineBase: origins.single.$2,
    ),
    font: font,
    chinese: Localizations.localeOf(context).languageCode == 'zh',
    onAttachRange: onAttachRange,
    onOpenLinkTarget: onOpenLinkTarget,
  );
}

Future<String?> showRetainedAiEvidence(
  BuildContext context, {
  required TerminalAiController controller,
  required AiEvidenceReference reference,
  required TerminalFontConfig font,
  String? Function(String sessionId)? sourceLabelFor,
}) async {
  final connections = controller.terminal as TerminalAiConnections;
  connections.evidence.refresh();
  final sources = reference.origins.map((r) => r.sessionId).toSet();
  final source =
      sources.length == 1 &&
          connections.sourceSessionIds.contains(sources.single)
      ? sources.single
      : '';
  return showAiEvidenceReader(
    context,
    controller: connections.evidence,
    reference: reference,
    sourceSessionId: source,
    sourceLabel: sourceLabelFor?.call(source),
    blockId: TerminalAiConnections.evidenceId(source, reference.id),
    font: font,
    onAttachRange: (block) => controller.attachContext(
      connections.evidenceContext(block, useSnapshot: true),
    ),
  );
}
