import 'dart:async';

import 'package:app/features/recording/recording_retention_maintenance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'periodic cleanup does not overlap and stop waits for the actual run',
    (tester) async {
      var calls = 0;
      final barrier = Completer<void>();
      final maintenance = RecordingRetentionMaintenance(
        run: () {
          calls++;
          return barrier.future;
        },
        onError: (error) => fail('$error'),
        interval: const Duration(seconds: 1),
      );
      maintenance.start();
      await tester.pump(const Duration(seconds: 3));
      expect(calls, 1);
      var stopped = false;
      final stopping = maintenance.stop().then((_) => stopped = true);
      await tester.pump(const Duration(seconds: 3));
      expect(stopped, isFalse);
      expect(calls, 1);
      barrier.complete();
      await stopping;
      await maintenance.tick();
      await tester.pump(const Duration(seconds: 3));
      expect(calls, 1);
    },
  );

  test(
    'cleanup failures are visible and do not prevent later attempts',
    () async {
      var calls = 0;
      final errors = <Object>[];
      final maintenance = RecordingRetentionMaintenance(
        run: () async {
          if (++calls == 1) throw StateError('fixture disk failure');
        },
        onError: errors.add,
      );
      await maintenance.tick();
      expect(errors.single.toString(), contains('fixture disk failure'));
      await maintenance.tick();
      expect(calls, 2);
      expect(errors, hasLength(1));
      await maintenance.stop();
    },
  );

  test(
    'shutdown suppresses a late cleanup error after settling the run',
    () async {
      final barrier = Completer<void>();
      final errors = <Object>[];
      final maintenance = RecordingRetentionMaintenance(
        run: () => barrier.future,
        onError: errors.add,
      );
      final running = maintenance.tick();
      final stopping = maintenance.stop();
      barrier.completeError(StateError('late failure'));
      await running;
      await stopping;
      expect(errors, isEmpty);
    },
  );
}
