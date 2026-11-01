import 'dart:convert';
import 'dart:io';

import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Apple remote login', () {
    test(
      'canceling native consent does not prepare a server login or issue a token',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final paths = <String>[];
        final nonce = base64Url
            .encode(List<int>.filled(32, 9))
            .replaceAll('=', '');
        server.listen((request) async {
          paths.add(request.uri.path);
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'nonce': nonce}));
          await request.response.close();
        });
        final authenticator = DataApiClientRemoteAuthenticator(
          appleIdentityProvider: (receivedNonce) async {
            expect(receivedNonce, nonce);
            throw const DataApiAppleLoginCanceled();
          },
        );
        await expectLater(
          authenticator.begin(
            DataApiRemoteLoginRequest.apple(
              baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
            ),
          ),
          throwsA(isA<DataApiAppleLoginCanceled>()),
        );
        expect(paths, ['/v1/auth/apple/challenge']);
      },
    );

    test(
      'retains Apple method and historical credentials when attaching the local key',
      () {
        final request = DataApiRemoteLoginRequest.apple(
          baseUri: Uri.parse('https://example.test'),
          username: 'Historical',
          password: 'historical-password',
        ).withEncryptionKey('local-encryption-key-material');
        expect(request.useApple, isTrue);
        expect(request.username, 'historical');
        expect(request.password, 'historical-password');
        expect(request.requireEncryptionKey, 'local-encryption-key-material');
      },
    );
    test('allows Apple-only login without a fake username or password', () {
      final request = DataApiRemoteLoginRequest.apple(
        baseUri: Uri.parse('https://example.test'),
      ).withEncryptionKey('local-encryption-key-material');
      expect(request.useApple, isTrue);
      expect(request.username, isEmpty);
      expect(request.password, isEmpty);
    });
    test(
      'rejects incomplete historical credentials and insecure remote origins',
      () {
        expect(
          () => DataApiRemoteLoginRequest.apple(
            baseUri: Uri.parse('https://example.test'),
            username: 'alice',
          ),
          throwsFormatException,
        );
        expect(
          () => DataApiRemoteLoginRequest.apple(
            baseUri: Uri.parse('http://example.test'),
          ),
          throwsFormatException,
        );
      },
    );
    test(
      'sends proof and old-account credentials without disclosing the local master key',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final nonce = base64Url
            .encode(List<int>.filled(32, 4))
            .replaceAll('=', '');
        final requests = <Map<String, dynamic>>[];
        server.listen((request) async {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          requests.add(body);
          expect(request.headers.value('X-Ianvs-Encryption-Key'), isNull);
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            isNull,
          );
          final response = switch (request.uri.path) {
            '/v1/auth/apple/challenge' => <String, Object?>{'nonce': nonce},
            '/v1/auth/apple/begin' => <String, Object?>{
              'operation_id': nonce,
              'kind': 'login',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            },
            '/v1/auth/login/complete' => <String, Object?>{
              'token': 'session-token',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
              'user': {'id': 'original-id', 'username': 'historical'},
            },
            _ => throw StateError('Unexpected route ${request.uri.path}'),
          };
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
          await request.response.close();
        });
        final client = DataApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          accessToken: null,
          encryptionKey: 'local-master-key-never-send',
        );
        expect(await client.createAppleChallenge(), nonce);
        final operation = await client.beginAppleLogin(
          identityToken: 'apple-identity-proof',
          nonce: nonce,
          username: 'historical',
          password: 'historical-password',
        );
        final login = await client.completeLogin(operation.operationId);
        expect(login.username, 'historical');
        expect(requests[1], {
          'identity_token': 'apple-identity-proof',
          'nonce': nonce,
          'username': 'historical',
          'password': 'historical-password',
        });
        expect(
          jsonEncode(requests),
          isNot(contains('local-master-key-never-send')),
        );
      },
    );
  });
}
