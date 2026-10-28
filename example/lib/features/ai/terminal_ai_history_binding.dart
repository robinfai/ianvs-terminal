import 'dart:async';
import 'dart:convert';

import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'terminal_ai_connections.dart';
import 'terminal_ai_controller.dart';
import 'terminal_ai_history_repository.dart';

/// Serializes saves and samples native output even when inference has stopped.
class TerminalAiHistoryBinding {
  TerminalAiHistoryBinding(
    this.controller,
    this.repository, {
    this.nativeBlocks,
  }) {
    controller.addListener(_changed);
    loaded = _load();
    _nativeTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _changed(),
    );
  }
  final TerminalAiController controller;
  final TerminalAiHistoryRepository repository;
  final CommandBlockController? Function()? nativeBlocks;
  late final Future<void> loaded;
  Timer? _timer;
  Timer? _nativeTimer;
  Future<void> _writes = Future.value();
  final _saved = <String, String>{};
  final _previous = <String, Map<String, Object?>>{};
  bool _disposed = false;
  bool _loaded = false;
  bool _saveFailed = false;
  bool _captureFailed = false;
  String? _loadError;
  Map<String, String> _pending = {};

  Future<void> _load() async {
    try {
      final documents = await repository.load();
      if (_disposed) return;
      for (final document in documents) {
        if (document['id'] case final String id) _previous[id] = document;
      }
      final port = controller.terminal;
      if (port is TerminalAiConnections) {
        for (final document in documents) {
          if (document['sources'] is Map) {
            port.restoreHistorySources(
              Map<String, Object?>.from(document['sources']! as Map),
            );
          }
          if (document['nativeView'] case final Map<Object?, Object?> view) {
            port.restoreHistoryView(view);
          }
        }
      }
      controller.restoreHistory(documents);
      _loadError = controller.historyError;
      final initial = _capture();
      for (final document in documents) {
        final id = document['id'];
        if (id is! String) continue;
        final encoded = initial[id];
        if (encoded != null) {
          _saved[id] = encoded;
          _previous[id] = Map<String, Object?>.from(jsonDecode(encoded) as Map);
        }
      }
    } on Object {
      _loadError = 'history_load_failed';
      if (!_disposed) controller.setHistoryError(_loadError);
    } finally {
      _loaded = true;
    }
  }

  void _changed() {
    if (_disposed || !_loaded || _timer != null) return;
    _timer = Timer(const Duration(milliseconds: 250), () {
      _timer = null;
      unawaited(flush());
    });
  }

  Map<String, String> _capture() {
    final port = controller.terminal;
    final sources = port is TerminalAiConnections
        ? port.exportHistorySources(controller.historySourceId)
        : <String, Object?>{};
    final documents = controller.exportHistory(sources);
    final view = port is TerminalAiConnections
        ? port.exportHistoryView(
            controller.historySourceId,
            nativeBlocks?.call(),
          )
        : null;
    // Freeze before any await: teardown may release native sources next.
    return {
      for (final document in documents)
        document['id']! as String: jsonEncode({
          ...document,
          if (view != null)
            'nativeView': {
              for (final entry in view.entries)
                entry.key: (entry.value! as List)
                    .whereType<String>()
                    .where(
                      (id) => (document['sources']! as Map).containsKey(
                        id.split('/').first,
                      ),
                    )
                    .toList(),
            },
        }),
    };
  }

  Future<void> flush({bool requireSaved = false}) {
    _timer?.cancel();
    _timer = null;
    if (!_disposed) {
      try {
        _pending = _capture();
        _captureFailed = false;
      } on Object {
        _captureFailed = true;
        controller.setHistoryError('history_save_failed');
      }
    }
    // Closed sessions can finish/retry their last frozen save without accessing
    // a disposed controller or a replacement native session.
    final encoded = _pending;
    final captureFailed = _captureFailed;
    _writes = _writes.then((_) async {
      var failed = captureFailed;
      for (final entry in encoded.entries) {
        if (_saved[entry.key] == entry.value) continue;
        try {
          final document = Map<String, Object?>.from(
            jsonDecode(entry.value) as Map,
          );
          await repository.save(
            entry.key,
            document,
            previous: _previous[entry.key],
          );
          _previous[entry.key] = document;
          _saved[entry.key] = entry.value;
        } on Object {
          failed = true;
        }
      }
      _saveFailed = failed;
      if (!_disposed) {
        controller.setHistoryError(failed ? 'history_save_failed' : _loadError);
      }
    });
    return _writes.then((_) {
      if (requireSaved && _saveFailed) {
        throw StateError('AI history save failed');
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    controller.removeListener(_changed);
    _nativeTimer?.cancel();
    _timer?.cancel();
    unawaited(flush());
    _disposed = true;
  }
}
