import '../config/local_terminal_config_bootstrap.dart';
import '../config/local_terminal_config_loader.dart';
import '../config/local_terminal_config_models.dart';
import '../config/local_terminal_config_preferences_adapter.dart';
import '../config/local_terminal_config_repository.dart';
import '../preferences/app_preferences_models.dart';
import '../preferences/app_preferences_repository.dart';
import '../profiles/profile_models.dart';
import '../profiles/profile_repository.dart';

typedef LocalConfigFallbackPolicy = bool Function(Object error);

class SessionBootstrapPreparation {
  SessionBootstrapPreparation({
    required List<TerminalProfile> profiles,
    required List<TerminalProfileLoadWarning> configurationWarnings,
    required this.appPreferences,
    required this.localConfig,
    required this.configSource,
    required this.preferencesLoadedFromDisk,
    required this.effectiveDefaultProfileId,
  }) : profiles = List.unmodifiable(profiles),
       configurationWarnings = List.unmodifiable(configurationWarnings);

  final List<TerminalProfile> profiles;
  final List<TerminalProfileLoadWarning> configurationWarnings;
  final TerminalAppPreferencesDocument appPreferences;
  final LocalTerminalConfigDocument localConfig;
  final LocalTerminalConfigBootstrapSource configSource;
  final bool preferencesLoadedFromDisk;
  final String? effectiveDefaultProfileId;
}

class SessionBootstrapService {
  const SessionBootstrapService({
    required this.profileRepository,
    required this.appPreferencesRepository,
    required this.localConfigRepository,
    required this.localConfigLoader,
    this.shouldFallbackToLegacyPreferences = _neverFallback,
  });

  final ProfileRepository profileRepository;
  final AppPreferencesRepository appPreferencesRepository;
  final LocalTerminalConfigRepository localConfigRepository;
  final LocalTerminalConfigLoader localConfigLoader;
  final LocalConfigFallbackPolicy shouldFallbackToLegacyPreferences;

  Future<SessionBootstrapPreparation> prepare({
    String? explicitDefaultProfileId,
  }) async {
    final profilesDocument = await profileRepository.load();
    final profiles = profilesDocument.profiles.isEmpty
        ? <TerminalProfile>[defaultTerminalProfile()]
        : profilesDocument.profiles;
    final configBootstrap = await _loadConfig();
    var localConfig = configBootstrap.config;
    final seededPreferences =
        LocalTerminalConfigPreferencesAdapter.toAppPreferences(localConfig);
    final resolution = _resolvePreferences(
      profiles: profiles,
      preferences: seededPreferences,
      explicitDefaultProfileId: explicitDefaultProfileId,
    );
    var preferencesLoadedFromDisk =
        configBootstrap.source != LocalTerminalConfigBootstrapSource.defaults;

    if (resolution.shouldRepairWritePreferences) {
      if (configBootstrap.source ==
          LocalTerminalConfigBootstrapSource.localConfig) {
        localConfig = localConfig.copyWith(
          defaultProfileId: resolution.preferences.defaults.defaultProfileId,
        );
        await localConfigRepository.save(localConfig);
      } else {
        await appPreferencesRepository.save(resolution.preferences);
      }
      preferencesLoadedFromDisk = true;
    }

    return SessionBootstrapPreparation(
      profiles: profiles,
      configurationWarnings: profilesDocument.loadWarnings,
      appPreferences: resolution.preferences,
      localConfig: localConfig,
      configSource: configBootstrap.source,
      preferencesLoadedFromDisk: preferencesLoadedFromDisk,
      effectiveDefaultProfileId: resolution.effectiveDefaultProfileId,
    );
  }

  Future<LocalTerminalConfigBootstrapResult> _loadConfig() async {
    try {
      return await localConfigLoader.load();
    } on Object catch (error) {
      if (!shouldFallbackToLegacyPreferences(error)) {
        rethrow;
      }
      final legacyPreferences = await appPreferencesRepository.load();
      return LocalTerminalConfigBootstrap.resolve(
        localConfig: null,
        legacyAppPreferences: legacyPreferences,
      );
    }
  }
}

class SessionBootstrapRunner {
  bool _isRunning = false;

  Future<void> run({
    required bool Function() isMounted,
    required void Function() onStarted,
    required Future<void> Function() operation,
    required void Function(Object error, StackTrace stackTrace) onFailed,
  }) async {
    if (_isRunning || !isMounted()) {
      return;
    }
    _isRunning = true;
    try {
      onStarted();
      await operation();
    } on Object catch (error, stackTrace) {
      if (isMounted()) {
        onFailed(error, stackTrace);
      }
    } finally {
      _isRunning = false;
    }
  }
}

_SessionBootstrapPreferencesResolution _resolvePreferences({
  required List<TerminalProfile> profiles,
  required TerminalAppPreferencesDocument preferences,
  required String? explicitDefaultProfileId,
}) {
  final explicitDefaultId = _normalizeProfileId(explicitDefaultProfileId);
  if (_hasProfileId(profiles, explicitDefaultId)) {
    return _SessionBootstrapPreferencesResolution(
      effectiveDefaultProfileId: explicitDefaultId,
      preferences: preferences,
    );
  }

  final preferencesDefaultId = _normalizeProfileId(
    preferences.defaults.defaultProfileId,
  );
  if (_hasProfileId(profiles, preferencesDefaultId)) {
    return _SessionBootstrapPreferencesResolution(
      effectiveDefaultProfileId: preferencesDefaultId,
      preferences: preferences,
    );
  }

  if (preferencesDefaultId != null) {
    final repairedPreferences = preferences.copyWith(
      defaults: preferences.defaults.copyWith(defaultProfileId: null),
    );
    return _SessionBootstrapPreferencesResolution(
      effectiveDefaultProfileId: profiles.isEmpty ? null : profiles.first.id,
      preferences: repairedPreferences,
      shouldRepairWritePreferences: true,
    );
  }

  return _SessionBootstrapPreferencesResolution(
    effectiveDefaultProfileId: profiles.isEmpty ? null : profiles.first.id,
    preferences: preferences,
  );
}

String? _normalizeProfileId(String? profileId) {
  final normalized = profileId?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

bool _hasProfileId(List<TerminalProfile> profiles, String? profileId) {
  if (profileId == null) {
    return false;
  }
  return profiles.any((profile) => profile.id == profileId);
}

class _SessionBootstrapPreferencesResolution {
  const _SessionBootstrapPreferencesResolution({
    required this.effectiveDefaultProfileId,
    required this.preferences,
    this.shouldRepairWritePreferences = false,
  });

  final String? effectiveDefaultProfileId;
  final TerminalAppPreferencesDocument preferences;
  final bool shouldRepairWritePreferences;
}

bool _neverFallback(Object error) => false;
