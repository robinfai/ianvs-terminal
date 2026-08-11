import 'package:flutter/material.dart';

import '../../data/services/data_api_runtime.dart';

/// Owns the modal and result-message choreography for Data API recovery.
///
/// The Shell supplies only its current context and lifecycle/running-state
/// callbacks. This keeps persistence recovery UI independent from terminal
/// rendering and session state.
final class DataApiStartupRecoveryPresenter {
  const DataApiStartupRecoveryPresenter({
    required BuildContext Function() context,
    required bool Function() isMounted,
    required bool Function() isRunning,
    required void Function(bool running) setRunning,
  }) : _context = context,
       _isMounted = isMounted,
       _isRunning = isRunning,
       _setRunning = setRunning;

  final BuildContext Function() _context;
  final bool Function() _isMounted;
  final bool Function() _isRunning;
  final void Function(bool running) _setRunning;

  Future<void> retry(DataApiStartupRetry action) {
    return _run(
      action: action,
      failurePrefix: 'Data service recovery failed',
      resultKey: 'data-api-startup-retry-result',
    );
  }

  Future<void> keepRemote(DataApiMigrationKeepRemote action) async {
    if (!_isMounted()) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: _context(),
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keep remote data?'),
        content: const Text(
          'Remote values will remain authoritative. The conflicting local '
          'JSON files will not be overwritten or deleted. This decision '
          'applies only to this app installation.',
        ),
        actions: [
          TextButton(
            key: const Key('data-api-keep-remote-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('data-api-keep-remote-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Keep remote data'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _run(
      action: action,
      failurePrefix: 'The migration decision failed',
      resultKey: 'data-api-keep-remote-result',
    );
  }

  Future<void> resetJournal(DataApiMigrationResetJournal action) async {
    if (!_isMounted()) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: _context(),
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset migration journal?'),
        content: const Text(
          'The corrupt per-installation revision journal will be quarantined. '
          'Ianvs Terminal will re-check and retry every local migration item; '
          'remote data will not be overwritten automatically. Persistence '
          'stays locked until the app is restarted after a successful retry.',
        ),
        actions: [
          TextButton(
            key: const Key('data-api-reset-journal-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('data-api-reset-journal-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset and retry'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _run(
      action: action,
      failurePrefix: 'The migration journal reset failed',
      resultKey: 'data-api-reset-journal-result',
    );
  }

  Future<void> _run({
    required Future<DataApiStartupRetryResult> Function() action,
    required String failurePrefix,
    required String resultKey,
  }) async {
    if (!_isMounted() || _isRunning()) {
      return;
    }
    _setRunning(true);
    late DataApiStartupRetryResult result;
    try {
      result = await action();
    } on Object catch (error) {
      result = DataApiStartupRetryResult(
        succeeded: false,
        message: '$failurePrefix: $error',
      );
    } finally {
      if (_isMounted()) {
        _setRunning(false);
      }
    }
    if (!_isMounted()) {
      return;
    }
    ScaffoldMessenger.of(_context()).showSnackBar(
      SnackBar(key: Key(resultKey), content: Text(result.message)),
    );
  }
}
