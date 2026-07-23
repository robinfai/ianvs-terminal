part of 'shell_screen.dart';

class _ShellCommandMenu extends StatefulWidget {
  const _ShellCommandMenu({
    required this.launcherShortcutLabel,
    required this.newTabShortcutLabel,
    required this.sessionPasteShortcutLabel,
    required this.instantReplayShortcutLabel,
    required this.searchShortcutLabel,
    required this.hasDefaultProfile,
    required this.hasActiveSession,
    required this.canReopenClosedTab,
    required this.isActiveSessionReadOnly,
    required this.isActiveSessionRecording,
    required this.isActiveRecordingPendingSave,
    required this.isActiveRecordingBusy,
    required this.notificationsBlockedBySystem,
    required this.commandFinishedNotificationsEnabled,
    required this.activityMonitorEnabled,
  });

  final String launcherShortcutLabel;
  final String newTabShortcutLabel;
  final String sessionPasteShortcutLabel;
  final String instantReplayShortcutLabel;
  final String searchShortcutLabel;
  final bool hasDefaultProfile;
  final bool hasActiveSession;
  final bool canReopenClosedTab;
  final bool isActiveSessionReadOnly;
  final bool isActiveSessionRecording;
  final bool isActiveRecordingPendingSave;
  final bool isActiveRecordingBusy;
  final bool notificationsBlockedBySystem;
  final bool commandFinishedNotificationsEnabled;
  final bool activityMonitorEnabled;

  @override
  State<_ShellCommandMenu> createState() => _ShellCommandMenuState();
}

class _ShellCommandMenuState extends State<_ShellCommandMenu> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final maxMenuHeight = (MediaQuery.sizeOf(context).height - 24)
        .clamp(320.0, 520.0)
        .toDouble();
    final launcherShortcutLabel = widget.launcherShortcutLabel;
    final newTabShortcutLabel = widget.newTabShortcutLabel;
    final sessionPasteShortcutLabel = widget.sessionPasteShortcutLabel;
    final instantReplayShortcutLabel = widget.instantReplayShortcutLabel;
    final searchShortcutLabel = widget.searchShortcutLabel;
    final hasDefaultProfile = widget.hasDefaultProfile;
    final hasActiveSession = widget.hasActiveSession;
    final canReopenClosedTab = widget.canReopenClosedTab;
    final isActiveSessionReadOnly = widget.isActiveSessionReadOnly;
    final isActiveSessionRecording = widget.isActiveSessionRecording;
    final isActiveRecordingPendingSave = widget.isActiveRecordingPendingSave;
    final isActiveRecordingBusy = widget.isActiveRecordingBusy;
    final notificationsBlockedBySystem = widget.notificationsBlockedBySystem;
    final commandFinishedNotificationsEnabled =
        widget.commandFinishedNotificationsEnabled;
    final activityMonitorEnabled = widget.activityMonitorEnabled;

    Widget sectionLabel(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.textSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.24,
            ),
          ),
        ),
      );
    }

    const activeSessionRequired = 'Open a terminal tab first.';
    const defaultProfileRequired = 'No default profile is configured.';
    const closedTabRequired = 'No recently closed tab is available.';
    const readOnlySendRequired = 'Disable read-only mode to send text.';

    var commandTileTraversalOrder = 1.0;

    Widget commandTile({
      Key? key,
      required TerminalActionId actionId,
      required IconData icon,
      required String title,
      required String subtitle,
      required bool enabled,
      String? disabledReason,
      int subtitleMaxLines = 2,
      String? shortcutLabel,
      VoidCallback? onTap,
    }) {
      if (!_commandMenuActionMatchesQuery(
        actionId,
        _query,
        title: title,
        subtitle: subtitle,
      )) {
        return const SizedBox.shrink();
      }

      final traversalOrder = commandTileTraversalOrder;
      commandTileTraversalOrder += 1;
      return FocusTraversalOrder(
        order: NumericFocusOrder(traversalOrder),
        child: _ShellCommandTile(
          key: key,
          icon: icon,
          title: title,
          subtitle: subtitle,
          shortcutLabel: shortcutLabel,
          enabled: enabled,
          disabledReason: disabledReason,
          subtitleMaxLines: subtitleMaxLines,
          onTap: onTap,
        ),
      );
    }

    return Material(
      key: const Key('shell-command-menu-overlay'),
      color: Colors.transparent,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400, maxHeight: maxMenuHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.overlay,
              borderRadius: BorderRadius.circular(palette.radius.xl),
              border: Border.all(color: palette.borderStrong),
              boxShadow: palette.elevation.dialog,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 1, 1, 1),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Command palette',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: palette.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(1000),
                              child: _buildSheetCloseButton(
                                tooltip: 'Close command palette',
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 3, 6, 5),
                        child: MergeSemantics(
                          child: Semantics(
                            label: 'Search actions',
                            textField: true,
                            child: FocusTraversalOrder(
                              order: const NumericFocusOrder(0),
                              child: TextField(
                                key: const Key('shell-command-search-field'),
                                autofocus: true,
                                textInputAction: TextInputAction.search,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: palette.textPrimary),
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  labelText: 'Search actions',
                                  hintText: 'Type an action and press Enter',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      palette.radius.lg,
                                    ),
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _query = value;
                                  });
                                },
                                onSubmitted: (query) {
                                  final action = _commandMenuActionForQuery(
                                    query,
                                  );
                                  if (action == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'No action matches "$query".',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.of(context).pop(action);
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      sectionLabel('Quick actions'),
                      commandTile(
                        key: const Key('shell-search-scrollback-top'),
                        actionId: TerminalActionId.search,
                        icon: Icons.search_rounded,
                        title: 'Search terminal output',
                        subtitle:
                            'Top action • Open in-terminal search for the active pane.',
                        shortcutLabel: searchShortcutLabel,
                        enabled: hasActiveSession,
                        disabledReason: activeSessionRequired,
                        onTap: () =>
                            Navigator.of(context).pop(TerminalActionId.search),
                      ),
                      commandTile(
                        key: const Key('shell-top-paste-clipboard'),
                        actionId: TerminalActionId.paste,
                        icon: Icons.content_paste_rounded,
                        title: 'Paste clipboard',
                        subtitle:
                            'Top action • Paste clipboard into the shell.',
                        shortcutLabel: sessionPasteShortcutLabel,
                        enabled: hasActiveSession && !isActiveSessionReadOnly,
                        disabledReason: hasActiveSession
                            ? readOnlySendRequired
                            : activeSessionRequired,
                        onTap: () =>
                            Navigator.of(context).pop(TerminalActionId.paste),
                      ),
                      commandTile(
                        key: const Key('shell-top-new-tab'),
                        actionId: TerminalActionId.newTab,
                        icon: Icons.add_box_outlined,
                        title: 'New tab',
                        subtitle:
                            'Top action • Open the default shell profile.',
                        shortcutLabel: newTabShortcutLabel,
                        enabled: hasDefaultProfile,
                        disabledReason: defaultProfileRequired,
                        onTap: () =>
                            Navigator.of(context).pop(TerminalActionId.newTab),
                      ),
                      commandTile(
                        key: const Key('shell-top-toolbelt'),
                        actionId: TerminalActionId.toolbelt,
                        icon: Icons.view_sidebar_rounded,
                        title: 'Toolbelt',
                        subtitle:
                            'Top action • Open terminal tools for this pane.',
                        enabled: hasActiveSession,
                        disabledReason: activeSessionRequired,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.toolbelt),
                      ),
                      sectionLabel('App actions'),
                      commandTile(
                        key: const Key('shell-command-defaults'),
                        actionId: TerminalActionId.defaults,
                        icon: Icons.tune_rounded,
                        title: 'Defaults & appearance',
                        subtitle:
                            'App action • Pick the default profile and theme.',
                        enabled: true,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.defaults),
                      ),
                      commandTile(
                        key: const Key('shell-reopen-closed-tab'),
                        actionId: TerminalActionId.reopenClosedTab,
                        icon: Icons.restore_rounded,
                        title: 'Reopen closed tab',
                        subtitle:
                            'App action • Recreate the most recently closed tab.',
                        enabled: canReopenClosedTab,
                        disabledReason: closedTabRequired,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.reopenClosedTab),
                      ),
                      commandTile(
                        key: const Key('shell-theme-picker'),
                        actionId: TerminalActionId.openThemePicker,
                        icon: Icons.palette_rounded,
                        title: 'Terminal color presets',
                        subtitle:
                            'App action • Open Defaults & appearance to choose terminal colors.',
                        enabled: true,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.openThemePicker),
                      ),
                      commandTile(
                        key: const Key('shell-toggle-command-finished-notify'),
                        actionId: TerminalActionId.toggleCommandFinishedNotify,
                        icon: Icons.notifications_active_rounded,
                        title:
                            '${commandFinishedNotificationsEnabled ? 'Disable' : 'Enable'} command-finished notifications',
                        subtitle: notificationsBlockedBySystem
                            ? 'App action • Toggle shell hook completion alerts. macOS notifications are currently blocked in System Settings.'
                            : 'App action • Toggle shell hook completion alerts.',
                        subtitleMaxLines: notificationsBlockedBySystem ? 2 : 1,
                        enabled: true,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.toggleCommandFinishedNotify),
                      ),
                      commandTile(
                        key: const Key('shell-toggle-activity-monitor'),
                        actionId: TerminalActionId.toggleActivityMonitor,
                        icon: Icons.notification_important_rounded,
                        title:
                            '${activityMonitorEnabled ? 'Disable' : 'Enable'} activity monitor',
                        subtitle: notificationsBlockedBySystem
                            ? 'App action • Toggle inactive-session activity alerts. macOS notifications are currently blocked in System Settings.'
                            : 'App action • Toggle inactive-session activity alerts.',
                        subtitleMaxLines: notificationsBlockedBySystem ? 2 : 1,
                        enabled: true,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.toggleActivityMonitor),
                      ),
                      commandTile(
                        key: const Key('shell-command-profiles'),
                        actionId: TerminalActionId.profiles,
                        icon: Icons.folder_open_rounded,
                        title: 'Profiles…',
                        subtitle: 'App action • Open or edit shell profiles.',
                        enabled: true,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.profiles),
                      ),
                      sectionLabel('Session actions'),
                      if (!hasActiveSession)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Requires an active shell session.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        ),
                      commandTile(
                        key: const Key('shell-toggle-read-only'),
                        actionId: TerminalActionId.toggleReadOnly,
                        icon: Icons.lock_outline_rounded,
                        title:
                            '${isActiveSessionReadOnly ? 'Disable' : 'Enable'} read-only mode',
                        subtitle:
                            'Session action • Block terminal input for this pane.',
                        enabled: hasActiveSession,
                        disabledReason: activeSessionRequired,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.toggleReadOnly),
                      ),
                      commandTile(
                        key: const Key('shell-toggle-session-recording'),
                        actionId: TerminalActionId.toggleSessionRecording,
                        icon: isActiveSessionRecording
                            ? Icons.stop_circle_outlined
                            : isActiveRecordingPendingSave
                            ? Icons.save_outlined
                            : Icons.fiber_manual_record_outlined,
                        title: isActiveSessionRecording
                            ? 'Stop & save recording'
                            : isActiveRecordingPendingSave
                            ? 'Retry saving recording'
                            : 'Start recording',
                        subtitle:
                            'Session action • Capture PTY output and lifecycle events. Input bytes are redacted.',
                        subtitleMaxLines: 2,
                        enabled: hasActiveSession && !isActiveRecordingBusy,
                        disabledReason: hasActiveSession
                            ? 'A recording operation is already in progress.'
                            : activeSessionRequired,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.toggleSessionRecording),
                      ),
                      commandTile(
                        key: const Key('shell-clear-scrollback'),
                        actionId: TerminalActionId.clearScrollback,
                        icon: Icons.clear_all_rounded,
                        title: 'Clear scrollback',
                        subtitle:
                            'Session action • Clear local scrollback when supported.',
                        enabled: hasActiveSession,
                        disabledReason: activeSessionRequired,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.clearScrollback),
                      ),
                      commandTile(
                        key: const Key('shell-export-scrollback'),
                        actionId: TerminalActionId.exportScrollback,
                        icon: Icons.ios_share_rounded,
                        title: 'Export scrollback',
                        subtitle:
                            'Session action • Save a terminal text snapshot to Application Support.',
                        enabled: hasActiveSession,
                        disabledReason: activeSessionRequired,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.exportScrollback),
                      ),
                      commandTile(
                        key: const Key('shell-export-diagnostics'),
                        actionId: TerminalActionId.exportDiagnostics,
                        icon: Icons.bug_report_rounded,
                        title: 'Export diagnostics',
                        subtitle:
                            'Session action • Save a local resource evidence bundle.',
                        enabled: hasActiveSession,
                        disabledReason: activeSessionRequired,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.exportDiagnostics),
                      ),
                      sectionLabel('Shell tools'),
                      commandTile(
                        key: const Key('shell-instant-replay'),
                        actionId: TerminalActionId.instantReplay,
                        icon: Icons.replay_rounded,
                        title: 'Instant replay',
                        subtitle:
                            'Shell tool • Recover text from recent terminal frames.',
                        shortcutLabel: instantReplayShortcutLabel,
                        enabled: hasActiveSession,
                        disabledReason: activeSessionRequired,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.instantReplay),
                      ),
                      commandTile(
                        key: const Key('shell-global-search'),
                        actionId: TerminalActionId.globalSearch,
                        icon: Icons.manage_search_rounded,
                        title: 'Global search',
                        subtitle: 'Shell tool • Search all tabs at once.',
                        enabled: hasActiveSession,
                        disabledReason: activeSessionRequired,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(TerminalActionId.globalSearch),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.keyboard_command_key_rounded,
                              size: 16,
                              color: palette.textSubtle,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Open command palette with $launcherShortcutLabel',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: palette.textSubtle),
                              ),
                            ),
                          ],
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
    );
  }
}

const _commandMenuActionSearchEntries = <MapEntry<String, TerminalActionId>>[
  MapEntry('new tab open default shell profile', TerminalActionId.newTab),
  MapEntry(
    'defaults appearance default profile theme',
    TerminalActionId.defaults,
  ),
  MapEntry('reopen closed tab restore tab', TerminalActionId.reopenClosedTab),
  MapEntry(
    'theme picker terminal color presets appearance defaults',
    TerminalActionId.openThemePicker,
  ),
  MapEntry('export scrollback save output', TerminalActionId.exportScrollback),
  MapEntry(
    'export diagnostics resource cpu memory evidence bundle',
    TerminalActionId.exportDiagnostics,
  ),
  MapEntry(
    'command finished notifications shell hook completion alerts',
    TerminalActionId.toggleCommandFinishedNotify,
  ),
  MapEntry(
    'activity monitor inactive session alerts',
    TerminalActionId.toggleActivityMonitor,
  ),
  MapEntry('profiles edit shell profiles', TerminalActionId.profiles),
  MapEntry(
    'read only readonly lock block input',
    TerminalActionId.toggleReadOnly,
  ),
  MapEntry(
    'record recording capture pty output redact input save',
    TerminalActionId.toggleSessionRecording,
  ),
  MapEntry('clear scrollback clear output', TerminalActionId.clearScrollback),
  MapEntry('paste clipboard', TerminalActionId.paste),
  MapEntry('toolbelt terminal tools sidebar', TerminalActionId.toolbelt),
  MapEntry(
    'instant replay recent terminal frames',
    TerminalActionId.instantReplay,
  ),
  MapEntry('search scrollback find local output', TerminalActionId.search),
  MapEntry('global search workspace all tabs', TerminalActionId.globalSearch),
];

TerminalActionId? _commandMenuActionForQuery(String query) {
  final normalized = _normalizeCommandMenuQuery(query);
  if (normalized.isEmpty) {
    return null;
  }
  for (final entry in _commandMenuActionSearchEntries) {
    if (_commandMenuQueryMatches(entry.key, normalized)) {
      return entry.value;
    }
  }
  return null;
}

bool _commandMenuActionMatchesQuery(
  TerminalActionId actionId,
  String query, {
  required String title,
  required String subtitle,
}) {
  final normalized = _normalizeCommandMenuQuery(query);
  if (normalized.isEmpty) {
    return true;
  }

  final fallback = _normalizeCommandMenuQuery(
    '$title $subtitle ${actionId.name}',
  );
  if (_commandMenuQueryMatches(fallback, normalized)) {
    return true;
  }

  return _commandMenuActionSearchEntries
      .where((entry) => entry.value == actionId)
      .map((entry) => entry.key)
      .any((entry) => _commandMenuQueryMatches(entry, normalized));
}

bool _commandMenuQueryMatches(String candidate, String query) {
  final normalizedCandidate = _normalizeCommandMenuQuery(candidate);
  final normalizedQuery = _normalizeCommandMenuQuery(query);
  if (normalizedQuery.isEmpty) {
    return true;
  }
  if (normalizedCandidate.isEmpty) {
    return false;
  }
  if (normalizedCandidate.contains(normalizedQuery) ||
      normalizedQuery.contains(normalizedCandidate)) {
    return true;
  }

  final candidateTokens = normalizedCandidate.split(' ');
  return normalizedQuery
      .split(' ')
      .every(
        (queryToken) => candidateTokens.any(
          (candidateToken) =>
              candidateToken.contains(queryToken) ||
              queryToken.contains(candidateToken),
        ),
      );
}

String _normalizeCommandMenuQuery(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

class _PaneDividerHandle extends StatefulWidget {
  const _PaneDividerHandle({
    super.key,
    required this.direction,
    required this.thickness,
    required this.terminalBackground,
    required this.palette,
    required this.onDragUpdate,
  });

  final Axis direction;
  final double thickness;
  final Color terminalBackground;
  final AppThemeTokens palette;
  final ValueChanged<double> onDragUpdate;

  @override
  State<_PaneDividerHandle> createState() => _PaneDividerHandleState();
}

class _PaneDividerHandleState extends State<_PaneDividerHandle> {
  bool _hovered = false;
  bool _dragging = false;

  bool get _active => _hovered || _dragging;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() {
      _hovered = value;
    });
  }

  void _setDragging(bool value) {
    if (_dragging == value) {
      return;
    }
    setState(() {
      _dragging = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.direction == Axis.horizontal;
    final background = _active
        ? widget.palette.accent.withValues(alpha: _dragging ? 0.16 : 0.09)
        : widget.terminalBackground;
    final lineColor = _active
        ? widget.palette.accent.withValues(alpha: _dragging ? 0.86 : 0.68)
        : widget.palette.borderStrong.withValues(alpha: 0.72);
    final lineThickness = _active ? 2.0 : 1.0;

    return SizedBox(
      width: horizontal ? widget.thickness : double.infinity,
      height: horizontal ? double.infinity : widget.thickness,
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Tooltip(
          message: horizontal
              ? 'Drag to resize panes horizontally'
              : 'Drag to resize panes vertically',
          child: Semantics(
            label: horizontal
                ? 'Drag to resize panes horizontally'
                : 'Drag to resize panes vertically',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: horizontal
                  ? (_) => _setDragging(true)
                  : null,
              onHorizontalDragEnd: horizontal
                  ? (_) => _setDragging(false)
                  : null,
              onHorizontalDragCancel: horizontal
                  ? () => _setDragging(false)
                  : null,
              onHorizontalDragUpdate: horizontal
                  ? (details) => widget.onDragUpdate(details.delta.dx)
                  : null,
              onVerticalDragStart: horizontal
                  ? null
                  : (_) => _setDragging(true),
              onVerticalDragEnd: horizontal ? null : (_) => _setDragging(false),
              onVerticalDragCancel: horizontal
                  ? null
                  : () => _setDragging(false),
              onVerticalDragUpdate: horizontal
                  ? null
                  : (details) => widget.onDragUpdate(details.delta.dy),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOutCubic,
                color: background,
                child: Align(
                  alignment: Alignment.center,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.easeOutCubic,
                    width: horizontal ? lineThickness : double.infinity,
                    height: horizontal ? double.infinity : lineThickness,
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.circular(2),
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

class _ShellCommandTile extends StatelessWidget {
  const _ShellCommandTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.disabledReason,
    this.subtitleMaxLines = 1,
    this.shortcutLabel,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String? disabledReason;
  final int subtitleMaxLines;
  final String? shortcutLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final effectiveSubtitle = enabled
        ? subtitle
        : 'Unavailable: ${disabledReason ?? 'Unavailable in the current context.'}';
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(palette.radius.lg),
      ),
      hoverColor: _shellTileHoverColor(palette),
      focusColor: _shellTileFocusColor(palette),
      minLeadingWidth: 26,
      horizontalTitleGap: 8,
      leading: Icon(
        icon,
        size: 18,
        color: enabled ? palette.accent : palette.textSubtle,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: enabled ? palette.textPrimary : palette.textSubtle,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        effectiveSubtitle,
        maxLines: enabled ? subtitleMaxLines : 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      trailing: shortcutLabel == null
          ? null
          : Text(
              shortcutLabel!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: enabled ? palette.textMuted : palette.textSubtle,
                fontWeight: FontWeight.w700,
              ),
            ),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}

Color _shellTileHoverColor(AppThemeTokens palette) {
  return palette.selected.withValues(alpha: 0.44);
}

Color _shellTileFocusColor(AppThemeTokens palette) {
  return palette.selected.withValues(alpha: 0.56);
}
