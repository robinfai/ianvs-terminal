import 'package:flutter/material.dart';

import 'local_terminal_shell_ui_wiring_exports.dart';

class LocalTerminalCompletionDiagnosticsPanel extends StatelessWidget {
  const LocalTerminalCompletionDiagnosticsPanel({
    required this.snapshot,
    this.maxItemsPerSection = 3,
    super.key,
  });

  final LocalTerminalShellUiWiringSnapshot snapshot;
  final int maxItemsPerSection;

  @override
  Widget build(BuildContext context) {
    final viewModel = snapshot.facade.diagnosticsViewModel;
    final theme = Theme.of(context);
    final sections = viewModel.sections;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(viewModel.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DiagnosticsCountChip(
                    label: 'Milestones',
                    count: snapshot.blockedMilestoneCount,
                  ),
                  _DiagnosticsCountChip(
                    label: 'Backlog',
                    count: snapshot.blockedBacklogItemCount,
                  ),
                  _DiagnosticsCountChip(
                    label: 'Verification',
                    count: snapshot.blockedVerificationGateCount,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final section in sections) ...[
                Text(section.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final item in section.items.take(maxItemsPerSection))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(item.label),
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiagnosticsCountChip extends StatelessWidget {
  const _DiagnosticsCountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text('$label: $count'),
      ),
    );
  }
}
