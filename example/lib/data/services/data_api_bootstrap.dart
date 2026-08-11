import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../configuration/data_api_configuration.dart';
import '../configuration/data_api_configuration_repository.dart';
import 'data_api_runtime.dart';
import 'data_api_secret_store.dart';
import 'local_data_api_sidecar.dart';

typedef LocalDataApiRuntimeStarter =
    Future<DataApiRuntime> Function(Directory appSupportDirectory);

class DataApiBootstrap {
  DataApiBootstrap({
    DataApiConfigurationRepository? configurationRepository,
    DataApiSecretStore? secretStore,
    LocalDataApiRuntimeStarter? localRuntimeStarter,
    bool? isMacOS,
  }) : _configurationRepository = configurationRepository,
       _secretStore = secretStore,
       _localRuntimeStarter = localRuntimeStarter,
       _isMacOS = isMacOS ?? Platform.isMacOS;

  final DataApiConfigurationRepository? _configurationRepository;
  final DataApiSecretStore? _secretStore;
  final LocalDataApiRuntimeStarter? _localRuntimeStarter;
  final bool _isMacOS;

  Future<DataApiRuntime?> start({
    required Directory appSupportDirectory,
  }) async {
    final repository =
        _configurationRepository ??
        FileDataApiConfigurationRepository(
          appSupportDirectory: appSupportDirectory,
        );
    final configuration = await repository.load();
    if (configuration.deployment == DataApiDeployment.disabled) {
      return null;
    }
    final remoteBaseUri = configuration.remoteBaseUri;
    if (remoteBaseUri != null) {
      return DataApiRuntime.remote(baseUri: remoteBaseUri);
    }
    if (!_isMacOS) {
      throw UnsupportedError(
        'The bundled local data API is only available on macOS.',
      );
    }
    return (_localRuntimeStarter ?? _startLocalRuntime)(appSupportDirectory);
  }

  Future<DataApiRuntime> _startLocalRuntime(
    Directory appSupportDirectory,
  ) async {
    final secretStore = _secretStore ?? FlutterSecureDataApiSecretStore();
    final localAccessToken = await secretStore.localAccessToken();
    final encryptionKey = await secretStore.encryptionKey();
    final sidecar = await LocalDataApiSidecar.start(
      binary: _resolveLocalApiBinary(),
      database: File(
        '${appSupportDirectory.path}${Platform.pathSeparator}'
        'data-api${Platform.pathSeparator}ianvs.db',
      ),
      localAccessToken: localAccessToken,
    );
    try {
      await _initializeLocalApi(
        baseUri: sidecar.baseUri,
        localAccessToken: localAccessToken,
        encryptionKey: encryptionKey,
      );
    } on Object {
      await sidecar.close();
      rethrow;
    }
    return DataApiRuntime.local(
      baseUri: sidecar.baseUri,
      localAccessToken: localAccessToken,
      encryptionKey: encryptionKey,
      closeLocalSidecar: sidecar.close,
    );
  }

  File _resolveLocalApiBinary() {
    final executable = File(Platform.resolvedExecutable);
    final contentsDirectory = executable.parent.parent;
    return File(
      '${contentsDirectory.path}${Platform.pathSeparator}Resources${Platform.pathSeparator}ianvs-api',
    );
  }

  Future<void> _initializeLocalApi({
    required Uri baseUri,
    required String localAccessToken,
    required String encryptionKey,
  }) async {
    final client = HttpClient();
    try {
      await _waitForHealth(client, baseUri, localAccessToken);
      final request = await client.postUrl(baseUri.resolve('/v1/auth/setup'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $localAccessToken');
      request.write(
        jsonEncode(<String, String>{'encryption_key': encryptionKey}),
      );
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.created) {
        throw HttpException(
          'Local data API setup failed with HTTP ${response.statusCode}.',
          uri: baseUri.resolve('/v1/auth/setup'),
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _waitForHealth(
    HttpClient client,
    Uri baseUri,
    String localAccessToken,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final request = await client.getUrl(baseUri.resolve('/healthz'));
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $localAccessToken',
        );
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) {
          return;
        }
        lastError = HttpException(
          'Health check returned HTTP ${response.statusCode}.',
          uri: baseUri.resolve('/healthz'),
        );
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    throw StateError('Local data API did not become healthy: $lastError');
  }
}
