import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data/configuration/data_api_configuration.dart';
import 'data/configuration/data_api_configuration_repository.dart';
import 'data/services/portable_master_key.dart';
import 'startup/app_startup_host.dart';
import 'startup/app_startup_models.dart';
import 'startup/production_app_startup.dart';

const _credentialsUrlEnvironment = 'IANVS_SIMULATOR_CREDENTIALS_URL';
const _remoteApiUrlEnvironment = 'IANVS_SIMULATOR_REMOTE_API_URL';
const _simulatorAcceptanceChannel = MethodChannel(
  'dev.ianvs.terminal/simulator-acceptance',
);

/// Test-only credentials fetched from a one-use loopback broker.
///
/// The password and master key never enter process environment, Dart defines,
/// compiled application assets, or the production `main.dart` entrypoint.
final class IosSimulatorAcceptanceConfiguration {
  factory IosSimulatorAcceptanceConfiguration.fromCredentialDocument(
    Map<String, Object?> document, {
    String remoteApiUrl = defaultRemoteDataApiBaseUrl,
  }) {
    final masterKey = document['encryption_key'];
    final username = document['username'];
    final password = document['password'];
    if (masterKey is! String ||
        masterKey.isEmpty ||
        username is! String ||
        username.trim().isEmpty ||
        password is! String ||
        password.isEmpty) {
      throw const FormatException(
        'Simulator acceptance credentials are incomplete or invalid.',
      );
    }
    PortableMasterKey.fromSecret(masterKey);
    final normalizedRemoteApiUrl = remoteApiUrl.trim();
    return IosSimulatorAcceptanceConfiguration._(
      masterKey: masterKey,
      remoteApiUrl: normalizedRemoteApiUrl.isEmpty
          ? defaultRemoteDataApiBaseUrl
          : normalizedRemoteApiUrl,
      username: username.trim(),
      password: password,
    );
  }

  const IosSimulatorAcceptanceConfiguration._({
    required this.masterKey,
    required this.remoteApiUrl,
    required this.username,
    required this.password,
  });

  final String masterKey;
  final String remoteApiUrl;
  final String username;
  final String password;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || !Platform.isIOS) {
    throw UnsupportedError(
      'simulator_main.dart may run only as an iOS Debug simulator target.',
    );
  }

  final launchConfiguration = await _readNativeSimulatorLaunchConfiguration();
  final credentialsUrl = parseIosSimulatorCredentialsUrl(
    launchConfiguration[_credentialsUrlEnvironment],
  );
  if (credentialsUrl == null) {
    runApp(
      AppStartupHost(coordinator: createProductionAppStartupCoordinator()),
    );
    return;
  }
  final configuration =
      IosSimulatorAcceptanceConfiguration.fromCredentialDocument(
        await _getJson(credentialsUrl),
        remoteApiUrl:
            launchConfiguration[_remoteApiUrlEnvironment] ??
            defaultRemoteDataApiBaseUrl,
      );

  final masterKey = PortableMasterKey.fromSecret(configuration.masterKey);
  final repository = PortableMasterKeyRepository(
    // CoreSimulator cannot participate in the user's real iCloud Keychain.
    // This process-only item models receipt of the exact macOS key while the
    // real authentication, vault encryption, and remote persistence paths run.
    storage: _SimulatorAcceptanceMasterKeyStorage(masterKey.portableValue),
    allowCreation: false,
  );
  final coordinator = createProductionAppStartupCoordinator(
    masterKeyRepository: repository,
  );

  await coordinator.start();
  final state = coordinator.state;
  if (state case AppStartupDataSetupRequired(:final settings)) {
    await settings.reconnect(
      DataApiRemoteLoginRequest(
        baseUri: DataApiConfiguration.remote(
          configuration.remoteApiUrl,
        ).remoteBaseUri!,
        username: configuration.username,
        password: configuration.password,
      ),
    );
    await coordinator.retry();
  }
  if (coordinator.state is! AppStartupReady) {
    throw StateError(
      'Simulator acceptance login did not produce a ready application.',
    );
  }

  runApp(AppStartupHost(coordinator: coordinator, startAutomatically: false));
}

/// Parses the optional one-use credential broker URL for the simulator.
///
/// `Uri.tryParse('')` returns an empty URI rather than `null`, so absence must
/// be handled before parsing. Without this guard a normal credential-free
/// simulator launch fails before Flutter can render its first frame.
Uri? parseIosSimulatorCredentialsUrl(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.scheme != 'http' || uri.host != '127.0.0.1') {
    throw const FormatException(
      'Simulator acceptance credentials must use an ephemeral loopback URL.',
    );
  }
  return uri;
}

Future<Map<String, String>> _readNativeSimulatorLaunchConfiguration() async {
  final raw = await _simulatorAcceptanceChannel
      .invokeMapMethod<String, Object?>('readLaunchConfiguration');
  if (raw == null) {
    return const <String, String>{};
  }
  return <String, String>{
    for (final entry in raw.entries)
      if (entry.value is String) entry.key: entry.value! as String,
  };
}

Future<Map<String, Object?>> _getJson(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 5));
    final response = await request.close().timeout(const Duration(seconds: 5));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Simulator credential broker returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      if (buffer.length + chunk.length > 4096) {
        throw const FormatException(
          'Simulator credentials exceeded the 4096-byte limit.',
        );
      }
      return buffer..addAll(chunk);
    });
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Simulator credentials are not a JSON object.',
      );
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

final class _SimulatorAcceptanceMasterKeyStorage
    implements PortableMasterKeyStorage {
  _SimulatorAcceptanceMasterKeyStorage(this.value);

  String value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String portableValue) async {
    value = portableValue;
  }
}
