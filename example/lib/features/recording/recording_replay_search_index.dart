import 'dart:convert';
import 'dart:math' as math;

import 'package:ianvs_terminal/ianvs_terminal.dart';

final class RecordingReplaySearchHit {
  const RecordingReplaySearchHit({required this.offset, required this.preview});

  final Duration offset;
  final String preview;
}

final class RecordingReplaySearchIndex {
  RecordingReplaySearchIndex(TerminalRecording recording)
    : _documents = _buildDocuments(recording);

  final List<_RecordingReplaySearchDocument> _documents;

  List<RecordingReplaySearchHit> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const <RecordingReplaySearchHit>[];
    }
    final hits = <RecordingReplaySearchHit>[];
    for (final document in _documents) {
      final haystack = document.text.toLowerCase();
      var start = haystack.indexOf(needle);
      while (start != -1) {
        hits.add(
          RecordingReplaySearchHit(
            offset: document.offsetForMatch(start),
            preview: _preview(document.text, start, needle.length),
          ),
        );
        start = haystack.indexOf(needle, start + needle.length);
      }
    }
    return List<RecordingReplaySearchHit>.unmodifiable(hits);
  }
}

final class _RecordingReplaySearchDocument {
  const _RecordingReplaySearchDocument({
    required this.text,
    required this.spans,
  });

  final String text;
  final List<_RecordingReplaySearchSpan> spans;

  Duration offsetForMatch(int start) {
    for (final span in spans) {
      if (start < span.end) {
        return span.offset;
      }
    }
    return spans.isEmpty ? Duration.zero : spans.last.offset;
  }
}

final class _RecordingReplaySearchSpan {
  const _RecordingReplaySearchSpan({
    required this.start,
    required this.end,
    required this.offset,
  });

  final int start;
  final int end;
  final Duration offset;
}

List<_RecordingReplaySearchDocument> _buildDocuments(
  TerminalRecording recording,
) {
  final documents = <_RecordingReplaySearchDocument>[];
  final output = StringBuffer();
  final outputSpans = <_RecordingReplaySearchSpan>[];
  for (final event in recording.events) {
    if (event.kind != TerminalRecordingEventKind.ptyOutput ||
        event.bytes == null) {
      continue;
    }
    final text = _searchableOutput(event.bytes!);
    if (text.isEmpty) {
      continue;
    }
    final start = output.length;
    output.write(text);
    outputSpans.add(
      _RecordingReplaySearchSpan(
        start: start,
        end: output.length,
        offset: event.monotonicOffset,
      ),
    );
  }
  if (output.isNotEmpty) {
    documents.add(
      _RecordingReplaySearchDocument(
        text: output.toString(),
        spans: List<_RecordingReplaySearchSpan>.unmodifiable(outputSpans),
      ),
    );
  }
  for (final event in recording.events) {
    if (event.kind != TerminalRecordingEventKind.shellSemantic ||
        event.semanticCommand == null) {
      continue;
    }
    final text = [
      event.semanticCommand,
      event.semanticCwd,
      event.semanticHostname,
    ].whereType<String>().join(' ');
    documents.add(
      _RecordingReplaySearchDocument(
        text: text,
        spans: <_RecordingReplaySearchSpan>[
          _RecordingReplaySearchSpan(
            start: 0,
            end: text.length,
            offset: event.monotonicOffset,
          ),
        ],
      ),
    );
  }
  return List<_RecordingReplaySearchDocument>.unmodifiable(documents);
}

String _searchableOutput(List<int> bytes) {
  return utf8
      .decode(bytes, allowMalformed: true)
      .replaceAll(RegExp(r'\x1B\][^\x07]*(?:\x07|\x1B\\)', multiLine: true), '')
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
}

String _preview(String text, int start, int length) {
  const contextLength = 32;
  final previewStart = math.max(0, start - contextLength);
  final previewEnd = math.min(text.length, start + length + contextLength);
  return text
      .substring(previewStart, previewEnd)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
