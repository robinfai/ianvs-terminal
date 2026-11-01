import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart' show MemoryAiStore;

void main() {
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
