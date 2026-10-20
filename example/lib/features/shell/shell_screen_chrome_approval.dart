part of 'shell_screen.dart';

extension _ShellScreenApprovalNavigation on _ShellScreenState {
  void _revealApproval(String sessionId) {
    final ai = _aiSessions[sessionId];
    if (!mounted ||
        !_sessionExists(sessionId) ||
        ai?.pending == null ||
        ai?.phase != AiPhase.awaitingApproval) {
      return;
    }
    _activateSession(
      ref.read(sessionControllerProvider.notifier),
      sessionId,
      requestFocus: false,
    );
    _openAi(sessionId);
  }
}

class _ShellApprovalScope extends InheritedWidget {
  const _ShellApprovalScope({
    required this.controllers,
    required this.onReveal,
    required super.child,
  });

  final Map<String, TerminalAiController> controllers;
  final ValueChanged<String> onReveal;

  static _ShellApprovalScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShellApprovalScope>();

  List<TerminalPane> pending(Iterable<TerminalTab> tabs) => [
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android)
      for (final tab in tabs)
        for (final pane in tab.effectivePanes)
          if (controllers[pane.sessionId]?.pending != null &&
              controllers[pane.sessionId]?.phase == AiPhase.awaitingApproval)
            pane,
  ];

  @override
  bool updateShouldNotify(_ShellApprovalScope oldWidget) => true;
}

String _approvalLabel(BuildContext context, int count) =>
    Localizations.localeOf(context).languageCode == 'zh'
    ? '$count 个 AI 操作待确认'
    : '$count AI ${count == 1 ? 'action needs' : 'actions need'} review';

class _ShellApprovalBadge extends StatelessWidget {
  _ShellApprovalBadge({required TerminalTab tab})
    : tabs = [tab],
      badgeKey = 'shell-tab-approval-${tab.sessionId}';

  const _ShellApprovalBadge.sidebar({required this.tabs})
    : badgeKey = 'shell-sidebar-approval';

  final Iterable<TerminalTab> tabs;
  final String badgeKey;

  @override
  Widget build(BuildContext context) {
    final scope = _ShellApprovalScope.of(context);
    final pending = scope?.pending(tabs) ?? const <TerminalPane>[];
    if (pending.isEmpty) return const SizedBox.shrink();
    final label =
        '${_approvalLabel(context, pending.length)}\n'
        '${pending.map((p) => '${p.title} · ${p.sessionId}').join('\n')}';
    return Tooltip(
      message: label,
      child: TextButton(
        key: Key(badgeKey),
        style: TextButton.styleFrom(
          minimumSize: const Size(24, 24),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          foregroundColor: context.appTheme.textPrimary,
          backgroundColor: context.appTheme.warningContainer,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () async {
          var target = pending.first.sessionId;
          if (pending.length > 1) {
            final box = context.findRenderObject()! as RenderBox;
            final overlay =
                Overlay.of(context).context.findRenderObject()! as RenderBox;
            final result = await showMenu<String>(
              context: context,
              position: RelativeRect.fromRect(
                box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
                Offset.zero & overlay.size,
              ),
              items: [
                for (final pane in pending)
                  PopupMenuItem(
                    value: pane.sessionId,
                    child: Text('${pane.title} · ${pane.sessionId}'),
                  ),
              ],
            );
            if (!context.mounted || result == null) return;
            target = result;
          }
          scope!.onReveal(target);
        },
        child: Semantics(label: label, child: Text('${pending.length}')),
      ),
    );
  }
}
