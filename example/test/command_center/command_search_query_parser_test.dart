import 'package:app/features/command_center/command_search_query_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandSearchQueryParser', () {
    const parser = CommandSearchQueryParser();

    test('parses plain text and normalizes whitespace', () {
      final query = parser.parse('  flutter    test  failure ');

      expect(query.text, 'flutter test failure');
      expect(query.filters, isEmpty);
      expect(query.isEmpty, isFalse);
    });

    test('parses known filter prefixes', () {
      final query = parser.parse(
        'history:global block:cmd-1 action:copy status:failed build',
      );

      expect(query.text, 'build');
      expect(query.valueFor(CommandSearchFilterKind.history), 'global');
      expect(query.valueFor(CommandSearchFilterKind.block), 'cmd-1');
      expect(query.valueFor(CommandSearchFilterKind.action), 'copy');
      expect(query.valueFor(CommandSearchFilterKind.status), 'failed');
    });

    test('preserves unknown prefixes as text', () {
      final query = parser.parse('owner:me status:success deploy');

      expect(query.text, 'owner:me deploy');
      expect(query.valueFor(CommandSearchFilterKind.status), 'success');
      expect(query.filters, hasLength(1));
    });

    test('parses quoted cwd filter values', () {
      final query = parser.parse('cwd:"/Users/dev/my project" flutter test');

      expect(query.text, 'flutter test');
      expect(
        query.valueFor(CommandSearchFilterKind.cwd),
        '/Users/dev/my project',
      );
    });

    test('handles empty and whitespace-only queries', () {
      expect(parser.parse('').isEmpty, isTrue);
      expect(parser.parse('    ').text, '');
      expect(parser.parse('    ').filters, isEmpty);
    });

    test('keeps known prefixes without values in text', () {
      final query = parser.parse('status: cwd: build');

      expect(query.text, 'status: cwd: build');
      expect(query.filters, isEmpty);
    });
  });
}
