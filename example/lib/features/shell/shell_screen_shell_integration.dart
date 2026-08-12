part of 'shell_screen.dart';

class _CoprocessSheet extends StatefulWidget {
  const _CoprocessSheet({
    required this.activeCoprocess,
    required this.onStart,
    required this.onStop,
  });

  final _ShellCoprocess? activeCoprocess;
  final ValueChanged<_CoprocessStartRequest> onStart;
  final VoidCallback onStop;

  @override
  State<_CoprocessSheet> createState() => _CoprocessSheetState();
}

class _CoprocessSheetState extends State<_CoprocessSheet> {
  late final TextEditingController _commandController;
  late final TextEditingController _patternController;
  late final TextEditingController _responseController;

  bool get _canStart =>
      _patternController.text.trim().isNotEmpty &&
      _responseController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _commandController = TextEditingController(text: 'presence bot');
    _patternController = TextEditingController(text: 'Are you there?');
    _responseController = TextEditingController(text: 'Yes\n');
  }

  @override
  void dispose() {
    _commandController.dispose();
    _patternController.dispose();
    _responseController.dispose();
    super.dispose();
  }

  void _start() {
    if (!_canStart) {
      return;
    }
    final command = _commandController.text.trim();
    widget.onStart(
      _CoprocessStartRequest(
        command: command.isEmpty ? 'Coprocess' : command,
        pattern: _patternController.text.trim(),
        response: _responseController.text,
      ),
    );
    Navigator.of(context).pop();
  }

  void _stop() {
    widget.onStop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final active = widget.activeCoprocess;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('coprocess-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Coprocess',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      _buildSheetCloseButton(
                        tooltip: 'Close coprocess',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (active == null)
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ShellIntegrationSectionHeader(
                              icon: Icons.hub_rounded,
                              title: 'Run Coprocess',
                              countLabel: 'one per session',
                              palette: palette,
                            ),
                            _CoprocessTextField(
                              fieldKey: const Key('coprocess-command-field'),
                              controller: _commandController,
                              label: 'Command label',
                              icon: Icons.label_rounded,
                              palette: palette,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            _CoprocessTextField(
                              fieldKey: const Key('coprocess-pattern-field'),
                              controller: _patternController,
                              label: 'Input pattern',
                              icon: Icons.search_rounded,
                              palette: palette,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            _CoprocessTextField(
                              fieldKey: const Key('coprocess-response-field'),
                              controller: _responseController,
                              label: 'Coprocess output',
                              icon: Icons.keyboard_return_rounded,
                              palette: palette,
                              maxLines: 3,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                key: const Key('coprocess-start'),
                                onPressed: _canStart ? _start : null,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Run'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    _ActiveCoprocessPanel(
                      coprocess: active,
                      palette: palette,
                      onStop: _stop,
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

class _CoprocessTextField extends StatelessWidget {
  const _CoprocessTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.icon,
    required this.palette,
    required this.onChanged,
    this.maxLines = 1,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final AppThemeTokens palette;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(prefixIcon: Icon(icon), labelText: label),
    );
  }
}

class _ActiveCoprocessPanel extends StatelessWidget {
  const _ActiveCoprocessPanel({
    required this.coprocess,
    required this.palette,
    required this.onStop,
  });

  final _ShellCoprocess coprocess;
  final AppThemeTokens palette;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('coprocess-active-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ShellIntegrationSectionHeader(
          icon: Icons.hub_rounded,
          title: coprocess.command,
          countLabel: '${coprocess.inputLineCount} lines',
          palette: palette,
        ),
        Text(
          'Pattern ${coprocess.pattern}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
        ),
        if (coprocess.lastInput != null) ...[
          const SizedBox(height: 6),
          Text(
            coprocess.lastInput!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
              fontFamily: 'monospace',
            ),
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const Key('coprocess-stop'),
            onPressed: onStop,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Stop'),
          ),
        ),
      ],
    );
  }
}

class _TmuxIntegrationSheet extends StatefulWidget {
  const _TmuxIntegrationSheet({
    required this.controlModeDetected,
    required this.onSendCommand,
  });

  final bool controlModeDetected;
  final ValueChanged<String> onSendCommand;

  @override
  State<_TmuxIntegrationSheet> createState() => _TmuxIntegrationSheetState();
}

class _TmuxIntegrationSheetState extends State<_TmuxIntegrationSheet> {
  late final TextEditingController _commandController;

  @override
  void initState() {
    super.initState();
    _commandController = TextEditingController();
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  void _send(String command) {
    Navigator.of(context).pop();
    widget.onSendCommand(command);
  }

  void _sendCustomCommand() {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      return;
    }
    _send('$command\n');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final controlModeDetected = widget.controlModeDetected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('tmux-integration-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'tmux Integration',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      _buildSheetCloseButton(
                        tooltip: 'Close tmux integration',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  _TmuxStatusChip(
                    controlModeDetected: controlModeDetected,
                    palette: palette,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ShellIntegrationSectionHeader(
                            icon: Icons.terminal_rounded,
                            title: 'Control Mode',
                            countLabel: 'tmux -CC',
                            palette: palette,
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-start-control-mode'),
                            icon: Icons.play_arrow_rounded,
                            title: 'Start tmux -CC',
                            subtitle: 'Create a new tmux control-mode session.',
                            palette: palette,
                            onTap: () => _send('tmux -CC\n'),
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-attach-control-mode'),
                            icon: Icons.login_rounded,
                            title: 'Attach tmux -CC',
                            subtitle: 'Attach to an existing tmux session.',
                            palette: palette,
                            onTap: () => _send('tmux -CC attach\n'),
                          ),
                          const SizedBox(height: 8),
                          _ShellIntegrationSectionHeader(
                            icon: Icons.account_tree_rounded,
                            title: 'tmux Actions',
                            countLabel: controlModeDetected
                                ? 'available'
                                : 'waiting',
                            palette: palette,
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-new-window'),
                            icon: Icons.add_box_outlined,
                            title: 'New window',
                            subtitle: 'Send new-window to tmux control mode.',
                            palette: palette,
                            enabled: controlModeDetected,
                            onTap: () => _send('new-window\n'),
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-split-right'),
                            icon: Icons.vertical_split_rounded,
                            title: 'Split pane right',
                            subtitle: 'Send split-window -h.',
                            palette: palette,
                            enabled: controlModeDetected,
                            onTap: () => _send('split-window -h\n'),
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-split-down'),
                            icon: Icons.horizontal_split_rounded,
                            title: 'Split pane down',
                            subtitle: 'Send split-window -v.',
                            palette: palette,
                            enabled: controlModeDetected,
                            onTap: () => _send('split-window -v\n'),
                          ),
                          _TmuxActionTile(
                            key: const Key('tmux-detach-client'),
                            icon: Icons.logout_rounded,
                            title: 'Detach client',
                            subtitle: 'Detach while leaving tmux running.',
                            palette: palette,
                            enabled: controlModeDetected,
                            onTap: () => _send('detach-client\n'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('tmux-command-field'),
                            controller: _commandController,
                            enabled: controlModeDetected,
                            onSubmitted: (_) => _sendCustomCommand(),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: palette.textPrimary),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.code_rounded),
                              suffixIcon: IconButton(
                                key: const Key('tmux-send-command'),
                                tooltip: 'Send tmux command',
                                onPressed: controlModeDetected
                                    ? _sendCustomCommand
                                    : null,
                                icon: const Icon(Icons.keyboard_return_rounded),
                              ),
                              hintText: 'tmux command',
                            ),
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

class _TmuxStatusChip extends StatelessWidget {
  const _TmuxStatusChip({
    required this.controlModeDetected,
    required this.palette,
  });

  final bool controlModeDetected;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: controlModeDetected
            ? palette.accent.withValues(alpha: 0.12)
            : palette.chrome,
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(
          color: controlModeDetected ? palette.accent : palette.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              controlModeDetected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: controlModeDetected ? palette.accent : palette.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              controlModeDetected
                  ? 'Control mode detected'
                  : 'No tmux control mode detected',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: controlModeDetected
                    ? palette.textPrimary
                    : palette.textSubtle,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TmuxActionTile extends StatelessWidget {
  const _TmuxActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final AppThemeTokens palette;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final titleColor = enabled ? palette.textPrimary : palette.textSubtle;
    final iconColor = enabled ? palette.textMuted : palette.textSubtle;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(icon, color: iconColor, size: 20),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: titleColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}

class _ShellIntegrationUtilitiesSheet extends StatelessWidget {
  const _ShellIntegrationUtilitiesSheet({
    required this.integration,
    required this.globalBottomRow,
    required this.scrollbackMaxOffset,
    required this.onInsertCommand,
    required this.onChangeDirectory,
    required this.onJumpToMark,
  });

  final TerminalShellIntegrationSnapshot integration;
  final int? globalBottomRow;
  final int scrollbackMaxOffset;
  final ValueChanged<String> onInsertCommand;
  final ValueChanged<String> onChangeDirectory;
  final ValueChanged<TerminalShellPromptMark> onJumpToMark;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final commandCount = integration.recentCommands.length;
    final directoryCount = integration.recentDirectories.length;
    final markCount = integration.promptMarks.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('shell-integration-utilities-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Shell Integration',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      AppActionButton(
                        tooltip: 'Close shell integration',
                        tone: AppActionTone.ghost,
                        size: AppActionSize.dense,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icons.close_rounded,
                      ),
                    ],
                  ),
                  _ShellIntegrationSummary(
                    integration: integration,
                    palette: palette,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        _ShellIntegrationSectionHeader(
                          icon: Icons.list_alt_rounded,
                          title: 'Command History',
                          countLabel:
                              '$commandCount command${commandCount == 1 ? '' : 's'}',
                          palette: palette,
                        ),
                        if (integration.recentCommands.isEmpty)
                          _ShellIntegrationEmptyRow(
                            message:
                                'Run a command after opening this tab to fill command history.',
                            palette: palette,
                          )
                        else
                          for (
                            var index = 0;
                            index < integration.recentCommands.length &&
                                index < 8;
                            index++
                          )
                            _ShellIntegrationActionTile(
                              key: Key('shell-command-history-entry-$index'),
                              icon: Icons.keyboard_return_rounded,
                              title: integration.recentCommands[index],
                              subtitle: 'Insert previous command',
                              palette: palette,
                              onTap: () {
                                Navigator.of(context).pop();
                                onInsertCommand(
                                  integration.recentCommands[index],
                                );
                              },
                            ),
                        const SizedBox(height: 8),
                        _ShellIntegrationSectionHeader(
                          icon: Icons.folder_rounded,
                          title: 'Recent Directories',
                          countLabel:
                              '$directoryCount director${directoryCount == 1 ? 'y' : 'ies'}',
                          palette: palette,
                        ),
                        if (integration.recentDirectories.isEmpty)
                          _ShellIntegrationEmptyRow(
                            message:
                                'Change directories after opening this tab to fill this list.',
                            palette: palette,
                          )
                        else
                          for (
                            var index = 0;
                            index < integration.recentDirectories.length &&
                                index < 8;
                            index++
                          )
                            _ShellIntegrationActionTile(
                              key: Key('shell-recent-directory-$index'),
                              icon: Icons.subdirectory_arrow_right_rounded,
                              title: integration.recentDirectories[index],
                              subtitle: 'Insert cd command',
                              palette: palette,
                              onTap: () {
                                Navigator.of(context).pop();
                                onChangeDirectory(
                                  integration.recentDirectories[index],
                                );
                              },
                            ),
                        const SizedBox(height: 8),
                        _ShellIntegrationSectionHeader(
                          icon: Icons.assistant_direction_rounded,
                          title: 'Prompt Marks',
                          countLabel:
                              '$markCount mark${markCount == 1 ? '' : 's'}',
                          palette: palette,
                        ),
                        if (integration.promptMarks.isEmpty)
                          _ShellIntegrationEmptyRow(
                            message:
                                'Prompt marks appear after the shell draws new prompts.',
                            palette: palette,
                          )
                        else
                          for (
                            var index = 0;
                            index < integration.promptMarks.length && index < 8;
                            index++
                          )
                            _ShellPromptMarkTile(
                              key: Key('shell-prompt-mark-$index'),
                              mark: integration.promptMarks.reversed.elementAt(
                                index,
                              ),
                              scrollbackOffset:
                                  terminalPromptMarkScrollbackOffset(
                                    integration.promptMarks.reversed.elementAt(
                                      index,
                                    ),
                                    globalBottomRow: globalBottomRow,
                                    scrollbackMaxOffset: scrollbackMaxOffset,
                                  ),
                              palette: palette,
                              onTap: () {
                                Navigator.of(context).pop();
                                onJumpToMark(
                                  integration.promptMarks.reversed.elementAt(
                                    index,
                                  ),
                                );
                              },
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
    );
  }
}

class _ShellIntegrationSummary extends StatelessWidget {
  const _ShellIntegrationSummary({
    required this.integration,
    required this.palette,
  });

  final TerminalShellIntegrationSnapshot integration;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final identity = _identityLabel;
    final directory = integration.currentDirectory;
    final command = integration.lastCommand;
    final exitCode = integration.lastExitCode;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ShellIntegrationChip(
          icon: Icons.account_tree_rounded,
          label: identity ?? 'Local shell',
          palette: palette,
        ),
        if (directory != null)
          _ShellIntegrationChip(
            icon: Icons.folder_open_rounded,
            label: _compactText(directory, 42),
            palette: palette,
          ),
        if (command != null)
          _ShellIntegrationChip(
            icon: Icons.terminal_rounded,
            label: exitCode == null
                ? _compactText(command, 42)
                : '${_compactText(command, 32)} ${exitCode == 0 ? 'ok' : 'exit $exitCode'}',
            palette: palette,
          ),
      ],
    );
  }

  String? get _identityLabel {
    final username = integration.username;
    final hostname = integration.hostname;
    if (username != null && hostname != null) {
      return '$username@$hostname';
    }
    return username ?? hostname ?? integration.shell;
  }
}

class _ShellIntegrationChip extends StatelessWidget {
  const _ShellIntegrationChip({
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chrome,
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: palette.textMuted),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: palette.textSubtle,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellIntegrationSectionHeader extends StatelessWidget {
  const _ShellIntegrationSectionHeader({
    required this.icon,
    required this.title,
    required this.countLabel,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final String countLabel;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            countLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.textSubtle,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellIntegrationEmptyRow extends StatelessWidget {
  const _ShellIntegrationEmptyRow({
    required this.message,
    required this.palette,
  });

  final String message;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
      ),
    );
  }
}

class _ShellIntegrationActionTile extends StatelessWidget {
  const _ShellIntegrationActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ShellEntryTile(
      dense: true,
      leading: Icon(icon, color: palette.textMuted, size: 20),
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: 1,
      onTap: onTap,
    );
  }
}

class _ShellPromptMarkTile extends StatelessWidget {
  const _ShellPromptMarkTile({
    super.key,
    required this.mark,
    required this.scrollbackOffset,
    required this.palette,
    required this.onTap,
  });

  final TerminalShellPromptMark mark;
  final int? scrollbackOffset;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final command = mark.command;
    final cwd = mark.cwd;
    final compactCwd = cwd == null ? null : _compactText(cwd, 42);
    final subtitle = [?command, ?compactCwd].join(' • ');

    return _ShellEntryTile(
      dense: true,
      leading: Icon(
        Icons.assistant_direction_rounded,
        color: palette.textMuted,
        size: 20,
      ),
      title: scrollbackOffset == null
          ? 'Global line ${mark.globalLine}'
          : 'Offset $scrollbackOffset',
      subtitle: subtitle.isEmpty ? 'Shell prompt mark' : subtitle,
      subtitleMaxLines: 1,
      onTap: onTap,
    );
  }
}

String _compactText(String text, int maxLength) {
  final trimmed = text.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxLength - 3)}...';
}
