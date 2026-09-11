part of 'shell_screen.dart';

class _MobileShellHeader extends StatelessWidget {
  const _MobileShellHeader({
    required this.title,
    required this.onReplay,
    required this.onSettings,
    this.onBack,
    this.onSessions,
    this.onFiles,
    this.onMore,
  });
  final String title;
  final VoidCallback onReplay;
  final VoidCallback onSettings;
  final VoidCallback? onBack;
  final VoidCallback? onSessions;
  final VoidCallback? onFiles;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => Material(
    color: context.appTheme.panel,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              key: const Key('mobile-connections-back'),
              tooltip: context.l10n.mobileConnections,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
          Expanded(
            child: onSessions == null
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  )
                : TextButton(
                    key: const Key('mobile-session-picker'),
                    onPressed: onSessions,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const Icon(Icons.expand_more_rounded),
                      ],
                    ),
                  ),
          ),
          if (onBack == null) ...[
            IconButton(
              key: const Key('shell-open-recording'),
              tooltip: context.l10n.mobileReplay,
              onPressed: onReplay,
              icon: const Icon(Icons.play_circle_outline_rounded),
            ),
            IconButton(
              key: const Key('shell-command-defaults'),
              tooltip: context.l10n.mobileSettings,
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ] else ...[
            if (onFiles != null)
              IconButton(
                key: const Key('shell-open-sftp-panel'),
                tooltip: context.l10n.mobileFiles,
                onPressed: onFiles,
                icon: const Icon(Icons.folder_outlined),
              ),
            IconButton(
              key: const Key('shell-chrome-menu'),
              tooltip: context.l10n.mobileSessionActions,
              onPressed: onMore,
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ],
      ),
    ),
  );
}

class _MobileTerminalToolbar extends StatelessWidget {
  const _MobileTerminalToolbar({
    required this.onKeyboard,
    required this.onSearch,
    required this.onReplay,
    required this.onRecording,
    required this.recording,
    required this.pendingSave,
  });
  final VoidCallback onKeyboard;
  final VoidCallback onSearch;
  final VoidCallback onReplay;
  final VoidCallback? onRecording;
  final bool recording;
  final bool pendingSave;

  @override
  Widget build(BuildContext context) {
    Widget action(
      String key,
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool active = false,
    }) => Expanded(
      child: TextButton(
        key: Key(key),
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: active ? Theme.of(context).colorScheme.error : null,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
    return Material(
      color: context.appTheme.panel,
      child: Row(
        children: [
          action(
            'mobile-show-keyboard',
            Icons.keyboard_outlined,
            context.l10n.mobileKeyboard,
            onKeyboard,
          ),
          action(
            'shell-search-scrollback-top',
            Icons.search_rounded,
            context.l10n.search,
            onSearch,
          ),
          action(
            'shell-toggle-session-recording',
            recording
                ? Icons.stop_circle_outlined
                : pendingSave
                ? Icons.save_outlined
                : Icons.fiber_manual_record_outlined,
            recording
                ? context.l10n.mobileStopRecording
                : pendingSave
                ? context.l10n.retrySavingRecording
                : context.l10n.mobileRecord,
            onRecording,
            active: recording,
          ),
          action(
            'shell-open-recording',
            Icons.play_circle_outline_rounded,
            context.l10n.mobileReplay,
            onReplay,
          ),
        ],
      ),
    );
  }
}

class _MobileSessionMenu extends StatelessWidget {
  const _MobileSessionMenu({
    required this.hasSession,
    required this.readOnly,
    required this.canReopen,
  });
  final bool hasSession;
  final bool readOnly;
  final bool canReopen;

  @override
  Widget build(BuildContext context) {
    Widget action(
      String key,
      TerminalActionId action,
      IconData icon,
      String title, {
      bool destructive = false,
    }) => ListTile(
      key: Key(key),
      leading: Icon(icon),
      title: Text(title),
      textColor: destructive ? Theme.of(context).colorScheme.error : null,
      iconColor: destructive ? Theme.of(context).colorScheme.error : null,
      onTap: () => Navigator.pop(context, action),
    );
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          key: const Key('mobile-session-menu'),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.mobileSessionActions,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: context.l10n.close,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (hasSession) ...[
              action(
                'shell-toggle-read-only',
                TerminalActionId.toggleReadOnly,
                readOnly ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                context.l10n.readOnlyMode(readOnly.toString()),
              ),
              action(
                'shell-export-scrollback',
                TerminalActionId.exportScrollback,
                Icons.copy_rounded,
                context.l10n.mobileCopyHistory,
              ),
            ],
            action(
              'shell-command-profiles',
              TerminalActionId.profiles,
              Icons.dns_outlined,
              context.l10n.mobileManageConnections,
            ),
            action(
              'shell-command-defaults',
              TerminalActionId.defaults,
              Icons.settings_outlined,
              context.l10n.mobileSettings,
            ),
            if (hasSession || canReopen)
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                key: const Key('mobile-session-advanced'),
                title: Text(context.l10n.mobileAdvanced),
                children: [
                  if (canReopen)
                    action(
                      'shell-reopen-closed-tab',
                      TerminalActionId.reopenClosedTab,
                      Icons.restore_rounded,
                      context.l10n.reopenClosedTab,
                    ),
                  if (hasSession) ...[
                    action(
                      'shell-clear-buffer',
                      TerminalActionId.clearBuffer,
                      Icons.clear_all_rounded,
                      context.l10n.clearBuffer,
                      destructive: true,
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

extension _ShellMobileNavigation on _ShellScreenState {
  void _showMobileConnections() {
    FocusManager.instance.primaryFocus?.unfocus();
    _mutateState(() => _mobileConnectionsOpen = true);
  }

  Future<void> _showMobileSessions(
    SessionController controller,
    SessionState state,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.mobileSessions,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              for (final tab in state.tabs)
                for (final pane in tab.effectivePanes)
                  ListTile(
                    key: Key('mobile-session-${pane.sessionId}'),
                    leading: const Icon(Icons.terminal_rounded),
                    title: Text(pane.title),
                    selected: pane.sessionId == state.activeSessionId,
                    onTap: () => Navigator.pop(context, pane.sessionId),
                    trailing: IconButton(
                      key: Key('mobile-session-close-${pane.sessionId}'),
                      tooltip: context.l10n.close,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        Navigator.pop(context);
                        if (tab.effectivePanes.length > 1) {
                          _closeSession(controller, state, pane.sessionId);
                        } else {
                          _closeTab(controller, state, tab.sessionId);
                        }
                      },
                    ),
                  ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: Text(context.l10n.newSshConnection),
                onTap: () => Navigator.pop(context, '__new__'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == '__new__') {
      await _openNewSessionLauncher(
        controller,
        ref.read(sessionControllerProvider),
      );
    } else {
      _activateSession(controller, selected);
    }
  }
}
