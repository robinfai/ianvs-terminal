import 'local_terminal_policy_models.dart';

enum LocalTerminalNotificationEventType {
  bell,
  commandFinished,
  longRunningCommandFinished,
  activity,
  silence,
}

class LocalTerminalNotificationIntent {
  const LocalTerminalNotificationIntent({
    required this.type,
    required this.target,
  });

  final LocalTerminalNotificationEventType type;
  final LocalTerminalMonitorTarget target;
}

class LocalTerminalNotificationDispatcher {
  const LocalTerminalNotificationDispatcher._();

  static LocalTerminalNotificationIntent? resolve({
    required LocalTerminalNotificationPolicy policy,
    required LocalTerminalNotificationEventType type,
    required bool focused,
    Duration? observedDuration,
  }) {
    final rule = switch (type) {
      LocalTerminalNotificationEventType.bell => policy.bell,
      LocalTerminalNotificationEventType.commandFinished =>
        policy.commandFinished,
      LocalTerminalNotificationEventType.longRunningCommandFinished =>
        policy.longRunningCommandFinished,
      LocalTerminalNotificationEventType.activity => policy.activity,
      LocalTerminalNotificationEventType.silence => policy.silence,
    };

    if (!rule.shouldNotify(
      focused: focused,
      observedDuration: observedDuration,
    )) {
      return null;
    }

    return LocalTerminalNotificationIntent(type: type, target: rule.target);
  }
}
