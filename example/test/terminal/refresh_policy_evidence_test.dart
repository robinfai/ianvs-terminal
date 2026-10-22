import 'package:flutter_test/flutter_test.dart';

import '../support/refresh_policy_evidence.dart';

void main() {
  group('latestRefreshResult', () {
    Map<String, Object?> event(
      String kind, {
      String session = 'session',
      int id = 12,
      int delay = 264000,
    }) => {
      'schema_version': 'ianvs-terminal-refresh-policy-v1',
      'session_id': session,
      'event': kind,
      'refresh_id': id,
      'current_delay_micros': delay,
    };

    test(
      'retains a completed result followed by skipped ticks and requests',
      () {
        final result = event('refresh_result');
        final events = [
          result,
          event('poll_tick_skipped'),
          event('refresh_requested', id: 13),
        ];
        expect(events.last['event'], 'refresh_requested');
        expect(latestRefreshResult(events, 'session'), same(result));
      },
    );

    test('ignores a newer result for a different session or schema', () {
      final result = event('refresh_result');
      expect(
        latestRefreshResult([
          result,
          event('refresh_result', session: 'other', id: 13),
          {...event('refresh_result', id: 14), 'schema_version': 'unrelated'},
        ], 'session'),
        same(result),
      );
    });

    test('returns null until this session completes a poll', () {
      expect(
        latestRefreshResult([
          event('refresh_result', session: 'other'),
          event('refresh_requested'),
          event('poll_tick_skipped'),
        ], 'session'),
        isNull,
      );
    });

    test('newer completed backoff replaces an older target state', () {
      final current = event('refresh_result', id: 13, delay: 396000);
      final result = latestRefreshResult([
        event('refresh_result'),
        current,
        event('poll_tick_skipped'),
      ], 'session');
      expect(result, same(current));
      expect(result!['current_delay_micros'], 396000);
    });
  });
}
