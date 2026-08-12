import 'dart:convert';
import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'writes the resource contract with auth and encryption headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      late String method;
      late Uri requestUri;
      late String? authorization;
      late String? encryptionKey;
      late Map<String, Object?> requestBody;
      server.listen((request) async {
        method = request.method;
        requestUri = request.uri;
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        encryptionKey = request.headers.value('X-Ianvs-Encryption-Key');
        requestBody =
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, Object?>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              _validResourceJson(
                id: 'work',
                kind: 'profile',
                data: requestBody['data'],
                sensitive: requestBody['sensitive'],
              ),
            ),
          );
        await request.response.close();
      });
      final client = DataApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/api/'),
        accessToken: 'access-token',
        encryptionKey: 'encryption-key-material',
      );

      final resource = await client.putResource(
        kind: 'profile',
        id: 'work',
        data: const <String, Object?>{'name': 'Work'},
        sensitive: const <String, Object?>{'password': 'secret'},
      );

      expect(method, 'PUT');
      expect(requestUri.path, '/api/v1/resources/profile/work');
      expect(authorization, 'Bearer access-token');
      expect(encryptionKey, 'encryption-key-material');
      expect(requestBody['data'], <String, Object?>{'name': 'Work'});
      expect(resource.revision, 1);
    },
  );

  test('maps 404 to a missing resource', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'error': <String, String>{
              'code': 'not_found',
              'message': 'resource not found',
            },
          }),
        );
      await request.response.close();
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: null,
    );

    expect(await client.getResource(kind: 'config', id: 'missing'), isNull);
  });

  test('migration export requests bounded sensitive pages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late Uri requestUri;
    late String? authorization;
    late String? encryptionKey;
    server.listen((request) async {
      requestUri = request.uri;
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      encryptionKey = request.headers.value('X-Ianvs-Encryption-Key');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'schema_version': 1,
            'source_id': 'local-api-instance',
            'exported_at': '2026-01-01T00:00:00Z',
            'resources': <Object?>[
              _validResourceJson(
                id: 'default',
                kind: 'profile',
                data: const <String, Object?>{'schemaVersion': 1},
                sensitive: const <String, Object?>{'secret': 'encrypted'},
              ),
            ],
            'next_cursor': 'next-page',
          }),
        );
      await request.response.close();
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: 'encryption-key-material',
    );

    final page = await client.exportMigrationPage(cursor: 'current-page');

    expect(requestUri.path, '/v1/migrations/export');
    expect(requestUri.queryParameters, <String, String>{
      'include_deleted': 'false',
      'include_sensitive': 'true',
      'limit': '100',
      'cursor': 'current-page',
    });
    expect(authorization, 'Bearer access-token');
    expect(encryptionKey, 'encryption-key-material');
    expect(page.sourceId, 'local-api-instance');
    expect(page.resources.single.sensitive, isNotNull);
    expect(page.nextCursor, 'next-page');
  });

  test(
    'migration merge sends the selected non-delete conflict policy',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      late Map<String, Object?> requestBody;
      server.listen((request) async {
        requestBody =
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, Object?>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'results': <Object?>[
                <String, Object?>{
                  'kind': 'profile',
                  'id': 'cloud',
                  'status': 'updated',
                },
              ],
            }),
          );
        await request.response.close();
      });
      final client = DataApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        accessToken: 'access-token',
        encryptionKey: null,
      );

      await client.mergeResources(
        sourceId: 'remote-api-instance',
        resources: <DataApiMigrationResource>[
          DataApiMigrationResource(
            id: 'cloud',
            kind: 'profile',
            data: const <String, Object?>{'name': 'Cloud'},
            sourceRevision: 2,
            sourceUpdatedAt: DateTime.utc(2026),
          ),
        ],
        conflictPolicy: DataApiMigrationConflictPolicy.sourceWins,
      );

      expect(requestBody['conflict_policy'], 'source_wins');
      expect(requestBody['propagate_deletes'], isFalse);
    },
  );

  test(
    'real HTTP resource responses require a boolean has_sensitive field',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var responseIndex = 0;
      server.listen((request) async {
        final resource = _validResourceJson();
        if (responseIndex == 0) {
          resource.remove('has_sensitive');
        } else {
          resource['has_sensitive'] = 'false';
        }
        responseIndex += 1;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(resource));
        await request.response.close();
      });
      final client = DataApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        accessToken: 'access-token',
        encryptionKey: null,
      );

      for (var index = 0; index < 2; index += 1) {
        await expectLater(
          client.getResource(kind: 'config', id: 'preferences'),
          throwsFormatException,
        );
      }
      expect(responseIndex, 2);
    },
  );

  test(
    'GET PUT and list reject every missing or mistyped required Resource field',
    () async {
      final invalidDocuments = _invalidRequiredResourceDocuments();
      for (final endpoint in <String>['GET', 'PUT', 'list']) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var responseIndex = 0;
        server.listen((request) async {
          if (request.method == 'PUT') {
            await request.drain<void>();
          }
          final document = invalidDocuments[responseIndex].document;
          responseIndex += 1;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(
                endpoint == 'list'
                    ? <String, Object?>{
                        'resources': <Object?>[document],
                      }
                    : document,
              ),
            );
          await request.response.close();
        });
        final client = DataApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
          accessToken: 'access-token',
          encryptionKey: null,
        );

        for (final invalid in invalidDocuments) {
          final request = switch (endpoint) {
            'GET' => client.getResource(kind: 'config', id: 'preferences'),
            'PUT' => client.putResource(
              kind: 'config',
              id: 'preferences',
              data: const <String, Object?>{},
            ),
            _ => client.listResourcePage(kind: 'config'),
          };
          await expectLater(
            request,
            throwsFormatException,
            reason: '$endpoint ${invalid.name}',
          );
        }
        expect(responseIndex, invalidDocuments.length);
      }
    },
  );

  test('Resource accepts a present data field whose value is null', () {
    final resource = DataApiResource.fromJson(_validResourceJson(data: null));

    expect(resource.data, isNull);
    expect(resource.sourceId, '');
    expect(resource.sourceUpdatedAt, DateTime.utc(2026));
  });

  test(
    'GET and PUT reject mismatched or deleted resource identities',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final responses = <Map<String, Object?>>[
        <String, Object?>{'id': 'other', 'kind': 'config', 'deleted': false},
        <String, Object?>{
          'id': 'preferences',
          'kind': 'profile',
          'deleted': false,
        },
        <String, Object?>{
          'id': 'preferences',
          'kind': 'config',
          'deleted': true,
        },
        <String, Object?>{'id': 'other', 'kind': 'config', 'deleted': false},
        <String, Object?>{
          'id': 'preferences',
          'kind': 'profile',
          'deleted': false,
        },
        <String, Object?>{
          'id': 'preferences',
          'kind': 'config',
          'deleted': true,
        },
      ];
      var responseIndex = 0;
      server.listen((request) async {
        if (request.method == 'PUT') {
          await request.drain<void>();
        }
        final identity = responses[responseIndex];
        responseIndex += 1;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{..._validResourceJson(), ...identity}),
          );
        await request.response.close();
      });
      final client = DataApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        accessToken: 'access-token',
        encryptionKey: null,
      );

      for (var index = 0; index < 3; index += 1) {
        await expectLater(
          client.getResource(kind: 'config', id: 'preferences'),
          throwsA(isA<DataApiProtocolException>()),
        );
      }
      for (var index = 0; index < 3; index += 1) {
        await expectLater(
          client.putResource(
            kind: 'config',
            id: 'preferences',
            data: const <String, Object?>{},
          ),
          throwsA(isA<DataApiProtocolException>()),
        );
      }
      expect(responseIndex, 6);
    },
  );

  test('resource lists expose bounded opaque cursor pages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final queries = <Map<String, String>>[];
    server.listen((request) async {
      queries.add(Map<String, String>.of(request.uri.queryParameters));
      final cursor = request.uri.queryParameters['cursor'];
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'resources': <Object?>[
              _validResourceJson(
                id: cursor == null ? 'first' : 'second',
                kind: 'profile',
              ),
            ],
            if (cursor == null) 'next_cursor': 'opaque-next-page',
          }),
        );
      await request.response.close();
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: null,
    );

    final first = await client.listResourcePage(kind: 'profile', limit: 1);
    final second = await client.listResourcePage(
      kind: 'profile',
      limit: 1,
      cursor: first.nextCursor,
    );

    expect(first.resources.single.id, 'first');
    expect(first.nextCursor, 'opaque-next-page');
    expect(second.resources.single.id, 'second');
    expect(second.nextCursor, isNull);
    expect(queries, <Map<String, String>>[
      <String, String>{'limit': '1', 'kind': 'profile'},
      <String, String>{
        'limit': '1',
        'cursor': 'opaque-next-page',
        'kind': 'profile',
      },
    ]);
    expect(DataApiClient.maximumPageSize, 100);
    expect(DataApiClient.maximumCursorBytes, 1024);
    expect(DataApiClient.maximumJsonResponseBytes, 12 * 1024 * 1024);
    expect(DataApiClient.maximumJsonRequestBytes, 12 * 1024 * 1024);
  });

  test('rejects oversized request and response cursors', () async {
    var clientCreated = false;
    final offlineClient = DataApiClient(
      baseUri: Uri.parse('https://sync.example.com/'),
      accessToken: 'access-token',
      encryptionKey: null,
      httpClientFactory: () {
        clientCreated = true;
        return HttpClient();
      },
    );

    await expectLater(
      offlineClient.listResourcePage(cursor: List.filled(300, '😀').join()),
      throwsA(isA<DataApiProtocolException>()),
    );
    expect(clientCreated, isFalse);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'resources': const <Object?>[],
            'next_cursor': List<String>.filled(1025, 'x').join(),
          }),
        );
      await request.response.close();
    });
    final onlineClient = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: null,
    );

    await expectLater(
      onlineClient.listResourcePage(),
      throwsA(isA<DataApiProtocolException>()),
    );
  });

  test('fails closed before transport when remote auth is absent', () async {
    var clientCreated = false;
    final client = DataApiClient(
      baseUri: Uri.parse('https://sync.example.com/'),
      accessToken: null,
      encryptionKey: null,
      httpClientFactory: () {
        clientCreated = true;
        return HttpClient();
      },
    );

    await expectLater(
      client.listResourcePage(kind: 'profile'),
      throwsA(isA<DataApiAuthenticationRequiredException>()),
    );
    expect(clientCreated, isFalse);
  });

  test('surfaces the backend error contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.conflict
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'error': <String, String>{
              'code': 'revision_conflict',
              'message': 'expected revision did not match',
            },
          }),
        );
      await request.response.close();
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: null,
    );

    await expectLater(
      client.putResource(
        kind: 'config',
        id: 'local-terminal',
        data: const <String, Object?>{},
      ),
      throwsA(
        isA<DataApiRequestException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'revision_conflict'),
      ),
    );
  });

  test('rejects unsafe base URLs at the client boundary', () {
    for (final value in <String>[
      'ftp://sync.example.com/',
      'https://user:password@sync.example.com/',
      'https://sync.example.com/?token=leak',
      'https://sync.example.com/#fragment',
      '/relative/data-api',
    ]) {
      expect(
        () => DataApiClient(
          baseUri: Uri.parse(value),
          accessToken: 'access-token',
          encryptionKey: 'encryption-key-material',
        ),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test(
    'does not follow redirects or forward credentials to another origin',
    () async {
      final redirectedServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => redirectedServer.close(force: true));
      var redirectedRequestCount = 0;
      String? redirectedAuthorization;
      String? redirectedEncryptionKey;
      redirectedServer.listen((request) async {
        redirectedRequestCount += 1;
        redirectedAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        redirectedEncryptionKey = request.headers.value(
          'X-Ianvs-Encryption-Key',
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{}');
        await request.response.close();
      });
      final redirectingServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => redirectingServer.close(force: true));
      redirectingServer.listen((request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${redirectedServer.port}/credential-sink',
          );
        await request.response.close();
      });
      final client = DataApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${redirectingServer.port}/'),
        accessToken: 'access-token',
        encryptionKey: 'encryption-key-material',
      );

      await expectLater(
        client.getResource(kind: 'profile', id: 'work', includeSensitive: true),
        throwsA(
          isA<DataApiRequestException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.found,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(redirectedRequestCount, 0);
      expect(redirectedAuthorization, isNull);
      expect(redirectedEncryptionKey, isNull);
    },
  );

  test('bounds response bytes before decoding JSON', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, String>{
            'payload': List<String>.filled(128, 'x').join(),
          }),
        );
      await request.response.close();
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: null,
      maximumResponseBytes: 32,
    );

    await expectLater(
      client.listResourcePage(),
      throwsA(isA<DataApiResponseTooLargeException>()),
    );
  });

  test('rejects an oversized JSON body before opening a request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requestCount = 0;
    server.listen((request) async {
      requestCount += 1;
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: null,
      maximumRequestBytes: 32,
    );

    await expectLater(
      client.putResource(
        kind: 'config',
        id: 'too-large',
        data: <String, Object?>{'payload': List.filled(128, 'x').join()},
      ),
      throwsA(isA<DataApiRequestTooLargeException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(requestCount, 0);
  });

  test('reports malformed JSON as a typed protocol error', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('not-json');
      await request.response.close();
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: null,
    );

    await expectLater(
      client.listResourcePage(),
      throwsA(isA<DataApiProtocolException>()),
    );
  });

  test('applies a deadline to the entire request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      // Intentionally leave the response open until the client deadline.
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: null,
      requestTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(
      client.listResourcePage(),
      throwsA(isA<DataApiTimeoutException>()),
    );
  });

  test(
    'two-step login issues only after prepared operation is completed',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      Map<String, Object?>? beginBody;
      Map<String, Object?>? completeBody;
      String? validationAuthorization;
      String? validationEncryptionKey;
      server.listen((request) async {
        paths.add(request.uri.toString());
        if (request.uri.path == '/v1/auth/login/begin') {
          beginBody =
              (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                  .cast<String, Object?>();
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'operation_id': List<String>.filled(43, 'A').join(),
                'kind': 'login',
                'expires_at': DateTime.now()
                    .add(const Duration(minutes: 5))
                    .toUtc()
                    .toIso8601String(),
              }),
            );
        } else if (request.uri.path == '/v1/auth/login/complete') {
          completeBody =
              (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                  .cast<String, Object?>();
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'token': 'issued-access-token',
                'expires_at': DateTime.now()
                    .add(const Duration(hours: 1))
                    .toUtc()
                    .toIso8601String(),
                'user': <String, Object?>{'id': 1, 'username': 'alice'},
              }),
            );
        } else if (request.uri.path == '/v1/me') {
          validationAuthorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{'id': 1, 'username': 'alice'}),
            );
        } else {
          validationEncryptionKey = request.headers.value(
            'X-Ianvs-Encryption-Key',
          );
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'verified': true,
                'basis': 'account_key_verifier',
              }),
            );
        }
        await request.response.close();
      });
      final baseUri = Uri.parse('http://127.0.0.1:${server.port}/');
      final unauthenticatedClient = DataApiClient(
        baseUri: baseUri,
        accessToken: null,
        encryptionKey: null,
      );
      final operation = await unauthenticatedClient.beginLogin(
        username: 'alice',
        password: 'ephemeral-password',
      );
      final login = await unauthenticatedClient.completeLogin(
        operation.operationId,
      );

      await DataApiClient(
        baseUri: baseUri,
        accessToken: login.accessToken,
        encryptionKey: 'encryption-key-material',
      ).validateSession();

      expect(beginBody, <String, Object?>{
        'username': 'alice',
        'password': 'ephemeral-password',
      });
      expect(completeBody, <String, Object?>{
        'operation_id': operation.operationId,
      });
      expect(paths, <String>[
        '/v1/auth/login/begin',
        '/v1/auth/login/complete',
        '/v1/me',
        '/v1/auth/verify-key',
      ]);
      expect(validationAuthorization, 'Bearer issued-access-token');
      expect(validationEncryptionKey, 'encryption-key-material');
    },
  );

  test('session validation exposes a wrong encryption key', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/v1/me') {
        request.response
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode(<String, Object?>{'username': 'alice'}));
      } else {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write(
            jsonEncode(<String, Object?>{
              'error': <String, String>{
                'code': 'invalid_encryption_key',
                'message': 'the encryption key is invalid',
              },
            }),
          );
      }
      await request.response.close();
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'issued-access-token',
      encryptionKey: 'wrong-encryption-key',
    );

    await expectLater(
      client.validateSession(),
      throwsA(
        isA<DataApiRequestException>().having(
          (error) => error.code,
          'code',
          'invalid_encryption_key',
        ),
      ),
    );
  });

  test('logout uses the bounded authenticated revocation contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late String method;
    late String path;
    String? authorization;
    server.listen((request) async {
      method = request.method;
      path = request.uri.path;
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    final client = DataApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      accessToken: 'access-token',
      encryptionKey: 'encryption-key-material',
      connectionTimeout: const Duration(seconds: 1),
      requestTimeout: const Duration(seconds: 1),
    );

    await client.logout();

    expect(method, 'POST');
    expect(path, '/v1/auth/logout');
    expect(authorization, 'Bearer access-token');
  });

  test(
    'auth operation cancellation is body-only and unauthenticated',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final operationId = List<String>.filled(43, 'B').join();
      Map<String, Object?>? body;
      String? authorization;
      Uri? requestUri;
      server.listen((request) async {
        requestUri = request.uri;
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        body = (jsonDecode(await utf8.decoder.bind(request).join()) as Map).map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      final client = DataApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        accessToken: null,
        encryptionKey: null,
      );

      await client.cancelAuthOperation(operationId);

      expect(requestUri?.path, '/v1/auth/cancel-operation');
      expect(requestUri?.query, isEmpty);
      expect(authorization, isNull);
      expect(body, <String, Object?>{'operation_id': operationId});
      await expectLater(
        client.cancelAuthOperation('not-an-operation-id'),
        throwsFormatException,
      );
    },
  );
}

Map<String, Object?> _validResourceJson({
  String id = 'preferences',
  String kind = 'config',
  Object? data = const <String, Object?>{},
  Object? sensitive,
}) {
  return <String, Object?>{
    'id': id,
    'kind': kind,
    'data': data,
    'sensitive': ?sensitive,
    'has_sensitive': sensitive != null,
    'revision': 1,
    'source_id': '',
    'source_revision': 1,
    'source_updated_at': '2026-01-01T00:00:00Z',
    'deleted': false,
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  };
}

List<({String name, Map<String, Object?> document})>
_invalidRequiredResourceDocuments() {
  const requiredFields = <String>[
    'id',
    'kind',
    'data',
    'has_sensitive',
    'revision',
    'source_id',
    'source_revision',
    'source_updated_at',
    'deleted',
    'created_at',
    'updated_at',
  ];
  final result = <({String name, Map<String, Object?> document})>[];
  for (final field in requiredFields) {
    final document = _validResourceJson()..remove(field);
    result.add((name: 'missing $field', document: document));
  }
  final wrongTypes = <String, Object?>{
    'id': 1,
    'kind': 1,
    'has_sensitive': 'false',
    'revision': '1',
    'source_id': 1,
    'source_revision': '1',
    'source_updated_at': 1,
    'deleted': 'false',
    'created_at': 1,
    'updated_at': 1,
  };
  for (final entry in wrongTypes.entries) {
    result.add((
      name: 'mistyped ${entry.key}',
      document: _validResourceJson()..[entry.key] = entry.value,
    ));
  }
  for (final field in <String>[
    'source_updated_at',
    'created_at',
    'updated_at',
  ]) {
    result.add((
      name: 'invalid RFC3339 $field',
      document: _validResourceJson()..[field] = '2026-02-30T00:00:00Z',
    ));
  }
  for (final entry in const <String, Object>{
    'revision': 0,
    'source_revision': 0,
  }.entries) {
    result.add((
      name: 'non-positive ${entry.key}',
      document: _validResourceJson()..[entry.key] = entry.value,
    ));
  }
  return result;
}
