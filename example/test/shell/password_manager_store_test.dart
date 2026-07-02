import 'package:app/features/shell/password_manager_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Password manager store', () {
    test('keeps newest entries within the session limit', () {
      final store = PasswordManagerStore();

      for (var index = 0; index < maxPasswordManagerEntries + 2; index += 1) {
        store.add(label: 'entry-$index', password: 'secret-$index');
      }

      expect(store.entries, hasLength(maxPasswordManagerEntries));
      expect(
        store.entries.first.label,
        'entry-${maxPasswordManagerEntries + 1}',
      );
      expect(store.entries.last.label, 'entry-2');
    });

    test('remove and clear update retained entries', () {
      final store = PasswordManagerStore();
      final first = store.add(label: 'first', password: 'secret');
      final second = store.add(label: 'second', password: 'secret');

      store.remove(first.id);

      expect(store.entries.map((entry) => entry.id), [second.id]);

      store.clear();

      expect(store.entries, isEmpty);
    });
  });
}
