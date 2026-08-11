import 'dart:async';

import 'package:app/data/services/data_api_lifecycle.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('disposing the app root closes the local sidecar once', (
    tester,
  ) async {
    var closeCount = 0;
    final runtime = DataApiRuntime.local(
      baseUri: Uri.parse('http://127.0.0.1:49152'),
      localAccessToken: 'access-token',
      encryptionKey: 'encryption-key',
      closeLocalSidecar: () async {
        closeCount += 1;
      },
    );
    await tester.pumpWidget(
      DataApiLifecycleBoundary(
        runtime: runtime,
        shutdownCoordinator: AppShutdownCoordinator(),
        child: const SizedBox.shrink(),
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('native shutdown request awaits all registered cleanup tasks', (
    tester,
  ) async {
    const channel = MethodChannel('test/app/shutdown');
    const codec = StandardMethodCodec();
    final coordinator = AppShutdownCoordinator();
    final extraTaskGate = Completer<void>();
    var runtimeCloseCount = 0;
    var extraTaskCount = 0;
    final runtime = DataApiRuntime.local(
      baseUri: Uri.parse('http://127.0.0.1:49152'),
      localAccessToken: 'access-token',
      encryptionKey: 'encryption-key',
      closeLocalSidecar: () async {
        runtimeCloseCount += 1;
      },
    );
    coordinator.registerTask('extra-cleanup', () async {
      extraTaskCount += 1;
      await extraTaskGate.future;
    });
    await tester.pumpWidget(
      DataApiLifecycleBoundary(
        runtime: runtime,
        shutdownCoordinator: coordinator,
        shutdownChannel: channel,
        child: const SizedBox.shrink(),
      ),
    );

    final response = Completer<Object?>();
    unawaited(
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('requestShutdown')),
        (data) {
          try {
            response.complete(codec.decodeEnvelope(data!));
          } catch (error, stackTrace) {
            response.completeError(error, stackTrace);
          }
        },
      ),
    );
    await tester.pump();

    expect(runtimeCloseCount, 0);
    expect(extraTaskCount, 1);
    expect(response.isCompleted, isFalse);

    extraTaskGate.complete();
    await tester.pump();
    final message = (await response.future)! as Map<Object?, Object?>;

    expect(runtimeCloseCount, 1);
    expect(message['completed'], isTrue);
    expect(message['totalTaskCount'], 2);
    expect(message['settledTaskCount'], 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(runtimeCloseCount, 1);
    expect(extraTaskCount, 1);
  });
}
