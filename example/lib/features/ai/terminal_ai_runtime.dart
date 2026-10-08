import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../sessions/session_state.dart';
import 'ai_models.dart';
import 'terminal_ai_controller.dart';

/// Bridges the agent to the existing PTY. It never creates a second shell.
class TerminalAiRuntime
    implements
        AiTerminalPort,
        AiBlockReader,
        AiSubmissionInspector,
        AiKeyInputInspector {
  TerminalAiRuntime({
    required this.sessionId,
    required this.runtime,
    required this.readPane,
    required this.isReadOnly,
  }) {
    _subscription = runtime.inputEvents
        .where((event) => event.sessionId == sessionId)
        .listen((event) {
          if (identical(event.origin, this)) return;
          _manualInputEpoch++;
          _userInput.add(null);
        });
  }
  final String sessionId;
  final TerminalRuntimeController runtime;
  final TerminalPane? Function() readPane;
  final bool Function() isReadOnly;
  final _userInput = StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<TerminalSessionInputEvent> _subscription;
  int _manualInputEpoch = 0;
  int _submission = 0;
  final _submissions = <String, String>{};
  final _keyInputs = Map<AiAction, AiKeyInputProgress>.identity();
  bool _disposed = false;

  @override
  Stream<void> get userInput => _userInput.stream;

  AiBlockContext blockContext(CommandBlock block, {bool useSnapshot = false}) {
    if (useSnapshot) return _blockContext(block);
    // Filters in the block reader do not change the error context sent to AI.
    final raw = runtime.commandBlocks(sessionId, {
      'id': block.id,
      'offset': (block.totalLines - 160).clamp(0, 1 << 30),
      'limit': 160,
    });
    final detail = CommandBlock.fromJson(raw?['block']) ?? block;
    return _blockContext(detail);
  }

  AiBlockContext _blockContext(CommandBlock detail) =>
      contextFromSnapshot(detail, sessionId: sessionId);

  /// Converts retained cells without re-reading, filtering, or joining gaps.
  static AiBlockContext contextFromSnapshot(
    CommandBlock detail, {
    required String sessionId,
    String? blockId,
  }) {
    final first = detail.lines.firstOrNull;
    final ranges = <AiBlockOutputRange>[];
    var start = 0;
    for (var end = 1; end <= detail.lines.length; end++) {
      if (end < detail.lines.length &&
          detail.lines[end].index == detail.lines[end - 1].index + 1) {
        continue;
      }
      final rows = detail.lines.sublist(start, end);
      final text = StringBuffer();
      final offsets = <int>[];
      for (var i = 0; i < rows.length; i++) {
        offsets.add(text.length);
        text.write(rows[i].text);
        if (i < rows.length - 1 && !rows[i].wrapped) text.writeln();
      }
      ranges.add(
        AiBlockOutputRange(
          startLine: rows.first.index,
          endLine: rows.last.index + 1,
          output: text.toString(),
          lineStartOffsets: List.unmodifiable(offsets),
        ),
      );
      start = end;
    }
    return AiBlockContext(
      id: blockId ?? detail.id,
      command: detail.command,
      output: detail.visibleOutput,
      exitCode: detail.exitCode,
      cwd: detail.cwd,
      sourceSessionId: sessionId,
      sourceContextId: detail.contextId ?? 'root',
      sourceLineBase: first?.sourceRow == null
          ? null
          : first!.sourceRow! - first.index,
      running: detail.running,
      totalLines: detail.totalLines,
      outputStartLine: first?.index ?? detail.offset,
      outputEndLine: detail.lines.isEmpty
          ? detail.offset
          : detail.lines.last.index + 1,
      evicted: detail.evicted,
      outputRanges: ranges.length > 1 ? List.unmodifiable(ranges) : const [],
      lineStartOffsets: ranges.length == 1
          ? ranges.single.lineStartOffsets
          : const [],
    );
  }

  @override
  String? submissionFor(String actionId) => _submissions[actionId];

  @override
  AiKeyInputProgress? keyInputProgress(AiAction action) => _keyInputs[action];

  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async =>
      runtime.composerRequest(sessionId, 'composer.receipt', {
        'submissionId': id,
      }) ??
      {'submissionId': id, 'outcome': 'unknown'};

  @override
  Future<AiBlockContext> readBlockRange(
    String blockId, {
    required int startLine,
    required int lineCount,
    required AiTerminalContext expected,
  }) async {
    if (startLine < 0 ||
        startLine > 1 << 30 ||
        lineCount < 1 ||
        lineCount > 500) {
      throw const AiFailure('invalid_range');
    }
    final current = await readContext();
    if (expected.sessionId != sessionId ||
        current.contextId != expected.contextId ||
        current.cwd != expected.cwd) {
      throw const AiFailure('stale_context');
    }
    final response = runtime.commandBlocks(sessionId, {
      'id': blockId,
      'offset': startLine,
      'limit': lineCount,
    });
    final block = CommandBlock.fromJson(response?['block']);
    if (block == null) throw const AiFailure('block_unavailable');
    return _blockContext(block);
  }

  @override
  Future<AiTerminalContext> readContext() async {
    final pane = readPane();
    if (_disposed ||
        pane == null ||
        pane.isExited ||
        !runtime.hasSession(sessionId)) {
      throw const AiFailure('session_unavailable');
    }
    final screen = runtime.liveScreen(sessionId);
    if (screen == null) throw const AiFailure('screen_unavailable');
    final state = runtime.composerRequest(
      sessionId,
      'composer.state',
      const {},
    );
    final blocks = runtime.commandBlocks(sessionId)?['blocks'];
    final last = blocks is List && blocks.isNotEmpty
        ? CommandBlock.fromJson(blocks.last)
        : null;
    final shell = pane.shellIntegration;
    final contextId =
        state?['contextId'] as String? ?? shell.contextId ?? 'root';
    final lease = state?['lease'] as String?;
    final alternate = screen['alternateScreen'] == true;
    final ready = state?['state'] == 'ready' && lease != null && !alternate;
    final cwd = state?['cwd'] as String? ?? shell.currentDirectory ?? '';
    final running = last?.running == true
        ? last!.command
        : shell.runningCommand;
    return AiTerminalContext(
      sessionId: sessionId,
      contextId: contextId,
      targetLabel: pane.title,
      commandNames: {
        if (state?['commandNames'] case final List<Object?> names)
          ...names.whereType<String>(),
      },
      aliases: {
        if (state?['aliases'] case final Map<Object?, Object?> aliases)
          for (final entry in aliases.entries)
            if (entry case MapEntry(
              key: final String name,
              value: final String expansion,
            ))
              name: expansion,
      },
      guard: jsonEncode([
        sessionId,
        contextId,
        cwd,
        state?['state'],
        lease,
        alternate,
        running,
        last?.id,
        shell.commandStartedAt?.toIso8601String(),
        _manualInputEpoch,
      ]),
      readyLease: ready ? lease : null,
      screen: screen['text'] as String? ?? '',
      cwd: cwd,
      shell: state?['dialect'] as String? ?? shell.shell ?? '',
      runningCommand: running,
      lastBlock: last == null ? null : blockContext(last),
      alternateScreen: alternate,
      canRunCommand: ready && !isReadOnly(),
      readOnly: isReadOnly(),
      rows: screen['rows'] as int? ?? 24,
      columns: screen['columns'] as int? ?? 80,
      cursorRow: screen['cursorRow'] as int? ?? 0,
      cursorColumn: screen['cursorColumn'] as int? ?? 0,
    );
  }

  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    if (action.kind == AiActionKind.sendKeys) {
      _keyInputs[action] = AiKeyInputProgress(
        sent: 0,
        total: action.keys.length,
      );
    }
    cancellation.check();
    if (!action.writesInput) throw const AiFailure('invalid_action');
    final current = await readContext();
    cancellation.check();
    if (current.readOnly || runtime.isZmodemTransferActive(sessionId)) {
      throw const AiFailure('read_only');
    }
    if (current.guard != expected.guard) throw const AiFailure('stale_context');
    if (action.kind == AiActionKind.runCommand) {
      if (!current.canRunCommand || current.readyLease == null) {
        throw const AiFailure('shell_not_ready');
      }
      final id = 'ai-${DateTime.now().microsecondsSinceEpoch}-${_submission++}';
      _submissions[action.id] = id;
      final result = runtime.composerRequest(sessionId, 'composer.submit', {
        'lease': current.readyLease,
        'submissionId': id,
        'text': action.command,
      });
      var outcome = result?['outcome'];
      final deadline = DateTime.now().add(const Duration(seconds: 6));
      while (outcome == 'pending' && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        cancellation.check();
        final state = runtime.composerRequest(
          sessionId,
          'composer.state',
          const {},
        );
        if (state?['submissionId'] == id) outcome = state?['outcome'];
      }
      if (outcome != 'accepted') {
        throw AiFailure(
          outcome == 'rejected' ? 'submission_rejected' : 'submission_unknown',
        );
      }
    } else if (action.kind == AiActionKind.sendKeys) {
      for (final stroke in action.keys) {
        cancellation.check();
        final target = await readContext();
        cancellation.check();
        if (target.guard != current.guard) {
          throw const AiFailure('stale_context');
        }
        if (target.readOnly || runtime.isZmodemTransferActive(sessionId)) {
          throw const AiFailure('read_only');
        }
        final screen = runtime.liveScreen(sessionId);
        if (screen == null) throw const AiFailure('screen_unavailable');
        final sent = _keyInputs[action]!.sent;
        _keyInputs[action] = AiKeyInputProgress(
          sent: sent,
          total: action.keys.length,
          writeUncertain: true,
        );
        if (!runtime.trySendInput(
          sessionId,
          Uint8List.fromList(
            utf8.encode(
              stroke.encode(
                applicationCursor: screen['applicationCursor'] == true,
              ),
            ),
          ),
          origin: this,
        )) {
          throw const AiFailure('input_rejected');
        }
        _keyInputs[action] = AiKeyInputProgress(
          sent: sent + 1,
          total: action.keys.length,
        );
        // A lone Esc must expire before the next character. Otherwise TUI
        // decoders such as tcell interpret Esc + ':' as Alt+:, losing the
        // command prompt. Keep checking cancellation between separate writes.
        if (stroke.key == 'ESC') {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }
    }
    // Wait for the PTY to produce a new screen or a command receipt, bounded
    // for long-running TUIs. Output observation never resubmits input.
    var fresh = current;
    var stable = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    do {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      cancellation.check();
      final next = await readContext();
      stable = next.screen == fresh.screen ? stable + 1 : 0;
      fresh = next;
      if (fresh.guard != current.guard && fresh.canRunCommand) break;
      if (stable >= 3 && fresh.alternateScreen) break;
    } while (DateTime.now().isBefore(deadline));
    final id = _submissions[action.id];
    final receipt = id == null ? null : await inspectSubmission(id);
    return {
      'status': 'input_sent',
      'terminal_context': fresh.toJson(),
      'submission_id': ?id,
      if (receipt?['blockId'] != null) 'block_id': receipt!['blockId'],
      'submission_receipt': ?receipt,
      if (_keyInputs[action] case final progress?)
        'input_progress': progress.toJson(action),
    };
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    unawaited(_userInput.close());
  }
}
