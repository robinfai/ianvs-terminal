import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import '../persistence/versioned_document.dart';
import 'app_preferences_models.dart';

typedef AppPreferencesDirectoryResolver = Future<Directory> Function();

abstract class AppPreferencesRepositoryPort {
  const AppPreferencesRepositoryPort();

  Future<TerminalAppPreferencesDocument?> load();

  Future<void> save(TerminalAppPreferencesDocument document);

  Future<VersionedDocument<TerminalAppPreferencesDocument?>>
  loadVersioned() async {
    return VersionedDocument<TerminalAppPreferencesDocument?>.local(
      await load(),
    );
  }

  Future<VersionedDocument<TerminalAppPreferencesDocument>> saveVersioned(
    VersionedDocument<TerminalAppPreferencesDocument> document,
  ) async {
    await save(document.value);
    return document.withRevision(null);
  }
}

class AppPreferencesRepository extends AppPreferencesRepositoryPort {
  AppPreferencesRepository({AppPreferencesDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final AppPreferencesDirectoryResolver _directoryResolver;

  @override
  Future<TerminalAppPreferencesDocument?> load() async {
    final file = await _preferencesFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const UnsupportedTerminalAppPreferencesSchemaVersion(null);
      }
      return TerminalAppPreferencesDocument.fromJson(decoded);
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = TerminalAppPreferencesDocument();
      await save(repaired);
      return repaired;
    }
  }

  @override
  Future<void> save(TerminalAppPreferencesDocument document) async {
    final file = await _preferencesFile();
    await writeStringAtomically(file, document.encode());
  }

  Future<File> _preferencesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_preferences.json');
  }
}
