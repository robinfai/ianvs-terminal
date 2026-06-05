part of 'shell_screen.dart';

class _ShellToolbelt extends StatelessWidget {
  const _ShellToolbelt({
    required this.capturedOutputCount,
    required this.pasteHistoryCount,
    required this.commandHistoryCount,
    required this.recentDirectoryCount,
    required this.promptMarkCount,
    required this.tmuxControlModeActive,
    required this.coprocessActive,
    required this.annotationCount,
    required this.completionDiagnosticsSnapshot,
    required this.palette,
    required this.onClose,
    required this.onOpenCapturedOutput,
    required this.onOpenPasteHistory,
    required this.onOpenShellIntegrationUtilities,
    required this.onOpenTmuxIntegration,
    required this.onOpenCoprocess,
    required this.onOpenAnnotations,
    required this.onOpenInstantReplay,
    required this.onOpenPasswordManager,
  });

  final int capturedOutputCount;
  final int pasteHistoryCount;
  final int commandHistoryCount;
  final int recentDirectoryCount;
  final int promptMarkCount;
  final bool tmuxControlModeActive;
  final bool coprocessActive;
  final int annotationCount;
  final LocalTerminalShellUiWiringSnapshot completionDiagnosticsSnapshot;
  final AppThemeTokens palette;
  final VoidCallback onClose;
  final VoidCallback onOpenCapturedOutput;
  final VoidCallback onOpenPasteHistory;
  final VoidCallback onOpenShellIntegrationUtilities;
  final VoidCallback onOpenTmuxIntegration;
  final VoidCallback onOpenCoprocess;
  final VoidCallback onOpenAnnotations;
  final VoidCallback onOpenInstantReplay;
  final VoidCallback onOpenPasswordManager;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('shell-toolbelt-panel'),
      width: 304,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.chromeElevated,
          border: Border(left: BorderSide(color: palette.borderStrong)),
          boxShadow: palette.elevation.floating,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                palette.spacing.lg,
                palette.spacing.lg,
                palette.spacing.lg,
                palette.spacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Toolbelt',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      _buildSheetCloseButton(
                        tooltip: 'Close toolbelt',
                        onPressed: onClose,
                        buttonKey: const Key('toolbelt-close'),
                      ),
                    ],
                  ),
                  SizedBox(height: palette.spacing.sm),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-captured-output'),
                            icon: Icons.outbox_rounded,
                            title: 'Captured output',
                            countLabel:
                                '$capturedOutputCount captured line${capturedOutputCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenCapturedOutput,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-paste-history'),
                            icon: Icons.history_rounded,
                            title: 'Paste history',
                            countLabel:
                                '$pasteHistoryCount recent item${pasteHistoryCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenPasteHistory,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-command-history'),
                            icon: Icons.list_alt_rounded,
                            title: 'Command history',
                            countLabel:
                                '$commandHistoryCount command${commandHistoryCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenShellIntegrationUtilities,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-recent-directories'),
                            icon: Icons.folder_rounded,
                            title: 'Recent directories',
                            countLabel:
                                '$recentDirectoryCount director${recentDirectoryCount == 1 ? 'y' : 'ies'}',
                            palette: palette,
                            onTap: onOpenShellIntegrationUtilities,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-prompt-marks'),
                            icon: Icons.assistant_direction_rounded,
                            title: 'Prompt marks',
                            countLabel:
                                '$promptMarkCount mark${promptMarkCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenShellIntegrationUtilities,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-tmux-integration'),
                            icon: Icons.account_tree_rounded,
                            title: 'tmux integration',
                            countLabel: tmuxControlModeActive
                                ? 'Control mode active'
                                : 'Start or attach',
                            palette: palette,
                            onTap: onOpenTmuxIntegration,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-coprocess'),
                            icon: Icons.hub_rounded,
                            title: 'Coprocess',
                            countLabel: coprocessActive
                                ? 'Automation active'
                                : 'Run automation',
                            palette: palette,
                            onTap: onOpenCoprocess,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-annotations'),
                            icon: Icons.sticky_note_2_rounded,
                            title: 'Annotations',
                            countLabel:
                                '$annotationCount note${annotationCount == 1 ? '' : 's'}',
                            palette: palette,
                            onTap: onOpenAnnotations,
                          ),
                          Divider(color: palette.border, height: 18),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-instant-replay'),
                            icon: Icons.replay_rounded,
                            title: 'Instant replay',
                            countLabel: 'Recent frames',
                            palette: palette,
                            onTap: onOpenInstantReplay,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-password-manager'),
                            icon: Icons.password_rounded,
                            title: 'Password manager',
                            countLabel: 'Prompt-gated sends',
                            palette: palette,
                            onTap: onOpenPasswordManager,
                          ),
                          Divider(color: palette.border, height: 18),
                          LocalTerminalCompletionDiagnosticsPanel(
                            key: const Key('toolbelt-completion-diagnostics'),
                            snapshot: completionDiagnosticsSnapshot,
                            maxItemsPerSection: 4,
                          ),
                        ],
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

class _ToolbeltActionRow extends StatelessWidget {
  const _ToolbeltActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.countLabel,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String countLabel;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      minLeadingWidth: 24,
      contentPadding: EdgeInsets.symmetric(
        horizontal: palette.spacing.sm,
        vertical: palette.spacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(palette.radius.md),
      ),
      hoverColor: _shellTileHoverColor(palette),
      focusColor: _shellTileFocusColor(palette),
      leading: Icon(icon, color: palette.accent, size: 20),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        countLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      onTap: onTap,
    );
  }
}
