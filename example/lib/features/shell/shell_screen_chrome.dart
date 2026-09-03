part of 'shell_screen.dart';

const double _shellChromeTitleHeight = 38;
const double _shellChromeTabRailHeight = 38;
const double _iosShellChromeTitleHeight = 44;
const double _iosShellChromeTabRailHeight = 52;
const double _shellChromeHorizontalInset = 12;
const double _compactMobileChromeBreakpoint = 600;

class _ShellChromeBar extends StatelessWidget {
  const _ShellChromeBar({
    required this.palette,
    required this.terminalBackgroundColor,
    required this.tabStripKey,
    required this.paneDropInsertionIndex,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabNewOutputTooltip,
    required this.hiddenTabsNewOutputTooltip,
    required this.hiddenTabsNewOutputPaneSessionId,
    required this.tabNewOutputPaneSessionId,
    required this.tabColor,
    required this.referenceDemoMode,
    required this.onNewTab,
    required this.onActivateSession,
    required this.onActivateBadgePane,
    required this.onNotificationInteraction,
    required this.onActivateNewOutputPane,
    required this.onCloseSession,
    required this.onReorderTab,
    required this.onSessionDragStarted,
    required this.onSessionDragUpdated,
    required this.onSessionDragEnded,
    required this.onSessionDragCancelled,
    required this.onShowTabContextMenu,
    required this.onShowCommandMenu,
  });

  final AppThemeTokens palette;
  final Color terminalBackgroundColor;
  final GlobalKey<_ShellTabStripState> tabStripKey;
  final int? paneDropInsertionIndex;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final String Function(TerminalTab tab) tabNewOutputTooltip;
  final String Function(Iterable<TerminalTab> tabs) hiddenTabsNewOutputTooltip;
  final String? Function(Iterable<TerminalTab> tabs)
  hiddenTabsNewOutputPaneSessionId;
  final String? Function(TerminalTab tab) tabNewOutputPaneSessionId;
  final Color? Function(TerminalTab tab) tabColor;
  final bool referenceDemoMode;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onActivateBadgePane;
  final ValueChanged<_ShellNotificationInteraction> onNotificationInteraction;
  final ValueChanged<String> onActivateNewOutputPane;
  final ValueChanged<String> onCloseSession;
  final void Function({required int oldIndex, required int newIndex})
  onReorderTab;
  final ValueChanged<_ShellSessionDragData> onSessionDragStarted;
  final void Function(_ShellSessionDragData data, Offset globalPosition)
  onSessionDragUpdated;
  final ValueChanged<_ShellSessionDragData> onSessionDragEnded;
  final ValueChanged<_ShellSessionDragData> onSessionDragCancelled;
  final void Function(TerminalTab tab, Offset position) onShowTabContextMenu;
  final VoidCallback onShowCommandMenu;

  @override
  Widget build(BuildContext context) {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final isMobilePlatform = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    };
    final windowSize = MediaQuery.sizeOf(context);
    final usesCompactMobileChrome =
        isMobilePlatform &&
        math.min(windowSize.width, windowSize.height) <
            _compactMobileChromeBreakpoint;
    final titleHeight = isIos
        ? _iosShellChromeTitleHeight
        : _shellChromeTitleHeight;
    final tabRailHeight = isIos
        ? _iosShellChromeTabRailHeight
        : _shellChromeTabRailHeight;
    final chromeBase = _ShellTabTone.chromeBaseFor(
      palette,
      terminalBackgroundColor,
    );
    final chromeTone = _ShellTabTone.fromTerminalBackground(palette: palette);
    final chromeSurface = _ShellTabTone.chromeSurfaceFor(palette, chromeBase);
    final railSurface = _ShellTabTone.railSurfaceFor(palette, chromeBase);
    return DecoratedBox(
      key: const Key('shell-chrome-bar'),
      decoration: BoxDecoration(
        color: terminalBackgroundColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(palette.radius.lg),
          topRight: Radius.circular(palette.radius.lg),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(palette.radius.lg),
          topRight: Radius.circular(palette.radius.lg),
        ),
        child: SizedBox(
          height: (usesCompactMobileChrome ? 0 : titleHeight) + tabRailHeight,
          child: Column(
            children: [
              if (!usesCompactMobileChrome)
                _ShellWindowTitleBar(
                  height: titleHeight,
                  palette: palette,
                  tone: chromeTone,
                  backgroundColor: chromeSurface,
                  onShowCommandMenu: referenceDemoMode
                      ? null
                      : onShowCommandMenu,
                ),
              SizedBox(
                height: tabRailHeight,
                child: DecoratedBox(
                  key: const Key('shell-chrome-tab-rail-surface'),
                  decoration: BoxDecoration(
                    color: railSurface,
                    border: Border(
                      top: BorderSide(
                        color: chromeTone.border.withValues(alpha: 0.18),
                      ),
                      bottom: BorderSide(
                        color: chromeTone.border.withValues(alpha: 0.20),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _shellChromeHorizontalInset,
                      3,
                      _shellChromeHorizontalInset,
                      5,
                    ),
                    child: Row(
                      children: [
                        if (usesCompactMobileChrome && !referenceDemoMode) ...[
                          _buildChromeIconButton(
                            key: const Key('shell-chrome-menu'),
                            tooltip: context.l10n.openCommandPalette,
                            onPressed: onShowCommandMenu,
                            iconSize: 16,
                            hoverBackgroundColor: chromeTone.hoverBackground,
                            icon: Icon(
                              Icons.tune_rounded,
                              color: chromeTone.subtleText,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: DecoratedBox(
                            key: const Key('shell-chrome-tab-track'),
                            decoration: BoxDecoration(
                              color: chromeTone.trackBackground,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: referenceDemoMode
                                ? _ReferenceDemoTabStrip(
                                    palette: palette,
                                    tabs: tabs,
                                    activeSessionId: activeSessionId,
                                    onActivateSession: onActivateSession,
                                  )
                                : _ShellTabStrip(
                                    key: tabStripKey,
                                    palette: palette,
                                    chromeBackgroundColor:
                                        terminalBackgroundColor,
                                    paneDropInsertionIndex:
                                        paneDropInsertionIndex,
                                    tabs: tabs,
                                    activeSessionId: activeSessionId,
                                    tabHasNewOutput: tabHasNewOutput,
                                    tabNewOutputTooltip: tabNewOutputTooltip,
                                    hiddenTabsNewOutputTooltip:
                                        hiddenTabsNewOutputTooltip,
                                    hiddenTabsNewOutputPaneSessionId:
                                        hiddenTabsNewOutputPaneSessionId,
                                    tabNewOutputPaneSessionId:
                                        tabNewOutputPaneSessionId,
                                    tabColor: tabColor,
                                    showNewTabAction: !usesCompactMobileChrome,
                                    onNewTab: onNewTab,
                                    onActivateSession: onActivateSession,
                                    onActivateBadgePane: onActivateBadgePane,
                                    onNotificationInteraction:
                                        onNotificationInteraction,
                                    onActivateNewOutputPane:
                                        onActivateNewOutputPane,
                                    onCloseSession: onCloseSession,
                                    onReorderTab: onReorderTab,
                                    onSessionDragStarted: onSessionDragStarted,
                                    onSessionDragUpdated: onSessionDragUpdated,
                                    onSessionDragEnded: onSessionDragEnded,
                                    onSessionDragCancelled:
                                        onSessionDragCancelled,
                                    onShowTabContextMenu: onShowTabContextMenu,
                                  ),
                          ),
                        ),
                        if (usesCompactMobileChrome && !referenceDemoMode) ...[
                          const SizedBox(width: 4),
                          _ShellNewTabButton(
                            palette: palette,
                            tone: chromeTone,
                            width: 44,
                            onPressed: onNewTab,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellWindowTitleBar extends StatelessWidget {
  const _ShellWindowTitleBar({
    required this.height,
    required this.palette,
    required this.tone,
    required this.backgroundColor,
    required this.onShowCommandMenu,
  });

  final double height;
  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final Color backgroundColor;
  final VoidCallback? onShowCommandMenu;

  @override
  Widget build(BuildContext context) {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final titleLeadingInset = defaultTargetPlatform == TargetPlatform.macOS
        ? 158.0
        : palette.spacing.xl;
    final trailingInset = onShowCommandMenu == null
        ? 16.0
        : isIos
        ? 64.0
        : 48.0;
    final titleSafeInset = math.max(titleLeadingInset, trailingInset);

    return SizedBox(
      height: height,
      child: DecoratedBox(
        key: const Key('shell-chrome-title-surface'),
        decoration: BoxDecoration(color: backgroundColor),
        child: Stack(
          children: [
            const Positioned.fill(
              child: _WindowDragHandle(
                key: Key('shell-window-drag-leading'),
                child: SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: titleSafeInset),
                  child: Center(
                    child: Text(
                      context.l10n.appTitle,
                      key: const Key('shell-chrome-window-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tone.mutedText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onShowCommandMenu != null)
              Positioned(
                top: isIos ? 0 : 5,
                right: 12,
                child: _buildChromeIconButton(
                  key: const Key('shell-chrome-menu'),
                  tooltip: context.l10n.openCommandPalette,
                  onPressed: onShowCommandMenu,
                  iconSize: 16,
                  hoverBackgroundColor: tone.hoverBackground,
                  icon: Icon(Icons.tune_rounded, color: tone.subtleText),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WindowDragHandle extends StatelessWidget {
  const _WindowDragHandle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _ShellConfigurationWarningsBanner extends StatelessWidget {
  const _ShellConfigurationWarningsBanner({
    required this.palette,
    required this.warnings,
    required this.onReviewProfiles,
    required this.onDismiss,
  });

  final AppThemeTokens palette;
  final List<TerminalProfileLoadWarning> warnings;
  final Future<void> Function() onReviewProfiles;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-configuration-warnings'),
      decoration: BoxDecoration(
        color: palette.warningContainer,
        border: Border(bottom: BorderSide(color: palette.warning)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: palette.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.configurationWarningsSummary,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final warning in warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            terminalProfileLoadWarningMessage(warning),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSubtle),
                          ),
                        ),
                    ],
                  ),
                ),
                _buildCompactActionButton(
                  key: const Key('shell-configuration-warnings-dismiss'),
                  tooltip: context.l10n.dismissConfigurationWarnings,
                  onPressed: onDismiss,
                  icon: Icon(Icons.close_rounded, color: palette.textSubtle),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                FilledButton.tonal(
                  key: const Key('shell-configuration-warnings-review'),
                  onPressed: () => unawaited(onReviewProfiles()),
                  child: Text(context.l10n.reviewProfiles),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(context.l10n.dismiss),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellRuntimeErrorBanner extends StatelessWidget {
  const _ShellRuntimeErrorBanner({
    required this.palette,
    required this.message,
    required this.onDismiss,
  });

  final AppThemeTokens palette;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: context.l10n.terminalRuntimeError,
      child: DecoratedBox(
        key: const Key('shell-runtime-error'),
        decoration: BoxDecoration(
          color: palette.dangerContainer,
          border: Border(bottom: BorderSide(color: palette.danger)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: palette.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
                ),
              ),
              _buildCompactActionButton(
                key: const Key('shell-runtime-error-dismiss'),
                tooltip: context.l10n.dismissRuntimeError,
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded, color: palette.textSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellZmodemRecoveryBanner extends StatelessWidget {
  const _ShellZmodemRecoveryBanner({
    required this.palette,
    required this.filename,
    required this.sourceLabel,
    required this.onReveal,
    required this.onDiscard,
  });

  final AppThemeTokens palette;
  final String filename;
  final String sourceLabel;
  final VoidCallback onReveal;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      liveRegion: true,
      label: l10n.zmodemPreservedSemantics(filename, sourceLabel),
      child: DecoratedBox(
        key: const Key('shell-zmodem-recovery'),
        decoration: BoxDecoration(
          color: palette.warningContainer,
          border: Border(bottom: BorderSide(color: palette.warning)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: palette.warning),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  l10n.zmodemPublishFailedPreserved(filename, sourceLabel),
                  key: const Key('shell-zmodem-recovery-message'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
                ),
              ),
              TextButton(
                key: const Key('shell-zmodem-recovery-reveal'),
                onPressed: onReveal,
                child: Text(l10n.reveal),
              ),
              Tooltip(
                message: l10n.permanentlyDeletePreservedZmodem,
                child: Semantics(
                  button: true,
                  label: l10n.permanentlyDeletePreservedZmodem,
                  child: TextButton(
                    key: const Key('shell-zmodem-recovery-dismiss'),
                    onPressed: onDiscard,
                    child: Text(l10n.discardFileEllipsis),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellZmodemTransferBanner extends StatelessWidget {
  const _ShellZmodemTransferBanner({
    required this.palette,
    required this.transfer,
    required this.onCancel,
    this.onRetry,
  });

  final AppThemeTokens palette;
  final _ShellZmodemTransferState transfer;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final progress = transfer.progress;
    final announcePhase =
        transfer.event.kind != terminal.TerminalZmodemEventKind.progress;
    return Semantics(
      container: true,
      child: DecoratedBox(
        key: Key('shell-zmodem-transfer-${transfer.transferId}'),
        decoration: BoxDecoration(
          color: palette.selected,
          border: Border(bottom: BorderSide(color: palette.accent)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            children: [
              if (announcePhase)
                Semantics(
                  liveRegion: true,
                  label: '${transfer.title}. ${transfer.detail}',
                  child: const SizedBox.shrink(),
                ),
              Icon(
                transfer.direction == terminal.TerminalZmodemDirection.receive
                    ? Icons.download_rounded
                    : Icons.upload_rounded,
                color: palette.accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      transfer.detail,
                      key: const Key('shell-zmodem-transfer-detail'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      container: true,
                      label: l10n.zmodemProgress,
                      value: progress == null
                          ? l10n.indeterminate
                          : l10n.percentValue((progress * 100).floor()),
                      liveRegion: false,
                      child: ExcludeSemantics(
                        child: LinearProgressIndicator(
                          key: const Key('shell-zmodem-transfer-progress'),
                          value: progress,
                          minHeight: 3,
                          color: palette.accent,
                          backgroundColor: palette.border,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (onRetry != null) ...[
                TextButton.icon(
                  key: const Key('shell-zmodem-transfer-retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l10n.retry),
                ),
                const SizedBox(width: 4),
              ],
              TextButton.icon(
                key: const Key('shell-zmodem-transfer-cancel'),
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(
                  transfer.cancelling ? l10n.cancelling : l10n.cancel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferenceDemoTabStrip extends StatelessWidget {
  const _ReferenceDemoTabStrip({
    required this.palette,
    required this.tabs,
    required this.activeSessionId,
    required this.onActivateSession,
  });

  final AppThemeTokens palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final ValueChanged<String> onActivateSession;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('shell-tab-strip'),
      children: [
        for (var index = 0; index < tabs.length; index++) ...[
          Expanded(
            child: _ReferenceDemoTab(
              palette: palette,
              tab: tabs[index],
              shortcutIndex:
                  defaultTargetPlatform != TargetPlatform.iOS && index < 9
                  ? index + 1
                  : null,
              isActive:
                  activeSessionId != null &&
                  tabs[index].containsSession(activeSessionId!),
              onActivate: () => onActivateSession(tabs[index].activeSessionId),
            ),
          ),
          if (index < tabs.length - 1)
            SizedBox(
              width: 1,
              height: double.infinity,
              child: ColoredBox(color: palette.border),
            ),
        ],
      ],
    );
  }
}

class _ReferenceDemoTab extends StatelessWidget {
  const _ReferenceDemoTab({
    required this.palette,
    required this.tab,
    required this.shortcutIndex,
    required this.isActive,
    required this.onActivate,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
  final bool isActive;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final title = _shellTabDisplayTitle(tab);
    return Semantics(
      identifier: _shellTabSemanticsIdentifier(tab),
      label: _shellTabSemanticsLabel(context.l10n, tab, shortcutIndex),
      selected: isActive,
      button: true,
      child: TextButton(
        key: Key('shell-tab-${tab.sessionId}'),
        onPressed: onActivate,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isActive ? palette.textPrimary : palette.textMuted,
          shape: const RoundedRectangleBorder(),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shortcutIndex != null) ...[
                Text(
                  '⌘$shortcutIndex',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isActive ? palette.textMuted : palette.textSubtle,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: isActive ? palette.textPrimary : palette.textSubtle,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellTabStrip extends StatefulWidget {
  const _ShellTabStrip({
    super.key,
    required this.palette,
    required this.chromeBackgroundColor,
    required this.paneDropInsertionIndex,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabNewOutputTooltip,
    required this.hiddenTabsNewOutputTooltip,
    required this.hiddenTabsNewOutputPaneSessionId,
    required this.tabNewOutputPaneSessionId,
    required this.tabColor,
    this.showNewTabAction = true,
    required this.onNewTab,
    required this.onActivateSession,
    required this.onActivateBadgePane,
    required this.onNotificationInteraction,
    required this.onActivateNewOutputPane,
    required this.onCloseSession,
    required this.onReorderTab,
    required this.onSessionDragStarted,
    required this.onSessionDragUpdated,
    required this.onSessionDragEnded,
    required this.onSessionDragCancelled,
    required this.onShowTabContextMenu,
  });

  final AppThemeTokens palette;
  final Color chromeBackgroundColor;
  final int? paneDropInsertionIndex;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final String Function(TerminalTab tab) tabNewOutputTooltip;
  final String Function(Iterable<TerminalTab> tabs) hiddenTabsNewOutputTooltip;
  final String? Function(Iterable<TerminalTab> tabs)
  hiddenTabsNewOutputPaneSessionId;
  final String? Function(TerminalTab tab) tabNewOutputPaneSessionId;
  final Color? Function(TerminalTab tab) tabColor;
  final bool showNewTabAction;
  final VoidCallback? onNewTab;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onActivateBadgePane;
  final ValueChanged<_ShellNotificationInteraction> onNotificationInteraction;
  final ValueChanged<String> onActivateNewOutputPane;
  final ValueChanged<String> onCloseSession;
  final void Function({required int oldIndex, required int newIndex})
  onReorderTab;
  final ValueChanged<_ShellSessionDragData> onSessionDragStarted;
  final void Function(_ShellSessionDragData data, Offset globalPosition)
  onSessionDragUpdated;
  final ValueChanged<_ShellSessionDragData> onSessionDragEnded;
  final ValueChanged<_ShellSessionDragData> onSessionDragCancelled;
  final void Function(TerminalTab tab, Offset position) onShowTabContextMenu;

  @override
  State<_ShellTabStrip> createState() => _ShellTabStripState();
}

class _ShellTabStripState extends State<_ShellTabStrip> {
  static const double _regularMinTabWidth = 180;
  static const double _compactMinTabWidth = 104;
  static const double _compactTabThreshold = 140;
  static double get _tabActionButtonWidth =>
      defaultTargetPlatform == TargetPlatform.iOS ? 44 : 40;

  String? _draggingSessionId;
  _ShellSessionDragData? _externalDragData;
  Offset? _lastDragGlobalPosition;
  int _visibleTabCount = 0;
  double _visibleTabWidth = 0;
  final ValueNotifier<bool> _externalDragOutsideStrip = ValueNotifier(false);
  final ValueNotifier<Offset?> _externalDragFeedbackPosition = ValueNotifier(
    null,
  );
  OverlayEntry? _externalDragFeedbackOverlay;
  SliverReorderableListState? _activeReorderListState;
  Timer? _dragCompletionTimer;
  final Map<String, FocusNode> _tabFocusNodes = <String, FocusNode>{};

  @override
  void didUpdateWidget(_ShellTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveSessionIds = widget.tabs.map((tab) => tab.sessionId).toSet();
    final staleSessionIds = _tabFocusNodes.keys
        .where((sessionId) => !liveSessionIds.contains(sessionId))
        .toList(growable: false);
    for (final sessionId in staleSessionIds) {
      _tabFocusNodes.remove(sessionId)?.dispose();
    }
  }

  @override
  void dispose() {
    _dragCompletionTimer?.cancel();
    _removeExternalDragFeedbackOverlay();
    _externalDragOutsideStrip.dispose();
    _externalDragFeedbackPosition.dispose();
    for (final focusNode in _tabFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  FocusNode _focusNodeForTab(TerminalTab tab) {
    return _tabFocusNodes.putIfAbsent(
      tab.sessionId,
      () => FocusNode(debugLabel: 'shell-tab-${tab.sessionId}'),
    );
  }

  bool containsGlobalPosition(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    return (origin & renderObject.size).contains(globalPosition);
  }

  int insertionIndexForGlobalPosition(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    final visibleCount = _visibleTabCount.clamp(0, widget.tabs.length);
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        visibleCount == 0 ||
        _visibleTabWidth <= 0) {
      return 0;
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    return ((localPosition.dx / _visibleTabWidth) + 0.5).floor().clamp(
      0,
      visibleCount,
    );
  }

  void _handleDragPointerPosition(Offset globalPosition) {
    _lastDragGlobalPosition = globalPosition;
    final data = _externalDragData;
    if (data != null) {
      final outsideStrip = !containsGlobalPosition(globalPosition);
      if (_externalDragOutsideStrip.value != outsideStrip) {
        _externalDragOutsideStrip.value = outsideStrip;
      }
      _externalDragFeedbackPosition.value = outsideStrip
          ? globalPosition
          : null;
      widget.onSessionDragUpdated(data, globalPosition);
    }
  }

  void _insertExternalDragFeedbackOverlay() {
    _removeExternalDragFeedbackOverlay();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    final entry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<Offset?>(
        valueListenable: _externalDragFeedbackPosition,
        builder: (context, globalPosition, _) {
          final data = _externalDragData;
          if (data == null || globalPosition == null) {
            return const SizedBox.shrink();
          }
          final overlaySize = MediaQuery.sizeOf(context);
          final feedbackWidth = _visibleTabWidth.clamp(144.0, 248.0);
          const feedbackHeight = 36.0;
          final left = (globalPosition.dx - feedbackWidth / 2)
              .clamp(8.0, math.max(8.0, overlaySize.width - feedbackWidth - 8))
              .toDouble();
          final top = (globalPosition.dy - feedbackHeight / 2)
              .clamp(
                8.0,
                math.max(8.0, overlaySize.height - feedbackHeight - 8),
              )
              .toDouble();
          return Positioned(
            left: left,
            top: top,
            width: feedbackWidth,
            height: feedbackHeight,
            child: _ShellExternalTabDragFeedback(
              key: Key('shell-external-tab-drag-feedback-${data.sessionId}'),
              title: data.title,
              palette: widget.palette,
            ),
          );
        },
      ),
    );
    _externalDragFeedbackOverlay = entry;
    overlay.insert(entry);
  }

  void _removeExternalDragFeedbackOverlay() {
    final entry = _externalDragFeedbackOverlay;
    _externalDragFeedbackOverlay = null;
    if (entry == null) {
      return;
    }
    // An inserted OverlayEntry can still report `mounted == false` before its
    // first overlay build. It nevertheless has an owner and must be removed
    // before disposal.
    entry.remove();
    entry.dispose();
  }

  void _clearExternalDragVisuals() {
    if (_externalDragOutsideStrip.value) {
      _externalDragOutsideStrip.value = false;
    }
    _externalDragFeedbackPosition.value = null;
    _removeExternalDragFeedbackOverlay();
  }

  void _handleDragPointerCancel() {
    _dragCompletionTimer?.cancel();
    _dragCompletionTimer = null;
    _activeReorderListState = null;
    final data = _externalDragData;
    if (_draggingSessionId == null && data == null) {
      return;
    }
    setState(() {
      _draggingSessionId = null;
    });
    _externalDragData = null;
    _lastDragGlobalPosition = null;
    _clearExternalDragVisuals();
    if (data != null) {
      widget.onSessionDragCancelled(data);
    }
  }

  bool get _usesDelayedDragStart {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final chromeBackground = _ShellTabTone.chromeBaseFor(
      widget.palette,
      widget.chromeBackgroundColor,
    );
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      palette: widget.palette,
    );
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SizedBox(
        key: const Key('shell-tab-strip'),
        height: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 0.0;
            final actionButtonWidth = math.min(
              _tabActionButtonWidth,
              totalWidth,
            );
            final initialTabsAreaWidth = widget.showNewTabAction
                ? math.max(0.0, totalWidth - actionButtonWidth)
                : totalWidth;
            final initialVisibleTabCount = _visibleTabCountFor(
              initialTabsAreaWidth,
            );
            final needsOverflowAction =
                initialVisibleTabCount < widget.tabs.length;
            final tabsAreaWidth =
                !widget.showNewTabAction && needsOverflowAction
                ? math.max(0.0, totalWidth - actionButtonWidth)
                : initialTabsAreaWidth;
            final visibleTabCount = needsOverflowAction
                ? _visibleTabCountFor(tabsAreaWidth)
                : initialVisibleTabCount;
            _visibleTabCount = visibleTabCount;
            final hasOverflow = visibleTabCount < widget.tabs.length;
            final hiddenTabs = hasOverflow
                ? widget.tabs.skip(visibleTabCount).toList(growable: false)
                : const <TerminalTab>[];
            final visibleTabsCapacity = tabsAreaWidth;
            final tabWidth = visibleTabCount == 0
                ? 0.0
                : visibleTabsCapacity / visibleTabCount;
            _visibleTabWidth = tabWidth;
            final compactTabs = tabWidth < _compactTabThreshold;
            final visibleTabsWidth = tabWidth * visibleTabCount;

            return Row(
              children: [
                SizedBox(
                  width: visibleTabsWidth,
                  child: _ShellTabDropTrack(
                    insertionIndex: widget.paneDropInsertionIndex,
                    tabWidth: tabWidth,
                    visibleTabsWidth: visibleTabsWidth,
                    color: widget.palette.focusRing,
                    child: visibleTabCount == 0
                        ? const SizedBox.expand()
                        : ReorderableListView.builder(
                            scrollDirection: Axis.horizontal,
                            buildDefaultDragHandles: false,
                            padding: EdgeInsets.zero,
                            proxyDecorator: (child, index, animation) =>
                                _ShellTabDragProxy(
                                  animation: animation,
                                  externalDragOutsideStrip:
                                      _externalDragOutsideStrip,
                                  child: child,
                                ),
                            onReorderStart: (index) {
                              if (index >= visibleTabCount) {
                                return;
                              }
                              _dragCompletionTimer?.cancel();
                              _dragCompletionTimer = null;
                              unawaited(HapticFeedback.selectionClick());
                              setState(() {
                                _draggingSessionId =
                                    widget.tabs[index].sessionId;
                              });
                              final tab = widget.tabs[index];
                              if (tab.effectivePanes.length == 1) {
                                final pane = tab.effectivePanes.single;
                                final data = _ShellSessionDragData(
                                  sessionId: pane.sessionId,
                                  title: pane.title,
                                  origin: _ShellSessionDragOrigin.tab,
                                );
                                _externalDragData = data;
                                _externalDragOutsideStrip.value = false;
                                _insertExternalDragFeedbackOverlay();
                                widget.onSessionDragStarted(data);
                                final globalPosition = _lastDragGlobalPosition;
                                if (globalPosition != null) {
                                  _handleDragPointerPosition(globalPosition);
                                }
                              }
                            },
                            onReorderEnd: (_) {
                              if (_draggingSessionId == null &&
                                  _externalDragData == null) {
                                return;
                              }
                              final data = _externalDragData;
                              final externalDrop =
                                  data != null &&
                                  _externalDragOutsideStrip.value;
                              final reorderListState = _activeReorderListState;
                              _activeReorderListState = null;
                              if (externalDrop) {
                                reorderListState?.cancelReorder();
                              }
                              setState(() {
                                _draggingSessionId = null;
                              });
                              _externalDragData = null;
                              _lastDragGlobalPosition = null;
                              _clearExternalDragVisuals();
                              if (data != null) {
                                if (externalDrop) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      widget.onSessionDragEnded(data);
                                    }
                                  });
                                } else {
                                  _dragCompletionTimer = Timer(
                                    const Duration(milliseconds: 280),
                                    () {
                                      _dragCompletionTimer = null;
                                      if (mounted) {
                                        widget.onSessionDragEnded(data);
                                      }
                                    },
                                  );
                                }
                              }
                            },
                            onReorderItem: (oldIndex, newIndex) =>
                                widget.onReorderTab(
                                  oldIndex: oldIndex,
                                  newIndex: newIndex,
                                ),
                            itemCount: visibleTabCount,
                            itemBuilder: (context, index) {
                              final tab = widget.tabs[index];
                              final isActive =
                                  widget.activeSessionId != null &&
                                  tab.containsSession(widget.activeSessionId!);
                              final isDragging =
                                  _draggingSessionId == tab.sessionId;
                              final shortcutIndex = !compactTabs && index < 9
                                  ? index + 1
                                  : null;
                              return _ShellReorderableTabItem(
                                key: ValueKey(
                                  'shell-tab-reorder-${tab.sessionId}',
                                ),
                                width: tabWidth,
                                child: FocusTraversalOrder(
                                  order: NumericFocusOrder(index.toDouble()),
                                  child: _ShellTabButton(
                                    palette: widget.palette,
                                    tab: tab,
                                    shortcutIndex: shortcutIndex,
                                    isActive: isActive,
                                    hasNewOutput: widget.tabHasNewOutput(tab),
                                    newOutputTooltip: widget
                                        .tabNewOutputTooltip(tab),
                                    newOutputPaneSessionId: widget
                                        .tabNewOutputPaneSessionId(tab),
                                    tabColor: widget.tabColor(tab),
                                    compact: compactTabs,
                                    chromeBackgroundColor: chromeBackground,
                                    focusNode: _focusNodeForTab(tab),
                                    dragRegionBuilder: (child) =>
                                        _ShellTabDragStartRegion(
                                          key: Key(
                                            'shell-tab-drag-${tab.sessionId}',
                                          ),
                                          index: index,
                                          useDelayedStart:
                                              _usesDelayedDragStart,
                                          isDragging: isDragging,
                                          onReorderListResolved: (state) {
                                            _activeReorderListState = state;
                                          },
                                          onPointerPosition:
                                              _handleDragPointerPosition,
                                          onPointerCancel:
                                              _handleDragPointerCancel,
                                          child: child,
                                        ),
                                    onActivate: () => widget.onActivateSession(
                                      tab.activeSessionId,
                                    ),
                                    onActivateBadgePane: (sessionId) =>
                                        widget.onActivateBadgePane(sessionId),
                                    onNotificationInteraction:
                                        widget.onNotificationInteraction,
                                    onActivateNewOutputPane: (sessionId) =>
                                        widget.onActivateNewOutputPane(
                                          sessionId,
                                        ),
                                    onClose: () =>
                                        widget.onCloseSession(tab.sessionId),
                                    onShowContextMenu: (position) => widget
                                        .onShowTabContextMenu(tab, position),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                if (visibleTabsWidth < tabsAreaWidth)
                  const Expanded(child: SizedBox()),
                if (hasOverflow)
                  _ShellTabOverflowMenu(
                    palette: widget.palette,
                    chromeBackgroundColor: chromeBackground,
                    tabs: hiddenTabs,
                    activeSessionId: widget.activeSessionId,
                    tabHasNewOutput: widget.tabHasNewOutput,
                    tabNewOutputTooltip: widget.tabNewOutputTooltip,
                    hiddenTabsNewOutputTooltip:
                        widget.hiddenTabsNewOutputTooltip,
                    hiddenTabsNewOutputPaneSessionId:
                        widget.hiddenTabsNewOutputPaneSessionId,
                    tabNewOutputPaneSessionId: widget.tabNewOutputPaneSessionId,
                    tabBackgroundColor: (_) => chromeBackground,
                    tabColor: widget.tabColor,
                    onActivateSession: widget.onActivateSession,
                    onActivateBadgePane: widget.onActivateBadgePane,
                    onNotificationInteraction: widget.onNotificationInteraction,
                    onActivateNewOutputPane: widget.onActivateNewOutputPane,
                    width: actionButtonWidth,
                  ),
                if (!hasOverflow &&
                    widget.showNewTabAction &&
                    actionButtonWidth > 0)
                  _ShellNewTabButton(
                    palette: widget.palette,
                    tone: chromeTone,
                    width: actionButtonWidth,
                    onPressed: widget.onNewTab,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  int _visibleTabCountFor(double tabsAreaWidth) {
    final tabCount = widget.tabs.length;
    if (tabCount == 0 || tabsAreaWidth <= 0) {
      return 0;
    }
    if (tabsAreaWidth / tabCount >= _regularMinTabWidth) {
      return tabCount;
    }
    if (tabsAreaWidth / tabCount >= _compactMinTabWidth) {
      return tabCount;
    }
    final regularVisibleCapacity = tabsAreaWidth ~/ _regularMinTabWidth;
    if (regularVisibleCapacity > 0) {
      return math.min(tabCount - 1, regularVisibleCapacity);
    }
    final compactVisibleCapacity = tabsAreaWidth ~/ _compactMinTabWidth;
    if (compactVisibleCapacity <= 0) {
      return 0;
    }
    return math.min(tabCount - 1, compactVisibleCapacity);
  }
}

class _ShellTabDropTrack extends StatelessWidget {
  const _ShellTabDropTrack({
    required this.insertionIndex,
    required this.tabWidth,
    required this.visibleTabsWidth,
    required this.color,
    required this.child,
  });

  final int? insertionIndex;
  final double tabWidth;
  final double visibleTabsWidth;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final index = insertionIndex;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: child),
        if (index != null && visibleTabsWidth > 0)
          Positioned(
            left: (tabWidth * index).clamp(
              1.0,
              math.max(1.0, visibleTabsWidth - 2),
            ),
            top: 2,
            bottom: 2,
            child: DecoratedBox(
              key: Key('shell-tab-drop-insertion-$index'),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox(width: 3),
            ),
          ),
      ],
    );
  }
}

class _ShellReorderableTabItem extends StatelessWidget {
  const _ShellReorderableTabItem({
    super.key,
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: child);
  }
}

class _ShellTabDragProxy extends StatelessWidget {
  const _ShellTabDragProxy({
    required this.animation,
    required this.externalDragOutsideStrip,
    required this.child,
  });

  final Animation<double> animation;
  final ValueListenable<bool> externalDragOutsideStrip;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _ShellDragProxyPaintVisibility(
      hidden: externalDragOutsideStrip,
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final lift = Curves.easeOutCubic.transform(animation.value);
          return Transform.scale(
            scale: 1 + lift * 0.018,
            child: Material(type: MaterialType.transparency, child: child),
          );
        },
      ),
    );
  }
}

class _ShellDragProxyPaintVisibility extends SingleChildRenderObjectWidget {
  const _ShellDragProxyPaintVisibility({
    required this.hidden,
    required super.child,
  });

  final ValueListenable<bool> hidden;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderShellDragProxyPaintVisibility(hidden);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderShellDragProxyPaintVisibility renderObject,
  ) {
    renderObject.hidden = hidden;
  }
}

class _RenderShellDragProxyPaintVisibility extends RenderProxyBox {
  _RenderShellDragProxyPaintVisibility(this._hidden);

  ValueListenable<bool> _hidden;

  set hidden(ValueListenable<bool> value) {
    if (identical(_hidden, value)) {
      return;
    }
    if (attached) {
      _hidden.removeListener(_handleVisibilityChanged);
    }
    _hidden = value;
    if (attached) {
      _hidden.addListener(_handleVisibilityChanged);
    }
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _hidden.addListener(_handleVisibilityChanged);
  }

  @override
  void detach() {
    _hidden.removeListener(_handleVisibilityChanged);
    super.detach();
  }

  void _handleVisibilityChanged() {
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hidden.value) {
      super.paint(context, offset);
    }
  }
}

class _ShellExternalTabDragFeedback extends StatelessWidget {
  const _ShellExternalTabDragFeedback({
    super.key,
    required this.title,
    required this.palette,
  });

  final String title;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final background = Color.alphaBlend(
      palette.focusRing.withValues(alpha: 0.07),
      palette.panelElevated,
    );
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(
              color: palette.borderStrong.withValues(alpha: 0.82),
            ),
            boxShadow: palette.elevation.floating,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 15,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 15,
                  color: palette.textSubtle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabDragStartRegion extends StatelessWidget {
  const _ShellTabDragStartRegion({
    super.key,
    required this.index,
    required this.useDelayedStart,
    required this.isDragging,
    required this.onReorderListResolved,
    required this.onPointerPosition,
    required this.onPointerCancel,
    required this.child,
  });

  final int index;
  final bool useDelayedStart;
  final bool isDragging;
  final ValueChanged<SliverReorderableListState?> onReorderListResolved;
  final ValueChanged<Offset> onPointerPosition;
  final VoidCallback onPointerCancel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dragStartListener = useDelayedStart
        ? ReorderableDelayedDragStartListener(index: index, child: child)
        : ReorderableDragStartListener(index: index, child: child);
    return MouseRegion(
      cursor: isDragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          onReorderListResolved(SliverReorderableList.maybeOf(context));
          onPointerPosition(event.position);
        },
        onPointerMove: (event) => onPointerPosition(event.position),
        onPointerCancel: (_) => onPointerCancel(),
        child: dragStartListener,
      ),
    );
  }
}

class _ShellNewTabButton extends StatelessWidget {
  const _ShellNewTabButton({
    required this.palette,
    required this.tone,
    required this.width,
    required this.onPressed,
  });

  final AppThemeTokens palette;
  final _ShellTabTone tone;
  final double width;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Center(
        child: _buildChromeIconButton(
          key: const Key('shell-chrome-new-tab'),
          tooltip: context.l10n.newTab,
          onPressed: onPressed,
          iconSize: 16,
          hoverBackgroundColor: tone.hoverBackground,
          icon: Icon(Icons.add_rounded, color: tone.subtleText),
        ),
      ),
    );
  }
}

class _ShellTabTone {
  const _ShellTabTone({
    required this.activeBackground,
    required this.trackBackground,
    required this.hoverBackground,
    required this.border,
    required this.primaryText,
    required this.mutedText,
    required this.subtleText,
  });

  final Color activeBackground;
  final Color trackBackground;
  final Color hoverBackground;
  final Color border;
  final Color primaryText;
  final Color mutedText;
  final Color subtleText;

  factory _ShellTabTone.fromTerminalBackground({
    required AppThemeTokens palette,
  }) {
    final chrome = palette.shellChrome;
    return _ShellTabTone(
      activeBackground: chrome.tabActiveBackground,
      trackBackground: chrome.tabTrackBackground,
      hoverBackground: chrome.tabHoverBackground,
      border: chrome.tabBorder,
      primaryText: chrome.tabTextPrimary,
      mutedText: chrome.tabTextMuted,
      subtleText: chrome.tabTextSubtle,
    );
  }

  static Color chromeBaseFor(AppThemeTokens palette, Color background) {
    return palette.shellChrome.base;
  }

  static Color chromeSurfaceFor(AppThemeTokens palette, Color background) {
    return palette.shellChrome.surface;
  }

  static Color railSurfaceFor(AppThemeTokens palette, Color background) {
    return palette.shellChrome.rail;
  }
}

class _ShellTabOverflowMenu extends StatefulWidget {
  const _ShellTabOverflowMenu({
    required this.palette,
    required this.chromeBackgroundColor,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabNewOutputTooltip,
    required this.hiddenTabsNewOutputTooltip,
    required this.hiddenTabsNewOutputPaneSessionId,
    required this.tabNewOutputPaneSessionId,
    required this.tabBackgroundColor,
    required this.tabColor,
    required this.onActivateSession,
    required this.onActivateBadgePane,
    required this.onNotificationInteraction,
    required this.onActivateNewOutputPane,
    required this.width,
  });

  final AppThemeTokens palette;
  final Color chromeBackgroundColor;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final String Function(TerminalTab tab) tabNewOutputTooltip;
  final String Function(Iterable<TerminalTab> tabs) hiddenTabsNewOutputTooltip;
  final String? Function(Iterable<TerminalTab> tabs)
  hiddenTabsNewOutputPaneSessionId;
  final String? Function(TerminalTab tab) tabNewOutputPaneSessionId;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final Color? Function(TerminalTab tab) tabColor;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onActivateBadgePane;
  final ValueChanged<_ShellNotificationInteraction> onNotificationInteraction;
  final ValueChanged<String> onActivateNewOutputPane;
  final double width;

  @override
  State<_ShellTabOverflowMenu> createState() => _ShellTabOverflowMenuState();
}

class _ShellTabOverflowMenuState extends State<_ShellTabOverflowMenu> {
  static const double _menuWidth = 168;
  static const double _menuMaxHeight = 332;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _hovered = false;

  @override
  void didUpdateWidget(_ShellTabOverflowMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_overlayEntry != null) {
      if (widget.tabs.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _closeMenu();
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _overlayEntry?.markNeedsBuild();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _removeMenuEntry();
    super.dispose();
  }

  void _toggleMenu() {
    if (_overlayEntry == null) {
      _openMenu();
    } else {
      _closeMenu();
    }
  }

  void _openMenu() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(widget.width - _menuWidth, 34),
            child: _ShellTabOverflowPanel(
              palette: widget.palette,
              width: _menuWidth,
              maxHeight: _menuMaxHeight,
              tabs: widget.tabs,
              activeSessionId: widget.activeSessionId,
              tabHasNewOutput: widget.tabHasNewOutput,
              tabNewOutputTooltip: widget.tabNewOutputTooltip,
              tabNewOutputPaneSessionId: widget.tabNewOutputPaneSessionId,
              tabBackgroundColor: widget.tabBackgroundColor,
              tabColor: widget.tabColor,
              onSelected: (sessionId) {
                _closeMenu();
                widget.onActivateSession(sessionId);
              },
              onBadgeSelected: (sessionId) {
                _closeMenu();
                widget.onActivateBadgePane(sessionId);
              },
              onNotificationInteraction: (interaction) {
                _closeMenu();
                widget.onNotificationInteraction(interaction);
              },
              onNewOutputPaneSelected: (sessionId) {
                _closeMenu();
                widget.onActivateNewOutputPane(sessionId);
              },
            ),
          ),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
    setState(() {});
  }

  void _closeMenu() {
    _removeMenuEntry();
    if (mounted) {
      setState(() {});
    }
  }

  void _removeMenuEntry() {
    final entry = _overlayEntry;
    if (entry == null) {
      return;
    }
    _overlayEntry = null;
    entry.remove();
  }

  @override
  Widget build(BuildContext context) {
    final activeHiddenTab = widget.activeSessionId == null
        ? null
        : widget.tabs.cast<TerminalTab?>().firstWhere(
            (tab) => tab!.containsSession(widget.activeSessionId!),
            orElse: () => null,
          );
    final isActive = activeHiddenTab != null;
    final isOpen = _overlayEntry != null;
    final hiddenOutputTabs = widget.tabs
        .where(widget.tabHasNewOutput)
        .toList(growable: false);
    final hasHiddenNewOutput = hiddenOutputTabs.isNotEmpty;
    final hiddenNewOutputPaneSessionId = widget
        .hiddenTabsNewOutputPaneSessionId(hiddenOutputTabs);
    final hiddenBadgeTargets = _shellHiddenTabBadgeTargets(
      widget.tabs,
      activeSessionId: widget.activeSessionId,
    );
    final hasHiddenBadges = hiddenBadgeTargets.isNotEmpty;
    final hiddenPaneSignalTargets = _shellHiddenTabPaneSignalTargets(
      context.l10n,
      widget.tabs,
      activeSessionId: widget.activeSessionId,
    );
    final hasHiddenPaneSignals = hiddenPaneSignalTargets.isNotEmpty;
    final activeTone = activeHiddenTab == null
        ? null
        : _ShellTabTone.fromTerminalBackground(palette: widget.palette);
    final chromeTone = _ShellTabTone.fromTerminalBackground(
      palette: widget.palette,
    );
    final background = isActive
        ? activeTone!.activeBackground
        : _hovered || isOpen
        ? chromeTone.hoverBackground
        : Colors.transparent;
    final overflowTooltip = _hiddenTabsOverflowButtonTooltip(
      context.l10n,
      hiddenTabCount: widget.tabs.length,
      badgePaneCount: hiddenBadgeTargets.length,
      paneSignalCount: hiddenPaneSignalTargets.length,
      newOutputTabCount: hiddenOutputTabs.length,
    );
    final overflowSemanticsLabel = _hiddenTabsOverflowButtonSemanticsLabel(
      context.l10n,
      hiddenTabCount: widget.tabs.length,
      badgePaneCount: hiddenBadgeTargets.length,
      paneSignalCount: hiddenPaneSignalTargets.length,
      newOutputTabCount: hiddenOutputTabs.length,
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: overflowTooltip,
        child: SizedBox(
          width: widget.width,
          height: double.infinity,
          child: Semantics(
            label: overflowSemanticsLabel,
            button: true,
            selected: isActive,
            expanded: isOpen,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                key: const Key('shell-tab-overflow-button'),
                behavior: HitTestBehavior.opaque,
                onTap: _toggleMenu,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isActive || _hovered || isOpen
                            ? (activeTone?.border ?? chromeTone.border)
                                  .withValues(alpha: isActive ? 0.34 : 0.18)
                            : Colors.transparent,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          key: const Key('shell-tab-overflow-ellipsis'),
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: isActive
                              ? activeTone!.primaryText
                              : chromeTone.subtleText,
                        ),
                        if (!isOpen && hasHiddenBadges)
                          Positioned(
                            top: 2,
                            left: 2,
                            width: 10,
                            height: 10,
                            child: _ShellTabOverflowBadgeMarker(
                              key: const Key('shell-tab-overflow-badge'),
                              palette: widget.palette,
                              tooltip: _hiddenTabsBadgeTooltip(
                                context.l10n,
                                hiddenBadgeTargets,
                                activeSessionId: widget.activeSessionId,
                              ),
                              onPressed: () {
                                _closeMenu();
                                widget.onActivateBadgePane(
                                  hiddenBadgeTargets.first.badge.sessionId,
                                );
                              },
                            ),
                          ),
                        if (!isOpen && hasHiddenPaneSignals)
                          Positioned(
                            bottom: 2,
                            left: 2,
                            width: 10,
                            height: 10,
                            child: _ShellTabOverflowSignalMarker(
                              key: const Key('shell-tab-overflow-pane-signal'),
                              palette: widget.palette,
                              tooltip: _hiddenTabsPaneSignalTooltip(
                                context.l10n,
                                hiddenPaneSignalTargets,
                                activeSessionId: widget.activeSessionId,
                              ),
                              onPressed: () {
                                _closeMenu();
                                widget.onActivateBadgePane(
                                  hiddenPaneSignalTargets
                                      .first
                                      .signal
                                      .sessionId,
                                );
                              },
                            ),
                          ),
                        if (!isOpen && hasHiddenNewOutput)
                          Positioned(
                            top: 0,
                            right: -2,
                            child: _ShellTabNewOutputDot(
                              key: const Key('shell-tab-overflow-new-output'),
                              palette: widget.palette,
                              tooltip: widget.hiddenTabsNewOutputTooltip(
                                hiddenOutputTabs,
                              ),
                              onPressed: hiddenNewOutputPaneSessionId == null
                                  ? null
                                  : () {
                                      _closeMenu();
                                      widget.onActivateNewOutputPane(
                                        hiddenNewOutputPaneSessionId,
                                      );
                                    },
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
      ),
    );
  }
}

class _ShellTabOverflowPanel extends StatelessWidget {
  const _ShellTabOverflowPanel({
    required this.palette,
    required this.width,
    required this.maxHeight,
    required this.tabs,
    required this.activeSessionId,
    required this.tabHasNewOutput,
    required this.tabNewOutputTooltip,
    required this.tabNewOutputPaneSessionId,
    required this.tabBackgroundColor,
    required this.tabColor,
    required this.onSelected,
    required this.onBadgeSelected,
    required this.onNotificationInteraction,
    required this.onNewOutputPaneSelected,
  });

  final AppThemeTokens palette;
  final double width;
  final double maxHeight;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool Function(TerminalTab tab) tabHasNewOutput;
  final String Function(TerminalTab tab) tabNewOutputTooltip;
  final String? Function(TerminalTab tab) tabNewOutputPaneSessionId;
  final Color Function(TerminalTab tab) tabBackgroundColor;
  final Color? Function(TerminalTab tab) tabColor;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onBadgeSelected;
  final ValueChanged<_ShellNotificationInteraction> onNotificationInteraction;
  final ValueChanged<String> onNewOutputPaneSelected;

  @override
  Widget build(BuildContext context) {
    final menuRadius = BorderRadius.circular(palette.radius.sm);

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: Directionality(
        textDirection: Directionality.of(context),
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: DecoratedBox(
              key: const Key('shell-tab-overflow-panel'),
              decoration: BoxDecoration(
                color: palette.panelElevated.withValues(alpha: 0.98),
                border: Border.all(
                  color: palette.borderStrong.withValues(alpha: 0.54),
                ),
                borderRadius: menuRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: menuRadius,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final tab in tabs)
                        _ShellTabOverflowRow(
                          key: Key('shell-tab-overflow-item-${tab.sessionId}'),
                          palette: palette,
                          tab: tab,
                          isActive:
                              activeSessionId != null &&
                              tab.containsSession(activeSessionId!),
                          hasNewOutput: tabHasNewOutput(tab),
                          newOutputTooltip: tabNewOutputTooltip(tab),
                          newOutputPaneSessionId: tabNewOutputPaneSessionId(
                            tab,
                          ),
                          terminalBackgroundColor: tabBackgroundColor(tab),
                          tabColor: tabColor(tab),
                          onSelected: () => onSelected(tab.activeSessionId),
                          onBadgeSelected: onBadgeSelected,
                          onNotificationInteraction: onNotificationInteraction,
                          onNewOutputPaneSelected: onNewOutputPaneSelected,
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

class _ShellTabOverflowRow extends StatefulWidget {
  const _ShellTabOverflowRow({
    super.key,
    required this.palette,
    required this.tab,
    required this.isActive,
    required this.hasNewOutput,
    required this.newOutputTooltip,
    required this.newOutputPaneSessionId,
    required this.terminalBackgroundColor,
    required this.tabColor,
    required this.onSelected,
    required this.onBadgeSelected,
    required this.onNotificationInteraction,
    required this.onNewOutputPaneSelected,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final bool isActive;
  final bool hasNewOutput;
  final String newOutputTooltip;
  final String? newOutputPaneSessionId;
  final Color terminalBackgroundColor;
  final Color? tabColor;
  final VoidCallback onSelected;
  final ValueChanged<String> onBadgeSelected;
  final ValueChanged<_ShellNotificationInteraction> onNotificationInteraction;
  final ValueChanged<String> onNewOutputPaneSelected;

  @override
  State<_ShellTabOverflowRow> createState() => _ShellTabOverflowRowState();
}

class _ShellTabOverflowRowState extends State<_ShellTabOverflowRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final title = _shellTabDisplayTitle(widget.tab);
    final badgeInfos = _shellTabBadgeInfos(widget.tab);
    final paneSignalInfos = _shellTabPaneSignalInfos(context.l10n, widget.tab);
    final paneSignalInfo = paneSignalInfos.isEmpty
        ? null
        : paneSignalInfos.first;
    final runtimeError = _shellTabRuntimeError(widget.tab);
    final canActivateBadgePane = widget.tab.effectivePanes.length > 1;
    final tabStatus = widget.tab.activePane.tabStatus;
    final indicatorColor = terminalViewportColorFromHex(tabStatus.indicator);
    final statusText = _normalizedShellTabStatusText(tabStatus.status);
    final requestedStatusColor = terminalViewportColorFromHex(
      tabStatus.statusColor,
    );
    final tone = _ShellTabTone.fromTerminalBackground(palette: widget.palette);
    final background = widget.isActive
        ? widget.palette.focus
        : _hovered
        ? tone.hoverBackground
        : Colors.transparent;
    final textColor = widget.isActive ? Colors.white : widget.palette.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: widget.isActive
                          ? Colors.white
                          : Colors.transparent,
                    ),
                    if (widget.hasNewOutput)
                      Align(
                        alignment: widget.isActive
                            ? Alignment.bottomRight
                            : Alignment.center,
                        child: _ShellTabNewOutputDot(
                          key: Key(
                            'shell-tab-new-output-${widget.tab.sessionId}',
                          ),
                          palette: widget.palette,
                          tooltip: widget.newOutputTooltip,
                          onPressed: widget.newOutputPaneSessionId == null
                              ? null
                              : () => widget.onNewOutputPaneSelected(
                                  widget.newOutputPaneSessionId!,
                                ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.tabColor == null)
                const SizedBox(width: 7)
              else ...[
                const SizedBox(width: 5),
                Tooltip(
                  message: context.l10n.profileTabColor,
                  child: DecoratedBox(
                    key: Key(
                      'shell-tab-overflow-color-${widget.tab.sessionId}',
                    ),
                    decoration: BoxDecoration(
                      color: widget.tabColor,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: widget.palette.textPrimary.withValues(
                          alpha: 0.22,
                        ),
                      ),
                    ),
                    child: const SizedBox.square(dimension: 8),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (indicatorColor != null) ...[
                Tooltip(
                  message: context.l10n.osc21337StatusIndicator,
                  child: DecoratedBox(
                    key: Key(
                      'shell-tab-overflow-status-indicator-${widget.tab.sessionId}',
                    ),
                    decoration: BoxDecoration(
                      color: indicatorColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.palette.textPrimary.withValues(
                          alpha: 0.28,
                        ),
                      ),
                    ),
                    child: const SizedBox.square(dimension: 8),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (runtimeError != null) ...[
                _ShellTabRuntimeErrorIcon(
                  key: Key('shell-tab-overflow-error-${widget.tab.sessionId}'),
                  palette: widget.palette,
                  error: runtimeError,
                  size: 14,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontSize: 12,
                    height: 1,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
              if (statusText != null) ...[
                const SizedBox(width: 6),
                _ShellTabStatusLabel(
                  key: Key('shell-tab-overflow-status-${widget.tab.sessionId}'),
                  text: statusText,
                  requestedColor: requestedStatusColor,
                  backgroundColor: background == Colors.transparent
                      ? widget.terminalBackgroundColor
                      : background,
                  fallbackColor: textColor,
                  maxWidth: 72,
                ),
              ],
              ..._shellTabBadgeChips(
                l10n: context.l10n,
                keyPrefix: 'shell-tab-overflow-badge-${widget.tab.sessionId}',
                tab: widget.tab,
                badges: badgeInfos,
                palette: widget.palette,
                foreground: textColor,
                background: widget.palette.panel.withValues(
                  alpha: widget.isActive ? 0.32 : 0.64,
                ),
                border: widget.palette.textPrimary.withValues(alpha: 0.20),
                maxWidth: 54,
                badgeNeedsFocus: (badge) =>
                    !(widget.isActive && badge.isActivePane),
                onSelected: canActivateBadgePane
                    ? widget.onBadgeSelected
                    : null,
              ),
              if (paneSignalInfo != null) ...[
                const SizedBox(width: 6),
                _ShellTabPaneSignalChip(
                  itemKey: Key(
                    'shell-tab-overflow-pane-signal-${widget.tab.sessionId}',
                  ),
                  palette: widget.palette,
                  tab: widget.tab,
                  signals: paneSignalInfos,
                  primaryNeedsFocus:
                      !(widget.isActive && paneSignalInfo.isActivePane),
                  onActivatePane: widget.onBadgeSelected,
                  onNotificationInteraction: widget.onNotificationInteraction,
                  foreground: textColor,
                  background: widget.palette.focusRing.withValues(
                    alpha: widget.isActive ? 0.34 : 0.58,
                  ),
                  border: widget.palette.focusRing.withValues(alpha: 0.34),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellTabOverflowBadgeMarker extends StatelessWidget {
  const _ShellTabOverflowBadgeMarker({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.onPressed,
  });

  final AppThemeTokens palette;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        label: tooltip,
        button: true,
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 10,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.warningContainer.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: palette.warning.withValues(alpha: 0.78),
                    ),
                  ),
                  child: Icon(
                    Icons.badge_outlined,
                    size: 7,
                    color: palette.warning,
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

class _ShellTabOverflowSignalMarker extends StatelessWidget {
  const _ShellTabOverflowSignalMarker({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.onPressed,
  });

  final AppThemeTokens palette;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        label: tooltip,
        button: true,
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 10,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.focusRing.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: palette.textPrimary.withValues(alpha: 0.36),
                    ),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 7,
                    color: palette.panel,
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

class _ShellTabNewOutputDot extends StatelessWidget {
  const _ShellTabNewOutputDot({
    super.key,
    required this.palette,
    required this.tooltip,
    this.onPressed,
  });

  final AppThemeTokens palette;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final marker = Semantics(
      container: true,
      label: tooltip,
      button: onPressed != null,
      onTap: onPressed,
      child: SizedBox.square(
        dimension: 14,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.focus,
              shape: BoxShape.circle,
              border: Border.all(
                color: palette.textPrimary.withValues(alpha: 0.36),
              ),
            ),
            child: const SizedBox.square(dimension: 7),
          ),
        ),
      ),
    );
    final tooltipMarker = Tooltip(message: tooltip, child: marker);
    if (onPressed == null) {
      return tooltipMarker;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: tooltipMarker,
      ),
    );
  }
}

class _ShellTabRuntimeErrorIcon extends StatelessWidget {
  const _ShellTabRuntimeErrorIcon({
    super.key,
    required this.palette,
    required this.error,
    this.size = 13,
  });

  final AppThemeTokens palette;
  final TerminalPaneRuntimeErrorState error;
  final double size;

  @override
  Widget build(BuildContext context) {
    final message = context.l10n.terminalTabError(error.message);
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        child: Icon(
          Icons.error_outline_rounded,
          size: size,
          color: palette.danger,
        ),
      ),
    );
  }
}

class _ShellTabBadgeChip extends StatelessWidget {
  const _ShellTabBadgeChip({
    super.key,
    required this.palette,
    required this.text,
    required this.tooltip,
    required this.semanticsLabel,
    required this.foreground,
    required this.background,
    required this.border,
    this.maxWidth = 72,
    this.semanticsButton = false,
    this.onPressed,
  });

  final AppThemeTokens palette;
  final String text;
  final String tooltip;
  final String semanticsLabel;
  final Color foreground;
  final Color background;
  final Color border;
  final double maxWidth;
  final bool semanticsButton;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final onPressed = this.onPressed;
    final chip = Tooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        label: semanticsLabel,
        button: onPressed != null || semanticsButton,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontSize: 9.5,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (onPressed == null) {
      return chip;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: chip,
      ),
    );
  }
}

class _ShellTabPaneSignalChip extends StatelessWidget {
  const _ShellTabPaneSignalChip({
    required this.itemKey,
    required this.palette,
    required this.tab,
    required this.signals,
    required this.primaryNeedsFocus,
    required this.onActivatePane,
    required this.onNotificationInteraction,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Key itemKey;
  final AppThemeTokens palette;
  final TerminalTab tab;
  final List<_ShellTabPaneSignalInfo> signals;
  final bool primaryNeedsFocus;
  final ValueChanged<String> onActivatePane;
  final ValueChanged<_ShellNotificationInteraction> onNotificationInteraction;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final primary = signals.first;
    final notificationTargets = _shellTabNotificationTargets(tab);
    final tooltip = _shellTabPaneSignalTooltip(
      context.l10n,
      tab,
      primary,
      signals,
      primaryNeedsFocus: primaryNeedsFocus,
    );
    final semanticsLabel = _shellTabPaneSignalSemanticsLabel(
      context.l10n,
      tab,
      primary,
      signals,
      primaryNeedsFocus: primaryNeedsFocus,
    );
    final chip = _ShellTabBadgeChip(
      key: notificationTargets.isEmpty ? itemKey : null,
      palette: palette,
      text: _shellTabPaneSignalLabel(context.l10n, signals),
      tooltip: tooltip,
      semanticsLabel: semanticsLabel,
      semanticsButton: notificationTargets.isNotEmpty,
      onPressed: notificationTargets.isEmpty
          ? () => onActivatePane(primary.sessionId)
          : null,
      foreground: foreground,
      background: background,
      border: border,
    );
    if (notificationTargets.isEmpty) {
      return chip;
    }

    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(palette.radius.md),
      side: BorderSide(color: palette.borderStrong.withValues(alpha: 0.58)),
    );
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: palette.panelElevated,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: menuShape,
        ),
      ),
      child: PopupMenuButton<_ShellNotificationInteraction>(
        key: itemKey,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        offset: Offset(0, palette.spacing.xs),
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
        color: palette.panelElevated,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: menuShape,
        onSelected: onNotificationInteraction,
        itemBuilder: (context) => _shellTabNotificationMenuEntries(
          notificationTargets,
          palette,
          context.l10n,
        ),
        child: chip,
      ),
    );
  }
}

List<PopupMenuEntry<_ShellNotificationInteraction>>
_shellTabNotificationMenuEntries(
  List<_ShellTabNotificationTarget> targets,
  AppThemeTokens palette,
  AppLocalizations l10n,
) {
  final visibleTargets = targets.take(6).toList(growable: false);
  return <PopupMenuEntry<_ShellNotificationInteraction>>[
    for (var index = 0; index < visibleTargets.length; index += 1) ...[
      if (index > 0) const PopupMenuDivider(height: 8),
      PopupMenuItem<_ShellNotificationInteraction>(
        key: Key('shell-tab-notification-$index-activate'),
        value: _ShellNotificationInteraction.activate(
          visibleTargets[index].sessionId,
          visibleTargets[index].notification,
        ),
        enabled: visibleTargets[index].notification.reportActivation,
        height: 52,
        child: _ShellTabNotificationMenuText(
          title: _shellTabNotificationMenuTitle(
            visibleTargets[index].notification,
          ),
          subtitle: _shellTabNotificationMenuSubtitle(visibleTargets[index]),
          palette: palette,
        ),
      ),
      for (
        var buttonIndex = 0;
        buttonIndex < visibleTargets[index].notification.buttons.length;
        buttonIndex += 1
      )
        PopupMenuItem<_ShellNotificationInteraction>(
          key: Key('shell-tab-notification-$index-button-${buttonIndex + 1}'),
          value: _ShellNotificationInteraction.button(
            visibleTargets[index].sessionId,
            visibleTargets[index].notification,
            buttonIndex + 1,
          ),
          enabled: visibleTargets[index].notification.reportActivation,
          height: 40,
          child: _ShellTabNotificationMenuText(
            title:
                visibleTargets[index].notification.buttons[buttonIndex].isEmpty
                ? l10n.notificationButton(buttonIndex + 1)
                : visibleTargets[index].notification.buttons[buttonIndex],
            subtitle: l10n.notificationAction(buttonIndex + 1),
            palette: palette,
          ),
        ),
      if (visibleTargets[index].notification.source == 'osc99' &&
          visibleTargets[index].notification.identifier != null)
        PopupMenuItem<_ShellNotificationInteraction>(
          key: Key('shell-tab-notification-$index-dismiss'),
          value: _ShellNotificationInteraction.dismiss(
            visibleTargets[index].sessionId,
            visibleTargets[index].notification,
          ),
          height: 40,
          child: _ShellTabNotificationMenuText(
            title: l10n.dismiss,
            subtitle: visibleTargets[index].notification.reportClose
                ? l10n.closeAndReportToTerminal
                : l10n.removeNotification,
            palette: palette,
          ),
        ),
    ],
  ];
}

class _ShellTabNotificationMenuText extends StatelessWidget {
  const _ShellTabNotificationMenuText({
    required this.title,
    required this.subtitle,
    required this.palette,
  });

  final String title;
  final String subtitle;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ],
    );
  }
}

List<Widget> _shellTabBadgeChips({
  required AppLocalizations l10n,
  required String keyPrefix,
  required TerminalTab tab,
  required List<_ShellTabBadgeInfo> badges,
  required AppThemeTokens palette,
  required Color foreground,
  required Color background,
  required Color border,
  required double maxWidth,
  required bool Function(_ShellTabBadgeInfo badge) badgeNeedsFocus,
  required ValueChanged<String>? onSelected,
}) {
  if (badges.isEmpty) {
    return const <Widget>[];
  }
  const visibleBadgeLimit = 2;
  final visibleBadges = badges.take(visibleBadgeLimit).toList(growable: false);
  final hiddenBadges = badges.skip(visibleBadgeLimit).toList(growable: false);
  final chips = <Widget>[];

  for (var index = 0; index < visibleBadges.length; index += 1) {
    final badge = visibleBadges[index];
    chips.add(const SizedBox(width: 6));
    chips.add(
      _ShellTabBadgeChip(
        key: Key(index == 0 ? keyPrefix : '$keyPrefix-${badge.sessionId}'),
        palette: palette,
        text: _shellTabBadgeLabel(badge.text, badgeCount: 1),
        tooltip: _shellTabBadgeTooltip(
          l10n,
          tab,
          badge,
          badges,
          badgeNeedsFocus: badgeNeedsFocus(badge),
        ),
        semanticsLabel: _shellTabBadgeSemanticsLabel(
          l10n,
          tab,
          badge,
          badges,
          badgeNeedsFocus: badgeNeedsFocus(badge),
        ),
        onPressed: onSelected == null
            ? null
            : () => onSelected(badge.sessionId),
        foreground: foreground,
        background: background,
        border: border,
        maxWidth: maxWidth,
      ),
    );
  }

  if (hiddenBadges.isNotEmpty) {
    final firstHidden = hiddenBadges.first;
    chips.add(const SizedBox(width: 6));
    chips.add(
      _ShellTabBadgeChip(
        key: Key('$keyPrefix-more'),
        palette: palette,
        text: '+${hiddenBadges.length}',
        tooltip: _shellTabBadgeOverflowTooltip(
          l10n,
          tab,
          hiddenBadges,
          badgeNeedsFocus,
        ),
        semanticsLabel: _shellTabBadgeOverflowSemanticsLabel(
          l10n,
          tab,
          hiddenBadges,
          badgeNeedsFocus,
        ),
        onPressed: onSelected == null
            ? null
            : () => onSelected(firstHidden.sessionId),
        foreground: foreground,
        background: background,
        border: border,
        maxWidth: 34,
      ),
    );
  }

  return chips;
}

class _ShellTabButton extends StatefulWidget {
  const _ShellTabButton({
    required this.palette,
    required this.tab,
    required this.shortcutIndex,
    required this.isActive,
    required this.hasNewOutput,
    required this.newOutputTooltip,
    required this.newOutputPaneSessionId,
    required this.tabColor,
    required this.compact,
    required this.chromeBackgroundColor,
    required this.focusNode,
    required this.dragRegionBuilder,
    required this.onActivate,
    required this.onActivateBadgePane,
    required this.onNotificationInteraction,
    required this.onActivateNewOutputPane,
    required this.onClose,
    required this.onShowContextMenu,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
  final bool isActive;
  final bool hasNewOutput;
  final String newOutputTooltip;
  final String? newOutputPaneSessionId;
  final Color? tabColor;
  final bool compact;
  final Color chromeBackgroundColor;
  final FocusNode focusNode;
  final Widget Function(Widget child) dragRegionBuilder;
  final VoidCallback onActivate;
  final ValueChanged<String> onActivateBadgePane;
  final ValueChanged<_ShellNotificationInteraction> onNotificationInteraction;
  final ValueChanged<String> onActivateNewOutputPane;
  final VoidCallback onClose;
  final ValueChanged<Offset> onShowContextMenu;

  @override
  State<_ShellTabButton> createState() => _ShellTabButtonState();
}

class _ShellTabButtonState extends State<_ShellTabButton> {
  bool _hovered = false;

  Widget _buildCloseControl(String title, _ShellTabTone tone, bool touch) {
    final icon = Icon(
      Icons.close_rounded,
      size: touch ? 18 : 12,
      color: touch ? tone.primaryText : tone.subtleText.withValues(alpha: 0.9),
    );
    return Semantics(
      key: Key('shell-tab-close-${widget.tab.sessionId}'),
      label: context.l10n.closeNamedTab(title),
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: context.l10n.closeNamed(title),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (touch) unawaited(HapticFeedback.lightImpact());
            widget.onClose();
          },
          child: SizedBox.square(
            dimension: touch ? 44 : 12,
            child: Center(
              child: touch
                  ? DecoratedBox(
                      key: Key(
                        'shell-tab-close-surface-${widget.tab.sessionId}',
                      ),
                      decoration: BoxDecoration(
                        color: tone.primaryText.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(dimension: 28, child: icon),
                    )
                  : icon,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _shellTabDisplayTitle(widget.tab);
    final usesPersistentTouchClose =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final closeVisible = usesPersistentTouchClose ? widget.isActive : _hovered;
    final badgeInfos = _shellTabBadgeInfos(widget.tab);
    final paneSignalInfos = _shellTabPaneSignalInfos(context.l10n, widget.tab);
    final paneSignalInfo = paneSignalInfos.isEmpty
        ? null
        : paneSignalInfos.first;
    final runtimeError = _shellTabRuntimeError(widget.tab);
    final canActivateBadgePane = widget.tab.effectivePanes.length > 1;
    final tabStatus = widget.tab.activePane.tabStatus;
    final indicatorColor = terminalViewportColorFromHex(tabStatus.indicator);
    final statusText = _normalizedShellTabStatusText(tabStatus.status);
    final requestedStatusColor = terminalViewportColorFromHex(
      tabStatus.statusColor,
    );
    final tone = _ShellTabTone.fromTerminalBackground(palette: widget.palette);
    final tabTextStyle = Theme.of(context).textTheme.titleSmall!.copyWith(
      color: widget.isActive ? tone.primaryText : tone.mutedText,
      fontSize: 12.5,
      fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) {
            widget.onShowContextMenu(event.position);
          }
        },
        child: SizedBox.expand(
          child: DecoratedBox(
            key: Key('shell-tab-border-${widget.tab.sessionId}'),
            decoration: const BoxDecoration(),
            child: Stack(
              children: [
                Semantics(
                  identifier: _shellTabSemanticsIdentifier(widget.tab),
                  label: _shellTabSemanticsLabel(
                    context.l10n,
                    widget.tab,
                    widget.shortcutIndex,
                    hasNewOutput: widget.hasNewOutput,
                  ),
                  selected: widget.isActive,
                  button: true,
                  excludeSemantics: true,
                  child: widget.dragRegionBuilder(
                    SizedBox.expand(
                      child: TextButton(
                        key: Key('shell-tab-${widget.tab.sessionId}'),
                        focusNode: widget.focusNode,
                        style: ButtonStyle(
                          minimumSize: const WidgetStatePropertyAll(
                            Size(0, 30),
                          ),
                          padding: WidgetStatePropertyAll(
                            usesPersistentTouchClose && widget.isActive
                                ? const EdgeInsets.only(left: 8, right: 48)
                                : EdgeInsets.symmetric(
                                    horizontal: widget.compact ? 8 : 12,
                                  ),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(
                            horizontal: -1,
                            vertical: -3,
                          ),
                          foregroundColor: WidgetStatePropertyAll(
                            widget.isActive ? tone.primaryText : tone.mutedText,
                          ),
                          overlayColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (widget.isActive) {
                              return tone.activeBackground;
                            }
                            if (states.contains(WidgetState.hovered) ||
                                states.contains(WidgetState.focused)) {
                              return tone.hoverBackground;
                            }
                            return Colors.transparent;
                          }),
                          side: WidgetStatePropertyAll(
                            widget.isActive
                                ? BorderSide(
                                    color: tone.border.withValues(alpha: 0.34),
                                  )
                                : BorderSide.none,
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                        onPressed: widget.onActivate,
                        child: Center(
                          child: KeyedSubtree(
                            key: Key('shell-tab-title-${widget.tab.sessionId}'),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (indicatorColor != null) ...[
                                  Tooltip(
                                    message:
                                        context.l10n.osc21337StatusIndicator,
                                    child: DecoratedBox(
                                      key: Key(
                                        'shell-tab-status-indicator-${widget.tab.sessionId}',
                                      ),
                                      decoration: BoxDecoration(
                                        color: indicatorColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: tone.primaryText.withValues(
                                            alpha: 0.28,
                                          ),
                                        ),
                                      ),
                                      child: const SizedBox.square(
                                        dimension: 8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (runtimeError != null) ...[
                                  _ShellTabRuntimeErrorIcon(
                                    key: Key(
                                      'shell-tab-error-${widget.tab.sessionId}',
                                    ),
                                    palette: widget.palette,
                                    error: runtimeError,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 140),
                                    style: tabTextStyle,
                                    child: Text(
                                      title,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (statusText != null) ...[
                                  const SizedBox(width: 6),
                                  _ShellTabStatusLabel(
                                    key: Key(
                                      'shell-tab-status-${widget.tab.sessionId}',
                                    ),
                                    text: statusText,
                                    requestedColor: requestedStatusColor,
                                    backgroundColor: widget.isActive
                                        ? tone.activeBackground
                                        : widget.chromeBackgroundColor,
                                    fallbackColor: widget.isActive
                                        ? tone.primaryText
                                        : tone.mutedText,
                                    maxWidth: widget.compact ? 48 : 72,
                                  ),
                                ],
                                ..._shellTabBadgeChips(
                                  l10n: context.l10n,
                                  keyPrefix:
                                      'shell-tab-badge-${widget.tab.sessionId}',
                                  tab: widget.tab,
                                  badges: badgeInfos,
                                  palette: widget.palette,
                                  foreground: widget.isActive
                                      ? tone.primaryText
                                      : tone.mutedText,
                                  background: tone.hoverBackground.withValues(
                                    alpha: widget.isActive ? 0.70 : 0.45,
                                  ),
                                  border: tone.border.withValues(alpha: 0.38),
                                  maxWidth: widget.compact ? 46 : 62,
                                  badgeNeedsFocus: (badge) =>
                                      !(widget.isActive && badge.isActivePane),
                                  onSelected: canActivateBadgePane
                                      ? widget.onActivateBadgePane
                                      : null,
                                ),
                                if (paneSignalInfo != null) ...[
                                  const SizedBox(width: 6),
                                  _ShellTabPaneSignalChip(
                                    itemKey: Key(
                                      'shell-tab-pane-signal-${widget.tab.sessionId}',
                                    ),
                                    palette: widget.palette,
                                    tab: widget.tab,
                                    signals: paneSignalInfos,
                                    primaryNeedsFocus:
                                        !(widget.isActive &&
                                            paneSignalInfo.isActivePane),
                                    onActivatePane: widget.onActivateBadgePane,
                                    onNotificationInteraction:
                                        widget.onNotificationInteraction,
                                    foreground: widget.isActive
                                        ? tone.primaryText
                                        : tone.mutedText,
                                    background: widget.palette.focusRing
                                        .withValues(
                                          alpha: widget.isActive ? 0.58 : 0.42,
                                        ),
                                    border: widget.palette.focusRing.withValues(
                                      alpha: 0.34,
                                    ),
                                  ),
                                ],
                                if (widget.hasNewOutput) ...[
                                  const SizedBox(width: 6),
                                  _ShellTabNewOutputDot(
                                    key: Key(
                                      'shell-tab-new-output-${widget.tab.sessionId}',
                                    ),
                                    palette: widget.palette,
                                    tooltip: widget.newOutputTooltip,
                                    onPressed:
                                        widget.newOutputPaneSessionId == null
                                        ? null
                                        : () => widget.onActivateNewOutputPane(
                                            widget.newOutputPaneSessionId!,
                                          ),
                                  ),
                                ],
                                if (widget.shortcutIndex != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '⌘${widget.shortcutIndex}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: tone.subtleText,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.tabColor != null)
                  Positioned(
                    top: 2,
                    left: widget.compact ? 10 : 14,
                    right: widget.compact ? 10 : 14,
                    child: IgnorePointer(
                      child: Tooltip(
                        message: context.l10n.profileTabColor,
                        child: DecoratedBox(
                          key: Key('shell-tab-color-${widget.tab.sessionId}'),
                          decoration: BoxDecoration(
                            color: widget.tabColor,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: widget.palette.textPrimary.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          child: const SizedBox(height: 3),
                        ),
                      ),
                    ),
                  ),
                if (!usesPersistentTouchClose || widget.isActive)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: usesPersistentTouchClose
                        ? null
                        : widget.palette.spacing.md,
                    right: usesPersistentTouchClose ? 0 : null,
                    child: usesPersistentTouchClose
                        ? _buildCloseControl(title, tone, true)
                        : IgnorePointer(
                            ignoring: !closeVisible,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 80),
                              opacity: closeVisible ? 1 : 0,
                              child: _buildCloseControl(title, tone, false),
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _shellTabSemanticsIdentifier(TerminalTab tab) {
  return 'shell-tab-${tab.sessionId}';
}

String _shellTabSemanticsLabel(
  AppLocalizations l10n,
  TerminalTab tab,
  int? shortcutIndex, {
  bool hasNewOutput = false,
}) {
  final parts = <String>[l10n.terminalTabSemantics(_shellTabDisplayTitle(tab))];
  final tabStatus = tab.activePane.tabStatus;
  final statusText = _normalizedShellTabStatusText(tabStatus.status);
  if (statusText != null) {
    parts.add(
      tab.effectivePanes.length < 2
          ? l10n.terminalStatus(statusText)
          : l10n.terminalStatusFromActivePane(statusText),
    );
  }
  if (tabStatus.indicator != null) {
    parts.add(
      tab.effectivePanes.length < 2
          ? l10n.statusIndicatorActive
          : l10n.statusIndicatorActiveOnActivePane,
    );
  }
  final runtimeError = _shellTabRuntimeError(tab);
  if (runtimeError != null) {
    parts.add(l10n.terminalTabError(runtimeError.message));
  }
  final badges = _shellTabBadgeInfos(tab);
  final badge = badges.isEmpty ? null : badges.first;
  final additionalBadgeCount = badges.length - 1;
  if (badge != null) {
    if (tab.effectivePanes.length < 2) {
      parts.add(l10n.badgeSemanticsValue(badge.text));
    } else {
      parts.add(
        l10n.terminalBadgeFromPane(
          badge.text,
          (badge.isActivePane ? l10n.activePane : l10n.inactivePane)
              .toLowerCase(),
        ),
      );
      if (additionalBadgeCount > 0) {
        parts.add(l10n.plusOtherPaneBadges(additionalBadgeCount));
      }
    }
  }

  final signals = _shellTabPaneSignalInfos(l10n, tab);
  if (signals.isNotEmpty) {
    final primary = signals.first;
    final signalScope = tab.effectivePanes.length < 2
        ? ''
        : l10n.signalFromPane(
            (primary.isActivePane ? l10n.activePane : l10n.inactivePane)
                .toLowerCase(),
          );
    parts.add(
      l10n.terminalSignalSummary(
        primary.title(l10n).toLowerCase(),
        primary.summary,
        signalScope,
      ),
    );
    final additionalSignalCount = signals.length - 1;
    if (additionalSignalCount > 0) {
      parts.add(l10n.plusOtherPaneSignals(additionalSignalCount));
    }
  }

  if (hasNewOutput) {
    parts.add(
      tab.effectivePanes.length < 2
          ? l10n.newOutputLower
          : l10n.newOutputInSplitPaneLower,
    );
  }

  if (shortcutIndex != null) {
    parts.add(l10n.commandShortcut(shortcutIndex));
  }
  return parts.join(', ');
}

TerminalPaneRuntimeErrorState? _shellTabRuntimeError(TerminalTab tab) {
  final activeError = tab.activePane.runtimeError;
  if (activeError != null) {
    return activeError;
  }
  for (final pane in tab.effectivePanes) {
    if (pane.runtimeError != null) {
      return pane.runtimeError;
    }
  }
  return null;
}

String _shellTabDisplayTitle(TerminalTab tab) {
  final activePaneTitle = tab.activePane.title.trim();
  return activePaneTitle.isEmpty ? tab.title : activePaneTitle;
}

List<_ShellTabBadgeInfo> _shellTabBadgeInfos(TerminalTab tab) {
  final activePane = tab.activePane;
  final badges = <_ShellTabBadgeInfo>[];

  void addPaneBadge(TerminalPane pane, {required bool isActivePane}) {
    final text = _normalizedShellTabBadgeText(pane.oscBadge);
    if (text != null) {
      badges.add(
        _ShellTabBadgeInfo(
          text: text,
          sessionId: pane.sessionId,
          paneTitle: pane.title,
          isActivePane: isActivePane,
        ),
      );
    }
  }

  for (final pane in tab.effectivePanes) {
    if (pane.sessionId != activePane.sessionId) {
      addPaneBadge(pane, isActivePane: false);
    }
  }
  addPaneBadge(activePane, isActivePane: true);
  return badges;
}

String? _normalizedShellTabBadgeText(String? rawText) {
  final text = rawText?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

String? _normalizedShellTabStatusText(String? rawText) {
  final text = rawText?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

class _ShellTabStatusLabel extends StatelessWidget {
  const _ShellTabStatusLabel({
    super.key,
    required this.text,
    required this.requestedColor,
    required this.backgroundColor,
    required this.fallbackColor,
    required this.maxWidth,
  });

  final String text;
  final Color? requestedColor;
  final Color backgroundColor;
  final Color fallbackColor;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final requested = requestedColor ?? fallbackColor;
    final chipBackground = Color.alphaBlend(
      requested.withValues(alpha: 0.14),
      backgroundColor,
    );
    final foreground = _shellAccessibleForeground(
      requested,
      chipBackground,
      fallbackColor,
    );
    return Tooltip(
      message: context.l10n.osc21337Status(text),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: requested.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: requested.withValues(alpha: 0.40)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.6),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontSize: 10.5,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _shellAccessibleForeground(
  Color requested,
  Color background,
  Color fallback,
) {
  if (_shellContrastRatio(requested, background) >= 4.5) {
    return requested;
  }
  if (_shellContrastRatio(fallback, background) >= 4.5) {
    return fallback;
  }
  const black = Colors.black;
  const white = Colors.white;
  return _shellContrastRatio(black, background) >=
          _shellContrastRatio(white, background)
      ? black
      : white;
}

double _shellContrastRatio(Color foreground, Color background) {
  final lighter = math.max(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  final darker = math.min(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  return (lighter + 0.05) / (darker + 0.05);
}

String _shellTabBadgeLabel(String text, {required int badgeCount}) {
  final trimmed = text.trim();
  final suffix = badgeCount > 1 ? ' +${badgeCount - 1}' : '';
  final maxRunes = badgeCount > 1 ? 7 : 10;
  final runes = trimmed.runes.toList(growable: false);
  final visible = runes.length <= maxRunes
      ? trimmed
      : '${String.fromCharCodes(runes.take(maxRunes - 1))}…';
  return '${visible.toUpperCase()}$suffix';
}

String _shellTabBadgeTooltip(
  AppLocalizations l10n,
  TerminalTab tab,
  _ShellTabBadgeInfo badge,
  List<_ShellTabBadgeInfo> badges, {
  required bool badgeNeedsFocus,
}) {
  if (tab.effectivePanes.length < 2) {
    return l10n.osc1337BadgeValue(badge.text);
  }
  final otherBadges = badges
      .where((candidate) => candidate.sessionId != badge.sessionId)
      .toList(growable: false);
  return [
    l10n.osc1337BadgeValue(badge.text),
    _shellTabBadgePaneContext(l10n, badge),
    if (otherBadges.isNotEmpty) ...[
      l10n.otherPaneBadges,
      for (final otherBadge in otherBadges)
        '${_shellTabBadgePaneContext(l10n, otherBadge)}: ${otherBadge.text}',
    ],
    if (badgeNeedsFocus) l10n.clickToFocusPane,
  ].join('\n');
}

String _shellTabBadgeSemanticsLabel(
  AppLocalizations l10n,
  TerminalTab tab,
  _ShellTabBadgeInfo badge,
  List<_ShellTabBadgeInfo> badges, {
  required bool badgeNeedsFocus,
}) {
  if (tab.effectivePanes.length < 2) {
    return l10n.terminalBadgeValue(badge.text);
  }
  final otherBadgeCount = badges
      .where((candidate) => candidate.sessionId != badge.sessionId)
      .length;
  final otherBadgeLabel = otherBadgeCount == 0
      ? ''
      : '; ${l10n.otherPaneBadgeCount(otherBadgeCount)}';
  return '${l10n.terminalBadgeValue(badge.text)}; '
      '${_shellTabBadgePaneContext(l10n, badge)}$otherBadgeLabel; '
      '${badgeNeedsFocus ? l10n.clickFocusPaneSemantics : l10n.paneAlreadyFocusedSemantics}';
}

String _shellTabBadgeOverflowTooltip(
  AppLocalizations l10n,
  TerminalTab tab,
  List<_ShellTabBadgeInfo> hiddenBadges,
  bool Function(_ShellTabBadgeInfo badge) badgeNeedsFocus,
) {
  if (hiddenBadges.length == 1) {
    final badge = hiddenBadges.single;
    return [
      l10n.additionalOsc1337Badge(badge.text),
      _shellTabBadgePaneContext(l10n, badge),
      if (badgeNeedsFocus(badge))
        l10n.clickToFocusPane
      else
        l10n.paneAlreadyFocused,
    ].join('\n');
  }
  final firstHiddenNeedsFocus = badgeNeedsFocus(hiddenBadges.first);
  return [
    l10n.additionalOsc1337BadgesSplitTab,
    for (final badge in hiddenBadges)
      '${_shellTabBadgePaneContext(l10n, badge)}: ${badge.text}',
    if (firstHiddenNeedsFocus)
      l10n.clickFocusFirstRemainingBadgePane
    else
      l10n.firstRemainingBadgePaneFocused,
  ].join('\n');
}

String _shellTabBadgeOverflowSemanticsLabel(
  AppLocalizations l10n,
  TerminalTab tab,
  List<_ShellTabBadgeInfo> hiddenBadges,
  bool Function(_ShellTabBadgeInfo badge) badgeNeedsFocus,
) {
  if (hiddenBadges.length == 1) {
    final badge = hiddenBadges.single;
    final action = badgeNeedsFocus(badge)
        ? l10n.clickFocusPaneSemantics
        : l10n.paneAlreadyFocusedSemantics;
    return '${l10n.terminalBadgeValue(badge.text)}; '
        '${_shellTabBadgePaneContext(l10n, badge)}; $action';
  }
  final action = badgeNeedsFocus(hiddenBadges.first)
      ? l10n.clickFocusFirstRemainingBadgePaneSemantics
      : l10n.firstRemainingBadgePaneFocusedSemantics;
  return l10n.terminalBadgesAdditional(
    hiddenBadges.length,
    _shellTabDisplayTitle(tab),
    action,
  );
}

String _shellTabBadgePaneContext(
  AppLocalizations l10n,
  _ShellTabBadgeInfo badge,
) {
  final paneState = (badge.isActivePane ? l10n.activePane : l10n.inactivePane)
      .toLowerCase();
  final title = badge.paneTitle.trim();
  return title.isEmpty
      ? l10n.paneContextUntitled(badge.sessionId, paneState)
      : l10n.paneContextTitled(title, badge.sessionId, paneState);
}

class _ShellTabBadgeInfo {
  const _ShellTabBadgeInfo({
    required this.text,
    required this.sessionId,
    required this.paneTitle,
    required this.isActivePane,
  });

  final String text;
  final String sessionId;
  final String paneTitle;
  final bool isActivePane;
}

enum _ShellTabPaneSignalKind { progress, notification }

class _ShellTabNotificationTarget {
  const _ShellTabNotificationTarget({
    required this.sessionId,
    required this.paneTitle,
    required this.notification,
  });

  final String sessionId;
  final String paneTitle;
  final TerminalPaneNotificationState notification;
}

enum _ShellNotificationInteractionKind { activate, button, dismiss }

class _ShellNotificationInteraction {
  const _ShellNotificationInteraction.activate(
    this.sessionId,
    this.notification,
  ) : kind = _ShellNotificationInteractionKind.activate,
      buttonNumber = null;

  const _ShellNotificationInteraction.button(
    this.sessionId,
    this.notification,
    this.buttonNumber,
  ) : kind = _ShellNotificationInteractionKind.button;

  const _ShellNotificationInteraction.dismiss(this.sessionId, this.notification)
    : kind = _ShellNotificationInteractionKind.dismiss,
      buttonNumber = null;

  final String sessionId;
  final TerminalPaneNotificationState notification;
  final _ShellNotificationInteractionKind kind;
  final int? buttonNumber;
}

class _ShellTabPaneSignalInfo {
  const _ShellTabPaneSignalInfo({
    required this.kind,
    required this.sessionId,
    required this.paneTitle,
    required this.isActivePane,
    required this.detail,
    required this.summary,
  });

  final _ShellTabPaneSignalKind kind;
  final String sessionId;
  final String paneTitle;
  final bool isActivePane;
  final String detail;
  final String summary;

  String label(AppLocalizations l10n) {
    return switch (kind) {
      _ShellTabPaneSignalKind.progress => l10n.terminalProgressAbbreviation,
      _ShellTabPaneSignalKind.notification =>
        l10n.terminalNotificationAbbreviation,
    };
  }

  String title(AppLocalizations l10n) {
    return switch (kind) {
      _ShellTabPaneSignalKind.progress => l10n.terminalProgress,
      _ShellTabPaneSignalKind.notification => l10n.terminalNotification,
    };
  }
}

List<TerminalPaneProgressState> _shellPaneActiveProgressItems(
  TerminalPane pane,
) {
  return <TerminalPaneProgressState>[
    if (pane.progress case final progress? when progress.active) progress,
    for (final progress in pane.namedProgress.values)
      if (progress.active) progress,
  ];
}

TerminalPaneProgressState? _shellPanePrimaryProgress(TerminalPane pane) {
  final primary = pane.progress;
  final activePrimary = primary != null && primary.active ? primary : null;
  final activeNamed = pane.namedProgress.values
      .where((progress) => progress.active)
      .toList(growable: false);

  if (activePrimary == null) {
    return activeNamed.isEmpty ? null : activeNamed.last;
  }
  if (!_shellPaneProgressIsComplete(activePrimary)) {
    return activePrimary;
  }
  final runningNamed = activeNamed
      .where((progress) => !_shellPaneProgressIsComplete(progress))
      .toList(growable: false);
  if (runningNamed.isNotEmpty) {
    return runningNamed.last;
  }
  return activeNamed.isEmpty ? activePrimary : activeNamed.last;
}

bool _shellPaneProgressIsComplete(TerminalPaneProgressState progress) {
  return progress.action == 'complete' || progress.state == 'complete';
}

List<_ShellTabPaneSignalInfo> _shellTabPaneSignalInfos(
  AppLocalizations l10n,
  TerminalTab tab,
) {
  final activePane = tab.activePane;
  final signals = <_ShellTabPaneSignalInfo>[];

  void addPaneSignals(TerminalPane pane, {required bool isActivePane}) {
    final progressItems = _shellPaneActiveProgressItems(pane);
    if (progressItems.isNotEmpty) {
      final primaryProgress = _shellPanePrimaryProgress(pane)!;
      signals.add(
        _ShellTabPaneSignalInfo(
          kind: _ShellTabPaneSignalKind.progress,
          sessionId: pane.sessionId,
          paneTitle: pane.title,
          isActivePane: isActivePane,
          detail: progressItems.length == 1
              ? _shellTabProgressDetail(l10n, primaryProgress)
              : [
                  l10n.terminalProgressInPane,
                  for (final progress in progressItems)
                    '${progress.displayLabel}: ${_shellTabProgressDetail(l10n, progress)}',
                ].join('\n'),
          summary: primaryProgress.displayLabel,
        ),
      );
    }

    final notification = pane.recentNotifications.isEmpty
        ? null
        : pane.recentNotifications.first;
    if (notification != null) {
      signals.add(
        _ShellTabPaneSignalInfo(
          kind: _ShellTabPaneSignalKind.notification,
          sessionId: pane.sessionId,
          paneTitle: pane.title,
          isActivePane: isActivePane,
          detail: _shellTabNotificationDetail(l10n, notification),
          summary:
              '${notification.title}${notification.count > 1 ? ' x${notification.count}' : ''}',
        ),
      );
    }
  }

  for (final pane in tab.effectivePanes) {
    if (pane.sessionId == activePane.sessionId) {
      continue;
    }
    addPaneSignals(pane, isActivePane: false);
  }
  addPaneSignals(activePane, isActivePane: true);
  return signals;
}

List<_ShellTabNotificationTarget> _shellTabNotificationTargets(
  TerminalTab tab,
) {
  return <_ShellTabNotificationTarget>[
    for (final pane in tab.effectivePanes)
      for (final notification in pane.recentNotifications)
        _ShellTabNotificationTarget(
          sessionId: pane.sessionId,
          paneTitle: pane.title,
          notification: notification,
        ),
  ];
}

String _shellTabNotificationMenuTitle(
  TerminalPaneNotificationState notification,
) {
  final count = notification.count > 1 ? ' x${notification.count}' : '';
  return '${notification.title}$count';
}

String _shellTabNotificationMenuSubtitle(_ShellTabNotificationTarget target) {
  final notification = target.notification;
  return [
    if (notification.message.trim().isNotEmpty) notification.message.trim(),
    if (target.paneTitle.trim().isNotEmpty) target.paneTitle.trim(),
    if (notification.remoteHost?.trim().isNotEmpty == true)
      notification.remoteUser?.trim().isNotEmpty == true
          ? '${notification.remoteUser!.trim()}@${notification.remoteHost!.trim()}'
          : notification.remoteHost!.trim(),
    notification.source,
  ].join(' · ');
}

String _shellTabPaneSignalLabel(
  AppLocalizations l10n,
  List<_ShellTabPaneSignalInfo> signals,
) {
  final label = signals.isEmpty
      ? l10n.paneSignalAbbreviation
      : signals.first.label(l10n);
  return '$label${signals.length > 1 ? ' +${signals.length - 1}' : ''}';
}

String _shellTabPaneSignalTooltip(
  AppLocalizations l10n,
  TerminalTab tab,
  _ShellTabPaneSignalInfo primary,
  List<_ShellTabPaneSignalInfo> signals, {
  required bool primaryNeedsFocus,
}) {
  final otherSignals = signals
      .where((candidate) => candidate != primary)
      .toList(growable: false);
  final hasNotifications = signals.any(
    (signal) => signal.kind == _ShellTabPaneSignalKind.notification,
  );
  if (tab.effectivePanes.length < 2 && otherSignals.isEmpty) {
    return [
      primary.title(l10n),
      primary.detail,
      if (hasNotifications) l10n.clickInspectRecentNotifications,
    ].join('\n');
  }
  return [
    l10n.signalInSplitPane(primary.title(l10n)),
    _shellTabPaneSignalContext(l10n, primary),
    primary.detail,
    if (otherSignals.isNotEmpty) ...[
      l10n.otherPaneSignals,
      for (final otherSignal in otherSignals)
        '${_shellTabPaneSignalContext(l10n, otherSignal)}: '
            '${otherSignal.label(l10n)} ${otherSignal.summary}',
    ],
    if (hasNotifications)
      l10n.clickInspectRecentNotifications
    else if (primaryNeedsFocus)
      otherSignals.isEmpty
          ? l10n.clickToFocusPane
          : l10n.clickFocusFirstPaneWithSignal,
  ].join('\n');
}

String _shellTabPaneSignalSemanticsLabel(
  AppLocalizations l10n,
  TerminalTab tab,
  _ShellTabPaneSignalInfo primary,
  List<_ShellTabPaneSignalInfo> signals, {
  required bool primaryNeedsFocus,
}) {
  final hasNotifications = signals.any(
    (signal) => signal.kind == _ShellTabPaneSignalKind.notification,
  );
  if (tab.effectivePanes.length < 2) {
    return '${primary.title(l10n)}: ${primary.summary}; '
        '${hasNotifications
            ? l10n.clickInspectNotificationActionsSemantics
            : primaryNeedsFocus
            ? l10n.clickFocusPaneSemantics
            : l10n.paneAlreadyFocusedSemantics}';
  }
  final otherSignalCount = signals.length - 1;
  final otherSignalLabel = otherSignalCount <= 0
      ? ''
      : '; ${l10n.otherPaneSignalCount(otherSignalCount)}';
  return '${primary.title(l10n)}: ${primary.summary}; '
      '${_shellTabPaneSignalContext(l10n, primary)}$otherSignalLabel; '
      '${hasNotifications
          ? l10n.clickInspectNotificationActionsSemantics
          : primaryNeedsFocus
          ? l10n.clickFocusPaneSemantics
          : l10n.paneAlreadyFocusedSemantics}';
}

String _shellTabPaneSignalContext(
  AppLocalizations l10n,
  _ShellTabPaneSignalInfo signal,
) {
  final paneState = (signal.isActivePane ? l10n.activePane : l10n.inactivePane)
      .toLowerCase();
  final title = signal.paneTitle.trim();
  return title.isEmpty
      ? l10n.paneContextUntitled(signal.sessionId, paneState)
      : l10n.paneContextTitled(title, signal.sessionId, paneState);
}

String _shellTabProgressDetail(
  AppLocalizations l10n,
  TerminalPaneProgressState progress,
) {
  return [
    l10n.terminalProgressReportedBy(progress.source),
    if (progress.label?.trim().isNotEmpty == true)
      l10n.labelValue(progress.label!.trim()),
    if (progress.percent != null) l10n.progressPercentValue(progress.percent!),
    if (progress.state?.trim().isNotEmpty == true)
      l10n.stateValue(progress.state!.trim()),
    if (progress.id?.trim().isNotEmpty == true)
      l10n.idValue(progress.id!.trim()),
  ].join('\n');
}

String _shellTabNotificationDetail(
  AppLocalizations l10n,
  TerminalPaneNotificationState notification,
) {
  return [
    l10n.terminalNotificationReportedBy(notification.source),
    l10n.titleValue(notification.title),
    if (notification.message.trim().isNotEmpty)
      l10n.messageValue(notification.message.trim()),
    if (notification.remoteHost?.trim().isNotEmpty == true)
      l10n.remoteHostValue(notification.remoteHost!.trim()),
    if (notification.remoteUser?.trim().isNotEmpty == true)
      l10n.remoteUserValue(notification.remoteUser!.trim()),
    if (notification.count > 1) l10n.countValue(notification.count),
  ].join('\n');
}

List<_ShellHiddenTabBadgeTarget> _shellHiddenTabBadgeTargets(
  Iterable<TerminalTab> tabs, {
  required String? activeSessionId,
}) {
  final targets = <_ShellHiddenTabBadgeTarget>[];
  for (final tab in tabs) {
    for (final badge in _shellTabBadgeInfos(tab)) {
      targets.add(_ShellHiddenTabBadgeTarget(tab: tab, badge: badge));
    }
  }
  return _prioritizeHiddenTargets(
    targets,
    activeSessionId: activeSessionId,
    sessionIdFor: (target) => target.badge.sessionId,
  );
}

String _hiddenTabsBadgeTooltip(
  AppLocalizations l10n,
  List<_ShellHiddenTabBadgeTarget> targets, {
  required String? activeSessionId,
}) {
  if (targets.length == 1) {
    final target = targets.single;
    final needsFocus = target.badge.sessionId != activeSessionId;
    return [
      l10n.osc1337BadgeInHiddenTab,
      l10n.tabSessionDetails(
        _shellTabDisplayTitle(target.tab),
        target.tab.sessionId,
      ),
      l10n.osc1337BadgeValue(target.badge.text),
      _shellTabBadgePaneContext(l10n, target.badge),
      if (needsFocus) l10n.clickToFocusPane else l10n.paneAlreadyFocused,
    ].join('\n');
  }
  final hasFocusableTarget = targets.any(
    (target) => target.badge.sessionId != activeSessionId,
  );
  return [
    l10n.osc1337BadgesInHiddenPanes(targets.length),
    for (final target in targets)
      '${_shellTabDisplayTitle(target.tab)} (${target.tab.sessionId}) - '
          '${_shellTabBadgePaneContext(l10n, target.badge)}: ${target.badge.text}',
    if (hasFocusableTarget)
      l10n.clickFocusFirstBadgePane
    else
      l10n.paneAlreadyFocused,
  ].join('\n');
}

class _ShellHiddenTabBadgeTarget {
  const _ShellHiddenTabBadgeTarget({required this.tab, required this.badge});

  final TerminalTab tab;
  final _ShellTabBadgeInfo badge;
}

List<_ShellHiddenTabPaneSignalTarget> _shellHiddenTabPaneSignalTargets(
  AppLocalizations l10n,
  Iterable<TerminalTab> tabs, {
  required String? activeSessionId,
}) {
  final targets = <_ShellHiddenTabPaneSignalTarget>[];
  for (final tab in tabs) {
    for (final signal in _shellTabPaneSignalInfos(l10n, tab)) {
      targets.add(_ShellHiddenTabPaneSignalTarget(tab: tab, signal: signal));
    }
  }
  return _prioritizeHiddenTargets(
    targets,
    activeSessionId: activeSessionId,
    sessionIdFor: (target) => target.signal.sessionId,
  );
}

String _hiddenTabsPaneSignalTooltip(
  AppLocalizations l10n,
  List<_ShellHiddenTabPaneSignalTarget> targets, {
  required String? activeSessionId,
}) {
  if (targets.length == 1) {
    final target = targets.single;
    final needsFocus = target.signal.sessionId != activeSessionId;
    return [
      l10n.signalInHiddenTab(target.signal.title(l10n)),
      l10n.tabSessionDetails(
        _shellTabDisplayTitle(target.tab),
        target.tab.sessionId,
      ),
      _shellTabPaneSignalContext(l10n, target.signal),
      target.signal.detail,
      if (needsFocus) l10n.clickToFocusPane else l10n.paneAlreadyFocused,
    ].join('\n');
  }
  final hasFocusableTarget = targets.any(
    (target) => target.signal.sessionId != activeSessionId,
  );
  return [
    l10n.paneSignalsInHiddenPanes(targets.length),
    for (final target in targets)
      '${_shellTabDisplayTitle(target.tab)} (${target.tab.sessionId}) - '
          '${_shellTabPaneSignalContext(l10n, target.signal)}: '
          '${target.signal.label(l10n)} ${target.signal.summary}',
    if (hasFocusableTarget)
      l10n.clickFocusFirstPaneWithSignal
    else
      l10n.paneAlreadyFocused,
  ].join('\n');
}

String _hiddenTabsOverflowButtonTooltip(
  AppLocalizations l10n, {
  required int hiddenTabCount,
  required int badgePaneCount,
  required int paneSignalCount,
  required int newOutputTabCount,
}) {
  final hasSignals =
      badgePaneCount > 0 || paneSignalCount > 0 || newOutputTabCount > 0;
  return [
    l10n.showHiddenTabs(hiddenTabCount),
    if (badgePaneCount > 0) l10n.hiddenOsc1337BadgePanesTooltip(badgePaneCount),
    if (paneSignalCount > 0) l10n.hiddenPaneSignalsTooltip(paneSignalCount),
    if (newOutputTabCount > 0)
      l10n.hiddenNewOutputTabsTooltip(newOutputTabCount),
    if (hasSignals) l10n.signalMarkersFocusSources,
  ].join('\n');
}

String _hiddenTabsOverflowButtonSemanticsLabel(
  AppLocalizations l10n, {
  required int hiddenTabCount,
  required int badgePaneCount,
  required int paneSignalCount,
  required int newOutputTabCount,
}) {
  return [
    l10n.showHiddenTabs(hiddenTabCount),
    if (badgePaneCount > 0)
      l10n.hiddenOsc1337BadgePanesSemantics(badgePaneCount),
    if (paneSignalCount > 0) l10n.hiddenPaneSignalsSemantics(paneSignalCount),
    if (newOutputTabCount > 0)
      l10n.hiddenNewOutputTabsSemantics(newOutputTabCount),
  ].join(', ');
}

List<T> _prioritizeHiddenTargets<T>(
  List<T> targets, {
  required String? activeSessionId,
  required String Function(T target) sessionIdFor,
}) {
  if (activeSessionId == null || targets.length < 2) {
    return targets;
  }
  return <T>[
    for (final target in targets)
      if (sessionIdFor(target) != activeSessionId) target,
    for (final target in targets)
      if (sessionIdFor(target) == activeSessionId) target,
  ];
}

class _ShellHiddenTabPaneSignalTarget {
  const _ShellHiddenTabPaneSignalTarget({
    required this.tab,
    required this.signal,
  });

  final TerminalTab tab;
  final _ShellTabPaneSignalInfo signal;
}
