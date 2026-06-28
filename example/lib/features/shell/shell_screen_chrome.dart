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
    required this.tabColor,
    required this.referenceDemoMode,
    required this.onNewTab,
    required this.onActivateSession,
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
  final Color? Function(TerminalTab tab) tabColor;
  final bool referenceDemoMode;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
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
                              tabColor: tabColor,
                              onNewTab: onNewTab,
                              onActivateSession: onActivateSession,
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
                  tooltip: 'Open command menu',
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

class _MacWindowDragHandle extends StatefulWidget {
  const _MacWindowDragHandle({required this.child});

  final Widget child;

  @override
  State<_MacWindowDragHandle> createState() => _MacWindowDragHandleState();
}

class _MacWindowDragHandleState extends State<_MacWindowDragHandle> {
  static const double _trafficLightCursorShieldLeft = 8;
  static const double _trafficLightCursorShieldTop = 7;
  static const double _trafficLightCursorShieldWidth = 70;
  static const double _trafficLightCursorShieldHeight = 24;

  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MouseRegion(
          cursor: _dragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              setState(() {
                _dragging = true;
              });
              unawaited(WindowBridge.beginWindowDrag());
            },
            onPointerUp: (_) {
              setState(() {
                _dragging = false;
              });
            },
            onPointerCancel: (_) {
              setState(() {
                _dragging = false;
              });
            },
            child: Tooltip(message: 'Drag window', child: widget.child),
          ),
        ),
        const Positioned(
          left: _trafficLightCursorShieldLeft,
          top: _trafficLightCursorShieldTop,
          width: _trafficLightCursorShieldWidth,
          height: _trafficLightCursorShieldHeight,
          child: MouseRegion(
            key: Key('shell-window-traffic-light-cursor-shield'),
            cursor: SystemMouseCursors.basic,
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
    required this.tabColor,
    required this.onNewTab,
    required this.onActivateSession,
    required this.onCloseSession,
    required this.onReorderTab,
    required this.onShowTabContextMenu,
  });

  final AppThemeTokens palette;
  final Color chromeBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color? Function(TerminalTab tab) tabColor;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
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
                    tabBackgroundColor: (_) => chromeBackground,
                    tabColor: widget.tabColor,
                    onActivateSession: widget.onActivateSession,
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
    required this.tabBackgroundColor,
    required this.tabColor,
    required this.onActivateSession,
    required this.width,
  });

  final AppThemeTokens palette;
  final Color chromeBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final Color? Function(TerminalTab tab) tabColor;
  final ValueChanged<String> onActivateSession;
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
        _closeMenu();
      } else {
        _overlayEntry!.markNeedsBuild();
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
              tabBackgroundColor: widget.tabBackgroundColor,
              tabColor: widget.tabColor,
              onSelected: (sessionId) {
                _closeMenu();
                widget.onActivateSession(sessionId);
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
    final hasHiddenNewOutput = widget.tabs.any(widget.tabHasNewOutput);
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

    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: 'Show hidden tabs',
        child: SizedBox(
          width: widget.width,
          height: double.infinity,
          child: Semantics(
            label: 'shell-tab-overflow',
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
                        if (hasHiddenNewOutput)
                          Positioned(
                            top: 5,
                            right: 4,
                            child: _ShellTabNewOutputDot(
                              key: const Key('shell-tab-overflow-new-output'),
                              palette: widget.palette,
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
    required this.tabBackgroundColor,
    required this.tabColor,
    required this.onSelected,
  });

  final AppThemeTokens palette;
  final double width;
  final double maxHeight;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final Color? Function(TerminalTab tab) tabColor;
  final ValueChanged<String> onSelected;

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
                          terminalBackgroundColor: tabBackgroundColor(tab),
                          tabColor: tabColor(tab),
                          onSelected: () => onSelected(tab.activeSessionId),
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
    required this.terminalBackgroundColor,
    required this.tabColor,
    required this.onSelected,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final bool isActive;
  final bool hasNewOutput;
  final Color terminalBackgroundColor;
  final Color? tabColor;
  final VoidCallback onSelected;

  @override
  State<_ShellTabOverflowRow> createState() => _ShellTabOverflowRowState();
}

class _ShellTabOverflowRowState extends State<_ShellTabOverflowRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final title = _shellTabDisplayTitle(widget.tab);
    final badgeText = _shellTabBadgeText(widget.tab);
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
                    if (!widget.isActive && widget.hasNewOutput)
                      _ShellTabNewOutputDot(
                        key: Key(
                          'shell-tab-new-output-${widget.tab.sessionId}',
                        ),
                        palette: widget.palette,
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
              if (badgeText != null) ...[
                const SizedBox(width: 6),
                _ShellTabBadgeChip(
                  key: Key('shell-tab-overflow-badge-${widget.tab.sessionId}'),
                  palette: widget.palette,
                  text: _shellTabBadgeLabel(badgeText),
                  fullText: badgeText,
                  foreground: textColor,
                  background: widget.palette.panel.withValues(
                    alpha: widget.isActive ? 0.32 : 0.64,
                  ),
                  border: widget.palette.textPrimary.withValues(alpha: 0.20),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellTabNewOutputDot extends StatelessWidget {
  const _ShellTabNewOutputDot({super.key, required this.palette});

  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New output',
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
    );
  }
}

class _ShellTabBadgeChip extends StatelessWidget {
  const _ShellTabBadgeChip({
    super.key,
    required this.palette,
    required this.text,
    required this.fullText,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final AppThemeTokens palette;
  final String text;
  final String fullText;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'OSC 1337 badge: $fullText',
      child: Semantics(
        container: true,
        label: 'Terminal badge: $fullText',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 72),
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
  }
}

class _ShellTabButton extends StatefulWidget {
  const _ShellTabButton({
    required this.palette,
    required this.tab,
    required this.shortcutIndex,
    required this.isActive,
    required this.hasNewOutput,
    required this.tabColor,
    required this.compact,
    required this.chromeBackgroundColor,
    required this.focusNode,
    required this.dragRegionBuilder,
    required this.onActivate,
    required this.onClose,
    required this.onShowContextMenu,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
  final bool isActive;
  final bool hasNewOutput;
  final Color? tabColor;
  final bool compact;
  final Color chromeBackgroundColor;
  final FocusNode focusNode;
  final Widget Function(Widget child) dragRegionBuilder;
  final VoidCallback onActivate;
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
    final badgeText = _shellTabBadgeText(widget.tab);
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
        label: _shellTabSemanticsLabel(widget.tab, widget.shortcutIndex),
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
                                if (badgeText != null) ...[
                                  const SizedBox(width: 6),
                                  _ShellTabBadgeChip(
                                    key: Key(
                                      'shell-tab-badge-${widget.tab.sessionId}',
                                    ),
                                    palette: widget.palette,
                                    text: _shellTabBadgeLabel(badgeText),
                                    fullText: badgeText,
                                    foreground: widget.isActive
                                        ? tone.primaryText
                                        : tone.mutedText,
                                    background: tone.hoverBackground.withValues(
                                      alpha: widget.isActive ? 0.70 : 0.45,
                                    ),
                                    border: tone.border.withValues(alpha: 0.38),
                                  ),
                                ],
                                if (widget.hasNewOutput &&
                                    !widget.isActive) ...[
                                  const SizedBox(width: 6),
                                  _ShellTabNewOutputDot(
                                    key: Key(
                                      'shell-tab-new-output-${widget.tab.sessionId}',
                                    ),
                                    palette: widget.palette,
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

String _shellTabSemanticsLabel(TerminalTab tab, int? shortcutIndex) {
  final shortcut = shortcutIndex == null ? '' : ', Command $shortcutIndex';
  final badge = _shellTabBadgeText(tab);
  final badgeLabel = badge == null ? '' : ', badge $badge';
  return '${_shellTabDisplayTitle(tab)} tab$badgeLabel$shortcut';
}

String _shellTabDisplayTitle(TerminalTab tab) {
  if (tab.effectivePanes.length < 2) {
    return tab.title;
  }
  final activePaneTitle = tab.activePane.title.trim();
  return activePaneTitle.isEmpty ? tab.title : activePaneTitle;
}

String? _shellTabBadgeText(TerminalTab tab) {
  final text = tab.activePane.oscBadge?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

String _shellTabBadgeLabel(String text) {
  final trimmed = text.trim();
  const maxRunes = 10;
  final runes = trimmed.runes.toList(growable: false);
  if (runes.length <= maxRunes) {
    return trimmed.toUpperCase();
  }
  return '${String.fromCharCodes(runes.take(maxRunes - 1)).toUpperCase()}…';
}

class _ShellStartupSurface extends StatelessWidget {
  const _ShellStartupSurface({super.key, required this.palette});

  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        border: Border(top: BorderSide(color: palette.terminalFrame)),
      ),
      child: const SizedBox.expand(),
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
