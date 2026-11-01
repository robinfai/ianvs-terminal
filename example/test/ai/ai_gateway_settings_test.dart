import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
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
