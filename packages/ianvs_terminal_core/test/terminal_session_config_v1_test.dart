import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

void main() {
  group('TerminalSessionConfigV1', () {
    test('round-trips the declared config and ignores additive fields', () {
      final wire = TerminalSessionConfigV1(
        sessionId: 'runtime-7',
        displayName: 'zsh',
        config: _config(),
      );
      final json = wire.toJson()..['future_top_level'] = true;
      (json['config']! as Map<String, Object?>)['future_config_field'] =
          <String, Object?>{'value': 1};

      final decoded = TerminalSessionConfigV1.fromJsonString(jsonEncode(json));

      expect(decoded.schemaVersion, 1);
      expect(decoded.contract, 'ianvs-session-config-v1');
      expect(decoded.sessionId, 'runtime-7');
      expect(decoded.displayName, 'zsh');
      expect(decoded.config.launch.program, '/bin/zsh');
      expect(decoded.config.launch.args, <String>['-l']);
      expect(decoded.config.launch.env, <String, String>{'LANG': 'C.UTF-8'});
      expect(decoded.config.scrollbackLines, 1234);
      expect(decoded.config.dragDropEnabled, isTrue);
      expect(decoded.config.display.font.family, 'Menlo');
      expect(decoded.config.interaction.copyOnSelect, isTrue);
      expect(decoded.zmodemEnabled, isFalse);
    });

    test('returns structured errors for unsupported and oversized input', () {
      expect(
        () => TerminalSessionConfigV1.fromJson(<String, Object?>{
          'schema_version': 2,
        }),
        throwsA(
          isA<TerminalSessionConfigContractException>()
              .having((error) => error.code, 'code', 'unsupported_schema')
              .having((error) => error.path, 'path', r'$.schema_version'),
        ),
      );
      expect(
        () => TerminalSessionConfigV1.fromJsonString(
          ' ' * (TerminalSessionConfigV1.maxEncodedBytes + 1),
        ),
        throwsA(
          isA<TerminalSessionConfigContractException>().having(
            (error) => error.code,
            'code',
            'encoded_config_too_large',
          ),
        ),
      );
    });

    test('rejects missing config and empty launch program', () {
      expect(
        () => TerminalSessionConfigV1.fromJson(<String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-session-config-v1',
          'session_id': 'runtime-1',
          'display_name': 'shell',
        }),
        throwsA(
          isA<TerminalSessionConfigContractException>().having(
            (error) => error.code,
            'code',
            'missing_field',
          ),
        ),
      );
      final invalid = const TerminalSessionConfigV1(
        sessionId: 'runtime-1',
        displayName: 'shell',
        config: TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: ''),
        ),
      ).toJson();
      expect(
        () => TerminalSessionConfigV1.fromJson(invalid),
        throwsA(
          isA<TerminalSessionConfigContractException>().having(
            (error) => error.code,
            'code',
            'invalid_launch_program',
          ),
        ),
      );
    });

    test('missing connection is legacy local only and cannot encode SSH', () {
      final legacyLocal = TerminalSessionConfigV1(
        sessionId: 'legacy-local',
        displayName: 'Legacy local',
        config: _config(),
      ).toJson();
      final localConfig = legacyLocal['config']! as Map<String, Object?>;
      localConfig.remove('connection');

      final decoded = TerminalSessionConfigV1.fromJson(legacyLocal);
      expect(decoded.config.connection.type, TerminalConnectionType.local);
      expect(decoded.config.connection.isSsh, isFalse);
      expect(decoded.config.launch.program, '/bin/zsh');

      final sshShaped = _validSshWireJson();
      final sshConfig = sshShaped['config']! as Map<String, Object?>;
      sshConfig.remove('connection');
      expect(
        () => TerminalSessionConfigV1.fromJson(sshShaped),
        throwsA(
          isA<TerminalSessionConfigContractException>()
              .having((error) => error.code, 'code', 'invalid_launch_program')
              .having(
                (error) => error.path,
                'path',
                r'$.config.launch.program',
              ),
        ),
      );
    });

    test('round-trips SSH connection fields and permits no local program', () {
      const wire = TerminalSessionConfigV1(
        sessionId: 'ssh-runtime-1',
        displayName: 'Production',
        config: TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: ''),
          connection: TerminalConnectionConfig.ssh(
            host: 'ssh.example.test',
            user: 'operator',
            port: 2222,
            auth: TerminalSshAuthMethod.password,
            password: 'transient-secret',
            privateKeys: <String>['/keys/target_ed25519'],
            hostKeyPolicy: TerminalSshHostKeyPolicy.acceptNew,
            connectTimeoutSeconds: 12,
            keepaliveSeconds: 30,
            proxyJump: 'jump-a,jump-b:2222',
            proxyJumpProfiles: <TerminalSshJumpConfig>[
              TerminalSshJumpConfig(
                host: 'jump-a.internal',
                user: 'jump-user',
                port: 2201,
                auth: TerminalSshAuthMethod.publicKey,
                privateKeys: <String>['/keys/jump_a_ed25519'],
                hostKeyPolicy: TerminalSshHostKeyPolicy.strict,
                knownHostsFile: '/known/jump_a_hosts',
                connectTimeoutSeconds: 11,
                keepaliveSeconds: 21,
                keepaliveCountMax: 5,
              ),
              TerminalSshJumpConfig(
                host: 'jump-b.internal',
                user: 'jump-b-user',
                port: 2222,
                auth: TerminalSshAuthMethod.auto,
                privateKeys: <String>['/keys/jump_b_ed25519'],
                hostKeyPolicy: TerminalSshHostKeyPolicy.acceptNew,
                connectTimeoutSeconds: 12,
                keepaliveSeconds: 22,
                keepaliveCountMax: 6,
              ),
            ],
            portForwards: <TerminalSshPortForwardConfig>[
              TerminalSshPortForwardConfig(
                type: TerminalSshPortForwardType.local,
                bindHost: '127.0.0.1',
                bindPort: 8080,
                targetHost: 'app.internal',
                targetPort: 80,
              ),
              TerminalSshPortForwardConfig(
                type: TerminalSshPortForwardType.dynamic,
                bindHost: '127.0.0.1',
                bindPort: 1080,
              ),
            ],
            agentForwarding: true,
            agentSocket: '/tmp/ssh-agent.sock',
            x11Forwarding: true,
            x11TargetHost: '127.0.0.1',
            x11TargetPort: 6000,
            x11AuthCookie: '00112233445566778899aabbccddeeff',
          ),
        ),
      );

      final decoded = TerminalSessionConfigV1.fromJsonString(
        wire.toJsonString(),
      );

      expect(decoded.config.connection.isSsh, isTrue);
      expect(decoded.config.connection.host, 'ssh.example.test');
      expect(decoded.config.connection.user, 'operator');
      expect(decoded.config.connection.port, 2222);
      expect(decoded.config.connection.auth, TerminalSshAuthMethod.password);
      expect(decoded.config.connection.password, 'transient-secret');
      expect(decoded.config.connection.privateKeys, const <String>[
        '/keys/target_ed25519',
      ]);
      expect(
        decoded.config.connection.hostKeyPolicy,
        TerminalSshHostKeyPolicy.acceptNew,
      );
      expect(decoded.config.connection.proxyJump, 'jump-a,jump-b:2222');
      expect(decoded.config.connection.proxyJumpProfiles, hasLength(2));
      expect(
        decoded.config.connection.proxyJumpProfiles.first.privateKeys,
        const <String>['/keys/jump_a_ed25519'],
      );
      expect(
        decoded.config.connection.proxyJumpProfiles.last.privateKeys,
        const <String>['/keys/jump_b_ed25519'],
      );
      expect(
        decoded.config.connection.proxyJumpProfiles.first.privateKeys,
        isNot(decoded.config.connection.privateKeys),
      );
      expect(decoded.config.connection.portForwards, hasLength(2));
      expect(
        decoded.config.connection.portForwards.last.type,
        TerminalSshPortForwardType.dynamic,
      );
      expect(decoded.config.connection.agentForwarding, isTrue);
      expect(decoded.config.connection.agentSocket, '/tmp/ssh-agent.sock');
      expect(decoded.config.connection.x11Forwarding, isTrue);
      expect(decoded.config.connection.x11TargetPort, 6000);
      expect(
        decoded.config.connection.x11AuthCookie,
        '00112233445566778899aabbccddeeff',
      );
    });

    test('rejects invalid raw SSH values before model normalization', () {
      for (final invalid in <({String field, Object? value, String code})>[
        (field: 'port', value: 0, code: 'invalid_integer'),
        (field: 'port', value: 65536, code: 'invalid_integer'),
        (field: 'port', value: '22', code: 'invalid_integer'),
        (field: 'auth', value: 'publickey', code: 'invalid_enum'),
        (field: 'hostKeyPolicy', value: 'accept-new', code: 'invalid_enum'),
        (field: 'agentForwarding', value: 1, code: 'invalid_type'),
        (field: 'connectTimeoutSeconds', value: 0, code: 'invalid_integer'),
      ]) {
        final json = _validSshWireJson();
        final connection =
            (json['config']! as Map<String, Object?>)['connection']!
                as Map<String, Object?>;
        connection[invalid.field] = invalid.value;

        expect(
          () => TerminalSessionConfigV1.fromJson(json),
          throwsA(
            isA<TerminalSessionConfigContractException>()
                .having((error) => error.code, 'code', invalid.code)
                .having(
                  (error) => error.path,
                  'path',
                  r'$.config.connection.' + invalid.field,
                ),
          ),
          reason: invalid.field,
        );
      }
    });

    test('rejects malformed raw SSH collections and forwarding enums', () {
      final wrongKeys = _validSshWireJson();
      final wrongKeysConnection =
          (wrongKeys['config']! as Map<String, Object?>)['connection']!
              as Map<String, Object?>;
      wrongKeysConnection['privateKeys'] = <Object?>['key', 7];
      expect(
        () => TerminalSessionConfigV1.fromJson(wrongKeys),
        throwsA(
          isA<TerminalSessionConfigContractException>()
              .having((error) => error.code, 'code', 'invalid_collection')
              .having(
                (error) => error.path,
                'path',
                r'$.config.connection.privateKeys',
              ),
        ),
      );

      final wrongForward = _validSshWireJson();
      final wrongForwardConnection =
          (wrongForward['config']! as Map<String, Object?>)['connection']!
              as Map<String, Object?>;
      wrongForwardConnection['portForwards'] = <Object?>[
        <String, Object?>{
          'type': 'forward',
          'bindHost': '127.0.0.1',
          'bindPort': 8080,
          'targetHost': 'internal',
          'targetPort': 80,
        },
      ];
      expect(
        () => TerminalSessionConfigV1.fromJson(wrongForward),
        throwsA(
          isA<TerminalSessionConfigContractException>()
              .having((error) => error.code, 'code', 'invalid_enum')
              .having(
                (error) => error.path,
                'path',
                r'$.config.connection.portForwards[0].type',
              ),
        ),
      );
    });

    test('rejects invalid raw ProxyJump profile enums, ports, and lists', () {
      for (final invalid
          in <({String field, Object? value, String code, String path})>[
            (
              field: 'auth',
              value: 'publickey',
              code: 'invalid_enum',
              path: r'$.config.connection.proxyJumpProfiles[0].auth',
            ),
            (
              field: 'port',
              value: 65536,
              code: 'invalid_integer',
              path: r'$.config.connection.proxyJumpProfiles[0].port',
            ),
            (
              field: 'privateKeys',
              value: <Object?>['/keys/jump', 7],
              code: 'invalid_collection',
              path: r'$.config.connection.proxyJumpProfiles[0].privateKeys',
            ),
          ]) {
        final json = _validSshWireJson();
        final connection =
            (json['config']! as Map<String, Object?>)['connection']!
                as Map<String, Object?>;
        final jump = const TerminalSshJumpConfig(
          host: 'jump.internal',
          user: 'jump-user',
          port: 22,
        ).toJson();
        jump[invalid.field] = invalid.value;
        connection['proxyJump'] = 'jump-user@jump.internal';
        connection['proxyJumpProfiles'] = <Object?>[jump];

        expect(
          () => TerminalSessionConfigV1.fromJson(json),
          throwsA(
            isA<TerminalSessionConfigContractException>()
                .having((error) => error.code, 'code', invalid.code)
                .having((error) => error.path, 'path', invalid.path),
          ),
          reason: invalid.field,
        );
      }

      final wrongList = _validSshWireJson();
      final wrongListConnection =
          (wrongList['config']! as Map<String, Object?>)['connection']!
              as Map<String, Object?>;
      wrongListConnection['proxyJumpProfiles'] = 'not-a-list';
      expect(
        () => TerminalSessionConfigV1.fromJson(wrongList),
        throwsA(
          isA<TerminalSessionConfigContractException>()
              .having((error) => error.code, 'code', 'invalid_collection')
              .having(
                (error) => error.path,
                'path',
                r'$.config.connection.proxyJumpProfiles',
              ),
        ),
      );
    });

    test('requires a real MIT-MAGIC-COOKIE when X11 is enabled', () {
      for (final invalid in <({Object? cookie, String code})>[
        (cookie: null, code: 'missing_field'),
        (cookie: 'not-hex', code: 'invalid_string'),
        (cookie: '00' * 15, code: 'invalid_string'),
      ]) {
        final json = _validSshWireJson();
        final connection =
            (json['config']! as Map<String, Object?>)['connection']!
                as Map<String, Object?>;
        connection['x11Forwarding'] = true;
        if (invalid.cookie == null) {
          connection.remove('x11AuthCookie');
        } else {
          connection['x11AuthCookie'] = invalid.cookie;
        }
        expect(
          () => TerminalSessionConfigV1.fromJson(json),
          throwsA(
            isA<TerminalSessionConfigContractException>()
                .having((error) => error.code, 'code', invalid.code)
                .having(
                  (error) => error.path,
                  'path',
                  r'$.config.connection.x11AuthCookie',
                ),
          ),
        );
      }

      final wrongProtocol = _validSshWireJson();
      final connection =
          (wrongProtocol['config']! as Map<String, Object?>)['connection']!
              as Map<String, Object?>;
      connection['x11Forwarding'] = true;
      connection['x11AuthProtocol'] = 'XDM-AUTHORIZATION-1';
      connection['x11AuthCookie'] = '00112233445566778899aabbccddeeff';
      expect(
        () => TerminalSessionConfigV1.fromJson(wrongProtocol),
        throwsA(
          isA<TerminalSessionConfigContractException>()
              .having((error) => error.code, 'code', 'invalid_ssh_connection')
              .having(
                (error) => error.path,
                'path',
                r'$.config.connection.x11AuthProtocol',
              ),
        ),
      );
    });
  });

  group('TerminalRuntimeController SessionConfig v1 routing', () {
    test('prefers v1 and never calls the Profile-shaped fallback', () {
      final backend = _SessionConfigBackend(supportsV1: true);
      final runtime = _runtime(backend);
      addTearDown(runtime.dispose);

      runtime.createSession(_config());

      expect(backend.v1CreateCalls, 1);
      expect(backend.legacyCreateCalls, 0);
      final payload = jsonDecode(backend.lastV1Json!) as Map<String, dynamic>;
      expect(payload['schema_version'], 1);
      expect(payload['contract'], 'ianvs-session-config-v1');
      expect(payload['session_id'], 'runtime-1');
      expect(payload['display_name'], 'zsh');
      expect(payload['client_capabilities'], <String, Object?>{'zmodem': true});
      expect(payload, isNot(contains('id')));
      expect(payload, isNot(contains('name')));
    });

    test('uses the exact legacy Profile wire when v1 is unavailable', () {
      final backend = _SessionConfigBackend(supportsV1: false);
      final runtime = _runtime(backend);
      addTearDown(runtime.dispose);

      runtime.createSession(_config());

      expect(backend.v1CreateCalls, 0);
      expect(backend.legacyCreateCalls, 1);
      final payload =
          jsonDecode(backend.lastLegacyJson!) as Map<String, dynamic>;
      expect(payload['id'], 'runtime-1');
      expect(payload['name'], 'zsh');
      expect(payload['launch'], isA<Map<String, dynamic>>());
      expect(payload, isNot(contains('schema_version')));
    });

    test('round-trips an explicit ZMODEM client capability', () {
      final wire = TerminalSessionConfigV1(
        sessionId: 'runtime-7',
        displayName: 'zsh',
        config: _config(),
        zmodemEnabled: true,
      );

      final decoded = TerminalSessionConfigV1.fromJsonString(
        wire.toJsonString(),
      );

      expect(decoded.zmodemEnabled, isTrue);
      expect(decoded.toJson()['client_capabilities'], <String, Object?>{
        'zmodem': true,
      });
    });

    test('requires an advertised native SSH capability', () {
      final backend = _SessionConfigBackend(supportsV1: true);
      final runtime = _runtime(backend);
      addTearDown(runtime.dispose);

      expect(
        () => runtime.createSession(_sshConfig()),
        throwsA(isA<UnsupportedError>()),
      );
      expect(backend.v1CreateCalls, 0);
    });

    test('routes SSH only through a capable SessionConfig v1 backend', () {
      final backend = _SessionConfigBackend(
        supportsV1: true,
        supportsSsh: true,
      );
      final runtime = _runtime(backend);
      addTearDown(runtime.dispose);

      runtime.createSession(_sshConfig());

      expect(backend.v1CreateCalls, 1);
      expect(backend.legacyCreateCalls, 0);
    });
  });
}

TerminalSessionConfig _config() {
  return const TerminalSessionConfig(
    launch: TerminalLaunchConfig(
      program: '/bin/zsh',
      args: <String>['-l'],
      env: <String, String>{'LANG': 'C.UTF-8'},
      cwd: '/tmp',
    ),
    scrollbackLines: 1234,
    dragDropEnabled: true,
    display: TerminalDisplayConfig(font: TerminalFontConfig(family: 'Menlo')),
    interaction: TerminalInteractionConfig(copyOnSelect: true),
  );
}

TerminalSessionConfig _sshConfig() {
  return const TerminalSessionConfig(
    launch: TerminalLaunchConfig(program: ''),
    connection: TerminalConnectionConfig.ssh(
      host: 'ssh.example.test',
      user: 'operator',
    ),
  );
}

Map<String, Object?> _validSshWireJson() {
  return TerminalSessionConfigV1(
    sessionId: 'ssh-validation',
    displayName: 'SSH validation',
    config: _sshConfig(),
  ).toJson();
}

TerminalRuntimeController _runtime(PtySessionBackend backend) {
  return TerminalRuntimeController(
    backend: backend,
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: false,
  );
}

final class _SessionConfigBackend
    implements
        PtySessionBackend,
        PtySessionConfigV1Backend,
        PtyRuntimeCapabilityBackend {
  _SessionConfigBackend({required this.supportsV1, bool supportsSsh = false})
    : runtimeCapabilities = supportsSsh
          ? PtyRuntimeCapabilities.fromJson(<String, Object?>{
              'schema_version': 1,
              'runtime_contract': 'ianvs-runtime-contract-v1',
              'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
              'recording_schema_versions': <Object?>[1],
              'features': <Object?>['session-config.json.v1', 'ssh-session.v1'],
            })
          : null;

  final bool supportsV1;
  int v1CreateCalls = 0;
  int legacyCreateCalls = 0;
  String? lastV1Json;
  String? lastLegacyJson;

  @override
  final PtyRuntimeCapabilities? runtimeCapabilities;

  @override
  bool get supportsSessionConfigV1 => supportsV1;

  @override
  String createSessionV1(String sessionConfigV1Json) {
    v1CreateCalls += 1;
    lastV1Json = sessionConfigV1Json;
    return '1';
  }

  @override
  String createSession(String sessionConfigJson) {
    legacyCreateCalls += 1;
    lastLegacyJson = sessionConfigJson;
    return '1';
  }

  @override
  int ping() => 42;

  @override
  void closeSession(String sessionId) {}

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? takeFrameDiffJson(String sessionId) => null;

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}
