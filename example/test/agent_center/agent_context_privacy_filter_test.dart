import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentContextPrivacyFilter', () {
    test('redacts common secret forms from terminal context text', () {
      const filter = AgentContextPrivacyFilter();

      final redacted = filter.redactText(
        [
          'DEEPSEEK_API_KEY=abc123456789',
          'Authorization: Bearer abcdefghijklmnopqrstuvwxyz',
          'curl --password hunter2 --token token-value',
          'url=https://example.test?api_key=query-secret',
          '-----BEGIN PRIVATE KEY-----',
          'private-key-body',
          '-----END PRIVATE KEY-----',
        ].join('\n'),
      );

      expect(redacted, contains('DEEPSEEK_API_KEY=[REDACTED]'));
      expect(redacted, contains('Authorization: Bearer [REDACTED]'));
      expect(redacted, contains('--password [REDACTED]'));
      expect(redacted, contains('--token [REDACTED]'));
      expect(redacted, contains('api_key=[REDACTED]'));
      expect(redacted, contains('[REDACTED]'));
      expect(redacted, isNot(contains('abc123456789')));
      expect(redacted, isNot(contains('abcdefghijklmnopqrstuvwxyz')));
      expect(redacted, isNot(contains('hunter2')));
      expect(redacted, isNot(contains('token-value')));
      expect(redacted, isNot(contains('query-secret')));
      expect(redacted, isNot(contains('private-key-body')));
    });
  });
}
