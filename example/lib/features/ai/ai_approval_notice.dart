import 'package:flutter/material.dart';

import 'ai_approval.dart';

class AiApprovalNotice extends StatelessWidget {
  const AiApprovalNotice({
    required this.review,
    this.confirmed = false,
    this.pending = true,
    super.key,
  });
  final AiApprovalReview review;
  final bool confirmed;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final reason = switch (review.source) {
      'manual' =>
        confirmed || !pending
            ? (zh ? '该命令采用「每次确认」审批。' : 'This command used manual approval.')
            : zh
            ? '当前为「每次确认」。可在 AI 连接设置中启用「智能审核」。'
            : 'Confirm every command is selected. Enable Smart review in AI connection settings for automatic low-risk review.',
      'interactive' =>
        zh ? '交互按键需要确认。' : 'Interactive input needs confirmation.',
      'sensitive' =>
        zh
            ? '敏感、破坏性、动态脚本或对外操作需要确认。'
            : 'Sensitive, destructive, dynamic or external operations need confirmation.',
      'context' =>
        zh
            ? '当前授权或终端信息不足。'
            : 'Authorization or terminal context is incomplete.',
      'unavailable' =>
        confirmed || !pending
            ? (zh ? '自动审核当时不可用。' : 'Automatic review was unavailable.')
            : zh
            ? '自动审核暂不可用，尚未发送命令。'
            : 'Automatic review is unavailable. No command was sent.',
      _ => review.reason,
    };
    final label = review.automatic
        ? (zh ? 'AI 审核通过' : 'AI review passed')
        : confirmed
        ? (zh ? '已由你确认' : 'Confirmed by you')
        : pending
        ? (zh ? '需要你确认' : 'Your confirmation is needed')
        : (zh ? '审核记录' : 'Review record');
    return Text(
      '$label · $reason',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
