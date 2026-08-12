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
      expect(hits.single.offset, const Duration(milliseconds: 1));
      expect(hits.single.preview, contains('hello world'));
      expect(hits.single.preview, isNot(contains('\x1b')));
    });

    test('searches semantic commands at their recorded offset', () {
      final index = RecordingReplaySearchIndex(_recording());

      final hits = index.search('deploy');

      expect(hits, hasLength(1));
      expect(hits.single.offset, const Duration(milliseconds: 3));
      expect(hits.single.preview, contains('deploy app'));
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
