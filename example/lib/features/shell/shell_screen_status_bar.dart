part of 'shell_screen.dart';

class _ShellStatusBar extends StatelessWidget {
  const _ShellStatusBar({
    super.key,
    required this.palette,
    required this.terminalBackgroundColor,
    required this.directory,
    this.directoryTooltip,
    required this.viewportLabel,
    required this.modeItems,
    required this.shellIntegrationHealth,
    this.shellIntegrationHealthTooltip,
    required this.encodingLabel,
    this.linkLabel,
    this.linkTooltip,
    this.onLinkPressed,
    this.osc52Label,
    this.osc52Tooltip,
    this.onOsc52Pressed,
    this.remoteLabel,
    this.remoteTooltip,
    this.onRemotePressed,
    this.progressLabel,
    this.progressTooltip,
    this.progressItems = const <TerminalPaneProgressState>[],
    this.onProgressPressed,
    this.notificationLabel,
    this.notificationTooltip,
    this.notifications = const <TerminalPaneNotificationState>[],
    this.onNotificationPressed,
    this.onNotificationInteraction,
    this.badgeLabel,
    this.badgeTooltip,
    this.onBadgePressed,
  });

  final AppThemeTokens palette;
  final Color terminalBackgroundColor;
  final String? directory;
  final String? directoryTooltip;
  final String? viewportLabel;
  final List<_ShellStatusModeItem> modeItems;
  final _ShellIntegrationHealth shellIntegrationHealth;
  final String? shellIntegrationHealthTooltip;
  final String encodingLabel;
  final String? linkLabel;
  final String? linkTooltip;
  final VoidCallback? onLinkPressed;
  final String? osc52Label;
  final String? osc52Tooltip;
  final VoidCallback? onOsc52Pressed;
  final String? remoteLabel;
  final String? remoteTooltip;
  final VoidCallback? onRemotePressed;
  final String? progressLabel;
  final String? progressTooltip;
  final List<TerminalPaneProgressState> progressItems;
  final VoidCallback? onProgressPressed;
  final String? notificationLabel;
  final String? notificationTooltip;
  final List<TerminalPaneNotificationState> notifications;
  final VoidCallback? onNotificationPressed;
  final ValueChanged<_ShellNotificationInteraction>? onNotificationInteraction;
  final String? badgeLabel;
  final String? badgeTooltip;
  final VoidCallback? onBadgePressed;

  @override
  Widget build(BuildContext context) {
    final tone = _ShellTabTone.fromTerminalBackground(
      palette: palette,
      terminalBackground: terminalBackgroundColor,
    );
    final statusItems = <Widget>[
      _ShellStatusItem(
        key: const Key('shell-status-encoding'),
        palette: palette,
        tone: tone,
        label: encodingLabel,
        monospace: true,
      ),
      if (viewportLabel != null)
        _ShellStatusItem(
          key: const Key('shell-status-viewport'),
          palette: palette,
          tone: tone,
          label: viewportLabel!,
          monospace: true,
        ),
      for (final modeItem in modeItems)
        _ShellStatusItem(
          key: modeItem.key,
          palette: palette,
          tone: tone,
          label: modeItem.label,
          tooltip: modeItem.tooltip,
          semanticsLabel: _statusSemanticsLabel(
            modeItem.semanticsLabel,
            modeItem.tooltip,
          ),
          monospace: true,
          highlighted: true,
          maxWidth: 118,
        ),
      if (linkLabel != null)
        _ShellStatusItem(
          key: const Key('shell-status-link-target'),
          palette: palette,
          tone: tone,
          label: linkLabel!,
          tooltip: linkTooltip,
          semanticsLabel: 'Terminal link target: ${linkTooltip ?? linkLabel}',
          monospace: true,
          highlighted: true,
          maxWidth: 220,
          onPressed: onLinkPressed,
        ),
      if (osc52Label != null)
        _ShellStatusItem(
          key: const Key('shell-status-osc52'),
          palette: palette,
          tone: tone,
          label: osc52Label!,
          tooltip: osc52Tooltip,
          semanticsLabel: _statusSemanticsLabel(
            'OSC 52 clipboard status: $osc52Label',
            osc52Tooltip,
          ),
          monospace: true,
          highlighted: true,
          maxWidth: 190,
          onPressed: onOsc52Pressed,
        ),
      if (remoteLabel != null)
        _ShellStatusItem(
          key: const Key('shell-status-remote'),
          palette: palette,
          tone: tone,
          label: remoteLabel!,
          tooltip: remoteTooltip,
          semanticsLabel:
              'Remote shell context: ${remoteTooltip ?? remoteLabel}',
          monospace: true,
          highlighted: true,
          maxWidth: 190,
          onPressed: onRemotePressed,
        ),
      if (progressLabel != null)
        _ShellStatusProgressItem(
          itemKey: const Key('shell-status-progress'),
          palette: palette,
          tone: tone,
          label: progressLabel!,
          tooltip: progressTooltip,
          progressItems: progressItems,
          onPressed: onProgressPressed,
        ),
      if (notificationLabel != null)
        _ShellStatusNotificationItem(
          itemKey: const Key('shell-status-notification'),
          palette: palette,
          tone: tone,
          label: notificationLabel!,
          tooltip: notificationTooltip,
          notifications: notifications,
          onPressed: onNotificationPressed,
          onInteraction: onNotificationInteraction,
        ),
      if (badgeLabel != null)
        _ShellStatusItem(
          key: const Key('shell-status-badge'),
          palette: palette,
          tone: tone,
          label: badgeLabel!,
          tooltip: badgeTooltip,
          semanticsLabel: _statusSemanticsLabel(
            'Terminal badge: $badgeLabel',
            badgeTooltip,
          ),
          monospace: true,
          highlighted: true,
          maxWidth: 170,
          onPressed: onBadgePressed,
        ),
      _ShellStatusItem(
        key: const Key('shell-status-shell-integration'),
        palette: palette,
        tone: tone,
        label: shellIntegrationHealth.label,
        tooltip:
            shellIntegrationHealthTooltip ?? shellIntegrationHealth.tooltip,
        semanticsLabel: _statusSemanticsLabel(
          shellIntegrationHealth.semanticsLabel,
          shellIntegrationHealthTooltip ?? shellIntegrationHealth.tooltip,
        ),
        monospace: true,
        highlighted: shellIntegrationHealth.highlighted,
        maxWidth: 142,
      ),
      if (directory != null && directory!.trim().isNotEmpty)
        _ShellStatusDirectoryItem(
          key: const Key('shell-status-directory'),
          palette: palette,
          tone: tone,
          label: _statusPathLabel(directory!),
          fullPath: directory!.trim(),
          tooltip: directoryTooltip,
          minWidth: 176,
          maxWidth: 260,
        ),
    ];

    return DecoratedBox(
      key: const Key('shell-status-bar-surface'),
      decoration: BoxDecoration(
        color: terminalBackgroundColor,
        border: Border(
          top: BorderSide(color: tone.border.withValues(alpha: 0.46)),
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(palette.radius.lg),
          bottomRight: Radius.circular(palette.radius.lg),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: palette.spacing.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var index = 0; index < statusItems.length; index++) ...[
                  if (index > 0)
                    _ShellStatusDivider(palette: palette, tone: tone),
                  statusItems[index],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusPathLabel(String path) {
    final normalized = path.trim();
    if (normalized.length <= 34) {
      return normalized;
    }
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '.../${parts[parts.length - 2]}/${parts.last}';
    }
    return '...${normalized.substring(normalized.length - 31)}';
  }
}

enum _ShellIntegrationHealthLevel { active, partial, unavailable }

class _ShellIntegrationHealth {
  const _ShellIntegrationHealth._(this.level);

  factory _ShellIntegrationHealth.fromSnapshot(
    TerminalShellIntegrationSnapshot snapshot,
  ) {
    final hasCommandMetadata =
        snapshot.recentCommands.isNotEmpty ||
        snapshot.promptMarks.isNotEmpty ||
        snapshot.lastCommand?.trim().isNotEmpty == true;
    if (hasCommandMetadata) {
      return const _ShellIntegrationHealth._(
        _ShellIntegrationHealthLevel.active,
      );
    }

    final hasContext =
        snapshot.currentDirectory?.trim().isNotEmpty == true ||
        snapshot.hostname?.trim().isNotEmpty == true ||
        snapshot.username?.trim().isNotEmpty == true ||
        snapshot.shell?.trim().isNotEmpty == true ||
        snapshot.recentDirectories.isNotEmpty;
    if (hasContext) {
      return const _ShellIntegrationHealth._(
        _ShellIntegrationHealthLevel.partial,
      );
    }

    return const _ShellIntegrationHealth._(
      _ShellIntegrationHealthLevel.unavailable,
    );
  }

  final _ShellIntegrationHealthLevel level;

  String get label {
    return switch (level) {
      _ShellIntegrationHealthLevel.active => 'SHELL ACTIVE',
      _ShellIntegrationHealthLevel.partial => 'SHELL PARTIAL',
      _ShellIntegrationHealthLevel.unavailable => 'SHELL WAITING',
    };
  }

  String get tooltip {
    return switch (level) {
      _ShellIntegrationHealthLevel.active =>
        'Shell integration is active for this pane.',
      _ShellIntegrationHealthLevel.partial =>
        'Shell integration has shell context, but command or prompt metadata has not arrived.',
      _ShellIntegrationHealthLevel.unavailable =>
        'Shell integration metadata has not arrived for this pane yet.',
    };
  }

  String get semanticsLabel {
    return switch (level) {
      _ShellIntegrationHealthLevel.active => 'Shell integration health: active',
      _ShellIntegrationHealthLevel.partial =>
        'Shell integration health: partial',
      _ShellIntegrationHealthLevel.unavailable =>
        'Shell integration health: waiting',
    };
  }

  bool get highlighted => level != _ShellIntegrationHealthLevel.unavailable;
}

class _ShellStatusModeItem {
  const _ShellStatusModeItem({
    required this.key,
    required this.label,
    required this.tooltip,
    required this.semanticsLabel,
  });

  final Key key;
  final String label;
  final String tooltip;
  final String semanticsLabel;
}

class _ShellStatusDirectoryItem extends StatefulWidget {
  const _ShellStatusDirectoryItem({
    super.key,
    required this.palette,
    required this.tone,
    required this.label,
    required this.fullPath,
    this.tooltip,
    this.minWidth,
    this.maxWidth,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final String label;
  final String fullPath;
  final String? tooltip;
  final double? minWidth;
  final double? maxWidth;

  @override
  State<_ShellStatusDirectoryItem> createState() =>
      _ShellStatusDirectoryItemState();
}

class _ShellStatusDirectoryItemState extends State<_ShellStatusDirectoryItem> {
  bool _hovered = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final menuBackground = Color.alphaBlend(
      widget.tone.hoverBackground.withValues(alpha: 0.42),
      widget.tone.activeBackground,
    );
    final menuBorder = widget.tone.border.withValues(alpha: 0.58);
    final menuTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: widget.tone.primaryText,
      fontWeight: FontWeight.w600,
    );
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.palette.radius.md),
      side: BorderSide(color: menuBorder),
    );
    final themedMenu = Theme.of(context).copyWith(
      hoverColor: widget.tone.hoverBackground.withValues(alpha: 0.72),
      highlightColor: widget.tone.hoverBackground.withValues(alpha: 0.72),
      focusColor: widget.tone.hoverBackground.withValues(alpha: 0.72),
      splashColor: Colors.transparent,
      popupMenuTheme: PopupMenuThemeData(
        color: menuBackground,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: menuShape,
        textStyle: menuTextStyle,
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Theme(
        data: themedMenu,
        child: PopupMenuButton<String>(
          tooltip: widget.tooltip ?? widget.fullPath,
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under,
          offset: Offset(0, widget.palette.spacing.xs),
          color: menuBackground,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: menuShape,
          onOpened: () => setState(() => _menuOpen = true),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'copyPath',
              height: 34,
              child: Text('Copy full path', style: menuTextStyle),
            ),
          ],
          onCanceled: () => setState(() => _menuOpen = false),
          onSelected: (value) {
            setState(() => _menuOpen = false);
            if (value == 'copyPath') {
              unawaited(ClipboardBridge.copy(widget.fullPath));
            }
          },
          child: _ShellStatusItem(
            palette: widget.palette,
            tone: widget.tone,
            label: widget.label,
            minWidth: widget.minWidth,
            maxWidth: widget.maxWidth,
            highlighted: _hovered || _menuOpen,
          ),
        ),
      ),
    );
  }
}

class _ShellStatusProgressItem extends StatelessWidget {
  const _ShellStatusProgressItem({
    required this.itemKey,
    required this.palette,
    required this.tone,
    required this.label,
    required this.progressItems,
    this.tooltip,
    this.onPressed,
  });

  final Key itemKey;
  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final String label;
  final List<TerminalPaneProgressState> progressItems;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    Widget item = _ShellStatusItem(
      key: itemKey,
      palette: palette,
      tone: tone,
      label: label,
      tooltip: progressItems.length <= 1 ? tooltip : null,
      semanticsLabel: _statusSemanticsLabel(
        'Terminal progress status: $label',
        tooltip,
      ),
      monospace: true,
      highlighted: true,
      maxWidth: 190,
    );
    if (progressItems.length <= 1) {
      if (onPressed != null) {
        item = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: item,
          ),
        );
      }
      return item;
    }
    return _ShellStatusPopup<int>(
      palette: palette,
      tone: tone,
      tooltip: tooltip ?? 'Terminal progress',
      item: item,
      onOpened: onPressed,
      entries: [
        for (var index = 0; index < progressItems.length; index += 1)
          PopupMenuItem<int>(
            value: index,
            enabled: false,
            height: 48,
            child: _ShellStatusMenuTextBlock(
              title: progressItems[index].displayLabel,
              subtitle: _progressMenuSubtitle(progressItems[index]),
              tone: tone,
            ),
          ),
      ],
    );
  }

  String _progressMenuSubtitle(TerminalPaneProgressState progress) {
    return [
      if (progress.label?.trim().isNotEmpty == true) progress.label!.trim(),
      if (progress.state?.trim().isNotEmpty == true) progress.state!.trim(),
      if (progress.percent != null) '${progress.percent}%',
      progress.source,
    ].join(' · ');
  }
}

class _ShellStatusNotificationItem extends StatelessWidget {
  const _ShellStatusNotificationItem({
    required this.itemKey,
    required this.palette,
    required this.tone,
    required this.label,
    required this.notifications,
    this.tooltip,
    this.onPressed,
    this.onInteraction,
  });

  final Key itemKey;
  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final String label;
  final List<TerminalPaneNotificationState> notifications;
  final String? tooltip;
  final VoidCallback? onPressed;
  final ValueChanged<_ShellNotificationInteraction>? onInteraction;

  @override
  Widget build(BuildContext context) {
    final item = _ShellStatusItem(
      key: itemKey,
      palette: palette,
      tone: tone,
      label: label,
      tooltip: notifications.isEmpty ? tooltip : null,
      semanticsLabel: _statusSemanticsLabel(
        'Terminal notification status: $label',
        tooltip,
      ),
      monospace: true,
      highlighted: true,
      maxWidth: 210,
    );
    if (notifications.isEmpty) {
      if (onPressed != null) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: item,
          ),
        );
      }
      return item;
    }
    return _ShellStatusPopup<_ShellNotificationInteraction>(
      palette: palette,
      tone: tone,
      tooltip: tooltip ?? 'Terminal notifications',
      item: item,
      onOpened: onPressed,
      onSelected: onInteraction,
      entries: [
        for (
          var index = 0;
          index < notifications.take(6).length;
          index += 1
        ) ...[
          if (index > 0) const PopupMenuDivider(height: 8),
          PopupMenuItem<_ShellNotificationInteraction>(
            key: Key('shell-status-notification-$index-activate'),
            value: _ShellNotificationInteraction.activate(notifications[index]),
            enabled: notifications[index].reportActivation,
            height: 52,
            child: _ShellStatusMenuTextBlock(
              title: _notificationMenuTitle(notifications[index]),
              subtitle: _notificationMenuSubtitle(notifications[index]),
              tone: tone,
            ),
          ),
          for (
            var buttonIndex = 0;
            buttonIndex < notifications[index].buttons.length;
            buttonIndex += 1
          )
            PopupMenuItem<_ShellNotificationInteraction>(
              key: Key(
                'shell-status-notification-$index-button-${buttonIndex + 1}',
              ),
              value: _ShellNotificationInteraction.button(
                notifications[index],
                buttonIndex + 1,
              ),
              enabled: notifications[index].reportActivation,
              height: 40,
              child: _ShellStatusMenuTextBlock(
                title: notifications[index].buttons[buttonIndex].isEmpty
                    ? 'Button ${buttonIndex + 1}'
                    : notifications[index].buttons[buttonIndex],
                subtitle: 'Notification action ${buttonIndex + 1}',
                tone: tone,
              ),
            ),
          if (notifications[index].source == 'osc99' &&
              notifications[index].identifier != null)
            PopupMenuItem<_ShellNotificationInteraction>(
              key: Key('shell-status-notification-$index-dismiss'),
              value: _ShellNotificationInteraction.dismiss(
                notifications[index],
              ),
              height: 40,
              child: _ShellStatusMenuTextBlock(
                title: 'Dismiss',
                subtitle: notifications[index].reportClose
                    ? 'Close and report to the terminal process'
                    : 'Remove this notification',
                tone: tone,
              ),
            ),
        ],
      ],
    );
  }

  String _notificationMenuTitle(TerminalPaneNotificationState notification) {
    final count = notification.count > 1 ? ' x${notification.count}' : '';
    return '${notification.title}$count';
  }

  String _notificationMenuSubtitle(TerminalPaneNotificationState notification) {
    return [
      if (notification.message.trim().isNotEmpty) notification.message.trim(),
      if (notification.remoteHost?.trim().isNotEmpty == true)
        notification.remoteUser?.trim().isNotEmpty == true
            ? '${notification.remoteUser!.trim()}@${notification.remoteHost!.trim()}'
            : notification.remoteHost!.trim(),
      notification.source,
    ].join(' · ');
  }
}

enum _ShellNotificationInteractionKind { activate, button, dismiss }

class _ShellNotificationInteraction {
  const _ShellNotificationInteraction.activate(this.notification)
    : kind = _ShellNotificationInteractionKind.activate,
      buttonNumber = null;

  const _ShellNotificationInteraction.button(
    this.notification,
    this.buttonNumber,
  ) : kind = _ShellNotificationInteractionKind.button;

  const _ShellNotificationInteraction.dismiss(this.notification)
    : kind = _ShellNotificationInteractionKind.dismiss,
      buttonNumber = null;

  final TerminalPaneNotificationState notification;
  final _ShellNotificationInteractionKind kind;
  final int? buttonNumber;
}

String _statusSemanticsLabel(String label, String? tooltip) {
  final detail = tooltip?.trim();
  if (detail == null || detail.isEmpty) {
    return label;
  }
  return '$label. $detail';
}

class _ShellStatusPopup<T> extends StatelessWidget {
  const _ShellStatusPopup({
    required this.palette,
    required this.tone,
    required this.tooltip,
    required this.item,
    required this.entries,
    this.onOpened,
    this.onSelected,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final String tooltip;
  final Widget item;
  final List<PopupMenuEntry<T>> entries;
  final VoidCallback? onOpened;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    final menuBackground = Color.alphaBlend(
      tone.hoverBackground.withValues(alpha: 0.42),
      tone.activeBackground,
    );
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(palette.radius.md),
      side: BorderSide(color: tone.border.withValues(alpha: 0.58)),
    );
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: menuBackground,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: menuShape,
        ),
      ),
      child: PopupMenuButton<T>(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        offset: Offset(0, palette.spacing.xs),
        color: menuBackground,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: menuShape,
        onOpened: onOpened,
        onSelected: onSelected,
        itemBuilder: (context) => entries,
        child: item,
      ),
    );
  }
}

class _ShellStatusMenuTextBlock extends StatelessWidget {
  const _ShellStatusMenuTextBlock({
    required this.title,
    required this.subtitle,
    required this.tone,
  });

  final String title;
  final String subtitle;
  final _ShellTabTone tone;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tone.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle.trim().isNotEmpty)
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tone.mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

class _ShellStatusDivider extends StatelessWidget {
  const _ShellStatusDivider({required this.palette, required this.tone});

  final AppThemeTokens palette;
  final _ShellTabTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: EdgeInsets.symmetric(horizontal: palette.spacing.lg),
      color: tone.border.withValues(alpha: 0.34),
    );
  }
}

class _ShellStatusItem extends StatelessWidget {
  const _ShellStatusItem({
    super.key,
    required this.palette,
    required this.tone,
    required this.label,
    this.monospace = false,
    this.minWidth,
    this.maxWidth,
    this.highlighted = false,
    this.tooltip,
    this.semanticsLabel,
    this.onPressed,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final String label;
  final bool monospace;
  final double? minWidth;
  final double? maxWidth;
  final bool highlighted;
  final String? tooltip;
  final String? semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final itemBackground = highlighted
        ? tone.hoverBackground
        : Color.alphaBlend(
            tone.hoverBackground.withValues(alpha: 0.34),
            tone.activeBackground,
          );
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: tone.mutedText,
      fontWeight: FontWeight.w600,
      fontFamily: monospace ? 'monospace' : null,
    );
    Widget item = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth ?? 0,
        maxWidth: maxWidth ?? 180,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: itemBackground,
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: tone.border.withValues(alpha: 0.38)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (onPressed != null) {
      item = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: item,
        ),
      );
    }
    if (semanticsLabel != null || onPressed != null) {
      item = Semantics(
        container: true,
        label: semanticsLabel,
        button: onPressed != null,
        onTap: onPressed,
        child: item,
      );
    }
    if (tooltip != null) {
      item = Tooltip(message: tooltip!, child: item);
    }
    return item;
  }
}
