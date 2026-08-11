import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configuration/data_api_configuration.dart';

typedef DataApiRuntimeClose = Future<void> Function();

/// Marks a close failure where the backing process may still be alive.
///
/// Startup coordinators must retain a poisoned lease for this failure instead
/// of treating the failed close future as proof that the runtime settled.
abstract interface class DataApiRuntimeTerminationUnknownFailure
    implements Exception {}

/// Exposes a nested termination status without replacing the operation's
/// primary error (for example, startup failed and cleanup was unconfirmed).
abstract interface class DataApiRuntimeTerminationFailureCarrier
    implements Exception {
  DataApiRuntimeTerminationUnknownFailure? get terminationFailure;
}

/// Finds an unconfirmed process-termination failure without coupling callers
/// to a concrete data service implementation.
DataApiRuntimeTerminationUnknownFailure? dataApiRuntimeTerminationFailureOf(
  Object? failure,
) {
  return switch (failure) {
    DataApiRuntimeTerminationUnknownFailure() => failure,
    DataApiRuntimeTerminationFailureCarrier(:final terminationFailure) =>
      terminationFailure,
    _ => null,
  };
}

class DataApiRuntime {
  DataApiRuntime.remote({
    required this.baseUri,
    this.remoteAccessToken,
    this.encryptionKey,
  }) : deployment = DataApiDeployment.remote,
       localAccessToken = null,
       _closeLocalSidecar = null;

  DataApiRuntime.local({
    required this.baseUri,
    required this.localAccessToken,
    required this.encryptionKey,
    required DataApiRuntimeClose closeLocalSidecar,
  }) : deployment = DataApiDeployment.local,
       remoteAccessToken = null,
       _closeLocalSidecar = closeLocalSidecar;

  final Uri baseUri;
  final DataApiDeployment deployment;
  final String? localAccessToken;
  final String? remoteAccessToken;
  final String? encryptionKey;
  final DataApiRuntimeClose? _closeLocalSidecar;

  Future<void>? _closeFuture;

  bool get isLocal => deployment == DataApiDeployment.local;

  String? get resourceAccessToken => localAccessToken ?? remoteAccessToken;

  bool get canAccessResources => resourceAccessToken?.isNotEmpty == true;

  Future<void> close() {
    return _closeFuture ??= _closeLocalSidecar?.call() ?? Future<void>.value();
  }
}

final dataApiRuntimeProvider = Provider<DataApiRuntime?>((ref) => null);

final class DataApiStartupWarning {
  const DataApiStartupWarning(this.message);

  final String message;
}

final dataApiStartupWarningProvider = Provider<DataApiStartupWarning?>(
  (ref) => null,
);

final class DataApiStartupRetryResult {
  const DataApiStartupRetryResult({
    required this.succeeded,
    required this.message,
  });

  final bool succeeded;
  final String message;
}

typedef DataApiStartupRetry = Future<DataApiStartupRetryResult> Function();
typedef DataApiMigrationKeepRemote =
    Future<DataApiStartupRetryResult> Function();
typedef DataApiMigrationResetJournal =
    Future<DataApiStartupRetryResult> Function();

final dataApiStartupRetryProvider = Provider<DataApiStartupRetry?>(
  (ref) => null,
);

final dataApiMigrationKeepRemoteProvider =
    Provider<DataApiMigrationKeepRemote?>((ref) => null);

final dataApiMigrationResetJournalProvider =
    Provider<DataApiMigrationResetJournal?>((ref) => null);
