import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/profiles/profile_secret_cipher.dart';
import 'package:app/startup/ios_prd_master_key.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app/build_identity');
  const acceptedIdentity = <String, Object?>{
    'bundleId': 'work.ianvs.trail.mobileprd',
    'deviceLocalMasterKey': true,
  };
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FlutterSecureStoragePlatform originalStorage;
  late _RecordingStorage storage;
  late List<MethodCall> identityCalls;

  void identity(Object? value) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      identityCalls.add(call);
      return value;
    });
  }

  setUp(() {
    originalStorage = FlutterSecureStoragePlatform.instance;
    storage = _RecordingStorage();
    FlutterSecureStoragePlatform.instance = storage;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    identityCalls = <MethodCall>[];
    identity(acceptedIdentity);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    FlutterSecureStoragePlatform.instance = originalStorage;
    debugDefaultTargetPlatformOverride = null;
  });

  test('only exact native PRD identity can opt into local creation', () async {
    for (final bundleId in <Object?>[
      'work.ianvs.trail',
      'work.ianvs.trail.mobileprd.other',
      'work.ianvs.trail.mobileprd ',
      '',
      null,
      1,
    ]) {
      identity(<String, Object?>{...acceptedIdentity, 'bundleId': bundleId});
      expect(await resolveIosPrdMasterKeyRepository(), isNull);
    }
    expect(storage.readKeys, isEmpty);
    expect(storage.writeKeys, isEmpty);
    expect(
      identityCalls.every((call) => call.method == 'readIdentity'),
      isTrue,
    );
    expect(identityCalls.every((call) => call.arguments == null), isTrue);
  });

  test('missing or non-boolean opt-in fails closed', () async {
    identity(<String, Object?>{'bundleId': 'work.ianvs.trail.mobileprd'});
    expect(await resolveIosPrdMasterKeyRepository(), isNull);
    for (final optIn in <Object?>[null, false, 'true', 1, <Object?>[]]) {
      identity(<String, Object?>{
        ...acceptedIdentity,
        'deviceLocalMasterKey': optIn,
      });
      expect(await resolveIosPrdMasterKeyRepository(), isNull);
    }
    expect(storage.readKeys, isEmpty);
    expect(storage.writeKeys, isEmpty);
  });

  test('non-iOS does not request an opt-in or touch secure storage', () async {
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.iOS) continue;
      debugDefaultTargetPlatformOverride = platform;
      expect(await resolveIosPrdMasterKeyRepository(), isNull);
    }
    expect(identityCalls, isEmpty);
    expect(storage.readKeys, isEmpty);
    expect(storage.writeKeys, isEmpty);
  });

  test('unavailable or malformed native channel fails closed', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await resolveIosPrdMasterKeyRepository(), isNull);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'identity_unavailable');
    });
    expect(await resolveIosPrdMasterKeyRepository(), isNull);
    for (final response in <Object?>[
      null,
      'true',
      <Object?>[],
      {1: true},
    ]) {
      identity(response);
      expect(await resolveIosPrdMasterKeyRepository(), isNull);
    }
    expect(storage.readKeys, isEmpty);
    expect(storage.writeKeys, isEmpty);
  });

  test(
    'accepted build creates one isolated device-only key without migration',
    () async {
      final productionKey = PortableMasterKey.fromSecret(
        'public-test-production-master-key',
      );
      storage.values[FlutterSecurePortableMasterKeyStorage.storageKey] =
          productionKey.portableValue;
      final repository = (await resolveIosPrdMasterKeyRepository())!;
      expect(repository.allowLegacyMigration, isFalse);
      expect(
        repository.storagePolicy,
        PortableMasterKeyStoragePolicy.acceptanceDeviceOnly,
      );
      var legacyRead = false;
      final created = await repository.readOrCreate(
        legacyLoader: () async {
          legacyRead = true;
          return productionKey.secret;
        },
      );
      expect(legacyRead, isFalse);
      expect(created.secret, isNot(productionKey.secret));
      expect(
        (await repository.readOrCreate()).portableValue,
        created.portableValue,
      );
      expect(storage.writeKeys, <String>[
        FlutterSecurePortableMasterKeyStorage.iosPrdStorageKey,
      ]);
      expect(storage.readKeys, <String>[
        FlutterSecurePortableMasterKeyStorage.iosPrdStorageKey,
      ]);
      expect(
        storage.values[FlutterSecurePortableMasterKeyStorage.storageKey],
        productionKey.portableValue,
      );
      for (final options in storage.options) {
        expect(options['synchronizable'], 'false');
        expect(options['accessibility'], 'unlocked_this_device');
        expect(options['groupId'], isNull);
      }

      final reopened = (await resolveIosPrdMasterKeyRepository())!;
      expect(
        (await reopened.readOrCreate()).portableValue,
        created.portableValue,
      );
      expect(storage.writeKeys, hasLength(1));
    },
  );

  test('existing device-only key is reused without an overwrite', () async {
    final existing = PortableMasterKey.fromSecret('public-test-existing-key');
    storage.values[FlutterSecurePortableMasterKeyStorage.iosPrdStorageKey] =
        existing.portableValue;
    final repository = (await resolveIosPrdMasterKeyRepository())!;

    expect(
      (await repository.readOrCreate()).portableValue,
      existing.portableValue,
    );
    expect(storage.writeKeys, isEmpty);
  });

  test('malformed existing device key is not replaced', () async {
    for (final encoded in <String>['invalid-existing-key', '']) {
      storage.values[FlutterSecurePortableMasterKeyStorage.iosPrdStorageKey] =
          encoded;
      final repository = (await resolveIosPrdMasterKeyRepository())!;

      await expectLater(repository.readOrCreate(), throwsFormatException);
      expect(storage.writeKeys, isEmpty);
      expect(
        storage.values[FlutterSecurePortableMasterKeyStorage.iosPrdStorageKey],
        encoded,
      );
    }
  });

  test(
    'Keychain read errors do not trigger generation or a fallback',
    () async {
      storage.readError = PlatformException(code: 'device_locked');
      final repository = (await resolveIosPrdMasterKeyRepository())!;

      await expectLater(
        repository.readOrCreate(),
        throwsA(isA<PlatformException>()),
      );
      expect(storage.writeKeys, isEmpty);
      expect(storage.values, isEmpty);
    },
  );

  test(
    'profile encryption creates a persistent device key on first save',
    () async {
      final repository = (await resolveIosPrdMasterKeyRepository())!;
      final cipher = ProfileSecretCipher(
        keyStore: PortableMasterProfileSecretKeyStore(
          masterKeyRepository: repository,
        ),
      );
      final envelope = await cipher.encrypt(
        profileId: 'fixture-profile',
        field: 'privateKeys',
        value: 'public-test-key-material',
      );
      final reopened = (await resolveIosPrdMasterKeyRepository())!;
      final reader = ProfileSecretCipher(
        keyStore: PortableMasterProfileSecretKeyStore(
          masterKeyRepository: reopened,
        ),
      );

      expect(
        await reader.decrypt(
          profileId: 'fixture-profile',
          field: 'privateKeys',
          envelope: envelope,
        ),
        'public-test-key-material',
      );
      expect(storage.writeKeys, hasLength(1));
      expect(
        storage.readKeys.every(
          (key) =>
              key == FlutterSecurePortableMasterKeyStorage.iosPrdStorageKey,
        ),
        isTrue,
      );
    },
  );
}

final class _RecordingStorage extends FlutterSecureStoragePlatform {
  PlatformException? readError;
  final values = <String, String>{};
  final readKeys = <String>[];
  final writeKeys = <String>[];
  final options = <Map<String, String>>[];

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    readKeys.add(key);
    this.options.add(Map<String, String>.of(options));
    if (readError case final error?) throw error;
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    writeKeys.add(key);
    this.options.add(Map<String, String>.of(options));
    values[key] = value;
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => throw StateError('Unexpected containsKey');

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => throw StateError('Unexpected delete');

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => throw StateError('Unexpected readAll');

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      throw StateError('Unexpected deleteAll');
}
