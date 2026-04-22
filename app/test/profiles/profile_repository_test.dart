import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';

void main() {
  test(
    'profile repository persists profiles to disk without legacy default field',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-profiles',
      );
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/flutterm_profiles.json');

      final document = TerminalProfilesDocument(
        profiles: [defaultTerminalProfile().copyWith(name: 'Custom Shell')],
      );

      await repository.save(document);
      final loaded = await repository.load();
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;

      expect(loaded.profiles.single.name, 'Custom Shell');
      expect(raw.containsKey('defaultProfileId'), isFalse);
    },
  );

  test(
    'profile repository seeds a strict VT220 preset on first launch without legacy default field',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-profiles-seeded',
      );
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/flutterm_profiles.json');

      final loaded = await repository.load();
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;

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
      expect(raw.containsKey('defaultProfileId'), isFalse);
    },
  );

  test(
    'profile repository ignores legacy defaultProfileId from older documents',
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
      expect(loaded.toJson().containsKey('defaultProfileId'), isFalse);
    },
  );

  test(
    'profile repository tolerates documents that omit defaultProfileId',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-profiles-missing-default',
      );
      final file = File('${directory.path}/flutterm_profiles.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'profiles': [
            {
              'id': 'default',
              'name': 'Local Shell',
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

      expect(loaded.profiles.single.id, 'default');
      expect(
        loaded.profiles.single.terminalEmulation,
        TerminalEmulation.xterm256,
      );
    },
  );
}
