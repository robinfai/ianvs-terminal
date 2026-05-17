import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_terminal_visual_models.dart';

typedef LocalTerminalThemeDirectoryResolver = Future<Directory> Function();

class LocalTerminalThemeRepository {
  LocalTerminalThemeRepository({
    LocalTerminalThemeDirectoryResolver? directoryResolver,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalTerminalThemeDirectoryResolver _directoryResolver;

  Future<List<LocalTerminalThemePreset>> load() async {
    final file = await _themesFile();
    if (!await file.exists()) {
      return const <LocalTerminalThemePreset>[];
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map(
            (item) => LocalTerminalThemePreset.fromJson(
              (item as Map).cast<Object?, Object?>(),
            ),
          )
          .toList(growable: false);
    } on Object {
      await _quarantineCorruptFile(file);
      await save(const <LocalTerminalThemePreset>[]);
      return const <LocalTerminalThemePreset>[];
    }
  }

  Future<void> save(List<LocalTerminalThemePreset> presets) async {
    final file = await _themesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(
        presets.map((preset) => preset.toJson()).toList(growable: false),
      ),
    );
  }

  Future<File> exportPreset(LocalTerminalThemePreset preset) async {
    final directory = await _directoryResolver();
    await directory.create(recursive: true);
    final file = File('${directory.path}/${preset.id}.flutterm-theme.json');
    await file.writeAsString(preset.encode());
    return file;
  }

  Future<File> _themesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/flutterm_themes.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
  }
}
