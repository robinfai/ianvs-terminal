import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import 'local_workspace_models.dart';

typedef LocalWorkspaceDirectoryResolver = Future<Directory> Function();

class LocalWorkspaceRepository {
  LocalWorkspaceRepository({LocalWorkspaceDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalWorkspaceDirectoryResolver _directoryResolver;

  Future<TerminalWorkspace?> load() async {
    final file = await _workspaceFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      return TerminalWorkspace.fromJson(
        decodeJsonObject(raw, documentName: 'Workspace layout'),
      );
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = TerminalWorkspace();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(TerminalWorkspace workspace) async {
    final file = await _workspaceFile();
    await writeStringAtomically(file, jsonEncode(workspace.toJson()));
  }

  Future<File> _workspaceFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_workspace_layout.json');
  }
}
