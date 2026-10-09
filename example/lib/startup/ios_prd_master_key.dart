import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/services/portable_master_key.dart';

/// The opt-in comes from the signed native bundle, never from Dart defines.
/// Missing or malformed native identity leaves the normal iOS consumer-only
/// repository in charge; it must not silently create a production master key.
Future<PortableMasterKeyRepository?> resolveIosPrdMasterKeyRepository({
  MethodChannel channel = const MethodChannel('app/build_identity'),
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return null;
  }
  try {
    final identity = await channel.invokeMapMethod<String, Object?>(
      'readIdentity',
    );
    if (identity?['bundleId'] != 'work.ianvs.trail.mobileprd' ||
        identity?['deviceLocalMasterKey'] != true) {
      return null;
    }
    return PortableMasterKeyRepository(
      storage: const FlutterSecurePortableMasterKeyStorage.iosPrdDeviceOnly(),
      allowCreation: true,
      allowLegacyMigration: false,
    );
  } on Object {
    return null;
  }
}
