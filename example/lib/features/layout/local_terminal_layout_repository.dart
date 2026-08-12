import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import '../persistence/versioned_document.dart';
import 'local_terminal_layout_models.dart';

typedef LocalTerminalLayoutDirectoryResolver = Future<Directory> Function();

abstract class TerminalLayoutRepository {
  const TerminalLayoutRepository();

  Future<TerminalLayout?> load();

  Future<void> save(TerminalLayout layout);

  Future<VersionedDocument<TerminalLayout?>> loadVersioned() async {
    return VersionedDocument<TerminalLayout?>.local(await load());
  }

  Future<VersionedDocument<TerminalLayout>> saveVersioned(
    VersionedDocument<TerminalLayout> layout,
  ) async {
    await save(layout.value);
    return layout.withRevision(null);
  }
}

/// Persists the single current local Terminal Layout document.
class LocalTerminalLayoutRepository extends TerminalLayoutRepository {
  LocalTerminalLayoutRepository({
    LocalTerminalLayoutDirectoryResolver? directoryResolver,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalTerminalLayoutDirectoryResolver _directoryResolver;

  @override
  Future<TerminalLayout?> load() async {
    final directory = await _directoryResolver();
    final currentFile = _layoutFile(directory);
    if (!await currentFile.exists()) {
      return null;
    }
    return _loadCurrent(currentFile);
  }

  @override
  Future<void> save(TerminalLayout layout) async {
    final directory = await _directoryResolver();
    await writeStringAtomically(
      _layoutFile(directory),
      jsonEncode(layout.toJson()),
    );
  }

  Future<TerminalLayout> _loadCurrent(File file) async {
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<Object?, Object?>) {
        throw const UnsupportedTerminalLayoutSchemaVersion(null);
      }
      return TerminalLayout.fromJson(decoded);
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = TerminalLayout();
      await save(repaired);
      return repaired;
    }
  }

  File _layoutFile(Directory directory) {
    return File('${directory.path}/ianvs_terminal_layout.json');
  }
}
