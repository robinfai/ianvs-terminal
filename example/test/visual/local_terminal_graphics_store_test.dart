import 'package:app/features/visual/local_terminal_graphics_store.dart';
import 'package:app/features/visual/local_terminal_visual_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal graphics store planner', () {
    test('rejects insert when graphics storage is disabled', () {
      final plan = LocalTerminalGraphicsStorePlanner.planInsert(
        policy: const LocalTerminalGraphicsStoragePolicy(enabled: false),
        existing: const [],
        next: const LocalTerminalGraphicsEntry(
          id: 'img',
          bytes: 1,
          createdAtMillis: 1,
        ),
      );

      expect(plan.accepted, isFalse);
      expect(plan.evictIds, isEmpty);
    });

    test('accepts insert within limit', () {
      final plan = LocalTerminalGraphicsStorePlanner.planInsert(
        policy: const LocalTerminalGraphicsStoragePolicy(
          enabled: true,
          maxBytes: 10,
        ),
        existing: const [],
        next: const LocalTerminalGraphicsEntry(
          id: 'img',
          bytes: 5,
          createdAtMillis: 1,
        ),
      );

      expect(plan.accepted, isTrue);
      expect(plan.evictIds, isEmpty);
    });

    test('plans oldest eviction when over limit', () {
      final plan = LocalTerminalGraphicsStorePlanner.planInsert(
        policy: const LocalTerminalGraphicsStoragePolicy(
          enabled: true,
          maxBytes: 10,
        ),
        existing: const [
          LocalTerminalGraphicsEntry(id: 'old', bytes: 6, createdAtMillis: 1),
          LocalTerminalGraphicsEntry(id: 'new', bytes: 3, createdAtMillis: 2),
        ],
        next: const LocalTerminalGraphicsEntry(
          id: 'next',
          bytes: 5,
          createdAtMillis: 3,
        ),
      );

      expect(plan.accepted, isTrue);
      expect(plan.evictIds, ['old']);
    });

    test('rejects insert without a usable image id', () {
      final plan = LocalTerminalGraphicsStorePlanner.planInsert(
        policy: const LocalTerminalGraphicsStoragePolicy(
          enabled: true,
          maxBytes: 10,
        ),
        existing: const [],
        next: const LocalTerminalGraphicsEntry(
          id: '   ',
          bytes: 5,
          createdAtMillis: 1,
        ),
      );

      expect(plan.accepted, isFalse);
      expect(plan.evictIds, isEmpty);
    });

    test('ignores invalid existing entries when planning capacity', () {
      final plan = LocalTerminalGraphicsStorePlanner.planInsert(
        policy: const LocalTerminalGraphicsStoragePolicy(
          enabled: true,
          maxBytes: 10,
        ),
        existing: const [
          LocalTerminalGraphicsEntry(
            id: 'bad',
            bytes: -100,
            createdAtMillis: 1,
          ),
          LocalTerminalGraphicsEntry(id: 'old', bytes: 9, createdAtMillis: 2),
        ],
        next: const LocalTerminalGraphicsEntry(
          id: 'next',
          bytes: 5,
          createdAtMillis: 3,
        ),
      );

      expect(plan.accepted, isTrue);
      expect(plan.evictIds, ['old']);
    });
  });
}
