import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_pump.dart';

void main() {
  group('TerminalFramePumpBackoff', () {
    test('expands idle skip windows and resets on activity', () {
      final backoff = TerminalFramePumpBackoff(
        emptyRefreshesBeforeBackoff: 2,
        initialSkipTicks: 3,
        maxSkipTicks: 8,
      );
      const sessionId = 'session-1';

      expect(backoff.shouldSkipPollingRefresh(sessionId), isFalse);

      backoff.recordRefreshResult(sessionId, hadActivity: false);
      expect(backoff.shouldSkipPollingRefresh(sessionId), isFalse);

      backoff.recordRefreshResult(sessionId, hadActivity: false);
      expect(_takeSkipWindow(backoff, sessionId), 3);

      backoff.recordRefreshResult(sessionId, hadActivity: false);
      expect(_takeSkipWindow(backoff, sessionId), 6);

      backoff.recordRefreshResult(sessionId, hadActivity: false);
      expect(_takeSkipWindow(backoff, sessionId), 8);

      backoff.recordRefreshResult(sessionId, hadActivity: true);
      expect(backoff.shouldSkipPollingRefresh(sessionId), isFalse);

      backoff.recordRefreshResult(sessionId, hadActivity: false);
      expect(backoff.shouldSkipPollingRefresh(sessionId), isFalse);

      backoff.recordRefreshResult(sessionId, hadActivity: false);
      expect(_takeSkipWindow(backoff, sessionId), 3);
    });

    test('remove clears all state for a closed session', () {
      final backoff = TerminalFramePumpBackoff(
        emptyRefreshesBeforeBackoff: 1,
        initialSkipTicks: 2,
        maxSkipTicks: 4,
      );
      const sessionId = 'session-1';

      backoff.recordRefreshResult(sessionId, hadActivity: false);
      expect(backoff.shouldSkipPollingRefresh(sessionId), isTrue);

      backoff.remove(sessionId);

      expect(backoff.shouldSkipPollingRefresh(sessionId), isFalse);
      backoff.recordRefreshResult(sessionId, hadActivity: false);
      expect(_takeSkipWindow(backoff, sessionId), 2);
    });
  });
}

int _takeSkipWindow(TerminalFramePumpBackoff backoff, String sessionId) {
  var skipped = 0;
  while (backoff.shouldSkipPollingRefresh(sessionId)) {
    skipped += 1;
  }
  return skipped;
}
