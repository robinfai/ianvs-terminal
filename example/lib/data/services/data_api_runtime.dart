import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configuration/data_api_configuration.dart';
import 'data_api_remote_session_store.dart';

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
    String? syncIdentity,
  }) : deployment = DataApiDeployment.remote,
       syncIdentity =
           syncIdentity ??
           legacyDataApiSyncIdentity(
             baseUri,
             remoteAccessToken ?? 'unavailable',
           ),
       localAccessToken = null,
       _closeLocalSidecar = null;

  DataApiRuntime.local({
    required this.baseUri,
    required this.localAccessToken,
    required this.encryptionKey,
    required DataApiRuntimeClose closeLocalSidecar,
  }) : deployment = DataApiDeployment.local,
       syncIdentity = 'bundled-local',
       remoteAccessToken = null,
       _closeLocalSidecar = closeLocalSidecar;

  final Uri baseUri;
  final DataApiDeployment deployment;
  final String? localAccessToken;
  final String? remoteAccessToken;
  final String? encryptionKey;
  final String syncIdentity;
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

enum DataApiStartupWarningKind { generic, remoteCleanupPending }

final class DataApiStartupWarning {
  const DataApiStartupWarning(this.message)
    : kind = DataApiStartupWarningKind.generic,
      diagnosticMessage = message;

  DataApiStartupWarning.remoteCleanupPending(Object cause)
    : message =
          'Remote sign-out cleanup is pending and will retry the next time the app starts.',
      kind = DataApiStartupWarningKind.remoteCleanupPending,
      diagnosticMessage = cause.toString();

  final String message;
  final DataApiStartupWarningKind kind;
  final String diagnosticMessage;
}

final dataApiStartupWarningProvider = Provider<DataApiStartupWarning?>(
  (ref) => null,
);
