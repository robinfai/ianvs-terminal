import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../ui/foundation/app_theme_tokens.dart';

/// The two explicit modes share fixed geometry and keyboard-accessible actions.
class AiWorkspaceModeSwitch extends StatelessWidget {
  const AiWorkspaceModeSwitch({
    required this.aiSelected,
    this.onTerminal,
    this.onAi,
    this.aiButtonKey,
    super.key,
  });
  final bool aiSelected;
  final VoidCallback? onTerminal;
  final VoidCallback? onAi;
  final Key? aiButtonKey;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final palette = context.appTheme;
    final compact = MediaQuery.sizeOf(context).width <= 640;
    Widget tab(bool ai, String label, IconData icon, VoidCallback? callback) {
      final selected = aiSelected == ai;
      return Semantics(
        selected: selected,
        label: compact ? label : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                // An invisible underline reserves identical geometry in both states.
                color: selected
                    ? palette.focus
                    : palette.focus.withValues(alpha: 0),
                width: 2,
              ),
            ),
          ),
          child: TextButton.icon(
            key: ai
                ? (aiButtonKey ?? const Key('ai-mode-ai'))
                : const Key('ai-mode-terminal'),
            onPressed: selected ? () {} : callback,
            style: TextButton.styleFrom(
              foregroundColor: selected ? palette.focus : palette.textMuted,
              minimumSize: Size(compact ? 32 : 64, 32),
              padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: Icon(icon, size: 16),
            label: compact ? const SizedBox.shrink() : Text(label, maxLines: 1),
          ),
        ),
      );
    }

    return Row(
      key: const Key('ai-workspace-mode'),
      mainAxisSize: MainAxisSize.min,
      children: [
        tab(
          false,
          zh ? '终端' : 'Terminal',
          LucideIcons300.squareTerminal,
          onTerminal,
        ),
        tab(true, 'AI', LucideIcons300.sparkles, onAi),
      ],
    );
  }
}

/// Presentation only. Native block identities, selection and scroll anchors
/// remain owned by the existing timeline.
class TerminalAiJournal extends StatelessWidget {
  const TerminalAiJournal({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appTheme;
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where(
            (value) =>
                value is! ComposerTheme && value is! IanvsMarkdownThemeData,
          ),
          ComposerTheme.of(context).copyWith(surface: palette.panel),
          // Prose emphasis is not a warning. Keep terminal ANSI and actual error
          // colors intact while aligning Markdown with the native reading surface.
          IanvsMarkdownThemeData.resolve(context).copyWith(
            textPrimary: palette.textPrimary,
            strongForeground: palette.textPrimary,
            emphasisForeground: palette.textPrimary,
          ),
        ],
      ),
      child: CommandTimelinePresentation(
        flatBlocks: true,
        padding: const EdgeInsets.only(top: 16, bottom: 20),
        decorateBlock: (context, item, block) => TerminalAiJournalRow(
          icon: LucideIcons300.squareTerminal,
          child: block,
        ),
        child: child,
      ),
    );
  }
}

/// A fixed marker gutter keeps prose, approvals and native output aligned.
/// The rule does not participate in hit testing or accessibility traversal.
class TerminalAiJournalRow extends StatelessWidget {
  const TerminalAiJournalRow({
    required this.child,
    this.icon,
    this.marker,
    this.connected = true,
    super.key,
  });
  final Widget child;
  final IconData? icon;
  final Widget? marker;
  final bool connected;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (connected)
        Positioned(
          left: 11.5,
          top: 32,
          bottom: 0,
          child: ExcludeSemantics(
            child: SizedBox(
              width: 1,
              child: ColoredBox(color: context.appTheme.border),
            ),
          ),
        ),
      Padding(padding: const EdgeInsets.only(left: 36), child: child),
      Positioned(
        left: 0,
        top: 10,
        child: SizedBox(
          width: 24,
          child: marker ?? Icon(icon, size: 18, color: context.appTheme.focus),
        ),
      ),
    ],
  );
}
