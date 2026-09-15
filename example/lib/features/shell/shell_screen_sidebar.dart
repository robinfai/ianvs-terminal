part of 'shell_screen.dart';

class _SessionGroupNode {
  _SessionGroupNode(this.label, this.path);
  final String label;
  final String path;
  final children = <String, _SessionGroupNode>{};
  final tabs = <TerminalTab>[];
}

class _SessionSidebar extends ConsumerStatefulWidget {
  const _SessionSidebar({
    required this.visible,
    required this.activeSessionId,
    required this.onActivate,
    required this.onClose,
    required this.onNew,
    required this.onContextMenu,
    required this.hasNewOutput,
  });

  final bool visible;
  final String? activeSessionId;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;
  final VoidCallback? onNew;
  final void Function(TerminalTab, Offset) onContextMenu;
  final bool Function(TerminalTab) hasNewOutput;

  @override
  ConsumerState<_SessionSidebar> createState() => _SessionSidebarState();
}

class _SessionSidebarState extends ConsumerState<_SessionSidebar> {
  String? _hoveredSession;
  final _collapsed = <String>{};
  final _alternate = <String, bool>{};
  final _watches = <String, ({Listenable viewport, VoidCallback listener})>{};
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.visible &&
          ref
              .read(sessionControllerProvider)
              .tabs
              .any(
                (tab) =>
                    !tab.activePane.isExited &&
                    tab.activePane.shellIntegration.commandStartedAt != null,
              )) {
        setState(() {});
      }
    });
  }

  void _syncViewports(List<TerminalTab> tabs) {
    final runtime = ref.read(terminalRuntimeControllerProvider);
    final ids = widget.visible
        ? tabs.map((tab) => tab.activeSessionId).toSet()
        : <String>{};
    for (final id in _watches.keys.toList()) {
      if (!ids.contains(id) ||
          !identical(_watches[id]!.viewport, runtime.existingViewportFor(id))) {
        final watch = _watches.remove(id)!;
        watch.viewport.removeListener(watch.listener);
        _alternate.remove(id);
      }
    }
    for (final id in ids) {
      if (_watches.containsKey(id)) continue;
      final viewport = runtime.existingViewportFor(id);
      if (viewport == null) continue;
      _alternate[id] = viewport.frame.modes.alternateScreen;
      void changed() {
        final alternate = viewport.frame.modes.alternateScreen;
        // Output frames may arrive many times per second. Only buffer changes
        // invalidate the sidebar; elapsed times use the one-second timer.
        if (mounted && _alternate[id] != alternate) {
          setState(() => _alternate[id] = alternate);
        }
      }

      viewport.addListener(changed);
      _watches[id] = (viewport: viewport, listener: changed);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    for (final watch in _watches.values) {
      watch.viewport.removeListener(watch.listener);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(sessionControllerProvider.select((s) => s.tabs));
    _syncViewports(tabs);
    final palette = context.appTheme;
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final now = ref.read(sessionCommandClockProvider)();
    final rowText = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.25,
    );
    final groupText = rowText?.copyWith(
      fontSize: 12,
      color: colors.onSurfaceVariant,
    );
    final rowHeight = 32.0 * MediaQuery.textScalerOf(context).scale(14) / 14;
    final sections = <SessionSidebarCategory, List<TerminalTab>>{
      for (final category in SessionSidebarCategory.values) category: [],
    };
    for (final tab in tabs) {
      sections[sessionSidebarCategory(
            tab,
            alternateScreen: _alternate[tab.activeSessionId] ?? false,
            now: now,
          )]!
          .add(tab);
    }
    String directory(TerminalTab tab) {
      final metadata = tab.activePane.shellIntegration;
      var path = metadata.currentDirectory?.trim();
      if (path == null || path.isEmpty) return l10n.sessionUnknownDirectory;
      final home = Platform.environment['HOME'];
      if (metadata.sshHost == null && home != null && home.isNotEmpty) {
        if (path == home) {
          path = '~';
        } else if (path.startsWith('$home/')) {
          path = '~${path.substring(home.length)}';
        }
      }
      final host = metadata.sshHost;
      return host == null || host.isEmpty
          ? path
          : '${metadata.sshUser ?? metadata.username ?? ''}@$host:$path';
    }

    final rows = <Widget>[];
    void header(
      String id,
      String label, {
      int? count,
      int depth = 0,
      bool pathLabel = false,
      bool section = false,
    }) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            top: section && rows.isNotEmpty
                ? palette.spacing.md
                : palette.spacing.xs,
          ),
          child: ListTile(
            key: ValueKey('session-group-$id'),
            dense: true,
            minTileHeight: rowHeight,
            minVerticalPadding: 0,
            minLeadingWidth: 18,
            horizontalTitleGap: palette.spacing.sm,
            contentPadding: EdgeInsets.only(
              left:
                  palette.spacing.sm + math.min(depth, 5) * palette.spacing.sm,
              right: palette.spacing.sm,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Tooltip(
                    message: label,
                    child: pathLabel
                        ? _SessionPathLabel(path: label, style: rowText)
                        : Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: section ? groupText : rowText,
                          ),
                  ),
                ),
                if (count != null) ...[
                  SizedBox(width: palette.spacing.sm),
                  Text('$count', style: groupText),
                ],
              ],
            ),
            trailing: Icon(
              _collapsed.contains(id) ? Icons.chevron_right : Icons.expand_more,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
            onTap: () => setState(() {
              if (!_collapsed.add(id)) _collapsed.remove(id);
            }),
          ),
        ),
      );
    }

    void session(
      TerminalTab tab, {
      required String label,
      required int depth,
      bool elapsed = false,
      bool pathLabel = false,
    }) {
      final selected = tab.containsSession(widget.activeSessionId ?? '');
      final started = tab.activePane.shellIntegration.commandStartedAt;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoveredSession = tab.sessionId),
            onExit: (_) => setState(() {
              if (_hoveredSession == tab.sessionId) _hoveredSession = null;
            }),
            child: GestureDetector(
              onSecondaryTapDown: (details) =>
                  widget.onContextMenu(tab, details.globalPosition),
              child: ListTile(
                key: ValueKey('sidebar-session-${tab.sessionId}'),
                dense: true,
                minTileHeight: rowHeight,
                minVerticalPadding: 0,
                minLeadingWidth: 18,
                horizontalTitleGap: palette.spacing.sm,
                selected: selected,
                selectedColor: colors.onSurface,
                selectedTileColor: palette.selected,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(palette.spacing.sm),
                ),
                contentPadding: EdgeInsets.only(
                  left:
                      palette.spacing.sm +
                      math.min(depth, 5) * palette.spacing.sm,
                  right: palette.spacing.xs,
                ),
                leading: tab.activePane.isExited || widget.hasNewOutput(tab)
                    ? Icon(
                        tab.activePane.isExited
                            ? Icons.stop_circle_outlined
                            : Icons.mark_chat_unread_outlined,
                        size: 14,
                      )
                    : null,
                title: Tooltip(
                  message: '${tab.activePane.title}\n${directory(tab)}',
                  child: pathLabel
                      ? _SessionPathLabel(path: label, style: rowText)
                      : Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: rowText,
                        ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (elapsed && started != null)
                      Text(
                        sessionSidebarElapsed(started, now),
                        style: groupText,
                      ),
                    Visibility(
                      visible: _hoveredSession == tab.sessionId,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      child: IconButton(
                        key: ValueKey('sidebar-close-${tab.sessionId}'),
                        style: ButtonStyle(
                          backgroundColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          overlayColor: WidgetStateProperty.resolveWith(
                            (states) =>
                                states.contains(WidgetState.hovered) ||
                                    states.contains(WidgetState.focused)
                                ? colors.onSurface.withValues(alpha: 0.06)
                                : Colors.transparent,
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.standard,
                          minimumSize: const WidgetStatePropertyAll(
                            Size.square(24),
                          ),
                          maximumSize: const WidgetStatePropertyAll(
                            Size.square(24),
                          ),
                          fixedSize: const WidgetStatePropertyAll(
                            Size.square(24),
                          ),
                          alignment: Alignment.center,
                        ),
                        padding: EdgeInsets.zero,
                        color: colors.onSurfaceVariant,
                        tooltip: l10n.close,
                        onPressed: () => widget.onClose(tab.sessionId),
                        icon: CustomPaint(
                          key: ValueKey('sidebar-close-glyph-${tab.sessionId}'),
                          size: const Size.square(14),
                          painter: _SidebarClosePainter(
                            colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () => widget.onActivate(tab.activeSessionId),
              ),
            ),
          ),
        ),
      );
    }

    for (final category in SessionSidebarCategory.values) {
      final members = sections[category]!;
      if (members.isEmpty) continue;
      final sectionId = category.name;
      header(
        sectionId,
        switch (category) {
          SessionSidebarCategory.interactive => l10n.sessionInteractive,
          SessionSidebarCategory.running => l10n.sessionLongRunning,
          SessionSidebarCategory.directory => l10n.sessionGroupDirectory,
        },
        count: members.length,
        section: true,
      );
      if (_collapsed.contains(sectionId)) continue;
      if (category != SessionSidebarCategory.directory) {
        final commands = <String, List<TerminalTab>>{};
        for (final tab in members) {
          final metadata = tab.activePane.shellIntegration;
          final command = metadata.runningCommand?.trim();
          final label = command == null || command.isEmpty
              ? l10n.sessionUnknownCommand
              : command;
          commands.putIfAbsent(label, () => []).add(tab);
        }
        final names = commands.keys.toList()..sort();
        for (final command in names) {
          final group = commands[command]!;
          final id = '$sectionId:$command';
          header(id, command, count: group.length);
          if (_collapsed.contains(id)) continue;
          final sorted = [...group]
            ..sort((a, b) => directory(a).compareTo(directory(b)));
          final seen = <String, int>{};
          for (final tab in sorted) {
            final path = directory(tab);
            final number = seen.update(path, (v) => v + 1, ifAbsent: () => 1);
            final duplicates =
                sorted.where((t) => directory(t) == path).length > 1;
            session(
              tab,
              label: duplicates ? '$path · $number' : path,
              depth: 1,
              pathLabel: true,
              elapsed: category == SessionSidebarCategory.running,
            );
          }
        }
      } else {
        final root = _SessionGroupNode('', '');
        for (final tab in members) {
          final path = directory(tab);
          final segments = [
            if (path.startsWith('/')) '/',
            ...path.split('/').where((s) => s.isNotEmpty),
          ];
          var node = root;
          for (final segment in segments) {
            final key = '${node.path}/${segment.length}:$segment';
            node = node.children.putIfAbsent(
              segment,
              () => _SessionGroupNode(segment, key),
            );
          }
          node.tabs.add(tab);
        }
        void visit(_SessionGroupNode initial, int depth) {
          var node = initial;
          var label = node.label;
          while (node.tabs.isEmpty && node.children.length == 1) {
            node = node.children.values.single;
            label = label.endsWith('/')
                ? '$label${node.label}'
                : '$label/${node.label}';
          }
          final id = 'directory:${node.path}';
          header(id, label, depth: depth, pathLabel: true);
          if (_collapsed.contains(id)) return;
          for (final tab in node.tabs) {
            session(tab, label: tab.activePane.title, depth: depth + 1);
          }
          final children = node.children.values.toList()
            ..sort((a, b) => a.label.compareTo(b.label));
          for (final child in children) {
            visit(child, depth + 1);
          }
        }

        final roots = root.children.values.toList()
          ..sort((a, b) => a.label.compareTo(b.label));
        for (final child in roots) {
          visit(child, 0);
        }
      }
    }
    return Material(
      key: const Key('session-sidebar'),
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            key: const Key('session-sidebar-header'),
            padding: EdgeInsets.symmetric(
              horizontal: palette.spacing.sm * 2,
              vertical: palette.spacing.xs,
            ),
            child: SizedBox(
              height: 32,
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.sessionSidebarTitle, style: rowText),
                  ),
                  _buildChromeIconButton(
                    key: const Key('session-sidebar-new'),
                    tooltip: l10n.newTab,
                    onPressed: widget.onNew,
                    iconSize: 18,
                    hoverBackgroundColor: colors.surfaceContainerHighest,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(l10n.sessionSidebarEmpty))
                : ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: palette.spacing.sm + palette.spacing.xs,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, index) => rows[index],
                  ),
          ),
        ],
      ),
    );
  }
}

// Preserve both path origin and distinguishing suffix in narrow sidebars.
class _SessionPathLabel extends StatelessWidget {
  const _SessionPathLabel({required this.path, required this.style});

  final String path;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        );
        bool fits(String value) {
          painter.text = TextSpan(text: value, style: effectiveStyle);
          painter.layout();
          return painter.width <= constraints.maxWidth;
        }

        var display = path;
        if (!fits(path)) {
          final characters = path.runes.toList();
          String shortened(int count) {
            final prefix = (count / 3).ceil();
            final suffix = count - prefix;
            return '${String.fromCharCodes(characters.take(prefix))}…${String.fromCharCodes(characters.skip(characters.length - suffix))}';
          }

          var low = 0;
          var high = characters.length;
          while (low < high) {
            final middle = (low + high + 1) ~/ 2;
            if (fits(shortened(middle))) {
              low = middle;
            } else {
              high = middle - 1;
            }
          }
          display = shortened(low);
        }
        painter.dispose();
        return Text(
          display,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.clip,
          semanticsLabel: path,
        );
      },
    );
  }
}

// Draw the cross symmetrically instead of relying on font glyph bearings.
class _SidebarClosePainter extends CustomPainter {
  const _SidebarClosePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.28;
    canvas.drawLine(
      center + Offset(-radius, -radius),
      center + Offset(radius, radius),
      paint,
    );
    canvas.drawLine(
      center + Offset(-radius, radius),
      center + Offset(radius, -radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SidebarClosePainter oldDelegate) =>
      color != oldDelegate.color;
}
