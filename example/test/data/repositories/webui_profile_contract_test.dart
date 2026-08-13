import 'dart:convert';
import 'dart:io';

import 'package:app/data/repositories/data_api_repository_helpers.dart';
import 'package:app/features/profiles/data_api_profile_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Web UI profile document contract', () {
    test(
      'accepts the canonical web fixture and reproduces its recursive sensitive envelope',
      () {
        final fixtureFile = _fixtureFile();
        final fixture = dataApiObject(
          jsonDecode(fixtureFile.readAsStringSync()),
          documentName: 'Web UI profile fixture',
        );
        final data = dataApiObject(
          fixture['data'],
          documentName: 'Web UI profile data',
        );
        final sensitive = dataApiObject(
          fixture['sensitive'],
          documentName: 'Web UI profile sensitive data',
        );

        final document = TerminalProfilesDocument.fromJson(
          mergeDataApiObjects(data, sensitive),
        );
        final encoded = encodeDataApiProfilesDocument(document);

        expect(
          dataApiJsonEquivalent(encoded.data, data),
          isTrue,
          reason: 'Dart encoded data:\n${jsonEncode(encoded.data)}',
        );
        expect(
          dataApiJsonEquivalent(encoded.sensitive, sensitive),
          isTrue,
          reason:
              'Dart encoded sensitive data:\n'
              '${jsonEncode(encoded.sensitive)}',
        );
        final connection = document.profiles.single.connection;
        expect(connection.password, ' target password ');
        expect(connection.proxyJumpProfiles.single.password, ' jump password ');
        expect(
          connection.proxyJumpProfiles.single.privateKeyPassphrase,
          ' jump passphrase ',
        );
      },
    );
  });
}

File _fixtureFile() {
  final fromExample = File(
    '../backend/webui/test/fixtures/profile_document.json',
  );
  if (fromExample.existsSync()) {
    return fromExample;
  }
  return File('backend/webui/test/fixtures/profile_document.json');
}
