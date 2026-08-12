import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import '../persistence/versioned_document.dart';
import 'local_terminal_config_models.dart';

typedef LocalTerminalConfigDirectoryResolver = Future<Directory> Function();

abstract class TerminalConfigRepository {
  const TerminalConfigRepository();

  Future<LocalTerminalConfigDocument?> load();

  Future<void> save(LocalTerminalConfigDocument document);

  Future<VersionedDocument<LocalTerminalConfigDocument?>>
  loadVersioned() async {
    return VersionedDocument<LocalTerminalConfigDocument?>.local(await load());
  }

  Future<VersionedDocument<LocalTerminalConfigDocument>> saveVersioned(
    VersionedDocument<LocalTerminalConfigDocument> document,
  ) async {
    await save(document.value);
    return document.withRevision(null);
  }

  Future<LocalTerminalConfigDocument> update(
    LocalTerminalConfigDocument Function(LocalTerminalConfigDocument current)
    transform, {
    LocalTerminalConfigDocument fallback = const LocalTerminalConfigDocument(),
  });
}

class LocalTerminalConfigRepository extends TerminalConfigRepository {
  LocalTerminalConfigRepository({
    LocalTerminalConfigDirectoryResolver? directoryResolver,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalTerminalConfigDirectoryResolver _directoryResolver;
  Future<void> _updateQueue = Future<void>.value();

  @override
  Future<LocalTerminalConfigDocument?> load() async {
    final file = await _configFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const UnsupportedLocalTerminalConfigSchemaVersion(null);
      }
      final version = decoded['schemaVersion'];
      if (version != LocalTerminalConfigDocument.currentSchemaVersion) {
        throw UnsupportedLocalTerminalConfigSchemaVersion(version);
      }
      return LocalTerminalConfigDocument.fromJson(decoded);
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = LocalTerminalConfigDocument(
        layout: LocalTerminalLayoutConfig(restoreLayout: false),
      );
      await save(repaired);
      return repaired;
    }
  }

  @override
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
  @override
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
