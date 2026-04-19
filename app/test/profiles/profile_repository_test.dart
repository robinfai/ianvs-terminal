import 'dart:io';
import 'dart:convert';

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

  test(
    'profile repository seeds a strict VT220 preset on first launch',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-profiles-seeded',
      );
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded.defaultProfileId, defaultTerminalProfile().id);
      expect(
        loaded.profiles.map((profile) => profile.id),
        containsAll(<String>[
          defaultTerminalProfile().id,
          vt220TerminalProfile().id,
        ]),
      );
      expect(
        loaded.profiles
            .firstWhere((profile) => profile.id == vt220TerminalProfile().id)
            .terminalEmulation,
        TerminalEmulation.vt220,
      );
    },
  );

  test(
    'profile repository migrates missing terminal emulation to xterm256',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-profiles-migration',
      );
      final file = File('${directory.path}/flutterm_profiles.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'defaultProfileId': 'legacy',
          'profiles': [
            {
              'id': 'legacy',
              'name': 'Legacy Shell',
              'shell': '/bin/zsh',
              'args': const <String>[],
              'env': const <String, String>{},
              'cwd': null,
            },
          ],
        }),
      );
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(
        loaded.profiles.single.terminalEmulation,
        TerminalEmulation.xterm256,
      );
    },
  );
}
