import 'package:app/features/shell/terminal_file_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  const local = CommandOccurrenceScope(
    sessionId: 's',
    sessionEpoch: 7,
    transport: CommandTransportIdentity(kind: CommandTransportKind.local),
  );
  const ssh = CommandOccurrenceScope(
    sessionId: 's',
    sessionEpoch: 7,
    transport: CommandTransportIdentity(
      kind: CommandTransportKind.ssh,
      host: 'server.test',
      user: 'dev',
      port: 22,
    ),
  );
  TerminalSemanticFileTarget target({
    String path = 'src/main.dart',
    String host = 'localhost',
    int epoch = 7,
    String context = 'root',
    String cwd = '/old/project',
    String? routeLease,
  }) => TerminalSemanticFileTarget(
    path: path,
    line: 12,
    column: 3,
    context: TerminalSemanticContext(
      occurrenceId: 'old-command',
      sessionId: 's',
      sessionEpoch: epoch,
      cwd: cwd,
      contextId: context,
      shellHostname: host,
      sftpContextId: routeLease,
    ),
  );

  TerminalFileLocation? resolve(
    TerminalSemanticFileTarget target,
    CommandOccurrenceScope scope, {
    bool route = false,
    String context = 'root',
    String? remoteHost,
    String remoteContextId = 'root',
  }) => resolveTerminalFileLocation(
    target: target,
    scope: scope,
    activeContextId: context,
    hasRemoteRoute: route,
    remoteHost: remoteHost,
    remoteContextId: remoteContextId,
    localHostnames: {'localhost'},
  );

  test('relative file binds historical cwd and retains line and column', () {
    final location = resolve(target(), local)!;
    expect(location.path, '/old/project/src/main.dart');
    expect(location.parent, '/old/project/src');
    expect(location.line, 12);
    expect(location.column, 3);
    expect(location.localUri, 'file:///old/project/src/main.dart');
  });

  test('SSH file never resolves as local even with a local hostname claim', () {
    expect(resolve(target(), ssh, route: true), isNull);
    final remote = resolve(target(host: 'server.test'), ssh, route: true)!;
    expect(remote.remote, isTrue);
    expect(remote.path, '/old/project/src/main.dart');
  });

  test('unknown nested host does not fall back to outer SSH endpoint', () {
    expect(resolve(target(host: 'inner.test'), ssh, route: true), isNull);
    expect(
      resolve(
        target(host: 'inner.test', context: 'inner'),
        ssh,
        context: 'inner',
      ),
      isNull,
    );
    final routed = resolve(
      target(host: 'inner.test', context: 'inner', routeLease: 'inner@1'),
      ssh,
      context: 'inner',
      route: true,
      remoteHost: 'inner.test',
      remoteContextId: 'inner@1',
    );
    expect(routed?.remote, isTrue);
  });

  test(
    'same nested host and context require the original route generation',
    () {
      for (final lease in [null, 'inner@1']) {
        expect(
          resolve(
            target(host: 'inner.test', context: 'inner', routeLease: lease),
            ssh,
            context: 'inner',
            route: true,
            remoteHost: 'inner.test',
            remoteContextId: 'inner@2',
          ),
          isNull,
        );
      }
    },
  );

  test('stale incarnation and historical context switch fail closed', () {
    expect(resolve(target(epoch: 6), local), isNull);
    expect(resolve(target(context: 'old-context'), local), isNull);
  });

  test('shell remote claim on a local transport is not a usable route', () {
    expect(resolve(target(host: 'other.test'), local), isNull);
  });

  test('control bytes and unknown home expansion are not opened', () {
    for (final path in ['~/secret', 'bad\u0000file', 'https://server/file']) {
      expect(resolve(target(path: path), local), isNull);
    }
  });

  test('semantic paths do not collapse symlink parent traversal', () {
    // If /old/project/link points to /outside/child, link/../file.txt
    // denotes /outside/file.txt, never /old/project/file.txt.
    for (final path in [
      'link/../file.txt',
      '/old/project/link/../file.txt',
      '../file.txt',
      '//host/file.txt',
    ]) {
      expect(resolve(target(path: path), local), isNull);
      expect(
        resolve(target(path: path, host: 'server.test'), ssh, route: true),
        isNull,
      );
    }
    expect(resolve(target(cwd: '/old/link/..'), local), isNull);
    expect(resolve(target(cwd: '//host/project'), local), isNull);
    expect(
      resolve(target(path: './src//main.dart'), local)?.path,
      '/old/project/src/main.dart',
    );
  });

  test('file URI encoding preserves spaces without executing shell syntax', () {
    final location = resolve(target(path: r'a b;$(echo nope).txt'), local)!;
    expect(
      Uri.parse(location.localUri).toFilePath(),
      r'/old/project/a b;$(echo nope).txt',
    );
  });
}
