import 'dart:convert';
import 'dart:io';

/// Records only this isolated UI fixture's JSON payloads, never auth headers.
/// The app still uses its production HTTP client and the real model response.
class ModelScenarioGateway {
  ModelScenarioGateway._(this.server, this._key);

  final HttpServer server;
  final String _key;
  final _client = HttpClient();
  final calls = <Map<String, Object?>>[];
  String? _fixtureSession;
  String? _fixtureCwd;

  void bindFixture({required String sessionId, required String cwd}) {
    if (!cwd.startsWith('/private/tmp/trail-model-scenes-')) {
      throw StateError('Only an isolated synthetic fixture may be forwarded');
    }
    _fixtureSession = sessionId;
    _fixtureCwd = cwd;
  }

  void _validateFixturePayload(String body, Object? data) {
    if (_fixtureSession == null ||
        _fixtureCwd == null ||
        body.contains(_key) ||
        body.contains('/Users/') ||
        body.contains('/var/folders/')) {
      throw StateError('Unbound or non-fixture payload');
    }
    void visit(Object? value) {
      if (value is Map) {
        if (value.containsKey('cwd') && value['cwd'] != _fixtureCwd) {
          throw StateError('Non-fixture working directory');
        }
        if (value.containsKey('session_id') &&
            value['session_id'] != _fixtureSession) {
          throw StateError('Non-fixture terminal session');
        }
        for (final child in value.values) {
          visit(child);
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child);
        }
      } else if (value is String && value.startsWith('{')) {
        Object? decoded;
        try {
          decoded = jsonDecode(value);
        } on FormatException {
          return;
        }
        visit(decoded);
      }
    }

    visit(data);
  }

  static Future<ModelScenarioGateway> start(String key) async {
    final gateway = ModelScenarioGateway._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      key,
    );
    gateway.server.listen(gateway._forward);
    return gateway;
  }

  Future<void> _forward(HttpRequest request) async {
    if (request.method != 'POST' ||
        request.uri.path != '/v1/chat/completions' ||
        calls.length >= 20) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await request.response.close();
      return;
    }
    final clock = Stopwatch()..start();
    final record = <String, Object?>{'sequence': calls.length + 1};
    calls.add(record);
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body);
      _validateFixturePayload(body, data);
      record['fixture_payload_validated'] = true;
      record['request'] = data;
      final upstream = await _client.postUrl(
        Uri.parse('http://127.0.0.1:8317/v1/chat/completions'),
      );
      upstream.headers.contentType = ContentType.json;
      upstream.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_key');
      final bytes = utf8.encode(body);
      upstream.contentLength = bytes.length;
      upstream.add(bytes);
      final response = await upstream.close();
      final result = await utf8.decoder.bind(response).join();
      record['http_status'] = response.statusCode;
      record['response'] = jsonDecode(result);
      request.response.statusCode = response.statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(result);
      await request.response.close();
    } on Object catch (error) {
      record['error_type'] = error.runtimeType.toString();
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    } finally {
      record['elapsed_ms'] = clock.elapsedMilliseconds;
    }
  }

  Future<void> close() async {
    _client.close(force: true);
    await server.close(force: true);
  }
}
