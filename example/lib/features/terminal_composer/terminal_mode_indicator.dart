import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../preferences/app_preferences_models.dart';
import '../sessions/session_controller.dart';
import 'terminal_mode.dart';

String blockUnavailableMessage(
  AppLocalizations l10n,
  BlockUnavailableReason? reason,
) => switch (reason) {
  BlockUnavailableReason.checking => l10n.blockUnavailableChecking,
  BlockUnavailableReason.unsupportedShell => l10n.blockUnavailableShell,
  BlockUnavailableReason.remoteShell => l10n.blockUnavailableRemote,
  BlockUnavailableReason.nestedShell => l10n.blockUnavailableNested,
  BlockUnavailableReason.terminalInput => l10n.blockUnavailableInput,
  BlockUnavailableReason.fullScreen => l10n.blockUnavailableFullScreen,
  BlockUnavailableReason.richOutput => l10n.blockUnavailableRichOutput,
  BlockUnavailableReason.unattributedOutput =>
    l10n.blockUnavailableUnattributed,
  BlockUnavailableReason.exited => l10n.blockUnavailableExited,
  BlockUnavailableReason.readOnly => l10n.blockUnavailableReadOnly,
  null => '',
};

String terminalModeNoticeMessage(
  AppLocalizations l10n,
  TerminalModeState state, {
  bool mobile = false,
}) => switch (state.notice) {
  TerminalModeNotice.supportChecked =>
    state.canUseBlocks
        ? l10n.terminalModeSupportAvailable
        : blockUnavailableMessage(l10n, state.unavailableReason),
  TerminalModeNotice.blocksAvailable =>
    mobile ? l10n.mobileBlocksAvailable : l10n.blockModeAvailableNotice,
  TerminalModeNotice.blocksRestored =>
    mobile ? l10n.mobileBlocksRestored : l10n.blockModeRestoredNotice,
  TerminalModeNotice.normalFallback =>
    '${blockUnavailableMessage(l10n, state.unavailableReason)} ${mobile ? l10n.mobileNormalFallback : l10n.normalModeFallbackNotice}',
  null => '',
};

/// A popup route outlives the tab build that opened it. Observe the session
/// inside the route so shell recovery or capability loss updates the menu too.
class TerminalModeMenuEntry extends PopupMenuEntry<Object> {
  const TerminalModeMenuEntry({
    super.key,
    required this.sessionId,
    required this.value,
  });

  final String sessionId;
  final Object value;

  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(Object? value) => this.value == value;

  @override
  State<TerminalModeMenuEntry> createState() => _TerminalModeMenuEntryState();
}

class _TerminalModeMenuEntryState extends State<TerminalModeMenuEntry> {
  @override
  Widget build(BuildContext context) => Consumer(
    builder: (context, ref, _) {
      final state = ref.watch(
        sessionControllerProvider.select(
          (state) => state.tabs
              .expand((tab) => tab.effectivePanes)
              .where((pane) => pane.sessionId == widget.sessionId)
              .firstOrNull
              ?.terminalMode,
        ),
      );
      final value = widget.value;
      if (value is! TerminalViewMode) {
        return PopupMenuItem<Object>(
          key: Key('terminal-mode-recheck-${widget.sessionId}'),
          value: value,
          enabled:
              state != null &&
              state.unavailableReason != BlockUnavailableReason.exited &&
              state.unavailableReason != BlockUnavailableReason.readOnly,
          child: Text(context.l10n.terminalModeRecheck),
        );
      }
      final canUseBlocks = state?.canUseBlocks ?? false;
      return CheckedPopupMenuItem<Object>(
        key: Key('terminal-mode-${value.name}-${widget.sessionId}'),
        value: value,
        checked: state?.mode == value,
        enabled:
            state != null && (value == TerminalViewMode.normal || canUseBlocks),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value == TerminalViewMode.blocks
                  ? context.l10n.terminalModeBlocks
                  : context.l10n.terminalModeNormal,
            ),
            if (value == TerminalViewMode.blocks && !canUseBlocks)
              Text(
                blockUnavailableMessage(
                  context.l10n,
                  state?.unavailableReason ?? BlockUnavailableReason.exited,
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      );
    },
  );
}

class TerminalModeIndicator extends StatelessWidget {
  const TerminalModeIndicator({
    super.key,
    required this.state,
    required this.color,
    this.onOpenMenu,
  });
  final TerminalModeState state;
  final Color color;
  final ValueChanged<Offset>? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    if (state.notice == null) return const SizedBox.shrink();
    final message = terminalModeNoticeMessage(
      context.l10n,
      state,
      mobile:
          Theme.of(context).materialTapTargetSize ==
          MaterialTapTargetSize.padded,
    );
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        liveRegion: true,
        button: onOpenMenu != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onOpenMenu == null
              ? null
              : (details) => onOpenMenu!(details.globalPosition),
          child: SizedBox(
            width: 22,
            height: 24,
            child: Icon(Icons.swap_horiz_rounded, size: 15, color: color),
          ),
        ),
      ),
    );
  }
}
