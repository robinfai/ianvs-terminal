import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'shell_productivity_models.dart';

typedef ShellRecentItemsDirectoryResolver = Future<Directory> Function();

class ShellRecentItemsRepository {
  ShellRecentItemsRepository({
    ShellRecentItemsDirectoryResolver? directoryResolver,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final ShellRecentItemsDirectoryResolver _directoryResolver;

  Future<ShellRecentItemsState> load() async {
    final file = await _recentItemsFile();
    if (!await file.exists()) {
      return const ShellRecentItemsState();
    }

    try {
      final raw = await file.readAsString();
      return ShellRecentItemsState.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on Object {
      await _quarantineCorruptFile(file);
      const repaired = ShellRecentItemsState();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(ShellRecentItemsState state) async {
    final file = await _recentItemsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  Future<File> _recentItemsFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/flutterm_recent_items.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
  }
}
