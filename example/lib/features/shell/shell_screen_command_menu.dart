part of 'shell_screen.dart';

class _ShellCommandMenuHotkeyStatus extends StatefulWidget {
  const _ShellCommandMenuHotkeyStatus({
    required this.statusFuture,
    required this.builder,
  });

  final Future<HotkeyWindowStatus?> statusFuture;
  final Widget Function(HotkeyWindowStatus? status) builder;

  @override
  State<_ShellCommandMenuHotkeyStatus> createState() =>
      _ShellCommandMenuHotkeyStatusState();
}

class _ShellCommandMenuHotkeyStatusState
    extends State<_ShellCommandMenuHotkeyStatus> {
  HotkeyWindowStatus? _status;

  @override
  void initState() {
    super.initState();
    widget.statusFuture.then((status) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_status);
  }
}

class _ShellCommandMenu extends StatefulWidget {
  const _ShellCommandMenu({
    required this.launcherShortcutLabel,
    required this.newTabShortcutLabel,
    required this.hotkeyWindowShortcutLabel,
    required this.autocompleteShortcutLabel,
    required this.copyModeShortcutLabel,
    required this.sessionCopyShortcutLabel,
    required this.sessionPasteShortcutLabel,
    required this.pasteHistoryShortcutLabel,
    required this.instantReplayShortcutLabel,
    required this.searchShortcutLabel,
    required this.hasDefaultProfile,
    required this.hasActiveSession,
    required this.activePaneZoomed,
    required this.canReopenClosedTab,
    required this.splitRightUnavailableReason,
    required this.splitDownUnavailableReason,
    required this.hotkeyWindowStatus,
    required this.isActiveSessionReadOnly,
    required this.notificationsBlockedBySystem,
    required this.commandFinishedNotificationsEnabled,
    required this.bellNotificationsEnabled,
    required this.activityMonitorEnabled,
    required this.canSelectCommandOutput,
  });

  final String launcherShortcutLabel;
  final String newTabShortcutLabel;
  final String hotkeyWindowShortcutLabel;
  final String autocompleteShortcutLabel;
  final String copyModeShortcutLabel;
  final String sessionCopyShortcutLabel;
  final String sessionPasteShortcutLabel;
  final String pasteHistoryShortcutLabel;
  final String instantReplayShortcutLabel;
  final String searchShortcutLabel;
  final bool hasDefaultProfile;
  final bool hasActiveSession;
  final bool activePaneZoomed;
  final bool canReopenClosedTab;
  final String? splitRightUnavailableReason;
  final String? splitDownUnavailableReason;
  final HotkeyWindowStatus? hotkeyWindowStatus;
  final bool isActiveSessionReadOnly;
  final bool notificationsBlockedBySystem;
  final bool commandFinishedNotificationsEnabled;
  final bool bellNotificationsEnabled;
  final bool activityMonitorEnabled;
  final bool canSelectCommandOutput;

  @override
  State<_ShellCommandMenu> createState() => _ShellCommandMenuState();
}

class _ShellCommandMenuState extends State<_ShellCommandMenu> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final maxMenuHeight = (MediaQuery.sizeOf(context).height - 24)
        .clamp(360.0, 560.0)
        .toDouble();
    final launcherShortcutLabel = widget.launcherShortcutLabel;
    final newTabShortcutLabel = widget.newTabShortcutLabel;
    final hotkeyWindowShortcutLabel = widget.hotkeyWindowShortcutLabel;
    final autocompleteShortcutLabel = widget.autocompleteShortcutLabel;
    final copyModeShortcutLabel = widget.copyModeShortcutLabel;
    final sessionCopyShortcutLabel = widget.sessionCopyShortcutLabel;
    final sessionPasteShortcutLabel = widget.sessionPasteShortcutLabel;
    final pasteHistoryShortcutLabel = widget.pasteHistoryShortcutLabel;
    final instantReplayShortcutLabel = widget.instantReplayShortcutLabel;
    final searchShortcutLabel = widget.searchShortcutLabel;
    final hasDefaultProfile = widget.hasDefaultProfile;
    final hasActiveSession = widget.hasActiveSession;
    final activePaneZoomed = widget.activePaneZoomed;
    final canReopenClosedTab = widget.canReopenClosedTab;
    final splitRightUnavailableReason = widget.splitRightUnavailableReason;
    final splitDownUnavailableReason = widget.splitDownUnavailableReason;
    final hotkeyWindowStatus = widget.hotkeyWindowStatus;
    final isActiveSessionReadOnly = widget.isActiveSessionReadOnly;
    final notificationsBlockedBySystem = widget.notificationsBlockedBySystem;
    final commandFinishedNotificationsEnabled =
        widget.commandFinishedNotificationsEnabled;
    final bellNotificationsEnabled = widget.bellNotificationsEnabled;
    final activityMonitorEnabled = widget.activityMonitorEnabled;
    final canSelectCommandOutput = widget.canSelectCommandOutput;

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

    String? hotkeyWindowUnavailableReason() {
      final status = hotkeyWindowStatus;
      if (status == null || status.registered) {
        return null;
      }
      final details = <String>[
        'Hotkey window is unavailable.',
        'Shortcut: ${status.shortcut}.',
        if (status.errorCode != null) 'Error: ${status.errorCode}.',
      ];
      return details.join(' ');
    }

    String selectCommandOutputUnavailableReason() {
      if (!hasActiveSession) {
        return activeSessionRequired;
      }
      return 'No prompt-marked command output is available yet.';
    }

    Widget commandTile({
      Key? key,
      required TerminalActionId actionId,
      required IconData icon,
      required String title,
      required String subtitle,
      required bool enabled,
      String? disabledReason,
      int subtitleMaxLines = 1,
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

      return _ShellCommandTile(
        key: key,
        icon: icon,
        title: title,
        subtitle: subtitle,
        shortcutLabel: shortcutLabel,
        enabled: enabled,
        disabledReason: disabledReason,
        subtitleMaxLines: subtitleMaxLines,
        onTap: onTap,
      );
    }

    return Material(
      key: const Key('shell-command-menu-overlay'),
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340, maxHeight: maxMenuHeight),
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
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Top actions',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          _buildSheetCloseButton(
                            tooltip: 'Close actions',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                      child: MergeSemantics(
                        child: Semantics(
                          label: 'Search actions',
                          textField: true,
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
                              helperText:
                                  'Examples: profile, paste history, read-only',
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
                              final action = _commandMenuActionForQuery(query);
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
                      key: const Key('shell-open-action-search'),
                      actionId: TerminalActionId.openActionSearch,
                      icon: Icons.manage_search_rounded,
                      title: 'Action search',
                      subtitle:
                          'Top action • Search actions and saved commands.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.openActionSearch),
                    ),
                    sectionLabel('App actions'),
                    commandTile(
                      key: const Key('shell-new-tab'),
                      actionId: TerminalActionId.newTab,
                      icon: Icons.add_box_outlined,
                      title: 'New tab',
                      subtitle: 'App action • Open the default shell profile.',
                      shortcutLabel: newTabShortcutLabel,
                      enabled: hasDefaultProfile,
                      disabledReason: defaultProfileRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.newTab),
                    ),
                    commandTile(
                      key: const Key('shell-command-defaults'),
                      actionId: TerminalActionId.defaults,
                      icon: Icons.tune_rounded,
                      title: 'Defaults & appearance',
                      subtitle:
                          'App action • Pick the default profile and theme.',
                      enabled: true,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.defaults),
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
                      key: const Key('shell-toolbelt'),
                      actionId: TerminalActionId.toolbelt,
                      icon: Icons.view_sidebar_rounded,
                      title: 'Toolbelt',
                      subtitle:
                          'App action • Keep terminal tools in a sidebar.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.toolbelt),
                    ),
                    commandTile(
                      key: const Key('shell-split-right'),
                      actionId: TerminalActionId.splitRight,
                      icon: Icons.vertical_split_rounded,
                      title: 'Split right',
                      subtitle: 'Session action • Add a pane to the right.',
                      enabled:
                          hasDefaultProfile &&
                          hasActiveSession &&
                          splitRightUnavailableReason == null,
                      disabledReason: !hasDefaultProfile
                          ? defaultProfileRequired
                          : !hasActiveSession
                          ? activeSessionRequired
                          : splitRightUnavailableReason,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.splitRight),
                    ),
                    commandTile(
                      key: const Key('shell-split-down'),
                      actionId: TerminalActionId.splitDown,
                      icon: Icons.horizontal_split_rounded,
                      title: 'Split down',
                      subtitle: 'Session action • Add a pane below.',
                      enabled:
                          hasDefaultProfile &&
                          hasActiveSession &&
                          splitDownUnavailableReason == null,
                      disabledReason: !hasDefaultProfile
                          ? defaultProfileRequired
                          : !hasActiveSession
                          ? activeSessionRequired
                          : splitDownUnavailableReason,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.splitDown),
                    ),
                    commandTile(
                      key: const Key('shell-zoom-pane'),
                      actionId: TerminalActionId.zoomPane,
                      icon: Icons.zoom_out_map_rounded,
                      title: activePaneZoomed
                          ? 'Unzoom active pane'
                          : 'Zoom active pane',
                      subtitle: 'Session action • Focus one pane temporarily.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.zoomPane),
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
                      key: const Key('shell-toggle-bell-notify'),
                      actionId: TerminalActionId.toggleBellNotify,
                      icon: Icons.notifications_rounded,
                      title:
                          '${bellNotificationsEnabled ? 'Disable' : 'Enable'} bell notifications',
                      subtitle: notificationsBlockedBySystem
                          ? 'App action • Toggle terminal bell alerts. macOS notifications are currently blocked in System Settings.'
                          : 'App action • Toggle terminal bell alerts.',
                      subtitleMaxLines: notificationsBlockedBySystem ? 2 : 1,
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.toggleBellNotify),
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
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.profiles),
                    ),
                    commandTile(
                      key: const Key('shell-dynamic-profiles'),
                      actionId: TerminalActionId.dynamicProfiles,
                      icon: Icons.data_object_rounded,
                      title: 'Dynamic profiles',
                      subtitle:
                          'App action • Import iTerm-style JSON profiles.',
                      enabled: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.dynamicProfiles),
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
                      actionId: TerminalActionId.copy,
                      icon: Icons.copy_rounded,
                      title: 'Copy selection',
                      subtitle: 'Session action • Copy the current selection.',
                      shortcutLabel: sessionCopyShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.copy),
                    ),
                    commandTile(
                      key: const Key('shell-copy-mode'),
                      actionId: TerminalActionId.copyMode,
                      icon: Icons.select_all_rounded,
                      title: 'Copy mode',
                      subtitle:
                          'Session action • Select terminal text from the keyboard.',
                      shortcutLabel: copyModeShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.copyMode),
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
                    commandTile(
                      key: const Key('shell-annotations'),
                      actionId: TerminalActionId.annotations,
                      icon: Icons.sticky_note_2_rounded,
                      title: 'Annotations',
                      subtitle:
                          'Session action • Attach notes to selected output.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.annotations),
                    ),
                    commandTile(
                      key: const Key('shell-captured-output'),
                      actionId: TerminalActionId.capturedOutput,
                      icon: Icons.outbox_rounded,
                      title: 'Captured output',
                      subtitle:
                          'Session action • Review lines matched by triggers.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.capturedOutput),
                    ),
                    commandTile(
                      key: const Key('shell-paste-clipboard'),
                      actionId: TerminalActionId.paste,
                      icon: Icons.content_paste_rounded,
                      title: 'Paste clipboard',
                      subtitle:
                          'Session action • Paste clipboard into the shell.',
                      shortcutLabel: sessionPasteShortcutLabel,
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.paste),
                    ),
                    commandTile(
                      key: const Key('shell-advanced-paste'),
                      actionId: TerminalActionId.advancedPaste,
                      icon: Icons.assignment_rounded,
                      title: 'Advanced paste',
                      subtitle:
                          'Session action • Edit and transform text before pasting.',
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.advancedPaste),
                    ),
                    commandTile(
                      key: const Key('shell-paste-history'),
                      actionId: TerminalActionId.pasteHistory,
                      icon: Icons.history_rounded,
                      title: 'Paste history',
                      subtitle:
                          'Session action • Revisit recently copied or pasted text.',
                      shortcutLabel: pasteHistoryShortcutLabel,
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.pasteHistory),
                    ),
                    commandTile(
                      key: const Key('shell-integration-utilities'),
                      actionId: TerminalActionId.shellIntegrationUtilities,
                      icon: Icons.integration_instructions_rounded,
                      title: 'Shell integration',
                      subtitle:
                          'Session action • Command history, directories, and marks.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.shellIntegrationUtilities),
                    ),
                    commandTile(
                      key: const Key('shell-select-command-output'),
                      actionId: TerminalActionId.selectCommandOutput,
                      icon: Icons.fact_check_rounded,
                      title: 'Select command output',
                      subtitle:
                          'Session action • Select output between prompt marks.',
                      enabled: hasActiveSession && canSelectCommandOutput,
                      disabledReason: selectCommandOutputUnavailableReason(),
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.selectCommandOutput),
                    ),
                    commandTile(
                      key: const Key('shell-tmux-integration'),
                      actionId: TerminalActionId.tmuxIntegration,
                      icon: Icons.account_tree_rounded,
                      title: 'tmux integration',
                      subtitle:
                          'Session action • Start or drive tmux control mode.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.tmuxIntegration),
                    ),
                    commandTile(
                      key: const Key('shell-coprocess'),
                      actionId: TerminalActionId.coprocess,
                      icon: Icons.hub_rounded,
                      title: 'Coprocess',
                      subtitle:
                          'Session action • Automate replies from terminal output.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.coprocess),
                    ),
                    commandTile(
                      key: const Key('shell-password-manager'),
                      actionId: TerminalActionId.passwordManager,
                      icon: Icons.password_rounded,
                      title: 'Password manager',
                      subtitle:
                          'Session action • Send saved passwords at prompts.',
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.passwordManager),
                    ),
                    commandTile(
                      key: const Key('shell-instant-replay'),
                      actionId: TerminalActionId.instantReplay,
                      icon: Icons.replay_rounded,
                      title: 'Instant replay',
                      subtitle:
                          'Session action • Recover text from recent terminal frames.',
                      shortcutLabel: instantReplayShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.instantReplay),
                    ),
                    commandTile(
                      actionId: TerminalActionId.search,
                      icon: Icons.search_rounded,
                      title: 'Search terminal output',
                      subtitle: 'Session action • Find text in local output.',
                      shortcutLabel: searchShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () =>
                          Navigator.of(context).pop(TerminalActionId.search),
                    ),
                    commandTile(
                      key: const Key('shell-global-search'),
                      actionId: TerminalActionId.globalSearch,
                      icon: Icons.manage_search_rounded,
                      title: 'Global search',
                      subtitle: 'Workspace action • Search all tabs at once.',
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.globalSearch),
                    ),
                    commandTile(
                      key: const Key('shell-autocomplete'),
                      actionId: TerminalActionId.autocomplete,
                      icon: Icons.auto_fix_high_rounded,
                      title: 'Autocomplete',
                      subtitle:
                          'Session action • Complete a word from visible output.',
                      shortcutLabel: autocompleteShortcutLabel,
                      enabled: hasActiveSession,
                      disabledReason: activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.autocomplete),
                    ),
                    commandTile(
                      key: const Key('shell-auto-composer'),
                      actionId: TerminalActionId.autoComposer,
                      icon: Icons.edit_note_rounded,
                      title: 'Auto Composer',
                      subtitle:
                          'Session action • Native command editor with completions.',
                      enabled: hasActiveSession && !isActiveSessionReadOnly,
                      disabledReason: hasActiveSession
                          ? readOnlySendRequired
                          : activeSessionRequired,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.autoComposer),
                    ),
                    commandTile(
                      key: const Key('shell-hotkey-window'),
                      actionId: TerminalActionId.hotkeyWindow,
                      icon: Icons.keyboard_rounded,
                      title: 'Hotkey window',
                      subtitle:
                          'App action • Hide this window. Reopen with $hotkeyWindowShortcutLabel.',
                      shortcutLabel: hotkeyWindowShortcutLabel,
                      enabled: hotkeyWindowUnavailableReason() == null,
                      disabledReason: hotkeyWindowUnavailableReason(),
                      onTap: () => Navigator.of(
                        context,
                      ).pop(TerminalActionId.hotkeyWindow),
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
                              'Open command menu with $launcherShortcutLabel',
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
  MapEntry('toolbelt sidebar terminal tools', TerminalActionId.toolbelt),
  MapEntry('split right vertical pane', TerminalActionId.splitRight),
  MapEntry('split down horizontal pane', TerminalActionId.splitDown),
  MapEntry('zoom active pane unzoom focus', TerminalActionId.zoomPane),
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
    'bell notifications terminal bell alerts',
    TerminalActionId.toggleBellNotify,
  ),
  MapEntry(
    'activity monitor inactive session alerts',
    TerminalActionId.toggleActivityMonitor,
  ),
  MapEntry('profiles edit shell profiles', TerminalActionId.profiles),
  MapEntry(
    'dynamic profiles import json iterm profile',
    TerminalActionId.dynamicProfiles,
  ),
  MapEntry('copy selection', TerminalActionId.copy),
  MapEntry(
    'copy mode select terminal text keyboard',
    TerminalActionId.copyMode,
  ),
  MapEntry(
    'read only readonly lock block input',
    TerminalActionId.toggleReadOnly,
  ),
  MapEntry('clear scrollback clear output', TerminalActionId.clearScrollback),
  MapEntry('annotations notes selected output', TerminalActionId.annotations),
  MapEntry('captured output trigger lines', TerminalActionId.capturedOutput),
  MapEntry('paste clipboard', TerminalActionId.paste),
  MapEntry(
    'advanced paste transform edit paste',
    TerminalActionId.advancedPaste,
  ),
  MapEntry('paste history recent copied pasted', TerminalActionId.pasteHistory),
  MapEntry(
    'shell integration command history directories prompt marks',
    TerminalActionId.shellIntegrationUtilities,
  ),
  MapEntry(
    'select command output prompt marks',
    TerminalActionId.selectCommandOutput,
  ),
  MapEntry('tmux integration control mode', TerminalActionId.tmuxIntegration),
  MapEntry('coprocess automate replies output', TerminalActionId.coprocess),
  MapEntry(
    'password manager saved passwords prompts',
    TerminalActionId.passwordManager,
  ),
  MapEntry(
    'instant replay recent terminal frames',
    TerminalActionId.instantReplay,
  ),
  MapEntry('search scrollback find local output', TerminalActionId.search),
  MapEntry(
    'action search command actions saved commands command center',
    TerminalActionId.openActionSearch,
  ),
  MapEntry('global search workspace all tabs', TerminalActionId.globalSearch),
  MapEntry(
    'autocomplete complete word visible output',
    TerminalActionId.autocomplete,
  ),
  MapEntry(
    'auto composer command editor completions',
    TerminalActionId.autoComposer,
  ),
  MapEntry('hotkey window summon hide shell', TerminalActionId.hotkeyWindow),
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: horizontal ? (_) => _setDragging(true) : null,
          onHorizontalDragEnd: horizontal ? (_) => _setDragging(false) : null,
          onHorizontalDragCancel: horizontal ? () => _setDragging(false) : null,
          onHorizontalDragUpdate: horizontal
              ? (details) => widget.onDragUpdate(details.delta.dx)
              : null,
          onVerticalDragStart: horizontal ? null : (_) => _setDragging(true),
          onVerticalDragEnd: horizontal ? null : (_) => _setDragging(false),
          onVerticalDragCancel: horizontal ? null : () => _setDragging(false),
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
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(palette.radius.lg),
      ),
      hoverColor: _shellTileHoverColor(palette),
      focusColor: _shellTileFocusColor(palette),
      leading: Icon(icon, color: enabled ? palette.accent : palette.textSubtle),
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
