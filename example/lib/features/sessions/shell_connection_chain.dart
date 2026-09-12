import '../profiles/profile_models.dart';

enum ShellConnectionHopKind { localClient, localShell, sshShell, jump, proxy }

/// Display-only route metadata. Contains no authentication or control sockets.
class ShellConnectionHop {
  const ShellConnectionHop({
    required this.kind,
    this.contextId,
    this.host,
    this.user,
    this.port,
  });

  final ShellConnectionHopKind kind;
  final String? contextId;
  final String? host;
  final String? user;
  final int? port;

  String get address {
    final name = host ?? '';
    final bracketed = name.contains(':') && !name.startsWith('[')
        ? '[$name]'
        : name;
    return '${user?.isNotEmpty == true ? '$user@' : ''}$bracketed'
        '${port != null && port! > 0 ? ':$port' : ''}';
  }

  static List<ShellConnectionHop> forProfile(TerminalProfile? profile) {
    if (profile == null) return const [];
    if (!profile.isSsh) {
      return const [
        ShellConnectionHop(
          kind: ShellConnectionHopKind.localShell,
          contextId: 'root',
        ),
      ];
    }
    final connection = profile.sessionConfig.connection;
    final jumps = <ShellConnectionHop>[];
    final jumpAddresses = connection.proxyJump?.split(',') ?? const <String>[];
    for (var index = 0; index < jumpAddresses.length; index++) {
      final uri = Uri.tryParse('ssh://${jumpAddresses[index].trim()}');
      final override = index < connection.proxyJumpProfiles.length
          ? connection.proxyJumpProfiles[index]
          : null;
      jumps.add(
        ShellConnectionHop(
          kind: ShellConnectionHopKind.jump,
          host: override?.host.isNotEmpty == true ? override!.host : uri?.host,
          user: override?.user.isNotEmpty == true
              ? override!.user
              : uri?.userInfo.split(':').first,
          port: (override?.port ?? 0) > 0
              ? override!.port
              : (uri?.hasPort == true ? uri!.port : 22),
        ),
      );
    }
    return List.unmodifiable([
      const ShellConnectionHop(kind: ShellConnectionHopKind.localClient),
      ...jumps,
      if (connection.proxyCommand?.isNotEmpty == true)
        const ShellConnectionHop(kind: ShellConnectionHopKind.proxy),
      ShellConnectionHop(
        kind: ShellConnectionHopKind.sshShell,
        contextId: 'root',
        host: connection.host,
        user: connection.user,
        port: connection.port,
      ),
    ]);
  }
}
