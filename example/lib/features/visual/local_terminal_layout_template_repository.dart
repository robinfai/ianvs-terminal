import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_terminal_visual_models.dart';

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
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map(
            (item) => LocalTerminalLayoutTemplate.fromJson(
              (item as Map).cast<Object?, Object?>(),
            ),
          )
          .where((template) => template.localOnly)
          .toList(growable: false);
    } on Object {
      await _quarantineCorruptFile(file);
      await save(const <LocalTerminalLayoutTemplate>[]);
      return const <LocalTerminalLayoutTemplate>[];
    }
  }

  Future<void> save(List<LocalTerminalLayoutTemplate> templates) async {
    final file = await _templatesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(
        templates
            .where((template) => template.localOnly)
            .map((template) => template.toJson())
            .toList(growable: false),
      ),
    );
  }

  Future<File> _templatesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_layout_templates.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
  }
}
