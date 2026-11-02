import 'dart:convert';
import 'dart:io';
import 'package:app/features/ai/ai_model_catalog.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'terminal_ai_test.dart' show MemoryAiStore;

void main() {
  test(
    'models uses normalized paths, bearer auth and OpenAI data IDs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      server.listen((r) async {
        paths.add(r.uri.path);
        expect(r.method, 'GET');
        expect(r.headers.value('Authorization'), 'Bearer catalog-secret');
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode({
            'object': 'list',
            'data': [
              {'id': 'z-model'},
              {'id': 'a-model'},
              {'id': 'z-model'},
            ],
          }),
        );
        await r.response.close();
      });
      for (final path in ['', '/v1/', '/v1/chat/completions', '/v1/ai']) {
        final ids = await const AiModelCatalog().fetch(
          AiConfiguration(
            endpoint: 'http://127.0.0.1:${server.port}$path',
            apiKey: 'catalog-secret',
            model: '',
          ),
        );
        expect(ids, ['a-model', 'z-model']);
      }
      expect(paths, [
        '/v1/models',
        '/v1/models',
        '/v1/models',
        '/v1/ai/models',
      ]);
    },
  );
  test(
    'models rejects redirects, auth failures and malformed responses',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var status = 302;
      var body = '{}';
      var hits = 0;
      server.listen((r) async {
        hits++;
        r.response.statusCode = status;
        r.response.headers.set('location', '/credential-leak');
        r.response.write(body);
        await r.response.close();
      });
      final config = AiConfiguration(
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'test',
        model: '',
      );
      for (final pair in [
        (302, 'models_unavailable'),
        (401, 'models_auth'),
        (403, 'models_auth'),
        (200, 'models_invalid'),
      ]) {
        status = pair.$1;
        await expectLater(
          const AiModelCatalog().fetch(config),
          throwsA(isA<AiFailure>().having((e) => e.code, 'code', pair.$2)),
        );
      }
      expect(hits, 4);
      body = '{"data":[]}';
      expect(await const AiModelCatalog().fetch(config), isEmpty);
    },
  );
  test(
    'official model persists without session token and follows refreshed credentials',
    () async {
      final store = MemoryAiStore(null);
      AiConfiguration gateway(String key) => AiConfiguration(
        endpoint: 'https://official.example/v1/ai',
        apiKey: key,
        model: 'default',
      );
      final settings = AiSettingsController(
        store,
        gatewayConfiguration: gateway('first'),
      );
      await settings.loaded;
      expect(settings.usesGateway, isTrue);
      await settings.save(const AiConfiguration.official(model: 'deepseek'));
      expect(settings.configuration!.model, 'deepseek');
      expect(settings.configuration!.apiKey, 'first');
      expect(jsonEncode(store.value!.toJson()), isNot(contains('first')));
      final persisted = AiConfiguration.fromJson(store.value!.toJson());
      expect(persisted.officialService, isTrue);
      settings.updateGatewayConfiguration(gateway('refreshed'));
      expect(settings.configuration!.model, 'deepseek');
      expect(settings.configuration!.apiKey, 'refreshed');
      final restarted = AiSettingsController(
        MemoryAiStore(persisted),
        gatewayConfiguration: gateway('restart'),
      );
      await restarted.loaded;
      expect(restarted.usesGateway, isTrue);
      expect(restarted.customConfiguration, isNull);
      expect(restarted.configuration!.model, 'deepseek');
      restarted.updateGatewayConfiguration(null);
      expect(restarted.configuration, isNull);
      settings.dispose();
      restarted.dispose();
    },
  );
}
