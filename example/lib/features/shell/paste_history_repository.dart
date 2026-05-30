import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef PasteHistoryDirectoryResolver = Future<Directory> Function();

enum PasteHistoryKind {
  copy,
  paste;

  static PasteHistoryKind fromJsonValue(Object? value) {
    return switch (value) {
      'copy' => PasteHistoryKind.copy,
      _ => PasteHistoryKind.paste,
    };
  }
}

class PasteHistoryEntry {
  const PasteHistoryEntry({
    required this.text,
    required this.kind,
    required this.createdAt,
  });

  final String text;
  final PasteHistoryKind kind;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return {
      'text': text,
      'kind': kind.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static PasteHistoryEntry fromJson(Map<Object?, Object?> json) {
    return PasteHistoryEntry(
      text: _stringOrNull(json['text']) ?? '',
      kind: PasteHistoryKind.fromJsonValue(json['kind']),
      createdAt:
          DateTime.tryParse(_stringOrNull(json['createdAt']) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class PasteHistoryDocument {
  const PasteHistoryDocument({this.entries = const []});

  final List<PasteHistoryEntry> entries;

  Map<String, Object?> toJson() {
    return {'entries': entries.map((entry) => entry.toJson()).toList()};
  }

  String encode() => jsonEncode(toJson());

  static PasteHistoryDocument fromJson(Map<String, Object?> json) {
    return PasteHistoryDocument(
      entries: _objectList(json['entries'])
          .map(PasteHistoryEntry.fromJson)
          .where((entry) => entry.text.isNotEmpty)
          .toList(),
    );
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

List<Map<Object?, Object?>> _objectList(Object? value) {
  if (value is! List) {
    return const <Map<Object?, Object?>>[];
  }

  return value
      .map(_objectMap)
      .whereType<Map<Object?, Object?>>()
      .toList(growable: false);
}

String? _stringOrNull(Object? value) {
  return value is String ? value : null;
}

class PasteHistoryRepository {
  PasteHistoryRepository({PasteHistoryDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final PasteHistoryDirectoryResolver _directoryResolver;

  Future<PasteHistoryDocument?> load() async {
    final file = await _historyFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      return PasteHistoryDocument.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on Object {
      await _quarantineCorruptFile(file);
      const repaired = PasteHistoryDocument();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(PasteHistoryDocument document) async {
    final file = await _historyFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(document.encode());
  }

  Future<void> clearDiskHistory() async {
    final file = await _historyFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _historyFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_paste_history.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
  }
}
