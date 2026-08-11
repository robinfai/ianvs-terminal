import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import '../preferences/app_preferences_models.dart';
import 'local_terminal_config_models.dart';

typedef LocalTerminalConfigDirectoryResolver = Future<Directory> Function();

class LocalTerminalConfigRepository {
  LocalTerminalConfigRepository({
    LocalTerminalConfigDirectoryResolver? directoryResolver,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalTerminalConfigDirectoryResolver _directoryResolver;
  Future<void> _updateQueue = Future<void>.value();

  Future<LocalTerminalConfigDocument?> load() async {
    final file = await _configFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      final json = decodeJsonObject(raw, documentName: 'Local terminal config');
      final document = LocalTerminalConfigDocument.fromJson(json);
      if (json.containsKey('workspace') ||
          json['schemaVersion'] !=
              LocalTerminalConfigDocument.currentSchemaVersion) {
        await save(document);
      }
      return document;
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = LocalTerminalConfigDocument(
        layout: LocalTerminalLayoutConfig(restoreLayout: false),
      );
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(LocalTerminalConfigDocument document) async {
    final file = await _configFile();
    await writeStringAtomically(file, document.encode());
  }

  /// Applies a read-modify-write transaction after all previously scheduled
  /// updates have completed.
  ///
  /// Callers that change only part of the document should use this method
  /// instead of a separate [load]/[save] pair. Atomic file replacement keeps
  /// individual writes intact; this queue additionally prevents two feature
  /// controllers from overwriting each other's newer fields.
  Future<LocalTerminalConfigDocument> update(
    LocalTerminalConfigDocument Function(LocalTerminalConfigDocument current)
    transform, {
    LocalTerminalConfigDocument fallback = const LocalTerminalConfigDocument(),
  }) {
    final operation = _updateQueue.then((_) async {
      final current = await load() ?? fallback;
      final next = transform(current);
      await save(next);
      return next;
    });
    _updateQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<File> _configFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_config.json');
  }
}

class LocalTerminalConfigMigration {
  const LocalTerminalConfigMigration._();

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
      layout: const LocalTerminalLayoutConfig(restoreLayout: false),
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
}
