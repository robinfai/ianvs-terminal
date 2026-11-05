import 'package:flutter/material.dart';
import 'package:ianvs_agent_chat/ianvs_agent_chat.dart';
import 'package:ianvs_agent_core/ianvs_agent_core.dart';

import '../../ui/components/app_grouped_section.dart';
import 'terminal_ai_journal.dart';

/// Host identity and localized role, with the shared conversation surface.
class TerminalAiMessageFrame extends StatelessWidget {
  const TerminalAiMessageFrame({
    required this.entryId,
    required this.isUser,
    required this.child,
    super.key,
  });
  final String entryId;
  final bool isUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final theme = ChatTheme.of(context);
    final platform = Theme.of(context).platform;
    final mobile =
        platform == TargetPlatform.iOS || platform == TargetPlatform.android;
    if (platform == TargetPlatform.macOS) {
      final marker = isUser
          ? Text(
              zh ? '你' : 'You',
              key: ValueKey('ai-message-role-$entryId'),
              style: TextStyle(color: theme.textPrimary),
            )
          : Icon(
              Icons.auto_awesome_outlined,
              key: ValueKey('ai-message-role-$entryId'),
              size: 18,
              color: theme.textPrimary,
              semanticLabel: 'AI',
            );
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: theme.contentMaxWidth),
          child: TerminalAiJournalRow(
            key: ValueKey('ai-message-frame-$entryId'),
            marker: marker,
            connected: !isUser,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 18),
              child: SizedBox(
                width: double.infinity,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (context.usesAppleGroups) {
      return Padding(
        key: ValueKey('ai-message-frame-$entryId'),
        padding: EdgeInsets.fromLTRB(isUser ? 30 : 6, 8, 6, 8),
        child: Semantics(
          label: isUser ? (zh ? '你' : 'You') : 'AI',
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isUser
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
                  : context.groupedSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: mobile ? 4 : 0, vertical: 8),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: theme.contentMaxWidth),
          child: ChatMessageFrame(
            key: ValueKey('ai-message-frame-$entryId'),
            role: isUser ? ChatMessageRole.user : ChatMessageRole.assistant,
            showRole: false,
            leading: isUser
                ? Text(
                    zh ? '你' : 'You',
                    style: TextStyle(color: theme.textPrimary),
                    key: ValueKey('ai-message-role-$entryId'),
                  )
                : Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    semanticLabel: 'AI',
                    color: theme.textPrimary,
                    key: ValueKey('ai-message-role-$entryId'),
                  ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Prose shares rendering and selection; the host owns links and outer scrolling.
class TerminalAiMessage extends StatelessWidget {
  const TerminalAiMessage({required this.text, this.onOpenLink, super.key});
  final String text;
  final ValueChanged<String>? onOpenLink;
  @override
  Widget build(BuildContext context) => ChatMessageBody(
    text: text,
    documentSelection: true,
    softLineBreak: true,
    onTapLink: onOpenLink == null
        ? null
        : (_, href, _) {
            if (href != null) onOpenLink!(href);
          },
  );
}

/// Literal source; the original payload is never changed by display normalization.
class TerminalCodePreview extends StatelessWidget {
  const TerminalCodePreview({required this.text, super.key});
  final String text;
  @override
  Widget build(BuildContext context) => ChatCodePreview(source: text);
}
