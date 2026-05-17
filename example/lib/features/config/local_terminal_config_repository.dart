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
      return LocalTerminalConfigDocument.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on Object {
      await _quarantineCorruptFile(file);
      const repaired = LocalTerminalConfigDocument();
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
    return File('${directory.path}/flutterm_config.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
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

    return LocalTerminalConfigDocument(
      defaultProfileId: preferences.defaults.defaultProfileId,
      appearance: preferences.appearance,
    );
  }
}
