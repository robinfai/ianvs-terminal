import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
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
        decodeJsonObject(raw, documentName: 'Recent items'),
      );
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = ShellRecentItemsState();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(ShellRecentItemsState state) async {
    final file = await _recentItemsFile();
    await writeStringAtomically(file, jsonEncode(state.toJson()));
  }

  Future<File> _recentItemsFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_recent_items.json');
  }
}
