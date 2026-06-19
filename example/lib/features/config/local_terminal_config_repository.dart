import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../preferences/app_preferences_models.dart';
import 'local_terminal_config_models.dart';

typedef LocalTerminalConfigDirectoryResolver = Future<Directory> Function();

class LocalTerminalConfigRepository {
  LocalTerminalConfigRepository({
    LocalTerminalConfigDirectoryResolver? directoryResolver,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalTerminalConfigDirectoryResolver _directoryResolver;

  Future<LocalTerminalConfigDocument?> load() async {
    final file = await _configFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, Object?>;
      final document = LocalTerminalConfigDocument.fromJson(json);
      return LocalTerminalConfigMigration.withRuntimeDefaultsForMissingLocalKeys(
        document,
        json,
      );
    } on Object {
      await _quarantineCorruptFile(file);
      const repaired = LocalTerminalConfigMigration.runtimeDefaults;
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(LocalTerminalConfigDocument document) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(document.encode());
  }

  Future<File> _configFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_config.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
  }
}

class LocalTerminalConfigMigration {
  const LocalTerminalConfigMigration._();

  static const runtimeDefaultCommandCenter = LocalTerminalCommandCenterConfig(
    enabled: true,
    historySearch: true,
    commandBlocks: true,
    commandBar: true,
    contextChips: true,
    reviewEntrypoints: true,
    verificationDiagnostics: true,
    agentCenter: true,
    agentConversation: true,
    agentContext: true,
    agentCommandProposals: true,
    agentProviderDraft: true,
    agentCommandSearchActions: true,
  );

  static const runtimeDefaultCommandBlocksHistory =
      LocalTerminalCommandBlocksHistoryConfig(
        enabled: true,
        commandBlocks: true,
        failureSnapshots: true,
        reviewWorkspaceEntrypoints: true,
        outputDiff: true,
      );

  static const runtimeDefaults = LocalTerminalConfigDocument(
    commandCenter: runtimeDefaultCommandCenter,
    commandBlocksHistory: runtimeDefaultCommandBlocksHistory,
  );

  static LocalTerminalConfigDocument fromLegacyAppPreferences(
    TerminalAppPreferencesDocument? preferences,
  ) {
    if (preferences == null) {
      return const LocalTerminalConfigDocument();
    }

    final notifications = preferences.notifications;
    return LocalTerminalConfigDocument(
      defaultProfileId: preferences.defaults.defaultProfileId,
      appearance: preferences.appearance,
      notifications: LocalTerminalNotificationsConfig(
        enabled:
            notifications.commandFinished ||
            notifications.bell ||
            notifications.activity,
        commandFinished: notifications.commandFinished,
        bell: notifications.bell,
        activity: notifications.activity,
      ),
    );
  }

  static LocalTerminalConfigDocument withRuntimeDefaults(
    LocalTerminalConfigDocument document,
  ) {
    return document.copyWith(
      commandCenter: runtimeDefaultCommandCenter,
      commandBlocksHistory: runtimeDefaultCommandBlocksHistory,
    );
  }

  static LocalTerminalConfigDocument withRuntimeDefaultsForMissingLocalKeys(
    LocalTerminalConfigDocument document,
    Map<String, Object?> json,
  ) {
    return document.copyWith(
      commandCenter: json.containsKey('commandCenter')
          ? _commandCenterWithRuntimeDefaultsForMissingKeys(
              document.commandCenter,
              json['commandCenter'],
            )
          : runtimeDefaultCommandCenter,
      commandBlocksHistory: json.containsKey('commandBlocksHistory')
          ? document.commandBlocksHistory
          : runtimeDefaultCommandBlocksHistory,
    );
  }

  static LocalTerminalCommandCenterConfig
  _commandCenterWithRuntimeDefaultsForMissingKeys(
    LocalTerminalCommandCenterConfig config,
    Object? rawCommandCenter,
  ) {
    final json = rawCommandCenter is Map
        ? rawCommandCenter.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    return LocalTerminalCommandCenterConfig(
      enabled: config.enabled,
      historySearch: config.historySearch,
      commandBlocks: config.commandBlocks,
      commandBar: config.commandBar,
      contextChips: config.contextChips,
      reviewEntrypoints: config.reviewEntrypoints,
      verificationDiagnostics: config.verificationDiagnostics,
      agentCenter: json.containsKey('agentCenter')
          ? config.agentCenter
          : runtimeDefaultCommandCenter.agentCenter,
      agentConversation: json.containsKey('agentConversation')
          ? config.agentConversation
          : runtimeDefaultCommandCenter.agentConversation,
      agentContext: json.containsKey('agentContext')
          ? config.agentContext
          : runtimeDefaultCommandCenter.agentContext,
      agentCommandProposals: json.containsKey('agentCommandProposals')
          ? config.agentCommandProposals
          : runtimeDefaultCommandCenter.agentCommandProposals,
      agentProviderDraft: json.containsKey('agentProviderDraft')
          ? config.agentProviderDraft
          : runtimeDefaultCommandCenter.agentProviderDraft,
      agentCommandSearchActions: json.containsKey('agentCommandSearchActions')
          ? config.agentCommandSearchActions
          : runtimeDefaultCommandCenter.agentCommandSearchActions,
    );
  }
}
