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
  }) : _sessionId = sessionId,
       _active = terminal {
    _sources[sessionId] = terminal;
    _listen();
  }

  final Map<String, AiTerminalPort> _sources = {};
  final Map<String, AiTerminalPort> _actions = {};
  final _keyActions = Map<AiAction, AiTerminalPort>.identity();
  final Map<(String, String), AiSubmissionInspector> _receipts = {};
  final Set<AiCancellation> _executions = {};
  final Map<String, Object?>? Function(String, Map<String, Object?>)
  requestBlocks;
  String _sessionId;
  AiTerminalPort _active;
  AiTerminalPort get active => _active;
  String get sessionId => _sessionId;
  bool get hasRetainedSources => _sources.length > 1;
  @override
  Set<String> get sourceSessionIds => Set.unmodifiable(_sources.keys);
  final _input = StreamController<void>.broadcast(sync: true);
  StreamSubscription<void>? _subscription;
  bool _disposed = false;
  late final evidence = CommandBlockController(
    request: _requestEvidence,
    maximumBlocks: null, // _requestEvidence bounds each native source below.
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

  static String evidenceId(String sessionId, String blockId) =>
      '$sessionId/$blockId';
  (String, String)? _source(String id) {
    final slash = id.indexOf('/');
    if (slash < 1) return null;
    final session = id.substring(0, slash);
    return _sources.containsKey(session)
        ? (session, id.substring(slash + 1))
        : null;
  }

  Map<String, Object?> _project(String session, Map<String, Object?> block) => {
    ...block,
    'id': evidenceId(session, block['id']! as String),
  };

  Map<String, Object?>? _requestEvidence(Map<String, Object?> query) {
    if (query['id'] case final String id) {
      final source = _source(id);
      if (source == null) return {'missing': true};
      final result = requestBlocks(source.$1, {...query, 'id': source.$2});
      final block = result?['block'];
      return block is Map<String, Object?>
          ? {...?result, 'block': _project(source.$1, block)}
          : result;
    }
    final blocks = <Map<String, Object?>>[];
    for (final source in _sources.keys) {
      final raw = requestBlocks(source, const {})?['blocks'];
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
                requestBlocks(source.$1, {
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
