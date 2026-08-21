part of 'shell_screen.dart';

enum _ToolbeltPanel {
  commandHistory,
  recentDirectories,
  capturedOutput,
  pasteHistory,
}

class _ShellToolbelt extends StatefulWidget {
  const _ShellToolbelt({
    required this.capturedOutputEntries,
    required this.pasteHistoryEntries,
    required this.shellIntegration,
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
    required this.onInsertCommand,
    required this.onChangeDirectory,
    required this.onOpenTmuxIntegration,
    required this.onOpenCoprocess,
    required this.onOpenAnnotations,
    required this.onOpenInstantReplay,
    required this.onOpenPasswordManager,
    this.showHiddenRedesignEntryPointsForTesting = false,
  });

  final List<_CapturedOutputEntry> capturedOutputEntries;
  final List<PasteHistoryEntry> pasteHistoryEntries;
  final TerminalShellIntegrationSnapshot shellIntegration;
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
  final ValueChanged<String> onInsertCommand;
  final ValueChanged<String> onChangeDirectory;
  final VoidCallback onOpenTmuxIntegration;
  final VoidCallback onOpenCoprocess;
  final VoidCallback onOpenAnnotations;
  final VoidCallback onOpenInstantReplay;
  final VoidCallback onOpenPasswordManager;
  final bool showHiddenRedesignEntryPointsForTesting;

  @override
  State<_ShellToolbelt> createState() => _ShellToolbeltState();
}

class _ShellToolbeltState extends State<_ShellToolbelt> {
  _ToolbeltPanel _activePanel = _ToolbeltPanel.commandHistory;
  late final Map<_ToolbeltPanel, FocusNode> _tabFocusNodes = {
    for (final panel in _ToolbeltPanel.values)
      panel: FocusNode(debugLabel: 'toolbelt-tab-${panel.name}'),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _tabFocusNodes[_activePanel]?.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final focusNode in _tabFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Semantics(
      identifier: 'toolbelt-panel',
      label: context.l10n.toolbeltTerminalTools,
      container: true,
      explicitChildNodes: true,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SizedBox(
          key: const Key('shell-toolbelt-panel'),
          width: 336,
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final header = Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.toolbelt,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: _buildSheetCloseButton(
                              tooltip: context.l10n.closeToolbelt,
                              onPressed: widget.onClose,
                              buttonKey: const Key('toolbelt-close'),
                            ),
                          ),
                        ],
                      );
                      final tabs = _ToolbeltPanelTabs(
                        activePanel: _activePanel,
                        palette: palette,
                        tabFocusNodes: _tabFocusNodes,
                        capturedOutputCount:
                            widget.capturedOutputEntries.length,
                        pasteHistoryCount: widget.pasteHistoryEntries.length,
                        commandHistoryCount:
                            widget.shellIntegration.recentCommands.length,
                        recentDirectoryCount:
                            widget.shellIntegration.recentDirectories.length,
                        onChanged: (panel) {
                          setState(() {
                            _activePanel = panel;
                          });
                        },
                      );
                      final body = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ToolbeltPrimaryPanel(
                            activePanel: _activePanel,
                            palette: palette,
                            capturedOutputEntries: widget.capturedOutputEntries,
                            pasteHistoryEntries: widget.pasteHistoryEntries,
                            shellIntegration: widget.shellIntegration,
                            onOpenCapturedOutput: widget.onOpenCapturedOutput,
                            onOpenPasteHistory: widget.onOpenPasteHistory,
                            onOpenShellIntegrationUtilities:
                                widget.onOpenShellIntegrationUtilities,
                            onInsertCommand: widget.onInsertCommand,
                            onChangeDirectory: widget.onChangeDirectory,
                          ),
                          Divider(color: palette.border, height: 22),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-prompt-marks'),
                            icon: Icons.assistant_direction_rounded,
                            title: context.l10n.promptMarks,
                            countLabel: context.l10n.promptMarkCount(
                              widget.promptMarkCount,
                            ),
                            palette: palette,
                            onTap: widget.onOpenShellIntegrationUtilities,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-tmux-integration'),
                            icon: Icons.account_tree_rounded,
                            title: context.l10n.tmuxIntegration,
                            countLabel: widget.tmuxControlModeActive
                                ? context.l10n.controlModeActive
                                : context.l10n.startOrAttach,
                            palette: palette,
                            onTap: widget.onOpenTmuxIntegration,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-coprocess'),
                            icon: Icons.hub_rounded,
                            title: context.l10n.coprocess,
                            countLabel: widget.coprocessActive
                                ? context.l10n.automationActive
                                : context.l10n.runAutomation,
                            palette: palette,
                            onTap: widget.onOpenCoprocess,
                          ),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-annotations'),
                            icon: Icons.sticky_note_2_rounded,
                            title: context.l10n.annotations,
                            countLabel: context.l10n.annotationCount(
                              widget.annotationCount,
                            ),
                            palette: palette,
                            onTap: widget.onOpenAnnotations,
                          ),
                          Divider(color: palette.border, height: 18),
                          _ToolbeltActionRow(
                            key: const Key('toolbelt-instant-replay'),
                            icon: Icons.replay_rounded,
                            title: context.l10n.replayRecentActivity,
                            countLabel: context.l10n.recentFrames,
                            palette: palette,
                            onTap: widget.onOpenInstantReplay,
                          ),
                          if (widget.showHiddenRedesignEntryPointsForTesting)
                            _ToolbeltActionRow(
                              key: const Key('toolbelt-password-manager'),
                              icon: Icons.password_rounded,
                              title: context.l10n.passwordManager,
                              countLabel: context.l10n.promptGatedSends,
                              palette: palette,
                              onTap: widget.onOpenPasswordManager,
                            ),
                          if (kDebugMode) ...[
                            Divider(color: palette.border, height: 18),
                            LocalTerminalCompletionDiagnosticsPanel(
                              key: const Key('toolbelt-completion-diagnostics'),
                              snapshot: widget.completionDiagnosticsSnapshot,
                              maxItemsPerSection: 4,
                            ),
                          ],
                        ],
                      );
                      final fixedHeaderExtent =
                          44 + palette.spacing.sm + 44 + palette.spacing.md;
                      if (constraints.maxHeight < fixedHeaderExtent) {
                        return SingleChildScrollView(
                          key: const Key('toolbelt-short-height-scroll'),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              header,
                              SizedBox(height: palette.spacing.sm),
                              tabs,
                              SizedBox(height: palette.spacing.md),
                              body,
                            ],
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          SizedBox(height: palette.spacing.sm),
                          tabs,
                          SizedBox(height: palette.spacing.md),
                          Expanded(child: SingleChildScrollView(child: body)),
                        ],
                      );
                    },
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

class _ToolbeltPanelTabs extends StatelessWidget {
  const _ToolbeltPanelTabs({
    required this.activePanel,
    required this.palette,
    required this.tabFocusNodes,
    required this.capturedOutputCount,
    required this.pasteHistoryCount,
    required this.commandHistoryCount,
    required this.recentDirectoryCount,
    required this.onChanged,
  });

  final _ToolbeltPanel activePanel;
  final AppThemeTokens palette;
  final Map<_ToolbeltPanel, FocusNode> tabFocusNodes;
  final int capturedOutputCount;
  final int pasteHistoryCount;
  final int commandHistoryCount;
  final int recentDirectoryCount;
  final ValueChanged<_ToolbeltPanel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: palette.spacing.xs,
      runSpacing: palette.spacing.xs,
      children: [
        _ToolbeltPanelTab(
          panel: _ToolbeltPanel.commandHistory,
          activePanel: activePanel,
          palette: palette,
          icon: Icons.list_alt_rounded,
          label: context.l10n.commands,
          count: commandHistoryCount,
          focusNode: tabFocusNodes[_ToolbeltPanel.commandHistory],
          onChanged: onChanged,
        ),
        _ToolbeltPanelTab(
          panel: _ToolbeltPanel.recentDirectories,
          activePanel: activePanel,
          palette: palette,
          icon: Icons.folder_rounded,
          label: context.l10n.directoriesShort,
          count: recentDirectoryCount,
          focusNode: tabFocusNodes[_ToolbeltPanel.recentDirectories],
          onChanged: onChanged,
        ),
        _ToolbeltPanelTab(
          panel: _ToolbeltPanel.capturedOutput,
          activePanel: activePanel,
          palette: palette,
          icon: Icons.outbox_rounded,
          label: context.l10n.output,
          count: capturedOutputCount,
          focusNode: tabFocusNodes[_ToolbeltPanel.capturedOutput],
          onChanged: onChanged,
        ),
        _ToolbeltPanelTab(
          panel: _ToolbeltPanel.pasteHistory,
          activePanel: activePanel,
          palette: palette,
          icon: Icons.history_rounded,
          label: context.l10n.paste,
          count: pasteHistoryCount,
          focusNode: tabFocusNodes[_ToolbeltPanel.pasteHistory],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ToolbeltPanelTab extends StatelessWidget {
  const _ToolbeltPanelTab({
    required this.panel,
    required this.activePanel,
    required this.palette,
    required this.icon,
    required this.label,
    required this.count,
    required this.focusNode,
    required this.onChanged,
  });

  final _ToolbeltPanel panel;
  final _ToolbeltPanel activePanel;
  final AppThemeTokens palette;
  final IconData icon;
  final String label;
  final int count;
  final FocusNode? focusNode;
  final ValueChanged<_ToolbeltPanel> onChanged;

  String get _wireName {
    return switch (panel) {
      _ToolbeltPanel.commandHistory => 'command-history',
      _ToolbeltPanel.recentDirectories => 'recent-directories',
      _ToolbeltPanel.capturedOutput => 'captured-output',
      _ToolbeltPanel.pasteHistory => 'paste-history',
    };
  }

  double get _focusOrder {
    return switch (panel) {
      _ToolbeltPanel.commandHistory => 10,
      _ToolbeltPanel.recentDirectories => 11,
      _ToolbeltPanel.capturedOutput => 12,
      _ToolbeltPanel.pasteHistory => 13,
    };
  }

  @override
  Widget build(BuildContext context) {
    final selected = panel == activePanel;
    final foreground = selected ? palette.textPrimary : palette.textMuted;
    return FocusTraversalOrder(
      order: NumericFocusOrder(_focusOrder),
      child: Semantics(
        identifier: 'toolbelt-tab-$_wireName',
        button: true,
        selected: selected,
        label: '$label toolbelt panel',
        onTap: () => onChanged(panel),
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('toolbelt-tab-$_wireName'),
            focusNode: focusNode,
            autofocus: selected,
            borderRadius: BorderRadius.circular(palette.radius.md),
            onTap: () => onChanged(panel),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              width: 142,
              height: 44,
              padding: EdgeInsets.symmetric(horizontal: palette.spacing.sm),
              decoration: BoxDecoration(
                color: selected ? palette.selected : palette.chrome,
                borderRadius: BorderRadius.circular(palette.radius.md),
                border: Border.all(
                  color: selected ? palette.focusRing : palette.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: foreground),
                  SizedBox(width: palette.spacing.xs),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    count.toString(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
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

class _ToolbeltPrimaryPanel extends StatelessWidget {
  const _ToolbeltPrimaryPanel({
    required this.activePanel,
    required this.palette,
    required this.capturedOutputEntries,
    required this.pasteHistoryEntries,
    required this.shellIntegration,
    required this.onOpenCapturedOutput,
    required this.onOpenPasteHistory,
    required this.onOpenShellIntegrationUtilities,
    required this.onInsertCommand,
    required this.onChangeDirectory,
  });

  final _ToolbeltPanel activePanel;
  final AppThemeTokens palette;
  final List<_CapturedOutputEntry> capturedOutputEntries;
  final List<PasteHistoryEntry> pasteHistoryEntries;
  final TerminalShellIntegrationSnapshot shellIntegration;
  final VoidCallback onOpenCapturedOutput;
  final VoidCallback onOpenPasteHistory;
  final VoidCallback onOpenShellIntegrationUtilities;
  final ValueChanged<String> onInsertCommand;
  final ValueChanged<String> onChangeDirectory;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      tone: AppPanelTone.panel,
      padding: EdgeInsets.all(palette.spacing.md),
      borderRadius: BorderRadius.circular(palette.radius.lg),
      child: switch (activePanel) {
        _ToolbeltPanel.commandHistory => _buildCommands(context),
        _ToolbeltPanel.recentDirectories => _buildDirectories(context),
        _ToolbeltPanel.capturedOutput => _buildCapturedOutput(context),
        _ToolbeltPanel.pasteHistory => _buildPasteHistory(context),
      },
    );
  }

  Widget _buildCommands(BuildContext context) {
    final commands = shellIntegration.recentCommands.take(5).toList();
    return _ToolbeltPreviewSection(
      sectionKey: const Key('toolbelt-panel-command-history'),
      icon: Icons.list_alt_rounded,
      title: context.l10n.commandHistory,
      subtitle: context.l10n.commandCount(
        shellIntegration.recentCommands.length,
      ),
      palette: palette,
      actionKey: const Key('toolbelt-command-history'),
      actionLabel: context.l10n.all,
      onAction: onOpenShellIntegrationUtilities,
      children: commands.isEmpty
          ? [
              _ToolbeltEmptyPreview(
                message: context.l10n.runCommandToFillHistory,
                palette: palette,
              ),
            ]
          : [
              for (var index = 0; index < commands.length; index += 1)
                _ToolbeltPreviewTile(
                  tileKey: Key('toolbelt-command-history-entry-$index'),
                  icon: Icons.keyboard_return_rounded,
                  title: commands[index],
                  subtitle: context.l10n.insertCommand,
                  palette: palette,
                  onTap: () => onInsertCommand(commands[index]),
                ),
            ],
    );
  }

  Widget _buildDirectories(BuildContext context) {
    final directories = shellIntegration.recentDirectories.take(5).toList();
    return _ToolbeltPreviewSection(
      sectionKey: const Key('toolbelt-panel-recent-directories'),
      icon: Icons.folder_rounded,
      title: context.l10n.recentDirectories,
      subtitle: context.l10n.directoryCount(
        shellIntegration.recentDirectories.length,
      ),
      palette: palette,
      actionKey: const Key('toolbelt-recent-directories'),
      actionLabel: context.l10n.all,
      onAction: onOpenShellIntegrationUtilities,
      children: directories.isEmpty
          ? [
              _ToolbeltEmptyPreview(
                message: context.l10n.changeDirectoriesToFillHistory,
                palette: palette,
              ),
            ]
          : [
              for (var index = 0; index < directories.length; index += 1)
                _ToolbeltPreviewTile(
                  tileKey: Key('toolbelt-recent-directory-entry-$index'),
                  icon: Icons.subdirectory_arrow_right_rounded,
                  title: directories[index],
                  subtitle: context.l10n.insertCdCommand,
                  palette: palette,
                  onTap: () => onChangeDirectory(directories[index]),
                ),
            ],
    );
  }

  Widget _buildCapturedOutput(BuildContext context) {
    final entries = capturedOutputEntries.take(5).toList();
    return _ToolbeltPreviewSection(
      sectionKey: const Key('toolbelt-panel-captured-output'),
      icon: Icons.outbox_rounded,
      title: context.l10n.capturedOutput,
      subtitle: context.l10n.capturedLineCount(capturedOutputEntries.length),
      palette: palette,
      actionKey: const Key('toolbelt-captured-output'),
      actionLabel: context.l10n.open,
      onAction: onOpenCapturedOutput,
      children: entries.isEmpty
          ? [
              _ToolbeltEmptyPreview(
                message: context.l10n.profileAutomationCapturesOutput,
                palette: palette,
              ),
            ]
          : [
              for (var index = 0; index < entries.length; index += 1)
                _ToolbeltPreviewTile(
                  tileKey: Key('toolbelt-captured-output-entry-$index'),
                  icon: Icons.outbox_rounded,
                  title: entries[index].text,
                  subtitle: context.l10n.capturedOutputLocation(
                    entries[index].pattern,
                    entries[index].rowIndex,
                  ),
                  palette: palette,
                  onTap: onOpenCapturedOutput,
                ),
            ],
    );
  }

  Widget _buildPasteHistory(BuildContext context) {
    final entries = pasteHistoryEntries.take(5).toList();
    return _ToolbeltPreviewSection(
      sectionKey: const Key('toolbelt-panel-paste-history'),
      icon: Icons.history_rounded,
      title: context.l10n.pasteHistory,
      subtitle: context.l10n.recentItemCount(pasteHistoryEntries.length),
      palette: palette,
      actionKey: const Key('toolbelt-paste-history'),
      actionLabel: context.l10n.open,
      onAction: onOpenPasteHistory,
      children: entries.isEmpty
          ? [
              _ToolbeltEmptyPreview(
                message: context.l10n.copiedAndPastedTextAppearsHere,
                palette: palette,
              ),
            ]
          : [
              for (var index = 0; index < entries.length; index += 1)
                _ToolbeltPreviewTile(
                  tileKey: Key('toolbelt-paste-history-entry-$index'),
                  icon: entries[index].kind == PasteHistoryKind.copy
                      ? Icons.copy_rounded
                      : Icons.content_paste_rounded,
                  title: entries[index].text.replaceAll('\n', r' \n '),
                  subtitle: switch (entries[index].kind) {
                    PasteHistoryKind.copy => context.l10n.copied,
                    PasteHistoryKind.paste => context.l10n.pasted,
                  },
                  palette: palette,
                  onTap: onOpenPasteHistory,
                ),
            ],
    );
  }
}

class _ToolbeltPreviewSection extends StatelessWidget {
  const _ToolbeltPreviewSection({
    required this.sectionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.actionKey,
    required this.actionLabel,
    required this.onAction,
    required this.children,
  });

  final Key sectionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final AppThemeTokens palette;
  final Key actionKey;
  final String actionLabel;
  final VoidCallback onAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: palette.accent),
            SizedBox(width: palette.spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
                  ),
                ],
              ),
            ),
            AppActionButton(
              buttonKey: actionKey,
              tone: AppActionTone.ghost,
              size: AppActionSize.compact,
              label: actionLabel,
              tooltip: actionLabel,
              onPressed: onAction,
            ),
          ],
        ),
        SizedBox(height: palette.spacing.sm),
        ...children,
      ],
    );
  }
}

class _ToolbeltPreviewTile extends StatelessWidget {
  const _ToolbeltPreviewTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      dense: true,
      minLeadingWidth: 22,
      contentPadding: EdgeInsets.symmetric(horizontal: palette.spacing.xs),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(palette.radius.md),
      ),
      leading: Icon(icon, color: palette.textMuted, size: 18),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: palette.textSubtle),
      ),
      hoverColor: _shellTileHoverColor(palette),
      focusColor: _shellTileFocusColor(palette),
      onTap: onTap,
    );
  }
}

class _ToolbeltEmptyPreview extends StatelessWidget {
  const _ToolbeltEmptyPreview({required this.message, required this.palette});

  final String message;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: palette.spacing.md),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
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
          fontWeight: FontWeight.w600,
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
