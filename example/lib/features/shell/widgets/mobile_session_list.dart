import 'package:flutter/material.dart';

import '../../../ui/app_ui.dart';
import '../../sessions/session_state.dart';

/// Shared session rows for the mobile connection page and session picker.
///
/// The caller owns scrolling and every session operation. Only the disclosure
/// state of the disconnected group is kept here; session data stays external.
class MobileSessionList extends StatefulWidget {
  const MobileSessionList({
    super.key,
    required this.tabs,
    this.activeSessionId,
    required this.onSelect,
    required this.onReconnect,
    required this.onDisconnect,
    required this.onRemove,
    required this.onClearDisconnected,
    this.liveReconnections = const {},
    this.protectedSessionIds = const {},
  });

  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final ValueChanged<TerminalPane> onSelect;
  final ValueChanged<TerminalPane> onReconnect;
  final ValueChanged<TerminalPane> onDisconnect;
  final ValueChanged<TerminalPane> onRemove;
  final VoidCallback onClearDisconnected;

  /// Maps a retained output record to its currently running replacement.
  final Map<String, String> liveReconnections;

  /// Sessions whose output is still referenced by another AI conversation.
  final Set<String> protectedSessionIds;

  @override
  State<MobileSessionList> createState() => _MobileSessionListState();
}

class _MobileSessionListState extends State<MobileSessionList> {
  bool _disconnectedExpanded = false;

  @override
  void didUpdateWidget(MobileSessionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.tabs
        .expand((tab) => tab.effectivePanes)
        .any((pane) => pane.isExited)) {
      _disconnectedExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final panes = widget.tabs.expand((tab) => tab.effectivePanes).toList();
    if (panes.isEmpty) return const SizedBox.shrink();
    final active = panes.where((pane) => !pane.isExited).toList();
    final disconnected = panes.where((pane) => pane.isExited).toList();
    final spacing = context.appTheme.spacing;
    final canClear = disconnected.any(
      (pane) => !widget.protectedSessionIds.contains(pane.sessionId),
    );

    Widget row(TerminalPane pane) => Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: _SessionRow(
        pane: pane,
        selected: pane.sessionId == widget.activeSessionId,
        reconnected: widget.liveReconnections.containsKey(pane.sessionId),
        protected: widget.protectedSessionIds.contains(pane.sessionId),
        onSelect: () => widget.onSelect(pane),
        onReconnect: () => widget.onReconnect(pane),
        onDisconnect: () => widget.onDisconnect(pane),
        onRemove: () => widget.onRemove(pane),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: spacing.sm),
          child: Text(
            '${context.l10n.mobileSessions} (${active.length})',
            key: const Key('mobile-sessions-active-heading'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (active.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: spacing.sm),
            child: Text(
              context.l10n.mobileSessionsNoActive,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.appTheme.textMuted,
              ),
            ),
          ),
        for (final pane in active) row(pane),
        if (disconnected.isNotEmpty) ...[
          if (active.isNotEmpty) SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  expanded: _disconnectedExpanded,
                  child: InkWell(
                    key: const Key('mobile-sessions-disconnected-toggle'),
                    borderRadius: BorderRadius.circular(
                      context.appTheme.radius.md,
                    ),
                    onTap: () => setState(
                      () => _disconnectedExpanded = !_disconnectedExpanded,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: spacing.md),
                      child: Row(
                        children: [
                          Icon(
                            _disconnectedExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                          SizedBox(width: spacing.xs),
                          Expanded(
                            child: Text(
                              '${context.l10n.mobileSessionsDisconnected} '
                              '(${disconnected.length})',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: spacing.xs),
              Flexible(
                child: Tooltip(
                  message: canClear
                      ? context.l10n.mobileSessionsClearDisconnected
                      : context.l10n.mobileSessionReferencedByAi,
                  child: TextButton(
                    key: const Key('mobile-sessions-clear-disconnected'),
                    onPressed: canClear ? widget.onClearDisconnected : null,
                    child: Text(
                      context.l10n.mobileSessionsClearDisconnected,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_disconnectedExpanded)
            for (final pane in disconnected) row(pane),
        ],
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.pane,
    required this.selected,
    required this.reconnected,
    required this.protected,
    required this.onSelect,
    required this.onReconnect,
    required this.onDisconnect,
    required this.onRemove,
  });

  final TerminalPane pane;
  final bool selected;
  final bool reconnected;
  final bool protected;
  final VoidCallback onSelect;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTheme;
    final spacing = tokens.spacing;
    final textTheme = Theme.of(context).textTheme;
    final host = _hostLabel(context);
    final status = pane.isExited
        ? reconnected
              ? context.l10n.mobileSessionReconnected
              : context.l10n.mobileSessionDisconnected
        : context.l10n.mobileSessionActive;
    final statusColor = pane.isExited ? tokens.textMuted : tokens.success;

    return AppPanel(
      tone: selected ? AppPanelTone.selected : AppPanelTone.panel,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            selected: selected,
            button: true,
            hint: pane.isExited ? context.l10n.mobileSessionViewOutput : null,
            child: InkWell(
              key: Key('mobile-session-${pane.sessionId}'),
              onTap: onSelect,
              child: Padding(
                padding: EdgeInsets.all(spacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pane.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall,
                          ),
                          SizedBox(height: spacing.xs),
                          Tooltip(
                            message: host,
                            child: Text(
                              host,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: tokens.textMuted,
                              ),
                            ),
                          ),
                          SizedBox(height: spacing.sm),
                          Wrap(
                            spacing: spacing.sm,
                            runSpacing: spacing.xs,
                            children: [
                              Text(
                                status,
                                style: textTheme.labelMedium?.copyWith(
                                  color: statusColor,
                                ),
                              ),
                              if (pane.isExited && pane.exitCode != null)
                                Text(
                                  context.l10n.mobileSessionExitCode(
                                    pane.exitCode!,
                                  ),
                                  style: textTheme.labelMedium?.copyWith(
                                    color: tokens.textMuted,
                                  ),
                                ),
                            ],
                          ),
                          if (pane.isExited) ...[
                            SizedBox(height: spacing.xs),
                            Text(
                              context.l10n.mobileSessionViewOutput,
                              style: textTheme.labelMedium?.copyWith(
                                color: tokens.accent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    Icon(
                      selected
                          ? Icons.check_circle_outline_rounded
                          : Icons.chevron_right_rounded,
                      color: selected ? tokens.accent : tokens.textSubtle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: spacing.sm,
              right: spacing.sm,
              bottom: spacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: spacing.xs,
                  runSpacing: spacing.xs,
                  children: [
                    if (pane.isExited) ...[
                      TextButton.icon(
                        key: Key('mobile-session-reconnect-${pane.sessionId}'),
                        onPressed: onReconnect,
                        icon: Icon(
                          reconnected
                              ? Icons.open_in_new_rounded
                              : Icons.refresh_rounded,
                        ),
                        label: Text(
                          reconnected
                              ? context.l10n.mobileSessionOpenCurrent
                              : context.l10n.mobileSessionReconnect,
                        ),
                      ),
                      TextButton.icon(
                        key: Key('mobile-session-remove-${pane.sessionId}'),
                        onPressed: protected ? null : onRemove,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(context.l10n.mobileSessionRemove),
                      ),
                    ] else
                      TextButton.icon(
                        key: Key('mobile-session-disconnect-${pane.sessionId}'),
                        onPressed: protected ? null : onDisconnect,
                        icon: const Icon(Icons.link_off_rounded),
                        label: Text(context.l10n.mobileSessionDisconnect),
                      ),
                  ],
                ),
                if (protected)
                  Padding(
                    padding: EdgeInsets.all(spacing.sm),
                    child: Text(
                      context.l10n.mobileSessionReferencedByAi,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _hostLabel(BuildContext context) {
    final profile = pane.profileSnapshot;
    if (profile != null) {
      if (!profile.isSsh) return context.l10n.mobileSessionLocalHost;
      final connection = profile.connection;
      return ShellConnectionHop(
        kind: ShellConnectionHopKind.sshShell,
        host: connection.host,
        user: connection.user,
        port: connection.port,
      ).address;
    }
    for (final hop in pane.shellConnectionChain.reversed) {
      if (hop.host?.isNotEmpty ?? false) return hop.address;
      if (hop.kind == ShellConnectionHopKind.localShell) {
        return context.l10n.mobileSessionLocalHost;
      }
    }
    return context.l10n.unknownProfile;
  }
}
