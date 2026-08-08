import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart' as pty;

import 'package:app/features/ssh/ssh_profile_import_service.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;

void main() {
  test(
    'native import is awaited through a non-blocking background boundary',
    () async {
      final release = Completer<SshProfileImportSnapshot>();
      var loaderInvoked = false;
      var eventLoopAdvanced = false;
      final service = NativeSshProfileImportService(
        backgroundLoader: (configPath) {
          loaderInvoked = true;
          expect(configPath, '/tmp/test-ssh-config');
          return release.future;
        },
      );

      final pending = service.load(configPath: '/tmp/test-ssh-config');
      unawaited(Future<void>(() => eventLoopAdvanced = true));
      await Future<void>.delayed(Duration.zero);

      expect(loaderInvoked, isTrue);
      expect(eventLoopAdvanced, isTrue);
      release.complete(
        const SshProfileImportSnapshot(
          profiles: [],
          sourcePath: '/tmp/test-ssh-config',
        ),
      );
      expect((await pending).sourcePath, '/tmp/test-ssh-config');
    },
  );

  test('maps imported OpenSSH forwarding settings into a terminal profile', () {
    const imported = pty.ImportedSshProfile(
      id: 'work',
      name: 'Work',
      group: 'Imported',
      source: 'openssh_config',
      alias: 'work',
      host: 'work.example.test',
      user: 'operator',
      port: 22,
      auth: 'keyboard_interactive',
      privateKeys: <String>['/keys/target_ed25519'],
      hostKeyPolicy: 'accept_new',
      connectTimeoutSeconds: 10,
      keepaliveSeconds: 15,
      keepaliveCountMax: 3,
      proxyJump: 'jump-user@jump-alias:2222',
      proxyJumpProfiles: <pty.ImportedSshJumpProfile>[
        pty.ImportedSshJumpProfile(
          host: 'jump.example.test',
          user: 'jump-user',
          port: 2222,
          auth: 'public_key',
          privateKeys: <String>['/keys/jump_ed25519'],
          hostKeyPolicy: 'strict',
          knownHostsFile: '/known/jump_hosts',
          connectTimeoutSeconds: 12,
          keepaliveSeconds: 20,
          keepaliveCountMax: 4,
        ),
      ],
      portForwards: <pty.ImportedSshPortForward>[
        pty.ImportedSshPortForward(
          type: pty.ImportedSshPortForwardType.local,
          bindHost: '127.0.0.1',
          bindPort: 8080,
          targetHost: 'app.internal',
          targetPort: 80,
        ),
      ],
      agentForwarding: true,
      x11Forwarding: true,
    );

    final profile = terminalProfileFromImportedSshConfig(imported);

    expect(
      profile.connection.auth,
      terminal.TerminalSshAuthMethod.keyboardInteractive,
    );
    expect(
      profile.connection.hostKeyPolicy,
      terminal.TerminalSshHostKeyPolicy.acceptNew,
    );
    expect(profile.connection.portForwards, hasLength(1));
    expect(profile.connection.portForwards.single.targetHost, 'app.internal');
    expect(profile.connection.agentForwarding, isTrue);
    expect(profile.connection.x11Forwarding, isFalse);
    expect(profile.connection.x11TargetHost, isNull);
    expect(profile.connection.x11AuthCookie, isNull);
    expect(profile.connection.privateKeys, <String>['/keys/target_ed25519']);
    expect(profile.connection.proxyJumpProfiles, hasLength(1));
    final jump = profile.connection.proxyJumpProfiles.single;
    expect(jump.host, 'jump.example.test');
    expect(jump.user, 'jump-user');
    expect(jump.port, 2222);
    expect(jump.auth, terminal.TerminalSshAuthMethod.publicKey);
    expect(jump.privateKeys, <String>['/keys/jump_ed25519']);
    expect(jump.privateKeys, isNot(profile.connection.privateKeys));
    expect(jump.hostKeyPolicy, terminal.TerminalSshHostKeyPolicy.strict);
    expect(jump.knownHostsFile, '/known/jump_hosts');
    expect(jump.connectTimeoutSeconds, 12);
    expect(jump.keepaliveSeconds, 20);
    expect(jump.keepaliveCountMax, 4);
    expect(
      () => terminal.TerminalSessionConfigV1(
        sessionId: 'imported-x11-disabled-safely',
        displayName: profile.name,
        config: profile.toSessionConfig(),
      ).toJsonString(),
      returnsNormally,
    );

    final snapshot = sshProfileImportSnapshotFromDocument(
      const pty.ImportedSshProfilesDocument(
        sourcePath: '/tmp/.ssh/config',
        sourceMtimeMicros: 7,
        profiles: <pty.ImportedSshProfile>[imported],
        warnings: <pty.SshConfigImportWarning>[],
      ),
    );
    expect(snapshot.profiles.single.connection.x11Forwarding, isFalse);
    expect(snapshot.warnings, hasLength(1));
    expect(snapshot.warnings.single, contains('ForwardX11 was disabled'));
  });
}
