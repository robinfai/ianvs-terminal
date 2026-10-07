import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/acp/acp_installation.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late String root;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('trail-acp-discovery-');
    root = await temporary.resolveSymbolicLinks();
  });
  tearDown(() => temporary.delete(recursive: true));

  Future<void> write(
    String path,
    String contents, {
    bool executable = false,
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    if (executable) await Process.run('/bin/chmod', ['700', path]);
  }

  Future<String> adapter(
    String path, {
    String name = '@agentclientprotocol/codex-acp',
  }) async {
    await write(
      '$path/package.json',
      jsonEncode({
        'name': name,
        'version': '2.1.1',
        'bin': {'codex-acp': 'dist/index.js'},
      }),
    );
    await write('$path/dist/index.js', 'throw new Error("must not execute");');
    return '$path/dist/index.js';
  }

  AcpInstallationDiscovery discovery({
    Map<String, String> environment = const {},
    String? cwd,
    String? executable,
    String os = 'macos',
  }) => AcpInstallationDiscovery(
    environment: environment,
    workingDirectory: cwd ?? '$root/workspace',
    executable: executable ?? '$root/app/bin/trail',
    operatingSystem: os,
    systemBinDirectories: const [],
  );

  Matcher failure(String code) =>
      throwsA(isA<AiFailure>().having((e) => e.code, 'code', code));

  test(
    'resolves npm and transient Node symlinks without executing them',
    () async {
      final node = '$root/versions/v22.22.0/installation/bin/node';
      await write(
        node,
        '#!/bin/sh\ntouch "$root/executed"\n',
        executable: true,
      );
      final entry = await adapter('$root/packages/codex-acp');
      await Directory('$root/session/bin').create(recursive: true);
      await Link('$root/session/bin/node').create(node);
      await Link('$root/session/bin/codex-acp').create(entry);
      final found = await discovery(
        environment: {'PATH': '$root/session/bin'},
      ).discover();
      expect(found.command, node);
      expect(found.arguments, [entry]);
      expect(found.version, '2.1.1');
      expect(await File('$root/executed').exists(), isFalse);
    },
  );

  test(
    'Finder launch finds fnm and repository-local development adapter',
    () async {
      final home = '$root/home';
      final node =
          '$home/.local/share/fnm/node-versions/v22.22.0/installation/bin/node';
      await write(node, '#!/bin/sh\n', executable: true);
      // Numeric version ordering: v9 must not take precedence over v22.
      await write(
        '$home/.local/share/fnm/node-versions/v9.0.0/installation/bin/node',
        '#!/bin/sh\n',
        executable: true,
      );
      final project = '$root/project';
      await write('$project/example/lib/features/ai/ai_settings.dart', '');
      final entry = await adapter(
        '$project/tmp/acp-runtime/node_modules/@agentclientprotocol/codex-acp',
      );
      final found = await discovery(
        environment: {'HOME': home},
        cwd: '/',
        executable:
            '$project/example/build/macos/Build/Products/Debug/Trail Development.app/Contents/MacOS/Trail',
      ).discover();
      expect(found.command, node);
      expect(found.arguments, [entry]);
    },
  );

  test('finds nvm global package without an interactive shell PATH', () async {
    final prefix = '$root/home/.nvm/versions/node/v22.0.0';
    await write('$prefix/bin/node', '#!/bin/sh\n', executable: true);
    final entry = await adapter(
      '$prefix/lib/node_modules/@agentclientprotocol/codex-acp',
    );
    final found = await discovery(
      environment: {'HOME': '$root/home'},
    ).discover();
    expect(found.command, '$prefix/bin/node');
    expect(found.arguments, [entry]);
  });

  test('honors npm prefix and keeps spaces in a single argument', () async {
    await write('$root/bin/node', '#!/bin/sh\n', executable: true);
    final entry = await adapter(
      '$root/npm prefix/lib/node_modules/@agentclientprotocol/codex-acp',
    );
    final found = await discovery(
      environment: {
        'PATH': '$root/bin',
        'npm_config_prefix': '$root/npm prefix',
      },
    ).discover();
    expect(found.arguments, [entry]);
  });

  test('native adapter does not require Node', () async {
    await write('$root/bin/codex-acp', '', executable: true);
    await File('$root/bin/codex-acp').writeAsBytes([0xcf, 0xfa, 0xed, 0xfe]);
    final found = await discovery(
      environment: {'PATH': '$root/bin'},
    ).discover();
    expect(found.command, '$root/bin/codex-acp');
    expect(found.arguments, isEmpty);
  });

  test('missing or non-executable Node gives a specific error', () async {
    await adapter(
      '$root/workspace/node_modules/@agentclientprotocol/codex-acp',
    );
    await write('$root/bin/node', 'not executable');
    await expectLater(
      discovery(environment: {'PATH': '$root/bin'}).discover(),
      failure('acp_node_missing'),
    );
  });

  test(
    'missing adapter, broken links and unrelated package are skipped',
    () async {
      await write('$root/bin/node', '#!/bin/sh\n', executable: true);
      await Link('$root/bin/codex-acp').create('$root/missing');
      await adapter(
        '$root/lib/node_modules/@agentclientprotocol/codex-acp',
        name: 'unrelated',
      );
      await expectLater(
        discovery(environment: {'PATH': '$root/bin'}).discover(),
        failure('acp_adapter_missing'),
      );
    },
  );

  test(
    'malformed manifests and entry points escaping the package are skipped',
    () async {
      await write('$root/bin/node', '#!/bin/sh\n', executable: true);
      final package =
          '$root/workspace/node_modules/@agentclientprotocol/codex-acp';
      await write('$package/package.json', '{broken');
      final lookup = discovery(environment: {'PATH': '$root/bin'});
      await expectLater(lookup.discover(), failure('acp_adapter_missing'));
      await adapter(package);
      await File('$package/dist/index.js').delete();
      await write('$root/outside.js', '');
      await Link('$package/dist/index.js').create('$root/outside.js');
      await expectLater(lookup.discover(), failure('acp_adapter_missing'));
    },
  );

  test('mobile fails before filesystem discovery', () async {
    await expectLater(
      discovery(os: 'ios').discover(),
      failure('acp_discovery_platform'),
    );
  });
}
