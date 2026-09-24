part of 'shell_screen.dart';

class _ShellWindowTitleBar extends StatelessWidget {
  const _ShellWindowTitleBar({
    required this.height,
    this.sidebarOpen = false,
    this.onToggleSidebar,
    required this.palette,
    required this.tone,
    required this.backgroundColor,
    required this.onShowCommandMenu,
    this.onOpenReplay,
    this.onOpenSettings,
    this.onSearch,
  });

  final bool sidebarOpen;
  final VoidCallback? onToggleSidebar;
  final double height;
  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final Color backgroundColor;
  final VoidCallback? onShowCommandMenu;
  final VoidCallback? onOpenReplay;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final titleLeadingInset = defaultTargetPlatform == TargetPlatform.macOS
        ? 90.0
        : palette.spacing.xl;
    final trailingInset = onShowCommandMenu == null
        ? 16.0
        : isIos
        ? 64.0
        : onOpenReplay == null
        ? 120.0
        : 156.0;
    final titleSafeInset = math.max(titleLeadingInset, trailingInset);

    return SizedBox(
      height: height,
      child: DecoratedBox(
        key: const Key('shell-chrome-title-surface'),
        decoration: BoxDecoration(color: backgroundColor),
        child: Stack(
          children: [
            const Positioned.fill(
              child: _WindowDragHandle(
                key: Key('shell-window-drag-leading'),
                child: SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: titleSafeInset),
                  child: Center(
                    child: Text(
                      context.l10n.appTitle,
                      key: const Key('shell-chrome-window-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tone.mutedText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onToggleSidebar != null)
              Positioned(
                left: titleLeadingInset,
                top: 8,
                bottom: 8,
                child: _buildChromeIconButton(
                  key: const Key('shell-toggle-sidebar'),
                  tooltip: sidebarOpen
                      ? context.l10n.hideSessionSidebar
                      : context.l10n.showSessionSidebar,
                  onPressed: onToggleSidebar,
                  iconSize: 18,
                  hoverBackgroundColor: tone.hoverBackground,
                  icon: Icon(
                    Icons.view_sidebar_outlined,
                    color: tone.mutedText,
                  ),
                ),
              ),
            if (onShowCommandMenu != null)
              Positioned(
                top: isIos ? 0 : 8,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onOpenReplay != null)
                      TextFieldTapRegion(
                        child: _buildChromeIconButton(
                          key: const Key('shell-toolbar-replay'),
                          iconSize: 16,
                          tooltip: context.l10n.replayHubTitle,
                          onPressed: onOpenReplay,
                          hoverBackgroundColor: tone.hoverBackground,
                          icon: Icon(
                            Icons.history_rounded,
                            color: tone.mutedText,
                          ),
                        ),
                      ),
                    if (onSearch != null)
                      _buildChromeIconButton(
                        key: const Key('shell-toolbar-search'),
                        iconSize: 16,
                        tooltip: context.l10n.search,
                        onPressed: onSearch,
                        hoverBackgroundColor: tone.hoverBackground,
                        icon: Icon(Icons.search_rounded, color: tone.mutedText),
                      ),
                    if (onOpenSettings != null)
                      _buildChromeIconButton(
                        key: const Key('shell-toolbar-settings'),
                        iconSize: 16,
                        tooltip: context.l10n.defaultsAppearance,
                        onPressed: onOpenSettings,
                        hoverBackgroundColor: tone.hoverBackground,
                        icon: Icon(
                          Icons.settings_outlined,
                          color: tone.mutedText,
                        ),
                      ),
                    _buildChromeIconButton(
                      key: const Key('shell-chrome-menu'),
                      tooltip: context.l10n.openCommandPalette,
                      onPressed: onShowCommandMenu,
                      iconSize: 16,
                      hoverBackgroundColor: tone.hoverBackground,
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: tone.mutedText,
                      ),
                    ),
                  ],
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
