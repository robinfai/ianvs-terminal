import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'terminal_ai_controller.dart';

/// Uses the existing theme colors and a short transition. Reduced motion keeps
/// the same state icon without an indeterminate animation.
class AiRequestIndicator extends StatelessWidget {
  const AiRequestIndicator({
    required this.controller,
    this.pulse = false,
    super.key,
  });

  final TerminalAiController controller;
  final bool pulse;

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
    if (pulse && c.busy && !failed) {
      return ExcludeSemantics(
        child: _ActivityDots(
          key: ValueKey('ai-request-$state'),
          reduced: reduced,
          color: colors.primary,
        ),
      );
    }
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

class _ActivityDots extends StatefulWidget {
  const _ActivityDots({required this.reduced, required this.color, super.key});
  final bool reduced;
  final Color color;
  @override
  State<_ActivityDots> createState() => _ActivityDotsState();
}

class _ActivityDotsState extends State<_ActivityDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  @override
  void initState() {
    super.initState();
    if (!widget.reduced) unawaited(_motion.repeat());
  }

  @override
  void didUpdateWidget(_ActivityDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduced) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      unawaited(_motion.repeat());
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 18,
    child: AnimatedBuilder(
      animation: _motion,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 3; i++)
            Opacity(
              opacity: widget.reduced
                  ? .65
                  : .35 +
                        .65 *
                            (1 +
                                math.sin(
                                  (_motion.value - i * .16) * math.pi * 2,
                                )) /
                            2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 5),
              ),
            ),
        ],
      ),
    ),
  );
}
