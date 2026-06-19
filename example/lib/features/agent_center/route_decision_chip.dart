import 'package:flutter/material.dart';

import '../../ui/foundation/app_theme_tokens.dart';
import 'agent_intent_router.dart';

enum RouteDecisionOverrideTarget { shell, agent }

class RouteDecisionOverride {
  const RouteDecisionOverride({
    required this.target,
    required this.originalText,
    required this.decision,
  });

  final RouteDecisionOverrideTarget target;
  final String originalText;
  final InputIntentDecision decision;
}

class RouteDecisionChip extends StatelessWidget {
  const RouteDecisionChip({
    super.key,
    required this.decision,
    required this.originalText,
    this.onOverride,
  });

  final InputIntentDecision decision;
  final String originalText;
  final ValueChanged<RouteDecisionOverride>? onOverride;

  @override
  Widget build(BuildContext context) {
    if (!decision.visible || decision.kind == InputIntentKind.empty) {
      return const SizedBox.shrink();
    }

    final theme = context.appTheme;
    final label = _routeLabel(decision);
    final icon = _routeIcon(decision);
    final tone = _routeTone(theme, decision);
    final shouldChoose =
        decision.requiresUserChoice ||
        decision.route == InputIntentRoute.ambiguous;

    return Semantics(
      container: true,
      label: shouldChoose
          ? 'Route ambiguous. Choose Shell or Agent before sending.'
          : 'Route decision $label',
      child: DecoratedBox(
        key: const Key('agent-route-decision-chip'),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(theme.radius.md),
          border: Border.all(color: tone.border),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.sm,
            vertical: theme.spacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: tone.foreground),
              SizedBox(width: theme.spacing.xs),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tone.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (shouldChoose && onOverride != null) ...[
                SizedBox(width: theme.spacing.sm),
                _RouteOverrideButton(
                  key: const Key('agent-route-shell-override'),
                  label: 'Shell',
                  selected: false,
                  onPressed: () =>
                      _emitOverride(RouteDecisionOverrideTarget.shell),
                ),
                SizedBox(width: theme.spacing.xs),
                _RouteOverrideButton(
                  key: const Key('agent-route-agent-override'),
                  label: 'Agent',
                  selected: false,
                  onPressed: () =>
                      _emitOverride(RouteDecisionOverrideTarget.agent),
                ),
              ] else if (!shouldChoose && onOverride != null) ...[
                SizedBox(width: theme.spacing.sm),
                _RouteOverrideButton(
                  key: const Key('agent-route-toggle-override'),
                  label: decision.route == InputIntentRoute.agent
                      ? 'Use Shell'
                      : 'Ask Agent',
                  selected: false,
                  onPressed: () => _emitOverride(
                    decision.route == InputIntentRoute.agent
                        ? RouteDecisionOverrideTarget.shell
                        : RouteDecisionOverrideTarget.agent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _emitOverride(RouteDecisionOverrideTarget target) {
    onOverride?.call(
      RouteDecisionOverride(
        target: target,
        originalText: originalText,
        decision: decision,
      ),
    );
  }
}

class _RouteOverrideButton extends StatelessWidget {
  const _RouteOverrideButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Tooltip(
      message: label,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: Size(0, theme.controls.dense - 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.sm,
            vertical: 0,
          ),
          foregroundColor: selected ? theme.accent : theme.textPrimary,
        ),
        child: Text(label),
      ),
    );
  }
}

String _routeLabel(InputIntentDecision decision) {
  return switch (decision.route) {
    InputIntentRoute.shell => 'Shell',
    InputIntentRoute.agent => 'Agent',
    InputIntentRoute.commandSearch => 'Command search',
    InputIntentRoute.actionSearch => 'Actions',
    InputIntentRoute.savedCommandSearch => 'Saved',
    InputIntentRoute.ambiguous => 'Ambiguous',
    InputIntentRoute.none => 'Ready',
  };
}

IconData _routeIcon(InputIntentDecision decision) {
  return switch (decision.route) {
    InputIntentRoute.shell => Icons.terminal_rounded,
    InputIntentRoute.agent => Icons.auto_awesome_rounded,
    InputIntentRoute.commandSearch => Icons.manage_search_rounded,
    InputIntentRoute.actionSearch => Icons.bolt_rounded,
    InputIntentRoute.savedCommandSearch => Icons.bookmark_rounded,
    InputIntentRoute.ambiguous => Icons.help_outline_rounded,
    InputIntentRoute.none => Icons.edit_note_rounded,
  };
}

_RouteTone _routeTone(AppThemeTokens theme, InputIntentDecision decision) {
  return switch (decision.route) {
    InputIntentRoute.shell => _RouteTone(
      foreground: theme.success,
      background: theme.successContainer.withValues(alpha: 0.72),
      border: theme.success.withValues(alpha: 0.40),
    ),
    InputIntentRoute.agent => _RouteTone(
      foreground: theme.accent,
      background: theme.selected.withValues(alpha: 0.78),
      border: theme.accent.withValues(alpha: 0.38),
    ),
    InputIntentRoute.ambiguous => _RouteTone(
      foreground: theme.warning,
      background: theme.warningContainer.withValues(alpha: 0.74),
      border: theme.warning.withValues(alpha: 0.42),
    ),
    _ => _RouteTone(
      foreground: theme.textMuted,
      background: theme.chrome.withValues(alpha: 0.74),
      border: theme.border,
    ),
  };
}

class _RouteTone {
  const _RouteTone({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}
