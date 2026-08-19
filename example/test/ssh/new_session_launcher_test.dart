import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/ssh/new_session_launcher.dart';
import 'package:app/features/ssh/ssh_profile_import_service.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart' as pty;

const _testPrivateKey =
    '-----BEGIN OPENSSH PRIVATE KEY-----\n'
    'b3BlbnNzaC1rZXktdjEAAAAA\n'
    '-----END OPENSSH PRIVATE KEY-----';
const _testJumpPrivateKey =
    '-----BEGIN OPENSSH PRIVATE KEY-----\n'
    'b3BlbnNzaC1rZXktdjEAAAAB\n'
    '-----END OPENSSH PRIVATE KEY-----';

String _materializeTestPrivateKey(String path) =>
    path.contains('jump') ? _testJumpPrivateKey : _testPrivateKey;

void main() {
  test('parses and formats local, remote, dynamic, and IPv6 forwards', () {
    const source =
        'L 127.0.0.1:8080 app.internal:80\n'
        'R [::1]:9000 127.0.0.1:9001\n'
        'D 127.0.0.1:1080';

    final forwards = parseSshPortForwards(source);

    expect(forwards, hasLength(3));
    expect(forwards[0].type, terminal.TerminalSshPortForwardType.local);
    expect(forwards[1].type, terminal.TerminalSshPortForwardType.remote);
    expect(forwards[1].bindHost, '::1');
    expect(forwards[2].type, terminal.TerminalSshPortForwardType.dynamic);
    expect(forwards[2].targetPort, 0);
    expect(parseSshPortForwards(formatSshPortForwards(forwards)), hasLength(3));
    expect(() => parseSshPortForwards('D localhost:0'), throwsFormatException);
  });

  test('parses independent ProxyJump profiles with actionable IPv6 errors', () {
    final jumps = parseSshProxyJumpProfiles(
      'jump-user@jump.example.test:2222,ipv6-user@[2001:db8::1]:2200',
    );

    expect(jumps, hasLength(2));
    expect(jumps.first.host, 'jump.example.test');
    expect(jumps.first.user, 'jump-user');
    expect(jumps.first.port, 2222);
    expect(jumps.first.auth, terminal.TerminalSshAuthMethod.auto);
    expect(
      jumps.first.hostKeyPolicy,
      terminal.TerminalSshHostKeyPolicy.acceptNew,
    );
    expect(jumps.first.password, isNull);
    expect(jumps.first.privateKeys, isEmpty);
    expect(jumps.last.host, '2001:db8::1');
    expect(jumps.last.port, 2200);
    expect(
      () => parseSshProxyJumpProfiles('jump-user@2001:db8::1'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('wrap IPv6 addresses in brackets'),
        ),
      ),
    );
  });

  testWidgets('chooses between local, saved SSH, and OpenSSH profiles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final saved = _sshProfile('saved', 'Saved host', 'saved.example.test');
    final imported = terminalProfileFromImportedSshConfig(
      const pty.ImportedSshProfile(
        id: 'imported',
        name: 'Imported host',
        group: 'Imported',
        source: 'openssh_config',
        alias: 'imported',
        host: 'imported.example.test',
        user: 'target-user',
        port: 22,
        auth: 'auto',
        privateKeys: <String>['/keys/target_ed25519'],
        hostKeyPolicy: 'strict',
        connectTimeoutSeconds: 10,
        keepaliveSeconds: 0,
        keepaliveCountMax: 3,
        proxyJump: 'jump-user@jump-alias:2222',
        proxyJumpProfiles: <pty.ImportedSshJumpProfile>[
          pty.ImportedSshJumpProfile(
            host: 'jump.example.test',
            user: 'jump-user',
            port: 2222,
            auth: 'public_key',
            privateKeys: <String>['/keys/jump_ed25519'],
            hostKeyPolicy: 'accept_new',
            knownHostsFile: '/known/jump_hosts',
            connectTimeoutSeconds: 12,
            keepaliveSeconds: 20,
            keepaliveCountMax: 4,
          ),
        ],
      ),
      privateKeyLoader: _materializeTestPrivateKey,
    );
    NewSessionSelection? result;

    await _pumpLauncher(
      tester,
      profiles: [defaultTerminalProfile(), saved],
      imported: SshProfileImportSnapshot(
        profiles: [imported],
        sourcePath: '/tmp/ssh/config',
      ),
      onClosed: (value) => result = value,
    );

    expect(find.byKey(const Key('new-local-session-default')), findsOneWidget);
    await tester.tap(find.text('SSH session'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-ssh-session-saved')), findsOneWidget);
    expect(find.byKey(const Key('new-ssh-session-imported')), findsOneWidget);
    expect(
      find.byKey(const Key('new-ssh-session-saved-actions')),
      findsNothing,
    );
    expect(find.byTooltip('More actions for Imported host'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ssh-profile-search')),
      'imported.example',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-ssh-session-saved')), findsNothing);
    expect(find.byKey(const Key('new-ssh-session-imported')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-ssh-session-imported')));
    await tester.pumpAndSettle();
    expect(result?.profile.id, 'imported');
    expect(result?.saveProfile, isFalse);
    expect(result?.openSession, isTrue);
    final wire = terminal.TerminalSessionConfigV1(
      sessionId: 'imported-two-leg-session',
      displayName: result!.profile.name,
      config: result!.profile.toSessionConfig(),
    );
    final encoded = wire.toJsonString();
    final decoded = terminal.TerminalSessionConfigV1.fromJsonString(encoded);
    expect(decoded.config.connection.host, 'imported.example.test');
    expect(decoded.config.connection.privateKeys, <String>[_testPrivateKey]);
    expect(decoded.config.connection.proxyJump, 'jump-user@jump-alias:2222');
    expect(decoded.config.connection.proxyJumpProfiles, hasLength(1));
    expect(
      decoded.config.connection.proxyJumpProfiles.single.host,
      'jump.example.test',
    );
    expect(
      decoded.config.connection.proxyJumpProfiles.single.privateKeys,
      <String>[_testJumpPrivateKey],
    );
    expect(
      decoded.config.connection.proxyJumpProfiles.single.privateKeys,
      isNot(decoded.config.connection.privateKeys),
    );
  });

  testWidgets('OpenSSH actions connect or import without connecting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final imported = _sshProfile(
      'import-actions',
      'Import actions',
      'import-actions.example.test',
    );
    NewSessionSelection? result;

    Future<void> openActions() async {
      await _pumpLauncher(
        tester,
        profiles: [defaultTerminalProfile()],
        imported: SshProfileImportSnapshot(
          profiles: [imported],
          sourcePath: '~/.ssh/config',
        ),
        onClosed: (value) => result = value,
      );
      await tester.tap(find.text('SSH session'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('new-ssh-session-import-actions-actions')),
      );
      await tester.pumpAndSettle();
    }

    await openActions();
    expect(
      find.byKey(const Key('new-ssh-session-import-actions-connect')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('new-ssh-session-import-actions-import')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('new-ssh-session-import-actions-connect')),
    );
    await tester.pumpAndSettle();
    expect(result?.profile.id, imported.id);
    expect(result?.saveProfile, isFalse);
    expect(result?.openSession, isTrue);

    result = null;
    await openActions();
    await tester.tap(
      find.byKey(const Key('new-ssh-session-import-actions-import')),
    );
    await tester.pumpAndSettle();
    expect(result?.profile.id, imported.id);
    expect(result?.saveProfile, isTrue);
    expect(result?.openSession, isFalse);
  });

  testWidgets('SSH-only launcher has no local session control', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final saved = _sshProfile('saved', 'Saved host', 'saved.example.test');

    await _pumpLauncher(
      tester,
      profiles: <TerminalProfile>[defaultTerminalProfile(), saved],
      imported: const SshProfileImportSnapshot(
        profiles: [],
        sourcePath: '~/.ssh/config',
      ),
      localSessionsEnabled: false,
      onClosed: (_) {},
    );

    expect(find.text('New SSH tab'), findsOneWidget);
    expect(find.byKey(const Key('new-session-type')), findsNothing);
    expect(find.text('Local shell'), findsNothing);
    expect(find.byKey(const Key('new-local-session-default')), findsNothing);
    expect(find.byKey(const Key('new-ssh-session-saved')), findsOneWidget);
    expect(find.byKey(const Key('new-custom-ssh-session')), findsOneWidget);
  });

  testWidgets('SSH-only launcher stays above the iPhone keyboard', (
    tester,
  ) async {
    const surfaceSize = Size(390, 844);
    const keyboardHeight = 336.0;
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.reset);

    await _pumpLauncher(
      tester,
      profiles: <TerminalProfile>[
        _sshProfile('saved', 'Saved host', 'saved.example.test'),
      ],
      imported: const SshProfileImportSnapshot(
        profiles: [],
        sourcePath: '~/.ssh/config',
      ),
      localSessionsEnabled: false,
      onClosed: (_) {},
    );

    await tester.tap(find.byKey(const Key('ssh-profile-search')));
    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardHeight * tester.view.devicePixelRatio,
    );
    await tester.pumpAndSettle();

    final keyboardTop = surfaceSize.height - keyboardHeight;
    expect(
      tester.getRect(find.byKey(const Key('new-session-launcher'))).bottom,
      lessThanOrEqualTo(keyboardTop),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no-data-service mode keeps OpenSSH hosts and allows one-time SSH',
    (tester) async {
      final saved = _sshProfile('saved', 'Saved host', 'saved.example.test');
      NewSessionSelection? result;
      final imported = terminalProfileFromImportedSshConfig(
        const pty.ImportedSshProfile(
          id: 'openssh-host',
          name: 'OpenSSH host',
          group: 'OpenSSH',
          source: 'openssh_config',
          alias: 'openssh-host',
          host: 'openssh.example.test',
          user: 'developer',
          port: 22,
          auth: 'auto',
          privateKeys: <String>[],
          hostKeyPolicy: 'strict',
          connectTimeoutSeconds: 10,
          keepaliveSeconds: 0,
          keepaliveCountMax: 3,
        ),
      );

      await _pumpLauncher(
        tester,
        profiles: <TerminalProfile>[defaultTerminalProfile(), saved],
        imported: SshProfileImportSnapshot(
          profiles: <TerminalProfile>[imported],
          sourcePath: '~/.ssh/config',
        ),
        customSshProfilesEnabled: false,
        localSessionsEnabled: false,
        onClosed: (value) => result = value,
      );

      expect(find.byKey(const Key('new-custom-ssh-session')), findsOneWidget);
      expect(
        find.byKey(const Key('custom-ssh-requires-remote-api')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('new-ssh-session-saved')), findsNothing);
      expect(
        find.byKey(const Key('new-ssh-session-openssh-host')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('new-ssh-session-openssh-host-actions')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem<void>>(
              find.byKey(const Key('new-ssh-session-openssh-host-import')),
            )
            .enabled,
        isFalse,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('new-custom-ssh-session')));
      await tester.pumpAndSettle();

      final saveProfile = tester.widget<CheckboxListTile>(
        find.byKey(const Key('ssh-save-profile')),
      );
      expect(saveProfile.value, isFalse);
      expect(saveProfile.onChanged, isNull);
      await tester.enterText(
        find.byKey(const Key('ssh-host')),
        'one-time.example.test',
      );
      await tester.enterText(find.byKey(const Key('ssh-user')), 'operator');
      await tester.tap(find.byKey(const Key('ssh-connect')));
      await tester.pumpAndSettle();

      expect(result?.profile.connection.host, 'one-time.example.test');
      expect(result?.saveProfile, isFalse);
    },
  );

  testWidgets('creates a custom SSH session with secure-save enabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NewSessionSelection? result;

    await _pumpLauncher(
      tester,
      profiles: [defaultTerminalProfile()],
      imported: const SshProfileImportSnapshot(
        profiles: [],
        sourcePath: '~/.ssh/config',
      ),
      onClosed: (value) => result = value,
    );
    await tester.tap(find.text('SSH session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-custom-ssh-session')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('ssh-profile-name')),
      'Production',
    );
    await tester.enterText(
      find.byKey(const Key('ssh-host')),
      'prod.example.test',
    );
    await tester.enterText(find.byKey(const Key('ssh-user')), 'operator');
    await tester.tap(find.byKey(const Key('ssh-auth-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Password').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ssh-password')), 'secret');
    await tester.ensureVisible(
      find.text('Host verification and advanced options'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Host verification and advanced options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ssh-proxy-jump')));
    await tester.enterText(
      find.byKey(const Key('ssh-proxy-jump')),
      'jump-one,jump-two:2222',
    );
    await tester.enterText(
      find.byKey(const Key('ssh-port-forwards')),
      'L 127.0.0.1:8080 app.internal:80\nD 127.0.0.1:1080',
    );
    await tester.ensureVisible(find.byKey(const Key('ssh-agent-forwarding')));
    await tester.tap(find.byKey(const Key('ssh-agent-forwarding')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ssh-agent-socket')),
      '/tmp/test-agent.sock',
    );
    await tester.ensureVisible(find.byKey(const Key('ssh-x11-forwarding')));
    await tester.tap(find.byKey(const Key('ssh-x11-forwarding')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ssh-x11-cookie')),
      '00112233445566778899aabbccddeeff',
    );
    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();

    expect(result?.profile.name, 'Production');
    expect(result?.profile.connection.host, 'prod.example.test');
    expect(result?.profile.connection.user, 'operator');
    expect(result?.profile.connection.password, 'secret');
    expect(
      result?.profile.connection.hostKeyPolicy,
      terminal.TerminalSshHostKeyPolicy.acceptNew,
    );
    expect(
      result?.profile.connection.auth,
      terminal.TerminalSshAuthMethod.password,
    );
    expect(result?.profile.connection.proxyJump, 'jump-one,jump-two:2222');
    expect(result?.profile.connection.portForwards, hasLength(2));
    expect(result?.profile.connection.agentForwarding, isTrue);
    expect(result?.profile.connection.agentSocket, '/tmp/test-agent.sock');
    expect(result?.profile.connection.x11Forwarding, isTrue);
    expect(result?.profile.connection.x11TargetHost, isNull);
    expect(
      result?.profile.connection.x11AuthCookie,
      '00112233445566778899aabbccddeeff',
    );
    expect(result?.saveProfile, isTrue);
  });

  testWidgets('SSH single-line fields keep one rendered height locally', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final baseTheme = buildIanvsTerminalTheme(Brightness.dark);
    final themeWithoutInputMinimum = baseTheme.copyWith(
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        constraints: const BoxConstraints(),
      ),
    );

    await _pumpLauncher(
      tester,
      profiles: [defaultTerminalProfile()],
      imported: const SshProfileImportSnapshot(
        profiles: [],
        sourcePath: '~/.ssh/config',
      ),
      onClosed: (_) {},
      theme: themeWithoutInputMinimum,
    );
    await tester.tap(find.text('SSH session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-custom-ssh-session')));
    await tester.pumpAndSettle();

    const fieldKeys = <Key>[
      Key('ssh-profile-name'),
      Key('ssh-host'),
      Key('ssh-user'),
      Key('ssh-port'),
      Key('ssh-password'),
      Key('ssh-key-passphrase'),
    ];
    final heights = fieldKeys
        .map((key) => tester.getSize(find.byKey(key)).height)
        .toList(growable: false);
    final paintedContainerHeights = fieldKeys
        .map((key) {
          final editable = find.descendant(
            of: find.byKey(key),
            matching: find.byType(EditableText),
          );
          return InputDecorator.containerOf(
            tester.element(editable),
          )!.size.height;
        })
        .toList(growable: false);
    for (final height in heights.skip(1)) {
      expect(
        height,
        closeTo(heights.first, 0.01),
        reason: 'SSH input heights must match: $heights',
      );
    }
    expect(heights.first, closeTo(36, 0.01));
    for (final height in paintedContainerHeights) {
      expect(
        height,
        closeTo(36, 0.01),
        reason:
            'SSH painted input containers must match: '
            '$paintedContainerHeights',
      );
    }
    await tester.ensureVisible(
      find.text('Host verification and advanced options'),
    );
    await tester.tap(find.text('Host verification and advanced options'));
    await tester.pumpAndSettle();
    const advancedSingleLineFieldKeys = <Key>[
      Key('ssh-known-hosts-file'),
      Key('ssh-connect-timeout'),
      Key('ssh-keepalive-seconds'),
      Key('ssh-keepalive-count'),
      Key('ssh-proxy-command'),
      Key('ssh-proxy-jump'),
    ];
    final advancedContainerHeights = advancedSingleLineFieldKeys
        .map((key) {
          final editable = find.descendant(
            of: find.byKey(key),
            matching: find.byType(EditableText),
          );
          return InputDecorator.containerOf(
            tester.element(editable),
          )!.size.height;
        })
        .toList(growable: false);
    for (final height in advancedContainerHeights) {
      expect(
        height,
        closeTo(36, 0.01),
        reason:
            'Advanced SSH painted input containers must match: '
            '$advancedContainerHeights',
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('ssh-private-keys')),
        matching: find.byType(EditableText),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects a private key file and keeps only its contents', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SshProfileEditorResult? result;
    final profile = _sshProfile('file-key', 'File key', 'key.example.test')
        .copyWith(
          connection: const terminal.TerminalConnectionConfig.ssh(
            host: 'key.example.test',
            user: 'operator',
            auth: terminal.TerminalSshAuthMethod.publicKey,
          ),
        );

    await _pumpSshEditor(
      tester,
      profile: profile,
      privateKeyPicker: () async =>
          (path: '/Users/alice/.ssh/id_ed25519', contents: _testPrivateKey),
      onClosed: (value) => result = value,
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('ssh-private-keys')),
        matching: find.byType(EditableText),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('ssh-select-private-key')));
    await tester.pumpAndSettle();
    expect(find.text('/Users/alice/.ssh/id_ed25519'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();

    expect(result?.profile.connection.privateKeys, const <String>[
      _testPrivateKey,
    ]);
    expect(
      result?.profile.connection.privateKeys,
      isNot(contains('/Users/alice/.ssh/id_ed25519')),
    );
    final wire = terminal.TerminalSessionConfigV1(
      sessionId: 'inline-private-key-session',
      displayName: result!.profile.name,
      config: result!.profile.toSessionConfig(),
    );
    expect(
      terminal.TerminalSessionConfigV1.fromJsonString(
        wire.toJsonString(),
      ).config.connection.privateKeys,
      const <String>[_testPrivateKey],
    );
  });

  testWidgets('unrelated SSH edits preserve imported jump profiles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SshProfileEditorResult? result;
    final profile = terminalProfileFromImportedSshConfig(
      const pty.ImportedSshProfile(
        id: 'imported-edit',
        name: 'Imported edit',
        group: 'Imported',
        source: 'openssh_config',
        alias: 'imported-edit',
        host: 'target.example.test',
        user: 'target-user',
        port: 22,
        auth: 'auto',
        privateKeys: <String>['/keys/target_ed25519'],
        hostKeyPolicy: 'strict',
        connectTimeoutSeconds: 10,
        keepaliveSeconds: 0,
        keepaliveCountMax: 3,
        proxyJump: 'jump-user@jump-alias:2222',
        proxyJumpProfiles: <pty.ImportedSshJumpProfile>[
          pty.ImportedSshJumpProfile(
            host: 'resolved-jump.example.test',
            user: 'jump-user',
            port: 2222,
            auth: 'public_key',
            privateKeys: <String>['/keys/jump_ed25519'],
            hostKeyPolicy: 'accept_new',
            knownHostsFile: '/known/jump_hosts',
            connectTimeoutSeconds: 12,
            keepaliveSeconds: 20,
            keepaliveCountMax: 4,
          ),
        ],
      ),
      privateKeyLoader: _materializeTestPrivateKey,
    );

    await _pumpSshEditor(
      tester,
      profile: profile,
      onClosed: (value) => result = value,
    );
    await tester.enterText(
      find.byKey(const Key('ssh-profile-name')),
      'Renamed imported profile',
    );
    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();

    expect(result?.profile.name, 'Renamed imported profile');
    expect(result?.profile.connection.proxyJumpProfiles, hasLength(1));
    final jump = result!.profile.connection.proxyJumpProfiles.single;
    expect(jump.host, 'resolved-jump.example.test');
    expect(jump.auth, terminal.TerminalSshAuthMethod.publicKey);
    expect(jump.privateKeys, <String>[_testJumpPrivateKey]);
    expect(jump.hostKeyPolicy, terminal.TerminalSshHostKeyPolicy.acceptNew);
    expect(jump.knownHostsFile, '/known/jump_hosts');
  });

  testWidgets(
    'changed ProxyJump creates independent hops without destination secrets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SshProfileEditorResult? result;
      final profile =
          _sshProfile(
            'custom-jump',
            'Custom jump',
            'target.example.test',
          ).copyWith(
            connection: const terminal.TerminalConnectionConfig.ssh(
              host: 'target.example.test',
              user: 'target-user',
              password: 'target-password',
              privateKeys: <String>['/keys/target_ed25519'],
              privateKeyPassphrase: 'target-passphrase',
            ),
          );

      await _pumpSshEditor(
        tester,
        profile: profile,
        onClosed: (value) => result = value,
      );
      await tester.ensureVisible(
        find.text('Host verification and advanced options'),
      );
      await tester.tap(find.text('Host verification and advanced options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ssh-proxy-jump')));
      await tester.enterText(
        find.byKey(const Key('ssh-proxy-jump')),
        'jump-user@2001:db8::1',
      );
      await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
      await tester.tap(find.byKey(const Key('ssh-connect')));
      await tester.pumpAndSettle();
      expect(
        find.text('Hop 1: wrap IPv6 addresses in brackets'),
        findsOneWidget,
      );
      expect(result, isNull);

      await tester.enterText(
        find.byKey(const Key('ssh-proxy-jump')),
        'jump-user@jump.example.test:2222',
      );
      await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
      await tester.tap(find.byKey(const Key('ssh-connect')));
      await tester.pumpAndSettle();

      final connection = result!.profile.connection;
      expect(connection.password, 'target-password');
      expect(connection.privateKeys, <String>['/keys/target_ed25519']);
      expect(connection.privateKeyPassphrase, 'target-passphrase');
      expect(connection.proxyJumpProfiles, hasLength(1));
      final jump = connection.proxyJumpProfiles.single;
      expect(jump.host, 'jump.example.test');
      expect(jump.user, 'jump-user');
      expect(jump.port, 2222);
      expect(jump.auth, terminal.TerminalSshAuthMethod.auto);
      expect(jump.hostKeyPolicy, terminal.TerminalSshHostKeyPolicy.acceptNew);
      expect(jump.password, isNull);
      expect(jump.privateKeys, isEmpty);
      expect(jump.privateKeyPassphrase, isNull);
    },
  );

  testWidgets('keeps the secure-save choice above the action row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpLauncher(
      tester,
      profiles: [defaultTerminalProfile()],
      imported: const SshProfileImportSnapshot(
        profiles: [],
        sourcePath: '~/.ssh/config',
      ),
      onClosed: (_) {},
    );
    await tester.tap(find.text('SSH session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-custom-ssh-session')));
    await tester.pumpAndSettle();

    final saveRect = tester.getRect(find.byKey(const Key('ssh-save-profile')));
    final connectRect = tester.getRect(find.byKey(const Key('ssh-connect')));
    expect(saveRect.bottom, lessThan(connectRect.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SSH form keeps its focused field and actions above the iPhone keyboard',
    (tester) async {
      const surfaceSize = Size(390, 844);
      const keyboardHeight = 336.0;
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.reset);

      await _pumpSshEditor(
        tester,
        profile: _sshProfile('keyboard', 'Keyboard host', 'host.example.test'),
        onClosed: (_) {},
      );
      await tester.tap(find.byKey(const Key('ssh-password')));
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardHeight * tester.view.devicePixelRatio,
      );
      await tester.pumpAndSettle();

      final keyboardTop = surfaceSize.height - keyboardHeight;
      expect(
        MediaQuery.of(tester.element(find.byType(Dialog))).viewInsets.bottom,
        keyboardHeight,
      );
      expect(find.text('SSH connection'), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('ssh-password'))).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(
        tester.getRect(find.byKey(const Key('ssh-connect'))).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(find.byKey(const Key('ssh-connect')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one-time SSH form does not overflow above a landscape iPhone keyboard',
    (tester) async {
      const surfaceSize = Size(844, 390);
      const keyboardHeight = 216.0;
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.reset);

      await _pumpSshEditor(
        tester,
        profile: _sshProfile('landscape', 'Landscape host', ''),
        allowSaveChoice: true,
        saveProfileAvailable: false,
        onClosed: (_) {},
      );
      await tester.ensureVisible(find.byKey(const Key('ssh-host')));
      await tester.tap(find.byKey(const Key('ssh-host')));
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardHeight * tester.view.devicePixelRatio,
      );
      await tester.pumpAndSettle();

      final keyboardTop = surfaceSize.height - keyboardHeight;
      expect(
        tester.getRect(find.byKey(const Key('ssh-connect'))).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(find.byKey(const Key('ssh-save-profile')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one-time SSH save notice scrolls with the form at large text sizes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSshEditor(
        tester,
        profile: _sshProfile('large-text', 'Large text host', ''),
        allowSaveChoice: true,
        saveProfileAvailable: false,
        textScaler: const TextScaler.linear(2),
        onClosed: (_) {},
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('ssh-profile-form-scroll')),
          matching: find.byKey(const Key('ssh-save-profile')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ssh-connect')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('advanced timing fields stack in narrow high-scale layouts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpLauncher(
      tester,
      profiles: [defaultTerminalProfile()],
      imported: const SshProfileImportSnapshot(
        profiles: [],
        sourcePath: '~/.ssh/config',
      ),
      textScale: 1.8,
      onClosed: (_) {},
    );
    await tester.tap(find.text('SSH session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-custom-ssh-session')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('Host verification and advanced options'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Host verification and advanced options'));
    await tester.pumpAndSettle();

    final timeout = tester.getTopLeft(
      find.byKey(const Key('ssh-connect-timeout')),
    );
    final keepalive = tester.getTopLeft(
      find.byKey(const Key('ssh-keepalive-seconds')),
    );
    final retry = tester.getTopLeft(
      find.byKey(const Key('ssh-keepalive-count')),
    );
    expect(keepalive.dx, closeTo(timeout.dx, 1));
    expect(retry.dx, closeTo(timeout.dx, 1));
    expect(keepalive.dy, greaterThan(timeout.dy));
    expect(retry.dy, greaterThan(keepalive.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SSH secret fields can be revealed and hidden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final profile = defaultTerminalProfile().copyWith(
      id: 'secret-visibility',
      name: 'Secret visibility',
      connection: const terminal.TerminalConnectionConfig.ssh(
        host: 'secret.example.test',
        user: 'operator',
        auth: terminal.TerminalSshAuthMethod.auto,
        password: 'password-secret',
        privateKeys: <String>['/keys/id_ed25519'],
        privateKeyPassphrase: 'key-secret',
        x11Forwarding: true,
        x11AuthCookie: '0123456789abcdef0123456789abcdef',
      ),
    );

    await _pumpSshEditor(tester, profile: profile, onClosed: (_) {});

    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('ssh-password')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('ssh-password-visibility')));
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('ssh-password')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isFalse,
    );

    await tester.ensureVisible(
      find.byKey(const Key('ssh-key-passphrase-visibility')),
    );
    await tester.tap(find.byKey(const Key('ssh-key-passphrase-visibility')));
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('ssh-key-passphrase')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isFalse,
    );

    await tester.ensureVisible(
      find.text('Host verification and advanced options'),
    );
    await tester.tap(find.text('Host verification and advanced options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('ssh-x11-cookie-visibility')),
    );
    await tester.tap(find.byKey(const Key('ssh-x11-cookie-visibility')));
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('ssh-x11-cookie')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isFalse,
    );
  });

  testWidgets('SSH edit save is disabled until the form changes', (
    tester,
  ) async {
    await _pumpSshEditor(
      tester,
      profile: _sshProfile('dirty-save', 'Dirty save', 'dirty.example.test'),
      saveWhenPristine: false,
      onClosed: (_) {},
    );

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ssh-connect')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('ssh-profile-name')),
      'Changed SSH profile',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ssh-connect')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('advanced SSH errors expand and focus the invalid field', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpSshEditor(
      tester,
      profile: _sshProfile('advanced-focus', 'Advanced', 'host.example.test'),
      onClosed: (_) {},
    );

    await tester.ensureVisible(
      find.text('Host verification and advanced options'),
    );
    await tester.tap(find.text('Host verification and advanced options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ssh-connect-timeout')));
    await tester.enterText(find.byKey(const Key('ssh-connect-timeout')), '0');
    await tester.tap(find.text('Host verification and advanced options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();

    final timeout = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('ssh-connect-timeout')),
        matching: find.byType(EditableText),
      ),
    );
    expect(timeout.focusNode.hasFocus, isTrue);
    expect(find.text('Enter 1–120'), findsOneWidget);
  });

  testWidgets('X11 requires a 32-character hexadecimal cookie', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SshProfileEditorResult? result;
    await _pumpSshEditor(
      tester,
      profile: _sshProfile('x11-cookie', 'X11 cookie', 'x11.example.test'),
      onClosed: (value) => result = value,
    );
    await tester.ensureVisible(
      find.text('Host verification and advanced options'),
    );
    await tester.tap(find.text('Host verification and advanced options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ssh-x11-forwarding')));
    await tester.tap(find.byKey(const Key('ssh-x11-forwarding')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter exactly 32 hexadecimal characters'),
      findsOneWidget,
    );
    expect(result, isNull);

    await tester.enterText(
      find.byKey(const Key('ssh-x11-cookie')),
      '00112233445566778899aabbccddeezz',
    );
    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter exactly 32 hexadecimal characters'),
      findsOneWidget,
    );
    expect(result, isNull);

    await tester.enterText(
      find.byKey(const Key('ssh-x11-cookie')),
      '00112233445566778899aabbccddeeff',
    );
    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();
    expect(
      result?.profile.connection.x11AuthCookie,
      '00112233445566778899aabbccddeeff',
    );
  });

  testWidgets('shows only credentials relevant to the authentication method', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NewSessionSelection? result;

    await _pumpLauncher(
      tester,
      profiles: [defaultTerminalProfile()],
      imported: const SshProfileImportSnapshot(
        profiles: [],
        sourcePath: '~/.ssh/config',
      ),
      onClosed: (value) => result = value,
    );
    await tester.tap(find.text('SSH session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-custom-ssh-session')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssh-password')), findsOneWidget);
    expect(find.byKey(const Key('ssh-private-keys')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssh-auth-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keyboard interactive / OTP').last);
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNothing);
    expect(find.byKey(const Key('ssh-password')), findsNothing);
    expect(find.byKey(const Key('ssh-private-keys')), findsNothing);
    expect(find.byKey(const Key('ssh-key-passphrase')), findsNothing);
    expect(find.textContaining('multi-step OTP challenges'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ssh-host')),
      'otp.example.test',
    );
    await tester.enterText(find.byKey(const Key('ssh-user')), 'operator');
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();

    expect(
      result?.profile.connection.auth,
      terminal.TerminalSshAuthMethod.keyboardInteractive,
    );
    expect(result?.profile.connection.password, isNull);
    expect(result?.profile.connection.privateKeys, isEmpty);
  });

  testWidgets(
    'explicit forget action emits a password clear intent even when blank',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SshProfileEditorResult? result;
      final profile = _sshProfile(
        'opaque-password',
        'Opaque password',
        'opaque.example.test',
      );

      await _pumpSshEditor(
        tester,
        profile: profile,
        onClosed: (value) => result = value,
      );
      expect(find.byKey(const Key('ssh-password')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('ssh-password')))
            .controller
            ?.text,
        isEmpty,
      );

      await tester.tap(find.byKey(const Key('ssh-clear-password')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
      await tester.tap(find.byKey(const Key('ssh-connect')));
      await tester.pumpAndSettle();

      expect(result?.clearSecrets, contains(ProfileSecretField.password));
      expect(result?.profile.connection.password, isNull);
    },
  );

  testWidgets('unrelated editor save emits no secret clear intents', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SshProfileEditorResult? result;
    final profile =
        _sshProfile(
          'unrelated-save',
          'Unrelated save',
          'unrelated.example.test',
        ).copyWith(
          connection: const terminal.TerminalConnectionConfig.ssh(
            host: 'unrelated.example.test',
            user: 'operator',
            auth: terminal.TerminalSshAuthMethod.keyboardInteractive,
          ),
        );

    await _pumpSshEditor(
      tester,
      profile: profile,
      onClosed: (value) => result = value,
    );
    await tester.enterText(
      find.byKey(const Key('ssh-profile-name')),
      'Renamed only',
    );
    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();

    expect(result?.profile.name, 'Renamed only');
    expect(result?.clearSecrets, isEmpty);
  });

  testWidgets(
    'auth and X11 changes emit cleanup intents for now-unused secrets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SshProfileEditorResult? result;
      final profile =
          _sshProfile(
            'cleanup-secrets',
            'Cleanup secrets',
            'cleanup.example.test',
          ).copyWith(
            connection: const terminal.TerminalConnectionConfig.ssh(
              host: 'cleanup.example.test',
              user: 'operator',
              auth: terminal.TerminalSshAuthMethod.auto,
              password: 'old-password',
              privateKeys: <String>['~/.ssh/id_ed25519'],
              privateKeyPassphrase: 'old-passphrase',
              x11Forwarding: true,
              x11TargetHost: '127.0.0.1',
              x11TargetPort: 6000,
              x11AuthCookie: 'old-cookie',
            ),
          );

      await _pumpSshEditor(
        tester,
        profile: profile,
        onClosed: (value) => result = value,
      );
      await tester.tap(find.byKey(const Key('ssh-auth-method')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keyboard interactive / OTP').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Host verification and advanced options'),
      );
      await tester.tap(find.text('Host verification and advanced options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ssh-x11-forwarding')));
      await tester.tap(find.byKey(const Key('ssh-x11-forwarding')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
      await tester.tap(find.byKey(const Key('ssh-connect')));
      await tester.pumpAndSettle();

      expect(result?.clearSecrets, <ProfileSecretField>{
        ProfileSecretField.password,
        ProfileSecretField.privateKeys,
        ProfileSecretField.privateKeyPassphrase,
        ProfileSecretField.x11AuthCookie,
      });
      expect(
        result?.profile.connection.auth,
        terminal.TerminalSshAuthMethod.keyboardInteractive,
      );
      expect(result?.profile.connection.password, isNull);
      expect(result?.profile.connection.privateKeyPassphrase, isNull);
      expect(result?.profile.connection.x11Forwarding, isFalse);
      expect(result?.profile.connection.x11AuthCookie, isNull);
    },
  );

  testWidgets('requires credentials for explicit password and key methods', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpLauncher(
      tester,
      profiles: [defaultTerminalProfile()],
      imported: const SshProfileImportSnapshot(
        profiles: [],
        sourcePath: '~/.ssh/config',
      ),
      onClosed: (_) {},
    );
    await tester.tap(find.text('SSH session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-custom-ssh-session')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ssh-host')), 'host.test');
    await tester.enterText(find.byKey(const Key('ssh-user')), 'operator');

    await tester.tap(find.byKey(const Key('ssh-auth-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Password').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssh-auth-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private key').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();
    expect(find.text('Select a private key file'), findsOneWidget);
  });
}

TerminalProfile _sshProfile(String id, String name, String host) {
  return defaultTerminalProfile().copyWith(
    id: id,
    name: name,
    connection: terminal.TerminalConnectionConfig.ssh(
      host: host,
      user: 'operator',
    ),
  );
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required List<TerminalProfile> profiles,
  required SshProfileImportSnapshot imported,
  required ValueChanged<NewSessionSelection?> onClosed,
  double textScale = 1,
  bool customSshProfilesEnabled = true,
  bool localSessionsEnabled = true,
  ThemeData? theme,
}) async {
  final resolvedTheme = theme ?? buildIanvsTerminalTheme(Brightness.dark);
  await tester.pumpWidget(
    MaterialApp(
      theme: resolvedTheme,
      darkTheme: resolvedTheme,
      themeMode: ThemeMode.dark,
      builder: textScale == 1
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                onClosed(
                  await showModalBottomSheet<NewSessionSelection>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => NewSessionLauncher(
                      profiles: profiles,
                      customSshProfilesEnabled: customSshProfilesEnabled,
                      localSessionsEnabled: localSessionsEnabled,
                      importOpenSshProfiles: () async => imported,
                    ),
                  ),
                );
              },
              child: const Text('Open launcher'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open launcher'));
  await tester.pumpAndSettle();
}

Future<void> _pumpSshEditor(
  WidgetTester tester, {
  required TerminalProfile profile,
  required ValueChanged<SshProfileEditorResult?> onClosed,
  bool saveWhenPristine = true,
  bool allowSaveChoice = false,
  bool saveProfileAvailable = true,
  TextScaler? textScaler,
  SshPrivateKeyPicker? privateKeyPicker,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
      theme: buildIanvsTerminalTheme(Brightness.dark),
      darkTheme: buildIanvsTerminalTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                onClosed(
                  await showDialog<SshProfileEditorResult>(
                    context: context,
                    builder: (_) => SshProfileEditorDialog(
                      initialValue: profile,
                      allowSaveChoice: allowSaveChoice,
                      saveProfileAvailable: saveProfileAvailable,
                      saveWhenPristine: saveWhenPristine,
                      privateKeyPicker: privateKeyPicker,
                    ),
                  ),
                );
              },
              child: const Text('Open SSH editor'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open SSH editor'));
  await tester.pumpAndSettle();
}
