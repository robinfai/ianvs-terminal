import 'dart:io';

import 'package:app/data/services/data_api_device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  test(
    'installation ID persists locally and is scoped to the server origin',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trail-device-test-',
      );
      final original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      addTearDown(() async {
        PathProviderPlatform.instance = original;
        await directory.delete(recursive: true);
      });
      final first = await dataApiDeviceIdentity(
        Uri.parse('https://one.example/'),
      );
      expect(
        first,
        await dataApiDeviceIdentity(Uri.parse('https://one.example/path')),
      );
      expect(
        first,
        isNot(await dataApiDeviceIdentity(Uri.parse('https://two.example/'))),
      );
      final stored = await File(
        '${directory.path}/auth-installation-id',
      ).readAsString();
      expect(stored.length, 43);
      expect(first, isNot(stored));
    },
  );
}
