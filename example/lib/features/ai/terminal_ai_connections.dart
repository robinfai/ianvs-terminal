import 'dart:async';

import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'ai_models.dart';
import 'terminal_ai_controller.dart';
import 'terminal_ai_runtime.dart';

/// A task's execution target can change, but its accepted submissions retain
/// their original endpoint. Reconnection never invokes an execution method.
class TerminalAiConnections
    implements
        AiTerminalPort,
        AiBlockReader,
        AiSubmissionInspector,
        AiKeyInputInspector,
        AiSourceSubmissionInspector,
        AiConnectionSources {
  TerminalAiConnections({
    required String sessionId,
    required AiTerminalPort terminal,
    required this.requestBlocks,
    this.scopeForSession,
  }) : _sessionId = sessionId,
       _active = terminal {
    _sources[sessionId] = terminal;
    _listen();
  }

  final Map<String, AiTerminalPort> _sources = {};
  final _historySnapshots = <String, Object?>{};
  final _archivedBlocks = <String, List<Map<String, Object?>>>{};
  final Map<String, AiTerminalPort> _actions = {};
  final _keyActions = Map<AiAction, AiTerminalPort>.identity();
  final Map<(String, String), AiSubmissionInspector> _receipts = {};
  final Set<AiCancellation> _executions = {};
  final Map<String, Object?>? Function(String, Map<String, Object?>)
  requestBlocks;
  final CommandOccurrenceScope? Function(String)? scopeForSession;
  String _sessionId;
  AiTerminalPort _active;
  AiTerminalPort get active => _active;
  String get sessionId => _sessionId;
  bool get hasRetainedSources =>
      _sources.length > 1 || _archivedBlocks.isNotEmpty;
  @override
  Set<String> get sourceSessionIds =>
      Set.unmodifiable({..._sources.keys, ..._archivedBlocks.keys});
  final _input = StreamController<void>.broadcast(sync: true);
  StreamSubscription<void>? _subscription;
  bool _disposed = false;
  late final evidence = CommandBlockController(
    request: _requestEvidence,
    maximumBlocks: null, // _requestEvidence bounds each native source below.
    occurrenceScopeForBlock: (block) {
      final source = _source(block.id);
      return source == null ? null : scopeForSession?.call(source.$1);
    },
  );

  void _listen() {
    final endpoint = _active;
    _subscription = endpoint.userInput.listen((_) {
      if (!_disposed && identical(endpoint, _active)) _input.add(null);
    });
  }

  void reconnect({
    required String sessionId,
    required AiTerminalPort terminal,
    CommandBlockController? originalBlocks,
  }) {
    if (_disposed || _sources.containsKey(sessionId)) {
      throw StateError('Connection already attached');
    }
    for (final cancellation in _executions) {
      cancellation.cancel();
    }
    if (!hasRetainedSources && originalBlocks != null) {
      String key(String id) => evidenceId(_sessionId, id);
      evidence.readingStates.addEntries(
        originalBlocks.readingStates.entries.map(
          (e) => MapEntry(key(e.key), e.value),
        ),
      );
      // Recreate the last successful native filter before restoring a possibly
      // invalid draft. Otherwise a saved reader anchor/selection would reopen
      // against unfiltered rows on the new presentation controller.
      for (final id in originalBlocks.filtering) {
        evidence.filter(
          key(id),
          originalBlocks.appliedFilter(id) ??
              originalBlocks.filters[id] ??
              const CommandBlockFilter(),
        );
      }
      evidence.filters.addEntries(
        originalBlocks.filters.entries.map(
          (e) => MapEntry(key(e.key), e.value),
        ),
      );
      evidence.errors.addEntries(
        originalBlocks.errors.entries.map((e) => MapEntry(key(e.key), e.value)),
      );
      evidence.collapsed.addAll(originalBlocks.collapsed.map(key));
      evidence.expandedOutput.addAll(originalBlocks.expandedOutput.map(key));
      evidence.bookmarks.addAll(originalBlocks.bookmarks.map(key));
    }
    unawaited(_subscription?.cancel());
    _sessionId = sessionId;
    _active = terminal;
    _sources[sessionId] = terminal;
    _listen();
    _input.add(null); // revoke any proposal before the new context is inspected
    evidence.refresh();
  }

  @override
  Stream<void> get userInput => _input.stream;
  @override
  Future<AiTerminalContext> readContext() async {
    final endpoint = _active;
    final result = await endpoint.readContext();
    if (!identical(endpoint, _active)) throw const AiFailure('stale_context');
    if (hasRetainedSources) evidence.refresh();
    return result;
  }

  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    if (_disposed || expected.sessionId != _sessionId) {
      throw const AiFailure('stale_context');
    }
    final endpoint = _active;
    if (action.kind == AiActionKind.sendKeys) {
      _keyActions[action] = endpoint;
    } else {
      _actions[action.id] = endpoint;
    }
    _executions.add(cancellation);
    try {
      return await endpoint.execute(action, expected, cancellation);
    } finally {
      _executions.remove(cancellation);
      if (action.kind == AiActionKind.runCommand &&
          endpoint is AiSubmissionInspector) {
        final inspector = endpoint as AiSubmissionInspector;
        final id = inspector.submissionFor(action.id);
        if (id != null) _receipts[(expected.sessionId, id)] = inspector;
      }
    }
  }

  @override
  String? submissionFor(String actionId) {
    final endpoint = _actions[actionId];
    return endpoint is AiSubmissionInspector
        ? (endpoint! as AiSubmissionInspector).submissionFor(actionId)
        : null;
  }

  @override
  AiKeyInputProgress? keyInputProgress(AiAction action) {
    final endpoint = _keyActions[action];
    return endpoint is AiKeyInputInspector
        ? (endpoint! as AiKeyInputInspector).keyInputProgress(action)
        : null;
  }

  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async {
    final matches = _receipts.entries
        .where((entry) => entry.key.$2 == id)
        .toList();
    return matches.length == 1
        ? matches.single.value.inspectSubmission(id)
        : {'submissionId': id, 'outcome': 'unknown'};
  }

  @override
  Future<Map<String, Object?>> inspectSourceSubmission(
    String id,
    String sessionId,
  ) async =>
      await _receipts[(sessionId, id)]?.inspectSubmission(id) ??
      {'submissionId': id, 'outcome': 'unknown'};

  @override
  Future<AiBlockContext> readBlockRange(
    String blockId, {
    required int startLine,
    required int lineCount,
    required AiTerminalContext expected,
  }) {
    if (expected.sessionId != _sessionId || _active is! AiBlockReader) {
      throw const AiFailure('stale_context');
    }
    return (_active as AiBlockReader).readBlockRange(
      blockId,
      startLine: startLine,
      lineCount: lineCount,
      expected: expected,
    );
  }

  Map<String, Object?> exportHistoryView(
    String Function(String) identity,
    CommandBlockController? native,
  ) {
    String remap(String id) {
      final source = _source(id);
      return source == null ? id : evidenceId(identity(source.$1), source.$2);
    }

    return {
      'collapsed': [
        ...evidence.collapsed.map(remap),
        ...?native?.collapsed.map((id) => evidenceId(identity(_sessionId), id)),
      ],
      'expanded': [
        ...evidence.expandedOutput.map(remap),
        ...?native?.expandedOutput.map(
          (id) => evidenceId(identity(_sessionId), id),
        ),
      ],
    };
  }

  void restoreHistoryView(Map<Object?, Object?> view) {
    evidence.collapsed.addAll(
      (view['collapsed'] as List? ?? []).whereType<String>(),
    );
    evidence.expandedOutput.addAll(
      (view['expanded'] as List? ?? []).whereType<String>(),
    );
  }

  /// Native-shaped snapshots retain cells and source coordinates, not Markdown.
  /// Each saved source has a process-independent identity, never a live PTY ID.
  Map<String, Object?> exportHistorySources(String Function(String) identity) {
    final result = <String, Object?>{..._historySnapshots, ..._archivedBlocks};
    for (final source in _sources.keys) {
      final summaries = requestBlocks(source, const {})?['blocks'];
      if (summaries is! List) continue;
      final blocks = <Map<String, Object?>>[];
      for (final summary
          in summaries.take(128).whereType<Map<Object?, Object?>>()) {
        final id = summary['id'];
        if (id is! String) continue;
        final total = summary['totalLines'] as int? ?? 0;
        final offset = (total - 2048).clamp(0, 1 << 30);
        final detail = requestBlocks(source, {
          'id': id,
          'offset': offset,
          'limit': 2048,
        })?['block'];
        if (detail is Map) blocks.add(Map<String, Object?>.from(detail));
      }
      // A cleared/evicted live grid must not erase previously saved output.
      final previous = (result[identity(source)] as List? ?? [])
          .whereType<Map<String, Object?>>();
      final merged = <String, Map<String, Object?>>{
        for (final block in previous)
          if (block['id'] is String) block['id']! as String: block,
        for (final block in blocks) block['id']! as String: block,
      }.values.toList();
      result[identity(source)] = merged
          .skip((merged.length - 128).clamp(0, merged.length))
          .toList();
    }
    _historySnapshots.addAll(result);
    return result;
  }

  void restoreHistorySources(Map<String, Object?> sources) {
    for (final entry in sources.entries) {
      if (!entry.key.startsWith('saved-') ||
          entry.value is! List ||
          _archivedBlocks.containsKey(entry.key)) {
        continue;
      }
      _archivedBlocks[entry.key] = [
        for (final block
            in (entry.value! as List)
                .take(128)
                .whereType<Map<Object?, Object?>>())
          {
            ...Map<String, Object?>.from(block),
            'archiveWasRunning':
                block['archiveWasRunning'] == true || block['running'] == true,
            'running': false,
            'suspended': false,
            'sftpContextId': null,
          },
      ];
    }
    evidence.refresh();
  }

  Map<String, Object?>? _requestSourceBlocks(
    String source,
    Map<String, Object?> query,
  ) {
    final archived = _archivedBlocks[source];
    if (archived == null) return requestBlocks(source, query);
    final id = query['id'];
    if (id == null) return {'blocks': archived, 'alternateScreen': false};
    final block = archived.where((b) => b['id'] == id).firstOrNull;
    if (block == null) return {'missing': true};
    if (query['query'] is String && (query['query']! as String).isNotEmpty) {
      return {'error': 'Filtering archived output is unavailable'};
    }
    final lines = block['lines'] as List? ?? [];
    final base = block['offset'] as int? ?? 0;
    final offset = query['offset'] as int? ?? base;
    final limit = (query['limit'] as int? ?? 256).clamp(1, 2048);
    final sourceLine = query['sourceLine'] as int?;
    final located = sourceLine == null
        ? -1
        : lines.indexWhere(
            (line) => line is Map && (line['index'] as int? ?? 0) >= sourceLine,
          );
    final start = sourceLine == null
        ? (offset - base).clamp(0, lines.length)
        : located < 0
        ? lines.length
        : located;
    final selected = lines.skip(start).take(limit).toList();
    final next = start + selected.length;
    return {
      'block': {
        ...block,
        'lines': selected,
        'offset': base + start,
        'evicted': block['evicted'] == true || base > 0,
        'nextOffset': next < lines.length ? base + next : null,
      },
    };
  }

  static String evidenceId(String sessionId, String blockId) =>
      '$sessionId/$blockId';
  (String, String)? _source(String id) {
    final slash = id.indexOf('/');
    if (slash < 1) return null;
    final session = id.substring(0, slash);
    return sourceSessionIds.contains(session)
        ? (session, id.substring(slash + 1))
        : null;
  }

  Map<String, Object?> _project(String session, Map<String, Object?> block) => {
    ...block,
    'id': evidenceId(session, block['id']! as String),
    'sourceBlockId': block['sourceBlockId'] ?? block['id'],
  };

  Map<String, Object?>? _requestEvidence(Map<String, Object?> query) {
    if (query['id'] case final String id) {
      final source = _source(id);
      if (source == null) return {'missing': true};
      final result = _requestSourceBlocks(source.$1, {
        ...query,
        'id': source.$2,
      });
      final block = result?['block'];
      return block is Map<String, Object?>
          ? {...?result, 'block': _project(source.$1, block)}
          : result;
    }
    final blocks = <Map<String, Object?>>[];
    for (final source in sourceSessionIds) {
      final raw = _requestSourceBlocks(source, const {})?['blocks'];
      if (raw is List) {
        blocks.addAll(
          raw
              .take(128)
              .whereType<Map<String, Object?>>()
              .map((b) => _project(source, b)),
        );
      }
    }
    return {'blocks': blocks, 'alternateScreen': false};
  }

  AiBlockContext evidenceContext(
    CommandBlock block, {
    bool useSnapshot = false,
  }) {
    final source = _source(block.id);
    if (source == null) throw const AiFailure('block_unavailable');
    final detail = useSnapshot
        ? block
        : CommandBlock.fromJson(
                _requestSourceBlocks(source.$1, {
                  'id': source.$2,
                  'offset': (block.totalLines - 160).clamp(0, 1 << 30),
                  'limit': 160,
                })?['block'],
              ) ??
              block;
    return TerminalAiRuntime.contextFromSnapshot(
      detail,
      sessionId: source.$1,
      blockId: source.$2,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final cancellation in _executions) {
      cancellation.cancel();
    }
    unawaited(_subscription?.cancel());
    for (final endpoint in _sources.values.toSet()) {
      endpoint.dispose();
    }
    evidence.dispose();
    unawaited(_input.close());
  }
}
