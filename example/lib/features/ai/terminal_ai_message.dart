import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:ianvs_design/ianvs_design.dart' show IanvsTypographyContext;

import '../../ui/app_ui.dart';

// Use the surface's constraints, not the window width: a narrow iPad pane must
// read like a phone without changing the layout of narrow desktop panes.
bool _usesMobileReadingLayout(BuildContext context, BoxConstraints bounds) {
  final platform = Theme.of(context).platform;
  return (platform == TargetPlatform.iOS ||
          platform == TargetPlatform.android) &&
      bounds.hasBoundedWidth &&
      bounds.maxWidth < 600;
}

/// Narrow mobile surfaces put the role above the content. A single horizontal
/// inset owns the reading measure; there is no permanent avatar column.
/// Desktop and wide tablet surfaces retain the existing bounded side-by-side
/// layout. User messages keep their neutral surface and both roles align.
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
    final role = isUser
        ? Text(
            label,
            key: ValueKey('ai-message-role-$entryId'),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
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
                  Theme.of(
                    context,
                  ).textButtonTheme.style?.foregroundColor?.resolve({}) ??
                  palette.textPrimary,
              semanticLabel: label,
            ),
          );
    final decoration = isUser
        ? BoxDecoration(
            color: palette.chrome,
            borderRadius: BorderRadius.circular(6),
          )
        : null;
    return LayoutBuilder(
      builder: (context, bounds) {
        if (_usesMobileReadingLayout(context, bounds)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              key: ValueKey('ai-message-frame-$entryId'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: decoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: role,
                  ),
                  const SizedBox(height: 8),
                  child,
                ],
              ),
            ),
          );
        }
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
                decoration: decoration,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: MediaQuery.textScalerOf(context).scale(28),
                      child: role,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Model prose shares the timeline's vertical scroll; code may scroll sideways.
/// Images are represented by their source text and never fetched by rendering.
/// Only mobile spacing changes; Markdown data, code bytes and selection remain
/// untouched. In particular, no soft-break characters are inserted into paths.
class TerminalAiMessage extends StatelessWidget {
  const TerminalAiMessage({required this.text, this.onOpenLink, super.key});

  final String text;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appTheme;
    final body = theme.textTheme.bodyMedium!;
    return LayoutBuilder(
      builder: (context, bounds) {
        final mobile = _usesMobileReadingLayout(context, bounds);
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
                // Transparent inline spans avoid fragmented dark bars while
                // fenced blocks keep their own themed container surface.
                backgroundColor: mobile
                    ? palette.chrome.withValues(alpha: 0)
                    : palette.chrome,
              ),
              blockSpacing: mobile ? 12 : 8,
              listIndent: mobile ? 18 : 24,
              listBullet: body,
              blockquote: body.copyWith(color: palette.textMuted),
              blockquotePadding: EdgeInsets.symmetric(
                horizontal: mobile ? 8 : 12,
                vertical: 8,
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: palette.borderStrong, width: 2),
                ),
              ),
              codeblockPadding: EdgeInsets.all(mobile ? 8 : 12),
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
      },
    );
  }
}
