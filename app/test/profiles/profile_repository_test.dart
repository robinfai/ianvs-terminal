import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';

void main() {
  test('profile repository persists profiles to disk', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flutterm-profiles',
    );
    final repository = ProfileRepository(
      directoryResolver: () async => directory,
    );

    final document = TerminalProfilesDocument(
      defaultProfileId: 'default',
      profiles: [defaultTerminalProfile().copyWith(name: 'Custom Shell')],
    );

    await repository.save(document);
    final loaded = await repository.load();

    expect(loaded.defaultProfileId, 'default');
    expect(loaded.profiles.single.name, 'Custom Shell');
  });
}
