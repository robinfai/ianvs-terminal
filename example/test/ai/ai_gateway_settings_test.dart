import 'dart:convert';
import 'dart:io';

import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_model_catalog.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/persistence_repository_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart' show FakeTerminal, MemoryAiStore;

class _RecordingApi implements AiApi {
  final configurations = <AiConfiguration>[];
  @override
  Future<AiReply> complete(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
  ) async {
    configurations.add(configuration);
    return const AiReply(text: 'OK');
  }
}

void main() {
  test('sync re-login refreshes official models without restarting', () async {
    final directory = await Directory.systemTemp.createTemp('ai-relogin-');
    addTearDown(() => directory.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final modelTokens = <String?>[];
    server.listen((request) async {
      await request.drain<void>();
      Object response = {'resources': <Object>[], 'next_cursor': ''};
      if (request.uri.path == '/v1/ai/models') {
        final token = request.headers.value(HttpHeaders.authorizationHeader);
        modelTokens.add(token);
        if (token != 'Bearer new-session') {
          request.response.statusCode = HttpStatus.unauthorized;
        } else {
          response = {
            'data': [
              {'id': 'available-model'},
            ],
          };
        }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    DataApiRuntime runtime(String token) => DataApiRuntime.remote(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      remoteAccessToken: token,
    );
    final composition = PersistenceRepositoryComposition.forRuntime(
      runtime('expired-session'),
      profileExportDirectoryResolver: () async => directory,
      masterKeyRepository: PortableMasterKeyRepository(
        storage: _MasterKeyStorage(),
        allowLegacyMigration: false,
      ),
    );
    addTearDown(composition.sync.close);
    final container = ProviderContainer(
      overrides: [
        dataApiRuntimeSourceProvider.overrideWithValue(
          composition.runtimeSource,
        ),
        aiConfigurationStoreProvider.overrideWithValue(MemoryAiStore()),
      ],
    );
    addTearDown(container.dispose);
    final settings = container.read(aiSettingsProvider);
    await settings.loaded;
    await settings.save(const AiConfiguration.official(model: 'preferred'));
    final oldUsage = settings.usage;
    const catalog = AiModelCatalog();
    await expectLater(
      catalog.fetch(settings.gatewayConfiguration!),
      throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'models_auth')),
    );

    await composition.configureSyncRuntime(runtime('new-session'));
    expect(settings.gatewayConfiguration!.apiKey, 'new-session');
    await container.pump();
    expect(container.read(aiSettingsProvider), same(settings));
    expect(settings.usage, isNot(same(oldUsage)));
    expect(settings.gatewayConfiguration!.model, 'preferred');
    expect(await catalog.fetch(settings.gatewayConfiguration!), [
      'available-model',
    ]);
    expect(modelTokens, ['Bearer expired-session', 'Bearer new-session']);

    await composition.configureSyncRuntime(null);
    expect(settings.gatewayConfiguration, isNull);
    await container.pump();
    expect(container.read(dataApiRuntimeProvider), isNull);
    expect(settings.gatewayConfiguration, isNull);
    expect(settings.usage, isNull);
  });

  test(
    'live session follows custom and gateway switches after runtime refresh',
    () async {
      DataApiRuntime runtime(String token) => DataApiRuntime.remote(
        baseUri: Uri.parse('https://backend.example/'),
        remoteAccessToken: token,
      );
      final container = ProviderContainer(
        overrides: [
          dataApiRuntimeProvider.overrideWithValue(runtime('first-token')),
          aiConfigurationStoreProvider.overrideWithValue(MemoryAiStore()),
        ],
      );
      addTearDown(container.dispose);
      final settings = container.read(aiSettingsProvider);
      await settings.loaded;
      final oldUsage = settings.usage;
      final api = _RecordingApi();
      final controller = TerminalAiController(
        settings: settings,
        terminal: FakeTerminal(),
        api: api,
      );
      addTearDown(controller.dispose);
      await controller.ask('first');
      container.updateOverrides([
        dataApiRuntimeProvider.overrideWithValue(runtime('second-token')),
        aiConfigurationStoreProvider.overrideWithValue(settings.store),
      ]);
      final current = container.read(aiSettingsProvider);
      await current.loaded;
      expect(current, same(settings));
      expect(current.usage, isNot(same(oldUsage)));
      await current.save(null);
      await controller.ask('backend');
      expect(api.configurations.last.apiKey, 'second-token');
      expect(
        api.configurations.last.completionsUri.path,
        '/v1/ai/chat/completions',
      );
      await current.save(
        const AiConfiguration(
          endpoint: 'https://custom.example/v1',
          apiKey: 'custom-token',
          model: 'custom',
        ),
      );
      await controller.ask('custom');
      expect(api.configurations.last.apiKey, 'custom-token');
      await current.save(null);
      await controller.ask('backend again');
      expect(api.configurations.last.apiKey, 'second-token');
      expect(api.configurations, hasLength(4));
      expect(
        controller.transcript.where((e) => e.role == 'user'),
        hasLength(4),
      );
      container.updateOverrides([
        dataApiRuntimeProvider.overrideWithValue(null),
        aiConfigurationStoreProvider.overrideWithValue(settings.store),
      ]);
      expect(container.read(aiSettingsProvider), same(settings));
      expect(settings.configuration, isNull);
      expect(settings.usage, isNull);
    },
  );

  test(
    'backend credentials stay ephemeral and clearing custom settings restores gateway',
    () async {
      final store = MemoryAiStore(null);
      const gateway = AiConfiguration(
        endpoint: 'https://backend.example/v1/ai',
        apiKey: 'login-session-token',
        model: 'default',
      );
      final settings = AiSettingsController(
        store,
        gatewayConfiguration: gateway,
      );
      addTearDown(settings.dispose);
      await settings.loaded;
      expect(settings.usesGateway, isTrue);
      expect(settings.hasLlmConfiguration, isTrue);
      expect(
        settings.configuration!.completionsUri.toString(),
        'https://backend.example/v1/ai/chat/completions',
      );
      expect(store.value, isNull);
      await settings.save(const AiConfiguration.mock());
      expect(settings.usesGateway, isFalse);
      await settings.save(null);
      expect(settings.usesGateway, isTrue);
      expect(settings.configuration, same(gateway));
      expect(store.value, isNull);
    },
  );
}

class _MasterKeyStorage implements PortableMasterKeyStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String portableValue) async => value = portableValue;
}
