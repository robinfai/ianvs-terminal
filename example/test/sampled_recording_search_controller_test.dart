import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:app/features/recording/sampled_recording_search_controller.dart';
import 'package:app/features/recording/sampled_recording_search_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'support/sampled_recording_files.dart';

class _Files extends SampledTestFiles {
  final documents = <String, List<Map<String, Object?>>>{};
  final requests = <Map<String, Object?>>[];
  final failing = <String>{};
  Completer<void>? oldBarrier;
  bool oldFinished = false;
  bool emptyFirstPage = false;
  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) async {
    if (operation != 'search') {
      return super.run(operation, payload, cancellation: cancellation);
    }
    requests.add(Map.of(payload));
    final id = payload['recording_id']! as String;
    if (failing.contains(id)) {
      throw const FileSystemException('unreadable fixture');
    }
    if (payload['query'] == 'old') {
      await oldBarrier?.future;
      oldFinished = true;
    }
    final cursor = payload['cursor']! as int;
    final matches = (documents[id] ?? [])
        .where(
          (doc) =>
              (doc['preview']! as String).contains(
                payload['query']! as String,
              ) &&
              ((payload['hostname']! as String).isEmpty ||
                  (doc['hostname']! as String).contains(
                    payload['hostname']! as String,
                  )) &&
              (payload['kind'] == 'all' || payload['kind'] == doc['kind']),
        )
        .toList();
    if (cursor == 0 && emptyFirstPage) {
      return {
        'hits': <Object>[],
        'next_cursor': 1,
        'scanned_bytes': 1,
        'total_bytes': matches.length + 2,
      };
    }
    final start = cursor == 0 ? 0 : cursor - 1;
    final selected = matches
        .skip(start)
        .take(payload['limit']! as int)
        .toList();
    final end = start + selected.length;
    return {
      'hits': selected,
      'next_cursor': end < matches.length ? end + 1 : null,
      'scanned_bytes': selected.length,
      'total_bytes': matches.length + 2 < 8 ? 8 : matches.length + 2,
    };
  }
}

Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) fail('Search did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Map<String, Object?> _hit(
  String text, {
  String host = 'nested.example',
  String kind = 'command',
}) => {
  'offset_micros': 3000000,
  'kind': kind,
  'hostname': host,
  'row': kind == 'screen' ? 0 : null,
  'preview': text,
};

void main() {
  late Directory directory;
  late _Files files;
  late SampledRecordingLibrary library;
  late RecordingSearchController search;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sampled-search-controller-',
    );
    files = _Files();
    library = SampledRecordingLibrary(
      files: files,
      directoryResolver: () async => directory,
    );
    search = RecordingSearchController(library, debounce: Duration.zero);
  });
  tearDown(() async {
    search.dispose();
    if (files.oldBarrier?.isCompleted == false) files.oldBarrier!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await directory.delete(recursive: true);
  });
  Future<SampledRecordingEntry> seed(
    String id,
    int day, {
    String state = 'finished',
  }) async {
    final entry = await seedSampledRecording(library, id: id);
    final json = entry.toJson();
    json['created_at_millis'] = DateTime.utc(
      2026,
      9,
      day,
    ).millisecondsSinceEpoch;
    json['state'] = state;
    await File(
      '${directory.path}/entries/$id.json',
    ).writeAsString(jsonEncode(json));
    return entry;
  }

  test(
    'pages across files with bounded results and supports previous and first',
    () async {
      final newer = 'a' * 32;
      final older = 'b' * 32;
      await seed(newer, 27);
      await seed(older, 26);
      files.documents[newer] = List.generate(60, (i) => _hit('find newer $i'));
      files.documents[older] = List.generate(70, (i) => _hit('find older $i'));
      files.emptyFirstPage = true;
      search.setQuery(const RecordingSearchQuery(text: 'find'));
      await _until(() => !search.loading);
      expect(search.results, hasLength(50));
      expect(search.results.first.preview, 'find newer 0');
      search.nextPage();
      await _until(() => !search.loading);
      expect(search.results, hasLength(50));
      expect(search.results.first.preview, 'find newer 50');
      expect(search.results.last.preview, 'find older 39');
      search.nextPage();
      await _until(() => !search.loading);
      expect(search.results, hasLength(30));
      expect(search.hasNext, isFalse);
      search.previousPage();
      await _until(() => !search.loading);
      expect(search.results.first.preview, 'find newer 50');
      search.firstPage();
      await _until(() => !search.loading);
      expect(search.pageNumber, 1);
      expect(search.results.first.preview, 'find newer 0');
    },
  );

  test(
    'filters dates before reads and forwards nested hostname and command scope',
    () async {
      final excluded = 'a' * 32;
      final selected = 'b' * 32;
      final active = 'c' * 32;
      await seed(excluded, 25);
      await seed(selected, 26);
      await seed(active, 26, state: 'capturing');
      files.documents[selected] = [
        _hit('find command'),
        _hit('find screen', kind: 'screen'),
        _hit('find other', host: 'other'),
      ];
      search.setQuery(
        RecordingSearchQuery(
          text: 'find',
          hostname: 'nested',
          scope: RecordingSearchScope.command,
          fromUtc: DateTime.utc(2026, 9, 26),
          untilUtc: DateTime.utc(2026, 9, 27),
        ),
      );
      await _until(() => !search.loading);
      expect(search.totalFiles, 1);
      expect(search.results.single.preview, 'find command');
      expect(files.requests.map((q) => q['recording_id']).toSet(), {selected});
      expect(files.requests.single['hostname'], 'nested');
      expect(files.requests.single['kind'], 'command');
    },
  );

  test('reports unreadable files while returning readable matches', () async {
    final broken = 'a' * 32;
    final readable = 'b' * 32;
    await seed(broken, 27);
    await seed(readable, 26);
    files.failing.add(broken);
    files.documents[readable] = [_hit('find available')];
    search.setQuery(const RecordingSearchQuery(text: 'find'));
    await _until(() => !search.loading);
    expect(search.results.single.preview, 'find available');
    expect(search.skippedFiles, 1);
    expect(search.warning, contains('unreadable fixture'));
  });

  test(
    'replaced query shares the viewer lease and late search cannot publish or permit deletion',
    () async {
      final id = 'a' * 32;
      final entry = await seed(id, 27);
      files.documents[id] = [_hit('old value'), _hit('new value')];
      final viewer = await library.openRecording(entry.path);
      files.oldBarrier = Completer<void>();
      search.setQuery(const RecordingSearchQuery(text: 'old'));
      await _until(() => files.requests.any((q) => q['query'] == 'old'));
      search.setQuery(const RecordingSearchQuery(text: 'new'));
      await _until(() => !search.loading);
      expect(search.results.single.preview, 'new value');
      await viewer.close();
      await expectLater(
        library.deleteRecording(entry.path),
        throwsA(isA<RecordingLibraryBusy>()),
      );
      files.oldBarrier!.complete();
      await _until(() => files.oldFinished);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(search.results.single.preview, 'new value');
      await library.deleteRecording(entry.path);
    },
  );
}
