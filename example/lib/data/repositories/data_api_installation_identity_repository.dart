import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';

final class DataApiInstallationIdentity {
  const DataApiInstallationIdentity(this.id);

  static final RegExp _validId = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  final String id;

  String get migrationSourceId => 'ianvs-client-$id';

  String get migrationMarkerId => 'local-json-v1-$id';

  static DataApiInstallationIdentity parse(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_validId.hasMatch(normalized)) {
      throw const FormatException('Invalid Data API installation identity.');
    }
    return DataApiInstallationIdentity(normalized);
  }
}

final class DataApiInstallationIdentityRepository {
  DataApiInstallationIdentityRepository({
    required Directory appSupportDirectory,
    Random? secureRandom,
  }) : identityFile = File(
         '${appSupportDirectory.path}${Platform.pathSeparator}'
         'data-api${Platform.pathSeparator}installation.json',
       ),
       _secureRandom = secureRandom ?? Random.secure();

  DataApiInstallationIdentityRepository.forFile(
    this.identityFile, {
    Random? secureRandom,
  }) : _secureRandom = secureRandom ?? Random.secure();

  final File identityFile;
  final Random _secureRandom;

  Future<DataApiInstallationIdentity> loadOrCreate() {
    final key = identityFile.absolute.path;
    final pending = _pendingInstallationIdentities[key];
    if (pending != null) {
      return pending;
    }
    late final Future<DataApiInstallationIdentity> tracked;
    tracked = _withCreationLock(_loadOrCreateLocked).whenComplete(() {
      if (identical(_pendingInstallationIdentities[key], tracked)) {
        final removed = _pendingInstallationIdentities.remove(key);
        assert(
          identical(removed, tracked),
          'The installation identity single-flight entry changed in flight.',
        );
      }
    });
    _pendingInstallationIdentities[key] = tracked;
    return tracked;
  }

  Future<DataApiInstallationIdentity> _loadOrCreateLocked() async {
    if (await identityFile.exists()) {
      try {
        final root = decodeJsonObject(
          await identityFile.readAsString(),
          documentName: 'Data API installation identity',
        );
        final id = root['id'];
        if (root['version'] != 1 || id is! String) {
          throw const FormatException(
            'Invalid Data API installation identity document.',
          );
        }
        return DataApiInstallationIdentity.parse(id);
      } on FormatException {
        await quarantineCorruptFile(identityFile);
      }
    }
    final identity = DataApiInstallationIdentity(_generateUuidV4());
    await writeStringAtomically(
      identityFile,
      '${jsonEncode(<String, Object?>{'version': 1, 'id': identity.id})}\n',
    );
    return identity;
  }

  Future<DataApiInstallationIdentity> _withCreationLock(
    Future<DataApiInstallationIdentity> Function() operation,
  ) async {
    final lockFile = File('${identityFile.path}.lock');
    RandomAccessFile? handle;
    var locked = false;
    try {
      await lockFile.parent.create(recursive: true);
      handle = await lockFile.open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      locked = true;
      return await operation();
    } finally {
      try {
        if (locked) {
          await handle?.unlock();
        }
      } finally {
        await handle?.close();
      }
    }
  }

  String _generateUuidV4() {
    final bytes = List<int>.generate(
      16,
      (_) => _secureRandom.nextInt(256),
      growable: false,
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

final Map<String, Future<DataApiInstallationIdentity>>
_pendingInstallationIdentities =
    <String, Future<DataApiInstallationIdentity>>{};
