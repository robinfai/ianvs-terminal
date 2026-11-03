import 'dart:async';

import 'package:app/features/sessions/session_controller.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'disposing the file provider waits for application persistence before closing workers',
    () async {
      final barrier = Completer<void>();
      final shutdown = AppShutdownCoordinator();
      shutdown.registerTask(
        'pending-library-publication',
        () => barrier.future,
      );
      final container = ProviderContainer(
        overrides: [appShutdownCoordinatorProvider.overrideWithValue(shutdown)],
      );
      final api = container.read(sampledRecordingFileApiProvider);
      container.dispose();
      expect(shutdown.hasStarted, isTrue);
      try {
        // An invalid request is rejected before loading FFI. Its error distinguishes
        // a live worker pool from one prematurely disposed with application work.
        await expectLater(api.run('invalid', {}), throwsArgumentError);
      } finally {
        barrier.complete();
      }
      expect((await shutdown.settle()).safeToTerminate, isTrue);
      await expectLater(api.run('invalid', {}), throwsStateError);
    },
  );
}
