import 'package:flutter/material.dart';

import 'terminal_ai_controller.dart';

/// Uses the existing theme colors and a short transition. Reduced motion keeps
/// the same state icon without an indeterminate animation.
class AiRequestIndicator extends StatelessWidget {
  const AiRequestIndicator({required this.controller, super.key});

  final TerminalAiController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final streaming =
        c.phase == AiPhase.connecting ||
        c.phase == AiPhase.waitingForFirstToken ||
        c.phase == AiPhase.generating;
    final failed = c.phase == AiPhase.failed || c.terminalError != null;
    final icon = failed || c.hasUnresolvedSubmission
        ? Icons.error_outline
        : c.takenOver
        ? Icons.pause_circle_outline
        : c.phase == AiPhase.awaitingApproval
        ? Icons.approval_outlined
        : c.busy
        ? Icons.more_horiz
        : c.transcript.isEmpty
        ? Icons.chat_bubble_outline
        : Icons.check_circle_outline;
    final state = failed
        ? 'failed'
        : c.takenOver
        ? 'cancelled'
        : c.phase.name;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 18,
        child: AnimatedSwitcher(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
          child: streaming && !reduced && !failed
              ? CircularProgressIndicator(
                  key: ValueKey('ai-request-$state'),
                  strokeWidth: 2,
                  color: colors.primary,
                )
              : Icon(
                  icon,
                  key: ValueKey('ai-request-$state'),
                  size: 18,
                  color: failed ? colors.error : colors.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}
