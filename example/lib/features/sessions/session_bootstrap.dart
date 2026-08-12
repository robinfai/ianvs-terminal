import '../config/local_terminal_config_bootstrap.dart';
import '../config/local_terminal_config_loader.dart';
import '../config/local_terminal_config_models.dart';
import '../config/local_terminal_config_repository.dart';
import '../persistence/versioned_document.dart';
import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';
import '../profiles/profile_repository.dart';

class SessionBootstrapPreparation {
  SessionBootstrapPreparation({
    required List<TerminalProfile> profiles,
    required List<TerminalProfileLoadWarning> configurationWarnings,
    required this.appPreferences,
    required this.localConfig,
    required this.configSource,
    required this.preferencesLoadedFromDisk,
    required this.effectiveDefaultProfileId,
    required this.profileDocument,
    required this.appPreferencesDocument,
    required this.localConfigDocument,
  }) : profiles = List.unmodifiable(profiles),
       configurationWarnings = List.unmodifiable(configurationWarnings);

  final List<TerminalProfile> profiles;
  final List<TerminalProfileLoadWarning> configurationWarnings;
  final TerminalAppPreferencesDocument appPreferences;
  final LocalTerminalConfigDocument localConfig;
  final LocalTerminalConfigBootstrapSource configSource;
  final bool preferencesLoadedFromDisk;
  final String? effectiveDefaultProfileId;
  final VersionedDocument<TerminalProfilesDocument> profileDocument;
  final VersionedDocument<TerminalAppPreferencesDocument>
  appPreferencesDocument;
  final VersionedDocument<LocalTerminalConfigDocument> localConfigDocument;
}

class SessionBootstrapService {
  const SessionBootstrapService({
    required this.profileRepository,
    required this.localConfigRepository,
    required this.localConfigLoader,
  });

  final ProfileRepositoryPort profileRepository;
  final TerminalConfigRepository localConfigRepository;
  final LocalTerminalConfigLoader localConfigLoader;

  Future<SessionBootstrapPreparation> prepare({
    String? explicitDefaultProfileId,
  }) async {
    final loadedProfiles = await profileRepository.loadVersioned();
    final profiles = loadedProfiles.value.profiles.isEmpty
        ? <TerminalProfile>[defaultTerminalProfile()]
        : loadedProfiles.value.profiles;
    final configBootstrap = await _loadConfig();
    var localConfig = configBootstrap.config;
    final seededPreferences = _preferencesFromCurrentConfig(localConfig);
    final resolution = _resolvePreferences(
      profiles: profiles,
      preferences: seededPreferences,
      explicitDefaultProfileId: explicitDefaultProfileId,
    );
    var preferencesLoadedFromDisk =
        configBootstrap.source != LocalTerminalConfigBootstrapSource.defaults;

    var localConfigDocument = VersionedDocument<LocalTerminalConfigDocument>(
      value: localConfig,
      revision: configBootstrap.localConfigRevision,
    );
    final appPreferencesDocument =
        VersionedDocument<TerminalAppPreferencesDocument>(
          value: resolution.preferences,
          revision: null,
        );
    if (resolution.shouldRepairWritePreferences) {
      localConfig = localConfig.copyWith(
        defaultProfileId: resolution.preferences.defaults.defaultProfileId,
      );
      localConfigDocument = await localConfigRepository.saveVersioned(
        localConfigDocument.withValue(localConfig),
      );
      preferencesLoadedFromDisk = true;
    }

    return SessionBootstrapPreparation(
      profiles: profiles,
      configurationWarnings: loadedProfiles.value.loadWarnings,
      appPreferences: resolution.preferences,
      localConfig: localConfig,
      configSource: configBootstrap.source,
      preferencesLoadedFromDisk: preferencesLoadedFromDisk,
      effectiveDefaultProfileId: resolution.effectiveDefaultProfileId,
      profileDocument: loadedProfiles.withValue(
        TerminalProfilesDocument(
          schemaVersion: loadedProfiles.value.schemaVersion,
          profiles: profiles,
          loadWarnings: loadedProfiles.value.loadWarnings,
          secretClearIntents: loadedProfiles.value.secretClearIntents,
        ),
      ),
      appPreferencesDocument: appPreferencesDocument,
      localConfigDocument: localConfigDocument,
    );
  }

  Future<LocalTerminalConfigBootstrapResult> _loadConfig() =>
      localConfigLoader.load();
}

TerminalAppPreferencesDocument _preferencesFromCurrentConfig(
  LocalTerminalConfigDocument config,
) {
  return TerminalAppPreferencesDocument(
    defaults: TerminalAppDefaults(defaultProfileId: config.defaultProfileId),
    appearance: config.appearance,
    notifications: TerminalAppNotifications(
      commandFinished: config.notifications.commandFinished,
      bell: config.notifications.bell,
      activity: config.notifications.activity,
    ),
  );
}

sealed class SessionBootstrapOutcome {
  const SessionBootstrapOutcome();
}

final class SessionBootstrapSuccess extends SessionBootstrapOutcome {
  const SessionBootstrapSuccess({required this.started});

  final bool started;
}

final class SessionBootstrapFailure extends SessionBootstrapOutcome {
  const SessionBootstrapFailure({
    required this.error,
    required this.stackTrace,
    required this.reportedToMountedConsumer,
  });

  final Object error;
  final StackTrace stackTrace;
  final bool reportedToMountedConsumer;
}

class SessionBootstrapRunner {
  bool _isRunning = false;

  Future<SessionBootstrapOutcome> run({
    required bool Function() isMounted,
    required void Function() onStarted,
    required Future<void> Function() operation,
    required void Function(Object error, StackTrace stackTrace) onFailed,
  }) async {
    if (_isRunning || !isMounted()) {
      return const SessionBootstrapSuccess(started: false);
    }
    _isRunning = true;
    try {
      onStarted();
      await operation();
      return const SessionBootstrapSuccess(started: true);
    } on Object catch (error, stackTrace) {
      final reportedToMountedConsumer = isMounted();
      if (reportedToMountedConsumer) {
        onFailed(error, stackTrace);
      }
      return SessionBootstrapFailure(
        error: error,
        stackTrace: stackTrace,
        reportedToMountedConsumer: reportedToMountedConsumer,
      );
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
