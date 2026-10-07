import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_connections.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply;

class _Endpoint extends FakeTerminal implements AiSubmissionInspector {
  _Endpoint(String session) {
    context = AiTerminalContext(
      sessionId: session,
      contextId: 'root',
      guard: '$session:1',
      screen: 'ready',
      cwd: '/srv/app',
      readyLease: '$session-lease',
      canRunCommand: true,
    );
  }
  bool unknown = false;
  bool disconnected = false;
  String outcome = 'accepted';
  int inspections = 0;
  @override
  Future<AiTerminalContext> readContext() async {
    if (disconnected) throw const AiFailure('session_unavailable');
    return context;
  }

  @override
  String? submissionFor(String actionId) => 'same-submission';
  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async {
    inspections++;
    return {
      'outcome': outcome,
      if (outcome == 'accepted') 'blockId': 'same-block',
    };
  }

  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    await super.execute(action, expected, cancellation);
    if (unknown) throw const AiFailure('submission_unknown');
    return {'submission_id': 'same-submission', 'block_id': 'same-block'};
  }
}

void main() {
  Map<String, Object?> blocks(String source, Map<String, Object?> query) {
    final block = <String, Object?>{
      'id': 'same-block',
      'command': 'echo $source',
      'contextId': 'root',
      'totalLines': 1,
      'columns': 80,
      'exitCode': 0,
      'lines': [
        {'index': 0, 'source_row': 20, 'text': '$source evidence'},
      ],
    };
    return query['id'] == null
        ? {
            'blocks': [block],
          }
        : {'block': block};
  }

  test(
    'three connections keep each native history window and original reading state',
    () async {
      final closed = <String>{};
      Map<String, Object?>? history(String source, Map<String, Object?> query) {
        if (closed.contains(source)) return null;
        Map<String, Object?> block(int index) => {
          'id': 'block-$index',
          'command': 'echo $source-$index',
          'contextId': 'root',
          'totalLines': 1,
          'columns': 80,
          'exitCode': 0,
          'lines': [
            {'index': 0, 'source_row': 20, 'text': '$source-$index evidence'},
          ],
        };
        if (query['id'] case final String id) {
          return {'block': block(int.parse(id.substring(6)))};
        }
        // Even a source exceeding its advertised budget is bounded separately,
        // without displacing a previous connection's retained evidence.
        return {
          'blocks': [for (var i = 0; i < 129; i++) block(i)],
        };
      }

      final original =
          CommandBlockController(request: (q) => history('first', q))
            ..refresh()
            ..filter('block-0', const CommandBlockFilter(query: 'evidence'));
      const reading = CommandBlockReadingState(
        lineIndex: 0,
        sourceRow: 20,
        pixelOffset: 4,
        horizontalOffset: 6,
        selection: null,
        selectionSourceBase: 20,
        blockSelection: false,
      );
      original.readingStates['block-0'] = reading;
      original.bookmarks.add('block-0');
      addTearDown(original.dispose);
      final connections = TerminalAiConnections(
        sessionId: 'first',
        terminal: _Endpoint('first'),
        requestBlocks: history,
      );
      addTearDown(connections.dispose);
      connections.reconnect(
        sessionId: 'second',
        terminal: _Endpoint('second'),
        originalBlocks: original,
      );
      connections.reconnect(sessionId: 'third', terminal: _Endpoint('third'));
      final evidence = connections.evidence;
      expect(evidence.blocks, hasLength(384));
      expect(evidence.blocks.map((b) => b.id).toSet(), hasLength(384));
      expect(evidence.readingStates['first/block-0'], same(reading));
      expect(evidence.appliedFilter('first/block-0')?.query, 'evidence');
      expect(evidence.bookmarks, contains('first/block-0'));
      for (final source in ['first', 'second', 'third']) {
        expect(
          await evidence.outputText('$source/block-0'),
          '$source-0 evidence',
        );
      }
      // Explicitly closing one source removes only its native history.
      closed.add('second');
      evidence.refresh();
      expect(evidence.blocks, hasLength(256));
      expect(evidence.readingStates['first/block-0'], same(reading));
      expect(evidence.blocks.any((b) => b.id.startsWith('second/')), false);
    },
  );

  test(
    'reconnect restores the applied source filter independently of its invalid draft',
    () {
      Map<String, Object?> request(String source, Map<String, Object?> query) {
        if (query['query'] == '[') return {'error': 'Invalid pattern'};
        return blocks(source, query);
      }

      final original = CommandBlockController(request: (q) => request('old', q))
        ..refresh()
        ..filter('same-block', const CommandBlockFilter(query: 'evidence'))
        ..filter(
          'same-block',
          const CommandBlockFilter(query: '[', regex: true),
        );
      addTearDown(original.dispose);
      final connections = TerminalAiConnections(
        sessionId: 'old',
        terminal: _Endpoint('old'),
        requestBlocks: request,
      );
      addTearDown(connections.dispose);
      connections.reconnect(
        sessionId: 'new',
        terminal: _Endpoint('new'),
        originalBlocks: original,
      );
      final evidence = connections.evidence;
      expect(evidence.filtering, contains('old/same-block'));
      expect(evidence.appliedFilter('old/same-block')?.query, 'evidence');
      expect(evidence.filters['old/same-block']?.query, '[');
      expect(evidence.errors['old/same-block'], 'Invalid pattern');
    },
  );

  test(
    'reconnect keeps receipt and output ownership even when native IDs collide',
    () async {
      final old = _Endpoint('old');
      final next = _Endpoint('new');
      final connections = TerminalAiConnections(
        sessionId: 'old',
        terminal: old,
        requestBlocks: blocks,
      );
      addTearDown(connections.dispose);
      final action = commandReply('printf original').action!;
      await connections.execute(action, old.context, AiCancellation());
      old.outcome = 'unknown';
      connections.reconnect(sessionId: 'new', terminal: next);
      expect(next.writes, isEmpty);
      expect(await connections.readContext(), next.context);
      await expectLater(
        connections.execute(action, old.context, AiCancellation()),
        throwsA(isA<AiFailure>()),
      );
      expect(next.writes, isEmpty);
      await connections.execute(
        commandReply('printf new', id: 'new-action').action!,
        next.context,
        AiCancellation(),
      );
      expect(
        (await connections.inspectSourceSubmission(
          'same-submission',
          'old',
        ))['outcome'],
        'unknown',
      );
      expect(
        (await connections.inspectSourceSubmission(
          'same-submission',
          'new',
        ))['outcome'],
        'accepted',
      );
      expect(
        (await connections.inspectSubmission('same-submission'))['outcome'],
        'unknown',
        reason:
            'An ambiguous unqualified receipt must not select the new endpoint',
      );
      connections.evidence.refresh();
      expect(connections.evidence.blocks.map((b) => b.id), [
        'old/same-block',
        'new/same-block',
      ]);
      expect(
        await connections.evidence.outputText('old/same-block'),
        'old evidence',
      );
      final context = connections.evidenceContext(
        connections.evidence.blocks.first,
        useSnapshot: true,
      );
      expect(context.id, 'same-block');
      expect(context.sourceSessionId, 'old');
      expect(context.output, 'old evidence');
    },
  );

  test(
    'only current connection input revokes proposals and reconnect cancels in-flight input',
    () async {
      final old = _Endpoint('old')..execution = Completer();
      final next = _Endpoint('new');
      final connections = TerminalAiConnections(
        sessionId: 'old',
        terminal: old,
        requestBlocks: blocks,
      );
      addTearDown(connections.dispose);
      var inputs = 0;
      connections.userInput.listen((_) => inputs++);
      final cancellation = AiCancellation();
      final execution = connections.execute(
        commandReply('sleep 1').action!,
        old.context,
        cancellation,
      );
      await Future<void>.delayed(Duration.zero);
      connections.reconnect(sessionId: 'new', terminal: next);
      expect(cancellation.isCancelled, true);
      expect(inputs, 1);
      old.inputs.add(null);
      expect(inputs, 1);
      next.inputs.add(null);
      expect(inputs, 2);
      old.execution!.complete({'status': 'input_sent'});
      await execution;
      expect(next.writes, isEmpty);
      expect(
        (await connections.inspectSourceSubmission(
          'same-submission',
          'old',
        ))['outcome'],
        'accepted',
      );
    },
  );

  test(
    'unknown old receipt blocks resume after reconnect; explicit target choice preserves task and draft',
    () async {
      final old = _Endpoint('old')
        ..unknown = true
        ..outcome = 'unknown';
      final next = _Endpoint('new');
      final connections = TerminalAiConnections(
        sessionId: 'old',
        terminal: old,
        requestBlocks: blocks,
      );
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      final api = FakeApi();
      final ai = TerminalAiController(
        settings: settings,
        terminal: connections,
        api: api,
      );
      addTearDown(ai.dispose);
      addTearDown(settings.dispose);
      await ai.ask('Inspect the original task without modifying files');
      await ai.approve();
      expect(ai.hasUnresolvedSubmission, true);
      final task = ai.taskId;
      ai.setDraft('Keep my follow-up');
      ai.prepareForConnectionChange();
      connections.reconnect(sessionId: 'new', terminal: next);
      await ai.refreshContext();
      expect(ai.canResume, false);
      expect(next.inspections, 0);
      expect(next.writes, isEmpty);
      expect(api.requests, hasLength(1));
      old.outcome = 'accepted';
      await ai.refreshContext();
      expect(ai.hasUnresolvedSubmission, false);
      expect(ai.targetChanged, true);
      expect(ai.canResume, true);
      await ai.resume();
      expect(ai.error, 'target_changed');
      expect(api.requests, hasLength(1));
      api.respond = (_) async => const AiReply(text: 'Fresh target inspected');
      await ai.resume(
        useCurrentTarget: true,
        expectedTargetGuard: next.context.guard,
      );
      expect(api.requests, hasLength(2));
      final resumed =
          jsonDecode(
                api.requests.last.lastWhere(
                      (m) => m['role'] == 'user',
                    )['content']!
                    as String,
              )
              as Map<String, Object?>;
      expect(
        ((resumed['original_submissions']! as List).single
            as Map)['source_session_id'],
        'old',
      );
      expect(ai.taskId, task);
      expect(ai.draft, 'Keep my follow-up');
      expect(old.writes, hasLength(1));
      expect(next.writes, isEmpty);
      expect(
        ai.transcript
            .singleWhere((e) => e.blockId == 'same-block')
            .target!
            .sessionId,
        'old',
      );
    },
  );
}
