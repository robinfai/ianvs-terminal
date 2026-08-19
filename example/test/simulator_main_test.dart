import 'package:app/simulator_main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseIosSimulatorCredentialsUrl', () {
    test('treats an absent or blank broker URL as credential-free launch', () {
      expect(parseIosSimulatorCredentialsUrl(null), isNull);
      expect(parseIosSimulatorCredentialsUrl(''), isNull);
      expect(parseIosSimulatorCredentialsUrl('   '), isNull);
    });

    test('accepts only an ephemeral loopback broker URL', () {
      expect(
        parseIosSimulatorCredentialsUrl(' http://127.0.0.1:43210/once '),
        Uri.parse('http://127.0.0.1:43210/once'),
      );
      expect(
        () => parseIosSimulatorCredentialsUrl('https://example.com/secret'),
        throwsFormatException,
      );
    });
  });

  group('IosSimulatorAcceptanceConfiguration', () {
    test('accepts a brokered master key and complete login', () {
      final configuration =
          IosSimulatorAcceptanceConfiguration.fromCredentialDocument(
            const <String, Object?>{
              'encryption_key': 'simulator-test-key-material',
              'username': 'alice',
              'password': 'acceptance-password',
            },
            remoteApiUrl: 'https://sync.example.com/',
          );

      expect(configuration.masterKey, 'simulator-test-key-material');
      expect(configuration.remoteApiUrl, 'https://sync.example.com/');
      expect(configuration.username, 'alice');
      expect(configuration.password, 'acceptance-password');
    });

    test('uses the production remote URL when the override is empty', () {
      final configuration =
          IosSimulatorAcceptanceConfiguration.fromCredentialDocument(
            const <String, Object?>{
              'encryption_key': 'simulator-test-key-material',
              'username': 'alice',
              'password': 'acceptance-password',
            },
            remoteApiUrl: '',
          );

      expect(configuration.remoteApiUrl, 'https://api.terminal.ianvs.work/');
    });

    test('rejects incomplete brokered credentials', () {
      expect(
        () => IosSimulatorAcceptanceConfiguration.fromCredentialDocument(
          const <String, Object?>{
            'encryption_key': 'simulator-test-key-material',
            'username': 'alice',
          },
        ),
        throwsFormatException,
      );
    });

    test('rejects an invalid master key', () {
      expect(
        () => IosSimulatorAcceptanceConfiguration.fromCredentialDocument(
          const <String, Object?>{
            'encryption_key': '',
            'username': 'alice',
            'password': 'acceptance-password',
          },
        ),
        throwsFormatException,
      );
    });
  });
}
