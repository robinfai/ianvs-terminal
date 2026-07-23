part of 'shell_screen.dart';

Widget _buildSheetCloseButton({
  required String tooltip,
  required VoidCallback onPressed,
  Key? buttonKey,
}) {
  return AppActionButton(
    buttonKey: buttonKey,
    tooltip: tooltip,
    tone: AppActionTone.ghost,
    size: AppActionSize.dense,
    onPressed: onPressed,
    icon: Icons.close_rounded,
  );
}

Widget _buildCompactActionButton({
  required Key key,
  required String tooltip,
  required Widget icon,
  required VoidCallback? onPressed,
  double? splashRadius,
  double? iconSize,
  bool isSelected = false,
  Widget? selectedIcon,
  EdgeInsetsGeometry? padding,
  BoxConstraints? constraints,
}) {
  return Semantics(
    label: tooltip,
    button: true,
    enabled: onPressed != null,
    excludeSemantics: true,
    onTap: onPressed,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      isSelected: isSelected,
      onPressed: onPressed,
      visualDensity: constraints == null
          ? VisualDensity.compact
          : VisualDensity.standard,
      splashRadius: splashRadius,
      iconSize: iconSize,
      padding: padding,
      constraints: constraints,
      selectedIcon: selectedIcon == null
          ? null
          : Semantics(
              label: tooltip,
              child: ExcludeSemantics(child: selectedIcon),
            ),
      icon: Semantics(
        label: tooltip,
        child: ExcludeSemantics(child: icon),
      ),
    ),
  );
}

Widget _buildEntryActionButton({
  required Key key,
  required String tooltip,
  required IconData icon,
  required VoidCallback? onPressed,
}) {
  return Builder(
    builder: (context) {
      return Semantics(
        label: tooltip,
        button: true,
        enabled: onPressed != null,
        excludeSemantics: true,
        onTap: onPressed,
        child: IconButton(
          key: key,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: ExcludeSemantics(
            child: Icon(icon, color: context.appTheme.textMuted),
          ),
        ),
      );
    },
  );
}

Widget _buildChromeIconButton({
  required Key key,
  required String tooltip,
  required Widget icon,
  required VoidCallback? onPressed,
  required double iconSize,
  Color? hoverBackgroundColor,
}) {
  return Semantics(
    label: tooltip,
    button: true,
    enabled: onPressed != null,
    excludeSemantics: true,
    onTap: onPressed,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      splashRadius: 14,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (hoverBackgroundColor == null) {
            return Colors.transparent;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return hoverBackgroundColor;
          }
          return Colors.transparent;
        }),
      ),
      iconSize: iconSize,
      icon: ExcludeSemantics(child: icon),
    ),
  );
}

class _ReplaySourceMark extends StatelessWidget {
  const _ReplaySourceMark({required this.palette, required this.sourceLabel});

  final AppThemeTokens palette;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Replay source: $sourceLabel',
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(palette.radius.md),
              border: Border.all(color: palette.accent.withValues(alpha: 0.34)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Icon(
                Icons.replay_rounded,
                size: 17,
                color: palette.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Replay',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.overlay,
              borderRadius: BorderRadius.circular(palette.radius.sm),
              border: Border.all(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(
                sourceLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.textSubtle,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
