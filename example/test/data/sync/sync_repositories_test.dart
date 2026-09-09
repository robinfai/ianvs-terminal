import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/sync/json_three_way_merge.dart';
import 'package:app/data/sync/local_first_sync.dart';
import 'package:app/data/sync/sync_repositories.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:app/features/profiles/data_api_profile_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/shell/paste_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retired paste history remains local and has no sync document',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-sync-bindings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final pasteHistory = PasteHistoryRepository(
        directoryResolver: () async => directory,
      );
      final bindings = SyncRepositoryBindings(
        profiles: ProfileRepository(directoryResolver: () async => directory),
        preferences: AppPreferencesRepository(
          directoryResolver: () async => directory,
        ),
        terminalConfig: LocalTerminalConfigRepository(
          directoryResolver: () async => directory,
        ),
        pasteHistory: pasteHistory,
      );
      final coordinator = LocalFirstSyncCoordinator(
        documents: bindings.bindings,
      );

      expect(
        bindings.bindings.map((binding) => binding.kind),
        isNot(contains('paste_history')),
      );
      expect(bindings.wrap(coordinator).pasteHistory, same(pasteHistory));
    },
  );

  group('LocalFirstTerminalConfigRepository', () {
    late _MemoryConfigRepository local;
    late SyncDocumentBinding binding;
    late LocalFirstTerminalConfigRepository repository;

    setUp(() {
      local = _MemoryConfigRepository(const LocalTerminalConfigDocument());
      binding = SyncDocumentBinding(
        kind: 'config',
        id: 'local-terminal',
        readLocal: () async => local.document?.toJson(),
        writeLocal: (_) async {},
        decodeRemote: (_) => throw UnimplementedError(),
        encodeRemote: (_) => (data: null, sensitive: null),
        validate: (_) {},
      );
      repository = LocalFirstTerminalConfigRepository(
        local: local,
        binding: binding,
        coordinator: LocalFirstSyncCoordinator(documents: [binding]),
      );
    });

    test(
      'rebases a versioned save over a newer non-overlapping local edit',
      () async {
        final loaded = await repository.loadVersioned();
        local.document = const LocalTerminalConfigDocument(
          defaultProfileId: 'pulled-profile',
        );

        final saved = await repository.saveVersioned(
          loaded.withValue(
            loaded.value!.copyWith(
              layout: const LocalTerminalLayoutConfig(restoreLayout: false),
            ),
          ),
        );

        expect(saved.value.defaultProfileId, 'pulled-profile');
        expect(saved.value.layout.restoreLayout, isFalse);
        expect(local.document?.defaultProfileId, 'pulled-profile');
      },
    );

    test('rejects an overlapping stale save without writing', () async {
      final loaded = await repository.loadVersioned();
      local.document = const LocalTerminalConfigDocument(
        defaultProfileId: 'pulled-profile',
      );

      await expectLater(
        repository.saveVersioned(
          loaded.withValue(
            loaded.value!.copyWith(defaultProfileId: 'edited-profile'),
          ),
        ),
        throwsA(
          isA<LocalSyncEditConflict>().having(
            (error) => error.paths,
            'paths',
            contains('/defaultProfileId'),
          ),
        ),
      );
      expect(local.document?.defaultProfileId, 'pulled-profile');
      expect(local.saveCount, 0);
    });
  });

  group('profile sync compatibility', () {
    test('normalizes omitted defaults before a first merge', () {
      final canonical = encodeDataApiProfilesDocument(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ).data;
      final stored = _copyJson(canonical);
      final profiles = stored['profiles']! as List<Object?>;
      final profile = profiles.single! as Map<String, Object?>;
      profile.remove('appearance');
      final resource = _profileResource(stored);

      final decoded = DataApiProfileRepository.decodeResource(resource);
      final normalized = encodeDataApiProfilesDocument(decoded).data;
      final merged = mergeJsonDocuments(
        base: null,
        local: null,
        remote: normalized,
      );

      expect(merged.conflicts, isEmpty);
      expect(merged.document, normalized);
      expect(
        (merged.document!['profiles']! as List<Object?>).single,
        contains('appearance'),
      );
    });

    test('does not discard an unknown non-empty profile field', () {
      final stored = _copyJson(
        encodeDataApiProfilesDocument(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ).data,
      );
      final profile =
          (stored['profiles']! as List<Object?>).single!
              as Map<String, Object?>;
      profile['futureField'] = 'must-not-be-lost';

      expect(
        () => DataApiProfileRepository.decodeResource(_profileResource(stored)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Map<String, Object?> _copyJson(Map<String, Object?> source) {
  Object? copy(Object? value) {
    if (value is List) return value.map(copy).toList();
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key as String: copy(entry.value),
      };
    }
    return value;
  }

  return copy(source)! as Map<String, Object?>;
}

DataApiResource _profileResource(Map<String, Object?> data) {
  final now = DateTime.utc(2026);
  return DataApiResource(
    id: DataApiProfileRepository.resourceId,
    kind: DataApiProfileRepository.resourceKind,
    data: data,
    sensitive: null,
    hasSensitive: false,
    revision: 1,
    sourceId: 'test-source',
    sourceRevision: 1,
    sourceUpdatedAt: now,
    deleted: false,
    createdAt: now,
    updatedAt: now,
  );
}

final class _MemoryConfigRepository extends TerminalConfigRepository {
  _MemoryConfigRepository(this.document);

  LocalTerminalConfigDocument? document;
  int saveCount = 0;

  @override
  Future<LocalTerminalConfigDocument?> load() async => document;

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {
    saveCount += 1;
    this.document = document;
  }

  @override
  Future<LocalTerminalConfigDocument> update(
    LocalTerminalConfigDocument Function(LocalTerminalConfigDocument current)
    transform, {
    LocalTerminalConfigDocument fallback = const LocalTerminalConfigDocument(),
  }) async {
    final next = transform(document ?? fallback);
    await save(next);
    return next;
  }
}
