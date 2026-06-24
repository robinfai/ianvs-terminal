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
