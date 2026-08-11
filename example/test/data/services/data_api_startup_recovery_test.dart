import 'dart:async';

import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/data/services/data_api_startup_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every recovery uses and closes a fresh runtime', () async {
    var initialCloseCount = 0;
    var bootstrapCount = 0;
    final freshCloseCounts = <int>[];
    final initial = DataApiRuntime.local(
      baseUri: Uri.parse('http://127.0.0.1:1000/'),
      localAccessToken: 'initial-token',
      encryptionKey: 'encryption-key-material',
      closeLocalSidecar: () async => initialCloseCount += 1,
    );
    final runner = DataApiFreshRuntimeRunner(
      initialRuntime: initial,
      bootstrap: () async {
        bootstrapCount += 1;
        final index = bootstrapCount;
        freshCloseCounts.add(0);
        return DataApiRuntime.local(
          baseUri: Uri.parse('http://127.0.0.1:${1000 + index}/'),
          localAccessToken: 'fresh-token-$index',
          encryptionKey: 'encryption-key-material',
          closeLocalSidecar: () async => freshCloseCounts[index - 1] += 1,
        );
      },
    );

    final firstPort = await runner.run(
      (runtime) async => runtime!.baseUri.port,
    );
    final secondPort = await runner.run(
      (runtime) async => runtime!.baseUri.port,
    );

    expect(firstPort, 1001);
    expect(secondPort, 1002);
    expect(initialCloseCount, 1);
    expect(bootstrapCount, 2);
    expect(freshCloseCounts, <int>[1, 1]);
  });

  test('fresh runtime closes when recovery work fails', () async {
    var closeCount = 0;
    final runner = DataApiFreshRuntimeRunner(
      initialRuntime: null,
      bootstrap: () async => DataApiRuntime.local(
        baseUri: Uri.parse('http://127.0.0.1:2000/'),
        localAccessToken: 'fresh-token',
        encryptionKey: 'encryption-key-material',
        closeLocalSidecar: () async => closeCount += 1,
      ),
    );

    await expectLater(
      runner.run<void>((_) async => throw StateError('migration failed')),
      throwsStateError,
    );

    expect(closeCount, 1);
  });

  test('a later recovery observes a changed remote session', () async {
    var currentToken = 'expired-token';
    final runner = DataApiFreshRuntimeRunner(
      initialRuntime: DataApiRuntime.remote(
        baseUri: Uri.parse('https://sync.example.com/'),
        remoteAccessToken: currentToken,
        encryptionKey: 'encryption-key-material',
      ),
      bootstrap: () async => DataApiRuntime.remote(
        baseUri: Uri.parse('https://sync.example.com/'),
        remoteAccessToken: currentToken,
        encryptionKey: 'encryption-key-material',
      ),
    );

    final first = await runner.run(
      (runtime) async => runtime!.resourceAccessToken,
    );
    currentToken = 'renewed-token';
    final second = await runner.run(
      (runtime) async => runtime!.resourceAccessToken,
    );

    expect(first, 'expired-token');
    expect(second, 'renewed-token');
  });

  test('rejects a concurrent recovery before a second bootstrap', () async {
    final operationStarted = Completer<void>();
    final releaseOperation = Completer<void>();
    var bootstrapCount = 0;
    final runner = DataApiFreshRuntimeRunner(
      initialRuntime: null,
      bootstrap: () async {
        bootstrapCount += 1;
        return DataApiRuntime.remote(
          baseUri: Uri.parse('https://sync.example.com/'),
          remoteAccessToken: 'access-token',
          encryptionKey: 'encryption-key-material',
        );
      },
    );
    final first = runner.run<void>((_) async {
      operationStarted.complete();
      await releaseOperation.future;
    });
    await operationStarted.future;

    await expectLater(
      runner.run<void>((_) async {}),
      throwsA(isA<DataApiStartupRecoveryBusyException>()),
    );
    expect(bootstrapCount, 1);

    releaseOperation.complete();
    await first;
  });
}
