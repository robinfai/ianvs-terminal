import 'package:flutter/material.dart';
import 'package:ianvs_agent_chat/ianvs_agent_chat.dart';
import 'package:ianvs_agent_core/ianvs_agent_core.dart';

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
