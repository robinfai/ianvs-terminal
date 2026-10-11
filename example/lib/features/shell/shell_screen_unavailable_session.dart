part of 'shell_screen.dart';

/// A runtime may disappear before its ordered exit effect reaches the feature
/// model. Keep the pane reachable, preserve its task/draft, and reconcile only
/// the exact missing incarnation after this frame (never mutate during build).
extension _ShellUnavailableSession on _ShellScreenState {
  Widget _buildUnavailableTerminalPane({
    required BuildContext context,
    required SessionController sessionController,
    required TerminalPane pane,
    required TerminalTab expectedTab,
    required AppThemeTokens palette,
    required bool isActive,
  }) {
    final sessionId = pane.sessionId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = sessionController.existingViewportFor(sessionId);
      if (current != null) {
        // A stale LayoutBuilder must bind the current viewport on its next
        // build, not permanently keep the previously captured controller.
        _mutateState(() {});
      } else {
        sessionController.reconcileUnavailableSession(sessionId,
            expectedTab: expectedTab);
      }
    });
    bool canAct() => mounted && isActive &&
        ref.read(sessionControllerProvider).activeSessionId == sessionId &&
        ref.read(sessionControllerProvider).tabs.any((tab) => identical(tab, expectedTab) && tab.containsSession(sessionId));
    final notice = TerminalUnavailablePaneNotice(
      onReconnect: isActive && pane.profileSnapshot?.isSsh == true
          ? () {
              if (canAct()) unawaited(_reconnectTerminalSession(sessionId));
            } : null,
      onBack: context.usesMobileNavigation ? _showMobileConnections : null,
    );
    return SizedBox.expand(
      key: Key('shell-unavailable-pane-$sessionId'),
      child: Stack(fit: StackFit.expand, children: [
        notice,
        if (_openAiSessions.contains(sessionId))
          Positioned.fill(child: _aiOverlay(sessionId, palette,
              targetLabel: pane.title, paneContext: context, active: isActive)),
      ]),
    );
  }
}

class TerminalUnavailablePaneNotice extends StatelessWidget {
  const TerminalUnavailablePaneNotice({this.onReconnect, this.onBack, super.key});
  final VoidCallback? onReconnect;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Material(
      color: context.appTheme.panel,
      child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.link_off, color: context.appTheme.textMuted, size: 28),
          const SizedBox(height: 12),
          Text(zh ? '终端会话不可用' : 'Terminal session unavailable',
              key: const Key('terminal-unavailable-title'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(zh
              ? '原终端运行时已不可用。不会自动重发命令；旧输出可能无法再次读取。'
              : 'The original terminal runtime is unavailable. Commands will not be replayed; old output may no longer be readable.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
            children: [
              if (onReconnect != null) FilledButton(
                  key: const Key('terminal-unavailable-reconnect'),
                  onPressed: onReconnect,
                  child: Text(zh ? '重新连接' : 'Reconnect')),
              if (onBack != null) TextButton(
                  key: const Key('terminal-unavailable-back'),
                  onPressed: onBack,
                  child: Text(zh ? '返回连接列表' : 'Back to connections')),
            ],
          ),
        ]),
      )),
    );
  }
}
