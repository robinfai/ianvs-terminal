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
  });

  test('remote runtime closes without owning a process', () async {
    final runtime = DataApiRuntime.remote(
      baseUri: Uri.parse('https://sync.example.com'),
    );

    await runtime.close();

    expect(runtime.isLocal, isFalse);
  });
}
