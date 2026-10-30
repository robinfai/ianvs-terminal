import 'dart:convert';

import 'package:app/features/recording/recording_replay_search_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  group('RecordingReplaySearchIndex', () {
    test('searches output across event boundaries and strips ANSI escapes', () {
      final index = RecordingReplaySearchIndex(_recording());

      final hits = index.search('HELLO');

      expect(hits, hasLength(1));
      expect(hits.single.offset, const Duration(milliseconds: 2));
      expect(hits.single.preview, contains('hello world'));
      expect(hits.single.preview, isNot(contains('\x1b')));
    });

    test('does not invent visible hits from semantic metadata', () {
      final index = RecordingReplaySearchIndex(_recording());
      expect(index.search('deploy'), isEmpty);
      expect(index.search('prod-server'), isEmpty);
    });

    test('command echo split across events waits for the full match', () {
      const id = 'search-index';
      final recording = TerminalRecording(
        metadata: _recording().metadata,
        events: [
          _recording().events.first,
          TerminalRecordingEvent.ptyOutput(
            sessionId: id,
            sequence: 1,
            monotonicOffset: const Duration(seconds: 1),
            bytes: utf8.encode('echo REP'),
          ),
          TerminalRecordingEvent.ptyOutput(
            sessionId: id,
            sequence: 2,
            monotonicOffset: const Duration(seconds: 2),
            bytes: utf8.encode('LAYQA'),
          ),
          TerminalRecordingEvent.shellSemantic(
            sessionId: id,
            sequence: 3,
            monotonicOffset: const Duration(seconds: 3),
            semanticKind: TerminalRecordingSemanticKind.commandStarted,
            command: 'echo REPLAYQA',
          ),
          TerminalRecordingEvent.ptyOutput(
            sessionId: id,
            sequence: 4,
            monotonicOffset: const Duration(seconds: 4),
            bytes: utf8.encode('\r\nREPLAYQA\r\n'),
          ),
        ],
      );
      final hits = RecordingReplaySearchIndex(recording).search('REPLAYQA');
      expect(hits.map((hit) => hit.offset), [
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
    });

    test('returns no hits for blank or missing queries', () {
      final index = RecordingReplaySearchIndex(_recording());

      expect(index.search('  '), isEmpty);
      expect(index.search('missing'), isEmpty);
    });
  });
}

TerminalRecording _recording() {
  const sessionId = 'search-index';
  return TerminalRecording(
    metadata: TerminalRecordingMetadata(
      sessionId: sessionId,
      createdAtUtc: DateTime.utc(2026, 7, 24),
      inputPolicy: TerminalRecordingInputPolicy.redact,
    ),
    events: <TerminalRecordingEvent>[
      TerminalRecordingEvent.sessionStarted(
        sessionId: sessionId,
        sequence: 0,
        monotonicOffset: Duration.zero,
        terminalEmulation: 'xterm256',
        cols: 80,
        rows: 24,
      ),
      TerminalRecordingEvent.ptyOutput(
        sessionId: sessionId,
        sequence: 1,
        monotonicOffset: const Duration(milliseconds: 1),
        bytes: utf8.encode('hel'),
      ),
      TerminalRecordingEvent.ptyOutput(
        sessionId: sessionId,
        sequence: 2,
        monotonicOffset: const Duration(milliseconds: 2),
        bytes: utf8.encode('\x1b[31mlo\x1b[0m world'),
      ),
      TerminalRecordingEvent.shellSemantic(
        sessionId: sessionId,
        sequence: 3,
        monotonicOffset: const Duration(milliseconds: 3),
        semanticKind: TerminalRecordingSemanticKind.commandStarted,
        command: 'deploy app',
        cwd: '/srv/app',
        hostname: 'prod-server',
        remote: true,
      ),
    ],
  );
}
