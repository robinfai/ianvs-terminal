import 'dart:io';

import 'package:app/features/config/local_terminal_config_bootstrap.dart';
import 'package:app/features/config/local_terminal_config_loader.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal config loader', () {
    test('loads local config before legacy preferences', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-loader-local',
      );
      final localRepository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );
      final legacyRepository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      await localRepository.save(
        const LocalTerminalConfigDocument(defaultProfileId: 'local'),
      );
      await legacyRepository.save(
        const TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(defaultProfileId: 'legacy'),
        ),
      );

      final result = await LocalTerminalConfigLoader(
        localConfigRepository: localRepository,
        legacyPreferencesRepository: legacyRepository,
      ).load();

      expect(result.source, LocalTerminalConfigBootstrapSource.localConfig);
      expect(result.config.defaultProfileId, 'local');
    });

    test(
      'does not read corrupt legacy preferences when local config exists',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-config-loader-local-corrupt-legacy',
        );
        final localRepository = LocalTerminalConfigRepository(
          directoryResolver: () async => directory,
        );
        final legacyFile = File('${directory.path}/ianvs_preferences.json');
        await localRepository.save(
          const LocalTerminalConfigDocument(defaultProfileId: 'local'),
        );
        await legacyFile.writeAsString('{bad json');

        final result = await LocalTerminalConfigLoader(
          localConfigRepository: localRepository,
          legacyPreferencesRepository: AppPreferencesRepository(
            directoryResolver: () async => directory,
          ),
        ).load();

        expect(result.source, LocalTerminalConfigBootstrapSource.localConfig);
        expect(result.config.defaultProfileId, 'local');
        expect(await legacyFile.readAsString(), '{bad json');
        expect(
          directory.listSync().any(
            (entry) => entry.path.contains('ianvs_preferences.json.corrupt'),
          ),
          isFalse,
        );
      },
    );

    test('loads legacy preferences when local config is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-loader-legacy',
      );
      final legacyRepository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      await legacyRepository.save(
        const TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(defaultProfileId: 'legacy'),
        ),
      );

      final result = await LocalTerminalConfigLoader(
        localConfigRepository: LocalTerminalConfigRepository(
          directoryResolver: () async => directory,
        ),
        legacyPreferencesRepository: legacyRepository,
      ).load();

      expect(
        result.source,
        LocalTerminalConfigBootstrapSource.legacyAppPreferences,
      );
      expect(result.config.defaultProfileId, 'legacy');
    });

    test(
      'corrupt local config never reads or writes legacy preferences',
      () async {
        final legacyRepository = _RecordingPreferencesRepository();

        await expectLater(
          LocalTerminalConfigLoader(
            localConfigRepository: _CorruptLocalConfigRepository(),
            legacyPreferencesRepository: legacyRepository,
          ).load(),
          throwsA(isA<FormatException>()),
        );

        expect(legacyRepository.loadCount, 0);
        expect(legacyRepository.saveCount, 0);
      },
    );
  });
}

final class _CorruptLocalConfigRepository extends TerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    throw const FormatException('corrupt local terminal config');
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}

  @override
  Future<LocalTerminalConfigDocument> update(
    LocalTerminalConfigDocument Function(LocalTerminalConfigDocument current)
    transform, {
    LocalTerminalConfigDocument fallback = const LocalTerminalConfigDocument(),
  }) async => transform(fallback);
}

final class _RecordingPreferencesRepository
    extends AppPreferencesRepositoryPort {
  int loadCount = 0;
  int saveCount = 0;

  @override
  Future<TerminalAppPreferencesDocument?> load() async {
    loadCount += 1;
    return const TerminalAppPreferencesDocument();
  }

  @override
  Future<void> save(TerminalAppPreferencesDocument document) async {
    saveCount += 1;
  }
}
