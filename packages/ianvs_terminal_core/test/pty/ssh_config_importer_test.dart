import 'dart:convert';

import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';
import 'package:test/test.dart';

void main() {
  test('decodes OpenSSH forwards, agent, and X11 settings', () {
    final document = ImportedSshProfilesDocument.fromJsonString('''
{
  "schemaVersion": 1,
  "contract": "ianvs-openssh-profiles-v1",
  "sourcePath": "/tmp/.ssh/config",
  "sourceMtimeMicros": 7,
  "profiles": [{
    "id": "work",
    "name": "Work",
    "group": "Imported",
    "source": "openssh_config",
    "alias": "work",
    "host": "work.example.test",
    "user": "operator",
    "port": 22,
    "auth": "auto",
    "privateKeys": [],
    "hostKeyPolicy": "strict",
    "connectTimeoutSeconds": 10,
    "keepaliveSeconds": 0,
    "keepaliveCountMax": 3,
    "proxyJump": "jump-user@jump-alias:2222",
    "proxyJumpProfiles": [{
      "host": "jump.example.test",
      "user": "jump-user",
      "port": 2222,
      "auth": "public_key",
      "privateKeys": ["/keys/jump_ed25519"],
      "hostKeyPolicy": "accept_new",
      "knownHostsFile": "/known/jump_hosts",
      "connectTimeoutSeconds": 12,
      "keepaliveSeconds": 20,
      "keepaliveCountMax": 4
    }],
    "portForwards": [
      {"type":"local","bindHost":"127.0.0.1","bindPort":8080,"targetHost":"app","targetPort":80},
      {"type":"dynamic","bindHost":"127.0.0.1","bindPort":1080,"targetHost":"","targetPort":0}
    ],
    "agentForwarding": true,
    "x11Forwarding": true
  }],
  "warnings": []
}
''');

    final profile = document.profiles.single;
    expect(profile.portForwards, hasLength(2));
    expect(profile.portForwards.first.type, ImportedSshPortForwardType.local);
    expect(profile.portForwards.last.type, ImportedSshPortForwardType.dynamic);
    expect(profile.portForwards.last.targetPort, 0);
    expect(profile.agentForwarding, isTrue);
    expect(profile.x11Forwarding, isTrue);
    expect(profile.proxyJumpProfiles, hasLength(1));
    expect(profile.proxyJumpProfiles.single.host, 'jump.example.test');
    expect(profile.proxyJumpProfiles.single.user, 'jump-user');
    expect(profile.proxyJumpProfiles.single.port, 2222);
    expect(profile.proxyJumpProfiles.single.auth, 'public_key');
    expect(profile.proxyJumpProfiles.single.privateKeys, <String>[
      '/keys/jump_ed25519',
    ]);
    expect(profile.proxyJumpProfiles.single.hostKeyPolicy, 'accept_new');
    expect(
      profile.proxyJumpProfiles.single.knownHostsFile,
      '/known/jump_hosts',
    );
  });

  test('strictly rejects invalid imported ProxyJump fields', () {
    for (final mutation in <void Function(Map<String, Object?>)>[
      (jump) => jump['auth'] = 'publickey',
      (jump) => jump['port'] = 65536,
      (jump) => jump['privateKeys'] = <Object?>['/keys/jump', 7],
    ]) {
      final document = _validImportedDocument();
      final profile = (document['profiles']! as List).single as Map;
      final jump = (profile['proxyJumpProfiles']! as List).single as Map;
      final mutableJump = Map<String, Object?>.from(jump);
      mutation(mutableJump);
      profile['proxyJumpProfiles'] = <Object?>[mutableJump];

      expect(
        () => ImportedSshProfilesDocument.fromJsonString(jsonEncode(document)),
        throwsFormatException,
      );
    }
  });

  test('bounds the imported ProxyJump profile list', () {
    final document = _validImportedDocument();
    final profile = (document['profiles']! as List).single as Map;
    final jump = (profile['proxyJumpProfiles']! as List).single as Map;
    profile['proxyJumpProfiles'] = <Object?>[
      for (var index = 0; index < 129; index += 1)
        Map<String, Object?>.from(jump),
    ];

    expect(
      () => ImportedSshProfilesDocument.fromJsonString(jsonEncode(document)),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _validImportedDocument() {
  return <String, Object?>{
    'schemaVersion': 1,
    'contract': 'ianvs-openssh-profiles-v1',
    'sourcePath': '/tmp/.ssh/config',
    'sourceMtimeMicros': 7,
    'profiles': <Object?>[
      <String, Object?>{
        'id': 'work',
        'name': 'Work',
        'group': 'Imported',
        'source': 'openssh_config',
        'alias': 'work',
        'host': 'target.example.test',
        'user': 'target-user',
        'port': 22,
        'auth': 'auto',
        'privateKeys': <Object?>['/keys/target_ed25519'],
        'hostKeyPolicy': 'strict',
        'connectTimeoutSeconds': 10,
        'keepaliveSeconds': 0,
        'keepaliveCountMax': 3,
        'proxyJump': 'jump-user@jump-alias:2222',
        'proxyJumpProfiles': <Object?>[
          <String, Object?>{
            'host': 'jump.example.test',
            'user': 'jump-user',
            'port': 2222,
            'auth': 'public_key',
            'privateKeys': <Object?>['/keys/jump_ed25519'],
            'hostKeyPolicy': 'accept_new',
            'knownHostsFile': '/known/jump_hosts',
            'connectTimeoutSeconds': 12,
            'keepaliveSeconds': 20,
            'keepaliveCountMax': 4,
          },
        ],
        'portForwards': <Object?>[],
        'agentForwarding': false,
        'x11Forwarding': false,
      },
    ],
    'warnings': <Object?>[],
  };
}
