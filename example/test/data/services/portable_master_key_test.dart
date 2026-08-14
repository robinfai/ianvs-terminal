import 'dart:convert';
import 'dart:math';

import 'package:app/data/services/portable_master_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portable representation preserves the exact Data API secret', () {
    final key = PortableMasterKey.fromSecret('  密钥 with spaces  ');

    final decoded = PortableMasterKey.parsePortable(key.portableValue);

    expect(decoded.secret, key.secret);
    expect(decoded.portableValue, startsWith('ianvs-key-v1.'));
  });

  test('generated key contains 32 random bytes of portable material', () {
    final key = PortableMasterKey.generate(Random(1234));

    expect(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(key.secret), isTrue);
    expect(base64Url.decode('${key.secret}='), hasLength(32));
  });

  test('repository stores one item and caches subsequent reads', () async {
    final storage = _MemoryMasterKeyStorage();
    final repository = PortableMasterKeyRepository(storage: storage);

    final first = await repository.readOrCreate();
    final second = await repository.readOrCreate();
    final exported = await repository.exportPortable();

    expect(second.secret, first.secret);
    expect(exported, first.portableValue);
    expect(storage.writeCount, 1);
    expect(storage.readCount, 1);
  });

  test(
    'export creates the one master key when encryption is not used yet',
    () async {
      final storage = _MemoryMasterKeyStorage();
      final repository = PortableMasterKeyRepository(storage: storage);

      final exported = await repository.exportPortable();

      expect(exported, startsWith('ianvs-key-v1.'));
      expect(storage.writeCount, 1);
    },
  );

  test('legacy secret is adopted before generation', () async {
    final storage = _MemoryMasterKeyStorage();
    final repository = PortableMasterKeyRepository(storage: storage);

    final key = await repository.readOrCreate(
      legacyLoader: () async => 'existing-encryption-key-material',
    );

    expect(key.secret, 'existing-encryption-key-material');
    expect(storage.value, key.portableValue);
  });

  test('copied key imports on an empty platform vault', () async {
    final source = PortableMasterKeyRepository(
      storage: _MemoryMasterKeyStorage(),
    );
    final destination = PortableMasterKeyRepository(
      storage: _MemoryMasterKeyStorage(),
    );
    final sourceKey = await source.readOrCreate();

    final imported = await destination.importPortable(
      await source.exportPortable(),
    );

    expect(imported.secret, sourceKey.secret);
  });

  test('import refuses to replace a different installed key', () async {
    final repository = PortableMasterKeyRepository(
      storage: _MemoryMasterKeyStorage(),
    );
    await repository.adoptLegacySecret('first-encryption-key-material');
    final other = PortableMasterKey.fromSecret(
      'second-encryption-key-material',
    );

    await expectLater(
      repository.importPortable(other.portableValue),
      throwsA(isA<PortableMasterKeyConflictException>()),
    );
    expect((await repository.read())?.secret, 'first-encryption-key-material');
  });

  test('purpose derivation is stable and domain separated', () async {
    final key = PortableMasterKey.fromSecret('master-key-material-1234');

    final profileA = await (await key.deriveKey(
      'ssh-profile-v1',
    )).extractBytes();
    final profileB = await (await key.deriveKey(
      'ssh-profile-v1',
    )).extractBytes();
    final vault = await (await key.deriveKey(
      'remote-session-vault-v1',
    )).extractBytes();

    expect(profileA, profileB);
    expect(profileA, isNot(vault));
    expect(profileA, hasLength(32));
  });
}

final class _MemoryMasterKeyStorage implements PortableMasterKeyStorage {
  String? value;
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<String?> read() async {
    readCount += 1;
    return value;
  }

  @override
  Future<void> write(String portableValue) async {
    writeCount += 1;
    value = portableValue;
  }
}
