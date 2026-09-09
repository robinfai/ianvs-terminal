part of 'shell_screen.dart';

class _TerminalAnnotationBadge extends StatelessWidget {
  const _TerminalAnnotationBadge({
    super.key,
    required this.count,
    required this.palette,
    required this.onTap,
  });

  final int count;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(palette.radius.md),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.overlay.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(color: palette.borderStrong),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sticky_note_2_rounded,
                  size: 16,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  '$count annotation${count == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
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

class _ShellLayoutCue extends StatelessWidget {
  const _ShellLayoutCue({required this.title, required this.palette});

  final String title;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-layout-focus-cue'),
      decoration: BoxDecoration(
        color: palette.overlay.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(palette.radius.lg),
        border: Border.all(color: palette.focusRing.withValues(alpha: 0.62)),
        boxShadow: palette.elevation.floating,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_command_key_rounded,
              color: palette.accent,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
