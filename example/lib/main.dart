import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'startup/app_environment.dart';
import 'startup/app_startup_host.dart';
import 'startup/ios_prd_master_key.dart';
import 'startup/production_app_startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final masterKeyRepository = await resolveIosPrdMasterKeyRepository();
  runApp(
    AppStartupHost(
      coordinator: createProductionAppStartupCoordinator(
        masterKeyRepository: masterKeyRepository,
        environment: AppEnvironment.forBuild(
          platform: defaultTargetPlatform,
          releaseMode: kReleaseMode,
        ),
      ),
    ),
  );
}
