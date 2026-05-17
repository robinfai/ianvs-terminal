import 'package:flutter/material.dart';

import 'local_terminal_shell_ui_wiring_exports.dart';

class LocalTerminalCompletionDiagnosticsPanel extends StatelessWidget {
  const LocalTerminalCompletionDiagnosticsPanel({
    required this.snapshot,
    this.maxItemsPerSection = 6,
    super.key,
  });

  final LocalTerminalShellUiWiringSnapshot snapshot;
  final int maxItemsPerSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = snapshot.facade.commandMenuAdapter.buildSections();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                snapshot.facade.diagnosticsViewModel.title,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CompletionCountChip(
                    label: 'Milestones',
                    count: snapshot.blockedMilestoneCount,
                  ),
                  _CompletionCountChip(
                    label: 'Backlog',
                    count: snapshot.blockedBacklogItemCount,
                  ),
                  _CompletionCountChip(
                    label: 'Verification',
                    count: snapshot.blockedVerificationGateCount,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final section in sections)
                _CompletionDiagnosticsSectionView(
                  section: section,
                  maxItems: maxItemsPerSection,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletionCountChip extends StatelessWidget {
  const _CompletionCountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Chip(
      label: Text('$label: $count'),
      visualDensity: VisualDensity.compact,
      backgroundColor: count == 0
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.errorContainer,
    );
  }
}

class _CompletionDiagnosticsSectionView extends StatelessWidget {
  const _CompletionDiagnosticsSectionView({
    required this.section,
    required this.maxItems,
  });

  final LocalTerminalCompletionCommandMenuSection section;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final visibleItems = section.items.take(maxItems).toList(growable: false);
    final hiddenCount = section.items.length - visibleItems.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(section.title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          for (final item in visibleItems)
            _CompletionDiagnosticsItemView(item: item),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+$hiddenCount more blockers'),
            ),
        ],
      ),
    );
  }
}

class _CompletionDiagnosticsItemView extends StatelessWidget {
  const _CompletionDiagnosticsItemView({required this.item});

  final LocalTerminalCompletionCommandMenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: item.isBlocker
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
              width: 3,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.title, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(item.subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
