import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_providers.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/persistence_repository_composition.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_pty_backend.dart';
import '../../support/memory_app_preferences_repository.dart';
import '../../support/memory_local_terminal_config_repository.dart';
import '../../support/memory_paste_history_repository.dart';

void main() {
  const credentialRef = 'current-credential-slot-0001';

  testWidgets(
    'expired remote startup can reconnect from the typed error surface',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final baseUri = Uri.parse('https://sync.example.com/');
      final configurationRepository = _MemoryConfigurationRepository(
        DataApiConfiguration.remote(baseUri.toString()).withPersistenceState(
          generation: 1,
          remoteCredentialRef: credentialRef,
          lastTransactionId: null,
        ),
      );
      final expiredSession = DataApiRemoteSession(
        baseUri: baseUri,
        accessToken: 'expired-token',
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final sessionStore = _MemoryRemoteSessionStore()
        ..slots[credentialRef] = expiredSession;
      final renewedSession = DataApiRemoteSession(
        baseUri: baseUri,
        accessToken: 'renewed-token',
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final guardedRepository = AuthenticatedDataApiConfigurationRepository(
        delegate: configurationRepository,
        remoteSessionStore: sessionStore,
        remoteAuthenticator: _RemoteAuthenticator(renewedSession),
        remoteConnectionValidator: const _NoopRemoteValidator(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              _NoopRecordingRepository(),
            ),
            profileRepositoryProvider.overrideWithValue(
              const _UnavailableProfileRepository(),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(null),
            ),
            pasteHistoryRepositoryProvider.overrideWithValue(
              MemoryPasteHistoryRepository(),
            ),
            dataApiConfigurationRepositoryProvider.overrideWithValue(
              guardedRepository,
            ),
            dataApiStartupWarningProvider.overrideWithValue(
              const DataApiStartupWarning(
                'Data service cleanup is pending. Restart to retry.',
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildIanvsTerminalTheme(Brightness.dark),
            home: const ShellScreen(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('shell-startup-error')),
      );

      expect(
        find.textContaining('configured Data API is unavailable'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('data-api-startup-warning')), findsOneWidget);
      await tester.tap(find.byKey(const Key('shell-startup-settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('defaults-data-api-panel')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('data-api-remote-reconnect')));
      await tester.enterText(
        find.byKey(const Key('data-api-remote-username')),
        'alice',
      );
      await tester.enterText(
        find.byKey(const Key('data-api-remote-password')),
        'new-password',
      );
      await tester.enterText(
        find.byKey(const Key('data-api-remote-encryption-key')),
        'encryption-key-material',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('defaults-save')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Data service configuration saved'),
        findsOneWidget,
      );
      final saved = await configurationRepository.load();
      expect(
        await sessionStore.readSlot(saved.remoteCredentialRef!),
        same(renewedSession),
      );
      expect(await sessionStore.readSlot(credentialRef), isNull);
      expect(configurationRepository.configuration.remoteBaseUri, baseUri);
    },
  );

  testWidgets(
    'unavailable remote can disable despite logout failure and restart local',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final baseUri = Uri.parse('https://sync.example.com/');
      final configurationRepository = _MemoryConfigurationRepository(
        DataApiConfiguration.remote(baseUri.toString()).withPersistenceState(
          generation: 1,
          remoteCredentialRef: credentialRef,
          lastTransactionId: null,
        ),
      );
      final expiredSession = DataApiRemoteSession(
        baseUri: baseUri,
        accessToken: 'expired-token',
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final sessionStore = _MemoryRemoteSessionStore()
        ..slots[credentialRef] = expiredSession;
      final guardedRepository = AuthenticatedDataApiConfigurationRepository(
        delegate: configurationRepository,
        remoteSessionStore: sessionStore,
        remoteSessionRevoker: const _FailingRemoteRevoker(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              _NoopRecordingRepository(),
            ),
            profileRepositoryProvider.overrideWithValue(
              const _UnavailableProfileRepository(),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(null),
            ),
            pasteHistoryRepositoryProvider.overrideWithValue(
              MemoryPasteHistoryRepository(),
            ),
            dataApiConfigurationRepositoryProvider.overrideWithValue(
              guardedRepository,
            ),
          ],
          child: MaterialApp(
            theme: buildIanvsTerminalTheme(Brightness.dark),
            home: const ShellScreen(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('shell-startup-error')),
      );

      await tester.tap(find.byKey(const Key('shell-startup-settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('defaults-data-api-panel')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('data-api-disabled')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('defaults-save')));
      await tester.pumpAndSettle();

      expect(
        configurationRepository.configuration,
        const DataApiConfiguration.disabled(),
      );
      expect(sessionStore.slots[credentialRef], same(expiredSession));
      expect(
        find.byKey(const Key('data-api-revocation-pending-warning')),
        findsOneWidget,
      );
      final restartComposition = PersistenceRepositoryComposition.forRuntime(
        null,
        profileExportDirectoryResolver: () async => Directory.systemTemp,
        dataApiPersistenceRequired: false,
      );
      expect(restartComposition.usesDataApi, isFalse);
      expect(restartComposition.profiles, isA<ProfileRepository>());
    },
  );

  testWidgets(
    'secure-session read failure cannot block the disabled escape path',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final baseUri = Uri.parse('https://sync.example.com/');
      final configurationRepository = _MemoryConfigurationRepository(
        DataApiConfiguration.remote(baseUri.toString()).withPersistenceState(
          generation: 1,
          remoteCredentialRef: credentialRef,
          lastTransactionId: null,
        ),
      );
      final unreadableSession = DataApiRemoteSession(
        baseUri: baseUri,
        accessToken: 'unreadable-token',
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final sessionStore = _MemoryRemoteSessionStore()
        ..slots[credentialRef] = unreadableSession
        ..readError = StateError('credential vault read failed');
      final guardedRepository = AuthenticatedDataApiConfigurationRepository(
        delegate: configurationRepository,
        remoteSessionStore: sessionStore,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              _NoopRecordingRepository(),
            ),
            profileRepositoryProvider.overrideWithValue(
              const _UnavailableProfileRepository(),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(null),
            ),
            pasteHistoryRepositoryProvider.overrideWithValue(
              MemoryPasteHistoryRepository(),
            ),
            dataApiConfigurationRepositoryProvider.overrideWithValue(
              guardedRepository,
            ),
          ],
          child: MaterialApp(
            theme: buildIanvsTerminalTheme(Brightness.dark),
            home: const ShellScreen(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('shell-startup-error')),
      );
      await tester.tap(find.byKey(const Key('shell-startup-settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('defaults-data-api-panel')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('data-api-disabled')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('defaults-save')));
      await tester.pumpAndSettle();

      expect(
        configurationRepository.configuration,
        const DataApiConfiguration.disabled(),
      );
      expect(sessionStore.slots[credentialRef], same(unreadableSession));
      expect(sessionStore.deleteCount, 0);
      expect(
        find.byKey(const Key('data-api-revocation-pending-warning')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'secure credential cleanup failure is shown after mode was saved',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final baseUri = Uri.parse('https://sync.example.com/');
      final configurationRepository = _MemoryConfigurationRepository(
        DataApiConfiguration.remote(baseUri.toString()).withPersistenceState(
          generation: 1,
          remoteCredentialRef: credentialRef,
          lastTransactionId: null,
        ),
      );
      final session = DataApiRemoteSession(
        baseUri: baseUri,
        accessToken: 'active-token',
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final sessionStore = _MemoryRemoteSessionStore()
        ..slots[credentialRef] = session
        ..clearError = StateError('credential vault unavailable');
      final guardedRepository = AuthenticatedDataApiConfigurationRepository(
        delegate: configurationRepository,
        remoteSessionStore: sessionStore,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              _NoopRecordingRepository(),
            ),
            profileRepositoryProvider.overrideWithValue(
              const _UnavailableProfileRepository(),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(null),
            ),
            pasteHistoryRepositoryProvider.overrideWithValue(
              MemoryPasteHistoryRepository(),
            ),
            dataApiConfigurationRepositoryProvider.overrideWithValue(
              guardedRepository,
            ),
          ],
          child: MaterialApp(
            theme: buildIanvsTerminalTheme(Brightness.dark),
            home: const ShellScreen(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('shell-startup-error')),
      );
      await tester.tap(find.byKey(const Key('shell-startup-settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('defaults-data-api-panel')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('data-api-disabled')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('defaults-save')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('data-api-revocation-pending-warning')),
        findsOneWidget,
      );
      expect(find.textContaining('configuration was saved'), findsOneWidget);
      expect(
        configurationRepository.configuration,
        const DataApiConfiguration.disabled(),
      );
      expect(sessionStore.slots[credentialRef], same(session));
    },
  );

  testWidgets('corrupt configuration requires explicit disabled confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final configurationRepository = _MemoryConfigurationRepository(
      const DataApiConfiguration.disabled(),
      recoveryRequired: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _NoopRecordingRepository(),
          ),
          profileRepositoryProvider.overrideWithValue(
            const _UnavailableProfileRepository(),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            MemoryAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(null),
          ),
          pasteHistoryRepositoryProvider.overrideWithValue(
            MemoryPasteHistoryRepository(),
          ),
          dataApiConfigurationRepositoryProvider.overrideWithValue(
            configurationRepository,
          ),
        ],
        child: MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: const ShellScreen(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(const Key('shell-startup-error')));
    await tester.tap(find.byKey(const Key('shell-startup-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(configurationRepository.saveCount, 1);
    expect(configurationRepository.recoveryRequired, isFalse);
    expect(
      find.textContaining('Data service configuration saved'),
      findsOneWidget,
    );
  });

  testWidgets(
    'startup configuration I/O failure can explicitly save disabled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final configurationRepository = _FailingLoadConfigurationRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              _NoopRecordingRepository(),
            ),
            profileRepositoryProvider.overrideWithValue(
              const _UnavailableProfileRepository(),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(null),
            ),
            pasteHistoryRepositoryProvider.overrideWithValue(
              MemoryPasteHistoryRepository(),
            ),
            dataApiConfigurationRepositoryProvider.overrideWithValue(
              configurationRepository,
            ),
            dataApiConfigurationRecoveryRequiredProvider.overrideWithValue(
              true,
            ),
          ],
          child: MaterialApp(
            theme: buildIanvsTerminalTheme(Brightness.dark),
            home: const ShellScreen(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('shell-startup-error')),
      );
      await tester.tap(find.byKey(const Key('shell-startup-settings')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('defaults-save')), findsOneWidget);
      await tester.tap(find.byKey(const Key('defaults-save')));
      await tester.pumpAndSettle();

      expect(configurationRepository.saveCount, 1);
      expect(
        configurationRepository.saved,
        const DataApiConfiguration.disabled(),
      );
      expect(find.byKey(const Key('defaults-save')), findsNothing);
    },
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var tick = 0; tick < 30 && finder.evaluate().isEmpty; tick += 1) {
    await tester.pump(const Duration(milliseconds: 33));
  }
  expect(
    finder,
    findsOneWidget,
    reason: find
        .byType(Text)
        .evaluate()
        .map((element) => (element.widget as Text).data)
        .whereType<String>()
        .join(' | '),
  );
}

final class _UnavailableProfileRepository extends ProfileRepositoryPort {
  const _UnavailableProfileRepository();

  @override
  Future<File> exportDocument(
    TerminalProfilesDocument document, {
    String basename = 'ianvs-profiles',
  }) async {
    throw const DataApiPersistenceUnavailableException();
  }

  @override
  Future<TerminalProfilesDocument> load() async {
    throw const DataApiPersistenceUnavailableException();
  }

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    throw const DataApiPersistenceUnavailableException();
  }
}

final class _NoopRecordingRepository extends LocalSessionRecordingRepository {
  _NoopRecordingRepository()
    : super(directoryResolver: () async => Directory.systemTemp);

  @override
  Future<LocalSessionRecordingRecoveryResult> recoverNativeRecordings() async {
    return const LocalSessionRecordingRecoveryResult(
      recoveredPaths: <String>[],
      pendingJobIds: <String>[],
      orphanPaths: <String>[],
      failures: <LocalSessionRecordingRecoveryFailure>[],
    );
  }
}

final class _MemoryConfigurationRepository
    implements
        DataApiConfigurationRepository,
        DataApiConfigurationRecoveryStatus {
  _MemoryConfigurationRepository(
    this.configuration, {
    this.recoveryRequired = false,
  });

  DataApiConfiguration configuration;
  @override
  bool recoveryRequired;
  int saveCount = 0;

  @override
  Future<DataApiConfiguration> load() async => configuration;

  @override
  Future<void> save(DataApiConfiguration configuration) async {
    this.configuration = configuration;
    recoveryRequired = false;
    saveCount += 1;
  }
}

final class _FailingLoadConfigurationRepository
    implements DataApiConfigurationRepository {
  int saveCount = 0;
  DataApiConfiguration? saved;

  @override
  Future<DataApiConfiguration> load() async {
    throw const FileSystemException('configuration read failed');
  }

  @override
  Future<void> save(DataApiConfiguration configuration) async {
    saveCount += 1;
    saved = configuration;
  }
}

final class _MemoryRemoteSessionStore implements DataApiRemoteSessionSlotStore {
  _MemoryRemoteSessionStore();

  Error? readError;
  Error? clearError;
  int deleteCount = 0;
  final Map<String, DataApiRemoteSession> slots =
      <String, DataApiRemoteSession>{};

  @override
  Future<Set<String>> listSlotRefs() async => slots.keys.toSet();

  @override
  Future<DataApiRemoteSession?> readSlot(String slotRef) async {
    final error = readError;
    if (error != null) {
      throw error;
    }
    return slots[slotRef];
  }

  @override
  Future<void> writeSlot(String slotRef, DataApiRemoteSession session) async {
    if (slots.containsKey(slotRef)) {
      throw DataApiRemoteSessionSlotExistsException(slotRef);
    }
    slots[slotRef] = session;
  }

  @override
  Future<void> deleteSlot(String slotRef) async {
    deleteCount += 1;
    final error = clearError;
    if (error != null) {
      throw error;
    }
    slots.remove(slotRef);
  }
}

final class _RemoteAuthenticator implements DataApiRemoteAuthenticator {
  const _RemoteAuthenticator(this.session);

  final DataApiRemoteSession session;

  @override
  Future<DataApiPreparedAuthOperation> begin(
    DataApiRemoteLoginRequest request,
  ) async => DataApiPreparedAuthOperation(
    operationId: List<String>.filled(43, 'R').join(),
    expiresAt: DateTime.utc(2100),
  );

  @override
  Future<DataApiRemoteSession> complete(
    DataApiRemoteLoginRequest request,
    DataApiPreparedAuthOperation operation,
  ) async => session;
}

final class _NoopRemoteValidator implements DataApiRemoteConnectionValidator {
  const _NoopRemoteValidator();

  @override
  Future<void> validate(DataApiRemoteSession session) async {}
}

final class _FailingRemoteRevoker implements DataApiRemoteSessionRevoker {
  const _FailingRemoteRevoker();

  @override
  Future<void> revoke(DataApiRemoteSession session) async {
    throw const DataApiTimeoutException(Duration(seconds: 5));
  }
}
