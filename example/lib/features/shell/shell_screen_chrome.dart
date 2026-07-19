part of 'shell_screen.dart';

const double _shellChromeTitleHeight = 38;
const double _shellChromeTabRailHeight = 38;
const double _shellChromeHeight =
    _shellChromeTitleHeight + _shellChromeTabRailHeight;
const double _shellChromeHorizontalInset = 12;

class _ShellChromeBar extends StatelessWidget {
  const _ShellChromeBar({
    required this.palette,
    required this.terminalBackgroundColor,
    required this.tabs,
    required this.activeSessionId,
    required this.activeTabTitle,
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
    required this.onActivateNewOutputPane,
    required this.onCloseSession,
    required this.onReorderTab,
    required this.onShowTabContextMenu,
    required this.onShowCommandMenu,
  });

  final AppThemeTokens palette;
  final Color terminalBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final String activeTabTitle;
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
  final ValueChanged<String> onActivateNewOutputPane;
  final ValueChanged<String> onCloseSession;
  final void Function({required int oldIndex, required int newIndex})
  onReorderTab;
  final void Function(TerminalTab tab, Offset position) onShowTabContextMenu;
  final VoidCallback onShowCommandMenu;

  @override
  Widget build(BuildContext context) {
    final chromeBase = _ShellTabTone.chromeBaseFor(
      palette,
      terminalBackgroundColor,
    );
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      palette: palette,
      terminalBackground: chromeBase,
    );
    final chromeSurface = _ShellTabTone.chromeSurfaceFor(palette, chromeBase);
    final railSurface = _ShellTabTone.railSurfaceFor(palette, chromeBase);
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
          height: _shellChromeHeight,
          child: Column(
            children: [
              _ShellWindowTitleBar(
                palette: palette,
                tone: chromeTone,
                backgroundColor: chromeSurface,
                title: activeTabTitle,
                onShowCommandMenu: referenceDemoMode ? null : onShowCommandMenu,
              ),
              SizedBox(
                height: _shellChromeTabRailHeight,
                child: DecoratedBox(
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
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: chromeTone.trackBackground,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: referenceDemoMode
                          ? _ReferenceDemoTabStrip(
                              palette: palette,
                              tabs: tabs,
                              activeSessionId: activeSessionId,
                              onActivateSession: onActivateSession,
                            )
                          : _ShellTabStrip(
                              palette: palette,
                              chromeBackgroundColor: terminalBackgroundColor,
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
                              onNewTab: onNewTab,
                              onActivateSession: onActivateSession,
                              onActivateBadgePane: onActivateBadgePane,
                              onActivateNewOutputPane: onActivateNewOutputPane,
                              onCloseSession: onCloseSession,
                              onReorderTab: onReorderTab,
                              onShowTabContextMenu: onShowTabContextMenu,
                            ),
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

class _ShellWindowTitleBar extends StatelessWidget {
  const _ShellWindowTitleBar({
    required this.palette,
    required this.tone,
    required this.backgroundColor,
    required this.title,
    required this.onShowCommandMenu,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final Color backgroundColor;
  final String title;
  final VoidCallback? onShowCommandMenu;

  @override
  Widget build(BuildContext context) {
    final titleLeadingInset = defaultTargetPlatform == TargetPlatform.macOS
        ? 158.0
        : palette.spacing.xl;
    final trailingInset = onShowCommandMenu == null ? 16.0 : 48.0;

    return SizedBox(
      height: _shellChromeTitleHeight,
      child: DecoratedBox(
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
                  padding: EdgeInsets.only(
                    left: titleLeadingInset,
                    right: trailingInset,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          key: const Key('shell-chrome-window-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: tone.mutedText,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onShowCommandMenu != null)
              Positioned(
                top: 5,
                right: 12,
                child: _buildChromeIconButton(
                  key: const Key('shell-chrome-menu'),
                  tooltip: 'Open command palette',
                  onPressed: onShowCommandMenu,
                  iconSize: 16,
                  hoverBackgroundColor: tone.hoverBackground,
                  icon: Icon(Icons.tune_rounded, color: tone.subtleText),
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
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return child;
    }
    return _MacWindowDragHandle(child: child);
  }
}

class _MacWindowDragHandle extends StatelessWidget {
  const _MacWindowDragHandle({required this.child});

  final Widget child;
  static const double _trafficLightCursorShieldLeft = 8;
  static const double _trafficLightCursorShieldTop = 7;
  static const double _trafficLightCursorShieldWidth = 70;
  static const double _trafficLightCursorShieldHeight = 24;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            unawaited(WindowBridge.beginWindowDrag());
          },
          child: child,
        ),
        const Positioned(
          left: _trafficLightCursorShieldLeft,
          top: _trafficLightCursorShieldTop,
          width: _trafficLightCursorShieldWidth,
          height: _trafficLightCursorShieldHeight,
          child: Listener(
            key: Key('shell-window-traffic-light-cursor-shield'),
            behavior: HitTestBehavior.opaque,
            child: SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _ShellConfigurationWarningsBanner extends StatelessWidget {
  const _ShellConfigurationWarningsBanner({
    required this.palette,
    required this.warnings,
    required this.onReviewProfiles,
    required this.onDismiss,
  });

  final AppThemeTokens palette;
  final List<TerminalProfileLoadWarning> warnings;
  final Future<void> Function() onReviewProfiles;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-configuration-warnings'),
      decoration: BoxDecoration(
        color: palette.warningContainer,
        border: Border(bottom: BorderSide(color: palette.warning)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: palette.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Some terminal profile values were ignored and reset to safe defaults.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final warning in warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            terminalProfileLoadWarningMessage(warning),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSubtle),
                          ),
                        ),
                    ],
                  ),
                ),
                _buildCompactActionButton(
                  key: const Key('shell-configuration-warnings-dismiss'),
                  tooltip: 'Dismiss configuration warnings',
                  onPressed: onDismiss,
                  icon: Icon(Icons.close_rounded, color: palette.textSubtle),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                FilledButton.tonal(
                  key: const Key('shell-configuration-warnings-review'),
                  onPressed: () => unawaited(onReviewProfiles()),
                  child: const Text('Review Profiles'),
                ),
                const SizedBox(width: 6),
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceDemoTabStrip extends StatelessWidget {
  const _ReferenceDemoTabStrip({
    required this.palette,
    required this.tabs,
    required this.activeSessionId,
    required this.onActivateSession,
  });

  final AppThemeTokens palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final ValueChanged<String> onActivateSession;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('shell-tab-strip'),
      children: [
        for (var index = 0; index < tabs.length; index++) ...[
          Expanded(
            child: _ReferenceDemoTab(
              palette: palette,
              tab: tabs[index],
              shortcutIndex: index < 9 ? index + 1 : null,
              isActive:
                  activeSessionId != null &&
                  tabs[index].containsSession(activeSessionId!),
              onActivate: () => onActivateSession(tabs[index].activeSessionId),
            ),
          ),
          if (index < tabs.length - 1)
            SizedBox(
              width: 1,
              height: double.infinity,
              child: ColoredBox(color: palette.border),
            ),
        ],
      ],
    );
  }
}

class _ReferenceDemoTab extends StatelessWidget {
  const _ReferenceDemoTab({
    required this.palette,
    required this.tab,
    required this.shortcutIndex,
    required this.isActive,
    required this.onActivate,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
  final bool isActive;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final title = _shellTabDisplayTitle(tab);
    return Semantics(
      identifier: _shellTabSemanticsIdentifier(tab),
      label: _shellTabSemanticsLabel(tab, shortcutIndex),
      selected: isActive,
      button: true,
      child: TextButton(
        key: Key('shell-tab-${tab.sessionId}'),
        onPressed: onActivate,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isActive ? palette.textPrimary : palette.textMuted,
          shape: const RoundedRectangleBorder(),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shortcutIndex != null) ...[
                Text(
                  '⌘$shortcutIndex',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isActive ? palette.textMuted : palette.textSubtle,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: isActive ? palette.textPrimary : palette.textSubtle,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellTabStrip extends StatefulWidget {
  const _ShellTabStrip({
    required this.palette,
    required this.chromeBackgroundColor,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabNewOutputTooltip,
    required this.hiddenTabsNewOutputTooltip,
    required this.hiddenTabsNewOutputPaneSessionId,
    required this.tabNewOutputPaneSessionId,
    required this.tabColor,
    required this.onNewTab,
    required this.onActivateSession,
    required this.onActivateBadgePane,
    required this.onActivateNewOutputPane,
    required this.onCloseSession,
    required this.onReorderTab,
    required this.onShowTabContextMenu,
  });

  final AppThemeTokens palette;
  final Color chromeBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final String Function(TerminalTab tab) tabNewOutputTooltip;
  final String Function(Iterable<TerminalTab> tabs) hiddenTabsNewOutputTooltip;
  final String? Function(Iterable<TerminalTab> tabs)
  hiddenTabsNewOutputPaneSessionId;
  final String? Function(TerminalTab tab) tabNewOutputPaneSessionId;
  final Color? Function(TerminalTab tab) tabColor;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onActivateBadgePane;
  final ValueChanged<String> onActivateNewOutputPane;
  final ValueChanged<String> onCloseSession;
  final void Function({required int oldIndex, required int newIndex})
  onReorderTab;
  final void Function(TerminalTab tab, Offset position) onShowTabContextMenu;

  @override
  State<_ShellTabStrip> createState() => _ShellTabStripState();
}

class _ShellTabStripState extends State<_ShellTabStrip> {
  static const double _regularMinTabWidth = 180;
  static const double _compactMinTabWidth = 104;
  static const double _compactTabThreshold = 140;
  static const double _tabActionButtonWidth = 40;

  String? _draggingSessionId;
  final Map<String, FocusNode> _tabFocusNodes = <String, FocusNode>{};

  @override
  void didUpdateWidget(_ShellTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveSessionIds = widget.tabs.map((tab) => tab.sessionId).toSet();
    final staleSessionIds = _tabFocusNodes.keys
        .where((sessionId) => !liveSessionIds.contains(sessionId))
        .toList(growable: false);
    for (final sessionId in staleSessionIds) {
      _tabFocusNodes.remove(sessionId)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final focusNode in _tabFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  FocusNode _focusNodeForTab(TerminalTab tab) {
    return _tabFocusNodes.putIfAbsent(
      tab.sessionId,
      () => FocusNode(debugLabel: 'shell-tab-${tab.sessionId}'),
    );
  }

  bool get _usesDelayedDragStart {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final chromeBackground = _ShellTabTone.chromeBaseFor(
      widget.palette,
      widget.chromeBackgroundColor,
    );
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      palette: widget.palette,
      terminalBackground: chromeBackground,
    );
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SizedBox(
        key: const Key('shell-tab-strip'),
        height: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 0.0;
            final actionButtonWidth = math.min(
              _tabActionButtonWidth,
              totalWidth,
            );
            final tabsAreaWidth = math.max(0.0, totalWidth - actionButtonWidth);
            final visibleTabCount = _visibleTabCountFor(tabsAreaWidth);
            final hasOverflow = visibleTabCount < widget.tabs.length;
            final hiddenTabs = hasOverflow
                ? widget.tabs.skip(visibleTabCount).toList(growable: false)
                : const <TerminalTab>[];
            final visibleTabsCapacity = tabsAreaWidth;
            final tabWidth = visibleTabCount == 0
                ? 0.0
                : visibleTabsCapacity / visibleTabCount;
            final compactTabs = tabWidth < _compactTabThreshold;
            final visibleTabsWidth = tabWidth * visibleTabCount;

            return Row(
              children: [
                SizedBox(
                  width: visibleTabsWidth,
                  child: visibleTabCount == 0
                      ? const SizedBox.expand()
                      : ReorderableListView.builder(
                          scrollDirection: Axis.horizontal,
                          buildDefaultDragHandles: false,
                          padding: EdgeInsets.zero,
                          proxyDecorator: (child, index, animation) =>
                              _ShellTabDragProxy(
                                animation: animation,
                                child: child,
                              ),
                          onReorderStart: (index) {
                            if (index >= visibleTabCount) {
                              return;
                            }
                            unawaited(HapticFeedback.selectionClick());
                            setState(() {
                              _draggingSessionId = widget.tabs[index].sessionId;
                            });
                          },
                          onReorderEnd: (_) {
                            if (_draggingSessionId == null) {
                              return;
                            }
                            setState(() {
                              _draggingSessionId = null;
                            });
                          },
                          onReorderItem: (oldIndex, newIndex) =>
                              widget.onReorderTab(
                                oldIndex: oldIndex,
                                newIndex: newIndex,
                              ),
                          itemCount: visibleTabCount,
                          itemBuilder: (context, index) {
                            final tab = widget.tabs[index];
                            final isActive =
                                widget.activeSessionId != null &&
                                tab.containsSession(widget.activeSessionId!);
                            final isDragging =
                                _draggingSessionId == tab.sessionId;
                            final shortcutIndex = !compactTabs && index < 9
                                ? index + 1
                                : null;
                            return _ShellReorderableTabItem(
                              key: ValueKey(
                                'shell-tab-reorder-${tab.sessionId}',
                              ),
                              width: tabWidth,
                              child: FocusTraversalOrder(
                                order: NumericFocusOrder(index.toDouble()),
                                child: _ShellTabButton(
                                  palette: widget.palette,
                                  tab: tab,
                                  shortcutIndex: shortcutIndex,
                                  isActive: isActive,
                                  hasNewOutput: widget.tabHasNewOutput(tab),
                                  newOutputTooltip: widget.tabNewOutputTooltip(
                                    tab,
                                  ),
                                  newOutputPaneSessionId: widget
                                      .tabNewOutputPaneSessionId(tab),
                                  tabColor: widget.tabColor(tab),
                                  compact: compactTabs,
                                  chromeBackgroundColor: chromeBackground,
                                  focusNode: _focusNodeForTab(tab),
                                  dragRegionBuilder: (child) =>
                                      _ShellTabDragStartRegion(
                                        key: Key(
                                          'shell-tab-drag-${tab.sessionId}',
                                        ),
                                        index: index,
                                        useDelayedStart: _usesDelayedDragStart,
                                        isDragging: isDragging,
                                        child: child,
                                      ),
                                  onActivate: () => widget.onActivateSession(
                                    tab.activeSessionId,
                                  ),
                                  onActivateBadgePane: (sessionId) =>
                                      widget.onActivateBadgePane(sessionId),
                                  onActivateNewOutputPane: (sessionId) =>
                                      widget.onActivateNewOutputPane(sessionId),
                                  onClose: () =>
                                      widget.onCloseSession(tab.sessionId),
                                  onShowContextMenu: (position) => widget
                                      .onShowTabContextMenu(tab, position),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (visibleTabsWidth < tabsAreaWidth)
                  const Expanded(child: SizedBox()),
                if (hasOverflow)
                  _ShellTabOverflowMenu(
                    palette: widget.palette,
                    chromeBackgroundColor: chromeBackground,
                    tabs: hiddenTabs,
                    activeSessionId: widget.activeSessionId,
                    tabHasNewOutput: widget.tabHasNewOutput,
                    tabNewOutputTooltip: widget.tabNewOutputTooltip,
                    hiddenTabsNewOutputTooltip:
                        widget.hiddenTabsNewOutputTooltip,
                    hiddenTabsNewOutputPaneSessionId:
                        widget.hiddenTabsNewOutputPaneSessionId,
                    tabNewOutputPaneSessionId: widget.tabNewOutputPaneSessionId,
                    tabBackgroundColor: (_) => chromeBackground,
                    tabColor: widget.tabColor,
                    onActivateSession: widget.onActivateSession,
                    onActivateBadgePane: widget.onActivateBadgePane,
                    onActivateNewOutputPane: widget.onActivateNewOutputPane,
                    width: actionButtonWidth,
                  ),
                if (!hasOverflow && actionButtonWidth > 0)
                  _ShellNewTabButton(
                    palette: widget.palette,
                    tone: chromeTone,
                    width: actionButtonWidth,
                    onPressed: widget.onNewTab,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  int _visibleTabCountFor(double tabsAreaWidth) {
    final tabCount = widget.tabs.length;
    if (tabCount == 0 || tabsAreaWidth <= 0) {
      return 0;
    }
    if (tabsAreaWidth / tabCount >= _regularMinTabWidth) {
      return tabCount;
    }
    if (tabsAreaWidth / tabCount >= _compactMinTabWidth) {
      return tabCount;
    }
    final regularVisibleCapacity = tabsAreaWidth ~/ _regularMinTabWidth;
    if (regularVisibleCapacity > 0) {
      return math.min(tabCount - 1, regularVisibleCapacity);
    }
    final compactVisibleCapacity = tabsAreaWidth ~/ _compactMinTabWidth;
    if (compactVisibleCapacity <= 0) {
      return 0;
    }
    return math.min(tabCount - 1, compactVisibleCapacity);
  }
}

class _ShellReorderableTabItem extends StatelessWidget {
  const _ShellReorderableTabItem({
    super.key,
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: child);
  }
}

class _ShellTabDragProxy extends StatelessWidget {
  const _ShellTabDragProxy({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final lift = Curves.easeOutCubic.transform(animation.value);
        return Transform.scale(
          scale: 1 + lift * 0.018,
          child: Material(type: MaterialType.transparency, child: child!),
        );
      },
    );
  }
}

class _ShellTabDragStartRegion extends StatelessWidget {
  const _ShellTabDragStartRegion({
    super.key,
    required this.index,
    required this.useDelayedStart,
    required this.isDragging,
    required this.child,
  });

  final int index;
  final bool useDelayedStart;
  final bool isDragging;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dragStartListener = useDelayedStart
        ? ReorderableDelayedDragStartListener(index: index, child: child)
        : ReorderableDragStartListener(index: index, child: child);
    return MouseRegion(
      cursor: isDragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      child: dragStartListener,
    );
  }
}

class _ShellNewTabButton extends StatelessWidget {
  const _ShellNewTabButton({
    required this.palette,
    required this.tone,
    required this.width,
    required this.onPressed,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final double width;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Center(
        child: _buildChromeIconButton(
          key: const Key('shell-chrome-new-tab'),
          tooltip: 'New tab',
          onPressed: onPressed,
          iconSize: 16,
          hoverBackgroundColor: tone.hoverBackground,
          icon: Icon(Icons.add_rounded, color: tone.subtleText),
        ),
      ),
    );
  }
}

class _ShellTabTone {
  const _ShellTabTone({
    required this.activeBackground,
    required this.trackBackground,
    required this.hoverBackground,
    required this.border,
    required this.primaryText,
    required this.mutedText,
    required this.subtleText,
  });

  final Color activeBackground;
  final Color trackBackground;
  final Color hoverBackground;
  final Color border;
  final Color primaryText;
  final Color mutedText;
  final Color subtleText;

  factory _ShellTabTone.fromTerminalBackground({
    required AppThemeTokens palette,
    required Color terminalBackground,
  }) {
    final chrome = palette.shellChrome;
    return _ShellTabTone(
      activeBackground: chrome.tabActiveBackground,
      trackBackground: chrome.tabTrackBackground,
      hoverBackground: chrome.tabHoverBackground,
      border: chrome.tabBorder,
      primaryText: chrome.tabTextPrimary,
      mutedText: chrome.tabTextMuted,
      subtleText: chrome.tabTextSubtle,
    );
  }

  static Color chromeBaseFor(AppThemeTokens palette, Color background) {
    return palette.shellChrome.base;
  }

  static Color chromeSurfaceFor(AppThemeTokens palette, Color background) {
    return palette.shellChrome.surface;
  }

  static Color railSurfaceFor(AppThemeTokens palette, Color background) {
    return palette.shellChrome.rail;
  }
}

class _ShellTabOverflowMenu extends StatefulWidget {
  const _ShellTabOverflowMenu({
    required this.palette,
    required this.chromeBackgroundColor,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabNewOutputTooltip,
    required this.hiddenTabsNewOutputTooltip,
    required this.hiddenTabsNewOutputPaneSessionId,
    required this.tabNewOutputPaneSessionId,
    required this.tabBackgroundColor,
    required this.tabColor,
    required this.onActivateSession,
    required this.onActivateBadgePane,
    required this.onActivateNewOutputPane,
    required this.width,
  });

  final AppThemeTokens palette;
  final Color chromeBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final String Function(TerminalTab tab) tabNewOutputTooltip;
  final String Function(Iterable<TerminalTab> tabs) hiddenTabsNewOutputTooltip;
  final String? Function(Iterable<TerminalTab> tabs)
  hiddenTabsNewOutputPaneSessionId;
  final String? Function(TerminalTab tab) tabNewOutputPaneSessionId;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final Color? Function(TerminalTab tab) tabColor;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onActivateBadgePane;
  final ValueChanged<String> onActivateNewOutputPane;
  final double width;

  @override
  State<_ShellTabOverflowMenu> createState() => _ShellTabOverflowMenuState();
}

class _ShellTabOverflowMenuState extends State<_ShellTabOverflowMenu> {
  static const double _menuWidth = 168;
  static const double _menuMaxHeight = 332;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _hovered = false;

  @override
  void didUpdateWidget(_ShellTabOverflowMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_overlayEntry != null) {
      if (widget.tabs.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _closeMenu();
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _overlayEntry?.markNeedsBuild();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _removeMenuEntry();
    super.dispose();
  }

  void _toggleMenu() {
    if (_overlayEntry == null) {
      _openMenu();
    } else {
      _closeMenu();
    }
  }

  void _openMenu() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(widget.width - _menuWidth, 34),
            child: _ShellTabOverflowPanel(
              palette: widget.palette,
              width: _menuWidth,
              maxHeight: _menuMaxHeight,
              tabs: widget.tabs,
              activeSessionId: widget.activeSessionId,
              tabHasNewOutput: widget.tabHasNewOutput,
              tabNewOutputTooltip: widget.tabNewOutputTooltip,
              tabNewOutputPaneSessionId: widget.tabNewOutputPaneSessionId,
              tabBackgroundColor: widget.tabBackgroundColor,
              tabColor: widget.tabColor,
              onSelected: (sessionId) {
                _closeMenu();
                widget.onActivateSession(sessionId);
              },
              onBadgeSelected: (sessionId) {
                _closeMenu();
                widget.onActivateBadgePane(sessionId);
              },
              onNewOutputPaneSelected: (sessionId) {
                _closeMenu();
                widget.onActivateNewOutputPane(sessionId);
              },
            ),
          ),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
    setState(() {});
  }

  void _closeMenu() {
    _removeMenuEntry();
    if (mounted) {
      setState(() {});
    }
  }

  void _removeMenuEntry() {
    final entry = _overlayEntry;
    if (entry == null) {
      return;
    }
    _overlayEntry = null;
    entry.remove();
  }

  @override
  Widget build(BuildContext context) {
    final activeHiddenTab = widget.activeSessionId == null
        ? null
        : widget.tabs.cast<TerminalTab?>().firstWhere(
            (tab) => tab!.containsSession(widget.activeSessionId!),
            orElse: () => null,
          );
    final isActive = activeHiddenTab != null;
    final isOpen = _overlayEntry != null;
    final hiddenOutputTabs = widget.tabs
        .where(widget.tabHasNewOutput)
        .toList(growable: false);
    final hasHiddenNewOutput = hiddenOutputTabs.isNotEmpty;
    final hiddenNewOutputPaneSessionId = widget
        .hiddenTabsNewOutputPaneSessionId(hiddenOutputTabs);
    final hiddenBadgeTargets = _shellHiddenTabBadgeTargets(
      widget.tabs,
      activeSessionId: widget.activeSessionId,
    );
    final hasHiddenBadges = hiddenBadgeTargets.isNotEmpty;
    final hiddenPaneSignalTargets = _shellHiddenTabPaneSignalTargets(
      widget.tabs,
      activeSessionId: widget.activeSessionId,
    );
    final hasHiddenPaneSignals = hiddenPaneSignalTargets.isNotEmpty;
    final activeTone = activeHiddenTab == null
        ? null
        : _ShellTabTone.fromTerminalBackground(
            palette: widget.palette,
            terminalBackground: widget.tabBackgroundColor(activeHiddenTab),
          );
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      palette: widget.palette,
      terminalBackground: widget.chromeBackgroundColor,
    );
    final background = isActive
        ? activeTone!.activeBackground
        : _hovered || isOpen
        ? chromeTone.hoverBackground
        : Colors.transparent;
    final overflowTooltip = _hiddenTabsOverflowButtonTooltip(
      hiddenTabCount: widget.tabs.length,
      badgePaneCount: hiddenBadgeTargets.length,
      paneSignalCount: hiddenPaneSignalTargets.length,
      newOutputTabCount: hiddenOutputTabs.length,
    );
    final overflowSemanticsLabel = _hiddenTabsOverflowButtonSemanticsLabel(
      hiddenTabCount: widget.tabs.length,
      badgePaneCount: hiddenBadgeTargets.length,
      paneSignalCount: hiddenPaneSignalTargets.length,
      newOutputTabCount: hiddenOutputTabs.length,
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: overflowTooltip,
        child: SizedBox(
          width: widget.width,
          height: double.infinity,
          child: Semantics(
            label: overflowSemanticsLabel,
            button: true,
            selected: isActive,
            expanded: isOpen,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                key: const Key('shell-tab-overflow-button'),
                behavior: HitTestBehavior.opaque,
                onTap: _toggleMenu,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isActive || _hovered || isOpen
                            ? (activeTone?.border ?? chromeTone.border)
                                  .withValues(alpha: isActive ? 0.34 : 0.18)
                            : Colors.transparent,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          key: const Key('shell-tab-overflow-ellipsis'),
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: isActive
                              ? activeTone!.primaryText
                              : chromeTone.subtleText,
                        ),
                        if (!isOpen && hasHiddenBadges)
                          Positioned(
                            top: 2,
                            left: 2,
                            width: 10,
                            height: 10,
                            child: _ShellTabOverflowBadgeMarker(
                              key: const Key('shell-tab-overflow-badge'),
                              palette: widget.palette,
                              tooltip: _hiddenTabsBadgeTooltip(
                                hiddenBadgeTargets,
                                activeSessionId: widget.activeSessionId,
                              ),
                              onPressed: () {
                                _closeMenu();
                                widget.onActivateBadgePane(
                                  hiddenBadgeTargets.first.badge.sessionId,
                                );
                              },
                            ),
                          ),
                        if (!isOpen && hasHiddenPaneSignals)
                          Positioned(
                            bottom: 2,
                            left: 2,
                            width: 10,
                            height: 10,
                            child: _ShellTabOverflowSignalMarker(
                              key: const Key('shell-tab-overflow-pane-signal'),
                              palette: widget.palette,
                              tooltip: _hiddenTabsPaneSignalTooltip(
                                hiddenPaneSignalTargets,
                                activeSessionId: widget.activeSessionId,
                              ),
                              onPressed: () {
                                _closeMenu();
                                widget.onActivateBadgePane(
                                  hiddenPaneSignalTargets
                                      .first
                                      .signal
                                      .sessionId,
                                );
                              },
                            ),
                          ),
                        if (!isOpen && hasHiddenNewOutput)
                          Positioned(
                            top: 0,
                            right: -2,
                            child: _ShellTabNewOutputDot(
                              key: const Key('shell-tab-overflow-new-output'),
                              palette: widget.palette,
                              tooltip: widget.hiddenTabsNewOutputTooltip(
                                hiddenOutputTabs,
                              ),
                              onPressed: hiddenNewOutputPaneSessionId == null
                                  ? null
                                  : () {
                                      _closeMenu();
                                      widget.onActivateNewOutputPane(
                                        hiddenNewOutputPaneSessionId,
                                      );
                                    },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabOverflowPanel extends StatelessWidget {
  const _ShellTabOverflowPanel({
    required this.palette,
    required this.width,
    required this.maxHeight,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabNewOutputTooltip,
    required this.tabNewOutputPaneSessionId,
    required this.tabBackgroundColor,
    required this.tabColor,
    required this.onSelected,
    required this.onBadgeSelected,
    required this.onNewOutputPaneSelected,
  });

  final AppThemeTokens palette;
  final double width;
  final double maxHeight;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final String Function(TerminalTab tab) tabNewOutputTooltip;
  final String? Function(TerminalTab tab) tabNewOutputPaneSessionId;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final Color? Function(TerminalTab tab) tabColor;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onBadgeSelected;
  final ValueChanged<String> onNewOutputPaneSelected;

  @override
  Widget build(BuildContext context) {
    final menuRadius = BorderRadius.circular(palette.radius.sm);

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: Directionality(
        textDirection: Directionality.of(context),
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: DecoratedBox(
              key: const Key('shell-tab-overflow-panel'),
              decoration: BoxDecoration(
                color: palette.panelElevated.withValues(alpha: 0.98),
                border: Border.all(
                  color: palette.borderStrong.withValues(alpha: 0.54),
                ),
                borderRadius: menuRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: menuRadius,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final tab in tabs)
                        _ShellTabOverflowRow(
                          key: Key('shell-tab-overflow-item-${tab.sessionId}'),
                          palette: palette,
                          tab: tab,
                          isActive:
                              activeSessionId != null &&
                              tab.containsSession(activeSessionId!),
                          hasNewOutput: tabHasNewOutput(tab),
                          newOutputTooltip: tabNewOutputTooltip(tab),
                          newOutputPaneSessionId: tabNewOutputPaneSessionId(
                            tab,
                          ),
                          terminalBackgroundColor: tabBackgroundColor(tab),
                          tabColor: tabColor(tab),
                          onSelected: () => onSelected(tab.activeSessionId),
                          onBadgeSelected: onBadgeSelected,
                          onNewOutputPaneSelected: onNewOutputPaneSelected,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabOverflowRow extends StatefulWidget {
  const _ShellTabOverflowRow({
    super.key,
    required this.palette,
    required this.tab,
    required this.isActive,
    required this.hasNewOutput,
    required this.newOutputTooltip,
    required this.newOutputPaneSessionId,
    required this.terminalBackgroundColor,
    required this.tabColor,
    required this.onSelected,
    required this.onBadgeSelected,
    required this.onNewOutputPaneSelected,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final bool isActive;
  final bool hasNewOutput;
  final String newOutputTooltip;
  final String? newOutputPaneSessionId;
  final Color terminalBackgroundColor;
  final Color? tabColor;
  final VoidCallback onSelected;
  final ValueChanged<String> onBadgeSelected;
  final ValueChanged<String> onNewOutputPaneSelected;

  @override
  State<_ShellTabOverflowRow> createState() => _ShellTabOverflowRowState();
}

class _ShellTabOverflowRowState extends State<_ShellTabOverflowRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final title = _shellTabDisplayTitle(widget.tab);
    final badgeInfos = _shellTabBadgeInfos(widget.tab);
    final paneSignalInfos = _shellTabPaneSignalInfos(widget.tab);
    final paneSignalInfo = paneSignalInfos.isEmpty
        ? null
        : paneSignalInfos.first;
    final canActivateBadgePane = widget.tab.effectivePanes.length > 1;
    final tabStatus = widget.tab.activePane.tabStatus;
    final indicatorColor = terminalViewportColorFromHex(tabStatus.indicator);
    final statusText = _normalizedShellTabStatusText(tabStatus.status);
    final requestedStatusColor = terminalViewportColorFromHex(
      tabStatus.statusColor,
    );
    final tone = _ShellTabTone.fromTerminalBackground(
      palette: widget.palette,
      terminalBackground: widget.terminalBackgroundColor,
    );
    final background = widget.isActive
        ? widget.palette.focus
        : _hovered
        ? tone.hoverBackground
        : Colors.transparent;
    final textColor = widget.isActive ? Colors.white : widget.palette.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: widget.isActive
                          ? Colors.white
                          : Colors.transparent,
                    ),
                    if (widget.hasNewOutput)
                      Align(
                        alignment: widget.isActive
                            ? Alignment.bottomRight
                            : Alignment.center,
                        child: _ShellTabNewOutputDot(
                          key: Key(
                            'shell-tab-new-output-${widget.tab.sessionId}',
                          ),
                          palette: widget.palette,
                          tooltip: widget.newOutputTooltip,
                          onPressed: widget.newOutputPaneSessionId == null
                              ? null
                              : () => widget.onNewOutputPaneSelected(
                                  widget.newOutputPaneSessionId!,
                                ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.tabColor == null)
                const SizedBox(width: 7)
              else ...[
                const SizedBox(width: 5),
                Tooltip(
                  message: 'Profile tab color',
                  child: DecoratedBox(
                    key: Key(
                      'shell-tab-overflow-color-${widget.tab.sessionId}',
                    ),
                    decoration: BoxDecoration(
                      color: widget.tabColor,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: widget.palette.textPrimary.withValues(
                          alpha: 0.22,
                        ),
                      ),
                    ),
                    child: const SizedBox.square(dimension: 8),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (indicatorColor != null) ...[
                Tooltip(
                  message: 'OSC 21337 session status indicator',
                  child: DecoratedBox(
                    key: Key(
                      'shell-tab-overflow-status-indicator-${widget.tab.sessionId}',
                    ),
                    decoration: BoxDecoration(
                      color: indicatorColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.palette.textPrimary.withValues(
                          alpha: 0.28,
                        ),
                      ),
                    ),
                    child: const SizedBox.square(dimension: 8),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontSize: 12,
                    height: 1,
                    fontWeight: widget.isActive
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
              if (statusText != null) ...[
                const SizedBox(width: 6),
                _ShellTabStatusLabel(
                  key: Key('shell-tab-overflow-status-${widget.tab.sessionId}'),
                  text: statusText,
                  requestedColor: requestedStatusColor,
                  backgroundColor: background == Colors.transparent
                      ? widget.terminalBackgroundColor
                      : background,
                  fallbackColor: textColor,
                  maxWidth: 72,
                ),
              ],
              ..._shellTabBadgeChips(
                keyPrefix: 'shell-tab-overflow-badge-${widget.tab.sessionId}',
                tab: widget.tab,
                badges: badgeInfos,
                palette: widget.palette,
                foreground: textColor,
                background: widget.palette.panel.withValues(
                  alpha: widget.isActive ? 0.32 : 0.64,
                ),
                border: widget.palette.textPrimary.withValues(alpha: 0.20),
                maxWidth: 54,
                badgeNeedsFocus: (badge) =>
                    !(widget.isActive && badge.isActivePane),
                onSelected: canActivateBadgePane
                    ? widget.onBadgeSelected
                    : null,
              ),
              if (paneSignalInfo != null) ...[
                const SizedBox(width: 6),
                _ShellTabBadgeChip(
                  key: Key(
                    'shell-tab-overflow-pane-signal-${widget.tab.sessionId}',
                  ),
                  palette: widget.palette,
                  text: _shellTabPaneSignalLabel(paneSignalInfos),
                  tooltip: _shellTabPaneSignalTooltip(
                    widget.tab,
                    paneSignalInfo,
                    paneSignalInfos,
                    primaryNeedsFocus:
                        !(widget.isActive && paneSignalInfo.isActivePane),
                  ),
                  semanticsLabel: _shellTabPaneSignalSemanticsLabel(
                    widget.tab,
                    paneSignalInfo,
                    paneSignalInfos,
                    primaryNeedsFocus:
                        !(widget.isActive && paneSignalInfo.isActivePane),
                  ),
                  onPressed: () =>
                      widget.onBadgeSelected(paneSignalInfo.sessionId),
                  foreground: textColor,
                  background: widget.palette.focusRing.withValues(
                    alpha: widget.isActive ? 0.34 : 0.58,
                  ),
                  border: widget.palette.focusRing.withValues(alpha: 0.34),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellTabOverflowBadgeMarker extends StatelessWidget {
  const _ShellTabOverflowBadgeMarker({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.onPressed,
  });

  final AppThemeTokens palette;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        label: tooltip,
        button: true,
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 10,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.warningContainer.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: palette.warning.withValues(alpha: 0.78),
                    ),
                  ),
                  child: Icon(
                    Icons.badge_outlined,
                    size: 7,
                    color: palette.warning,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabOverflowSignalMarker extends StatelessWidget {
  const _ShellTabOverflowSignalMarker({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.onPressed,
  });

  final AppThemeTokens palette;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        label: tooltip,
        button: true,
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 10,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.focusRing.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: palette.textPrimary.withValues(alpha: 0.36),
                    ),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 7,
                    color: palette.panel,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabNewOutputDot extends StatelessWidget {
  const _ShellTabNewOutputDot({
    super.key,
    required this.palette,
    required this.tooltip,
    this.onPressed,
  });

  final AppThemeTokens palette;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final marker = Semantics(
      container: true,
      label: tooltip,
      button: onPressed != null,
      onTap: onPressed,
      child: SizedBox.square(
        dimension: 14,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.focus,
              shape: BoxShape.circle,
              border: Border.all(
                color: palette.textPrimary.withValues(alpha: 0.36),
              ),
            ),
            child: const SizedBox.square(dimension: 7),
          ),
        ),
      ),
    );
    final tooltipMarker = Tooltip(message: tooltip, child: marker);
    if (onPressed == null) {
      return tooltipMarker;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: tooltipMarker,
      ),
    );
  }
}

class _ShellTabBadgeChip extends StatelessWidget {
  const _ShellTabBadgeChip({
    super.key,
    required this.palette,
    required this.text,
    required this.tooltip,
    required this.semanticsLabel,
    required this.foreground,
    required this.background,
    required this.border,
    this.maxWidth = 72,
    this.onPressed,
  });

  final AppThemeTokens palette;
  final String text;
  final String tooltip;
  final String semanticsLabel;
  final Color foreground;
  final Color background;
  final Color border;
  final double maxWidth;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final onPressed = this.onPressed;
    final chip = Tooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        label: semanticsLabel,
        button: onPressed != null,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontSize: 9.5,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (onPressed == null) {
      return chip;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: chip,
      ),
    );
  }
}

List<Widget> _shellTabBadgeChips({
  required String keyPrefix,
  required TerminalTab tab,
  required List<_ShellTabBadgeInfo> badges,
  required AppThemeTokens palette,
  required Color foreground,
  required Color background,
  required Color border,
  required double maxWidth,
  required bool Function(_ShellTabBadgeInfo badge) badgeNeedsFocus,
  required ValueChanged<String>? onSelected,
}) {
  if (badges.isEmpty) {
    return const <Widget>[];
  }
  const visibleBadgeLimit = 2;
  final visibleBadges = badges.take(visibleBadgeLimit).toList(growable: false);
  final hiddenBadges = badges.skip(visibleBadgeLimit).toList(growable: false);
  final chips = <Widget>[];

  for (var index = 0; index < visibleBadges.length; index += 1) {
    final badge = visibleBadges[index];
    chips.add(const SizedBox(width: 6));
    chips.add(
      _ShellTabBadgeChip(
        key: Key(index == 0 ? keyPrefix : '$keyPrefix-${badge.sessionId}'),
        palette: palette,
        text: _shellTabBadgeLabel(badge.text, badgeCount: 1),
        tooltip: _shellTabBadgeTooltip(
          tab,
          badge,
          badges,
          badgeNeedsFocus: badgeNeedsFocus(badge),
        ),
        semanticsLabel: _shellTabBadgeSemanticsLabel(
          tab,
          badge,
          badges,
          badgeNeedsFocus: badgeNeedsFocus(badge),
        ),
        onPressed: onSelected == null
            ? null
            : () => onSelected(badge.sessionId),
        foreground: foreground,
        background: background,
        border: border,
        maxWidth: maxWidth,
      ),
    );
  }

  if (hiddenBadges.isNotEmpty) {
    final firstHidden = hiddenBadges.first;
    chips.add(const SizedBox(width: 6));
    chips.add(
      _ShellTabBadgeChip(
        key: Key('$keyPrefix-more'),
        palette: palette,
        text: '+${hiddenBadges.length}',
        tooltip: _shellTabBadgeOverflowTooltip(
          tab,
          hiddenBadges,
          badgeNeedsFocus,
        ),
        semanticsLabel: _shellTabBadgeOverflowSemanticsLabel(
          tab,
          hiddenBadges,
          badgeNeedsFocus,
        ),
        onPressed: onSelected == null
            ? null
            : () => onSelected(firstHidden.sessionId),
        foreground: foreground,
        background: background,
        border: border,
        maxWidth: 34,
      ),
    );
  }

  return chips;
}

class _ShellTabButton extends StatefulWidget {
  const _ShellTabButton({
    required this.palette,
    required this.tab,
    required this.shortcutIndex,
    required this.isActive,
    required this.hasNewOutput,
    required this.newOutputTooltip,
    required this.newOutputPaneSessionId,
    required this.tabColor,
    required this.compact,
    required this.chromeBackgroundColor,
    required this.focusNode,
    required this.dragRegionBuilder,
    required this.onActivate,
    required this.onActivateBadgePane,
    required this.onActivateNewOutputPane,
    required this.onClose,
    required this.onShowContextMenu,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
  final bool isActive;
  final bool hasNewOutput;
  final String newOutputTooltip;
  final String? newOutputPaneSessionId;
  final Color? tabColor;
  final bool compact;
  final Color chromeBackgroundColor;
  final FocusNode focusNode;
  final Widget Function(Widget child) dragRegionBuilder;
  final VoidCallback onActivate;
  final ValueChanged<String> onActivateBadgePane;
  final ValueChanged<String> onActivateNewOutputPane;
  final VoidCallback onClose;
  final ValueChanged<Offset> onShowContextMenu;

  @override
  State<_ShellTabButton> createState() => _ShellTabButtonState();
}

class _ShellTabButtonState extends State<_ShellTabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final title = _shellTabDisplayTitle(widget.tab);
    final badgeInfos = _shellTabBadgeInfos(widget.tab);
    final paneSignalInfos = _shellTabPaneSignalInfos(widget.tab);
    final paneSignalInfo = paneSignalInfos.isEmpty
        ? null
        : paneSignalInfos.first;
    final canActivateBadgePane = widget.tab.effectivePanes.length > 1;
    final tabStatus = widget.tab.activePane.tabStatus;
    final indicatorColor = terminalViewportColorFromHex(tabStatus.indicator);
    final statusText = _normalizedShellTabStatusText(tabStatus.status);
    final requestedStatusColor = terminalViewportColorFromHex(
      tabStatus.statusColor,
    );
    final tone = _ShellTabTone.fromTerminalBackground(
      palette: widget.palette,
      terminalBackground: widget.chromeBackgroundColor,
    );
    final tabTextStyle = Theme.of(context).textTheme.titleSmall!.copyWith(
      color: widget.isActive ? tone.primaryText : tone.mutedText,
      fontSize: 12.5,
      fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w600,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        identifier: _shellTabSemanticsIdentifier(widget.tab),
        label: _shellTabSemanticsLabel(
          widget.tab,
          widget.shortcutIndex,
          hasNewOutput: widget.hasNewOutput,
        ),
        selected: widget.isActive,
        button: true,
        excludeSemantics: true,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (event.buttons & kSecondaryMouseButton != 0) {
              widget.onShowContextMenu(event.position);
            }
          },
          child: SizedBox.expand(
            child: DecoratedBox(
              key: Key('shell-tab-border-${widget.tab.sessionId}'),
              decoration: const BoxDecoration(),
              child: Stack(
                children: [
                  widget.dragRegionBuilder(
                    SizedBox.expand(
                      child: TextButton(
                        key: Key('shell-tab-${widget.tab.sessionId}'),
                        focusNode: widget.focusNode,
                        style: ButtonStyle(
                          minimumSize: const WidgetStatePropertyAll(
                            Size(0, 30),
                          ),
                          padding: WidgetStatePropertyAll(
                            EdgeInsets.symmetric(
                              horizontal: widget.compact ? 8 : 12,
                            ),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(
                            horizontal: -1,
                            vertical: -3,
                          ),
                          foregroundColor: WidgetStatePropertyAll(
                            widget.isActive ? tone.primaryText : tone.mutedText,
                          ),
                          overlayColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (widget.isActive) {
                              return tone.activeBackground;
                            }
                            if (states.contains(WidgetState.hovered) ||
                                states.contains(WidgetState.focused)) {
                              return tone.hoverBackground;
                            }
                            return Colors.transparent;
                          }),
                          side: WidgetStatePropertyAll(
                            widget.isActive
                                ? BorderSide(
                                    color: tone.border.withValues(alpha: 0.34),
                                  )
                                : BorderSide.none,
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                        onPressed: widget.onActivate,
                        child: Center(
                          child: KeyedSubtree(
                            key: Key('shell-tab-title-${widget.tab.sessionId}'),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (indicatorColor != null) ...[
                                  Tooltip(
                                    message:
                                        'OSC 21337 session status indicator',
                                    child: DecoratedBox(
                                      key: Key(
                                        'shell-tab-status-indicator-${widget.tab.sessionId}',
                                      ),
                                      decoration: BoxDecoration(
                                        color: indicatorColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: tone.primaryText.withValues(
                                            alpha: 0.28,
                                          ),
                                        ),
                                      ),
                                      child: const SizedBox.square(
                                        dimension: 8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 140),
                                    style: tabTextStyle,
                                    child: Text(
                                      title,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (statusText != null) ...[
                                  const SizedBox(width: 6),
                                  _ShellTabStatusLabel(
                                    key: Key(
                                      'shell-tab-status-${widget.tab.sessionId}',
                                    ),
                                    text: statusText,
                                    requestedColor: requestedStatusColor,
                                    backgroundColor: widget.isActive
                                        ? tone.activeBackground
                                        : widget.chromeBackgroundColor,
                                    fallbackColor: widget.isActive
                                        ? tone.primaryText
                                        : tone.mutedText,
                                    maxWidth: widget.compact ? 48 : 72,
                                  ),
                                ],
                                ..._shellTabBadgeChips(
                                  keyPrefix:
                                      'shell-tab-badge-${widget.tab.sessionId}',
                                  tab: widget.tab,
                                  badges: badgeInfos,
                                  palette: widget.palette,
                                  foreground: widget.isActive
                                      ? tone.primaryText
                                      : tone.mutedText,
                                  background: tone.hoverBackground.withValues(
                                    alpha: widget.isActive ? 0.70 : 0.45,
                                  ),
                                  border: tone.border.withValues(alpha: 0.38),
                                  maxWidth: widget.compact ? 46 : 62,
                                  badgeNeedsFocus: (badge) =>
                                      !(widget.isActive && badge.isActivePane),
                                  onSelected: canActivateBadgePane
                                      ? widget.onActivateBadgePane
                                      : null,
                                ),
                                if (paneSignalInfo != null) ...[
                                  const SizedBox(width: 6),
                                  _ShellTabBadgeChip(
                                    key: Key(
                                      'shell-tab-pane-signal-${widget.tab.sessionId}',
                                    ),
                                    palette: widget.palette,
                                    text: _shellTabPaneSignalLabel(
                                      paneSignalInfos,
                                    ),
                                    tooltip: _shellTabPaneSignalTooltip(
                                      widget.tab,
                                      paneSignalInfo,
                                      paneSignalInfos,
                                      primaryNeedsFocus:
                                          !(widget.isActive &&
                                              paneSignalInfo.isActivePane),
                                    ),
                                    semanticsLabel:
                                        _shellTabPaneSignalSemanticsLabel(
                                          widget.tab,
                                          paneSignalInfo,
                                          paneSignalInfos,
                                          primaryNeedsFocus:
                                              !(widget.isActive &&
                                                  paneSignalInfo.isActivePane),
                                        ),
                                    onPressed: () => widget.onActivateBadgePane(
                                      paneSignalInfo.sessionId,
                                    ),
                                    foreground: widget.isActive
                                        ? tone.primaryText
                                        : tone.mutedText,
                                    background: widget.palette.focusRing
                                        .withValues(
                                          alpha: widget.isActive ? 0.58 : 0.42,
                                        ),
                                    border: widget.palette.focusRing.withValues(
                                      alpha: 0.34,
                                    ),
                                  ),
                                ],
                                if (widget.hasNewOutput) ...[
                                  const SizedBox(width: 6),
                                  _ShellTabNewOutputDot(
                                    key: Key(
                                      'shell-tab-new-output-${widget.tab.sessionId}',
                                    ),
                                    palette: widget.palette,
                                    tooltip: widget.newOutputTooltip,
                                    onPressed:
                                        widget.newOutputPaneSessionId == null
                                        ? null
                                        : () => widget.onActivateNewOutputPane(
                                            widget.newOutputPaneSessionId!,
                                          ),
                                  ),
                                ],
                                if (widget.shortcutIndex != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '⌘${widget.shortcutIndex}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: tone.subtleText,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.tabColor != null)
                    Positioned(
                      top: 2,
                      left: widget.compact ? 10 : 14,
                      right: widget.compact ? 10 : 14,
                      child: IgnorePointer(
                        child: Tooltip(
                          message: 'Profile tab color',
                          child: DecoratedBox(
                            key: Key('shell-tab-color-${widget.tab.sessionId}'),
                            decoration: BoxDecoration(
                              color: widget.tabColor,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: widget.palette.textPrimary.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                            child: const SizedBox(height: 3),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: widget.palette.spacing.md,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 80),
                        opacity: _hovered ? 1 : 0,
                        child: Tooltip(
                          message: 'Close $title',
                          child: GestureDetector(
                            key: Key('shell-tab-close-${widget.tab.sessionId}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onClose,
                            child: Icon(
                              Icons.close_rounded,
                              size: 12,
                              color: tone.subtleText.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _shellTabSemanticsIdentifier(TerminalTab tab) {
  return 'shell-tab-${tab.sessionId}';
}

String _shellTabSemanticsLabel(
  TerminalTab tab,
  int? shortcutIndex, {
  bool hasNewOutput = false,
}) {
  final parts = <String>['${_shellTabDisplayTitle(tab)} tab'];
  final tabStatus = tab.activePane.tabStatus;
  final statusText = _normalizedShellTabStatusText(tabStatus.status);
  if (statusText != null) {
    parts.add(
      tab.effectivePanes.length < 2
          ? 'status $statusText'
          : 'status $statusText from active pane',
    );
  }
  if (tabStatus.indicator != null) {
    parts.add(
      tab.effectivePanes.length < 2
          ? 'status indicator active'
          : 'status indicator active on active pane',
    );
  }
  final badges = _shellTabBadgeInfos(tab);
  final badge = badges.isEmpty ? null : badges.first;
  final additionalBadgeCount = badges.length - 1;
  if (badge != null) {
    if (tab.effectivePanes.length < 2) {
      parts.add('badge ${badge.text}');
    } else {
      parts.add(
        'badge ${badge.text} from ${badge.isActivePane ? 'active' : 'inactive'} pane',
      );
      if (additionalBadgeCount > 0) {
        parts.add(
          'plus $additionalBadgeCount other pane badge${additionalBadgeCount == 1 ? '' : 's'}',
        );
      }
    }
  }

  final signals = _shellTabPaneSignalInfos(tab);
  if (signals.isNotEmpty) {
    final primary = signals.first;
    final signalScope = tab.effectivePanes.length < 2
        ? ''
        : ' from ${primary.isActivePane ? 'active' : 'inactive'} pane';
    parts.add('${primary.title.toLowerCase()}: ${primary.summary}$signalScope');
    final additionalSignalCount = signals.length - 1;
    if (additionalSignalCount > 0) {
      parts.add(
        'plus $additionalSignalCount other pane signal${additionalSignalCount == 1 ? '' : 's'}',
      );
    }
  }

  if (hasNewOutput) {
    parts.add(
      tab.effectivePanes.length < 2 ? 'new output' : 'new output in split pane',
    );
  }

  if (shortcutIndex != null) {
    parts.add('Command $shortcutIndex');
  }
  return parts.join(', ');
}

String _shellTabDisplayTitle(TerminalTab tab) {
  final activePaneTitle = tab.activePane.title.trim();
  return activePaneTitle.isEmpty ? tab.title : activePaneTitle;
}

List<_ShellTabBadgeInfo> _shellTabBadgeInfos(TerminalTab tab) {
  final activePane = tab.activePane;
  final badges = <_ShellTabBadgeInfo>[];

  void addPaneBadge(TerminalPane pane, {required bool isActivePane}) {
    final text = _normalizedShellTabBadgeText(pane.oscBadge);
    if (text != null) {
      badges.add(
        _ShellTabBadgeInfo(
          text: text,
          sessionId: pane.sessionId,
          paneTitle: pane.title,
          isActivePane: isActivePane,
        ),
      );
    }
  }

  for (final pane in tab.effectivePanes) {
    if (pane.sessionId != activePane.sessionId) {
      addPaneBadge(pane, isActivePane: false);
    }
  }
  addPaneBadge(activePane, isActivePane: true);
  return badges;
}

String? _normalizedShellTabBadgeText(String? rawText) {
  final text = rawText?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

String? _normalizedShellTabStatusText(String? rawText) {
  final text = rawText?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

class _ShellTabStatusLabel extends StatelessWidget {
  const _ShellTabStatusLabel({
    super.key,
    required this.text,
    required this.requestedColor,
    required this.backgroundColor,
    required this.fallbackColor,
    required this.maxWidth,
  });

  final String text;
  final Color? requestedColor;
  final Color backgroundColor;
  final Color fallbackColor;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final requested = requestedColor ?? fallbackColor;
    final chipBackground = Color.alphaBlend(
      requested.withValues(alpha: 0.14),
      backgroundColor,
    );
    final foreground = _shellAccessibleForeground(
      requested,
      chipBackground,
      fallbackColor,
    );
    return Tooltip(
      message: 'OSC 21337 status: $text',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: requested.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: requested.withValues(alpha: 0.40)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.6),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontSize: 10.5,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _shellAccessibleForeground(
  Color requested,
  Color background,
  Color fallback,
) {
  if (_shellContrastRatio(requested, background) >= 4.5) {
    return requested;
  }
  if (_shellContrastRatio(fallback, background) >= 4.5) {
    return fallback;
  }
  final black = Colors.black;
  final white = Colors.white;
  return _shellContrastRatio(black, background) >=
          _shellContrastRatio(white, background)
      ? black
      : white;
}

double _shellContrastRatio(Color foreground, Color background) {
  final lighter = math.max(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  final darker = math.min(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  return (lighter + 0.05) / (darker + 0.05);
}

String _shellTabBadgeLabel(String text, {required int badgeCount}) {
  final trimmed = text.trim();
  final suffix = badgeCount > 1 ? ' +${badgeCount - 1}' : '';
  final maxRunes = badgeCount > 1 ? 7 : 10;
  final runes = trimmed.runes.toList(growable: false);
  final visible = runes.length <= maxRunes
      ? trimmed
      : '${String.fromCharCodes(runes.take(maxRunes - 1))}…';
  return '${visible.toUpperCase()}$suffix';
}

String _shellTabBadgeTooltip(
  TerminalTab tab,
  _ShellTabBadgeInfo badge,
  List<_ShellTabBadgeInfo> badges, {
  required bool badgeNeedsFocus,
}) {
  if (tab.effectivePanes.length < 2) {
    return 'OSC 1337 badge: ${badge.text}';
  }
  final otherBadges = badges
      .where((candidate) => candidate.sessionId != badge.sessionId)
      .toList(growable: false);
  return [
    'OSC 1337 badge: ${badge.text}',
    _shellTabBadgePaneContext(badge),
    if (otherBadges.isNotEmpty) ...[
      'Other pane badges:',
      for (final otherBadge in otherBadges)
        '${_shellTabBadgePaneContext(otherBadge)}: ${otherBadge.text}',
    ],
    if (badgeNeedsFocus) 'Click to focus this pane.',
  ].join('\n');
}

String _shellTabBadgeSemanticsLabel(
  TerminalTab tab,
  _ShellTabBadgeInfo badge,
  List<_ShellTabBadgeInfo> badges, {
  required bool badgeNeedsFocus,
}) {
  if (tab.effectivePanes.length < 2) {
    return 'Terminal badge: ${badge.text}';
  }
  final otherBadgeCount = badges
      .where((candidate) => candidate.sessionId != badge.sessionId)
      .length;
  final otherBadgeLabel = otherBadgeCount == 0
      ? ''
      : '; $otherBadgeCount other pane badge${otherBadgeCount == 1 ? '' : 's'}';
  return 'Terminal badge: ${badge.text}; '
      '${_shellTabBadgePaneContext(badge)}$otherBadgeLabel; '
      '${badgeNeedsFocus ? 'click to focus this pane' : 'pane already focused'}';
}

String _shellTabBadgeOverflowTooltip(
  TerminalTab tab,
  List<_ShellTabBadgeInfo> hiddenBadges,
  bool Function(_ShellTabBadgeInfo badge) badgeNeedsFocus,
) {
  if (hiddenBadges.length == 1) {
    final badge = hiddenBadges.single;
    return [
      'Additional OSC 1337 badge: ${badge.text}',
      _shellTabBadgePaneContext(badge),
      badgeNeedsFocus(badge)
          ? 'Click to focus this pane.'
          : 'Pane already focused.',
    ].join('\n');
  }
  final firstHiddenNeedsFocus = badgeNeedsFocus(hiddenBadges.first);
  return [
    'Additional OSC 1337 badges in this split tab.',
    for (final badge in hiddenBadges)
      '${_shellTabBadgePaneContext(badge)}: ${badge.text}',
    firstHiddenNeedsFocus
        ? 'Click to focus the first remaining badge pane.'
        : 'First remaining badge pane is already focused.',
  ].join('\n');
}

String _shellTabBadgeOverflowSemanticsLabel(
  TerminalTab tab,
  List<_ShellTabBadgeInfo> hiddenBadges,
  bool Function(_ShellTabBadgeInfo badge) badgeNeedsFocus,
) {
  if (hiddenBadges.length == 1) {
    final badge = hiddenBadges.single;
    final action = badgeNeedsFocus(badge)
        ? 'click to focus this pane'
        : 'pane already focused';
    return 'Terminal badge: ${badge.text}; ${_shellTabBadgePaneContext(badge)}; $action';
  }
  final action = badgeNeedsFocus(hiddenBadges.first)
      ? 'click to focus the first remaining badge pane'
      : 'first remaining badge pane is already focused';
  return 'Terminal badges: ${hiddenBadges.length} additional pane badges in ${_shellTabDisplayTitle(tab)}; $action';
}

String _shellTabBadgePaneContext(_ShellTabBadgeInfo badge) {
  final paneState = badge.isActivePane ? 'active pane' : 'inactive pane';
  final title = badge.paneTitle.trim();
  if (title.isEmpty) {
    return 'Pane: ${badge.sessionId} · $paneState';
  }
  return 'Pane: $title (${badge.sessionId}) · $paneState';
}

class _ShellTabBadgeInfo {
  const _ShellTabBadgeInfo({
    required this.text,
    required this.sessionId,
    required this.paneTitle,
    required this.isActivePane,
  });

  final String text;
  final String sessionId;
  final String paneTitle;
  final bool isActivePane;
}

enum _ShellTabPaneSignalKind { progress, notification }

class _ShellTabPaneSignalInfo {
  const _ShellTabPaneSignalInfo({
    required this.kind,
    required this.sessionId,
    required this.paneTitle,
    required this.isActivePane,
    required this.detail,
    required this.summary,
  });

  final _ShellTabPaneSignalKind kind;
  final String sessionId;
  final String paneTitle;
  final bool isActivePane;
  final String detail;
  final String summary;

  String get label {
    return switch (kind) {
      _ShellTabPaneSignalKind.progress => 'PROG',
      _ShellTabPaneSignalKind.notification => 'NOTE',
    };
  }

  String get title {
    return switch (kind) {
      _ShellTabPaneSignalKind.progress => 'Terminal progress',
      _ShellTabPaneSignalKind.notification => 'Terminal notification',
    };
  }
}

List<TerminalPaneProgressState> _shellPaneActiveProgressItems(
  TerminalPane pane,
) {
  return <TerminalPaneProgressState>[
    if (pane.progress case final progress? when progress.active) progress,
    for (final progress in pane.namedProgress.values)
      if (progress.active) progress,
  ];
}

TerminalPaneProgressState? _shellPanePrimaryProgress(TerminalPane pane) {
  final primary = pane.progress;
  final activePrimary = primary != null && primary.active ? primary : null;
  final activeNamed = pane.namedProgress.values
      .where((progress) => progress.active)
      .toList(growable: false);

  if (activePrimary == null) {
    return activeNamed.isEmpty ? null : activeNamed.last;
  }
  if (!_shellPaneProgressIsComplete(activePrimary)) {
    return activePrimary;
  }
  final runningNamed = activeNamed
      .where((progress) => !_shellPaneProgressIsComplete(progress))
      .toList(growable: false);
  if (runningNamed.isNotEmpty) {
    return runningNamed.last;
  }
  return activeNamed.isEmpty ? activePrimary : activeNamed.last;
}

bool _shellPaneProgressIsComplete(TerminalPaneProgressState progress) {
  return progress.action == 'complete' || progress.state == 'complete';
}

List<_ShellTabPaneSignalInfo> _shellTabPaneSignalInfos(TerminalTab tab) {
  final activePane = tab.activePane;
  final signals = <_ShellTabPaneSignalInfo>[];

  void addPaneSignals(TerminalPane pane, {required bool isActivePane}) {
    final progressItems = _shellPaneActiveProgressItems(pane);
    if (progressItems.isNotEmpty) {
      final primaryProgress = _shellPanePrimaryProgress(pane)!;
      signals.add(
        _ShellTabPaneSignalInfo(
          kind: _ShellTabPaneSignalKind.progress,
          sessionId: pane.sessionId,
          paneTitle: pane.title,
          isActivePane: isActivePane,
          detail: progressItems.length == 1
              ? _shellTabProgressDetail(primaryProgress)
              : [
                  'Terminal progress in this pane.',
                  for (final progress in progressItems)
                    '${progress.displayLabel}: ${_shellTabProgressDetail(progress)}',
                ].join('\n'),
          summary: primaryProgress.displayLabel,
        ),
      );
    }

    final notification = pane.recentNotifications.isEmpty
        ? null
        : pane.recentNotifications.first;
    if (notification != null) {
      signals.add(
        _ShellTabPaneSignalInfo(
          kind: _ShellTabPaneSignalKind.notification,
          sessionId: pane.sessionId,
          paneTitle: pane.title,
          isActivePane: isActivePane,
          detail: _shellTabNotificationDetail(notification),
          summary:
              '${notification.title}${notification.count > 1 ? ' x${notification.count}' : ''}',
        ),
      );
    }
  }

  for (final pane in tab.effectivePanes) {
    if (pane.sessionId == activePane.sessionId) {
      continue;
    }
    addPaneSignals(pane, isActivePane: false);
  }
  addPaneSignals(activePane, isActivePane: true);
  return signals;
}

String _shellTabPaneSignalLabel(List<_ShellTabPaneSignalInfo> signals) {
  if (signals.isEmpty) {
    return 'PANE';
  }
  final suffix = signals.length > 1 ? ' +${signals.length - 1}' : '';
  return '${signals.first.label}$suffix';
}

String _shellTabPaneSignalTooltip(
  TerminalTab tab,
  _ShellTabPaneSignalInfo primary,
  List<_ShellTabPaneSignalInfo> signals, {
  required bool primaryNeedsFocus,
}) {
  final otherSignals = signals
      .where((candidate) => candidate != primary)
      .toList(growable: false);
  if (tab.effectivePanes.length < 2 && otherSignals.isEmpty) {
    return [primary.title, primary.detail].join('\n');
  }
  return [
    '${primary.title} in a split pane.',
    _shellTabPaneSignalContext(primary),
    primary.detail,
    if (otherSignals.isNotEmpty) ...[
      'Other pane signals:',
      for (final otherSignal in otherSignals)
        '${_shellTabPaneSignalContext(otherSignal)}: '
            '${otherSignal.label} ${otherSignal.summary}',
    ],
    if (primaryNeedsFocus)
      otherSignals.isEmpty
          ? 'Click to focus this pane.'
          : 'Click to focus the first pane with a signal.',
  ].join('\n');
}

String _shellTabPaneSignalSemanticsLabel(
  TerminalTab tab,
  _ShellTabPaneSignalInfo primary,
  List<_ShellTabPaneSignalInfo> signals, {
  required bool primaryNeedsFocus,
}) {
  if (tab.effectivePanes.length < 2) {
    return '${primary.title}: ${primary.summary}';
  }
  final otherSignalCount = signals.length - 1;
  final otherSignalLabel = otherSignalCount <= 0
      ? ''
      : '; $otherSignalCount other pane signal${otherSignalCount == 1 ? '' : 's'}';
  return '${primary.title}: ${primary.summary}; '
      '${_shellTabPaneSignalContext(primary)}$otherSignalLabel; '
      '${primaryNeedsFocus ? 'click to focus this pane' : 'pane already focused'}';
}

String _shellTabPaneSignalContext(_ShellTabPaneSignalInfo signal) {
  final paneState = signal.isActivePane ? 'active pane' : 'inactive pane';
  final title = signal.paneTitle.trim();
  if (title.isEmpty) {
    return 'Pane: ${signal.sessionId} · $paneState';
  }
  return 'Pane: $title (${signal.sessionId}) · $paneState';
}

String _shellTabProgressDetail(TerminalPaneProgressState progress) {
  return [
    'Terminal progress reported by ${progress.source}.',
    if (progress.label?.trim().isNotEmpty == true)
      'Label: ${progress.label!.trim()}',
    if (progress.percent != null) 'Percent: ${progress.percent}%',
    if (progress.state?.trim().isNotEmpty == true)
      'State: ${progress.state!.trim()}',
    if (progress.id?.trim().isNotEmpty == true) 'ID: ${progress.id!.trim()}',
  ].join('\n');
}

String _shellTabNotificationDetail(TerminalPaneNotificationState notification) {
  return [
    'Terminal notification reported by ${notification.source}.',
    'Title: ${notification.title}',
    if (notification.message.trim().isNotEmpty)
      'Message: ${notification.message.trim()}',
    if (notification.remoteHost?.trim().isNotEmpty == true)
      'Remote host: ${notification.remoteHost!.trim()}',
    if (notification.remoteUser?.trim().isNotEmpty == true)
      'Remote user: ${notification.remoteUser!.trim()}',
    if (notification.count > 1) 'Count: ${notification.count}',
  ].join('\n');
}

List<_ShellHiddenTabBadgeTarget> _shellHiddenTabBadgeTargets(
  Iterable<TerminalTab> tabs, {
  required String? activeSessionId,
}) {
  final targets = <_ShellHiddenTabBadgeTarget>[];
  for (final tab in tabs) {
    for (final badge in _shellTabBadgeInfos(tab)) {
      targets.add(_ShellHiddenTabBadgeTarget(tab: tab, badge: badge));
    }
  }
  return _prioritizeHiddenTargets(
    targets,
    activeSessionId: activeSessionId,
    sessionIdFor: (target) => target.badge.sessionId,
  );
}

String _hiddenTabsBadgeTooltip(
  List<_ShellHiddenTabBadgeTarget> targets, {
  required String? activeSessionId,
}) {
  if (targets.length == 1) {
    final target = targets.single;
    final needsFocus = target.badge.sessionId != activeSessionId;
    return [
      'OSC 1337 badge in a hidden tab.',
      'Tab: ${_shellTabDisplayTitle(target.tab)} (${target.tab.sessionId})',
      'OSC 1337 badge: ${target.badge.text}',
      _shellTabBadgePaneContext(target.badge),
      needsFocus ? 'Click to focus this pane.' : 'Pane already focused.',
    ].join('\n');
  }
  final hasFocusableTarget = targets.any(
    (target) => target.badge.sessionId != activeSessionId,
  );
  return [
    'OSC 1337 badges in ${targets.length} hidden panes.',
    for (final target in targets)
      '${_shellTabDisplayTitle(target.tab)} (${target.tab.sessionId}) - '
          '${_shellTabBadgePaneContext(target.badge)}: ${target.badge.text}',
    hasFocusableTarget
        ? 'Click to focus the first badge pane.'
        : 'Pane already focused.',
  ].join('\n');
}

class _ShellHiddenTabBadgeTarget {
  const _ShellHiddenTabBadgeTarget({required this.tab, required this.badge});

  final TerminalTab tab;
  final _ShellTabBadgeInfo badge;
}

List<_ShellHiddenTabPaneSignalTarget> _shellHiddenTabPaneSignalTargets(
  Iterable<TerminalTab> tabs, {
  required String? activeSessionId,
}) {
  final targets = <_ShellHiddenTabPaneSignalTarget>[];
  for (final tab in tabs) {
    for (final signal in _shellTabPaneSignalInfos(tab)) {
      targets.add(_ShellHiddenTabPaneSignalTarget(tab: tab, signal: signal));
    }
  }
  return _prioritizeHiddenTargets(
    targets,
    activeSessionId: activeSessionId,
    sessionIdFor: (target) => target.signal.sessionId,
  );
}

String _hiddenTabsPaneSignalTooltip(
  List<_ShellHiddenTabPaneSignalTarget> targets, {
  required String? activeSessionId,
}) {
  if (targets.length == 1) {
    final target = targets.single;
    final needsFocus = target.signal.sessionId != activeSessionId;
    return [
      '${target.signal.title} in a hidden tab.',
      'Tab: ${_shellTabDisplayTitle(target.tab)} (${target.tab.sessionId})',
      _shellTabPaneSignalContext(target.signal),
      target.signal.detail,
      needsFocus ? 'Click to focus this pane.' : 'Pane already focused.',
    ].join('\n');
  }
  final hasFocusableTarget = targets.any(
    (target) => target.signal.sessionId != activeSessionId,
  );
  return [
    'Pane signals in ${targets.length} hidden panes.',
    for (final target in targets)
      '${_shellTabDisplayTitle(target.tab)} (${target.tab.sessionId}) - '
          '${_shellTabPaneSignalContext(target.signal)}: '
          '${target.signal.label} ${target.signal.summary}',
    hasFocusableTarget
        ? 'Click to focus the first pane with a signal.'
        : 'Pane already focused.',
  ].join('\n');
}

String _hiddenTabsOverflowButtonTooltip({
  required int hiddenTabCount,
  required int badgePaneCount,
  required int paneSignalCount,
  required int newOutputTabCount,
}) {
  final hasSignals =
      badgePaneCount > 0 || paneSignalCount > 0 || newOutputTabCount > 0;
  return [
    hiddenTabCount == 1
        ? 'Show 1 hidden tab'
        : 'Show $hiddenTabCount hidden tabs',
    if (badgePaneCount > 0)
      badgePaneCount == 1
          ? 'Hidden OSC 1337 badge: 1 pane'
          : 'Hidden OSC 1337 badges: $badgePaneCount panes',
    if (paneSignalCount > 0)
      paneSignalCount == 1
          ? 'Hidden pane signal: 1 pane'
          : 'Hidden pane signals: $paneSignalCount panes',
    if (newOutputTabCount > 0)
      newOutputTabCount == 1
          ? 'Hidden new output: 1 tab'
          : 'Hidden new output: $newOutputTabCount tabs',
    if (hasSignals) 'Signal markers can focus their source panes.',
  ].join('\n');
}

String _hiddenTabsOverflowButtonSemanticsLabel({
  required int hiddenTabCount,
  required int badgePaneCount,
  required int paneSignalCount,
  required int newOutputTabCount,
}) {
  return [
    hiddenTabCount == 1
        ? 'Show 1 hidden tab'
        : 'Show $hiddenTabCount hidden tabs',
    if (badgePaneCount > 0)
      badgePaneCount == 1
          ? '1 hidden OSC 1337 badge pane'
          : '$badgePaneCount hidden OSC 1337 badge panes',
    if (paneSignalCount > 0)
      paneSignalCount == 1
          ? '1 hidden pane signal'
          : '$paneSignalCount hidden pane signals',
    if (newOutputTabCount > 0)
      newOutputTabCount == 1
          ? '1 hidden tab with new output'
          : '$newOutputTabCount hidden tabs with new output',
  ].join(', ');
}

List<T> _prioritizeHiddenTargets<T>(
  List<T> targets, {
  required String? activeSessionId,
  required String Function(T target) sessionIdFor,
}) {
  if (activeSessionId == null || targets.length < 2) {
    return targets;
  }
  return <T>[
    for (final target in targets)
      if (sessionIdFor(target) != activeSessionId) target,
    for (final target in targets)
      if (sessionIdFor(target) == activeSessionId) target,
  ];
}

class _ShellHiddenTabPaneSignalTarget {
  const _ShellHiddenTabPaneSignalTarget({
    required this.tab,
    required this.signal,
  });

  final TerminalTab tab;
  final _ShellTabPaneSignalInfo signal;
}

class _ShellStartupSurface extends StatelessWidget {
  const _ShellStartupSurface({
    super.key,
    required this.palette,
    required this.errorMessage,
    required this.onRetry,
  });

  final AppThemeTokens palette;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        border: Border(top: BorderSide(color: palette.terminalFrame)),
      ),
      child: errorMessage == null
          ? const SizedBox.expand()
          : Semantics(
              container: true,
              liveRegion: true,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppEmptyState(
                    key: const Key('shell-startup-error'),
                    title: 'Terminal could not start',
                    message:
                        'Review the startup error, then try loading the workspace again.',
                    supportingText: errorMessage!,
                    action: AppActionButton(
                      buttonKey: const Key('shell-startup-retry'),
                      icon: Icons.refresh,
                      label: 'Retry',
                      onPressed: onRetry,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ShellEmptyState extends StatelessWidget {
  const _ShellEmptyState({
    super.key,
    required this.palette,
    required this.title,
    required this.message,
    required this.defaultSummary,
    required this.onNewTab,
  });

  final AppThemeTokens palette;
  final String title;
  final String message;
  final String defaultSummary;
  final VoidCallback? onNewTab;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        border: Border(top: BorderSide(color: palette.terminalFrame)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppEmptyState(
            title: title,
            message: message,
            supportingText: defaultSummary,
            action: AppActionButton(
              buttonKey: const Key('shell-empty-new-tab'),
              icon: Icons.add_box_outlined,
              label: 'New Tab',
              onPressed: onNewTab,
            ),
          ),
        ),
      ),
    );
  }
}
