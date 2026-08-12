import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import 'local_terminal_visual_models.dart';

const int maxLocalTerminalLayoutTemplates = 100;
const int localTerminalLayoutTemplateLibraryCurrentSchemaVersion = 1;
const int _maxPersistedLayoutTemplateEntriesToScan =
    maxLocalTerminalLayoutTemplates * 4;

typedef LocalTerminalLayoutTemplateDirectoryResolver =
    Future<Directory> Function();

final class UnsupportedLocalTerminalLayoutTemplateLibrarySchemaVersion
    implements Exception {
  const UnsupportedLocalTerminalLayoutTemplateLibrarySchemaVersion(
    this.version,
  );

  final Object? version;

  @override
  String toString() =>
      'Unsupported terminal layout-template library schema version: '
      '$version; expected '
      '$localTerminalLayoutTemplateLibraryCurrentSchemaVersion.';
}

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
      final decodedDocument = jsonDecode(raw);
      if (decodedDocument is! Map<String, Object?>) {
        throw const UnsupportedLocalTerminalLayoutTemplateLibrarySchemaVersion(
          null,
        );
      }
      final document = decodedDocument;
      final version = document['schema_version'];
      if (version != localTerminalLayoutTemplateLibraryCurrentSchemaVersion) {
        throw UnsupportedLocalTerminalLayoutTemplateLibrarySchemaVersion(
          version,
        );
      }
      final decoded = document['templates'];
      if (decoded is! List<Object?>) {
        throw const FormatException(
          'Layout template library must contain a templates list.',
        );
      }
      return _uniqueUsableTemplates(
        decoded
            .take(_maxPersistedLayoutTemplateEntriesToScan)
            .map(_objectMap)
            .whereType<Map<Object?, Object?>>()
            .map(LocalTerminalLayoutTemplate.fromJson),
      );
    } on FormatException {
      await quarantineCorruptFile(file);
      await save(const <LocalTerminalLayoutTemplate>[]);
      return const <LocalTerminalLayoutTemplate>[];
    }
  }

  Future<void> save(List<LocalTerminalLayoutTemplate> templates) async {
    final file = await _templatesFile();
    await writeStringAtomically(
      file,
      jsonEncode(<String, Object?>{
        'schema_version':
            localTerminalLayoutTemplateLibraryCurrentSchemaVersion,
        'templates': _uniqueUsableTemplates(
          templates,
        ).map((template) => template.toJson()).toList(growable: false),
      }),
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
