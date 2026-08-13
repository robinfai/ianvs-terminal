import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/features/persistence/versioned_document.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/ssh/ssh_feature_access.dart';
import 'package:app/features/ssh/ssh_profile_import_service.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';

final class _FailingRemoteProfileRepository extends ProfileRepositoryPort {
  _FailingRemoteProfileRepository()
    : _document = TerminalProfilesDocument(
        profiles: <TerminalProfile>[defaultTerminalProfile()],
      );

  final TerminalProfilesDocument _document;
  int saveAttempts = 0;

  @override
  Future<TerminalProfilesDocument> load() async => _document;

  @override
  Future<VersionedDocument<TerminalProfilesDocument>> loadVersioned() async {
    return VersionedDocument<TerminalProfilesDocument>(
      value: _document,
      revision: 7,
    );
  }

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    saveAttempts += 1;
    throw const DataApiRequestException(
      statusCode: 503,
      code: 'service_unavailable',
      message: 'Remote profile store is unavailable.',
    );
  }

  @override
  Future<File> exportDocument(
    TerminalProfilesDocument document, {
    String basename = 'ianvs-profiles',
  }) {
    throw UnsupportedError('Not used by this test.');
  }
}

final class _EmptySshProfileImportService implements SshProfileImportService {
  const _EmptySshProfileImportService();

  @override
  Future<SshProfileImportSnapshot> load({String? configPath}) async {
    return const SshProfileImportSnapshot(
      profiles: <TerminalProfile>[],
      sourcePath: '~/.ssh/config',
    );
  }
}

final class _SshFakePtyBackend extends FakePtyBackend {
  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson(<String, Object?>{
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
        'recording_schema_versions': <Object?>[],
        'features': <Object?>['session-config.json.v1', 'ssh-session.v1'],
      });
}

Future<void> _pumpShell(
  WidgetTester tester,
  _FailingRemoteProfileRepository repository,
  _SshFakePtyBackend backend,
) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        customSshProfileConfigurationEnabledProvider.overrideWithValue(true),
        sshProfileImportServiceProvider.overrideWithValue(
          const _EmptySshProfileImportService(),
        ),
        ptySessionBackendProvider.overrideWithValue(backend),
        profileRepositoryProvider.overrideWithValue(repository),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(null),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          noIoLocalTerminalLayoutRepository(),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
      ],
      child: MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.light),
        home: const ShellScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (find.bySemanticsIdentifier('shell-tab-1').evaluate().isNotEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(find.bySemanticsIdentifier('shell-tab-1'), findsOne);
}

Future<void> _submitSavedSshSession(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-chrome-new-tab')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('new-session-launcher')), findsOne);
  await tester.tap(find.text('SSH session'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('new-custom-ssh-session')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('ssh-profile-name')),
    'Remote test host',
  );
  await tester.enterText(find.byKey(const Key('ssh-host')), 'ssh.example.test');
  await tester.enterText(find.byKey(const Key('ssh-user')), 'operator');
  await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
  await tester.tap(find.byKey(const Key('ssh-connect')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a failed SSH profile save requires an explicit one-time connection',
    (tester) async {
      final repository = _FailingRemoteProfileRepository();
      final backend = _SshFakePtyBackend();
      await _pumpShell(tester, repository, backend);
      final initialPayload = backend.lastCreatedSessionPayload;

      await _submitSavedSshSession(tester);

      expect(repository.saveAttempts, 1);
      expect(find.byKey(const Key('profile-save-failure-dialog')), findsOne);
      expect(find.text('Profile was not saved'), findsOne);
      expect(
        find.textContaining(
          '“Remote test host” was not written to profile storage',
        ),
        findsOne,
      );
      expect(
        find.textContaining(
          'Remote service rejected the save (503/service_unavailable)',
        ),
        findsOne,
      );
      expect(find.bySemanticsIdentifier('shell-tab-2'), findsNothing);

      await tester.tap(
        find.byKey(const Key('profile-save-failure-connect-once')),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 50; attempt += 1) {
        if (find.bySemanticsIdentifier('shell-tab-2').evaluate().isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(
        find.byKey(const Key('profile-save-failure-dialog')),
        findsNothing,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      expect(container.read(sessionControllerProvider).lastError, isNull);
      expect(backend.lastCreatedSessionPayload, isNot(same(initialPayload)));
    },
  );

  testWidgets('cancelling a failed SSH profile save does not connect', (
    tester,
  ) async {
    final repository = _FailingRemoteProfileRepository();
    final backend = _SshFakePtyBackend();
    await _pumpShell(tester, repository, backend);
    final initialPayload = backend.lastCreatedSessionPayload;

    await _submitSavedSshSession(tester);
    await tester.tap(find.byKey(const Key('profile-save-failure-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-save-failure-dialog')), findsNothing);
    expect(find.bySemanticsIdentifier('shell-tab-2'), findsNothing);
    expect(backend.lastCreatedSessionPayload, same(initialPayload));
  });
}
