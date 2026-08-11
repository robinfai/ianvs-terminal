import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configuration/data_api_configuration.dart';

typedef DataApiRuntimeClose = Future<void> Function();

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
