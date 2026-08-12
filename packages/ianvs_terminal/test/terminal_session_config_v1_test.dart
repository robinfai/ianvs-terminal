import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  group('TerminalSessionConfigV1', () {
    test('round-trips the declared exact current config', () {
      final wire = TerminalSessionConfigV1(
        sessionId: 'runtime-7',
        displayName: 'zsh',
        config: _config(),
      );
      final decoded = TerminalSessionConfigV1.fromJsonString(
        jsonEncode(wire.toJson()),
      );

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

    test('rejects unknown and case-alias fields at every boundary', () {
      for (final mutation in <void Function(Map<String, Object?>)>{
        (json) => json['future_top_level'] = true,
        (json) => json['Contract'] = json.remove('contract'),
        (json) =>
            (json['client_capabilities']! as Map<String, Object?>)['Zmodem'] =
                true,
        (json) =>
            (json['config']! as Map<String, Object?>)['shell'] = '/bin/zsh',
        (json) =>
            ((json['config']! as Map<String, Object?>)['launch']!
                    as Map<String, Object?>)['Program'] =
                '/bin/zsh',
      }) {
        final json = TerminalSessionConfigV1(
          sessionId: 'runtime-7',
          displayName: 'zsh',
          config: _config(),
        ).toJson();
        mutation(json);
        expect(
          () => TerminalSessionConfigV1.fromJson(json),
          throwsA(
            isA<TerminalSessionConfigContractException>().having(
              (error) => error.code,
              'code',
              'unknown_field',
            ),
          ),
        );
      }
    });

    test('enforces the shared complete exact-shape corpus', () {
      final corpus = _sessionConfigShapeCorpus();
      final validLocal = _object(corpus['valid_local']);
      final validSsh = _object(corpus['valid_ssh']);
      expect(
        TerminalSessionConfigV1.fromJson(_deepCopy(validLocal)).sessionId,
        'shape-local',
      );
      expect(
        TerminalSessionConfigV1.fromJson(_deepCopy(validSsh)).sessionId,
        'shape-ssh',
      );

      final paths = (corpus['closed_object_paths']! as List<Object?>)
          .cast<String>();
      for (final path in paths) {
        final sourceObject = _objectAt(validSsh, path);
        for (final key in sourceObject.keys.toList(growable: false)) {
          final missing = _deepCopy(validSsh);
          _objectAt(missing, path).remove(key);
          expect(
            () => TerminalSessionConfigV1.fromJson(missing),
            throwsA(isA<TerminalSessionConfigContractException>()),
            reason: 'missing $path/$key',
          );

          final caseAlias = _deepCopy(validSsh);
          final caseObject = _objectAt(caseAlias, path);
          final value = caseObject.remove(key);
          caseObject[_caseAlias(key)] = value;
          expect(
            () => TerminalSessionConfigV1.fromJson(caseAlias),
            throwsA(isA<TerminalSessionConfigContractException>()),
            reason: 'case alias $path/$key',
          );
        }

        final unknown = _deepCopy(validSsh);
        _objectAt(unknown, path)['future_field'] = true;
        expect(
          () => TerminalSessionConfigV1.fromJson(unknown),
          throwsA(isA<TerminalSessionConfigContractException>()),
          reason: 'unknown field at $path',
        );
      }

      for (final mutation in <void Function(Map<String, Object?>)>[
        (connection) => connection.remove('type'),
        (connection) => connection['Type'] = connection.remove('type'),
        (connection) => connection['future_field'] = true,
      ]) {
        final invalidLocal = _deepCopy(validLocal);
        mutation(_objectAt(invalidLocal, '/config/connection'));
        expect(
          () => TerminalSessionConfigV1.fromJson(invalidLocal),
          throwsA(isA<TerminalSessionConfigContractException>()),
        );
      }
    });

    test(
      'rejects every shared invalid-value mutation without normalization',
      () {
        final corpus = _sessionConfigShapeCorpus();
        final groups = (corpus['value_mutation_groups']! as List<Object?>)
            .cast<Map<Object?, Object?>>();
        for (final rawGroup in groups) {
          final group = rawGroup.cast<String, Object?>();
          final id = group['id']! as String;
          final base = group['base']! as String;
          final paths = (group['paths']! as List<Object?>).cast<String>();
          final invalidValues = group['invalid_values']! as List<Object?>;
          for (final path in paths) {
            for (var index = 0; index < invalidValues.length; index += 1) {
              final invalid = _deepCopy(_object(corpus[base]));
              final current = _valueAt(invalid, path);
              _setAt(
                invalid,
                path,
                _materializeMutation(invalidValues[index], current: current),
              );
              expect(
                () => TerminalSessionConfigV1.fromJson(invalid),
                throwsA(isA<TerminalSessionConfigContractException>()),
                reason: '$id $path mutation $index',
              );
            }
          }
        }
      },
    );

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

    test('missing connection is rejected by the current schema', () {
      final local = TerminalSessionConfigV1(
        sessionId: 'current-local',
        displayName: 'Current local',
        config: _config(),
      ).toJson();
      final localConfig = local['config']! as Map<String, Object?>;
      localConfig.remove('connection');
      expect(
        () => TerminalSessionConfigV1.fromJson(local),
        throwsA(
          isA<TerminalSessionConfigContractException>()
              .having((error) => error.code, 'code', 'missing_field')
              .having((error) => error.path, 'path', r'$.config.connection'),
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
        jump.addAll(<String, Object?>{
          'password': null,
          'privateKeyPassphrase': null,
          'knownHostsFile': null,
        });
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
    test('uses the exact current SessionConfig v1 boundary', () {
      final backend = _SessionConfigBackend();
      final runtime = _runtime(backend);
      addTearDown(runtime.dispose);

      runtime.createSession(_config());

      expect(backend.v1CreateCalls, 1);
      final payload = jsonDecode(backend.lastV1Json!) as Map<String, dynamic>;
      expect(payload['schema_version'], 1);
      expect(payload['contract'], 'ianvs-session-config-v1');
      expect(payload['session_id'], 'runtime-1');
      expect(payload['display_name'], 'zsh');
      expect(payload['client_capabilities'], <String, Object?>{'zmodem': true});
      expect(payload, isNot(contains('id')));
      expect(payload, isNot(contains('name')));
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
      final backend = _SessionConfigBackend();
      final runtime = _runtime(backend);
      addTearDown(runtime.dispose);

      expect(
        () => runtime.createSession(_sshConfig()),
        throwsA(isA<UnsupportedError>()),
      );
      expect(backend.v1CreateCalls, 0);
    });

    test('routes SSH only through a capable SessionConfig v1 backend', () {
      final backend = _SessionConfigBackend(supportsSsh: true);
      final runtime = _runtime(backend);
      addTearDown(runtime.dispose);

      runtime.createSession(_sshConfig());

      expect(backend.v1CreateCalls, 1);
    });
  });
}

Map<String, Object?> _sessionConfigShapeCorpus() {
  var directory = Directory.current.absolute;
  while (true) {
    final file = File(
      '${directory.path}/native/core/tests/fixtures/session_config/'
      'session_config_v1_shape_corpus.json',
    );
    if (file.existsSync()) {
      return _object(jsonDecode(file.readAsStringSync()));
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('repository root not found from ${Directory.current}');
    }
    directory = parent;
  }
}

Map<String, Object?> _object(Object? value) {
  return (value! as Map<Object?, Object?>).cast<String, Object?>();
}

Map<String, Object?> _deepCopy(Map<String, Object?> value) {
  return _object(jsonDecode(jsonEncode(value)));
}

Map<String, Object?> _objectAt(Map<String, Object?> root, String pointer) {
  return _object(_valueAt(root, pointer));
}

Object? _valueAt(Object? root, String pointer) {
  Object? value = root;
  if (pointer.isNotEmpty) {
    for (final segment in pointer.substring(1).split('/')) {
      value = switch (value) {
        final Map<Object?, Object?> map => map[segment],
        final List<Object?> list => list[int.parse(segment)],
        _ => throw StateError('invalid corpus pointer $pointer'),
      };
    }
  }
  return value;
}

void _setAt(Map<String, Object?> root, String pointer, Object? replacement) {
  final segments = pointer.substring(1).split('/');
  Object? parent = root;
  for (final segment in segments.take(segments.length - 1)) {
    parent = switch (parent) {
      final Map<Object?, Object?> map => map[segment],
      final List<Object?> list => list[int.parse(segment)],
      _ => throw StateError('invalid corpus pointer $pointer'),
    };
  }
  final last = segments.last;
  switch (parent) {
    case final Map<Object?, Object?> map:
      map[last] = replacement;
    case final List<Object?> list:
      list[int.parse(last)] = replacement;
    default:
      throw StateError('invalid corpus pointer $pointer');
  }
}

Object? _materializeMutation(Object? specification, {Object? current}) {
  if (specification is List<Object?>) {
    return specification.map(_materializeMutation).toList(growable: false);
  }
  if (specification is! Map<Object?, Object?>) {
    return specification;
  }
  final object = specification.cast<String, Object?>();
  final operation = object['op'];
  if (operation == null) {
    return <String, Object?>{
      for (final entry in object.entries)
        entry.key: _materializeMutation(entry.value),
    };
  }
  final count = object['count']! as int;
  return switch (operation) {
    'repeat_string' => (object['value']! as String) * count,
    'repeat_array' => List<Object?>.generate(
      count,
      (_) => _materializeMutation(object['value']),
      growable: false,
    ),
    'repeat_current_array_item' => List<Object?>.generate(
      count,
      (_) => _deepCopyValue((current! as List<Object?>).first),
      growable: false,
    ),
    'oversized_string_map' => <String, Object?>{
      for (var index = 0; index < count; index += 1) 'KEY_$index': 'value',
    },
    _ => throw StateError('unknown corpus mutation operation $operation'),
  };
}

Object? _deepCopyValue(Object? value) => jsonDecode(jsonEncode(value));

String _caseAlias(String key) {
  final first = key[0];
  final alias = first.toUpperCase() + key.substring(1);
  return alias == key ? first.toLowerCase() + key.substring(1) : alias;
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
        PtySessionFramePacketV1Backend,
        PtyRuntimeCapabilityBackend {
  _SessionConfigBackend({bool supportsSsh = false})
    : runtimeCapabilities = supportsSsh
          ? PtyRuntimeCapabilities.fromJson(<String, Object?>{
              'schema_version': 1,
              'runtime_contract': 'ianvs-runtime-contract-v1',
              'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
              'recording_schema_versions': <Object?>[1],
              'features': <Object?>['session-config.json.v1', 'ssh-session.v1'],
            })
          : null;

  int v1CreateCalls = 0;
  String? lastV1Json;

  @override
  final PtyRuntimeCapabilities? runtimeCapabilities;

  @override
  String createSessionV1(String sessionConfigV1Json) {
    v1CreateCalls += 1;
    lastV1Json = sessionConfigV1Json;
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
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) => null;

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}
