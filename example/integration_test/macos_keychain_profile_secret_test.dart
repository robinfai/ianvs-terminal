import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS Keychain stores and deletes an SSH profile secret', (
    WidgetTester tester,
  ) async {
    expect(Platform.isMacOS, isTrue);

    final suffix = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final key = 'ssh-profile-secret-$suffix';
    final storage = FlutterSecureStorage(
      mOptions: MacOsOptions(
        accountName: 'dev.ianvs.terminal.integration-test.$suffix',
        usesDataProtectionKeychain: false,
        synchronizable: false,
      ),
    );
    addTearDown(() async {
      // flutter_secure_storage_darwin 0.3.2 probes the synchronizable
      // keychain when deleting an already-missing item, which can return
      // errSecMissingEntitlement for an intentionally non-synchronizing app.
      // Read first so teardown stays idempotent without weakening production
      // Keychain options or masking a real item that still needs removal.
      if (await storage.read(key: key) != null) {
        await storage.delete(key: key);
      }
    });

    final secret = 'integration-secret-$suffix';
    await storage.write(key: key, value: secret);
    expect(await storage.read(key: key), secret);

    await storage.delete(key: key);
    expect(await storage.read(key: key), isNull);
  });
}
