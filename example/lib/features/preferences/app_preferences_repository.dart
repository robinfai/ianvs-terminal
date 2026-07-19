import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
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
        decodeJsonObject(raw, documentName: 'App preferences'),
      );
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = TerminalAppPreferencesDocument();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(TerminalAppPreferencesDocument document) async {
    final file = await _preferencesFile();
    await writeStringAtomically(file, document.encode());
  }

  Future<File> _preferencesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_preferences.json');
  }
}
