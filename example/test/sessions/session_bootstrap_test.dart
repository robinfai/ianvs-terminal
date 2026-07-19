import 'dart:async';
import 'dart:io';

import 'package:app/features/config/local_terminal_config_bootstrap.dart';
import 'package:app/features/config/local_terminal_config_loader.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/sessions/session_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionBootstrapService', () {
    test('prefers a valid explicit profile without rewriting config', () async {
      final defaultProfile = defaultTerminalProfile();
      final sshProfile = defaultProfile.copyWith(id: 'ssh', name: 'SSH');
      final profiles = _MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final preferences = _MemoryPreferencesRepository(null);
      final config = _MemoryLocalConfigRepository(
        const LocalTerminalConfigDocument(defaultProfileId: 'default'),
      );

      final preparation = await _service(
        profiles: profiles,
        preferences: preferences,
        config: config,
      ).prepare(explicitDefaultProfileId: ' ssh ');

      expect(preparation.effectiveDefaultProfileId, 'ssh');
      expect(preparation.appPreferences.defaults.defaultProfileId, 'default');
      expect(
        preparation.configSource,
        LocalTerminalConfigBootstrapSource.localConfig,
      );
      expect(preparation.preferencesLoadedFromDisk, isTrue);
      expect(config.savedDocuments, isEmpty);
      expect(preferences.savedDocuments, isEmpty);
    });

    test('repairs an invalid local config default in local config', () async {
      final defaultProfile = defaultTerminalProfile();
      final profiles = _MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile]),
      );
      final preferences = _MemoryPreferencesRepository(null);
      final config = _MemoryLocalConfigRepository(
        const LocalTerminalConfigDocument(defaultProfileId: 'missing'),
      );

      final preparation = await _service(
        profiles: profiles,
        preferences: preferences,
        config: config,
      ).prepare();

      expect(preparation.effectiveDefaultProfileId, defaultProfile.id);
      expect(preparation.localConfig.defaultProfileId, isNull);
      expect(config.savedDocuments, hasLength(1));
      expect(config.savedDocuments.single.defaultProfileId, isNull);
      expect(preferences.savedDocuments, isEmpty);
    });

    test('propagates config I/O failures without legacy fallback', () async {
      final profiles = _MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      );
      final preferences = _MemoryPreferencesRepository(
        const TerminalAppPreferencesDocument(),
      );
      final config = _FailingLocalConfigRepository();

      await expectLater(
        _service(
          profiles: profiles,
          preferences: preferences,
          config: config,
        ).prepare(),
        throwsA(isA<FileSystemException>()),
      );

      expect(preferences.loadAttempts, 0);
      expect(preferences.savedDocuments, isEmpty);
    });

    test('uses legacy fallback only when the policy allows it', () async {
      final defaultProfile = defaultTerminalProfile();
      final profiles = _MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile]),
      );
      final preferences = _MemoryPreferencesRepository(
        const TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(defaultProfileId: 'default'),
        ),
      );
      final config = _FailingLocalConfigRepository();

      final preparation = await _service(
        profiles: profiles,
        preferences: preferences,
        config: config,
        shouldFallbackToLegacyPreferences: (error) =>
            error is FileSystemException,
      ).prepare();

      expect(preferences.loadAttempts, 1);
      expect(preparation.effectiveDefaultProfileId, defaultProfile.id);
      expect(
        preparation.configSource,
        LocalTerminalConfigBootstrapSource.legacyAppPreferences,
      );
    });
  });

  group('SessionBootstrapRunner', () {
    test('coalesces concurrent runs and allows a later run', () async {
      final runner = SessionBootstrapRunner();
      final blocker = Completer<void>();
      var starts = 0;
      var operations = 0;

      Future<void> run() {
        return runner.run(
          isMounted: () => true,
          onStarted: () => starts += 1,
          operation: () async {
            operations += 1;
            if (operations == 1) {
              await blocker.future;
            }
          },
          onFailed: (_, _) {},
        );
      }

      final first = run();
      await Future<void>.delayed(Duration.zero);
      await run();

      expect(starts, 1);
      expect(operations, 1);

      blocker.complete();
      await first;
      await run();

      expect(starts, 2);
      expect(operations, 2);
    });

    test(
      'reports failures, resets for retry, and skips when unmounted',
      () async {
        final runner = SessionBootstrapRunner();
        final failures = <Object>[];
        var mounted = true;
        var starts = 0;

        await runner.run(
          isMounted: () => mounted,
          onStarted: () => starts += 1,
          operation: () async => throw StateError('unavailable'),
          onFailed: (error, _) => failures.add(error),
        );

        expect(starts, 1);
        expect(failures.single, isA<StateError>());

        await runner.run(
          isMounted: () => mounted,
          onStarted: () => starts += 1,
          operation: () async {},
          onFailed: (error, _) => failures.add(error),
        );
        mounted = false;
        await runner.run(
          isMounted: () => mounted,
          onStarted: () => starts += 1,
          operation: () async {},
          onFailed: (error, _) => failures.add(error),
        );

        expect(starts, 2);
        expect(failures, hasLength(1));
      },
    );
  });
}

SessionBootstrapService _service({
  required _MemoryProfileRepository profiles,
  required _MemoryPreferencesRepository preferences,
  required LocalTerminalConfigRepository config,
  LocalConfigFallbackPolicy? shouldFallbackToLegacyPreferences,
}) {
  return SessionBootstrapService(
    profileRepository: profiles,
    appPreferencesRepository: preferences,
    localConfigRepository: config,
    localConfigLoader: LocalTerminalConfigLoader(
      localConfigRepository: config,
      legacyPreferencesRepository: preferences,
    ),
    shouldFallbackToLegacyPreferences:
        shouldFallbackToLegacyPreferences ?? (_) => false,
  );
}

class _MemoryProfileRepository extends ProfileRepository {
  _MemoryProfileRepository(this.document);

  TerminalProfilesDocument document;

  @override
  Future<TerminalProfilesDocument> load() async => document;

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    this.document = document;
  }
}

class _MemoryPreferencesRepository extends AppPreferencesRepository {
  _MemoryPreferencesRepository(this.document);

  TerminalAppPreferencesDocument? document;
  int loadAttempts = 0;
  final List<TerminalAppPreferencesDocument> savedDocuments = [];

  @override
  Future<TerminalAppPreferencesDocument?> load() async {
    loadAttempts += 1;
    return document;
  }

  @override
  Future<void> save(TerminalAppPreferencesDocument document) async {
    savedDocuments.add(document);
    this.document = document;
  }
}

class _MemoryLocalConfigRepository extends LocalTerminalConfigRepository {
  _MemoryLocalConfigRepository(this.document);

  LocalTerminalConfigDocument? document;
  final List<LocalTerminalConfigDocument> savedDocuments = [];

  @override
  Future<LocalTerminalConfigDocument?> load() async => document;

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {
    savedDocuments.add(document);
    this.document = document;
  }
}

class _FailingLocalConfigRepository extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    throw const FileSystemException('local config unavailable');
  }
}
