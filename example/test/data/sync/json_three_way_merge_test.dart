import 'package:app/data/sync/json_three_way_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeJsonDocuments', () {
    test('merges non-overlapping nested edits', () {
      final result = mergeJsonDocuments(
        base: {
          'settings': {'theme': 'dark', 'fontSize': 12},
        },
        local: {
          'settings': {'theme': 'light', 'fontSize': 12},
        },
        remote: {
          'settings': {'theme': 'dark', 'fontSize': 14},
        },
      );

      expect(result.conflicts, isEmpty);
      expect(result.document, {
        'settings': {'theme': 'light', 'fontSize': 14},
      });
    });

    test('distinguishes missing fields from explicit null', () {
      final result = mergeJsonDocuments(
        base: {'value': 1, 'untouched': true},
        local: {'value': null, 'untouched': true},
        remote: {'untouched': true},
      );

      expect(result.hasConflicts, isTrue);
      expect(result.document, {'value': null, 'untouched': true});
      expect(result.conflicts.single.path, '/value');
      expect(result.conflicts.single.localPresent, isTrue);
      expect(result.conflicts.single.local, isNull);
      expect(result.conflicts.single.remotePresent, isFalse);
    });

    test('accepts equal values on first synchronization', () {
      final result = mergeJsonDocuments(
        base: null,
        local: {'version': 1},
        remote: {'version': 1},
      );

      expect(result.conflicts, isEmpty);
      expect(result.document, {'version': 1});
    });

    test('merges independent first-sync fields', () {
      final result = mergeJsonDocuments(
        base: null,
        local: {'local': 1},
        remote: {'remote': 2},
      );

      expect(result.conflicts, isEmpty);
      expect(result.document, {'local': 1, 'remote': 2});
    });

    test('treats ordinary arrays atomically', () {
      final result = mergeJsonDocuments(
        base: {
          'tabs': [1],
        },
        local: {
          'tabs': [1, 2],
        },
        remote: {
          'tabs': [1, 3],
        },
      );

      expect(result.hasConflicts, isTrue);
      expect(result.conflicts.single.path, '/tabs');
      expect(result.document, {
        'tabs': [1, 2],
      });
    });

    test('merges profiles by stable id including independent additions', () {
      final result = mergeJsonDocuments(
        base: {
          'profiles': [
            {'id': 'a', 'name': 'A', 'port': 22},
          ],
        },
        local: {
          'profiles': [
            {'id': 'a', 'name': 'Local A', 'port': 22},
            {'id': 'local', 'name': 'L'},
          ],
        },
        remote: {
          'profiles': [
            {'id': 'a', 'name': 'A', 'port': 2222},
            {'id': 'remote', 'name': 'R'},
          ],
        },
      );

      expect(result.conflicts, isEmpty);
      expect(result.document!['profiles'], [
        {'id': 'a', 'name': 'Local A', 'port': 2222},
        {'id': 'local', 'name': 'L'},
        {'id': 'remote', 'name': 'R'},
      ]);
    });

    test('does not resurrect a deletion when the other side is unchanged', () {
      final result = mergeJsonDocuments(
        base: {
          'profiles': [
            {'id': 'gone', 'name': 'Old'},
          ],
        },
        local: {'profiles': <Object?>[]},
        remote: {
          'profiles': [
            {'id': 'gone', 'name': 'Old'},
          ],
        },
      );

      expect(result.conflicts, isEmpty);
      expect(result.document, {'profiles': <Object?>[]});
    });

    test('reports delete-versus-modify and keeps local pending resolution', () {
      final result = mergeJsonDocuments(
        base: {
          'profiles': [
            {'id': 'p/1', 'name': 'Old'},
          ],
        },
        local: {'profiles': <Object?>[]},
        remote: {
          'profiles': [
            {'id': 'p/1', 'name': 'Remote'},
          ],
        },
      );

      expect(result.hasConflicts, isTrue);
      expect(result.document, {'profiles': <Object?>[]});
      expect(result.conflicts.single.path, '/profiles/p~11');
      expect(result.conflicts.single.localPresent, isFalse);
      expect(result.conflicts.single.remotePresent, isTrue);
    });

    test('can consistently resolve conflicts in either direction', () {
      JsonThreeWayMergeResult mergeWith(JsonConflictResolution resolution) =>
          mergeJsonDocuments(
            base: {'value': 1},
            local: {'value': 2},
            remote: {'value': 3},
            conflictResolution: resolution,
          );

      final local = mergeWith(JsonConflictResolution.preferLocal);
      final remote = mergeWith(JsonConflictResolution.preferRemote);
      expect(local.document, {'value': 2});
      expect(remote.document, {'value': 3});
      expect(local.conflicts, isEmpty);
      expect(remote.conflicts, isEmpty);
    });

    test('supports deletion of the whole document', () {
      final result = mergeJsonDocuments(
        base: {'value': 1},
        local: null,
        remote: {'value': 1},
      );

      expect(result.conflicts, isEmpty);
      expect(result.document, isNull);
    });
  });
}
