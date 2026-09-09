import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import 'json_three_way_merge.dart';
import 'local_first_sync.dart';

class ApiSyncPanel extends StatelessWidget {
  const ApiSyncPanel({super.key});
  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
    } on StateError {
      // Standalone previews of the settings form have no application graph.
      return Text(
        context.l10n.syncLocalOnly,
        key: const Key('api-sync-status'),
      );
    }
    return const _ConnectedApiSyncPanel();
  }
}

class _ConnectedApiSyncPanel extends ConsumerWidget {
  const _ConnectedApiSyncPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(localFirstSyncProvider);
    final l10n = context.l10n;
    final phase = sync?.phase ?? LocalFirstSyncPhase.disabled;
    final status = switch (phase) {
      LocalFirstSyncPhase.disabled => l10n.syncLocalOnly,
      LocalFirstSyncPhase.idle => l10n.syncUpToDate,
      LocalFirstSyncPhase.syncing => l10n.syncInProgress,
      LocalFirstSyncPhase.pending => l10n.syncPending,
      LocalFirstSyncPhase.conflict => l10n.syncConflicts,
      LocalFirstSyncPhase.unavailable => l10n.syncUnavailable,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status, key: const Key('api-sync-status')),
          if (phase != LocalFirstSyncPhase.disabled) ...[
            const SizedBox(height: 8),
            Text(l10n.syncLocalFirstDescription),
            if (sync!.conflicts.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final entry in sync.conflicts.entries)
                Text('${entry.key}: ${entry.value.take(6).join(', ')}'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('api-sync-keep-local'),
                    onPressed: phase == LocalFirstSyncPhase.syncing
                        ? null
                        : () => sync.synchronize(
                            resolution: JsonConflictResolution.preferLocal,
                          ),
                    child: Text(l10n.syncKeepLocal),
                  ),
                  OutlinedButton(
                    key: const Key('api-sync-use-remote'),
                    onPressed: phase == LocalFirstSyncPhase.syncing
                        ? null
                        : () => sync.synchronize(
                            resolution: JsonConflictResolution.preferRemote,
                          ),
                    child: Text(l10n.syncUseRemote),
                  ),
                ],
              ),
            ],
            TextButton(
              key: const Key('api-sync-now'),
              onPressed: phase == LocalFirstSyncPhase.syncing
                  ? null
                  : sync.synchronize,
              child: Text(l10n.syncNow),
            ),
          ],
        ],
      ),
    );
  }
}
