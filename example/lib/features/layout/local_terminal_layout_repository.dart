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

/// Persists one local Terminal Layout.
///
/// The former project-keyed Workspace collection remains read-only migration
/// input. New writes never create project identity, recent-project indexes, or
/// per-project layout documents.
class LocalTerminalLayoutRepository extends TerminalLayoutRepository {
  LocalTerminalLayoutRepository({
    LocalTerminalLayoutDirectoryResolver? directoryResolver,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalTerminalLayoutDirectoryResolver _directoryResolver;

  @override
  Future<TerminalLayout?> load() async {
    final directory = await _directoryResolver();
    final currentFile = _layoutFile(directory);
    if (await currentFile.exists()) {
      return _loadCurrent(currentFile);
    }

    final legacy = await _loadLegacyWorkspace(directory);
    if (legacy != null) {
      await save(legacy);
    }
    return legacy;
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
      return TerminalLayout.fromJson(
        decodeJsonObject(raw, documentName: 'Terminal layout'),
      );
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = TerminalLayout();
      await save(repaired);
      return repaired;
    }
  }

  Future<TerminalLayout?> _loadLegacyWorkspace(Directory directory) async {
    final collectionCandidates = await _legacyCollectionCandidates(directory);
    for (final workspaceId in collectionCandidates) {
      final file = _legacyCollectionFile(directory, workspaceId);
      final migrated = await _tryLoadLegacyFile(file);
      if (migrated != null) {
        return migrated;
      }
    }
    return _tryLoadLegacyFile(_legacyAliasFile(directory));
  }

  Future<List<String>> _legacyCollectionCandidates(Directory directory) async {
    final file = _legacyIndexFile(directory);
    if (!await file.exists()) {
      return const <String>[];
    }
    try {
      final index = decodeJsonObject(
        await file.readAsString(),
        documentName: 'Legacy Workspace index',
      );
      final ids = <String>{};
      final current = _nonEmptyString(index['currentWorkspaceId']);
      if (current != null) {
        ids.add(current);
      }
      final recent = index['recent'];
      if (recent is List) {
        for (final value in recent.take(40)) {
          if (value is! Map) {
            continue;
          }
          final id = _nonEmptyString(value['id']);
          if (id != null) {
            ids.add(id);
          }
        }
      }
      return ids.toList(growable: false);
    } on FormatException {
      await quarantineCorruptFile(file);
      return const <String>[];
    }
  }

  Future<TerminalLayout?> _tryLoadLegacyFile(File file) async {
    if (!await file.exists()) {
      return null;
    }
    try {
      final raw = await file.readAsString();
      return TerminalLayout.fromLegacyWorkspaceJson(
        decodeJsonObject(raw, documentName: 'Legacy Workspace layout'),
      );
    } on FormatException {
      await quarantineCorruptFile(file);
      return null;
    }
  }

  File _layoutFile(Directory directory) {
    return File('${directory.path}/ianvs_terminal_layout.json');
  }

  File _legacyAliasFile(Directory directory) {
    return File('${directory.path}/ianvs_workspace_layout.json');
  }

  File _legacyIndexFile(Directory directory) {
    return File('${directory.path}/ianvs_workspace_index.json');
  }

  File _legacyCollectionFile(Directory directory, String workspaceId) {
    final encodedId = base64Url
        .encode(utf8.encode(workspaceId))
        .replaceAll('=', '');
    if (encodedId.isEmpty || encodedId.length > 180) {
      throw const FormatException('Legacy Workspace id is invalid.');
    }
    return File('${directory.path}/ianvs_workspaces/workspace-$encodedId.json');
  }
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
