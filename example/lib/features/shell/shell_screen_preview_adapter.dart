part of 'shell_screen.dart';

/// Development-only access to the production tab presentation. The caller owns
/// fixture state; this adapter creates no ShellScreen, provider, PTY or window.
class ShellTabComponentPreview extends StatelessWidget {
  const ShellTabComponentPreview({
    required this.tab,
    required this.selected,
    required this.focusNode,
    required this.onActivate,
    required this.onClose,
    super.key,
  });

  final TerminalTab tab;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onActivate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return _ShellTabButton(
      palette: palette,
      tab: tab,
      shortcutIndex: 1,
      isActive: selected,
      hasNewOutput: false,
      newOutputTooltip: '',
      newOutputPaneSessionId: null,
      tabColor: null,
      compact: false,
      chromeBackgroundColor: palette.panel,
      focusNode: focusNode,
      dragRegionBuilder: (child) => child,
      onActivate: onActivate,
      onActivateBadgePane: (_) {},
      onNotificationInteraction: (_) {},
      onActivateNewOutputPane: (_) {},
      onClose: onClose,
      onShowContextMenu: (_) {},
    );
  }
}

/// The real pointer resize handle, with only a local fixture resize callback.
/// Focus and key handling remain owned by the production handle; no preview
/// decoration or selected/disabled/pressed presentation is added here.
class ShellDividerComponentPreview extends StatelessWidget {
  const ShellDividerComponentPreview({
    required this.direction,
    required this.onDragUpdate,
    this.focusNode,
    this.ratio,
    this.increasedRatio,
    this.decreasedRatio,
    super.key,
  });

  final Axis direction;
  final ValueChanged<double> onDragUpdate;
  final FocusNode? focusNode;
  final double? ratio;
  final double? increasedRatio;
  final double? decreasedRatio;

  @override
  Widget build(BuildContext context) => _PaneDividerHandle(
    direction: direction,
    thickness: 10,
    terminalBackground: context.appTheme.panel,
    palette: context.appTheme,
    onDragUpdate: onDragUpdate,
    focusNode: focusNode,
    ratio: ratio,
    increasedRatio: increasedRatio,
    decreasedRatio: decreasedRatio,
  );
}
