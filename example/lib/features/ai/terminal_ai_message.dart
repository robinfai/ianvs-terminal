import 'package:flutter/material.dart';
import 'package:ianvs_agent_chat/ianvs_agent_chat.dart' show ChatMessageBody;
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
/// Shared content rendering never fetches images by default. The terminal owns
/// its frame, links and outer scroll; Markdown parsing and selection are shared.
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

/// Host command/evidence previews are literal bytes, not model prose. Preserve
/// line boundaries and horizontal scrolling without routing through Markdown.
class TerminalCodePreview extends StatelessWidget {
  const TerminalCodePreview({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.chrome,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectionArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            text,
            softWrap: false,
            style: context.ianvsTypography.code.copyWith(
              color: palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
