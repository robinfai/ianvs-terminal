import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_file_collision.dart';
import '../../platform/local_json_file.dart';
import 'local_terminal_visual_models.dart';

const int maxLocalTerminalThemePresets = 100;
const _maxSafeBasenameLength = 120;
const _maxPersistedThemePresetEntriesToScan = maxLocalTerminalThemePresets * 4;

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
      final decoded = decodeJsonArray(raw, documentName: 'Theme preset list');
      return _uniqueUsablePresets(
        decoded
            .take(_maxPersistedThemePresetEntriesToScan)
            .map(_objectMap)
            .whereType<Map<Object?, Object?>>()
            .map(LocalTerminalThemePreset.fromJson),
      );
    } on FormatException {
      await quarantineCorruptFile(file);
      await save(const <LocalTerminalThemePreset>[]);
      return const <LocalTerminalThemePreset>[];
    }
  }

  Future<void> save(List<LocalTerminalThemePreset> presets) async {
    final file = await _themesFile();
    await writeStringAtomically(
      file,
      jsonEncode(
        _uniqueUsablePresets(
          presets,
        ).map((preset) => preset.toJson()).toList(growable: false),
      ),
    );
  }

  Future<File> exportPreset(LocalTerminalThemePreset preset) async {
    final directory = await _directoryResolver();
    await directory.create(recursive: true);
    final safePresetId = _safeBasename(preset.id);
    final file = await nextAvailableFile(
      File('${directory.path}/$safePresetId.ianvs-terminal-theme.json'),
    );
    await writeStringAtomically(file, preset.encode());
    return file;
  }

  Future<File> _themesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_themes.json');
  }

  String _safeBasename(String basename) {
    final safe = basename
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (safe.isEmpty || RegExp(r'^\.+$').hasMatch(safe)) {
      return _fallbackBasename();
    }
    if (safe.length <= _maxSafeBasenameLength) {
      return safe;
    }
    final truncated = safe
        .substring(0, _maxSafeBasenameLength)
        .replaceAll(RegExp(r'[._-]+$'), '');
    if (truncated.isEmpty || RegExp(r'^\.+$').hasMatch(truncated)) {
      return _fallbackBasename();
    }
    return truncated;
  }

  String _fallbackBasename() {
    return 'theme-${DateTime.now().millisecondsSinceEpoch}';
  }

  List<LocalTerminalThemePreset> _uniqueUsablePresets(
    Iterable<LocalTerminalThemePreset> presets,
  ) {
    final seenIds = <String>{};
    final unique = <LocalTerminalThemePreset>[];
    for (final preset in presets) {
      final id = preset.id.trim();
      if (id.isEmpty || preset.name.trim().isEmpty || !seenIds.add(id)) {
        continue;
      }
      unique.add(preset);
      if (unique.length >= maxLocalTerminalThemePresets) {
        break;
      }
    }
    return unique;
  }
}

Map<Object?, Object?>? _objectMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<Object?, Object?>();
  }
  return null;
}
