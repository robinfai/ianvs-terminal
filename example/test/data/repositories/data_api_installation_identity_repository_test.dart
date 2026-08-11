import 'dart:io';
import 'dart:math';

import 'package:app/data/repositories/data_api_installation_identity_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ianvs-data-api-installation-identity-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists a stable installation-scoped UUID', () async {
    final repository = DataApiInstallationIdentityRepository(
      appSupportDirectory: temporaryDirectory,
      secureRandom: Random(1),
    );

    final created = await repository.loadOrCreate();
    final reloaded = await DataApiInstallationIdentityRepository(
      appSupportDirectory: temporaryDirectory,
      secureRandom: Random(2),
    ).loadOrCreate();

    expect(reloaded.id, created.id);
    expect(created.migrationSourceId, 'ianvs-client-${created.id}');
    expect(created.migrationSourceId.length, lessThanOrEqualTo(64));
    expect(created.migrationMarkerId, 'local-json-v1-${created.id}');
  });

  test('concurrent first creation shares one installation identity', () async {
    final first = DataApiInstallationIdentityRepository(
      appSupportDirectory: temporaryDirectory,
      secureRandom: Random(1),
    ).loadOrCreate();
    final second = DataApiInstallationIdentityRepository(
      appSupportDirectory: temporaryDirectory,
      secureRandom: Random(2),
    ).loadOrCreate();

    final identities = await Future.wait(<Future<DataApiInstallationIdentity>>[
      first,
      second,
    ]);

    expect(identities[1].id, identities[0].id);
    expect(
      (await DataApiInstallationIdentityRepository(
        appSupportDirectory: temporaryDirectory,
      ).loadOrCreate()).id,
      identities[0].id,
    );
  });

  test('different installations use different migration sources', () async {
    final otherDirectory = await Directory.systemTemp.createTemp(
      'ianvs-data-api-installation-identity-other-',
    );
    addTearDown(() async {
      if (await otherDirectory.exists()) {
        await otherDirectory.delete(recursive: true);
      }
    });

    final first = await DataApiInstallationIdentityRepository(
      appSupportDirectory: temporaryDirectory,
      secureRandom: Random(1),
    ).loadOrCreate();
    final second = await DataApiInstallationIdentityRepository(
      appSupportDirectory: otherDirectory,
      secureRandom: Random(2),
    ).loadOrCreate();

    expect(second.id, isNot(first.id));
    expect(second.migrationSourceId, isNot(first.migrationSourceId));
    expect(second.migrationMarkerId, isNot(first.migrationMarkerId));
  });

  test(
    'quarantines a corrupt identity and creates a valid replacement',
    () async {
      final repository = DataApiInstallationIdentityRepository(
        appSupportDirectory: temporaryDirectory,
        secureRandom: Random(1),
      );
      await repository.identityFile.parent.create(recursive: true);
      await repository.identityFile.writeAsString('{"version":1,"id":"bad"}');

      final repaired = await repository.loadOrCreate();

      expect(DataApiInstallationIdentity.parse(repaired.id).id, repaired.id);
      expect(await repository.identityFile.exists(), isTrue);
      expect(
        repository.identityFile.parent.listSync().any(
          (entry) => entry.path.contains('installation.json.corrupt'),
        ),
        isTrue,
      );
    },
  );
}
