import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

void main() {
  group('TerminalRecordingCodec', () {
    const codec = TerminalRecordingCodec();

    test('decodes and canonically re-encodes the current fixture', () {
      final source = _fixture('basic_current.ndjson').readAsStringSync();

      final recording = codec.decode(source);

      expect(recording.metadata.schemaVersion, 1);
      expect(recording.metadata.sessionId, 'fixture-session');
      expect(
        recording.metadata.inputPolicy,
        TerminalRecordingInputPolicy.redact,
      );
      expect(
        recording.events.map((event) => event.kind),
        <TerminalRecordingEventKind>[
          TerminalRecordingEventKind.sessionStarted,
          TerminalRecordingEventKind.ptyOutput,
          TerminalRecordingEventKind.userInput,
          TerminalRecordingEventKind.resize,
          TerminalRecordingEventKind.sessionExited,
        ],
      );
      expect(recording.events[1].bytes, utf8.encode('hello\r\n'));
      expect(recording.events[2].bytes, isNull);
      expect(recording.events[2].redactedByteLength, 6);
      expect(codec.encode(recording), source);
    });

    test('round trips recorded input without changing event ordering', () {
      final recording = TerminalRecording(
        metadata: TerminalRecordingMetadata(
          sessionId: 'session-7',
          createdAtUtc: DateTime.utc(2026, 7, 21),
          inputPolicy: TerminalRecordingInputPolicy.record,
        ),
        events: <TerminalRecordingEvent>[
          TerminalRecordingEvent.sessionStarted(
            sessionId: 'session-7',
            sequence: 0,
            monotonicOffset: Duration.zero,
            terminalEmulation: 'xterm256',
            cols: 80,
            rows: 24,
          ),
          TerminalRecordingEvent.ptyOutput(
            sessionId: 'session-7',
            sequence: 1,
            monotonicOffset: const Duration(milliseconds: 1),
            bytes: Uint8List.fromList(<int>[0, 27, 255]),
          ),
          TerminalRecordingEvent.userInput(
            sessionId: 'session-7',
            sequence: 2,
            monotonicOffset: const Duration(milliseconds: 2),
            bytes: Uint8List.fromList(<int>[13]),
          ),
          TerminalRecordingEvent.resize(
            sessionId: 'session-7',
            sequence: 3,
            monotonicOffset: const Duration(milliseconds: 3),
            cols: 120,
            rows: 40,
            pixelWidth: 1200,
            pixelHeight: 800,
            cellWidth: 10,
            cellHeight: 20,
          ),
          TerminalRecordingEvent.sessionExited(
            sessionId: 'session-7',
            sequence: 4,
            monotonicOffset: const Duration(milliseconds: 4),
            exitCode: 0,
          ),
        ],
      );

      final decoded = codec.decode(codec.encode(recording));

      expect(decoded.events.map((event) => event.sequence), <int>[
        0,
        1,
        2,
        3,
        4,
      ]);
      expect(decoded.events[1].bytes, <int>[0, 27, 255]);
      expect(decoded.events[2].bytes, <int>[13]);
    });

    test('ignores additive unknown fields', () {
      final lines = _fixture('basic_current.ndjson')
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map<String, Object?>)
          .toList(growable: false);
      lines.first['future_metadata'] = true;
      lines[1]['future_event'] = <String, Object?>{'enabled': true};
      final source = '${lines.map(jsonEncode).join('\n')}\n';

      final recording = codec.decode(source);

      expect(recording.events, hasLength(5));
      expect(codec.encode(recording), isNot(contains('future_')));
    });

    test('redacted input never serializes sensitive bytes', () {
      final recording = TerminalRecording(
        metadata: TerminalRecordingMetadata(
          sessionId: 'private-session',
          createdAtUtc: DateTime.utc(2026, 7, 21),
          inputPolicy: TerminalRecordingInputPolicy.redact,
        ),
        events: <TerminalRecordingEvent>[
          TerminalRecordingEvent.redactedUserInput(
            sessionId: 'private-session',
            sequence: 0,
            monotonicOffset: Duration.zero,
            byteLength: utf8.encode('secret-value').length,
          ),
        ],
      );

      final encoded = codec.encode(recording);

      expect(encoded, isNot(contains('secret-value')));
      expect(
        encoded,
        isNot(contains(base64Encode(utf8.encode('secret-value')))),
      );
      expect(codec.decode(encoded).events.single.redactedByteLength, 12);
    });

    test('decodes and canonically re-encodes current checkpoints', () {
      final source = _fixture('checkpoint_current.ndjson').readAsStringSync();

      final recording = codec.decode(source);

      expect(recording.metadata.schemaVersion, terminalRecordingSchemaVersion);
      expect(recording.events[2].kind, TerminalRecordingEventKind.checkpoint);
      expect(recording.events[2].checkpointId, 'checkpoint-1');
      expect(recording.events[2].checkpointSourceSequence, 1);
      expect(codec.encode(recording), source);
    });

    test('current graphic assets are content-addressed and deduplicated', () {
      final recording = TerminalRecording(
        metadata: TerminalRecordingMetadata(
          sessionId: 'graphics-session',
          createdAtUtc: DateTime.utc(2026, 7, 21),
          inputPolicy: TerminalRecordingInputPolicy.redact,
        ),
        graphicAssets: <TerminalRecordingGraphicAsset>[
          TerminalRecordingGraphicAsset(
            assetId: 7,
            assetVersion: 1,
            width: 1,
            height: 1,
            rgba: <int>[1, 2, 3, 255],
          ),
          TerminalRecordingGraphicAsset(
            assetId: 8,
            assetVersion: 2,
            width: 1,
            height: 1,
            rgba: <int>[1, 2, 3, 255],
          ),
        ],
        events: <TerminalRecordingEvent>[
          TerminalRecordingEvent.sessionStarted(
            sessionId: 'graphics-session',
            sequence: 0,
            monotonicOffset: Duration.zero,
            terminalEmulation: 'xterm256',
            cols: 80,
            rows: 24,
          ),
        ],
      );

      final encoded = codec.encode(recording);
      final decoded = codec.decode(encoded);

      expect(encoded, _fixture('graphics_current.ndjson').readAsStringSync());
      expect(
        RegExp('"record_type":"graphic_asset_blob"').allMatches(encoded),
        hasLength(1),
      );
      expect(
        RegExp('"record_type":"graphic_asset"').allMatches(encoded),
        hasLength(2),
      );
      expect(encoded, contains('"blob_id":"sha256:'));
      expect(decoded.graphicAssets, hasLength(2));
      expect(decoded.graphicAssets[0].rgba, <int>[1, 2, 3, 255]);
      expect(decoded.graphicAssets[1].rgba, <int>[1, 2, 3, 255]);
      expect(
        identical(decoded.graphicAssets[0].rgba, decoded.graphicAssets[1].rgba),
        isTrue,
      );
      expect(codec.encode(decoded), encoded);
    });

    test('graphic asset bundler preserves the current schema and events', () {
      final source = _fixture('basic_current.ndjson').readAsStringSync();
      final original = codec.decode(source);

      final bundled = const TerminalRecordingGraphicAssetBundler().bundle(
        original,
        graphicAssets: <TerminalRecordingGraphicAsset>[
          TerminalRecordingGraphicAsset(
            assetId: 9,
            assetVersion: 4,
            width: 1,
            height: 1,
            rgba: <int>[4, 3, 2, 255],
          ),
        ],
      );

      expect(bundled.metadata.schemaVersion, terminalRecordingSchemaVersion);
      expect(
        bundled.events.map((event) => event.kind),
        original.events.map((event) => event.kind),
      );
      expect(
        bundled.events,
        everyElement(
          isA<TerminalRecordingEvent>().having(
            (event) => event.schemaVersion,
            'schemaVersion',
            terminalRecordingSchemaVersion,
          ),
        ),
      );
      expect(codec.decode(codec.encode(bundled)).graphicAssets, hasLength(1));
      final checkpointed = const TerminalRecordingCheckpointPlanner(
        playableEventsPerCheckpoint: 2,
      ).addCheckpoints(bundled);
      expect(checkpointed.graphicAssets, hasLength(1));
      expect(
        codec.decode(codec.encode(checkpointed)).graphicAssets,
        hasLength(1),
      );
    });

    test('current recordings stay byte-stable and can contain assets', () {
      final source = _fixture('basic_current.ndjson').readAsStringSync();
      final original = codec.decode(source);
      final sourceRgba = <int>[1, 2, 3, 255];
      final asset = TerminalRecordingGraphicAsset(
        assetId: 1,
        assetVersion: 1,
        width: 1,
        height: 1,
        rgba: sourceRgba,
      );

      sourceRgba[0] = 9;
      expect(codec.encode(original), source);
      expect(asset.rgba, <int>[1, 2, 3, 255]);
      final withAsset = codec.decode(
        codec.encode(
          TerminalRecording(
            metadata: original.metadata,
            graphicAssets: <TerminalRecordingGraphicAsset>[asset],
            events: original.events,
          ),
        ),
      );
      expect(withAsset.graphicAssets, hasLength(1));

      expect(() => asset.rgba[0] = 9, throwsUnsupportedError);
    });

    test('rejects corrupted and missing graphic asset blobs', () {
      final recording = const TerminalRecordingGraphicAssetBundler().bundle(
        codec.decode(_fixture('basic_current.ndjson').readAsStringSync()),
        graphicAssets: <TerminalRecordingGraphicAsset>[
          TerminalRecordingGraphicAsset(
            assetId: 7,
            assetVersion: 1,
            width: 1,
            height: 1,
            rgba: <int>[1, 2, 3, 255],
          ),
        ],
      );
      final records = const LineSplitter()
          .convert(codec.encode(recording))
          .map((line) => jsonDecode(line) as Map<String, Object?>)
          .toList();
      final blob = records.firstWhere(
        (record) => record['record_type'] == 'graphic_asset_blob',
      );
      final reference = records.firstWhere(
        (record) => record['record_type'] == 'graphic_asset',
      );

      blob['rgba_base64'] = base64Encode(<int>[4, 3, 2, 255]);
      expect(
        () => codec.decode('${records.map(jsonEncode).join('\n')}\n'),
        throwsA(
          isA<TerminalRecordingFormatException>().having(
            (error) => error.code,
            'code',
            TerminalRecordingFormatErrorCode.invalidPayload,
          ),
        ),
      );

      blob['rgba_base64'] = base64Encode(<int>[1, 2, 3, 255]);
      reference['blob_id'] = 'sha256:${List.filled(64, '0').join()}';
      expect(
        () => codec.decode('${records.map(jsonEncode).join('\n')}\n'),
        throwsA(
          isA<TerminalRecordingFormatException>().having(
            (error) => error.code,
            'code',
            TerminalRecordingFormatErrorCode.invalidPayload,
          ),
        ),
      );
    });

    test('rejects graphic asset identity count and RGBA size drift', () {
      final original = codec.decode(
        _fixture('basic_current.ndjson').readAsStringSync(),
      );
      expect(
        () => const TerminalRecordingGraphicAssetBundler().bundle(
          original,
          graphicAssets: <TerminalRecordingGraphicAsset>[
            for (
              var id = 1;
              id <= terminalRecordingGraphicAssetMaxCount + 1;
              id += 1
            )
              TerminalRecordingGraphicAsset(
                assetId: id,
                assetVersion: 1,
                width: 1,
                height: 1,
                rgba: <int>[0, 0, 0, 255],
              ),
          ],
        ),
        throwsA(
          isA<TerminalRecordingFormatException>().having(
            (error) => error.code,
            'code',
            TerminalRecordingFormatErrorCode.invalidPayload,
          ),
        ),
      );

      expect(
        () => const TerminalRecordingGraphicAssetBundler().bundle(
          original,
          graphicAssets: <TerminalRecordingGraphicAsset>[
            TerminalRecordingGraphicAsset(
              assetId: 1,
              assetVersion: 1,
              width: 2,
              height: 1,
              rgba: <int>[0, 0, 0, 255],
            ),
          ],
        ),
        throwsA(
          isA<TerminalRecordingFormatException>().having(
            (error) => error.code,
            'code',
            TerminalRecordingFormatErrorCode.invalidPayload,
          ),
        ),
      );
    });

    test('accepts checkpoint events in the only current schema', () {
      final lines = _fixture('basic_current.ndjson').readAsLinesSync();
      final event = jsonDecode(lines[2]) as Map<String, Object?>;
      event['event_kind'] = 'checkpoint';
      event['payload'] = <String, Object?>{
        'checkpoint_id': 'checkpoint-current',
        'source_sequence': 0,
      };
      final source = <String>[
        lines.first,
        lines[1],
        jsonEncode(event),
      ].join('\n');

      final decoded = codec.decode(source);
      expect(decoded.events.last.kind, TerminalRecordingEventKind.checkpoint);
    });

    test('reports unsupported versions with a structured error', () {
      const source =
          '{"record_type":"metadata","schema_version":2,'
          '"session_id":"s","created_at_utc":"2026-07-21T00:00:00.000Z",'
          '"input_policy":"redact"}\n';

      expect(
        () => codec.decode(source),
        throwsA(
          isA<TerminalRecordingFormatException>()
              .having(
                (error) => error.code,
                'code',
                TerminalRecordingFormatErrorCode.unsupportedSchemaVersion,
              )
              .having((error) => error.lineNumber, 'lineNumber', 1),
        ),
      );
    });

    test('merges and round trips shell semantics including nested SSH', () {
      final source = codec.decode(
        _fixture('basic_current.ndjson').readAsStringSync(),
      );
      final enriched = const TerminalRecordingSemanticMerger()
          .merge(source, <TerminalRecordingSemanticEvent>[
            const TerminalRecordingSemanticEvent(
              monotonicOffset: Duration(microseconds: 500),
              kind: TerminalRecordingSemanticKind.remoteSessionStarted,
              command: 'ssh prod-server',
              cwd: '~/project',
            ),
            const TerminalRecordingSemanticEvent(
              monotonicOffset: Duration(microseconds: 1200),
              kind: TerminalRecordingSemanticKind.commandStarted,
              command: 'ls -la',
              cwd: '/srv/app',
              remote: true,
            ),
            const TerminalRecordingSemanticEvent(
              monotonicOffset: Duration(microseconds: 2200),
              kind: TerminalRecordingSemanticKind.commandFinished,
              command: 'ls -la',
              cwd: '/srv/app',
              exitCode: 0,
              remote: true,
            ),
            const TerminalRecordingSemanticEvent(
              monotonicOffset: Duration(microseconds: 3500),
              kind: TerminalRecordingSemanticKind.remoteSessionFinished,
              command: 'ssh prod-server',
              exitCode: 0,
            ),
          ]);

      final decoded = codec.decode(codec.encode(enriched));
      final semantics = decoded.events
          .where(
            (event) => event.kind == TerminalRecordingEventKind.shellSemantic,
          )
          .toList(growable: false);

      expect(decoded.metadata.schemaVersion, terminalRecordingSchemaVersion);
      expect(
        decoded.events.map((event) => event.sequence),
        List<int>.generate(decoded.events.length, (index) => index),
      );
      expect(
        semantics.map((event) => event.semanticKind),
        <TerminalRecordingSemanticKind>[
          TerminalRecordingSemanticKind.remoteSessionStarted,
          TerminalRecordingSemanticKind.commandStarted,
          TerminalRecordingSemanticKind.commandFinished,
          TerminalRecordingSemanticKind.remoteSessionFinished,
        ],
      );
      expect(semantics[1].semanticCommand, 'ls -la');
      expect(semantics[1].semanticCwd, '/srv/app');
      expect(semantics[1].semanticRemote, isTrue);
      expect(semantics[2].semanticExitCode, 0);

      final bundled = const TerminalRecordingGraphicAssetBundler().bundle(
        decoded,
        graphicAssets: <TerminalRecordingGraphicAsset>[
          TerminalRecordingGraphicAsset(
            assetId: 11,
            assetVersion: 1,
            width: 1,
            height: 1,
            rgba: <int>[18, 52, 86, 255],
          ),
        ],
      );
      final bundledDecoded = codec.decode(codec.encode(bundled));
      expect(
        bundledDecoded.metadata.schemaVersion,
        terminalRecordingSchemaVersion,
      );
      expect(bundledDecoded.graphicAssets, hasLength(1));
      expect(
        bundledDecoded.events.where(
          (event) => event.kind == TerminalRecordingEventKind.shellSemantic,
        ),
        hasLength(4),
      );
    });

    test('reports truncated JSON with a structured error', () {
      final source =
          '${_fixture('basic_current.ndjson').readAsLinesSync().first}\n'
          '{"record_type":"event"';

      expect(
        () => codec.decode(source),
        throwsA(
          isA<TerminalRecordingFormatException>()
              .having(
                (error) => error.code,
                'code',
                TerminalRecordingFormatErrorCode.invalidJson,
              )
              .having((error) => error.lineNumber, 'lineNumber', 2),
        ),
      );
    });

    test('rejects missing sequence entries and decreasing timestamps', () {
      final lines = _fixture('basic_current.ndjson').readAsLinesSync();
      final missingSequence = jsonDecode(lines[3]) as Map<String, Object?>;
      missingSequence['sequence'] = 9;
      final missingSequenceSource = <String>[
        ...lines.take(3),
        jsonEncode(missingSequence),
        ...lines.skip(4),
      ].join('\n');

      expect(
        () => codec.decode(missingSequenceSource),
        throwsA(
          isA<TerminalRecordingFormatException>().having(
            (error) => error.code,
            'code',
            TerminalRecordingFormatErrorCode.invalidSequence,
          ),
        ),
      );

      final decreasingOffset = jsonDecode(lines[4]) as Map<String, Object?>;
      decreasingOffset['monotonic_offset_micros'] = 1;
      final decreasingOffsetSource = <String>[
        ...lines.take(4),
        jsonEncode(decreasingOffset),
        ...lines.skip(5),
      ].join('\n');

      expect(
        () => codec.decode(decreasingOffsetSource),
        throwsA(
          isA<TerminalRecordingFormatException>().having(
            (error) => error.code,
            'code',
            TerminalRecordingFormatErrorCode.invalidMonotonicOffset,
          ),
        ),
      );
    });
  });
}

File _fixture(String name) {
  for (final root in <Directory>[
    Directory.current,
    Directory.current.parent,
    Directory.current.parent.parent,
  ]) {
    final file = File(
      '${root.path}/packages/ianvs_terminal_core/test/fixtures/recording/$name',
    );
    if (file.existsSync()) {
      return file;
    }
  }
  throw FileSystemException('Missing recording fixture', name);
}
