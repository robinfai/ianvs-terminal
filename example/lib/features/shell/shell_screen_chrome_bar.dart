part of 'shell_screen.dart';

const double _shellChromeTitleHeight = appWindowTitleBarHeight;
const double _shellChromeTabRailHeight = 38;
const double _iosShellChromeTitleHeight = 44;
const double _iosShellChromeTabRailHeight = 52;
const double _shellChromeHorizontalInset = 12;
const double _compactMobileChromeBreakpoint = 600;

double desktopShellChromeHeight(BuildContext context) {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android) {
    return _shellChromeTitleHeight + _shellChromeTabRailHeight;
  }
  final line = TextPainter(
    text: TextSpan(
      text: 'Ag 国',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final height = math.max(_shellChromeTitleHeight, line.height + 12);
  line.dispose();
  return height;
}

class _ShellChromeBar extends ConsumerWidget {
  const _ShellChromeBar({
    required this.palette,
    this.sidebarOpen = false,
    required this.sidebarWidth,
    this.onToggleSidebar,
    required this.terminalBackgroundColor,
    required this.tabStripKey,
    required this.paneDropInsertionIndex,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabNewOutputTooltip,
    required this.hiddenTabsNewOutputTooltip,
    required this.hiddenTabsNewOutputPaneSessionId,
    required this.tabNewOutputPaneSessionId,
    required this.tabColor,
    required this.referenceDemoMode,
    required this.onNewTab,
    required this.onActivateSession,
    required this.onActivateBadgePane,
    required this.onNotificationInteraction,
    required this.onActivateNewOutputPane,
    required this.onCloseSession,
    required this.onReorderTab,
    required this.onSessionDragStarted,
    required this.onSessionDragUpdated,
    required this.onSessionDragEnded,
    required this.onSessionDragCancelled,
    required this.onShowTabContextMenu,
    required this.onShowCommandMenu,
    this.onOpenReplay,
    this.aiAction,
    required this.aiSessions,
    required this.onRevealApproval,
  });

  final bool sidebarOpen;
  final double sidebarWidth;
  final VoidCallback? onToggleSidebar;
  final AppThemeTokens palette;
  final Color terminalBackgroundColor;
  final GlobalKey<_ShellTabStripState> tabStripKey;
  final int? paneDropInsertionIndex;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final String Function(TerminalTab tab) tabNewOutputTooltip;
  final String Function(Iterable<TerminalTab> tabs) hiddenTabsNewOutputTooltip;
  final String? Function(Iterable<TerminalTab> tabs)
  hiddenTabsNewOutputPaneSessionId;
  final String? Function(TerminalTab tab) tabNewOutputPaneSessionId;
  final Color? Function(TerminalTab tab) tabColor;
  final bool referenceDemoMode;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onActivateBadgePane;
  final ValueChanged<_ShellNotificationInteraction> onNotificationInteraction;
  final ValueChanged<String> onActivateNewOutputPane;
  final ValueChanged<String> onCloseSession;
  final void Function({required int oldIndex, required int newIndex})
  onReorderTab;
  final ValueChanged<_ShellSessionDragData> onSessionDragStarted;
  final void Function(_ShellSessionDragData data, Offset globalPosition)
  onSessionDragUpdated;
  final ValueChanged<_ShellSessionDragData> onSessionDragEnded;
  final ValueChanged<_ShellSessionDragData> onSessionDragCancelled;
  final void Function(TerminalTab tab, Offset position) onShowTabContextMenu;
  final VoidCallback onShowCommandMenu;
  final VoidCallback? onOpenReplay;
  final Widget? aiAction;
  final Map<String, TerminalAiController> aiSessions;
  final ValueChanged<String> onRevealApproval;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
    listenable: Listenable.merge(aiSessions.values),
    builder: (_, _) => _ShellApprovalScope(
      controllers: aiSessions,
      onReveal: onRevealApproval,
      child: _buildChrome(context, ref),
    ),
  );

  Widget _buildChrome(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(
      sessionControllerProvider.select((state) => state.tabs),
    );
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final isMobilePlatform = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    };
    final windowSize = MediaQuery.sizeOf(context);
    final usesCompactMobileChrome =
        isMobilePlatform &&
        math.min(windowSize.width, windowSize.height) <
            _compactMobileChromeBreakpoint;
    final titleHeight = isIos
        ? _iosShellChromeTitleHeight
        : _shellChromeTitleHeight;
    final tabRailHeight = isIos
        ? _iosShellChromeTabRailHeight
        : _shellChromeTabRailHeight;
    final chromeBase = _ShellTabTone.chromeBaseFor(
      palette,
      terminalBackgroundColor,
    );
    final chromeTone = _ShellTabTone.fromTerminalBackground(palette: palette);
    final chromeSurface = _ShellTabTone.chromeSurfaceFor(palette, chromeBase);
    final railSurface = _ShellTabTone.railSurfaceFor(palette, chromeBase);
    if (!isMobilePlatform) {
      final track = DecoratedBox(
        key: const Key('shell-chrome-tab-rail-surface'),
        decoration: BoxDecoration(color: railSurface),
        child: DecoratedBox(
          key: const Key('shell-chrome-tab-track'),
          decoration: BoxDecoration(
            color: chromeTone.trackBackground,
            borderRadius: BorderRadius.circular(palette.radius.md),
          ),
          child: referenceDemoMode
              ? _ReferenceDemoTabStrip(
                  palette: palette,
                  tabs: tabs,
                  activeSessionId: activeSessionId,
                  onActivateSession: onActivateSession,
                )
              : _ShellTabStrip(
                  key: tabStripKey,
                  palette: palette,
                  chromeBackgroundColor: terminalBackgroundColor,
                  paneDropInsertionIndex: paneDropInsertionIndex,
                  tabs: tabs,
                  activeSessionId: activeSessionId,
                  tabHasNewOutput: tabHasNewOutput,
                  tabNewOutputTooltip: tabNewOutputTooltip,
                  hiddenTabsNewOutputTooltip: hiddenTabsNewOutputTooltip,
                  hiddenTabsNewOutputPaneSessionId:
                      hiddenTabsNewOutputPaneSessionId,
                  tabNewOutputPaneSessionId: tabNewOutputPaneSessionId,
                  tabColor: tabColor,
                  showNewTabAction: true,
                  onNewTab: onNewTab,
                  onActivateSession: onActivateSession,
                  onActivateBadgePane: onActivateBadgePane,
                  onNotificationInteraction: onNotificationInteraction,
                  onActivateNewOutputPane: onActivateNewOutputPane,
                  onCloseSession: onCloseSession,
                  onReorderTab: onReorderTab,
                  onSessionDragStarted: onSessionDragStarted,
                  onSessionDragUpdated: onSessionDragUpdated,
                  onSessionDragEnded: onSessionDragEnded,
                  onSessionDragCancelled: onSessionDragCancelled,
                  onShowTabContextMenu: onShowTabContextMenu,
                ),
        ),
      );
      return DecoratedBox(
        key: const Key('shell-chrome-bar'),
        decoration: BoxDecoration(color: terminalBackgroundColor),
        child: _ShellWindowTitleBar(
          height: desktopShellChromeHeight(context),
          sidebarOpen: sidebarOpen,
          sidebarWidth: sidebarWidth,
          onToggleSidebar: onToggleSidebar,
          palette: palette,
          tone: chromeTone,
          backgroundColor: chromeSurface,
          terminalBackgroundColor: terminalBackgroundColor,
          onShowCommandMenu: referenceDemoMode ? null : onShowCommandMenu,
          aiAction: aiAction,
          tabs: sidebarOpen ? null : track,
          tabStripKey: sidebarOpen ? null : tabStripKey,
        ),
      );
    }
    return DecoratedBox(
      key: const Key('shell-chrome-bar'),
      decoration: BoxDecoration(
        color: terminalBackgroundColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(palette.radius.lg),
          topRight: Radius.circular(palette.radius.lg),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(palette.radius.lg),
          topRight: Radius.circular(palette.radius.lg),
        ),
        child: SizedBox(
          height:
              (usesCompactMobileChrome ? 0 : titleHeight) +
              (sidebarOpen ? 0 : tabRailHeight),
          child: Column(
            children: [
              if (!usesCompactMobileChrome)
                _ShellWindowTitleBar(
                  height: titleHeight,
                  sidebarOpen: sidebarOpen,
                  sidebarWidth: sidebarWidth,
                  onToggleSidebar: onToggleSidebar,
                  palette: palette,
                  tone: chromeTone,
                  backgroundColor: chromeSurface,
                  terminalBackgroundColor: terminalBackgroundColor,
                  onShowCommandMenu: referenceDemoMode
                      ? null
                      : onShowCommandMenu,
                  aiAction: aiAction,
                ),
              if (!sidebarOpen)
                SizedBox(
                  height: tabRailHeight,
                  child: DecoratedBox(
                    key: const Key('shell-chrome-tab-rail-surface'),
                    decoration: BoxDecoration(
                      color: railSurface,
                      border: Border(
                        top: BorderSide(
                          color: chromeTone.border.withValues(alpha: 0.18),
                        ),
                        bottom: BorderSide(
                          color: chromeTone.border.withValues(alpha: 0.20),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _shellChromeHorizontalInset,
                        3,
                        _shellChromeHorizontalInset,
                        5,
                      ),
                      child: Row(
                        children: [
                          if (usesCompactMobileChrome &&
                              !referenceDemoMode) ...[
                            _buildChromeIconButton(
                              key: const Key('shell-chrome-menu'),
                              tooltip: context.l10n.openCommandPalette,
                              onPressed: onShowCommandMenu,
                              iconSize: 16,
                              hoverBackgroundColor: chromeTone.hoverBackground,
                              icon: Icon(
                                Icons.tune_rounded,
                                color: chromeTone.subtleText,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: DecoratedBox(
                              key: const Key('shell-chrome-tab-track'),
                              decoration: BoxDecoration(
                                color: chromeTone.trackBackground,
                                borderRadius: BorderRadius.circular(
                                  palette.radius.md,
                                ),
                              ),
                              child: referenceDemoMode
                                  ? _ReferenceDemoTabStrip(
                                      palette: palette,
                                      tabs: tabs,
                                      activeSessionId: activeSessionId,
                                      onActivateSession: onActivateSession,
                                    )
                                  : _ShellTabStrip(
                                      key: tabStripKey,
                                      palette: palette,
                                      chromeBackgroundColor:
                                          terminalBackgroundColor,
                                      paneDropInsertionIndex:
                                          paneDropInsertionIndex,
                                      tabs: tabs,
                                      activeSessionId: activeSessionId,
                                      tabHasNewOutput: tabHasNewOutput,
                                      tabNewOutputTooltip: tabNewOutputTooltip,
                                      hiddenTabsNewOutputTooltip:
                                          hiddenTabsNewOutputTooltip,
                                      hiddenTabsNewOutputPaneSessionId:
                                          hiddenTabsNewOutputPaneSessionId,
                                      tabNewOutputPaneSessionId:
                                          tabNewOutputPaneSessionId,
                                      tabColor: tabColor,
                                      showNewTabAction:
                                          !usesCompactMobileChrome,
                                      onNewTab: onNewTab,
                                      onActivateSession: onActivateSession,
                                      onActivateBadgePane: onActivateBadgePane,
                                      onNotificationInteraction:
                                          onNotificationInteraction,
                                      onActivateNewOutputPane:
                                          onActivateNewOutputPane,
                                      onCloseSession: onCloseSession,
                                      onReorderTab: onReorderTab,
                                      onSessionDragStarted:
                                          onSessionDragStarted,
                                      onSessionDragUpdated:
                                          onSessionDragUpdated,
                                      onSessionDragEnded: onSessionDragEnded,
                                      onSessionDragCancelled:
                                          onSessionDragCancelled,
                                      onShowTabContextMenu:
                                          onShowTabContextMenu,
                                    ),
                            ),
                          ),
                          if (usesCompactMobileChrome &&
                              !referenceDemoMode) ...[
                            ?aiAction,
                            if (onOpenReplay != null)
                              TextFieldTapRegion(
                                child: _buildChromeIconButton(
                                  key: const Key('shell-toolbar-replay'),
                                  iconSize: 20,
                                  tooltip: context.l10n.replayHubTitle,
                                  onPressed: onOpenReplay,
                                  icon: Icon(
                                    Icons.history_rounded,
                                    color: chromeTone.mutedText,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            _ShellNewTabButton(
                              palette: palette,
                              tone: chromeTone,
                              width: 44,
                              onPressed: onNewTab,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
