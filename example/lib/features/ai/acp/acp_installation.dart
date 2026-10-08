import 'dart:convert';
import 'dart:io';

import '../ai_models.dart';

/// Launch details only. Discovery does not run an agent, a shell or npm, and
/// does not access credentials. The connection test performs the ACP handshake.
class AcpInstallation {
  const AcpInstallation({
    required this.command,
    this.arguments = const [],
    this.version,
  });

  final String command;
  final List<String> arguments;
  final String? version;
}

class AcpInstallationDiscovery {
  AcpInstallationDiscovery({
    required Map<String, String> environment,
    String? workingDirectory,
    String? executable,
    String? operatingSystem,
    this.systemBinDirectories = const [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
    ],
  }) : environment = Map.unmodifiable(environment),
       workingDirectory = workingDirectory ?? Directory.current.path,
       executable = executable ?? Platform.resolvedExecutable,
       operatingSystem = operatingSystem ?? Platform.operatingSystem;

  final Map<String, String> environment;
  final String workingDirectory;
  final String executable;
  final String operatingSystem;
  final List<String> systemBinDirectories;

  Future<AcpInstallation> discover() async {
    if (!{'macos', 'linux'}.contains(operatingSystem)) {
      throw const AiFailure('acp_discovery_platform');
    }
    final bins = <String>{
      ...?environment['PATH']?.split(':').where(_absolute),
      ...systemBinDirectories,
    };
    final home = environment['HOME'];
    if (home != null && _absolute(home)) {
      bins.addAll([
        '$home/.local/bin',
        '$home/.npm-global/bin',
        '$home/.npm/bin',
      ]);
      // Finder does not inherit an interactive shell's version-manager PATH.
      for (final (root, suffix) in [
        (
          '${environment['FNM_DIR'] ?? '$home/.local/share/fnm'}/node-versions',
          'installation/bin',
        ),
        (
          '$home/Library/Application Support/fnm/node-versions',
          'installation/bin',
        ),
        ('$home/.fnm/node-versions', 'installation/bin'),
        ('${environment['NVM_DIR'] ?? '$home/.nvm'}/versions/node', 'bin'),
        (
          '${environment['VOLTA_HOME'] ?? '$home/.volta'}/tools/image/node',
          'bin',
        ),
        (
          '${environment['ASDF_DATA_DIR'] ?? '$home/.asdf'}/installs/nodejs',
          'bin',
        ),
      ]) {
        if (_absolute(root)) {
          for (final version in await _children(root)) {
            bins.add('$version/$suffix');
          }
        }
      }
    }
    for (final key in ['npm_config_prefix', 'NPM_CONFIG_PREFIX']) {
      final prefix = environment[key];
      if (prefix != null && _absolute(prefix)) bins.add('$prefix/bin');
    }

    // Resolve fnm multishell and npm symlinks so saved settings survive the
    // terminal session that created them. Keep prefixes for global npm installs.
    final nodes = <String>{};
    for (final bin in bins.toList()) {
      final node = await _file('$bin/node', executable: true);
      if (node != null) {
        nodes.add(node);
        bins.add(File(node).parent.path);
      }
    }
    final packages = <String>{};
    for (final bin in bins) {
      final adapter = await _file('$bin/codex-acp');
      if (adapter != null) {
        // npm's bin symlink points into the package's dist directory.
        packages.addAll(_ancestors(File(adapter).parent.path).take(3));
        if (await _nativeExecutable(adapter)) {
          return AcpInstallation(command: adapter);
        }
      }
      final prefix = Directory(bin).parent.path;
      packages.add('$prefix/lib/node_modules/@agentclientprotocol/codex-acp');
      packages.add('$prefix/node_modules/@agentclientprotocol/codex-acp');
    }
    for (final root in {
      ..._ancestors(workingDirectory),
      ..._ancestors(File(executable).parent.path),
    }) {
      packages.add('$root/node_modules/@agentclientprotocol/codex-acp');
      // Repository-local installation used by Trail's development/bench tools.
      if (await File(
        '$root/example/lib/features/ai/ai_settings.dart',
      ).exists()) {
        packages.add(
          '$root/tmp/acp-runtime/node_modules/@agentclientprotocol/codex-acp',
        );
      }
    }
    var foundAdapter = false;
    for (final package in packages) {
      final entry = await _packageEntry(package);
      if (entry == null) continue;
      foundAdapter = true;
      if (nodes.isNotEmpty) {
        return AcpInstallation(
          command: nodes.first,
          arguments: [entry.$1],
          version: entry.$2,
        );
      }
    }
    throw AiFailure(foundAdapter ? 'acp_node_missing' : 'acp_adapter_missing');
  }

  static bool _absolute(String path) => path.startsWith('/');

  static Iterable<String> _ancestors(String path) sync* {
    var directory = Directory(path).absolute;
    for (var i = 0; i < 12 && directory.path != directory.parent.path; i++) {
      yield directory.path;
      directory = directory.parent;
    }
  }

  static Future<List<String>> _children(String path) async {
    try {
      final entries = await Directory(path)
          .list(followLinks: false)
          .where((entry) => entry is Directory)
          .take(64)
          .toList();
      // Prefer recent installed versions without relying on lexicographic order.
      entries.sort((a, b) {
        List<int> parts(String p) => RegExp(r'\d+')
            .allMatches(p.split('/').last)
            .map((m) => int.tryParse(m[0]!) ?? 0)
            .toList();
        final ap = parts(a.path);
        final bp = parts(b.path);
        for (var i = 0; i < ap.length && i < bp.length; i++) {
          final order = bp[i].compareTo(ap[i]);
          if (order != 0) return order;
        }
        return b.path.compareTo(a.path);
      });
      return entries.map((e) => e.path).toList();
    } on FileSystemException {
      return const [];
    }
  }

  static Future<String?> _file(String path, {bool executable = false}) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          (executable && stat.mode & 0x49 == 0)) {
        return null;
      }
      return await file.resolveSymbolicLinks();
    } on FileSystemException {
      return null;
    }
  }

  static Future<(String, String?)?> _packageEntry(String root) async {
    try {
      final file = File('$root/package.json');
      if (await file.length() > 128 * 1024) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['name'] != '@agentclientprotocol/codex-acp') {
        return null;
      }
      final bin = json['bin'];
      final entry = bin is String
          ? bin
          : (bin is Map ? bin['codex-acp'] : null);
      if (entry is! String || entry.startsWith('/') || entry.contains('..')) {
        return null;
      }
      final path = await _file('$root/$entry');
      final package = await Directory(root).resolveSymbolicLinks();
      if (path == null || !path.startsWith('$package/')) return null;
      return (
        path,
        json['version'] is String ? json['version'] as String : null,
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<bool> _nativeExecutable(String path) async {
    if (await _file(path, executable: true) == null) return false;
    try {
      final file = await File(path).open();
      try {
        final bytes = await file.read(4);
        // Native release binaries; shell wrappers still require manual config.
        final magic = bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        return {
          '7f454c46',
          'cffaedfe',
          'cefaedfe',
          'feedfacf',
          'feedface',
          'cafebabe',
          'bebafeca',
        }.contains(magic);
      } finally {
        await file.close();
      }
    } on FileSystemException {
      return false;
    }
  }
}
