import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import 'local_terminal_visual_models.dart';

const int maxLocalTerminalLayoutTemplates = 100;
const _maxPersistedLayoutTemplateEntriesToScan =
    maxLocalTerminalLayoutTemplates * 4;

typedef LocalTerminalLayoutTemplateDirectoryResolver =
    Future<Directory> Function();

class LocalTerminalLayoutTemplateRepository {
  LocalTerminalLayoutTemplateRepository({
    LocalTerminalLayoutTemplateDirectoryResolver? directoryResolver,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalTerminalLayoutTemplateDirectoryResolver _directoryResolver;

  Future<List<LocalTerminalLayoutTemplate>> load() async {
    final file = await _templatesFile();
    if (!await file.exists()) {
      return const <LocalTerminalLayoutTemplate>[];
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Layout template list must be an array.');
      }
      return _uniqueUsableTemplates(
        decoded
            .take(_maxPersistedLayoutTemplateEntriesToScan)
            .map(_objectMap)
            .whereType<Map<Object?, Object?>>()
            .map(LocalTerminalLayoutTemplate.fromJson),
      );
    } on Object {
      await quarantineCorruptFile(file);
      await save(const <LocalTerminalLayoutTemplate>[]);
      return const <LocalTerminalLayoutTemplate>[];
    }
  }

  Future<void> save(List<LocalTerminalLayoutTemplate> templates) async {
    final file = await _templatesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(
        _uniqueUsableTemplates(
          templates,
        ).map((template) => template.toJson()).toList(growable: false),
      ),
    );
  }

  Future<File> _templatesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_layout_templates.json');
  }

  List<LocalTerminalLayoutTemplate> _uniqueUsableTemplates(
    Iterable<LocalTerminalLayoutTemplate> templates,
  ) {
    final seenIds = <String>{};
    final unique = <LocalTerminalLayoutTemplate>[];
    for (final template in templates) {
      final id = template.id.trim();
      if (!template.canApply || !seenIds.add(id)) {
        continue;
      }
      unique.add(template);
      if (unique.length >= maxLocalTerminalLayoutTemplates) {
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
