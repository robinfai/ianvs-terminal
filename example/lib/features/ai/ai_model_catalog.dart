import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_models.dart';

/// OpenAI-compatible GET /models, shared by the official gateway and BYOK.
class AiModelCatalog {
  const AiModelCatalog();

  Future<List<String>> fetch(AiConfiguration configuration) async {
    // Listing models does not require a selected model yet.
    final connection = AiConfiguration(
      endpoint: configuration.endpoint,
      apiKey: configuration.apiKey,
      model: 'catalog',
    );
    final completions = connection.completionsUri;
    final uri = completions.replace(
      path: completions.path.replaceFirst(
        RegExp(r'/chat/completions$'),
        '/models',
      ),
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${connection.apiKey.trim()}',
        );
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const AiFailure('models_auth');
        }
        if (response.statusCode != 200) {
          throw const AiFailure('models_unavailable');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 2 * 1024 * 1024) {
            throw const AiFailure('models_invalid');
          }
        }
        final json = jsonDecode(utf8.decode(bytes));
        if (json is! Map || json['data'] is! List) {
          throw const AiFailure('models_invalid');
        }
        final models = <String>{};
        for (final item in json['data'] as List) {
          if (item is! Map || item['id'] is! String) {
            throw const AiFailure('models_invalid');
          }
          final id = item['id'] as String;
          if (id.trim().isEmpty || id.length > 200) {
            throw const AiFailure('models_invalid');
          }
          models.add(id);
        }
        return models.toList()..sort();
      })().timeout(const Duration(seconds: 20));
    } on AiFailure {
      rethrow;
    } on FormatException {
      throw const AiFailure('models_invalid');
    } on Object {
      throw const AiFailure('models_unavailable');
    } finally {
      client.close(force: true);
    }
  }
}
