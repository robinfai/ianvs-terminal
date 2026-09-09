import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local runtime closes its sidecar only once', () async {
    var closeCount = 0;
    final runtime = DataApiRuntime.local(
      baseUri: Uri.parse('http://127.0.0.1:49152'),
      localAccessToken: 'access-token',
      encryptionKey: 'encryption-key',
      closeLocalSidecar: () async {
        closeCount += 1;
      },
    );

    await Future.wait(<Future<void>>[runtime.close(), runtime.close()]);

    expect(closeCount, 1);
    expect(runtime.syncIdentity, 'bundled-local');
  });

  test('remote runtime closes without owning a process', () async {
    final runtime = DataApiRuntime.remote(
      baseUri: Uri.parse('https://sync.example.com'),
    );

    await runtime.close();

    expect(runtime.isLocal, isFalse);
  });

  test('remote runtime exposes its supplied stable sync identity', () {
    final runtime = DataApiRuntime.remote(
      baseUri: Uri.parse('https://sync.example.com'),
      remoteAccessToken: 'rotating-token',
      syncIdentity: 'remote:https://sync.example.com/:user:alice',
    );

    expect(runtime.syncIdentity, 'remote:https://sync.example.com/:user:alice');
  });

  test('remote session persists a normalized account sync identity', () {
    final session = DataApiRemoteSession(
      baseUri: Uri.parse('https://sync.example.com'),
      accessToken: 'first-token',
      encryptionKey: 'encryption-key-material',
      expiresAt: DateTime.utc(2030),
      username: ' Alice ',
    );

    final restored = DataApiRemoteSession.fromJson(session.toJson());

    expect(restored.username, 'alice');
    expect(
      restored.syncIdentity,
      'remote:https://sync.example.com/:user:alice',
    );
  });

  test('legacy sessions use isolated token namespaces until next login', () {
    final first = DataApiRemoteSession(
      baseUri: Uri.parse('https://sync.example.com'),
      accessToken: 'first-token',
      encryptionKey: 'encryption-key-material',
      expiresAt: DateTime.utc(2030),
    );
    final second = DataApiRemoteSession(
      baseUri: Uri.parse('https://sync.example.com'),
      accessToken: 'second-token',
      encryptionKey: 'encryption-key-material',
      expiresAt: DateTime.utc(2030),
    );

    expect(first.syncIdentity, isNot(second.syncIdentity));
    expect(DataApiRemoteSession.fromJson(first.toJson()).username, isNull);
  });
}
