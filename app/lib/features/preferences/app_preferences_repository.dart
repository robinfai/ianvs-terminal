import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_preferences_models.dart';

typedef AppPreferencesDirectoryResolver = Future<Directory> Function();

class AppPreferencesRepository {
  AppPreferencesRepository({AppPreferencesDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final AppPreferencesDirectoryResolver _directoryResolver;

  Future<TerminalAppPreferencesDocument?> load() async {
    final file = await _preferencesFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      return TerminalAppPreferencesDocument.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on Object {
      await _quarantineCorruptFile(file);
      const repaired = TerminalAppPreferencesDocument();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(TerminalAppPreferencesDocument document) async {
    final file = await _preferencesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(document.encode());
  }

  Future<File> _preferencesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/flutterm_preferences.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
  }
}
