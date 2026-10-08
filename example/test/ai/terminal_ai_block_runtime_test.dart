import 'dart:async';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/terminal_ai_runtime.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class _Runtime extends Fake implements TerminalRuntimeController {
  final requests = <Map<String, Object?>>[];
  bool supportSourceLine = true;
  final List<Map<String, Object?>> rows = [
    {'index': 0, 'source_row': 100, 'text': 'PARENT_PREFIX'},
    {'index': 8, 'source_row': 108, 'text': 'PARENT_SUFFIX'},
    {'index': 9, 'source_row': 109, 'text': 'PARENT_END'},
  ];

  @override
  Stream<TerminalSessionInputEvent> get inputEvents => const Stream.empty();
  @override
  bool hasSession(String sessionId) => true;
  @override
  Map<String, Object?>? liveScreen(String sessionId) => {'text': 'shell> '};
  @override
  Map<String, Object?>? composerRequest(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) => {'contextId': 'root', 'cwd': '/tmp', 'state': 'ready', 'lease': 'lease'};

  @override
  Map<String, Object?>? commandBlocks(
    String sessionId, [
    Map<String, Object?> payload = const {},
  ]) {
    if (payload['id'] == null) return {'blocks': <Object?>[]};
    requests.add(payload);
    final offset = supportSourceLine && payload['sourceLine'] != null
        ? rows.indexWhere((row) => row['index'] == payload['sourceLine'])
        : (payload['offset'] as int? ?? 0).clamp(0, rows.length);
    if (offset < 0) return {'error': 'Source line is no longer available'};
    return {
      'block': {
        'id': 'parent',
        'command': 'printf PARENT_PREFIX; zsh; printf PARENT_SUFFIX',
        'cwd': '/tmp',
        'contextId': 'root',
        'exitCode': 0,
        'totalLines': rows.length,
        'sourceLineCount': 10,
        'segmented': true,
        'offset': offset,
        'lines': rows
            .skip(offset)
            .take(payload['limit'] as int? ?? 500)
            .toList(),
      },
    };
  }
}

void main() {
  late _Runtime runtime;
  late TerminalAiRuntime terminal;
  late AiTerminalContext expected;
  setUp(() async {
    runtime = _Runtime();
    terminal = TerminalAiRuntime(
      sessionId: 'one',
      runtime: runtime,
      readPane: () => const TerminalPane(
        sessionId: 'one',
        title: 'Local shell',
        profileId: 'local',
      ),
      isReadOnly: () => false,
    );
    expected = await terminal.readContext();
  });
  tearDown(() => terminal.dispose());

  Future<AiBlockContext> read(int start, int count) => terminal.readBlockRange(
    'parent',
    startLine: start,
    lineCount: count,
    expected: expected,
  );

  test(
    'reads a parent suffix by source line instead of output ordinal',
    () async {
      final block = await read(8, 2);
      expect(runtime.requests.single['sourceLine'], 8);
      expect(block.output, 'PARENT_SUFFIX\nPARENT_END');
      expect(block.sourceLineBase, 100);
      expect(block.totalLines, 10);
      expect(block.toJson()['citation'], '[block:parent:9-10]');
    },
  );

  test(
    'a bounded range never expands across an omitted child output gap',
    () async {
      final prefix = await read(0, 2);
      expect(prefix.output, 'PARENT_PREFIX');
      expect(prefix.outputEndLine, 1);
      final whole = await read(0, 10);
      expect(whole.includedLineCount, 3);
      expect(whole.sourceLineBase, 100);
      expect(
        whole.outputRanges.map((range) => (range.startLine, range.endLine)),
        [(0, 1), (8, 10)],
      );
    },
  );

  test(
    'missing source rows fail without returning an unrelated suffix',
    () async {
      await expectLater(read(1, 2), throwsA(isA<AiFailure>()));
      runtime.supportSourceLine = false;
      // An older backend that silently interprets line 1 as ordinal 1 must
      // never relabel the suffix at line 8 as the requested evidence.
      await expectLater(read(1, 2), throwsA(isA<AiFailure>()));
    },
  );
}
