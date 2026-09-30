import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
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
  TerminalModeNotice.blocksAvailable =>
    mobile ? l10n.mobileBlocksAvailable : l10n.blockModeAvailableNotice,
  TerminalModeNotice.blocksRestored =>
    mobile ? l10n.mobileBlocksRestored : l10n.blockModeRestoredNotice,
  TerminalModeNotice.normalFallback =>
    '${blockUnavailableMessage(l10n, state.unavailableReason)} ${mobile ? l10n.mobileNormalFallback : l10n.normalModeFallbackNotice}',
  null => '',
};

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
