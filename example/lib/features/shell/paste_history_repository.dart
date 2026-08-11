import 'dart:convert' show jsonEncode;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import '../persistence/versioned_document.dart';
import '../policies/local_terminal_policy_models.dart';

typedef PasteHistoryDirectoryResolver = Future<Directory> Function();

abstract class PasteHistoryRepositoryPort {
  const PasteHistoryRepositoryPort();

  Future<PasteHistoryDocument?> load();

  Future<void> save(PasteHistoryDocument document);

  Future<VersionedDocument<PasteHistoryDocument?>> loadVersioned() async {
    return VersionedDocument<PasteHistoryDocument?>.local(await load());
  }

  Future<VersionedDocument<PasteHistoryDocument>> saveVersioned(
    VersionedDocument<PasteHistoryDocument> document,
  ) async {
    await save(document.value);
    return document.withRevision(null);
  }

  Future<VersionedDocument<PasteHistoryDocument>> clearDiskHistoryVersioned(
    VersionedDocument<PasteHistoryDocument?> document,
  ) async {
    await clearDiskHistory();
    return const VersionedDocument<PasteHistoryDocument>.local(
      PasteHistoryDocument(),
    );
  }

  Future<void> clearDiskHistory();
}

const int maxPasteHistoryEntries = defaultLocalTerminalPasteHistoryEntries;
const int _maxPersistedPasteHistoryEntriesToScan = maxPasteHistoryEntries * 4;

enum PasteHistoryKind {
  copy,
  paste;

  static PasteHistoryKind fromJsonValue(Object? value) {
    final normalized = value is String ? value.trim().toLowerCase() : null;
    return switch (normalized) {
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
    return {
      'entries': _normalizedEntries(
        entries,
      ).map((entry) => entry.toJson()).toList(),
    };
  }

  String encode() => jsonEncode(toJson());

  static PasteHistoryDocument fromJson(Map<String, Object?> json) {
    return PasteHistoryDocument(
      entries: _normalizedEntries(
        _objectList(
          json['entries'],
          maxEntries: _maxPersistedPasteHistoryEntriesToScan,
        ).map(PasteHistoryEntry.fromJson),
      ),
    );
  }
}

List<PasteHistoryEntry> _normalizedEntries(
  Iterable<PasteHistoryEntry> entries,
) {
  final normalized = <PasteHistoryEntry>[];
  final seenTexts = <String>{};
  for (final entry in entries) {
    final text = entry.text.trimRight();
    if (text.trim().isEmpty || !seenTexts.add(text)) {
      continue;
    }
    normalized.add(
      PasteHistoryEntry(
        text: text,
        kind: entry.kind,
        createdAt: entry.createdAt,
      ),
    );
    if (normalized.length >= maxPasteHistoryEntries) {
      break;
    }
  }
  return normalized;
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

List<Map<Object?, Object?>> _objectList(Object? value, {int? maxEntries}) {
  if (value is! List) {
    return const <Map<Object?, Object?>>[];
  }

  return (maxEntries == null ? value : value.take(maxEntries))
      .map(_objectMap)
      .whereType<Map<Object?, Object?>>()
      .toList(growable: false);
}

String? _stringOrNull(Object? value) {
  return value is String ? value : null;
}

class PasteHistoryRepository extends PasteHistoryRepositoryPort {
  PasteHistoryRepository({PasteHistoryDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final PasteHistoryDirectoryResolver _directoryResolver;

  @override
  Future<PasteHistoryDocument?> load() async {
    final file = await _historyFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      return PasteHistoryDocument.fromJson(
        decodeJsonObject(raw, documentName: 'Paste history'),
      );
    } on FormatException {
      await quarantineCorruptFile(file);
      const repaired = PasteHistoryDocument();
      await save(repaired);
      return repaired;
    }
  }

  @override
  Future<void> save(PasteHistoryDocument document) async {
    final file = await _historyFile();
    await writeStringAtomically(file, document.encode());
  }

  @override
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
}
