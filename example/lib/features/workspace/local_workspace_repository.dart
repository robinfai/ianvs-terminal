import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import 'local_workspace_models.dart';

typedef LocalWorkspaceDirectoryResolver = Future<Directory> Function();
typedef LocalWorkspaceClock = DateTime Function();

class LocalWorkspaceRepository {
  LocalWorkspaceRepository({
    LocalWorkspaceDirectoryResolver? directoryResolver,
    LocalWorkspaceClock? now,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  final LocalWorkspaceDirectoryResolver _directoryResolver;
  final LocalWorkspaceClock _now;

  Future<TerminalWorkspace?> load() async {
    final directory = await _directoryResolver();
    final index = await _loadIndex(directory);
    if (index != null) {
      final workspaceIds = <String>{
        ?index.currentWorkspaceId,
        for (final entry in index.recent) entry.identity.id,
      };
      for (final workspaceId in workspaceIds) {
        final workspace = await _loadWorkspaceDocument(directory, workspaceId);
        if (workspace == null) {
          continue;
        }
        await _activateWorkspace(directory, workspace, index: index);
        return workspace;
      }
    }
    return _loadLegacyWorkspace(directory);
  }

  Future<TerminalWorkspace?> loadWorkspace(String workspaceId) async {
    final normalizedId = _normalizedWorkspaceId(workspaceId);
    if (normalizedId == null) {
      return null;
    }
    final directory = await _directoryResolver();
    return _loadWorkspaceDocument(directory, normalizedId);
  }

  Future<TerminalWorkspace?> openWorkspace(String workspaceId) async {
    final normalizedId = _normalizedWorkspaceId(workspaceId);
    if (normalizedId == null) {
      return null;
    }
    final directory = await _directoryResolver();
    final index = await _loadIndex(directory) ?? const TerminalWorkspaceIndex();
    final workspace = await _loadWorkspaceDocument(directory, normalizedId);
    if (workspace == null) {
      return null;
    }
    await _activateWorkspace(directory, workspace, index: index);
    return workspace;
  }

  Future<TerminalWorkspace> openProject({
    required String projectPath,
    String? name,
  }) async {
    final workspace = await loadOrCreateProject(
      projectPath: projectPath,
      name: name,
    );
    await activateWorkspace(workspace);
    return workspace;
  }

  Future<TerminalWorkspace> loadOrCreateProject({
    required String projectPath,
    String? name,
  }) async {
    final identity = TerminalWorkspaceIdentity.forProject(
      projectPath,
      name: name,
    );
    final directory = await _directoryResolver();
    await _loadIndex(directory);
    final existing = await _loadWorkspaceDocument(directory, identity.id);
    if (existing != null &&
        existing.identity.projectPath != identity.projectPath) {
      throw StateError(
        'Workspace identity collision for ${identity.projectPath}.',
      );
    }
    final workspace = (existing ?? TerminalWorkspace(identity: identity))
        .withIdentity(identity);
    await _persistWorkspaceDocument(directory, workspace);
    return workspace;
  }

  Future<void> activateWorkspace(TerminalWorkspace workspace) async {
    final normalized = workspace.withIdentity(workspace.identity);
    final directory = await _directoryResolver();
    final index = await _loadIndex(directory) ?? const TerminalWorkspaceIndex();
    await _persistWorkspaceDocument(directory, normalized);
    await _activateWorkspace(directory, normalized, index: index);
  }

  Future<List<TerminalWorkspaceRecentEntry>> loadRecent() async {
    final directory = await _directoryResolver();
    final index = await _loadIndex(directory);
    return List.unmodifiable(
      index?.recent ?? const <TerminalWorkspaceRecentEntry>[],
    );
  }

  Future<void> save(TerminalWorkspace workspace) async {
    final normalized = workspace.withIdentity(workspace.identity);
    final directory = await _directoryResolver();
    final index = await _loadIndex(directory) ?? const TerminalWorkspaceIndex();
    await _persistWorkspaceDocument(directory, normalized);
    await _persistLegacyAlias(directory, normalized);
    await _saveIndex(
      directory,
      index.upsert(normalized.identity, openedAtUtcIfMissing: _now().toUtc()),
    );
  }

  Future<TerminalWorkspace?> _loadLegacyWorkspace(Directory directory) async {
    final file = _legacyWorkspaceFile(directory);
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      final document = decodeJsonObject(raw, documentName: 'Workspace layout');
      final workspace = TerminalWorkspace.fromJson(document);
      await save(workspace);
      return workspace;
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = TerminalWorkspace();
      await save(repaired);
      return repaired;
    }
  }

  Future<TerminalWorkspace?> _loadWorkspaceDocument(
    Directory directory,
    String workspaceId,
  ) async {
    final file = _workspaceFile(directory, workspaceId);
    if (!await file.exists()) {
      return null;
    }
    try {
      final raw = await file.readAsString();
      final document = decodeJsonObject(raw, documentName: 'Workspace layout');
      final needsMigration =
          document['schemaVersion'] != currentTerminalWorkspaceSchemaVersion;
      var workspace = TerminalWorkspace.fromJson(document);
      if (workspace.identity.id != workspaceId) {
        throw const FormatException(
          'Workspace document identity does not match its collection key.',
        );
      }
      if (needsMigration) {
        workspace = workspace.withIdentity(
          TerminalWorkspaceIdentity(
            id: workspaceId,
            name: workspace.identity.name,
            projectPath: workspace.identity.projectPath,
          ),
        );
        await _persistWorkspaceDocument(directory, workspace);
      }
      return workspace;
    } on FormatException {
      await quarantineCorruptFile(file);
      return null;
    }
  }

  Future<TerminalWorkspaceIndex?> _loadIndex(Directory directory) async {
    final file = _indexFile(directory);
    if (!await file.exists()) {
      return null;
    }
    try {
      final raw = await file.readAsString();
      return TerminalWorkspaceIndex.fromJson(
        decodeJsonObject(raw, documentName: 'Workspace index'),
      );
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = TerminalWorkspaceIndex();
      await _saveIndex(directory, repaired);
      return repaired;
    }
  }

  Future<void> _activateWorkspace(
    Directory directory,
    TerminalWorkspace workspace, {
    required TerminalWorkspaceIndex index,
  }) async {
    await _persistLegacyAlias(directory, workspace);
    await _saveIndex(
      directory,
      index.markOpened(workspace.identity, openedAtUtc: _now().toUtc()),
    );
  }

  Future<void> _persistWorkspaceDocument(
    Directory directory,
    TerminalWorkspace workspace,
  ) {
    return writeStringAtomically(
      _workspaceFile(directory, workspace.identity.id),
      jsonEncode(workspace.toJson()),
    );
  }

  Future<void> _persistLegacyAlias(
    Directory directory,
    TerminalWorkspace workspace,
  ) {
    return writeStringAtomically(
      _legacyWorkspaceFile(directory),
      jsonEncode(workspace.toJson()),
    );
  }

  Future<void> _saveIndex(Directory directory, TerminalWorkspaceIndex index) {
    return writeStringAtomically(
      _indexFile(directory),
      jsonEncode(index.toJson()),
    );
  }

  File _legacyWorkspaceFile(Directory directory) {
    return File('${directory.path}/ianvs_workspace_layout.json');
  }

  File _indexFile(Directory directory) {
    return File('${directory.path}/ianvs_workspace_index.json');
  }

  File _workspaceFile(Directory directory, String workspaceId) {
    final encodedId = base64Url
        .encode(utf8.encode(workspaceId))
        .replaceAll('=', '');
    if (encodedId.isEmpty || encodedId.length > 180) {
      throw const FormatException('Workspace id is too long to persist.');
    }
    return File('${directory.path}/ianvs_workspaces/workspace-$encodedId.json');
  }
}

String? _normalizedWorkspaceId(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
