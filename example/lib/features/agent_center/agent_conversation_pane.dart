import 'package:flutter/material.dart';

import '../../ui/foundation/app_theme_tokens.dart';
import 'agent_command_proposal.dart';
import 'agent_context_chips.dart';
import 'agent_conversation_models.dart';

class AgentConversationPane extends StatelessWidget {
  const AgentConversationPane({
    super.key,
    this.conversation,
    this.contextChips = const <AgentContextChipModel>[],
    this.onCancelStreaming,
    this.onRetry,
    this.onInsertProposal,
    this.onReviewProposal,
    this.compact = false,
  });

  final AgentConversation? conversation;
  final List<AgentContextChipModel> contextChips;
  final VoidCallback? onCancelStreaming;
  final VoidCallback? onRetry;
  final ValueChanged<AgentCommandProposal>? onInsertProposal;
  final ValueChanged<AgentCommandProposal>? onReviewProposal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final status = conversation?.status ?? AgentConversationStatus.idle;
    final messages = conversation?.messages ?? const <AgentMessage>[];

    return Semantics(
      container: true,
      label: 'Agent conversation pane',
      child: DecoratedBox(
        key: const Key('agent-conversation-pane'),
        decoration: BoxDecoration(
          color: theme.panelElevated.withValues(alpha: compact ? 0.92 : 1),
          borderRadius: BorderRadius.circular(theme.radius.lg),
          border: Border.all(color: theme.border),
        ),
        child: Column(
          children: [
            _AgentConversationHeader(
              title: conversation?.title ?? 'Agent conversation',
              status: status,
              compact: compact,
              onCancelStreaming: onCancelStreaming,
              onRetry: onRetry,
            ),
            if (contextChips.isNotEmpty)
              _AgentContextChipRail(chips: contextChips, compact: compact),
            Divider(height: 1, color: theme.border),
            Expanded(
              child: messages.isEmpty
                  ? _AgentConversationEmptyState(
                      compact: compact,
                      status: status,
                    )
                  : _AgentMessageList(
                      messages: messages,
                      compact: compact,
                      onInsertProposal: onInsertProposal,
                      onReviewProposal: onReviewProposal,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentConversationHeader extends StatelessWidget {
  const _AgentConversationHeader({
    required this.title,
    required this.status,
    required this.compact,
    this.onCancelStreaming,
    this.onRetry,
  });

  final String title;
  final AgentConversationStatus status;
  final bool compact;
  final VoidCallback? onCancelStreaming;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final canCancel = status == AgentConversationStatus.streaming;
    final canRetry = status == AgentConversationStatus.failed;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.lg,
        vertical: compact ? theme.spacing.sm : theme.spacing.lg,
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: theme.accent),
          SizedBox(width: theme.spacing.sm),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: theme.spacing.sm),
          _AgentStatusPill(status: status),
          if (canCancel) ...[
            SizedBox(width: theme.spacing.xs),
            IconButton(
              key: const Key('agent-conversation-cancel'),
              tooltip: 'Cancel Agent response',
              onPressed: onCancelStreaming,
              icon: const Icon(
                Icons.stop_circle_rounded,
                semanticLabel: 'Cancel Agent response',
              ),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
            ),
          ],
          if (canRetry) ...[
            SizedBox(width: theme.spacing.xs),
            IconButton(
              key: const Key('agent-conversation-retry'),
              tooltip: 'Retry Agent response',
              onPressed: onRetry,
              icon: const Icon(
                Icons.refresh_rounded,
                semanticLabel: 'Retry Agent response',
              ),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentStatusPill extends StatelessWidget {
  const _AgentStatusPill({required this.status});

  final AgentConversationStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final tone = _statusTone(theme, status);
    return DecoratedBox(
      key: const Key('agent-conversation-status'),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(theme.radius.sm),
        border: Border.all(color: tone.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.sm,
          vertical: theme.spacing.xs,
        ),
        child: Text(
          _statusLabel(status),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: tone.foreground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AgentContextChipRail extends StatelessWidget {
  const _AgentContextChipRail({required this.chips, required this.compact});

  final List<AgentContextChipModel> chips;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return SizedBox(
      height: compact ? 30 : 36,
      child: ListView.separated(
        key: const Key('agent-conversation-context-rail'),
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: theme.spacing.lg),
        itemCount: chips.length,
        separatorBuilder: (context, index) => SizedBox(width: theme.spacing.xs),
        itemBuilder: (context, index) {
          return _AgentContextChipView(chip: chips[index]);
        },
      ),
    );
  }
}

class _AgentContextChipView extends StatelessWidget {
  const _AgentContextChipView({required this.chip});

  final AgentContextChipModel chip;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final tone = _contextTone(theme, chip.tone);
    return Semantics(
      label: chip.semanticLabel,
      child: Tooltip(
        message: chip.preview,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tone.background,
            borderRadius: BorderRadius.circular(theme.radius.sm),
            border: Border.all(color: tone.border),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing.sm,
              vertical: theme.spacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (chip.pinned) ...[
                  Icon(
                    Icons.push_pin_rounded,
                    size: 12,
                    color: tone.foreground,
                  ),
                  SizedBox(width: theme.spacing.xs),
                ],
                Text(
                  chip.label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tone.foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentConversationEmptyState extends StatelessWidget {
  const _AgentConversationEmptyState({
    required this.compact,
    required this.status,
  });

  final bool compact;
  final AgentConversationStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final streaming = status == AgentConversationStatus.streaming;
    final title = streaming
        ? 'Waiting for Agent response'
        : 'No Agent messages yet';
    final detail = streaming
        ? 'The Agent is preparing a response. You can cancel if it takes too long.'
        : 'Context is ready for the next question.';
    if (compact) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: theme.spacing.lg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                streaming ? Icons.pending_rounded : Icons.forum_rounded,
                size: 18,
                color: streaming ? theme.accent : theme.textMuted,
              ),
              SizedBox(width: theme.spacing.sm),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              streaming ? Icons.pending_rounded : Icons.forum_rounded,
              size: compact ? 20 : 26,
              color: streaming ? theme.accent : theme.textMuted,
            ),
            SizedBox(height: theme.spacing.sm),
            Text(
              title,
              key: const Key('agent-conversation-empty-title'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: theme.spacing.xs),
            Text(
              detail,
              key: const Key('agent-conversation-empty-detail'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: theme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentMessageList extends StatelessWidget {
  const _AgentMessageList({
    required this.messages,
    required this.compact,
    this.onInsertProposal,
    this.onReviewProposal,
  });

  final List<AgentMessage> messages;
  final bool compact;
  final ValueChanged<AgentCommandProposal>? onInsertProposal;
  final ValueChanged<AgentCommandProposal>? onReviewProposal;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return ListView.separated(
      key: const Key('agent-conversation-message-list'),
      padding: EdgeInsets.all(compact ? theme.spacing.md : theme.spacing.lg),
      itemCount: messages.length,
      separatorBuilder: (context, index) => SizedBox(height: theme.spacing.sm),
      itemBuilder: (context, index) {
        return _AgentMessageBubble(
          message: messages[index],
          compact: compact,
          onInsertProposal: onInsertProposal,
          onReviewProposal: onReviewProposal,
        );
      },
    );
  }
}

class _AgentMessageBubble extends StatelessWidget {
  const _AgentMessageBubble({
    required this.message,
    required this.compact,
    this.onInsertProposal,
    this.onReviewProposal,
  });

  final AgentMessage message;
  final bool compact;
  final ValueChanged<AgentCommandProposal>? onInsertProposal;
  final ValueChanged<AgentCommandProposal>? onReviewProposal;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isUser = message.role == AgentMessageRole.user;
    final tone = _messageTone(theme, message);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: isUser ? 0.78 : 0.88,
        child: DecoratedBox(
          key: Key('agent-message-${message.id}'),
          decoration: BoxDecoration(
            color: tone.background,
            borderRadius: BorderRadius.circular(theme.radius.lg),
            border: Border.all(color: tone.border),
          ),
          child: Padding(
            padding: EdgeInsets.all(
              compact ? theme.spacing.md : theme.spacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _roleIcon(message.role),
                      size: 15,
                      color: tone.foreground,
                    ),
                    SizedBox(width: theme.spacing.xs),
                    Expanded(
                      child: Text(
                        _roleLabel(message.role),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tone.foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (message.status != AgentMessageStatus.completed)
                      _MessageStatusLabel(status: message.status, tone: tone),
                  ],
                ),
                SizedBox(height: theme.spacing.sm),
                for (var index = 0; index < message.parts.length; index++) ...[
                  if (index > 0) SizedBox(height: theme.spacing.sm),
                  _AgentMessagePartView(
                    part: message.parts[index],
                    compact: compact,
                    onInsertProposal: onInsertProposal,
                    onReviewProposal: onReviewProposal,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageStatusLabel extends StatelessWidget {
  const _MessageStatusLabel({required this.status, required this.tone});

  final AgentMessageStatus status;
  final _AgentTone tone;

  @override
  Widget build(BuildContext context) {
    return Text(
      _messageStatusLabel(status),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: tone.foreground,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _AgentMessagePartView extends StatelessWidget {
  const _AgentMessagePartView({
    required this.part,
    required this.compact,
    this.onInsertProposal,
    this.onReviewProposal,
  });

  final AgentMessagePart part;
  final bool compact;
  final ValueChanged<AgentCommandProposal>? onInsertProposal;
  final ValueChanged<AgentCommandProposal>? onReviewProposal;

  @override
  Widget build(BuildContext context) {
    return switch (part.kind) {
      AgentMessagePartKind.codeBlock ||
      AgentMessagePartKind.terminalOutputExcerpt ||
      AgentMessagePartKind.diagnostic ||
      AgentMessagePartKind.toolCall ||
      AgentMessagePartKind.toolResult => _AgentCodePart(part: part),
      AgentMessagePartKind.commandProposal => _AgentCommandProposalCard(
        proposal: part.commandProposal,
        compact: compact,
        onInsertProposal: onInsertProposal,
        onReviewProposal: onReviewProposal,
      ),
      AgentMessagePartKind.text ||
      AgentMessagePartKind.markdown => _AgentTextPart(text: part.text),
    };
  }
}

class _AgentTextPart extends StatelessWidget {
  const _AgentTextPart({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return SelectableText(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: theme.textPrimary, height: 1.32),
    );
  }
}

class _AgentCodePart extends StatelessWidget {
  const _AgentCodePart({required this.part});

  final AgentMessagePart part;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.terminalSurface,
        borderRadius: BorderRadius.circular(theme.radius.md),
        border: Border.all(color: theme.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (part.language != null) ...[
              Text(
                part.language!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: theme.textSubtle,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: theme.spacing.xs),
            ],
            SelectableText(
              part.text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: theme.textMuted,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCommandProposalCard extends StatelessWidget {
  const _AgentCommandProposalCard({
    required this.proposal,
    required this.compact,
    this.onInsertProposal,
    this.onReviewProposal,
  });

  final AgentCommandProposal? proposal;
  final bool compact;
  final ValueChanged<AgentCommandProposal>? onInsertProposal;
  final ValueChanged<AgentCommandProposal>? onReviewProposal;

  @override
  Widget build(BuildContext context) {
    final proposal = this.proposal;
    if (proposal == null) {
      return const SizedBox.shrink();
    }

    final theme = context.appTheme;
    final tone = _riskTone(theme, proposal.riskLevel);
    return DecoratedBox(
      key: Key('agent-command-proposal-${proposal.id}'),
      decoration: BoxDecoration(
        color: theme.overlay,
        borderRadius: BorderRadius.circular(theme.radius.md),
        border: Border.all(color: tone.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? theme.spacing.md : theme.spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal_rounded, size: 15, color: tone.foreground),
                SizedBox(width: theme.spacing.xs),
                Expanded(
                  child: Text(
                    'Proposed command',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _RiskPill(riskLevel: proposal.riskLevel),
              ],
            ),
            SizedBox(height: theme.spacing.sm),
            _CommandText(command: proposal.command),
            if (proposal.cwd != null) ...[
              SizedBox(height: theme.spacing.xs),
              Text(
                proposal.cwd!,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: theme.textSubtle,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            SizedBox(height: theme.spacing.sm),
            Text(
              proposal.explanation,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: theme.textMuted,
                height: 1.32,
              ),
            ),
            if (proposal.warnings.isNotEmpty) ...[
              SizedBox(height: theme.spacing.sm),
              for (final warning in proposal.warnings)
                _ProposalDetailLine(
                  icon: Icons.warning_amber_rounded,
                  text: warning,
                  color: theme.warning,
                ),
            ],
            if (proposal.detectedEffects.isNotEmpty) ...[
              SizedBox(height: theme.spacing.sm),
              for (final effect in proposal.detectedEffects)
                _ProposalDetailLine(
                  icon: Icons.info_outline_rounded,
                  text: effect,
                  color: theme.textMuted,
                ),
            ],
            SizedBox(height: theme.spacing.md),
            Wrap(
              spacing: theme.spacing.sm,
              runSpacing: theme.spacing.xs,
              children: [
                OutlinedButton.icon(
                  key: const Key('agent-command-proposal-review'),
                  onPressed: onReviewProposal == null
                      ? null
                      : () => onReviewProposal?.call(proposal),
                  icon: const Icon(Icons.fact_check_rounded),
                  label: const Text('Review'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('agent-command-proposal-insert'),
                  onPressed: onInsertProposal == null
                      ? null
                      : () => onInsertProposal?.call(proposal),
                  icon: const Icon(Icons.input_rounded),
                  label: const Text('Insert'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandText extends StatelessWidget {
  const _CommandText({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.terminalSurface,
        borderRadius: BorderRadius.circular(theme.radius.sm),
        border: Border.all(color: theme.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.md,
          vertical: theme.spacing.sm,
        ),
        child: SelectableText(
          command,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: theme.textPrimary,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ProposalDetailLine extends StatelessWidget {
  const _ProposalDetailLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Padding(
      padding: EdgeInsets.only(top: theme.spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: theme.spacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: theme.textMuted,
                height: 1.28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskPill extends StatelessWidget {
  const _RiskPill({required this.riskLevel});

  final AgentCommandRiskLevel riskLevel;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final tone = _riskTone(theme, riskLevel);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(theme.radius.sm),
        border: Border.all(color: tone.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.sm,
          vertical: theme.spacing.xs,
        ),
        child: Text(
          _riskLabel(riskLevel),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: tone.foreground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String _statusLabel(AgentConversationStatus status) {
  return switch (status) {
    AgentConversationStatus.idle => 'Ready',
    AgentConversationStatus.streaming => 'Streaming',
    AgentConversationStatus.waitingForUser => 'Waiting',
    AgentConversationStatus.toolRunning => 'Tool running',
    AgentConversationStatus.completed => 'Complete',
    AgentConversationStatus.cancelled => 'Cancelled',
    AgentConversationStatus.failed => 'Failed',
  };
}

String _messageStatusLabel(AgentMessageStatus status) {
  return switch (status) {
    AgentMessageStatus.pending => 'Pending',
    AgentMessageStatus.streaming => 'Streaming',
    AgentMessageStatus.completed => 'Complete',
    AgentMessageStatus.cancelled => 'Cancelled',
    AgentMessageStatus.failed => 'Failed',
  };
}

String _roleLabel(AgentMessageRole role) {
  return switch (role) {
    AgentMessageRole.user => 'You',
    AgentMessageRole.assistant => 'Agent',
    AgentMessageRole.system => 'System',
    AgentMessageRole.tool => 'Tool',
  };
}

IconData _roleIcon(AgentMessageRole role) {
  return switch (role) {
    AgentMessageRole.user => Icons.person_rounded,
    AgentMessageRole.assistant => Icons.auto_awesome_rounded,
    AgentMessageRole.system => Icons.tune_rounded,
    AgentMessageRole.tool => Icons.build_circle_rounded,
  };
}

String _riskLabel(AgentCommandRiskLevel riskLevel) {
  return switch (riskLevel) {
    AgentCommandRiskLevel.low => 'Low risk',
    AgentCommandRiskLevel.medium => 'Medium risk',
    AgentCommandRiskLevel.high => 'High risk',
    AgentCommandRiskLevel.destructive => 'Destructive',
    AgentCommandRiskLevel.unknown => 'Unknown risk',
  };
}

_AgentTone _statusTone(AppThemeTokens theme, AgentConversationStatus status) {
  return switch (status) {
    AgentConversationStatus.failed => _AgentTone(
      foreground: theme.danger,
      background: theme.dangerContainer,
      border: theme.danger.withValues(alpha: 0.44),
    ),
    AgentConversationStatus.cancelled ||
    AgentConversationStatus.idle => _AgentTone(
      foreground: theme.textMuted,
      background: theme.chrome,
      border: theme.border,
    ),
    AgentConversationStatus.streaming ||
    AgentConversationStatus.toolRunning => _AgentTone(
      foreground: theme.accent,
      background: theme.selected,
      border: theme.accent.withValues(alpha: 0.38),
    ),
    AgentConversationStatus.waitingForUser => _AgentTone(
      foreground: theme.warning,
      background: theme.warningContainer,
      border: theme.warning.withValues(alpha: 0.42),
    ),
    AgentConversationStatus.completed => _AgentTone(
      foreground: theme.success,
      background: theme.successContainer,
      border: theme.success.withValues(alpha: 0.38),
    ),
  };
}

_AgentTone _contextTone(AppThemeTokens theme, AgentContextChipTone tone) {
  return switch (tone) {
    AgentContextChipTone.warning => _AgentTone(
      foreground: theme.warning,
      background: theme.warningContainer,
      border: theme.warning.withValues(alpha: 0.42),
    ),
    AgentContextChipTone.danger => _AgentTone(
      foreground: theme.danger,
      background: theme.dangerContainer,
      border: theme.danger.withValues(alpha: 0.42),
    ),
    AgentContextChipTone.disabled => _AgentTone(
      foreground: theme.textSubtle,
      background: theme.chrome,
      border: theme.border,
    ),
    AgentContextChipTone.normal => _AgentTone(
      foreground: theme.textMuted,
      background: theme.chromeElevated,
      border: theme.border,
    ),
  };
}

_AgentTone _messageTone(AppThemeTokens theme, AgentMessage message) {
  if (message.status == AgentMessageStatus.failed) {
    return _AgentTone(
      foreground: theme.danger,
      background: theme.dangerContainer.withValues(alpha: 0.66),
      border: theme.danger.withValues(alpha: 0.40),
    );
  }
  return switch (message.role) {
    AgentMessageRole.user => _AgentTone(
      foreground: theme.accent,
      background: theme.selected.withValues(alpha: 0.70),
      border: theme.accent.withValues(alpha: 0.34),
    ),
    AgentMessageRole.assistant => _AgentTone(
      foreground: theme.textMuted,
      background: theme.panel,
      border: theme.border,
    ),
    AgentMessageRole.system || AgentMessageRole.tool => _AgentTone(
      foreground: theme.warning,
      background: theme.warningContainer.withValues(alpha: 0.50),
      border: theme.warning.withValues(alpha: 0.34),
    ),
  };
}

_AgentTone _riskTone(AppThemeTokens theme, AgentCommandRiskLevel riskLevel) {
  return switch (riskLevel) {
    AgentCommandRiskLevel.low => _AgentTone(
      foreground: theme.success,
      background: theme.successContainer,
      border: theme.success.withValues(alpha: 0.40),
    ),
    AgentCommandRiskLevel.medium => _AgentTone(
      foreground: theme.warning,
      background: theme.warningContainer,
      border: theme.warning.withValues(alpha: 0.42),
    ),
    AgentCommandRiskLevel.high ||
    AgentCommandRiskLevel.destructive => _AgentTone(
      foreground: theme.danger,
      background: theme.dangerContainer,
      border: theme.danger.withValues(alpha: 0.44),
    ),
    AgentCommandRiskLevel.unknown => _AgentTone(
      foreground: theme.textMuted,
      background: theme.chrome,
      border: theme.border,
    ),
  };
}

class _AgentTone {
  const _AgentTone({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}
