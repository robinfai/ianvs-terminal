import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on Object {
      await _quarantineCorruptFile(file);
      const repaired = TerminalWorkspace();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(TerminalWorkspace workspace) async {
    final file = await _workspaceFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(workspace.toJson()));
  }

  Future<File> _workspaceFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/flutterm_workspace_layout.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
  }
}
