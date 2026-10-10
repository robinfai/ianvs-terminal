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
    this.aiAction,
    this.tabs,
    this.tabStripKey,
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
  final Widget? aiAction;
  final Widget? tabs;
  final GlobalKey<_ShellTabStripState>? tabStripKey;

  @override
  State<_ShellWindowTitleBar> createState() => _ShellWindowTitleBarState();
}

class _ShellWindowTitleBarState extends State<_ShellWindowTitleBar> {
  final GlobalKey _boundsKey = GlobalKey();
  final GlobalKey _titleKey = GlobalKey();
  final GlobalKey _trailingGapKey = GlobalKey();
  bool _layoutScheduled = false;
  String? _lastLayout;
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
    // Until the new layout is measured, no Flutter control is a drag region.
    unawaited(
      WindowBridge.setTitleBarLayout(
        sidebarWidth: widget.sidebarOpen ? widget.sidebarWidth : null,
        height: widget.height,
        draggableRegions: const [],
      ),
    );
    _lastLayout = null;
  }

  void _scheduleNativeLayout() {
    if (_layoutScheduled) return;
    _layoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (!mounted || defaultTargetPlatform != TargetPlatform.macOS) return;
      Rect? rect(GlobalKey key) {
        final box = key.currentContext?.findRenderObject();
        return box is RenderBox && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : null;
      }

      final bounds = rect(_boundsKey);
      if (bounds == null) return;
      final regions = <Rect>[
        // Native traffic lights are excluded again by their actual NSRects.
        Rect.fromLTWH(bounds.left, bounds.top, 90, bounds.height),
        if (widget.tabs == null)
          if (rect(_titleKey) case final Rect title) title,
        if (rect(_trailingGapKey) case final Rect gap) gap,
        if (widget.tabStripKey?.currentState?.nativeDragGap case final Rect gap)
          gap,
        if (widget.sidebarOpen && bounds.width > widget.sidebarWidth)
          Rect.fromLTWH(
            bounds.left + widget.sidebarWidth,
            bounds.top,
            bounds.width - widget.sidebarWidth,
            bounds.height,
          ),
      ];
      final layout = '${widget.sidebarWidth}:${widget.height}:$regions';
      if (_lastLayout == layout) return;
      _lastLayout = layout;
      unawaited(
        WindowBridge.setTitleBarLayout(
          sidebarWidth: widget.sidebarOpen ? widget.sidebarWidth : null,
          height: widget.height,
          draggableRegions: regions,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleNativeLayout();
    final leadingInset = defaultTargetPlatform == TargetPlatform.macOS
        ? 90.0
        : widget.palette.spacing.xl;
    final buttonExtent = defaultTargetPlatform == TargetPlatform.iOS
        ? 44.0
        : 28.0;
    return SizedBox(
      key: _boundsKey,
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
                          child: widget.tabs != null
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: widget.tabs,
                                )
                              : Center(
                                  key: _titleKey,
                                  child: Text(
                                    context.l10n.appTitle,
                                    key: const Key('shell-chrome-window-title'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: widget.palette.textPrimary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                        ),
                        if (widget.tabs != null)
                          SizedBox(
                            key: _trailingGapKey,
                            width: 16,
                            height: double.infinity,
                          ),
                        if (widget.aiAction != null) widget.aiAction!,
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
