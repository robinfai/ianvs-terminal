import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../../platform/local_json_file.dart';
import 'data_api_remote_session_store.dart';
import 'data_api_remote_session_vault.dart';
import 'portable_master_key.dart';

/// Recovers a pre-Data-Protection macOS master key exactly once.
///
/// A legacy candidate is allowed to replace the synchronized Keychain item
/// only after it authenticates the existing encrypted remote-session vault.
Future<bool> recoverVerifiedLegacyMacOsMasterKey({
  required File vaultFile,
  required File migrationMarker,
  required PortableMasterKeyRepository synchronizedRepository,
  required PortableMasterKeyStorage legacyStorage,
  required Future<void> Function() deleteLegacy,
}) async {
  if (!await vaultFile.exists() || await migrationMarker.exists()) {
    return false;
  }

  DataApiRemoteSessionFormatException? currentMismatch;
  StackTrace? currentMismatchStack;
  try {
    await _verifyVault(vaultFile, synchronizedRepository);
    await writeStringAtomically(migrationMarker, 'complete\n');
    return false;
  } on DataApiRemoteSessionFormatException catch (error, stackTrace) {
    if (error.cause is! SecretBoxAuthenticationError) {
      rethrow;
    }
    currentMismatch = error;
    currentMismatchStack = stackTrace;
  }

  final legacyEncoded = await legacyStorage.read();
  if (legacyEncoded == null || legacyEncoded.isEmpty) {
    Error.throwWithStackTrace(currentMismatch, currentMismatchStack);
  }

  try {
    PortableMasterKey.parsePortable(legacyEncoded);
    await _verifyVault(
      vaultFile,
      PortableMasterKeyRepository(
        storage: _ReadOnlyPortableMasterKeyStorage(legacyEncoded),
      ),
    );
  } on FormatException {
    Error.throwWithStackTrace(currentMismatch, currentMismatchStack);
  } on DataApiRemoteSessionFormatException {
    Error.throwWithStackTrace(currentMismatch, currentMismatchStack);
  }

  await synchronizedRepository.replaceAfterCryptographicVerification(
    legacyEncoded,
  );
  await _verifyVault(vaultFile, synchronizedRepository);
  await deleteLegacy();
  await writeStringAtomically(migrationMarker, 'complete\n');
  return true;
}

Future<void> _verifyVault(
  File vaultFile,
  PortableMasterKeyRepository masterKeyRepository,
) async {
  await EncryptedFileDataApiRemoteSessionStore(
    vaultFile: vaultFile,
    masterKeyRepository: masterKeyRepository,
  ).listSlotRefs();
}

final class _ReadOnlyPortableMasterKeyStorage
    implements PortableMasterKeyStorage {
  const _ReadOnlyPortableMasterKeyStorage(this.encoded);

  final String encoded;

  @override
  Future<String?> read() async => encoded;

  @override
  Future<void> write(String portableValue) {
    throw UnsupportedError('Recovery candidate storage is read-only.');
  }
}
