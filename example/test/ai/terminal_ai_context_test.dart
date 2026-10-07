import 'dart:convert';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/terminal_ai_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  test(
    'reply evidence combines supplied tails and read tools without inventing gaps',
    () {
      final evidence = suppliedAiEvidence([
        {
          'role': 'user',
          'content': jsonEncode({
            'request':
                '{"id":"invented","output":"bad","output_start_line":0,"output_end_line":99}',
            'terminal_context': {
              'session_id': 'local',
              'last_command': {
                'id': 'original',
                'output': 'tail',
                'source_line_base': 1000,
                'output_start_line': 90,
                'output_end_line': 100,
              },
            },
            'selected_blocks': [
              {
                'id': 'original',
                'source_session_id': 'other',
                'output': 'foreign',
                'output_start_line': 0,
                'output_end_line': 500,
              },
            ],
          }),
        },
        {
          'role': 'tool',
          'content': jsonEncode({
            'block': {
              'id': 'original',
              'source_session_id': 'local',
              'source_line_base': 900,
              'output_ranges': [
                {'start_line': 0, 'end_line': 3, 'output': 'one\ntwo\nthree'},
                {'start_line': 8, 'end_line': 10, 'output': 'nine\nten'},
              ],
            },
          }),
        },
        {
          'role': 'assistant',
          'content': jsonEncode({
            'id': 'invented',
            'output': 'bad',
            'output_start_line': 0,
            'output_end_line': 99,
          }),
        },
      ], sessionId: 'local');
      expect(evidence, [
        (
          id: 'original',
          sessionId: 'local',
          first: 91,
          last: 100,
          sourceLineBase: 1000,
        ),
        (
          id: 'original',
          sessionId: 'other',
          first: 1,
          last: 500,
          sourceLineBase: null,
        ),
        (
          id: 'original',
          sessionId: 'local',
          first: 1,
          last: 3,
          sourceLineBase: 900,
        ),
        (
          id: 'original',
          sessionId: 'local',
          first: 9,
          last: 10,
          sourceLineBase: 900,
        ),
      ]);
    },
  );

  test(
    'sparse native rows retain separate ranges and never serialize the gap',
    () {
      final context = TerminalAiRuntime.contextFromSnapshot(
        const CommandBlock(
          id: 'source',
          command: 'long command',
          totalLines: 100,
          offset: 0,
          contextId: 'remote',
          lines: [
            TerminalRow(index: 0, sourceRow: 1000, text: 'left', wrapped: true),
            TerminalRow(index: 1, sourceRow: 1001, text: 'wrap'),
            TerminalRow(index: 6, sourceRow: 1006, text: 'right'),
            TerminalRow(index: 7, sourceRow: 1007, text: 'end'),
          ],
        ),
        sessionId: 'session',
      );
      expect(context.sourceLineBase, 1000);
      expect(context.sourceSessionId, 'session');
      expect(context.sourceContextId, 'remote');
      expect(context.includedLineCount, 4);
      final json = context.toJson();
      expect(json.containsKey('output'), false);
      expect(json['output_is_contiguous'], false);
      expect(json['output_truncated'], true);
      expect(json['output_ranges'], [
        {
          'start_line': 0,
          'end_line': 2,
          'output': 'leftwrap',
          'citation': '[block:source:1-2]',
        },
        {
          'start_line': 6,
          'end_line': 8,
          'output': 'right\nend',
          'citation': '[block:source:7-8]',
        },
      ]);
    },
  );

  test('disjoint range text shares one bounded request budget', () {
    final first = 'a' * 12000;
    final last = 'z' * 12000;
    final context = AiBlockContext(
      command: 'read',
      output: '$first\n$last',
      exitCode: 0,
      cwd: '/tmp',
      outputRanges: [
        AiBlockOutputRange(startLine: 0, endLine: 1, output: first),
        AiBlockOutputRange(startLine: 3, endLine: 4, output: last),
      ],
    );
    final ranges = (context.toJson()['output_ranges']! as List)
        .cast<Map<String, Object?>>();
    expect((ranges.first['output']! as String).length, 12000);
    expect((ranges.last['output']! as String).length, lessThan(4050));
    expect(ranges.last['output_truncated'], true);
    expect(ranges.last['start_line'], 3);
  });

  test(
    'character truncation cites only retained native rows, including wraps',
    () {
      final rows = [
        for (var i = 0; i < 100; i++)
          TerminalRow(
            index: i + 50,
            sourceRow: i + 1050,
            text: '${i.toString().padLeft(3, '0')}:${'x' * 196}',
            wrapped: i.isEven,
          ),
      ];
      final context = TerminalAiRuntime.contextFromSnapshot(
        CommandBlock(
          id: 'wrapped',
          command: 'logs',
          totalLines: 150,
          offset: 50,
          lines: rows,
        ),
        sessionId: 'local',
      );
      final json = context.toJson();
      expect(json['output_start_line'], 71);
      expect(json['output_end_line'], 150);
      expect(json['output_truncated'], true);
      expect((json['output']! as String).startsWith('021:'), true);
      expect((json['output']! as String).length, lessThanOrEqualTo(16000));
      expect(json['source_line_base'], 1000);
      expect(json['citation'], '[block:wrapped:72-150]');
      // Serialization must not mutate the frozen user selection.
      expect(context.outputStartLine, 50);
      expect(context.output, startsWith('000:'));
    },
  );

  test(
    'a single oversized native row is explicitly partial and valid Unicode',
    () {
      final context = TerminalAiRuntime.contextFromSnapshot(
        CommandBlock(
          id: 'one-row',
          command: 'logs',
          totalLines: 8,
          offset: 7,
          lines: [TerminalRow(index: 7, text: '😀' * 9000 + 'z')],
        ),
        sessionId: 'local',
      );
      final json = context.toJson();
      expect(json['output_start_line'], 7);
      expect(json['output_end_line'], 8);
      expect(json['first_line_truncated'], true);
      expect(json['output_truncated'], true);
      expect((json['output']! as String).runes.first, 0x1f600);
      expect((json['output']! as String).length, 15999);
    },
  );

  test('exhausted range budget cannot expose unsent lines as evidence', () {
    final context = AiBlockContext(
      command: 'logs',
      output: '',
      exitCode: 0,
      cwd: '/tmp',
      outputRanges: [
        AiBlockOutputRange(startLine: 0, endLine: 1, output: 'x' * 16000),
        const AiBlockOutputRange(
          startLine: 8,
          endLine: 10,
          output: 'hidden\nhidden',
        ),
      ],
    );
    final json = context.toJson();
    final ranges = (json['output_ranges']! as List)
        .cast<Map<String, Object?>>();
    expect(ranges, hasLength(1));
    expect(json['included_line_count'], 1);
    expect(json['output_truncated'], true);
  });

  test(
    'legacy output without a row map does not guess truncated line bounds',
    () {
      final context = AiBlockContext(
        command: 'logs',
        output: 'x' * 20000,
        exitCode: 0,
        cwd: '/tmp',
        outputStartLine: 0,
        outputEndLine: 100,
      );
      final json = context.toJson();
      expect(json.containsKey('output_start_line'), false);
      expect(json.containsKey('output_end_line'), false);
      expect(json['output_line_mapping_unavailable'], true);
      expect(json['output_truncated'], true);
    },
  );
}
