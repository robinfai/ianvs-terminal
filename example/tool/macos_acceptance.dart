import 'dart:io';

import 'package:app/data/services/portable_master_key.dart';
import 'package:app/startup/app_startup_host.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The production app with an isolated data directory and platform-vault item.
/// Native PTY, SSH, recording, repositories, and UI are unchanged.
Future<void> main() async {
  const dataDirectory = String.fromEnvironment(
    'TRAIL_ACCEPTANCE_DATA_DIRECTORY',
    defaultValue: '/tmp/trail-macos-acceptance/data',
  );
  const keychainAccount = String.fromEnvironment(
    'TRAIL_ACCEPTANCE_KEYCHAIN_ACCOUNT',
    defaultValue: 'work.ianvs.trail.acceptance',
  );
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    AppStartupHost(
      coordinator: createProductionAppStartupCoordinator(
        appSupportDirectoryResolver: () async => Directory(dataDirectory),
        masterKeyRepository: PortableMasterKeyRepository(
          allowLegacyMigration: false,
          storage: const FlutterSecurePortableMasterKeyStorage(
            storage: FlutterSecureStorage(
              mOptions: MacOsOptions(
                accountName: keychainAccount,
                synchronizable: false,
                usesDataProtectionKeychain: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
