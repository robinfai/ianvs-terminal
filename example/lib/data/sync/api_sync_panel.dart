import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../ui/components/app_action_button.dart';
import '../../ui/components/app_grouped_section.dart';
import '../../ui/foundation/app_theme_tokens.dart';
import '../configuration/data_api_configuration.dart';
import '../services/data_api_runtime.dart';
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
      return const SizedBox.shrink();
    }
    return const _ConnectedApiSyncPanel();
  }
}

class _ConnectedApiSyncPanel extends ConsumerStatefulWidget {
  const _ConnectedApiSyncPanel();
  @override
  ConsumerState<_ConnectedApiSyncPanel> createState() =>
      _ConnectedApiSyncPanelState();
}

class _ConnectedApiSyncPanelState
    extends ConsumerState<_ConnectedApiSyncPanel> {
  Timer? _successTimer;
  bool _recentSuccess = false;

  void _showSuccess() {
    if (!mounted) return;
    _successTimer?.cancel();
    setState(() => _recentSuccess = true);
    _successTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _recentSuccess = false);
    });
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(localFirstSyncProvider);
    final restoreTransport = ref.watch(applyApiSyncConfigurationProvider);
    final l10n = context.l10n;
    final spacing = context.appTheme.spacing;
    final localOnly =
        ref.watch(dataApiRuntimeProvider)?.deployment ==
        DataApiDeployment.local;
    final phase = localOnly
        ? LocalFirstSyncPhase.disabled
        : sync?.phase ?? LocalFirstSyncPhase.disabled;
    final status = switch (phase) {
      LocalFirstSyncPhase.disabled =>
        context.usesMobileNavigation
            ? l10n.mobileLocalSyncStatus
            : l10n.syncLocalOnly,
      LocalFirstSyncPhase.idle => l10n.syncUpToDate,
      LocalFirstSyncPhase.syncing => l10n.syncInProgress,
      LocalFirstSyncPhase.pending => l10n.syncPending,
      LocalFirstSyncPhase.conflict => l10n.syncConflicts,
      LocalFirstSyncPhase.unavailable => l10n.syncUnavailable,
    };
    if (phase == LocalFirstSyncPhase.disabled) return const SizedBox.shrink();
    final needsAttention =
        phase == LocalFirstSyncPhase.unavailable ||
        phase == LocalFirstSyncPhase.conflict;
    return AppGroupedSection(
      flat: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (needsAttention)
              Text(
                status,
                key: const Key('api-sync-status'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (phase != LocalFirstSyncPhase.disabled) ...[
              if (sync!.failures.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final entry in sync.failures.entries)
                  Text(
                    '${_resourceLabel(context, entry.key)}${_failureMessage(context, entry.value)}',
                    key: ValueKey('sync-failure-${entry.key}'),
                  ),
              ],
              for (final entry in sync.failures.entries)
                if (entry.value.reason ==
                    LocalFirstSyncFailureReason.terminalConfigRepairRequired)
                  AppActionButton(
                    buttonKey: const Key('api-sync-repair-terminal'),
                    label: l10n.syncRepairTerminal,
                    onPressed: phase == LocalFirstSyncPhase.syncing
                        ? null
                        : () async {
                            await sync.repairRemoteDocument(entry.key);
                            if (context.mounted &&
                                sync.phase == LocalFirstSyncPhase.idle) {
                              _showSuccess();
                            }
                          },
                  ),
              if (sync.conflicts.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final entry in sync.conflicts.entries)
                  Text(
                    '${_resourceLabel(context, entry.key)}${entry.value.take(6).map((path) => path == '/defaultProfileId' ? l10n.defaultProfile : path).join(', ')}',
                  ),
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
                tone: AppActionTone.ghost,
                icon: _recentSuccess && phase == LocalFirstSyncPhase.idle
                    ? Icons.check_circle_outline
                    : Icons.sync_rounded,
                label: phase == LocalFirstSyncPhase.syncing
                    ? l10n.syncInProgress
                    : _recentSuccess && phase == LocalFirstSyncPhase.idle
                    ? l10n.syncCompleted
                    : l10n.syncNow,
                onPressed:
                    phase == LocalFirstSyncPhase.syncing ||
                        (sync.enabledButUnavailable && restoreTransport == null)
                    ? null
                    : () async {
                        await sync.retry(restoreTransport: restoreTransport);
                        if (context.mounted &&
                            sync.phase == LocalFirstSyncPhase.idle) {
                          _showSuccess();
                        }
                      },
              ),
            ],
          ],
        ),
      ],
    );
  }
}

String _resourceLabel(BuildContext context, String key) {
  final l10n = context.l10n;
  return switch (key) {
    'profile/default' => '${l10n.syncProfiles}: ',
    'config/preferences' => '${l10n.syncPreferences}: ',
    'config/local-terminal' => '${l10n.syncTerminalConfig}: ',
    _ => '',
  };
}

String _failureMessage(BuildContext context, SyncFailure failure) {
  final l10n = context.l10n;
  return switch (failure.reason) {
    LocalFirstSyncFailureReason.authenticationRequired =>
      l10n.syncAuthenticationRequired,
    LocalFirstSyncFailureReason.network => l10n.syncNetworkFailure,
    LocalFirstSyncFailureReason.timeout => l10n.syncTimeoutFailure,
    LocalFirstSyncFailureReason.tls => l10n.syncTlsFailure,
    LocalFirstSyncFailureReason.encryptionKeyRequired =>
      l10n.syncKeyMissingFailure,
    LocalFirstSyncFailureReason.encryptionMismatch =>
      l10n.syncKeyMismatchFailure,
    LocalFirstSyncFailureReason.invalidData => l10n.syncInvalidDataFailure,
    LocalFirstSyncFailureReason.terminalConfigRepairRequired =>
      l10n.syncTerminalRepairRequired,
    LocalFirstSyncFailureReason.requestRejected =>
      '${l10n.syncRejectedFailure} (HTTP ${failure.httpStatus})',
    LocalFirstSyncFailureReason.revisionConflict => l10n.syncRevisionFailure,
    LocalFirstSyncFailureReason.localStorage => l10n.syncStorageFailure,
    LocalFirstSyncFailureReason.unavailable => l10n.syncUnavailable,
  };
}
