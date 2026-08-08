import 'dart:isolate';

import 'package:ianvs_pty/ianvs_pty.dart' as pty;

import '../profiles/profile_models.dart';
import '../terminal/terminal.dart' as terminal;

final class SshProfileImportSnapshot {
  const SshProfileImportSnapshot({
    required this.profiles,
    required this.sourcePath,
    this.warnings = const <String>[],
    this.error,
  });

  final List<TerminalProfile> profiles;
  final String sourcePath;
  final List<String> warnings;
  final String? error;
}

abstract interface class SshProfileImportService {
  Future<SshProfileImportSnapshot> load({String? configPath});
}

typedef SshProfileImportBackgroundLoader =
    Future<SshProfileImportSnapshot> Function(String? configPath);

final class NativeSshProfileImportService implements SshProfileImportService {
  const NativeSshProfileImportService({
    SshProfileImportBackgroundLoader backgroundLoader =
        _loadNativeSshProfilesInBackground,
  }) : _backgroundLoader = backgroundLoader;

  final SshProfileImportBackgroundLoader _backgroundLoader;

  @override
  Future<SshProfileImportSnapshot> load({String? configPath}) async {
    try {
      return await _backgroundLoader(configPath);
    } on Object catch (error) {
      return SshProfileImportSnapshot(
        sourcePath: configPath ?? '~/.ssh/config',
        profiles: const <TerminalProfile>[],
        error: 'OpenSSH profiles could not be loaded: $error',
      );
    }
  }
}

Future<SshProfileImportSnapshot> _loadNativeSshProfilesInBackground(
  String? configPath,
) {
  return Isolate.run(() => _loadNativeSshProfiles(configPath));
}

SshProfileImportSnapshot _loadNativeSshProfiles(String? configPath) {
  final imported = pty.NativeSshConfigImporter.load().importProfiles(
    configPath: configPath,
  );
  return sshProfileImportSnapshotFromDocument(imported);
}

SshProfileImportSnapshot sshProfileImportSnapshotFromDocument(
  pty.ImportedSshProfilesDocument imported,
) {
  return SshProfileImportSnapshot(
    sourcePath: imported.sourcePath,
    profiles: imported.profiles
        .map(terminalProfileFromImportedSshConfig)
        .toList(growable: false),
    warnings: imported.warnings
        .map(
          (warning) => warning.path.isEmpty
              ? warning.message
              : '${warning.path}: ${warning.message}',
        )
        .followedBy(
          imported.profiles
              .where((profile) => profile.x11Forwarding)
              .map(
                (profile) =>
                    '${profile.name}: ForwardX11 was disabled because OpenSSH config does not provide a reusable 32-character MIT-MAGIC-COOKIE.',
              ),
        )
        .toList(growable: false),
  );
}

TerminalProfile terminalProfileFromImportedSshConfig(
  pty.ImportedSshProfile profile,
) {
  final hostKeyPolicy = _terminalHostKeyPolicy(profile.hostKeyPolicy);
  final auth = _terminalAuthMethod(profile.auth);
  final portForwards = profile.portForwards
      .map((forward) {
        final type = switch (forward.type) {
          pty.ImportedSshPortForwardType.local =>
            terminal.TerminalSshPortForwardType.local,
          pty.ImportedSshPortForwardType.remote =>
            terminal.TerminalSshPortForwardType.remote,
          pty.ImportedSshPortForwardType.dynamic =>
            terminal.TerminalSshPortForwardType.dynamic,
        };
        return terminal.TerminalSshPortForwardConfig(
          type: type,
          bindHost: forward.bindHost,
          bindPort: forward.bindPort,
          targetHost: forward.targetHost,
          targetPort: forward.targetPort,
        );
      })
      .toList(growable: false);
  final proxyJumpProfiles = profile.proxyJumpProfiles
      .map(
        (jump) => terminal.TerminalSshJumpConfig(
          host: jump.host,
          user: jump.user,
          port: jump.port,
          auth: _terminalAuthMethod(jump.auth),
          privateKeys: jump.privateKeys,
          hostKeyPolicy: _terminalHostKeyPolicy(jump.hostKeyPolicy),
          knownHostsFile: jump.knownHostsFile,
          connectTimeoutSeconds: jump.connectTimeoutSeconds,
          keepaliveSeconds: jump.keepaliveSeconds,
          keepaliveCountMax: jump.keepaliveCountMax,
        ),
      )
      .toList(growable: false);
  return defaultTerminalProfile().copyWith(
    id: profile.id,
    name: profile.name,
    tags: const <String>['SSH', 'OpenSSH'],
    connection: terminal.TerminalConnectionConfig.ssh(
      host: profile.host,
      user: profile.user,
      port: profile.port,
      auth: auth,
      privateKeys: profile.privateKeys,
      hostKeyPolicy: hostKeyPolicy,
      knownHostsFile: profile.knownHostsFile,
      connectTimeoutSeconds: profile.connectTimeoutSeconds,
      keepaliveSeconds: profile.keepaliveSeconds,
      keepaliveCountMax: profile.keepaliveCountMax,
      proxyCommand: profile.proxyCommand,
      proxyJump: profile.proxyJump,
      proxyJumpProfiles: proxyJumpProfiles,
      portForwards: portForwards,
      agentForwarding: profile.agentForwarding,
      // OpenSSH config expresses the forwarding intent but never supplies the
      // concrete 16-byte cookie required by the runtime. Disable it with an
      // import warning instead of relaying an unauthenticated X11 request.
      x11Forwarding: false,
    ),
  );
}

terminal.TerminalSshAuthMethod _terminalAuthMethod(String value) {
  return switch (value) {
    'password' => terminal.TerminalSshAuthMethod.password,
    'public_key' => terminal.TerminalSshAuthMethod.publicKey,
    'keyboard_interactive' =>
      terminal.TerminalSshAuthMethod.keyboardInteractive,
    _ => terminal.TerminalSshAuthMethod.auto,
  };
}

terminal.TerminalSshHostKeyPolicy _terminalHostKeyPolicy(String value) {
  return switch (value) {
    'accept_new' => terminal.TerminalSshHostKeyPolicy.acceptNew,
    'insecure' => terminal.TerminalSshHostKeyPolicy.insecure,
    _ => terminal.TerminalSshHostKeyPolicy.strict,
  };
}
