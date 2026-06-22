part of 'shell_screen.dart';

class _ShellStatusBar extends StatelessWidget {
  const _ShellStatusBar({
    super.key,
    required this.palette,
    required this.terminalBackgroundColor,
    required this.directory,
    required this.viewportLabel,
    required this.modeItems,
    required this.encodingLabel,
  });

  final AppThemeTokens palette;
  final Color terminalBackgroundColor;
  final String? directory;
  final String? viewportLabel;
  final List<ShellStatusModeItem> modeItems;
  final String encodingLabel;

  @override
  Widget build(BuildContext context) {
    final tone = _ShellTabTone.fromTerminalBackground(
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
          semanticsLabel: modeItem.semanticsLabel,
          monospace: true,
          highlighted: true,
          maxWidth: 118,
        ),
      if (directory != null && directory!.trim().isNotEmpty)
        _ShellStatusDirectoryItem(
          key: const Key('shell-status-directory'),
          palette: palette,
          tone: tone,
          label: _statusPathLabel(directory!),
          fullPath: directory!.trim(),
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

class ShellStatusModeItem {
  const ShellStatusModeItem({
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
    this.minWidth,
    this.maxWidth,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final String label;
  final String fullPath;
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
          tooltip: widget.fullPath,
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
    if (semanticsLabel != null) {
      item = Semantics(container: true, label: semanticsLabel, child: item);
    }
    if (tooltip != null) {
      item = Tooltip(message: tooltip!, child: item);
    }
    return item;
  }
}
