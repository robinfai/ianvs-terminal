import 'dart:io';

import 'package:app/features/config/local_terminal_config_bootstrap.dart';
import 'package:app/features/config/local_terminal_config_loader.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal config loader', () {
    test('loads current local config', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-loader-local',
      );
      final localRepository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );
      await localRepository.save(
        const LocalTerminalConfigDocument(defaultProfileId: 'local'),
      );

      final result = await LocalTerminalConfigLoader(
        localConfigRepository: localRepository,
      ).load();

      expect(result.source, LocalTerminalConfigBootstrapSource.localConfig);
      expect(result.config.defaultProfileId, 'local');
    });

    test('uses current defaults when local config is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-loader-defaults',
      );

      final result = await LocalTerminalConfigLoader(
        localConfigRepository: LocalTerminalConfigRepository(
          directoryResolver: () async => directory,
        ),
      ).load();

      expect(result.source, LocalTerminalConfigBootstrapSource.defaults);
      expect(result.config.defaultProfileId, isNull);
    });

    test('corrupt local config fails closed', () async {
      await expectLater(
        LocalTerminalConfigLoader(
          localConfigRepository: _CorruptLocalConfigRepository(),
        ).load(),
        throwsA(isA<FormatException>()),
      );
    });
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
