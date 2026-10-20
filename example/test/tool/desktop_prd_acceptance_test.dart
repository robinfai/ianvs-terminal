import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/persistence_repository_composition.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import '../../tool/desktop_prd_environment.dart';
import '../support/fake_pty_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const keychain = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;
  var keychainCalls = 0;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'desktop-prd-entry-test-',
    );
    keychainCalls = 0;
    messenger.setMockMethodCallHandler(keychain, (_) async {
      keychainCalls++;
      throw StateError('Acceptance must not touch production Keychain.');
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(keychain, null);
    await temporary.delete(recursive: true);
  });

  Directory directory(String name) => Directory('${temporary.path}/$name');

  test(
    'nonempty unrelated roots are rejected without changing their files',
    () async {
      final root = await directory('unrelated').create();
      final existing = File('${root.path}/user-data');
      await existing.writeAsString('keep-user-data');
      await expectLater(
        DesktopPrdEnvironment.prepare(root),
        throwsA(isA<FileSystemException>()),
      );
      expect(await existing.readAsString(), 'keep-user-data');
      expect(await root.list().length, 1);
      expect(keychainCalls, 0);
    },
  );

  test(
    'copied markers and directory links cannot adopt another root',
    () async {
      final original = await DesktopPrdEnvironment.prepare(
        directory('original'),
      );
      final copied = await directory('copied').create();
      await File(
        '${original.root.path}/${DesktopPrdEnvironment.markerName}',
      ).copy('${copied.path}/${DesktopPrdEnvironment.markerName}');
      await expectLater(
        DesktopPrdEnvironment.prepare(copied),
        throwsA(isA<FileSystemException>()),
      );
      final link = await Link(
        '${temporary.path}/alias',
      ).create(original.root.path);
      await expectLater(
        DesktopPrdEnvironment.prepare(Directory(link.path)),
        throwsA(isA<FileSystemException>()),
      );
      expect(keychainCalls, 0);
    },
  );

  test('marked fixtures also reject a redirected storage directory', () async {
    final fixture = await DesktopPrdEnvironment.prepare(directory('fixture'));
    final outside = await directory('outside').create();
    await fixture.home.delete(recursive: true);
    await Link(fixture.home.path).create(outside.path);
    await expectLater(
      DesktopPrdEnvironment.prepare(fixture.root),
      throwsA(isA<FileSystemException>()),
    );
    expect(await outside.list().isEmpty, isTrue);
  });

  test(
    'reuse preserves manual AI and SSH settings without reading Keychain',
    () async {
      final first = await DesktopPrdEnvironment.prepare(directory('first'));
      expect(await first.aiConfigurationStore.read(), isNull);
      expect(first.masterKeyRepository.allowLegacyMigration, isFalse);
      expect(
        first.masterKeyRepository.storagePolicy,
        PortableMasterKeyStoragePolicy.developmentFile,
      );
      const configuration = AiConfiguration(
        endpoint: 'https://test.invalid/v1',
        apiKey: 'synthetic-acceptance-key',
        model: 'test-model',
      );
      await first.aiConfigurationStore.write(configuration);
      final repositories = _repositories(first);
      try {
        final local = (await repositories.profiles.load()).profiles.single;
        await repositories.profiles.save(
          TerminalProfilesDocument(
            profiles: [
              local.copyWith(name: 'Manually renamed fixture'),
              local.copyWith(
                id: 'manual-ssh',
                connection: const terminal.TerminalConnectionConfig.ssh(
                  host: 'test.invalid',
                  user: 'tester',
                  password: 'synthetic-ssh-password',
                ),
              ),
            ],
          ),
        );
      } finally {
        await repositories.sync.close();
      }
      final shellConfiguration = File('${first.home.path}/.zshrc');
      await shellConfiguration.writeAsString('# manually edited fixture\n');
      final originalKey =
          (await first.masterKeyRepository.readOrCreate()).portableValue;

      final reopened = await DesktopPrdEnvironment.prepare(first.root);
      final reader = _repositories(reopened);
      try {
        expect(
          (await reopened.aiConfigurationStore.read())?.toJson(),
          configuration.toJson(),
        );
        expect(
          (await reopened.masterKeyRepository.readOrCreate()).portableValue,
          originalKey,
        );
        final profiles = (await reader.profiles.load()).profiles;
        expect(profiles.first.name, 'Manually renamed fixture');
        expect(profiles.last.connection.password, 'synthetic-ssh-password');
        expect(
          await shellConfiguration.readAsString(),
          '# manually edited fixture\n',
        );
        final raw = await File(
          '${reopened.support.path}/ianvs_profiles.json',
        ).readAsString();
        expect(raw, isNot(contains('synthetic-ssh-password')));
      } finally {
        await reader.sync.close();
      }
      final other = await DesktopPrdEnvironment.prepare(directory('other'));
      expect(await other.aiConfigurationStore.read(), isNull);
      expect(
        (await other.masterKeyRepository.readOrCreate()).portableValue,
        isNot(originalKey),
      );
      final otherRepositories = _repositories(other);
      try {
        final profiles = (await otherRepositories.profiles.load()).profiles;
        expect(profiles, hasLength(1));
        expect(profiles.single.isSsh, isFalse);
      } finally {
        await otherRepositories.sync.close();
      }
      expect((await first.root.stat()).mode & 511, 448);
      expect(keychainCalls, 0);
    },
  );

  testWidgets(
    'production startup and Shell use the fixture stores and PTY environment',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        final fixture = await DesktopPrdEnvironment.prepare(
          directory('full-graph'),
        );
        // Select a normal persisted data mode, so this unit host does not start
        // the native local sidecar. The target itself retains the real default.
        await FileDataApiConfigurationRepository(
          appSupportDirectory: fixture.support,
        ).save(const DataApiConfiguration.disabled());
        final repositories = _repositories(fixture);
        try {
          final local = (await repositories.profiles.load()).profiles.single;
          await repositories.profiles.save(
            TerminalProfilesDocument(
              profiles: [
                local.copyWith(
                  env: {
                    'HOME': '/unrelated/profile-home',
                    'ZDOTDIR': '/unrelated/profile-zsh',
                    'MANUAL_SETTING': 'preserved',
                  },
                ),
              ],
            ),
          );
        } finally {
          await repositories.sync.close();
        }
        return fixture;
      }))!;
      final backend = _SshPtyBackend();
      final coordinator = createDesktopPrdStartupCoordinator(
        fixture,
        nativePtyLoader: () async => backend,
      );
      try {
        await tester.pumpWidget(
          buildDesktopPrdApp(environment: fixture, coordinator: coordinator),
        );
        // Files complete in the real event loop, while callbacks created by the
        // host's first frame need widget pumps. Await neither half in isolation.
        await _pumpUntil(tester, () => coordinator.state is! AppStartupLoading);
        expect(coordinator.state, isA<AppStartupReady>());
        final graph = (coordinator.state as AppStartupReady).graph;
        expect(graph.paths.appSupportDirectory.path, fixture.support.path);
        expect(graph.masterKeyRepository, same(fixture.masterKeyRepository));
        expect(graph.ptySessionBackend, same(backend));
        await tester.pump();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ShellScreen)),
        );
        await _pumpUntil(
          tester,
          () => container.read(sessionControllerProvider).isReady,
        );
        expect(container.read(sessionControllerProvider).isReady, isTrue);
        expect(
          container.read(profileRepositoryProvider),
          same(graph.persistenceRepositories.profiles),
        );
        expect(
          container.read(sessionEnvironmentOverridesProvider),
          fixture.shellEnvironment,
        );
        final settings = container.read(aiSettingsProvider);
        await _pumpUntil(tester, () => !settings.loading);
        expect(settings.store, same(fixture.aiConfigurationStore));
        expect(settings.configuration, isNull);
        const configuredInApp = AiConfiguration.mock();
        await tester.runAsync(() => settings.save(configuredInApp));
        final saved = await tester.runAsync(fixture.aiConfigurationStore.read);
        expect(saved?.toJson(), configuredInApp.toJson());

        final launch = (backend.lastCreatedSessionPayload!['launch']! as Map)
            .cast<String, Object?>();
        expect(launch['program'], '/bin/zsh');
        expect(launch['cwd'], fixture.home.path);
        final environment = (launch['env']! as Map).cast<String, Object?>();
        for (final entry in fixture.shellEnvironment.entries) {
          expect(environment[entry.key], entry.value, reason: entry.key);
        }
        expect(environment['MANUAL_SETTING'], 'preserved');

        // The same real SessionController must leave a manually configured remote
        // environment intact; a Mac HOME must never be sent to an SSH server.
        final ssh = TerminalProfile(
          id: 'manual-remote',
          name: 'Synthetic SSH target',
          shell: '/bin/sh',
          env: const {'HOME': '/remote/tester', 'REMOTE_SETTING': 'preserved'},
          connection: const terminal.TerminalConnectionConfig.ssh(
            host: 'test.invalid',
            user: 'tester',
            password: 'synthetic-ssh-password',
          ),
        );
        final remoteId = container
            .read(sessionControllerProvider.notifier)
            .createSession(ssh);
        expect(remoteId, isNotNull);
        final remoteLaunch =
            (backend.lastCreatedSessionPayload!['launch']! as Map)
                .cast<String, Object?>();
        expect(remoteLaunch['env'], ssh.env);
        expect(keychainCalls, 0);
        expect(tester.takeException(), isNull);
      } finally {
        // Close while the test still owns the mounted application. The
        // widget-test framework unmounts before addTearDown callbacks run.
        var closed = false;
        final closing = coordinator.close().whenComplete(() => closed = true);
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntil(tester, () => closed);
        final result = await closing;
        expect(
          result.safeToTerminate,
          isTrue,
          reason: result.failures.map((failure) => failure.error).join('\n'),
        );
        await tester.pump();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

PersistenceRepositoryComposition _repositories(DesktopPrdEnvironment fixture) =>
    PersistenceRepositoryComposition.forRuntime(
      null,
      profileExportDirectoryResolver: () async => fixture.support,
      masterKeyRepository: fixture.masterKeyRepository,
    );

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(condition(), isTrue, reason: 'Fixture startup did not settle.');
}

class _SshPtyBackend extends FakePtyBackend {
  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson({
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <String>[],
        'recording_schema_versions': <int>[],
        'features': ['session-config.json.v1', 'ssh-session.v1'],
      });
}
