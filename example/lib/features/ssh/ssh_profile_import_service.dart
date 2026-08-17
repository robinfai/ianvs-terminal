import 'dart:io';
import 'dart:isolate';

import 'package:ianvs_pty/ianvs_pty.dart' as pty;

import '../profiles/profile_models.dart';
import '../terminal/terminal.dart' as terminal;
import 'ssh_private_key_material.dart';

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
  pty.ImportedSshProfilesDocument imported, {
  String Function(String path) privateKeyLoader = readSshPrivateKeyContents,
}) {
  final warnings = imported.warnings
      .map(
        (warning) => warning.path.isEmpty
            ? warning.message
            : '${warning.path}: ${warning.message}',
      )
      .toList(growable: true);
  final profiles = imported.profiles
      .map(
        (profile) => terminalProfileFromImportedSshConfig(
          profile,
          privateKeyLoader: privateKeyLoader,
          onPrivateKeyWarning: warnings.add,
        ),
      )
      .toList(growable: false);
  warnings.addAll(
    imported.profiles
        .where((profile) => profile.x11Forwarding)
        .map(
          (profile) =>
              '${profile.name}: ForwardX11 was disabled because OpenSSH config does not provide a reusable 32-character MIT-MAGIC-COOKIE.',
        ),
  );
  return SshProfileImportSnapshot(
    sourcePath: imported.sourcePath,
    profiles: profiles,
    warnings: warnings,
  );
}

TerminalProfile terminalProfileFromImportedSshConfig(
  pty.ImportedSshProfile profile, {
  String Function(String path) privateKeyLoader = readSshPrivateKeyContents,
  void Function(String warning)? onPrivateKeyWarning,
}) {
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
          privateKeys: _materializeImportedPrivateKeys(
            jump.privateKeys,
            host: jump.host,
            user: jump.user,
            port: jump.port,
            profileName: profile.name,
            location: 'ProxyJump ${jump.user}@${jump.host}:${jump.port}',
            privateKeyLoader: privateKeyLoader,
            onWarning: onPrivateKeyWarning,
          ),
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
      privateKeys: _materializeImportedPrivateKeys(
        profile.privateKeys,
        host: profile.host,
        user: profile.user,
        port: profile.port,
        profileName: profile.name,
        location: 'target',
        privateKeyLoader: privateKeyLoader,
        onWarning: onPrivateKeyWarning,
      ),
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

List<String> _materializeImportedPrivateKeys(
  List<String> values, {
  required String host,
  required String user,
  required int port,
  required String profileName,
  required String location,
  required String Function(String path) privateKeyLoader,
  required void Function(String warning)? onWarning,
}) {
  final materialized = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (looksLikeSshPrivateKeyContents(trimmed)) {
      materialized.add(validateSshPrivateKeyContents(trimmed));
      continue;
    }
    final path = _expandImportedIdentityPath(
      trimmed,
      host: host,
      user: user,
      port: port,
    );
    try {
      materialized.add(privateKeyLoader(path));
    } on Object catch (error) {
      onWarning?.call(
        '$profileName: $location IdentityFile $path was omitted: '
        '${_privateKeyImportError(error)}',
      );
    }
  }
  return materialized;
}

String _expandImportedIdentityPath(
  String value, {
  required String host,
  required String user,
  required int port,
}) {
  const escapedPercent = '\u0000';
  final expanded = value
      .replaceAll('%%', escapedPercent)
      .replaceAll('%h', host)
      .replaceAll('%r', user)
      .replaceAll('%p', port.toString())
      .replaceAll(escapedPercent, '%');
  if (!expanded.startsWith('~/')) {
    return expanded;
  }
  final home = Platform.environment['HOME'];
  return home == null || home.isEmpty
      ? expanded
      : '$home/${expanded.substring(2)}';
}

String _privateKeyImportError(Object error) {
  return switch (error) {
    FormatException(:final message) => message,
    FileSystemException() => 'the private key file could not be read.',
    _ => 'the private key file could not be loaded.',
  };
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
