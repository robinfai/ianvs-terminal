part of 'shell_screen.dart';

class _ShellChromeBar extends StatelessWidget {
  const _ShellChromeBar({
    required this.palette,
    required this.terminalBackgroundColor,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabBackgroundColor,
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
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color Function(TerminalTab tab) tabBackgroundColor;
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
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: terminalBackgroundColor,
    );
    return DecoratedBox(
      key: const Key('shell-chrome-bar'),
      decoration: BoxDecoration(
        color: terminalBackgroundColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(palette.radius.lg),
          topRight: Radius.circular(palette.radius.lg),
        ),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            _WindowDragHandle(
              key: const Key('shell-window-drag-leading'),
              child: SizedBox(
                width: defaultTargetPlatform == TargetPlatform.macOS
                    ? 132
                    : palette.spacing.md,
                height: double.infinity,
              ),
            ),
            Expanded(
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
                      tabBackgroundColor: tabBackgroundColor,
                      onNewTab: onNewTab,
                      onActivateSession: onActivateSession,
                      onCloseSession: onCloseSession,
                      onReorderTab: onReorderTab,
                      onShowTabContextMenu: onShowTabContextMenu,
                    ),
            ),
            if (!referenceDemoMode) ...[
              _buildChromeIconButton(
                key: const Key('shell-chrome-menu'),
                tooltip: 'Open Command Center',
                onPressed: onShowCommandMenu,
                iconSize: 16,
                hoverBackgroundColor: chromeTone.hoverBackground,
                icon: Icon(Icons.tune_rounded, color: chromeTone.subtleText),
              ),
              SizedBox(width: palette.spacing.xs),
              const SizedBox(width: 8),
            ] else
              const SizedBox(width: 20),
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
  static const double _trafficLightCursorShieldTop = 8;
  static const double _trafficLightCursorShieldWidth = 70;
  static const double _trafficLightCursorShieldHeight = 28;

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
                tab.title,
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
    required this.tabBackgroundColor,
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
  final Color Function(TerminalTab tab) tabBackgroundColor;
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
  static const double _minReadableTabWidth = 112;
  static const double _newTabButtonWidth = 30;
  static const double _overflowButtonWidth = 120;

  String? _draggingSessionId;

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
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: widget.chromeBackgroundColor,
    );
    return SizedBox(
      key: const Key('shell-tab-strip'),
      height: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 0.0;
          final newTabWidth = math.min(_newTabButtonWidth, totalWidth);
          final tabsAreaWidth = math.max(0.0, totalWidth - newTabWidth);
          final visibleTabCount = _visibleTabCountFor(tabsAreaWidth);
          final hasOverflow = visibleTabCount < widget.tabs.length;
          final overflowWidth = hasOverflow
              ? _overflowWidthFor(
                  tabsAreaWidth,
                  visibleTabCount: visibleTabCount,
                )
              : 0.0;
          final visibleTabsWidth = math.max(0.0, tabsAreaWidth - overflowWidth);
          final tabWidth = visibleTabCount == 0
              ? 0.0
              : visibleTabsWidth / visibleTabCount;
          final visibleTabStartIndex = _visibleTabStartIndexFor(
            visibleTabCount,
          );
          final visibleTabs = visibleTabCount == 0
              ? const <TerminalTab>[]
              : widget.tabs
                    .skip(visibleTabStartIndex)
                    .take(visibleTabCount)
                    .toList(growable: false);
          final hiddenTabs = hasOverflow
              ? <TerminalTab>[
                  ...widget.tabs.take(visibleTabStartIndex),
                  ...widget.tabs.skip(visibleTabStartIndex + visibleTabCount),
                ]
              : const <TerminalTab>[];

          return Row(
            children: [
              SizedBox(
                width: visibleTabsWidth,
                child: visibleTabCount == 0
                    ? const SizedBox.expand()
                    : ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        proxyDecorator: (child, index, animation) =>
                            _ShellTabDragProxy(
                              palette: widget.palette,
                              animation: animation,
                              child: child,
                            ),
                        onReorderStart: (index) {
                          if (index >= visibleTabCount) {
                            return;
                          }
                          unawaited(HapticFeedback.selectionClick());
                          setState(() {
                            _draggingSessionId = visibleTabs[index].sessionId;
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
                              oldIndex: visibleTabStartIndex + oldIndex,
                              newIndex: math.min(
                                widget.tabs.length,
                                visibleTabStartIndex + newIndex,
                              ),
                            ),
                        itemCount: visibleTabCount,
                        itemBuilder: (context, index) {
                          final tab = visibleTabs[index];
                          final actualIndex = visibleTabStartIndex + index;
                          final isActive =
                              widget.activeSessionId != null &&
                              tab.containsSession(widget.activeSessionId!);
                          final isDragging =
                              _draggingSessionId == tab.sessionId;
                          return _ShellReorderableTabItem(
                            key: ValueKey('shell-tab-reorder-${tab.sessionId}'),
                            width: tabWidth,
                            child: _ShellTabButton(
                              palette: widget.palette,
                              tab: tab,
                              shortcutIndex: actualIndex < 9
                                  ? actualIndex + 1
                                  : null,
                              isActive: isActive,
                              hasNewOutput: widget.tabHasNewOutput(tab),
                              terminalBackgroundColor: widget
                                  .tabBackgroundColor(tab),
                              dragRegionBuilder: (child) =>
                                  _ShellTabDragStartRegion(
                                    key: Key('shell-tab-drag-${tab.sessionId}'),
                                    index: index,
                                    useDelayedStart: _usesDelayedDragStart,
                                    isDragging: isDragging,
                                    child: child,
                                  ),
                              onActivate: () =>
                                  widget.onActivateSession(tab.activeSessionId),
                              onClose: () =>
                                  widget.onCloseSession(tab.sessionId),
                              onShowContextMenu: (position) =>
                                  widget.onShowTabContextMenu(tab, position),
                            ),
                          );
                        },
                      ),
              ),
              if (hasOverflow)
                _ShellTabOverflowMenu(
                  palette: widget.palette,
                  chromeBackgroundColor: widget.chromeBackgroundColor,
                  tabs: hiddenTabs,
                  activeSessionId: widget.activeSessionId,
                  tabHasNewOutput: widget.tabHasNewOutput,
                  tabBackgroundColor: widget.tabBackgroundColor,
                  onActivateSession: widget.onActivateSession,
                  width: overflowWidth,
                ),
              if (newTabWidth > 0)
                _ShellNewTabButton(
                  palette: widget.palette,
                  tone: chromeTone,
                  width: newTabWidth,
                  onPressed: widget.onNewTab,
                ),
            ],
          );
        },
      ),
    );
  }

  int _visibleTabCountFor(double tabsAreaWidth) {
    final tabCount = widget.tabs.length;
    if (tabCount == 0 || tabsAreaWidth <= 0) {
      return 0;
    }
    if (tabCount == 1) {
      return 1;
    }
    final capacityWithoutOverflow = tabsAreaWidth ~/ _minReadableTabWidth;
    if (tabCount <= capacityWithoutOverflow) {
      return tabCount;
    }
    final tabsWidthWithOverflow =
        tabsAreaWidth - _overflowButtonWidthFor(tabsAreaWidth);
    if (tabsWidthWithOverflow < _minReadableTabWidth) {
      return 0;
    }
    final capacityWithOverflow = tabsWidthWithOverflow ~/ _minReadableTabWidth;
    return math.min(tabCount - 1, capacityWithOverflow);
  }

  int _visibleTabStartIndexFor(int visibleTabCount) {
    if (visibleTabCount <= 0 || widget.tabs.length <= visibleTabCount) {
      return 0;
    }
    final activeIndex = widget.activeSessionId == null
        ? -1
        : widget.tabs.indexWhere(
            (tab) => tab.containsSession(widget.activeSessionId!),
          );
    if (activeIndex == -1 || activeIndex < visibleTabCount) {
      return 0;
    }
    return math.min(
      activeIndex - visibleTabCount + 1,
      widget.tabs.length - visibleTabCount,
    );
  }

  static double _overflowWidthFor(
    double tabsAreaWidth, {
    required int visibleTabCount,
  }) {
    if (visibleTabCount == 0) {
      return tabsAreaWidth;
    }
    return _overflowButtonWidthFor(tabsAreaWidth);
  }

  static double _overflowButtonWidthFor(double tabsAreaWidth) {
    if (tabsAreaWidth <= 0) {
      return 0;
    }
    return math.min(_overflowButtonWidth, tabsAreaWidth);
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
  const _ShellTabDragProxy({
    required this.palette,
    required this.animation,
    required this.child,
  });

  final AppThemeTokens palette;
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
          child: Material(
            color: palette.chromeElevated.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(palette.radius.md),
            elevation: 6 * lift,
            shadowColor: palette.elevation.floating.first.color,
            child: child!,
          ),
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
          iconSize: 18,
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
    required this.hoverBackground,
    required this.border,
    required this.primaryText,
    required this.mutedText,
    required this.subtleText,
    required this.menuSelectionBackground,
    required this.menuSelectionText,
  });

  final Color activeBackground;
  final Color hoverBackground;
  final Color border;
  final Color primaryText;
  final Color mutedText;
  final Color subtleText;
  final Color menuSelectionBackground;
  final Color menuSelectionText;

  factory _ShellTabTone.fromTerminalBackground({
    required Color terminalBackground,
  }) {
    final luminance = terminalBackground.computeLuminance();
    final isDark = luminance < 0.5;
    final contrastColor = isDark ? Colors.white : Colors.black;
    final hoverBackground = _neutralHighlightFor(terminalBackground);
    final border = Color.lerp(
      terminalBackground,
      contrastColor,
      isDark ? 0.34 : 0.26,
    )!;
    final menuSelectionBackground = _neutralHighlightFor(
      terminalBackground,
      emphasis: true,
    );
    final primaryText = _readableTextOn(terminalBackground);
    final inactiveText = _readableTextOn(terminalBackground);

    return _ShellTabTone(
      activeBackground: terminalBackground,
      hoverBackground: hoverBackground,
      border: border,
      primaryText: primaryText,
      mutedText: inactiveText.withValues(alpha: 0.82),
      subtleText: inactiveText.withValues(alpha: 0.58),
      menuSelectionBackground: menuSelectionBackground,
      menuSelectionText: _readableTextOn(menuSelectionBackground),
    );
  }

  static Color _readableTextOn(Color background) {
    return background.computeLuminance() < 0.5 ? Colors.white : Colors.black;
  }

  static Color _neutralHighlightFor(Color background, {bool emphasis = false}) {
    final hsl = HSLColor.fromColor(background);
    final isDark = background.computeLuminance() < 0.5;
    final delta = emphasis ? 0.24 : 0.16;
    final lightness = isDark
        ? math.min(1.0, hsl.lightness + delta)
        : math.max(0.0, hsl.lightness - delta);
    return hsl.withSaturation(0).withLightness(lightness).toColor();
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
    required this.onActivateSession,
    required this.width,
  });

  final AppThemeTokens palette;
  final Color chromeBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final ValueChanged<String> onActivateSession;
  final double width;

  @override
  State<_ShellTabOverflowMenu> createState() => _ShellTabOverflowMenuState();
}

class _ShellTabOverflowMenuState extends State<_ShellTabOverflowMenu> {
  static const double _menuWidth = 176;
  static const double _menuMaxHeight = 360;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _hovered = false;

  @override
  void didUpdateWidget(_ShellTabOverflowMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_overlayEntry == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _overlayEntry == null) {
        return;
      }
      if (widget.tabs.isEmpty) {
        _closeMenu();
      } else {
        _overlayEntry!.markNeedsBuild();
      }
    });
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
            offset: Offset(widget.width - _menuWidth, 38),
            child: _ShellTabOverflowPanel(
              palette: widget.palette,
              width: _menuWidth,
              maxHeight: _menuMaxHeight,
              tabs: widget.tabs,
              activeSessionId: widget.activeSessionId,
              tabHasNewOutput: widget.tabHasNewOutput,
              tabBackgroundColor: widget.tabBackgroundColor,
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
    final label = activeHiddenTab?.title ?? '${widget.tabs.length} more';
    final activeTone = activeHiddenTab == null
        ? null
        : _ShellTabTone.fromTerminalBackground(
            terminalBackground: widget.tabBackgroundColor(activeHiddenTab),
          );
    final chromeTone = _ShellTabTone.fromTerminalBackground(
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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    border: Border(
                      left: BorderSide(
                        color:
                            activeTone?.border.withValues(alpha: 0.72) ??
                            chromeTone.border.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.palette.spacing.md,
                    ),
                    child: Row(
                      children: [
                        if (hasHiddenNewOutput) ...[
                          _ShellTabNewOutputDot(
                            key: const Key('shell-tab-overflow-new-output'),
                            palette: widget.palette,
                          ),
                          const SizedBox(width: 7),
                        ],
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: isActive
                                      ? activeTone!.primaryText
                                      : chromeTone.mutedText,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 120),
                          turns: isOpen ? 0.5 : 0,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: isActive
                                ? activeTone!.subtleText
                                : chromeTone.subtleText,
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
    required this.onSelected,
  });

  final AppThemeTokens palette;
  final double width;
  final double maxHeight;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final Color Function(TerminalTab tab) tabBackgroundColor;
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
    required this.onSelected,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final bool isActive;
  final bool hasNewOutput;
  final Color terminalBackgroundColor;
  final VoidCallback onSelected;

  @override
  State<_ShellTabOverflowRow> createState() => _ShellTabOverflowRowState();
}

class _ShellTabOverflowRowState extends State<_ShellTabOverflowRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: widget.terminalBackgroundColor,
    );
    final background = widget.isActive
        ? tone.menuSelectionBackground
        : _hovered
        ? tone.hoverBackground
        : Colors.transparent;
    final textColor = widget.isActive
        ? tone.menuSelectionText
        : widget.palette.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 9),
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
                          ? tone.menuSelectionText
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
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.tab.title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontSize: 13,
                    height: 1,
                    fontWeight: widget.isActive
                        ? FontWeight.w700
                        : FontWeight.w500,
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
        child: const SizedBox.square(dimension: 8),
      ),
    );
  }
}

class _ShellTabButton extends StatelessWidget {
  const _ShellTabButton({
    required this.palette,
    required this.tab,
    required this.shortcutIndex,
    required this.isActive,
    required this.hasNewOutput,
    required this.terminalBackgroundColor,
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
  final Color terminalBackgroundColor;
  final Widget Function(Widget child) dragRegionBuilder;
  final VoidCallback onActivate;
  final VoidCallback onClose;
  final ValueChanged<Offset> onShowContextMenu;

  @override
  Widget build(BuildContext context) {
    final tone = _ShellTabTone.fromTerminalBackground(
      terminalBackground: terminalBackgroundColor,
    );
    final tabTextStyle = Theme.of(context).textTheme.titleSmall!.copyWith(
      color: isActive ? tone.primaryText : tone.mutedText,
      fontWeight: FontWeight.w500,
    );
    final tabBorder = isActive
        ? Border(
            top: BorderSide(color: tone.border.withValues(alpha: 0.58)),
            left: BorderSide(color: tone.border.withValues(alpha: 0.72)),
            right: BorderSide(color: tone.border.withValues(alpha: 0.72)),
          )
        : Border(
            left: BorderSide(color: tone.border.withValues(alpha: 0.34)),
            right: BorderSide(color: tone.border.withValues(alpha: 0.34)),
            bottom: BorderSide(color: tone.border.withValues(alpha: 0.34)),
          );

    return Semantics(
      identifier: _shellTabSemanticsIdentifier(tab),
      label: _shellTabSemanticsLabel(tab, shortcutIndex),
      selected: isActive,
      button: true,
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) {
            onShowContextMenu(event.position);
          }
        },
        child: SizedBox.expand(
          child: DecoratedBox(
            key: Key('shell-tab-border-${tab.sessionId}'),
            decoration: BoxDecoration(border: tabBorder),
            child: Stack(
              children: [
                dragRegionBuilder(
                  SizedBox.expand(
                    child: TextButton(
                      key: Key('shell-tab-${tab.sessionId}'),
                      style: ButtonStyle(
                        minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(
                          horizontal: -1,
                          vertical: -2,
                        ),
                        foregroundColor: WidgetStatePropertyAll(
                          isActive ? tone.primaryText : tone.mutedText,
                        ),
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (isActive) {
                            return tone.activeBackground;
                          }
                          if (states.contains(WidgetState.hovered) ||
                              states.contains(WidgetState.focused)) {
                            return tone.hoverBackground;
                          }
                          return Colors.transparent;
                        }),
                        side: const WidgetStatePropertyAll(BorderSide.none),
                        shape: const WidgetStatePropertyAll(
                          RoundedRectangleBorder(),
                        ),
                      ),
                      onPressed: onActivate,
                      child: Center(
                        child: KeyedSubtree(
                          key: Key('shell-tab-title-${tab.sessionId}'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (shortcutIndex != null) ...[
                                Text(
                                  '⌘$shortcutIndex',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: isActive
                                            ? tone.subtleText
                                            : tone.subtleText,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (hasNewOutput && !isActive) ...[
                                _ShellTabNewOutputDot(
                                  key: Key(
                                    'shell-tab-new-output-${tab.sessionId}',
                                  ),
                                  palette: palette,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 140),
                                  style: tabTextStyle,
                                  child: Text(
                                    tab.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: palette.spacing.sm,
                  bottom: 0,
                  child: Tooltip(
                    message: 'Close ${tab.title}',
                    child: GestureDetector(
                      key: Key('shell-tab-close-${tab.sessionId}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onClose,
                      child: Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: isActive
                            ? tone.subtleText.withValues(alpha: 0.78)
                            : tone.subtleText.withValues(alpha: 0.48),
                      ),
                    ),
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

String _shellTabSemanticsIdentifier(TerminalTab tab) {
  return 'shell-tab-${tab.sessionId}';
}

String _shellTabSemanticsLabel(TerminalTab tab, int? shortcutIndex) {
  final shortcut = shortcutIndex == null ? '' : ', Command $shortcutIndex';
  return '${tab.title} tab$shortcut';
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
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
        },
      ),
    );
  }
}
