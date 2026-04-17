import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';

class _TestProfileRepository extends ProfileRepository {
  _TestProfileRepository(this._document);

  TerminalProfilesDocument _document;
  final List<TerminalProfilesDocument> savedDocuments = [];

  @override
  Future<TerminalProfilesDocument> load() async => _document;

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    savedDocuments.add(document);
    _document = document;
  }
}

class _TestAppPreferencesRepository extends AppPreferencesRepository {
  _TestAppPreferencesRepository(this._document);

  TerminalAppPreferencesDocument? _document;
  final List<TerminalAppPreferencesDocument> savedDocuments = [];

  @override
  Future<TerminalAppPreferencesDocument?> load() async => _document;

  @override
  Future<void> save(TerminalAppPreferencesDocument document) async {
    savedDocuments.add(document);
    _document = document;
  }
}

void main() {
  const defaultProfile = TerminalProfile(
    id: 'default',
    name: 'Local Shell',
    shell: '/bin/zsh',
  );
  const sshProfile = TerminalProfile(
    id: 'ssh',
    name: 'SSH',
    shell: '/usr/bin/ssh',
  );

  test('bootstrap prefers app defaults over legacy profile defaults', () async {
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(FakeCoreBindings()),
        ),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(
              defaultProfileId: 'default',
              profiles: [defaultProfile, sshProfile],
            ),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(
            const TerminalAppPreferencesDocument(
              defaults: TerminalAppDefaults(defaultProfileId: 'ssh'),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(sessionControllerProvider);
    expect(state.defaultProfileId, 'ssh');
    expect(state.tabs.single.profileId, 'ssh');
  });

  test('bootstrap falls back to legacy default when preferences are absent', () async {
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(FakeCoreBindings()),
        ),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(
              defaultProfileId: 'ssh',
              profiles: [defaultProfile, sshProfile],
            ),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(sessionControllerProvider);
    expect(state.defaultProfileId, 'ssh');
    expect(state.tabs.single.profileId, 'ssh');
  });

  test('bootstrap clears invalid persisted defaults and falls back to first profile', () async {
    final preferencesRepository = _TestAppPreferencesRepository(
      const TerminalAppPreferencesDocument(
        defaults: TerminalAppDefaults(defaultProfileId: 'missing'),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(FakeCoreBindings()),
        ),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(
              defaultProfileId: 'ssh',
              profiles: [defaultProfile, sshProfile],
            ),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          preferencesRepository,
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(sessionControllerProvider);
    expect(state.defaultProfileId, 'default');
    expect(state.tabs.single.profileId, 'default');
    expect(preferencesRepository.savedDocuments, hasLength(1));
    expect(
      preferencesRepository.savedDocuments.single.defaults.defaultProfileId,
      isNull,
    );
  });

  test('bootstrap falls back to built-in default when no catalog profiles exist', () async {
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(FakeCoreBindings()),
        ),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(sessionControllerProvider);
    expect(state.defaultProfileId, defaultTerminalProfile().id);
    expect(state.tabs.single.profileId, defaultTerminalProfile().id);
    expect(state.tabs.single.title, defaultTerminalProfile().name);
  });

  test('setDefaultProfile writes only app preferences during the compatibility window', () async {
    final profileRepository = _TestProfileRepository(
      const TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultProfile, sshProfile],
      ),
    );
    final preferencesRepository = _TestAppPreferencesRepository(null);
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(
          TerminalCoreClient(FakeCoreBindings()),
        ),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        appPreferencesRepositoryProvider.overrideWithValue(
          preferencesRepository,
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await container.read(sessionControllerProvider.notifier).setDefaultProfile(
      'ssh',
    );

    expect(preferencesRepository.savedDocuments, hasLength(1));
    expect(
      preferencesRepository.savedDocuments.single.defaults.defaultProfileId,
      'ssh',
    );
    expect(profileRepository.savedDocuments, isEmpty);
  });
}
