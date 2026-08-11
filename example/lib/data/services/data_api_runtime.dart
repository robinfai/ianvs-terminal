import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configuration/data_api_configuration.dart';

typedef DataApiRuntimeClose = Future<void> Function();

class DataApiRuntime {
  DataApiRuntime.remote({required this.baseUri})
    : deployment = DataApiDeployment.remote,
      localAccessToken = null,
      encryptionKey = null,
      _closeLocalSidecar = null;

  DataApiRuntime.local({
    required this.baseUri,
    required this.localAccessToken,
    required this.encryptionKey,
    required DataApiRuntimeClose closeLocalSidecar,
  }) : deployment = DataApiDeployment.local,
       _closeLocalSidecar = closeLocalSidecar;

  final Uri baseUri;
  final DataApiDeployment deployment;
  final String? localAccessToken;
  final String? encryptionKey;
  final DataApiRuntimeClose? _closeLocalSidecar;

  Future<void>? _closeFuture;

  bool get isLocal => deployment == DataApiDeployment.local;

  Future<void> close() {
    return _closeFuture ??= _closeLocalSidecar?.call() ?? Future<void>.value();
  }
}

final dataApiRuntimeProvider = Provider<DataApiRuntime?>((ref) => null);
