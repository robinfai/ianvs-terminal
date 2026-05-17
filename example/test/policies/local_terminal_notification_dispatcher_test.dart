import 'package:app/features/policies/local_terminal_notification_dispatcher.dart';
import 'package:app/features/policies/local_terminal_policy_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal notification dispatcher', () {
    test('returns null when focus policy suppresses notification', () {
      final intent = LocalTerminalNotificationDispatcher.resolve(
        policy: const LocalTerminalNotificationPolicy(),
        type: LocalTerminalNotificationEventType.bell,
        focused: true,
      );

      expect(intent, isNull);
    });

    test('returns badge intent for unfocused bell', () {
      final intent = LocalTerminalNotificationDispatcher.resolve(
        policy: const LocalTerminalNotificationPolicy(),
        type: LocalTerminalNotificationEventType.bell,
        focused: false,
      );

      expect(intent, isNotNull);
      expect(intent!.target, LocalTerminalMonitorTarget.badge);
    });

    test('requires threshold for long running command finished', () {
      final short = LocalTerminalNotificationDispatcher.resolve(
        policy: const LocalTerminalNotificationPolicy(),
        type: LocalTerminalNotificationEventType.longRunningCommandFinished,
        focused: false,
        observedDuration: const Duration(seconds: 2),
      );
      final long = LocalTerminalNotificationDispatcher.resolve(
        policy: const LocalTerminalNotificationPolicy(),
        type: LocalTerminalNotificationEventType.longRunningCommandFinished,
        focused: false,
        observedDuration: const Duration(seconds: 40),
      );

      expect(short, isNull);
      expect(long, isNotNull);
      expect(long!.target, LocalTerminalMonitorTarget.systemNotification);
    });
  });
}
