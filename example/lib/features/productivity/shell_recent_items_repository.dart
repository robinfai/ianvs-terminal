import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import 'shell_productivity_models.dart';

typedef ShellRecentItemsDirectoryResolver = Future<Directory> Function();

const int shellRecentItemsCurrentSchemaVersion = 1;

final class UnsupportedShellRecentItemsSchemaVersion implements Exception {
  const UnsupportedShellRecentItemsSchemaVersion(this.version);

  final Object? version;

  @override
  String toString() =>
      'Unsupported recent-items schema version: $version; expected '
      '$shellRecentItemsCurrentSchemaVersion.';
}

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
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const UnsupportedShellRecentItemsSchemaVersion(null);
      }
      final document = decoded;
      final version = document['schema_version'];
      if (version != shellRecentItemsCurrentSchemaVersion) {
        throw UnsupportedShellRecentItemsSchemaVersion(version);
      }
      final recentItems = document['recent_items'];
      if (recentItems is! Map<Object?, Object?>) {
        throw const FormatException(
          'Recent items document must contain a recent_items object.',
        );
      }
      return ShellRecentItemsState.fromJson(recentItems);
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = ShellRecentItemsState();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(ShellRecentItemsState state) async {
    final file = await _recentItemsFile();
    await writeStringAtomically(
      file,
      jsonEncode(<String, Object?>{
        'schema_version': shellRecentItemsCurrentSchemaVersion,
        'recent_items': state.toJson(),
      }),
    );
  }

  Future<File> _recentItemsFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_recent_items.json');
  }
}
