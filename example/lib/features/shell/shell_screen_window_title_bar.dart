part of 'shell_screen.dart';

class _ShellWindowTitleBar extends StatefulWidget {
  const _ShellWindowTitleBar({
    required this.height,
    required this.sidebarOpen,
    required this.sidebarWidth,
    required this.onToggleSidebar,
    required this.palette,
    required this.tone,
    required this.backgroundColor,
    required this.terminalBackgroundColor,
    required this.onShowCommandMenu,
  });

  final bool sidebarOpen;
  final double sidebarWidth;
  final VoidCallback? onToggleSidebar;
  final double height;
  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final Color backgroundColor;
  final Color terminalBackgroundColor;
  final VoidCallback? onShowCommandMenu;

  @override
  State<_ShellWindowTitleBar> createState() => _ShellWindowTitleBarState();
}

class _ShellWindowTitleBarState extends State<_ShellWindowTitleBar> {
  @override
  void initState() {
    super.initState();
    _syncNativeControls();
  }

  @override
  void didUpdateWidget(_ShellWindowTitleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sidebarOpen != widget.sidebarOpen ||
        oldWidget.sidebarWidth != widget.sidebarWidth) {
      _syncNativeControls();
    }
  }

  void _syncNativeControls() {
    unawaited(
      WindowBridge.setTitleBarLayout(
        sidebarWidth: widget.sidebarOpen ? widget.sidebarWidth : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leadingInset = defaultTargetPlatform == TargetPlatform.macOS
        ? 90.0
        : widget.palette.spacing.xl;
    final buttonExtent = defaultTargetPlatform == TargetPlatform.iOS
        ? 44.0
        : 28.0;
    return SizedBox(
      height: widget.height,
      child: ColoredBox(
        color: widget.sidebarOpen
            ? widget.terminalBackgroundColor
            : widget.backgroundColor,
        child: Stack(
          children: [
            const Positioned.fill(
              child: _WindowDragHandle(
                key: Key('shell-window-drag-leading'),
                child: SizedBox.expand(),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: widget.sidebarOpen
                    ? widget.sidebarWidth
                    : double.infinity,
                height: widget.height,
                child: ColoredBox(
                  key: const Key('shell-chrome-title-surface'),
                  color: widget.sidebarOpen
                      ? Theme.of(context).colorScheme.surfaceContainerLow
                      : widget.backgroundColor,
                  child: Padding(
                    padding: EdgeInsets.only(left: leadingInset, right: 12),
                    child: Row(
                      children: [
                        if (widget.onToggleSidebar != null)
                          SizedBox.square(
                            dimension: buttonExtent,
                            child: _buildChromeIconButton(
                              key: const Key('shell-toggle-sidebar'),
                              tooltip: widget.sidebarOpen
                                  ? context.l10n.switchToTopTabs
                                  : context.l10n.switchToSidebarTabs,
                              onPressed: widget.onToggleSidebar,
                              iconSize: 18,
                              hoverBackgroundColor: widget.tone.hoverBackground,
                              icon: AppTabLayoutIcon(
                                layout: widget.sidebarOpen
                                    ? AppTabLayout.top
                                    : AppTabLayout.sidebar,
                                color: widget.tone.mutedText,
                              ),
                            ),
                          )
                        else
                          SizedBox(width: buttonExtent),
                        Expanded(
                          child: Center(
                            child: Text(
                              context.l10n.appTitle,
                              key: const Key('shell-chrome-window-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: widget.palette.textPrimary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                        if (widget.onShowCommandMenu != null)
                          SizedBox.square(
                            dimension: buttonExtent,
                            child: TextFieldTapRegion(
                              child: _buildChromeIconButton(
                                key: const Key('shell-chrome-menu'),
                                tooltip: context.l10n.openCommandPalette,
                                onPressed: widget.onShowCommandMenu,
                                iconSize: 18,
                                hoverBackgroundColor:
                                    widget.tone.hoverBackground,
                                icon: Icon(
                                  Icons.settings_outlined,
                                  color: widget.tone.mutedText,
                                ),
                              ),
                            ),
                          )
                        else
                          SizedBox(width: buttonExtent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowDragHandle extends StatelessWidget {
  const _WindowDragHandle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
