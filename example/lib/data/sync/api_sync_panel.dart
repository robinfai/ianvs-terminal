import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../ui/components/app_action_button.dart';
import '../../ui/foundation/app_theme_tokens.dart';
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
    final restoreTransport = ref.watch(applyApiSyncConfigurationProvider);
    final l10n = context.l10n;
    final spacing = context.appTheme.spacing;
    final phase = sync?.phase ?? LocalFirstSyncPhase.disabled;
    final status = switch (phase) {
      LocalFirstSyncPhase.disabled => l10n.syncLocalOnly,
      LocalFirstSyncPhase.idle => l10n.syncUpToDate,
      LocalFirstSyncPhase.syncing => l10n.syncInProgress,
      LocalFirstSyncPhase.pending => l10n.syncPending,
      LocalFirstSyncPhase.conflict => l10n.syncConflicts,
      LocalFirstSyncPhase.unavailable =>
        sync?.failureReason ==
                LocalFirstSyncFailureReason.authenticationRequired
            ? l10n.syncAuthenticationRequired
            : l10n.syncUnavailable,
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
            SizedBox(height: spacing.md),
            AppActionButton(
              buttonKey: const Key('api-sync-now'),
              tone: AppActionTone.secondary,
              icon: Icons.sync_rounded,
              label: l10n.syncNow,
              onPressed:
                  phase == LocalFirstSyncPhase.syncing ||
                      (sync.enabledButUnavailable && restoreTransport == null)
                  ? null
                  : () => sync.retry(restoreTransport: restoreTransport),
            ),
          ],
        ],
      ),
    );
  }
}
