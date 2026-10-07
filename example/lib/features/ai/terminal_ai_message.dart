import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:ianvs_design/ianvs_design.dart' show IanvsTypographyContext;

import '../../ui/app_ui.dart';

/// Prose has a comfortable reading measure; terminal blocks remain full width.
/// Role markers and the user's neutral surface distinguish turns without bubbles
/// or relying on color alone. Both roles share the same content alignment.
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
    final palette = context.appTheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final label = isUser ? (zh ? '你' : 'You') : 'AI';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Container(
            key: ValueKey('ai-message-frame-$entryId'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: isUser
                ? BoxDecoration(
                    color: palette.chrome,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: MediaQuery.textScalerOf(context).scale(28),
                  child: isUser
                      ? Text(
                          label,
                          key: ValueKey('ai-message-role-$entryId'),
                          style: Theme.of(context).textTheme.bodyMedium!
                              .copyWith(
                                color: palette.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                        )
                      : Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Icon(
                            Icons.auto_awesome_outlined,
                            key: ValueKey('ai-message-role-$entryId'),
                            size: 18,
                            color:
                                Theme.of(context)
                                    .textButtonTheme
                                    .style
                                    ?.foregroundColor
                                    ?.resolve({}) ??
                                palette.textPrimary,
                            semanticLabel: label,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Model prose shares the timeline's vertical scroll; code may scroll sideways.
/// Images are represented by their source text and never fetched by rendering.
class TerminalAiMessage extends StatelessWidget {
  const TerminalAiMessage({required this.text, this.onOpenLink, super.key});

  final String text;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appTheme;
    final body = theme.textTheme.bodyMedium!;
    return SelectionArea(
      child: MarkdownBody(
        data: text,
        softLineBreak: true,
        fitContent: false,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: body,
          h1: theme.textTheme.titleMedium,
          h2: theme.textTheme.titleSmall,
          h3: theme.textTheme.titleSmall,
          h4: body.copyWith(fontWeight: FontWeight.w600),
          h5: body.copyWith(fontWeight: FontWeight.w600),
          h6: body.copyWith(fontWeight: FontWeight.w600),
          strong: const TextStyle(fontWeight: FontWeight.w600),
          a: body.copyWith(
            color:
                theme.textButtonTheme.style?.foregroundColor?.resolve({}) ??
                palette.textPrimary,
            decoration: TextDecoration.underline,
          ),
          code: context.ianvsTypography.code.copyWith(
            fontSize: body.fontSize,
            backgroundColor: palette.chrome,
          ),
          blockSpacing: 8,
          listIndent: 24,
          listBullet: body,
          blockquote: body.copyWith(color: palette.textMuted),
          blockquotePadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: palette.borderStrong, width: 2),
            ),
          ),
          codeblockPadding: const EdgeInsets.all(12),
          codeblockDecoration: BoxDecoration(
            color: palette.chrome,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        onTapLink: onOpenLink == null
            ? null
            : (_, href, _) {
                if (href != null) onOpenLink!(href);
              },
        imageBuilder: (uri, title, alt) => Text(
          '${alt?.isNotEmpty == true ? '$alt · ' : ''}$uri',
          style: body.copyWith(color: palette.textMuted),
        ),
      ),
    );
  }
}
