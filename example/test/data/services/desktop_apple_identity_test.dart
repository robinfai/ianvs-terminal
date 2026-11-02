import 'dart:convert';
import 'dart:io';

import 'package:app/data/configuration/desktop_apple_identity.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app/window_bridge');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final base = Uri.parse('https://example.invalid/');
  final id = 'f' * 43;
  final secret = 's' * 43;

  for (final result in ['success', 'wrong-state', 'cancelled']) {
    test('system Apple authentication: $result', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final operations = <String>[];
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final action = request.uri.pathSegments.last;
        operations.add(action);
        expect(request.uri.toString(), isNot(contains(secret)));
        request.response.headers.contentType = ContentType.json;
        if (action == 'start') {
          request.response.write(
            jsonEncode({
              'id': id,
              'secret': secret,
              'authorization_url':
                  'https://appleid.apple.com/auth/authorize?state=$id',
            }),
          );
        } else {
          expect(body['id'], id);
          expect(body['secret'], secret);
          request.response.write(
            jsonEncode(
              action == 'poll'
                  ? {'identity_token': 'verified-identity', 'nonce': 'nonce'}
                  : {'cancelled': true},
            ),
          );
        }
        await request.response.close();
      });
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancelAppleWebAuthentication') return null;
        expect(call.method, 'appleWebAuthentication');
        expect(call.arguments.toString(), isNot(contains(secret)));
        if (result == 'cancelled') {
          throw PlatformException(code: 'oauth_cancelled');
        }
        return 'work.ianvs.trail.auth://apple?state=${result == 'success' ? id : 'wrong'}';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final client = DataApiClient(
        baseUri: base,
        accessToken: null,
        encryptionKey: null,
        httpClientFactory: () => _LoopbackClient(server.port),
      );
      final operation = desktopAppleIdentity(client, base);
      if (result == 'success') {
        expect((await operation)['identity_token'], 'verified-identity');
        expect(operations, ['start', 'poll']);
      } else {
        await expectLater(
          operation,
          throwsA(
            result == 'cancelled'
                ? isA<PlatformException>()
                : isA<StateError>(),
          ),
        );
        expect(operations, ['start', 'cancel']);
      }
    });
  }
}

// Preserve real HTTP request serialization while routing fixture HTTPS requests
// to the test's local server. Production still requires HTTPS.
class _LoopbackClient implements HttpClient {
  _LoopbackClient(this.port);
  final int port;
  final HttpClient delegate = _RealHttpOverrides().createHttpClient(null);
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => delegate.openUrl(
    method,
    url.replace(scheme: 'http', host: '127.0.0.1', port: port),
  );
  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RealHttpOverrides extends HttpOverrides {}
