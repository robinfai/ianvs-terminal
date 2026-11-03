import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'sampled_recording_library.dart';
import 'sampled_recording_search_models.dart';

/// One bounded result page, up to 128 navigation cursors, and one leased file
/// per scan. Closing/replacing a query cancels work but retains each file claim
/// until its actual worker has finished. Active captures are excluded.
final class RecordingSearchController extends ChangeNotifier {
  RecordingSearchController(
    this.library, {
    this.debounce = const Duration(milliseconds: 250),
  });
  final SampledRecordingLibrary library;
  final Duration debounce;
  static const pageSize = 50;
  RecordingSearchQuery query = const RecordingSearchQuery();
  List<RecordingSearchResult> results = const [];
  List<SampledRecordingEntry> _entries = const [];
  final Set<String> _skipped = {};
  final List<_Cursor> _history = [];
  _Cursor _current = const _Cursor(0, 0);
  _Cursor? _next;
  int pageNumber = 1;
  int scannedFiles = 0;
  bool loading = false;
  String? error;
  String? warning;
  Timer? _timer;
  RecordingFileCancellation? _cancellation;
  int _generation = 0;
  bool _disposed = false;
  int get totalFiles => _entries.length;
  int get skippedFiles => _skipped.length;
  bool get hasNext => _next != null;
  bool get hasPrevious => _history.isNotEmpty;
  bool get canRestart => pageNumber > 1;

  void setQuery(RecordingSearchQuery value) {
    if (_disposed) return;
    _timer?.cancel();
    _cancellation?.cancel();
    final generation = ++_generation;
    query = value;
    results = const [];
    _entries = const [];
    _history.clear();
    _skipped.clear();
    warning = null;
    _current = const _Cursor(0, 0);
    _next = null;
    pageNumber = 1;
    scannedFiles = 0;
    error = null;
    loading = value.hasCriteria;
    notifyListeners();
    if (!value.hasCriteria) return;
    _timer = Timer(debounce, () => unawaited(_start(generation)));
  }

  bool _currentGeneration(int generation) =>
      !_disposed && generation == _generation;

  Future<void> _start(int generation) async {
    try {
      final entries = await library.listRecordings();
      if (!_currentGeneration(generation)) return;
      _entries = entries
          .where(
            (entry) =>
                entry.isReadable && query.includesDate(entry.createdAtUtc),
          )
          .toList(growable: false);
      await _load(generation);
    } on Object catch (failure) {
      if (!_currentGeneration(generation)) return;
      error = failure.toString();
      loading = false;
      notifyListeners();
    }
  }

  void nextPage() {
    if (_disposed || loading || _next == null) return;
    if (_history.length == 128) _history.removeAt(0);
    _history.add(_current);
    _current = _next!;
    pageNumber++;
    unawaited(_load(++_generation));
  }

  void previousPage() {
    if (_disposed || loading || _history.isEmpty) return;
    _current = _history.removeLast();
    pageNumber--;
    unawaited(_load(++_generation));
  }

  void firstPage() {
    if (_disposed || loading) return;
    _current = const _Cursor(0, 0);
    _history.clear();
    pageNumber = 1;
    unawaited(_load(++_generation));
  }

  Future<void> _load(int generation) async {
    if (!_currentGeneration(generation)) return;
    _cancellation?.cancel();
    final token = RecordingFileCancellation();
    _cancellation = token;
    final request = query;
    final entries = _entries;
    var fileIndex = _current.file;
    var cursor = _current.byte;
    final hits = <RecordingSearchResult>[];
    loading = true;
    results = const [];
    error = null;
    notifyListeners();
    try {
      while (fileIndex < entries.length &&
          hits.length < pageSize &&
          _currentGeneration(generation)) {
        final entry = entries[fileIndex];
        SampledOpenedRecording? opened;
        try {
          opened = await library.openRecording(entry.path, cancellation: token);
          while (_currentGeneration(generation) && hits.length < pageSize) {
            final page = await opened.recording.search(
              query: request.text,
              hostname: request.hostname,
              kind: SampledRecordingSearchKind.values.byName(
                request.scope.name,
              ),
              cursor: cursor,
              limit: pageSize - hits.length,
              cancellation: token,
            );
            if (!_currentGeneration(generation)) return;
            hits.addAll(
              page.hits.map(
                (hit) => RecordingSearchResult(
                  path: entry.path,
                  title: entry.displayName,
                  createdAtUtc: entry.createdAtUtc,
                  offset: hit.offset,
                  scope: RecordingSearchScope.values.byName(hit.kind.name),
                  preview: hit.preview,
                  hostname: hit.hostname,
                ),
              ),
            );
            if (page.nextCursor == null) {
              fileIndex++;
              cursor = 0;
              break;
            }
            cursor = page.nextCursor!;
          }
        } on RecordingFileCancelled {
          if (_currentGeneration(generation)) rethrow;
          return;
        } on Object catch (failure) {
          if (!_currentGeneration(generation)) return;
          final message = '${entry.displayName}: $failure';
          warning = message.length > 600
              ? '${message.substring(0, 600)}…'
              : message;
          _skipped.add(entry.path);
          fileIndex++;
          cursor = 0;
        } finally {
          await opened?.close();
        }
        if (_currentGeneration(generation)) {
          scannedFiles = fileIndex;
          notifyListeners();
        }
      }
      if (!_currentGeneration(generation)) return;
      results = List.unmodifiable(hits);
      _next = fileIndex < entries.length ? _Cursor(fileIndex, cursor) : null;
    } on Object catch (failure) {
      if (_currentGeneration(generation)) error = failure.toString();
    } finally {
      if (_currentGeneration(generation)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _cancellation?.cancel();
    super.dispose();
  }
}

final class _Cursor {
  const _Cursor(this.file, this.byte);
  final int file;
  final int byte;
}
