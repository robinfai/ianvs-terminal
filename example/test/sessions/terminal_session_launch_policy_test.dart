import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/terminal_session_launch_policy.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final localProfile = defaultTerminalProfile();
  final sshProfile = TerminalProfile(
    id: 'ssh',
    name: 'SSH',
    shell: '',
    connection: const terminal.TerminalConnectionConfig.ssh(
      host: 'ssh.example.test',
      user: 'operator',
    ),
  );

  test('iOS policy exposes only SSH and waits for an explicit choice', () {
    final policy = TerminalSessionLaunchPolicy.forPlatform(TargetPlatform.iOS);

    expect(policy.isSshOnly, isTrue);
    expect(policy.allows(localProfile), isFalse);
    expect(policy.allows(sshProfile), isTrue);
    expect(policy.visibleProfiles([localProfile, sshProfile]), [sshProfile]);
    expect(policy.opensDefaultSessionOnEmptyLayout, isFalse);
  });

  test('macOS policy preserves local and SSH session behavior', () {
    final policy = TerminalSessionLaunchPolicy.forPlatform(
      TargetPlatform.macOS,
    );

    expect(policy.localSessionsEnabled, isTrue);
    expect(policy.visibleProfiles([localProfile, sshProfile]), [
      localProfile,
      sshProfile,
    ]);
    expect(policy.opensDefaultSessionOnEmptyLayout, isTrue);
  });
}
