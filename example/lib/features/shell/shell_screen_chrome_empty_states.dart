part of 'shell_screen.dart';

class _ShellStartupSurface extends StatelessWidget {
  const _ShellStartupSurface({
    super.key,
    required this.palette,
    required this.errorMessage,
    required this.onRetry,
    required this.onOpenSettings,
    this.onRepairSettings,
    this.onUseLocalSnapshot,
    this.remoteFallbackSwitching = false,
  });

  final AppThemeTokens palette;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback? onRepairSettings;
  final VoidCallback? onUseLocalSnapshot;
  final bool remoteFallbackSwitching;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        border: Border(top: BorderSide(color: palette.terminalFrame)),
      ),
      child: errorMessage == null
          ? const SizedBox.expand()
          : Semantics(
              container: true,
              liveRegion: true,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppEmptyState(
                    key: const Key('shell-startup-error'),
                    title: context.l10n.terminalCouldNotStart,
                    message: context.l10n.terminalCouldNotStartHelp,
                    supportingText: errorMessage,
                    action: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppActionButton(
                          buttonKey: const Key('shell-startup-settings'),
                          tone: AppActionTone.secondary,
                          icon: Icons.settings_rounded,
                          label: context.l10n.dataServiceSettings,
                          onPressed: onOpenSettings,
                        ),
                        if (onRepairSettings != null)
                          AppActionButton(
                            buttonKey: const Key(
                              'shell-startup-repair-settings',
                            ),
                            tone: AppActionTone.secondary,
                            icon: Icons.build_circle_outlined,
                            label: context.l10n.repairTerminalSettings,
                            onPressed: onRepairSettings,
                          ),
                        if (onUseLocalSnapshot != null ||
                            remoteFallbackSwitching)
                          AppActionButton(
                            buttonKey: const Key(
                              'shell-startup-use-local-snapshot',
                            ),
                            tone: AppActionTone.secondary,
                            icon: Icons.cloud_off_rounded,
                            label: remoteFallbackSwitching
                                ? context.l10n.switchingToLocalSnapshot
                                : context.l10n.useLastRemoteSnapshot,
                            onPressed: onUseLocalSnapshot,
                          ),
                        AppActionButton(
                          buttonKey: const Key('shell-startup-retry'),
                          icon: Icons.refresh,
                          label: context.l10n.retry,
                          onPressed: onRetry,
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

class _ShellEmptyState extends StatelessWidget {
  const _ShellEmptyState({
    super.key,
    required this.palette,
    required this.title,
    required this.message,
    required this.defaultSummary,
    required this.onNewTab,
  });

  final AppThemeTokens palette;
  final String title;
  final String message;
  final String defaultSummary;
  final VoidCallback? onNewTab;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        border: Border(top: BorderSide(color: palette.terminalFrame)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppEmptyState(
            title: title,
            message: message,
            supportingText: defaultSummary,
            action: AppActionButton(
              buttonKey: const Key('shell-empty-new-tab'),
              icon: Icons.add_box_outlined,
              label: context.l10n.newTabTitleCase,
              onPressed: onNewTab,
            ),
          ),
        ),
      ),
    );
  }
}
