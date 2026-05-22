import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/sessions/session_controller.dart';

import '../support/fake_pty_backend.dart';

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
  final defaultProfile = TerminalProfile(
    id: 'default',
    name: 'Local Shell',
    shell: '/bin/zsh',
  );
  final sshProfile = TerminalProfile(
    id: 'ssh',
    name: 'SSH',
    shell: '/usr/bin/ssh',
  );

  test('bootstrap prefers app defaults over legacy profile defaults', () async {
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
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
    expect(state.configuredDefaultProfileId, 'ssh');
    expect(state.themeMode, TerminalThemeMode.system);
    expect(state.tabs.single.profileId, 'ssh');
  });

  test(
    'bootstrap ignores legacy profile defaults when preferences are absent',
    () async {
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
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
      expect(state.defaultProfileId, 'default');
      expect(state.configuredDefaultProfileId, isNull);
      expect(state.tabs.single.profileId, 'default');
    },
  );

  test(
    'bootstrap clears invalid persisted defaults and falls back to first profile',
    () async {
      final preferencesRepository = _TestAppPreferencesRepository(
        const TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(defaultProfileId: 'missing'),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
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
      expect(state.configuredDefaultProfileId, isNull);
      expect(state.tabs.single.profileId, 'default');
      expect(preferencesRepository.savedDocuments, hasLength(1));
      expect(
        preferencesRepository.savedDocuments.single.defaults.defaultProfileId,
        isNull,
      );
    },
  );

  test(
    'bootstrap falls back to built-in default when no catalog profiles exist',
    () async {
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
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
      expect(state.configuredDefaultProfileId, isNull);
      expect(state.themeMode, TerminalThemeMode.system);
      expect(state.tabs.single.profileId, defaultTerminalProfile().id);
      expect(state.tabs.single.title, defaultTerminalProfile().name);
    },
  );

  test(
    'setDefaultProfile writes only app preferences during the compatibility window',
    () async {
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final preferencesRepository = _TestAppPreferencesRepository(null);
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await container
          .read(sessionControllerProvider.notifier)
          .setDefaultProfile('ssh');

      expect(preferencesRepository.savedDocuments, hasLength(1));
      expect(
        preferencesRepository.savedDocuments.single.defaults.defaultProfileId,
        'ssh',
      );
      expect(profileRepository.savedDocuments, isEmpty);
      final state = container.read(sessionControllerProvider);
      expect(state.configuredDefaultProfileId, 'ssh');
      expect(state.defaultProfileId, 'ssh');
    },
  );

  test(
    'saveProfile keeps legacy default ids out of steady-state profile writes',
    () async {
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final preferencesRepository = _TestAppPreferencesRepository(null);
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await container
          .read(sessionControllerProvider.notifier)
          .saveProfile(sshProfile.copyWith(name: 'SSH Updated'));

      expect(profileRepository.savedDocuments, hasLength(1));
      expect(
        profileRepository.savedDocuments.single.toJson().containsKey(
          'defaultProfileId',
        ),
        isFalse,
      );
      expect(
        profileRepository.savedDocuments.single.profiles
            .firstWhere((profile) => profile.id == 'ssh')
            .name,
        'SSH Updated',
      );
      final state = container.read(sessionControllerProvider);
      expect(state.defaultProfileId, 'default');
      expect(state.configuredDefaultProfileId, isNull);
      expect(preferencesRepository.savedDocuments, isEmpty);
    },
  );

  test(
    'resetDefaultProfile clears configured intent and falls back deterministically',
    () async {
      final preferencesRepository = _TestAppPreferencesRepository(
        const TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(defaultProfileId: 'ssh'),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
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
      await container
          .read(sessionControllerProvider.notifier)
          .resetDefaultProfile();

      final state = container.read(sessionControllerProvider);
      expect(state.configuredDefaultProfileId, isNull);
      expect(state.defaultProfileId, 'default');
      expect(
        preferencesRepository.savedDocuments.last.defaults.defaultProfileId,
        isNull,
      );
    },
  );

  test(
    'setThemeMode and resetThemeMode persist the selected appearance mode',
    () async {
      final preferencesRepository = _TestAppPreferencesRepository(null);
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
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
      await container
          .read(sessionControllerProvider.notifier)
          .setThemeMode(TerminalThemeMode.dark);

      expect(
        container.read(sessionControllerProvider).themeMode,
        TerminalThemeMode.dark,
      );
      expect(
        preferencesRepository.savedDocuments.last.appearance.themeMode,
        TerminalThemeMode.dark,
      );

      await container.read(sessionControllerProvider.notifier).resetThemeMode();

      expect(
        container.read(sessionControllerProvider).themeMode,
        TerminalThemeMode.system,
      );
      expect(
        preferencesRepository.savedDocuments.last.appearance.themeMode,
        TerminalThemeMode.system,
      );
    },
  );

  test('setTerminalViewportPadding persists the shell inset', () async {
    final preferencesRepository = _TestAppPreferencesRepository(null);
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
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
    await container
        .read(sessionControllerProvider.notifier)
        .setTerminalViewportPadding(22);

    expect(
      container.read(sessionControllerProvider).terminalViewportPadding,
      22,
    );
    expect(
      preferencesRepository
          .savedDocuments
          .last
          .appearance
          .terminalViewportPadding,
      22,
    );
  });
}
